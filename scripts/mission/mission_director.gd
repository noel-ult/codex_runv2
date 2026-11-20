class_name MissionDirector
extends Node
## Runs the vertical-slice objective chain:
##   1. COPY & DECODE - copy a packet behind an unaware Hunter, then carry it to the
##      shielded Storage 07 decoder and win Signal Lock to recover lab credentials.
##   2. INFILTRATE - get into Meridian Signal Labs and authenticate at the HunterNet core door.
##   3. BREACH - beat the 3-stage Main Hunter Database hack (Signal Lock -> Firewall Override ->
##      Cipher). A full trace sounds the alarm and locks the terminal for a while.
##      Success reveals the one live uplink relay + its cipher and triggers a HunterNet LOCKDOWN
##      (every Hunter converges, the relay guard doubles, the Codex Release speeds up).
##   4. TRANSMIT - hold the relay for `transmit_duration` while the uplink broadcasts you.
## The mission never references Hunter AI nodes: it talks to the Director through its public
## API / signals (wired in main) and reports positions outward through `signal_reported`.

signal objectives_changed(lines: PackedStringArray, active_index: int)
signal marker_changed(marker_id: StringName, world_position: Vector3, label: String, color: Color, shown: bool)
signal transmission_progress(progress: float, in_range: bool)
signal radio_message(text: String)
signal signal_reported(world_position: Vector3)
signal relay_spoofed(world_position: Vector3)
signal mission_completed(elapsed_seconds: float, captures: int)
signal lockdown_started()
signal mission_reset()
signal suit_extraction_changed(enabled: bool)

const RELAY_SPOOF_SECONDS: float = 24.0
const RELAY_SPOOF_COLOR: Color = Color(0.78, 0.56, 1.0)
const DEMO_UPLOAD_SECONDS: float = 6.0
const CHECKPOINT_PATH: String = "user://mission_checkpoint.cfg"

enum Checkpoint { NONE = -1, PACKET, CREDENTIALS, CORE, CIPHER, COMPLETE }

@export var transmit_duration: float = 50.0
@export var transmit_radius: float = 16.0
@export var trace_alarm_time: float = 6.0
@export var terminal_lockout: float = 20.0
@export var lockdown_release_interval: float = 20.0

var has_suit_packet: bool = false
var has_credentials: bool = false
var inside_core: bool = false
var has_cipher: bool = false
var transmitting: bool = false
var demo_upload: bool = false
var completed: bool = false
var transmit_progress: float = 0.0

var _player: PlayerController
var _codex: CodexSignalSystem
var _compound: FacilityCompound
var _terminal: HackTerminal
var _director: HunterAIDirector
var _stations: Array[UplinkStation] = []
var _genuine: UplinkStation
var _spoof_station: UplinkStation
var _spoof_used: bool = false
var _elapsed: float = 0.0
var _alarm_left: float = 0.0
var _lockout_left: float = 0.0
var _cctv_cooldown: float = 0.0
var _hideout: Hideout
var _restore_lockdown_pending: bool = false
var _saved_step: int = Checkpoint.NONE
var _relay_seed: int
var _release_interval_before_lockdown: float = 30.0


## Picks the genuine relay and wires interactables. Returns the genuine station.
func setup(player: PlayerController, compound: FacilityCompound, stations: Array[UplinkStation], terminal: HackTerminal, director: HunterAIDirector, rng_seed: int) -> UplinkStation:
	_player = player
	_codex = player.get_codex()
	_release_interval_before_lockdown = _codex.release_interval
	_compound = compound
	_stations = stations
	_terminal = terminal
	_director = director
	var checkpoint := ConfigFile.new()
	_relay_seed = rng_seed
	if checkpoint.load(CHECKPOINT_PATH) == OK:
		_relay_seed = int(checkpoint.get_value("mission", "relay_seed", rng_seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = _relay_seed
	_genuine = _stations[rng.randi_range(0, _stations.size() - 1)]
	_genuine.is_genuine = true
	_select_spoof_station()
	for station: UplinkStation in _stations:
		var s: UplinkStation = station
		if s == _spoof_station:
			station.interactable.prompt = "Broadcast a false uplink"
			station.interactable.requirement = _can_spoof_relay
			station.interactable.requirement_hint = "Recover the database cipher to spoof this relay."
		else:
			station.interactable.requirement = func(_actor: Node3D) -> bool: return s.is_genuine and has_cipher and not transmitting and not completed
			station.interactable.requirement_hint = "Dormant relay - you need the uplink cipher from the Hunter database." if s.is_genuine else "This relay cannot carry the Codex."
		station.interactable.completed.connect(_on_station_used)

	_compound.server_door_panel.requirement = func(_actor: Node3D) -> bool: return has_credentials
	_compound.server_door_panel.requirement_hint = "Credentials required - copy a Hunter packet, then decode it at Storage 07"
	_compound.database_terminal.requirement = func(_actor: Node3D) -> bool: return has_credentials and not has_cipher and _lockout_left <= 0.0
	_compound.database_terminal.requirement_hint = "Terminal locked out - wait for the trace to clear"
	_compound.hack_completed.connect(func(label: String, cost: float) -> void: _codex.add_resonance(cost, label))
	_compound.intruder_spotted.connect(_on_cctv_spotted)
	_compound.entered_via_hatch.connect(func() -> void: radio_message.emit("You drop into the loading-bay hall through the roof hatch."))
	_compound.server_door_opened.connect(_on_core_opened)
	_compound.database_terminal_used.connect(_on_database_terminal)
	_director.suit_packet_copied.connect(_on_suit_packet_copied)
	_terminal.session_completed.connect(_on_session_completed)
	_terminal.session_aborted.connect(_on_session_aborted)
	return _genuine


func start() -> void:
	var checkpoint := ConfigFile.new()
	if checkpoint.load(CHECKPOINT_PATH) == OK:
		var legacy_step: int = Checkpoint.CREDENTIALS if checkpoint.get_value("mission", "credentials", false) == true else Checkpoint.NONE
		_saved_step = clampi(int(checkpoint.get_value("mission", "step", legacy_step)), Checkpoint.NONE, Checkpoint.COMPLETE)
	if _saved_step != Checkpoint.NONE:
		if _saved_step >= Checkpoint.CREDENTIALS:
			_unlock_credentials()
			_player.teleport(_hideout.get_checkpoint_position())
		_restore_saved_step()
		_publish()
		if not completed:
			radio_message.emit("Mission checkpoint loaded. Follow the marked objective.")
		return
	_publish()
	radio_message.emit("Copy an unaware Hunter's suit packet from behind. Then move to Storage 07 on the west edge and decode it in shelter for lab access.")


## Main supplies the sheltered world interaction after setup has built the mission.
func bind_decoder(hideout: Hideout) -> void:
	_hideout = hideout
	_hideout.decoder.completed.connect(_on_decoder_used)
	_refresh_decoder()


func save_checkpoint() -> void:
	if demo_upload:
		radio_message.emit("Judging demo progress cannot be saved.")
		return
	var step: int = current_objective()
	if step == Checkpoint.PACKET and not has_suit_packet:
		radio_message.emit("Complete a mission objective before saving.")
		return
	var checkpoint := ConfigFile.new()
	checkpoint.set_value("mission", "step", step)
	checkpoint.set_value("mission", "relay_seed", _relay_seed)
	if checkpoint.save(CHECKPOINT_PATH) != OK:
		radio_message.emit("Checkpoint could not be saved.")
		return
	_saved_step = step
	radio_message.emit("Mission checkpoint saved.")


func _restore_saved_step() -> void:
	has_suit_packet = _saved_step == Checkpoint.PACKET
	suit_extraction_changed.emit(not has_suit_packet and not has_credentials)
	_refresh_decoder()
	if _saved_step >= Checkpoint.CORE:
		inside_core = true
		_compound.server_door.open()
		_compound.server_door_panel.enabled = false
	if _saved_step >= Checkpoint.CIPHER:
		_restore_cipher()
	if _saved_step == Checkpoint.COMPLETE:
		_complete()
	elif has_cipher:
		_restore_lockdown_pending = true


func clear_checkpoint() -> bool:
	if not FileAccess.file_exists(CHECKPOINT_PATH):
		return true
	if DirAccess.remove_absolute(CHECKPOINT_PATH) == OK:
		return true
	radio_message.emit("Couldn't clear the saved checkpoint. The run is still active.")
	return false


func on_runner_captured(_total: int) -> void:
	if completed:
		return
	# Invalidate objectives before closing any modal so no old stage can award progress.
	has_suit_packet = false
	inside_core = false
	has_cipher = false
	_spoof_used = false
	transmitting = false
	transmit_progress = 0.0
	_elapsed = 0.0
	_alarm_left = 0.0
	_lockout_left = 0.0
	_cctv_cooldown = 0.0
	_terminal.reset_session()
	_player.set_carrying_device(false)
	_codex.release_interval = _release_interval_before_lockdown
	_codex.reset_resonance()
	_compound.reset_mission_access()
	for station: UplinkStation in _stations:
		station.reset_mission_state()
	_refresh_spoof_relay()
	_refresh_facility_marker()
	marker_changed.emit(&"uplink", Vector3.ZERO, "", Color.WHITE, false)
	transmission_progress.emit(-1.0, false)
	suit_extraction_changed.emit(not has_credentials)
	_refresh_decoder()
	mission_reset.emit()
	_restore_saved_step()
	_publish()
	if _saved_step >= Checkpoint.CORE or _saved_step == Checkpoint.PACKET:
		radio_message.emit("Captured. Your saved mission objective has been restored.")
	elif has_credentials:
		radio_message.emit("Captured. Back at the Storage 07 checkpoint with your lab credentials. Head for Meridian Signal Labs (NE).")
	else:
		radio_message.emit("Captured. Copy a new Hunter packet and decode it at Storage 07.")


# --- Simulation ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null or completed:
		return
	if _restore_lockdown_pending and NavigationServer3D.map_get_iteration_id(_player.get_world_3d().navigation_map) > 0:
		_restore_lockdown_pending = false
		_start_lockdown()
	_elapsed += delta
	_cctv_cooldown = maxf(_cctv_cooldown - delta, 0.0)
	if _lockout_left > 0.0:
		_lockout_left -= delta
		if _lockout_left <= 0.0:
			radio_message.emit("Database terminal lockout cleared.")
	if _alarm_left > 0.0:
		_alarm_left -= delta
		signal_reported.emit(_player.global_position)
	if transmitting:
		_update_transmission(delta)


# --- Step 1: suit hack -------------------------------------------------------------------------

func _on_suit_packet_copied() -> void:
	if has_suit_packet or has_credentials or completed:
		return
	has_suit_packet = true
	suit_extraction_changed.emit(false)
	_refresh_decoder()
	_publish()
	radio_message.emit("Packet copied. Press Ctrl+S to save. Take it to the HunterNet decoder inside Storage 07, then hold E to hack from shelter.")


func _refresh_decoder() -> void:
	if _hideout == null:
		return
	var pending: bool = has_suit_packet and not has_credentials and not completed
	_hideout.decoder.enabled = pending
	marker_changed.emit(&"decoder", _hideout.get_decoder_marker_position(), "DECODE / STORAGE 07", Color(0.35, 1.0, 0.8), pending)


func _unlock_credentials() -> void:
	has_suit_packet = false
	has_credentials = true
	_player.get_gadgets().add_parts(3)
	var spawn: Transform3D = _player.global_transform
	spawn.origin = _hideout.get_checkpoint_position()
	_player.set_spawn_transform(spawn)
	suit_extraction_changed.emit(false)
	_refresh_decoder()
	_refresh_facility_marker()


func _refresh_facility_marker() -> void:
	marker_changed.emit(&"facility", _compound.get_entrance_position() + Vector3(0.0, 3.0, 0.0), "MERIDIAN LABS", Color(1.0, 0.75, 0.3), has_credentials and not has_cipher)


func _on_decoder_used(interactable: Interactable, actor: Node3D) -> void:
	if actor != _player or _terminal.is_open or not has_suit_packet or has_credentials or completed:
		return
	if _hideout == null or not _hideout.protects_runner(actor) or not interactable.is_available_for(actor):
		return
	var stages: Array[StringName] = [HackTerminal.STAGE_SIGNAL]
	_terminal.open(&"suit", "STORAGE 07  //  SUIT PACKET", stages, 0.9)


# --- Step 2: infiltration -----------------------------------------------------------------------

func _on_core_opened() -> void:
	if not has_credentials or completed:
		return
	inside_core = true
	radio_message.emit("You're in the HunterNet core. Press Ctrl+S to save your progress.")
	_publish()


func _on_cctv_spotted(_position: Vector3) -> void:
	if _cctv_cooldown <= 0.0:
		_cctv_cooldown = 6.0
		radio_message.emit("Facility security has eyes on you - Hunters are being vectored in!")


# --- Step 3: database breach ---------------------------------------------------------------------

func _on_database_terminal(_actor: Node3D) -> void:
	if not has_credentials or has_cipher or completed or _terminal.is_open or _lockout_left > 0.0:
		return
	var stages: Array[StringName] = [HackTerminal.STAGE_SIGNAL, HackTerminal.STAGE_FIREWALL, HackTerminal.STAGE_CIPHER]
	_terminal.open(&"database", "MAIN HUNTER DATABASE", stages, 1.0)


func _on_session_completed(session_id: StringName) -> void:
	match session_id:
		&"suit":
			if not has_suit_packet or has_credentials or _hideout == null or not _hideout.protects_runner(_player):
				return
			_unlock_credentials()
			radio_message.emit("Lab credentials recovered. Head for Meridian Signal Labs (NE).")
			save_checkpoint()
		&"database":
			if not has_credentials or has_cipher or completed:
				return
			_restore_cipher()
			_start_lockdown()
			radio_message.emit("Database breached. Press Ctrl+S to save your progress.")
	_publish()


func _restore_cipher() -> void:
	has_cipher = true
	_player.set_carrying_device(true)
	_genuine.set_revealed()
	_refresh_facility_marker()
	marker_changed.emit(&"uplink", _genuine.get_marker_position(), "UPLINK %s" % _genuine.station_label, Color(0.35, 1.0, 0.5), true)
	_refresh_spoof_relay()


func _on_session_aborted(session_id: StringName, traced: bool) -> void:
	match session_id:
		&"suit":
			radio_message.emit("Decode disconnected. Your copied packet is retained; use the Storage 07 decoder again when ready.")
		&"database":
			if traced:
				_alarm_left = trace_alarm_time
				_lockout_left = terminal_lockout
				radio_message.emit("TRACE COMPLETE - HunterNet has your location! Terminal locked for %d s." % int(terminal_lockout))
			else:
				radio_message.emit("Disconnected from the database. The breach resets - try again when ready.")
	_publish()


func _start_lockdown() -> void:
	_codex.release_interval = lockdown_release_interval
	_director.trigger_lockdown(_compound.get_database_position(), _genuine.global_position + _genuine.global_basis.z * 4.5)
	lockdown_started.emit()
	var message: String = "LOCKDOWN. Live relay: %s. Codex Release every %d s." % [_genuine.station_label, int(lockdown_release_interval)]
	if _spoof_station != null:
		message += " Optional: use %s to divert Hunters for %d s." % [_spoof_station.station_label, int(RELAY_SPOOF_SECONDS)]
	radio_message.emit(message)


# --- Optional relay diversion -------------------------------------------------------------------

func _select_spoof_station() -> void:
	var lab: Vector3 = _compound.get_database_position()
	var shortest_detour: float = INF
	for station: UplinkStation in _stations:
		if station == _genuine:
			continue
		var distance: float = lab.distance_to(station.global_position) + station.global_position.distance_to(_genuine.global_position)
		if distance < shortest_detour:
			shortest_detour = distance
			_spoof_station = station


func _spoof_available() -> bool:
	return has_cipher and not _spoof_used and not transmitting and not completed


func _can_spoof_relay(actor: Node3D) -> bool:
	return actor == _player and _spoof_available() and _player.input_enabled and not _player.is_driving() and not _terminal.is_open


func _refresh_spoof_relay() -> void:
	if _spoof_station == null:
		return
	var available: bool = _spoof_available()
	_spoof_station.set_spoof_available(available)
	var port: Interactable = _spoof_station.interactable
	if _spoof_used:
		port.requirement_hint = "False uplink already used."
	elif has_cipher:
		port.requirement_hint = "Spoof available before starting the real transmission."
	else:
		port.requirement_hint = "Recover the database cipher to spoof this relay."
	marker_changed.emit(&"relay_spoof", _spoof_station.get_marker_position(), "OPTIONAL SPOOF · %s" % _spoof_station.station_label, RELAY_SPOOF_COLOR, available)


func _spoof_relay(interactable: Interactable, actor: Node3D) -> void:
	if not _can_spoof_relay(actor) or not interactable.is_available_for(actor):
		return
	_spoof_used = true
	_spoof_station.broadcast_spoof(RELAY_SPOOF_SECONDS)
	_refresh_spoof_relay()
	var approach: Vector3 = _spoof_station.global_position + _spoof_station.global_basis.z * 4.5
	relay_spoofed.emit(approach)
	radio_message.emit("False uplink sent. Up to two Hunters will follow it for %d s. Move toward %s." % [int(RELAY_SPOOF_SECONDS), _genuine.station_label])


# --- Step 4: transmission ------------------------------------------------------------------------

func _on_station_used(interactable: Interactable, actor: Node3D) -> void:
	if _spoof_station != null and interactable == _spoof_station.interactable:
		_spoof_relay(interactable, actor)
		return
	if interactable != _genuine.interactable or not has_cipher or transmitting or completed:
		return
	_begin_transmission()


func _begin_transmission() -> void:
	transmitting = true
	transmit_progress = 0.0
	_genuine.set_handshake(false)
	_genuine.set_transmission(0.0)
	_refresh_spoof_relay()
	if demo_upload:
		radio_message.emit("Final upload in progress.")
		_publish()
		return
	radio_message.emit("Uplink open! Hold within %d m of the relay for %d s - it broadcasts your position." % [int(transmit_radius), int(transmit_duration)])
	_publish()


func _update_transmission(delta: float) -> void:
	var in_range: bool = _player.global_position.distance_to(_genuine.global_position) <= transmit_radius
	if in_range or demo_upload:
		var duration: float = DEMO_UPLOAD_SECONDS if demo_upload else transmit_duration
		transmit_progress = minf(transmit_progress + delta / duration, 1.0)
	if not demo_upload:
		signal_reported.emit(_player.global_position)
	_genuine.set_transmission(transmit_progress)
	transmission_progress.emit(transmit_progress, in_range or demo_upload)
	if transmit_progress >= 1.0:
		_complete()


func start_demo_upload() -> void:
	if completed or demo_upload:
		return
	demo_upload = true
	_player.input_enabled = false
	_player.teleport(_genuine.to_global(Vector3(0.0, 0.25, 7.0)))
	_player.face_camera_toward(_genuine.global_position)
	_genuine.set_revealed()
	_begin_transmission()


func _complete() -> void:
	transmitting = false
	completed = true
	if _spoof_station != null:
		_spoof_station.stop_spoof()
	_player.input_enabled = false
	transmission_progress.emit(-1.0, true)
	radio_message.emit("TRANSMISSION COMPLETE - the Codex is safe.")
	_publish()
	mission_completed.emit(_elapsed, _player.captures)


func current_objective() -> int:
	if completed:
		return 4
	if has_cipher or demo_upload:
		return 3
	if inside_core:
		return 2
	if has_credentials:
		return 1
	return 0


func _publish() -> void:
	var lines := PackedStringArray()
	var credential_step: String = "Copy a packet from an unaware Hunter's suit port"
	if has_suit_packet:
		credential_step = "Take the copied packet to Storage 07 and decode it in shelter"
	elif has_credentials:
		credential_step = "HunterNet lab credentials decoded"
	lines.append(("[x] " if has_credentials else "[ ] ") + credential_step)
	lines.append(("[x] " if inside_core else "[ ] ") + "Infiltrate Meridian Labs (NE) and enter the HunterNet core")
	lines.append(("[x] " if has_cipher else "[ ] ") + "Breach the Main Hunter Database (3 layers)")
	lines.append(("[x] " if completed else "[ ] ") + ("Transmit at %s" % _genuine.station_label if has_cipher else "Transmit the Codex at the live uplink relay"))
	objectives_changed.emit(lines, current_objective())
