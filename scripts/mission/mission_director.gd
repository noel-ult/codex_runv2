class_name MissionDirector
extends Node
## Runs the vertical-slice objective chain:
##   1. TAP HUNTERNET - sneak behind an unaware Hunter, jack into its suit port and win the
##      Signal Lock hack to steal HunterNet credentials (fail = it wakes up on you).
##   2. INFILTRATE - get into Meridian Signal Labs and authenticate at the HunterNet core door.
##   3. BREACH - beat the 3-stage Main Hunter Database hack (Signal Lock -> Firewall Breaker ->
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
signal mission_completed(elapsed_seconds: float, captures: int)
signal lockdown_started()

@export var transmit_duration: float = 30.0
@export var transmit_radius: float = 16.0
@export var trace_alarm_time: float = 6.0
@export var terminal_lockout: float = 20.0
@export var lockdown_release_interval: float = 20.0

var has_credentials: bool = false
var inside_core: bool = false
var has_cipher: bool = false
var transmitting: bool = false
var completed: bool = false
var transmit_progress: float = 0.0

var _player: PlayerController
var _codex: CodexSignalSystem
var _compound: FacilityCompound
var _terminal: HackTerminal
var _director: HunterAIDirector
var _stations: Array[UplinkStation] = []
var _genuine: UplinkStation
var _elapsed: float = 0.0
var _alarm_left: float = 0.0
var _lockout_left: float = 0.0
var _cctv_cooldown: float = 0.0
var _suit_hunter: int = -1


## Picks the genuine relay and wires interactables. Returns the genuine station.
func setup(player: PlayerController, compound: FacilityCompound, stations: Array[UplinkStation], terminal: HackTerminal, director: HunterAIDirector, rng_seed: int) -> UplinkStation:
	_player = player
	_codex = player.get_codex()
	_compound = compound
	_stations = stations
	_terminal = terminal
	_director = director
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	_genuine = _stations[rng.randi_range(0, _stations.size() - 1)]
	_genuine.is_genuine = true
	for station: UplinkStation in _stations:
		var s: UplinkStation = station
		station.interactable.requirement = func(_actor: Node3D) -> bool: return s.is_genuine and has_cipher and not transmitting and not completed
		station.interactable.requirement_hint = "Dormant relay - you need the uplink cipher from the Hunter database."
		station.interactable.completed.connect(_on_station_used)

	_compound.server_door_panel.requirement = func(_actor: Node3D) -> bool: return has_credentials
	_compound.server_door_panel.requirement_hint = "HunterNet credentials required - hack a Hunter's suit first"
	_compound.database_terminal.requirement = func(_actor: Node3D) -> bool: return has_credentials and not has_cipher and _lockout_left <= 0.0
	_compound.database_terminal.requirement_hint = "Terminal locked out - wait for the trace to clear"
	_compound.hack_completed.connect(func(label: String, cost: float) -> void: _codex.add_resonance(cost, label))
	_compound.intruder_spotted.connect(_on_cctv_spotted)
	_compound.entered_via_hatch.connect(func() -> void: radio_message.emit("You drop into the loading-bay hall through the roof hatch."))
	_compound.server_door_opened.connect(_on_core_opened)
	_compound.database_terminal_used.connect(_on_database_terminal)
	_director.suit_hack_started.connect(_on_suit_hack_started)
	_terminal.session_completed.connect(_on_session_completed)
	_terminal.session_aborted.connect(_on_session_aborted)
	return _genuine


func start() -> void:
	_publish()
	radio_message.emit("The Codex can only escape through the Hunters' own uplink. Steal their credentials first - jack into a Hunter's suit from behind.")


func on_runner_captured(_total: int) -> void:
	if transmitting:
		transmitting = false
		transmit_progress = 0.0
		_genuine.set_transmission(-1.0)
		transmission_progress.emit(-1.0, false)
		radio_message.emit("Uplink dropped. Get back to the relay and restart the transmission.")
	_publish()


# --- Simulation ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null or completed:
		return
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

func _on_suit_hack_started(hunter_id: int) -> void:
	_suit_hunter = hunter_id
	var stages: Array[StringName] = [HackTerminal.STAGE_SIGNAL]
	_terminal.open(&"suit", "HUNTER SUIT PORT  //  CREDENTIAL HANDSHAKE", stages, 0.9)


# --- Step 2: infiltration -----------------------------------------------------------------------

func _on_core_opened() -> void:
	inside_core = true
	radio_message.emit("You're in the HunterNet core. The room is Faraday-shielded - your Release is masked here.")
	_publish()


func _on_cctv_spotted(_position: Vector3) -> void:
	if _cctv_cooldown <= 0.0:
		_cctv_cooldown = 6.0
		radio_message.emit("Facility security has eyes on you - Hunters are being vectored in!")


# --- Step 3: database breach ---------------------------------------------------------------------

func _on_database_terminal(_actor: Node3D) -> void:
	var stages: Array[StringName] = [HackTerminal.STAGE_SIGNAL, HackTerminal.STAGE_FIREWALL, HackTerminal.STAGE_CIPHER]
	_terminal.open(&"database", "MAIN HUNTER DATABASE", stages, 1.15)


func _on_session_completed(session_id: StringName) -> void:
	match session_id:
		&"suit":
			has_credentials = true
			_director.resolve_suit_hack(_suit_hunter, true, _player.global_position)
			radio_message.emit("HunterNet credentials captured. The Hunter never noticed. Head for Meridian Signal Labs (NE).")
			marker_changed.emit(&"facility", _compound.get_entrance_position() + Vector3(0.0, 3.0, 0.0), "MERIDIAN LABS", Color(1.0, 0.75, 0.3), true)
		&"database":
			has_cipher = true
			_player.set_carrying_device(true)
			_genuine.set_revealed()
			marker_changed.emit(&"facility", Vector3.ZERO, "", Color.WHITE, false)
			marker_changed.emit(&"uplink", _genuine.get_marker_position(), "UPLINK %s" % _genuine.station_label, Color(0.35, 1.0, 0.5), true)
			_start_lockdown()
	_publish()


func _on_session_aborted(session_id: StringName, traced: bool) -> void:
	match session_id:
		&"suit":
			_director.resolve_suit_hack(_suit_hunter, false, _player.global_position)
			radio_message.emit("Handshake failed - the Hunter's suit rebooted and it knows you're here!")
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
	radio_message.emit("Cipher extracted: the live relay is %s. HUNTERNET LOCKDOWN - every Hunter is inbound and the Codex is agitated (Release every %d s)." % [_genuine.station_label, int(lockdown_release_interval)])


# --- Step 4: transmission ------------------------------------------------------------------------

func _on_station_used(interactable: Interactable, _actor: Node3D) -> void:
	if interactable != _genuine.interactable:
		return
	transmitting = true
	transmit_progress = 0.0
	_genuine.set_handshake(false)
	_genuine.set_transmission(0.0)
	radio_message.emit("Uplink open! Hold within %d m of the relay for %d s - it broadcasts your position." % [int(transmit_radius), int(transmit_duration)])
	_publish()


func _update_transmission(delta: float) -> void:
	var in_range: bool = _player.global_position.distance_to(_genuine.global_position) <= transmit_radius
	if in_range:
		transmit_progress = minf(transmit_progress + delta / transmit_duration, 1.0)
	signal_reported.emit(_player.global_position)
	_genuine.set_transmission(transmit_progress)
	transmission_progress.emit(transmit_progress, in_range)
	if transmit_progress >= 1.0:
		_complete()


func _complete() -> void:
	transmitting = false
	completed = true
	_player.input_enabled = false
	transmission_progress.emit(-1.0, true)
	radio_message.emit("TRANSMISSION COMPLETE - the Codex is safe.")
	_publish()
	mission_completed.emit(_elapsed, _player.captures)


func current_objective() -> int:
	if completed:
		return 4
	if has_cipher:
		return 3
	if inside_core:
		return 2
	if has_credentials:
		return 1
	return 0


func _publish() -> void:
	var lines := PackedStringArray()
	lines.append(("[x] " if has_credentials else "[ ] ") + "Tap HunterNet: jack into an unaware Hunter's suit port")
	lines.append(("[x] " if inside_core else "[ ] ") + "Infiltrate Meridian Labs (NE) and enter the HunterNet core")
	lines.append(("[x] " if has_cipher else "[ ] ") + "Breach the Main Hunter Database (3 layers)")
	lines.append(("[x] " if completed else "[ ] ") + ("Transmit at %s" % _genuine.station_label if has_cipher else "Transmit the Codex at the live uplink relay"))
	objectives_changed.emit(lines, current_objective())
