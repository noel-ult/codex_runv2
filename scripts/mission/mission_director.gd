class_name MissionDirector
extends Node
## Runs the vertical-slice objective chain:
##   1. Locate the genuine uplink relay. Four identical relays sit on the city edge; only the
##      Hunters know which is real and they periodically sweep it. Shadow a sweep and keep
##      line of sight on the scanning Hunter to confirm the site.
##   2. Break into Meridian Signal Labs and steal the Codex Uplink Key (the Device).
##   3. Carry the Device to the confirmed relay and transmit; survive while the uplink
##      broadcasts your position.
## The mission never references Hunter AI: it consumes Director sweep signals (wired in main)
## and reports positions outward through `signal_reported`.

signal objectives_changed(lines: PackedStringArray, active_index: int)
signal marker_changed(marker_id: StringName, world_position: Vector3, label: String, color: Color, shown: bool)
signal observation_progress(progress: float)
signal transmission_progress(progress: float, in_range: bool)
signal radio_message(text: String)
signal signal_reported(world_position: Vector3)
signal mission_completed(elapsed_seconds: float, captures: int)

@export var observe_distance: float = 45.0
@export var observe_time: float = 2.5
@export var transmit_duration: float = 30.0
@export var transmit_radius: float = 16.0
@export var device_decay_scale: float = 0.6
@export var theft_alarm_time: float = 4.0

var site_revealed: bool = false
var carrying: bool = false
var transmitting: bool = false
var completed: bool = false
var transmit_progress: float = 0.0

var _player: PlayerController
var _codex: CodexSignalSystem
var _compound: FacilityCompound
var _stations: Array[UplinkStation] = []
var _genuine: UplinkStation
var _sweep_scanning: bool = false
var _observe: float = 0.0
var _elapsed: float = 0.0
var _theft_alarm_left: float = 0.0
var _cctv_cooldown: float = 0.0


## Picks the genuine relay and wires interactables. Returns the genuine station.
func setup(player: PlayerController, compound: FacilityCompound, stations: Array[UplinkStation], rng_seed: int) -> UplinkStation:
	_player = player
	_codex = player.get_codex()
	_compound = compound
	_stations = stations
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	_genuine = _stations[rng.randi_range(0, _stations.size() - 1)]
	_genuine.is_genuine = true
	for station: UplinkStation in _stations:
		var s: UplinkStation = station
		station.interactable.requirement = func(_actor: Node3D) -> bool: return s.is_genuine and site_revealed and carrying and not transmitting and not completed
		station.interactable.requirement_hint = "Dormant relay - no carrier signal."
		station.interactable.completed.connect(_on_station_used)

	_compound.hack_completed.connect(func(label: String, cost: float) -> void: _codex.add_resonance(cost, label))
	_compound.database_terminal_used.connect(func(_actor: Node3D) -> void: _on_device_collected())
	_compound.intruder_spotted.connect(_on_cctv_spotted)
	_compound.entered_via_hatch.connect(func() -> void: radio_message.emit("You drop into the vault through the roof hatch."))
	return _genuine


func start() -> void:
	_publish()
	marker_changed.emit(&"facility", _compound.get_entrance_position() + Vector3(0.0, 3.0, 0.0), "MERIDIAN LABS", Color(1.0, 0.75, 0.3), true)
	radio_message.emit("The Codex can only escape through a live uplink relay. The Hunters know which one - watch them.")


# --- Hooks wired by main -----------------------------------------------------------------

func on_site_sweep_dispatched(_site: Vector3) -> void:
	if not site_revealed:
		radio_message.emit("RADIO INTERCEPT: \"Unit, run a sweep on the relay.\" Follow the Hunter that peels off.")


func on_site_sweep_scanning(_site: Vector3, active: bool) -> void:
	_sweep_scanning = active
	_genuine.set_handshake(active and not transmitting)


func on_runner_captured(_total: int) -> void:
	if transmitting:
		transmitting = false
		_genuine.set_transmission(-1.0)
		transmission_progress.emit(-1.0, false)
	if carrying:
		carrying = false
		_player.set_carrying_device(false)
		_codex.decay_scale = 1.0
		radio_message.emit("The Hunters recovered the Uplink Key. It's back in the vault.")
	_publish()


# --- Simulation ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null or completed:
		return
	_elapsed += delta
	_cctv_cooldown = maxf(_cctv_cooldown - delta, 0.0)
	_update_observation(delta)
	if _theft_alarm_left > 0.0:
		_theft_alarm_left -= delta
		signal_reported.emit(_player.global_position)
	if transmitting:
		_update_transmission(delta)


func _update_observation(delta: float) -> void:
	if site_revealed:
		return
	if _sweep_scanning and _can_observe():
		_observe += delta
		observation_progress.emit(clampf(_observe / observe_time, 0.0, 1.0))
		if _observe >= observe_time:
			_reveal_site()
	elif _observe > 0.0:
		_observe = maxf(_observe - delta * 0.25, 0.0)
		observation_progress.emit(-1.0)


func _can_observe() -> bool:
	var eye: Vector3 = _player.get_head_position()
	var target: Vector3 = _genuine.global_position + Vector3(0.0, 2.5, 0.0)
	if eye.distance_to(target) > observe_distance:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target, GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER, [_player.get_rid()])
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.get("collider") as Node
	return collider != null and _genuine.is_ancestor_of(collider)


func _reveal_site() -> void:
	site_revealed = true
	_genuine.set_revealed()
	observation_progress.emit(-1.0)
	radio_message.emit("Handshake decoded - %s is the live uplink relay!" % _genuine.station_label)
	marker_changed.emit(&"uplink", _genuine.get_marker_position(), "UPLINK: %s" % _genuine.station_label, Color(0.35, 1.0, 0.5), true)
	_publish()


func _on_device_collected() -> void:
	carrying = true
	_player.set_carrying_device(true)
	_codex.decay_scale = device_decay_scale
	_theft_alarm_left = theft_alarm_time
	radio_message.emit("Uplink Key secured - silent alarm tripped! The Key hums: Resonance decays slower while you carry it.")
	_publish()


func _on_cctv_spotted(_position: Vector3) -> void:
	if _cctv_cooldown <= 0.0:
		_cctv_cooldown = 6.0
		radio_message.emit("CCTV has eyes on you - Hunters are being vectored in!")


func _on_station_used(interactable: Interactable, _actor: Node3D) -> void:
	if interactable != _genuine.interactable:
		return
	transmitting = true
	transmit_progress = 0.0
	_genuine.set_handshake(false)
	_genuine.set_transmission(0.0)
	radio_message.emit("Uplink open! Stay within %d m of the relay for %d s - it is broadcasting your position." % [int(transmit_radius), int(transmit_duration)])
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


func _publish() -> void:
	var lines := PackedStringArray()
	lines.append(("[x] Uplink relay confirmed: %s" % _genuine.station_label) if site_revealed else "[ ] Find the live uplink relay - shadow a Hunter's site sweep")
	lines.append("[x] Uplink Key secured" if carrying or completed else "[ ] Break into Meridian Signal Labs (NE) and steal the Uplink Key")
	if completed:
		lines.append("[x] Codex transmitted to safety")
	elif transmitting:
		lines.append("[ ] Transmitting... %d%%  (stay within %d m)" % [int(transmit_progress * 100.0), int(transmit_radius)])
	else:
		lines.append("[ ] Carry the Key to the live relay and transmit (hold E)")
	var active: int = 0
	if site_revealed:
		active = 1
	if site_revealed and carrying:
		active = 2
	if completed:
		active = 3
	objectives_changed.emit(lines, active)
	marker_changed.emit(&"facility", _compound.get_entrance_position() + Vector3(0.0, 3.0, 0.0), "MERIDIAN LABS", Color(1.0, 0.75, 0.3), not carrying and not completed)
