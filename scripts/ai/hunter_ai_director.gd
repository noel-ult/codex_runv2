class_name HunterAIDirector
extends Node3D
## Spawns Hunters and coordinates them from Codex signals.
##
## Information flow is strictly one-way: CodexSignalSystem -> (signals) -> Director -> Hunters.
## The Director is handed the CodexSignalSystem by the scene's composition root via
## `bind_codex()`; the Codex system never learns that the Director exists. Other world
## systems (security cameras, the uplink) feed positions in through `report_signal()`.
##
## Priority each decision tick:
##   1. CHASE_DECOY      - each active fake Codex beacon pulls its nearest `decoy_pull_count`
##                         Hunters, unless a Hunter is already right on top of the live signal.
##   2. APEX_PURSUIT     - live coordinates (Ignition / alarm / uplink) are fresh.
##   3. INVESTIGATE_ECHO - lost live signal -> last known position, otherwise the best Residual Echo.
##   4. PATROL           - including periodic sweeps of the guarded uplink site.

signal hunter_state_changed(hunter_id: int, state_name: String)
signal hunter_census_changed(patrolling: int, investigating: int, pursuing: int, decoyed: int)
signal runner_caught()
signal site_sweep_dispatched(site: Vector3)
signal site_sweep_scanning(site: Vector3, active: bool)
## A Codex Release was heard; `responders` hunters were dispatched to `world_position`.
signal release_heard(world_position: Vector3, responders: int)
signal drone_launched(search_position: Vector3)

@export var hunter_scene: PackedScene
@export var hunter_count: int = 4
@export var decision_interval: float = 0.2
@export var live_signal_timeout: float = 1.0
@export var decoy_pull_count: int = 2
## Hunters closer than this to the live signal ignore decoys.
@export var proximity_override_radius: float = 12.0
@export var echo_hearing_radius: float = 90.0
@export var max_investigators_per_echo: int = 2
@export var capture_grace_period: float = 3.0
@export var random_seed: int = 7

@export_group("Seeker Drones")
@export var max_drones: int = 2
@export var drone_cooldown: float = 20.0

@export_group("Site Sweeps")
@export var first_sweep_delay: float = 12.0
@export var sweep_interval: float = 28.0
@export var sweep_scan_duration: float = 9.0

var _hunters: Array[HunterAgent] = []
var _active_decoys: Array[Node3D] = []
var _echoes: Array[ResidualEcho] = []
## echo instance id -> Array[int] of hunter ids that already searched it.
var _investigated: Dictionary = {}
var _live_position: Vector3 = Vector3.ZERO
var _last_live_time: float = -1000.0
var _decision_left: float = 0.0
var _grace_left: float = 0.0
var _census: Vector4i = Vector4i(-1, -1, -1, -1)
var _clock: float = 0.0
var _has_site: bool = false
var _site: Vector3 = Vector3.ZERO
var _sweep_timer: float = 0.0
var _sweeper: HunterAgent
var _drones: Array[SeekerDrone] = []
var _drone_cd: float = 0.0


func bind_codex(codex: CodexSignalSystem) -> void:
	codex.ignition_broadcast.connect(report_signal)
	codex.codex_released.connect(_on_codex_released)
	codex.echo_dropped.connect(_on_echo_dropped)
	codex.decoy_beacon_activated.connect(_on_decoy_activated)
	codex.decoy_beacon_deactivated.connect(_on_decoy_deactivated)


func spawn_hunters(spawn_points: Array[Vector3], patrol_points: Array[Vector3]) -> void:
	if hunter_scene == null:
		push_error("HunterAIDirector: hunter_scene is not assigned.")
		return
	if spawn_points.is_empty():
		push_error("HunterAIDirector: no spawn points supplied.")
		return
	for i: int in hunter_count:
		var hunter := hunter_scene.instantiate() as HunterAgent
		if hunter == null:
			push_error("HunterAIDirector: hunter_scene root must use hunter_agent.gd.")
			return
		hunter.setup(i, patrol_points.duplicate(), random_seed + i * 101)
		add_child(hunter)
		hunter.global_position = spawn_points[i % spawn_points.size()] + Vector3(0.0, 0.2, 0.0)
		hunter.state_changed.connect(_on_hunter_state_changed)
		hunter.investigation_finished.connect(_on_investigation_finished)
		hunter.runner_touched.connect(_on_runner_touched)
		hunter.sweep_scan_started.connect(_on_sweep_scan_started)
		hunter.sweep_finished.connect(_on_sweep_finished)
		hunter.weapon_report.connect(func(_h: HunterAgent, at: Vector3) -> void: report_signal(at))
		_hunters.append(hunter)
	_emit_census()


## Tells the hunters which site they guard. They patrol near it and sweep it periodically.
func set_guarded_site(site: Vector3, nearby_patrol_points: Array[Vector3]) -> void:
	_has_site = true
	_site = site
	_sweep_timer = first_sweep_delay
	for hunter: HunterAgent in _hunters:
		hunter.add_patrol_points(nearby_patrol_points)


## Any system may report the Runner's position (Ignition broadcast, security alarm, uplink).
func report_signal(world_position: Vector3) -> void:
	if _grace_left > 0.0:
		return
	_live_position = world_position
	_last_live_time = _clock


## Called (via signal wiring in main) after the Runner has been captured and respawned.
func on_runner_respawned(_total_captures: int) -> void:
	_grace_left = capture_grace_period
	_last_live_time = -1000.0
	for hunter: HunterAgent in _hunters:
		hunter.command_patrol()


func get_hunters() -> Array[HunterAgent]:
	return _hunters.duplicate()


func _physics_process(delta: float) -> void:
	_clock += delta
	_drone_cd -= delta
	_grace_left = maxf(_grace_left - delta, 0.0)
	_update_sweeps(delta)
	_decision_left -= delta
	if _decision_left <= 0.0:
		_decision_left = decision_interval
		_run_decisions()


func _is_live() -> bool:
	return _grace_left <= 0.0 and _clock - _last_live_time <= live_signal_timeout


func _update_sweeps(delta: float) -> void:
	if not _has_site or _sweeper != null:
		return
	_sweep_timer -= delta
	if _sweep_timer > 0.0:
		return
	var best: HunterAgent = null
	var best_distance: float = INF
	for hunter: HunterAgent in _hunters:
		if hunter.state != HunterAgent.State.PATROL or hunter.is_sweeping():
			continue
		var distance: float = hunter.global_position.distance_to(_site)
		if distance < best_distance:
			best_distance = distance
			best = hunter
	if best == null:
		_sweep_timer = 3.0
		return
	if best.command_sweep(_site, sweep_scan_duration):
		_sweeper = best
		_sweep_timer = sweep_interval
		site_sweep_dispatched.emit(_site)


func _run_decisions() -> void:
	_prune()
	var live: bool = _is_live()
	var assigned: Dictionary = {}

	for beacon: Node3D in _active_decoys:
		var candidates: Array[HunterAgent] = []
		for hunter: HunterAgent in _hunters:
			if assigned.has(hunter.hunter_id):
				continue
			if live and hunter.global_position.distance_to(_live_position) < proximity_override_radius:
				continue
			candidates.append(hunter)
		var beacon_position: Vector3 = beacon.global_position
		candidates.sort_custom(func(a: HunterAgent, b: HunterAgent) -> bool:
			return a.global_position.distance_squared_to(beacon_position) < b.global_position.distance_squared_to(beacon_position))
		for i: int in mini(decoy_pull_count, candidates.size()):
			candidates[i].command_chase_decoy(beacon)
			assigned[candidates[i].hunter_id] = true

	for hunter: HunterAgent in _hunters:
		if assigned.has(hunter.hunter_id):
			continue
		if live:
			hunter.command_apex_pursuit(_live_position)
			continue
		if hunter.state == HunterAgent.State.APEX_PURSUIT:
			hunter.command_investigate(hunter.last_known_position, -1)
			_launch_drone(hunter.global_position, hunter.last_known_position)
			continue
		var echo: ResidualEcho = _best_echo_for(hunter)
		if echo != null:
			hunter.command_investigate(echo.global_position, echo.get_instance_id())
		elif hunter.state == HunterAgent.State.CHASE_DECOY:
			hunter.command_patrol()

	_emit_census()


## Lost contact: send a Seeker Drone to search the last known position.
func _launch_drone(from: Vector3, search_at: Vector3) -> void:
	_drones = _drones.filter(func(d: SeekerDrone) -> bool: return is_instance_valid(d))
	if _drone_cd > 0.0 or _drones.size() >= max_drones:
		return
	_drone_cd = drone_cooldown
	var drone := SeekerDrone.new()
	drone.name = "SeekerDrone"
	drone.search_center = search_at
	add_child(drone)
	drone.global_position = from + Vector3(0.0, 2.5, 0.0)
	drone.runner_spotted.connect(report_signal)
	_drones.append(drone)
	drone_launched.emit(search_at)


func _best_echo_for(hunter: HunterAgent) -> ResidualEcho:
	var best: ResidualEcho = null
	var best_score: float = -INF
	for echo: ResidualEcho in _echoes:
		var echo_id: int = echo.get_instance_id()
		var searched: Array = _investigated.get(echo_id, [])
		if searched.has(hunter.hunter_id):
			continue
		var distance: float = hunter.global_position.distance_to(echo.global_position)
		if distance > echo_hearing_radius * (0.4 + 0.6 * echo.strength):
			continue
		if hunter.current_echo_id != echo_id and _investigator_count(echo_id) >= max_investigators_per_echo:
			continue
		var score: float = echo.strength * 100.0 - distance * 0.5
		if score > best_score:
			best_score = score
			best = echo
	return best


func _investigator_count(echo_id: int) -> int:
	var count: int = 0
	for hunter: HunterAgent in _hunters:
		if hunter.state == HunterAgent.State.INVESTIGATE_ECHO and hunter.current_echo_id == echo_id:
			count += 1
	return count


func _prune() -> void:
	_active_decoys = _active_decoys.filter(func(beacon: Node3D) -> bool: return is_instance_valid(beacon))
	_echoes = _echoes.filter(func(echo: ResidualEcho) -> bool: return is_instance_valid(echo) and echo.strength > 0.0)


func _emit_census() -> void:
	var census := Vector4i.ZERO
	for hunter: HunterAgent in _hunters:
		match hunter.state:
			HunterAgent.State.PATROL:
				census.x += 1
			HunterAgent.State.INVESTIGATE_ECHO:
				census.y += 1
			HunterAgent.State.APEX_PURSUIT:
				census.z += 1
			HunterAgent.State.CHASE_DECOY:
				census.w += 1
	if census != _census:
		_census = census
		hunter_census_changed.emit(census.x, census.y, census.z, census.w)


# --- Signal handlers -------------------------------------------------------------

## Every Hunter within the pulse radius converges on the Release point (APEX hunters keep chasing).
func _on_codex_released(world_position: Vector3, radius: float, _from_decoy: bool) -> void:
	if _grace_left > 0.0:
		return
	var responders: int = 0
	for hunter: HunterAgent in _hunters:
		if hunter.state == HunterAgent.State.APEX_PURSUIT:
			continue
		if hunter.global_position.distance_to(world_position) <= radius:
			hunter.command_investigate(world_position, -1)
			responders += 1
	release_heard.emit(world_position, responders)
	_emit_census()


func _on_echo_dropped(echo: ResidualEcho) -> void:
	if _grace_left > 0.0:
		return
	_echoes.append(echo)
	echo.expired.connect(_on_echo_expired)


func _on_echo_expired(echo: ResidualEcho) -> void:
	_echoes.erase(echo)
	_investigated.erase(echo.get_instance_id())


func _on_decoy_activated(beacon: Node3D, _ability: StringName) -> void:
	if not _active_decoys.has(beacon):
		_active_decoys.append(beacon)
	_decision_left = 0.0


func _on_decoy_deactivated(beacon: Node3D, _ability: StringName) -> void:
	_active_decoys.erase(beacon)
	_decision_left = 0.0


func _on_hunter_state_changed(hunter: HunterAgent, new_state: int) -> void:
	hunter_state_changed.emit(hunter.hunter_id, HunterAgent.state_to_name(new_state))
	_emit_census()


func _on_investigation_finished(hunter: HunterAgent, echo_id: int) -> void:
	if echo_id == -1:
		return
	var searched: Array = _investigated.get(echo_id, [])
	searched.append(hunter.hunter_id)
	_investigated[echo_id] = searched


func _on_runner_touched(_hunter: HunterAgent) -> void:
	if _grace_left > 0.0:
		return
	_grace_left = capture_grace_period
	_last_live_time = -1000.0
	runner_caught.emit()


func _on_sweep_scan_started(_hunter: HunterAgent, site: Vector3) -> void:
	site_sweep_scanning.emit(site, true)


func _on_sweep_finished(hunter: HunterAgent) -> void:
	if hunter == _sweeper:
		_sweeper = null
	site_sweep_scanning.emit(_site, false)
