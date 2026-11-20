class_name HunterAgent
extends CharacterBody3D
## Individual Hunter with a 4-state FSM:
## PATROL -> INVESTIGATE_ECHO -> APEX_PURSUIT -> CHASE_DECOY.
##
## Hunters never perceive the Runner directly (Base Form is invisible). They act only on
## commands issued by the HunterAIDirector, which itself listens to CodexSignalSystem signals.
## While patrolling, the Director may order a "site sweep": the hunter walks to the guarded
## uplink site and scans it. Physical contact while alerted (APEX/INVESTIGATE) is a capture.

signal state_changed(hunter: HunterAgent, new_state: int)
signal investigation_finished(hunter: HunterAgent, echo_id: int)
signal sweep_scan_started(hunter: HunterAgent, site: Vector3)
signal sweep_finished(hunter: HunterAgent)
signal runner_touched(hunter: HunterAgent)
## A Hunter weapon (sonar) located the Runner.
signal weapon_report(hunter: HunterAgent, world_position: Vector3)
## The Runner plugged into this Hunter's suit port (HunterNet access point).
signal suit_port_accessed(hunter: HunterAgent, actor: Node3D)

enum State { PATROL, INVESTIGATE_ECHO, APEX_PURSUIT, CHASE_DECOY }

@export_group("Speeds")
@export var patrol_speed: float = 4.0
@export var investigate_speed: float = 6.0
@export var pursuit_speed: float = 8.0
@export var decoy_chase_speed: float = 9.0
@export var acceleration: float = 20.0
@export var turn_speed: float = 8.0
@export var gravity: float = 22.0

@export_group("Weapons")
@export var harpoon_range: float = 16.0
@export var harpoon_cooldown: float = 6.0
@export var sonar_range: float = 32.0
@export var sonar_cooldown: float = 14.0

@export_group("Behaviour")
@export var investigate_linger_time: float = 3.0
@export var moving_target_repath_interval: float = 0.25
@export var stuck_timeout: float = 2.5

var hunter_id: int = 0
var state: State = State.PATROL
var current_echo_id: int = -1
var last_known_position: Vector3 = Vector3.ZERO

var _patrol_points: Array[Vector3] = []
var _decoy_target: Node3D
var _linger_left: float = 0.0
var _repath_left: float = 0.0
var _stuck_time: float = 0.0
var _needs_patrol_target: bool = true
var _rng := RandomNumberGenerator.new()
var _indicator_material: StandardMaterial3D
var _time: float = 0.0
var _sweep_active: bool = false
var _sweep_scanning: bool = false
var _sweep_site: Vector3 = Vector3.ZERO
var _sweep_left: float = 0.0
var _decoy_check_left: float = 0.0
var _stun_left: float = 0.0
var _harpoon_cd: float = 2.0
var _sonar_cd: float = 4.0
var _apex_fresh: float = 99.0
var _diagnostic: bool = false
var _suit_port: Interactable

@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _indicator: MeshInstance3D = $StateIndicator
@onready var _state_light: OmniLight3D = $StateLight
@onready var _rig: HumanoidRig = $Rig
@onready var _catch_area: Area3D = $CatchArea


func _ready() -> void:
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator_material.emission_enabled = true
	_indicator_material.emission_energy_multiplier = 3.0
	_indicator.material_override = _indicator_material
	_catch_area.body_entered.connect(_on_catch_body_entered)
	add_to_group(Electronics.EMP_GROUP)
	_suit_port = Interactable.new()
	_suit_port.name = "SuitPort"
	_suit_port.prompt = "Jack into the Hunter's suit port (HunterNet)"
	_suit_port.hold_time = 1.2
	_suit_port.radius = 1.9
	_suit_port.position = Vector3(0.0, 1.3, 0.35)
	_suit_port.requirement = _port_accessible
	_suit_port.requirement_hint = "Only from behind an unaware (green) Hunter"
	add_child(_suit_port)
	_suit_port.completed.connect(func(_i: Interactable, actor: Node3D) -> void: suit_port_accessed.emit(self, actor))
	_apply_state_visual()


func setup(id: int, patrol_points: Array[Vector3], random_seed: int) -> void:
	hunter_id = id
	name = "Hunter%d" % id
	_patrol_points = patrol_points
	_rng.seed = random_seed


static func state_to_name(value: int) -> String:
	match value:
		State.PATROL:
			return "PATROL"
		State.INVESTIGATE_ECHO:
			return "INVESTIGATE_ECHO"
		State.APEX_PURSUIT:
			return "APEX_PURSUIT"
		State.CHASE_DECOY:
			return "CHASE_DECOY"
	return "UNKNOWN"


static func state_to_color(value: int) -> Color:
	match value:
		State.PATROL:
			return Color(0.2, 0.95, 0.4)
		State.INVESTIGATE_ECHO:
			return Color(1.0, 0.75, 0.1)
		State.APEX_PURSUIT:
			return Color(1.0, 0.1, 0.1)
		State.CHASE_DECOY:
			return Color(0.7, 0.3, 1.0)
	return Color.WHITE


# --- Commands issued by the Director -----------------------------------------

func command_patrol() -> void:
	if state == State.PATROL:
		return
	current_echo_id = -1
	_decoy_target = null
	_change_state(State.PATROL)
	_needs_patrol_target = true


func command_investigate(target: Vector3, echo_id: int) -> void:
	if state == State.INVESTIGATE_ECHO and echo_id == current_echo_id and echo_id != -1:
		return
	current_echo_id = echo_id
	_decoy_target = null
	_change_state(State.INVESTIGATE_ECHO)
	_linger_left = investigate_linger_time
	_set_destination(target)
	_try_sonar(target)


func command_apex_pursuit(target: Vector3) -> void:
	last_known_position = target
	_apex_fresh = 0.0
	current_echo_id = -1
	_decoy_target = null
	if state != State.APEX_PURSUIT:
		_change_state(State.APEX_PURSUIT)
		_repath_left = 0.0
	if _repath_left <= 0.0:
		_repath_left = moving_target_repath_interval
		_set_destination(target)


func command_chase_decoy(beacon: Node3D) -> void:
	if state == State.CHASE_DECOY and beacon == _decoy_target:
		return
	current_echo_id = -1
	_decoy_target = beacon
	_change_state(State.CHASE_DECOY)
	_repath_left = 0.0


func get_decoy_target() -> Node3D:
	return _decoy_target


## EMP / Jammer dart: the hunter's suit seizes up - it stops, can't catch, loses its target.
func apply_emp(seconds: float) -> void:
	_stun_left = maxf(_stun_left, seconds)
	velocity = Vector3(0.0, velocity.y, 0.0)
	Electronics.sparks(get_parent(), global_position + Vector3(0.0, 1.6, 0.0), Color(0.5, 0.7, 1.0))


func is_stunned() -> bool:
	return _stun_left > 0.0


func _port_accessible(actor: Node3D) -> bool:
	if state != State.PATROL or _stun_left > 0.0 or _diagnostic:
		return false
	var to_actor: Vector3 = actor.global_position - global_position
	to_actor.y = 0.0
	return (-global_basis.z).dot(to_actor.normalized()) < -0.3


## Suit diagnostics: the Hunter freezes (unaware) while the Runner hacks it.
func begin_diagnostic(seconds: float) -> void:
	_diagnostic = true
	_stun_left = maxf(_stun_left, seconds)
	velocity = Vector3(0.0, velocity.y, 0.0)


func end_diagnostic() -> void:
	_diagnostic = false
	_stun_left = minf(_stun_left, 0.8)


func add_patrol_points(points: Array[Vector3]) -> void:
	_patrol_points.append_array(points)


## Orders a sweep of the guarded site. Only honoured while patrolling.
func command_sweep(site: Vector3, duration: float) -> bool:
	if state != State.PATROL or _sweep_active:
		return false
	_sweep_active = true
	_sweep_scanning = false
	_sweep_site = site
	_sweep_left = duration
	_needs_patrol_target = false
	var offset := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * 3.5
	_set_destination(site + offset)
	return true


func is_sweeping() -> bool:
	return _sweep_active


func is_sweep_scanning() -> bool:
	return _sweep_scanning


# --- Simulation ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	_repath_left -= delta
	_apex_fresh += delta
	_harpoon_cd -= delta
	_sonar_cd -= delta
	if not is_on_floor():
		velocity.y -= gravity * delta

	if not _is_navigation_ready():
		move_and_slide()
		return

	if _stun_left > 0.0:
		_stun_left -= delta
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		move_and_slide()
		var flicker: bool = fmod(_stun_left, 0.3) < 0.15
		if _diagnostic:
			_rig.set_accent(Color(0.9, 0.7, 0.2) if fmod(_stun_left, 1.0) < 0.5 else Color(0.2, 0.15, 0.05), 2.0)
			_rig.crouch_amount = 0.15
		else:
			_rig.set_accent(Color(0.5, 0.6, 1.0) if flicker else Color(0.05, 0.05, 0.08), 3.0)
			_rig.crouch_amount = 0.6
		_rig.animate(Vector3.ZERO, is_on_floor(), delta)
		if _stun_left <= 0.0:
			_diagnostic = false
			_rig.crouch_amount = 0.0
			_apply_state_visual()
		return

	match state:
		State.PATROL:
			_tick_patrol()
		State.INVESTIGATE_ECHO:
			_tick_investigate(delta)
		State.APEX_PURSUIT:
			pass
		State.CHASE_DECOY:
			_tick_chase_decoy()

	_follow_path(delta)
	move_and_slide()
	_update_stuck(delta)
	_animate_indicator()
	_animate_rig(delta)
	_check_contact()
	_check_decoys(delta)
	_try_harpoon()


func _tick_patrol() -> void:
	if _sweep_active:
		_tick_sweep()
		return
	if _needs_patrol_target or _agent.is_navigation_finished():
		_needs_patrol_target = false
		_pick_patrol_target()


func _tick_sweep() -> void:
	if not _sweep_scanning:
		if _agent.is_navigation_finished():
			_sweep_scanning = true
			sweep_scan_started.emit(self, _sweep_site)
		return
	var to_site: Vector3 = _sweep_site - global_position
	var look_yaw: float = atan2(-to_site.x, -to_site.z) + sin(_time * 1.3) * 0.8
	rotation.y = lerp_angle(rotation.y, look_yaw, clampf(3.0 * get_physics_process_delta_time(), 0.0, 1.0))
	_sweep_left -= get_physics_process_delta_time()
	if _sweep_left <= 0.0:
		_end_sweep()
		_needs_patrol_target = true


func _end_sweep() -> void:
	if not _sweep_active:
		return
	_sweep_active = false
	_sweep_scanning = false
	sweep_finished.emit(self)


func _tick_investigate(delta: float) -> void:
	if not _agent.is_navigation_finished():
		return
	_linger_left -= delta
	rotation.y += sin(_time * 2.0) * 2.0 * delta
	if _linger_left <= 0.0:
		var finished_id: int = current_echo_id
		command_patrol()
		investigation_finished.emit(self, finished_id)


func _tick_chase_decoy() -> void:
	if _decoy_target == null or not is_instance_valid(_decoy_target):
		command_patrol()
		return
	if _repath_left <= 0.0:
		_repath_left = moving_target_repath_interval
		_set_destination(_decoy_target.global_position)


func _follow_path(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var desired := Vector3.ZERO
	if not _agent.is_navigation_finished():
		var next_point: Vector3 = _agent.get_next_path_position()
		var to_next: Vector3 = next_point - global_position
		to_next.y = 0.0
		if to_next.length_squared() > 0.0001:
			desired = to_next.normalized() * _speed_for_state()
			var target_yaw: float = atan2(-to_next.x, -to_next.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	horizontal = horizontal.move_toward(desired, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _update_stuck(delta: float) -> void:
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.3
	if moving or _agent.is_navigation_finished():
		_stuck_time = 0.0
		return
	_stuck_time += delta
	if _stuck_time < stuck_timeout:
		return
	_stuck_time = 0.0
	if state == State.PATROL and _sweep_active and not _sweep_scanning:
		_sweep_scanning = true
		sweep_scan_started.emit(self, _sweep_site)
	elif state == State.PATROL:
		_pick_patrol_target()
	elif state == State.INVESTIGATE_ECHO:
		_linger_left = 0.0
		_agent.target_position = global_position


func _speed_for_state() -> float:
	match state:
		State.INVESTIGATE_ECHO:
			return investigate_speed
		State.APEX_PURSUIT:
			return pursuit_speed
		State.CHASE_DECOY:
			return decoy_chase_speed
	return patrol_speed


func _pick_patrol_target() -> void:
	if _patrol_points.is_empty():
		return
	var point: Vector3 = _patrol_points[_rng.randi_range(0, _patrol_points.size() - 1)]
	if point.distance_to(global_position) < 6.0 and _patrol_points.size() > 1:
		point = _patrol_points[(_patrol_points.find(point) + 1) % _patrol_points.size()]
	_set_destination(point)


func _set_destination(target: Vector3) -> void:
	var map: RID = _agent.get_navigation_map()
	_agent.target_position = NavigationServer3D.map_get_closest_point(map, target)


func _is_navigation_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0


func _change_state(new_state: State) -> void:
	if state == new_state:
		return
	if state == State.PATROL:
		_end_sweep()
	state = new_state
	_stuck_time = 0.0
	_apply_state_visual()
	state_changed.emit(self, state)


func _apply_state_visual() -> void:
	var color: Color = state_to_color(state)
	_indicator_material.albedo_color = color
	_indicator_material.emission = color
	_state_light.light_color = color
	if _rig != null:
		_rig.set_accent(color, 4.0 if state == State.APEX_PURSUIT else 2.5)


func _animate_indicator() -> void:
	var spin: float = 6.0 if state == State.APEX_PURSUIT else 1.5
	_indicator.rotation.y = _time * spin
	_indicator.position.y = 2.3 + sin(_time * 3.0) * 0.05


func _animate_rig(delta: float) -> void:
	var local_velocity: Vector3 = global_basis.inverse() * velocity
	var lingering: bool = state == State.INVESTIGATE_ECHO and _agent.is_navigation_finished()
	_rig.scanning = _sweep_scanning or lingering
	_rig.animate(local_velocity, is_on_floor(), delta)


func _is_alerted() -> bool:
	return _stun_left <= 0.0 and (state == State.APEX_PURSUIT or state == State.INVESTIGATE_ECHO)


func _check_contact() -> void:
	if not _is_alerted():
		return
	for body: Node3D in _catch_area.get_overlapping_bodies():
		if body.is_in_group(&"runner"):
			runner_touched.emit(self)
			return


# --- Weapons -----------------------------------------------------------------------

func _chest() -> Vector3:
	return global_position + Vector3(0.0, 1.4, 0.0) - global_basis.z * 0.3


func _has_line_of_sight(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(_chest(), target, GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Tether Harpoon at the live broadcast position.
func _try_harpoon() -> void:
	if state != State.APEX_PURSUIT or _apex_fresh > 0.4 or _harpoon_cd > 0.0 or _stun_left > 0.0:
		return
	var target: Vector3 = last_known_position + Vector3(0.0, 1.0, 0.0)
	if _chest().distance_to(target) > harpoon_range or not _has_line_of_sight(target):
		return
	_harpoon_cd = harpoon_cooldown
	var harpoon := TetherHarpoon.new()
	get_parent().add_child(harpoon)
	harpoon.launch(_chest(), target, self)
	HunterFX.flash(get_parent(), _chest(), Color(1.0, 0.35, 0.2), 3.0)


## Sonar Grenade lobbed at a suspected position.
func _try_sonar(target: Vector3) -> void:
	if _sonar_cd > 0.0 or _stun_left > 0.0 or not is_inside_tree():
		return
	var distance: float = global_position.distance_to(target)
	if distance > sonar_range or distance < 4.0:
		return
	_sonar_cd = sonar_cooldown
	var grenade := SonarGrenade.new()
	get_parent().add_child(grenade)
	var from: Vector3 = _chest() + Vector3(0.0, 0.3, 0.0)
	grenade.global_position = from
	var flight: float = clampf(distance / 18.0, 0.6, 1.6)
	var gravity_value: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var delta_pos: Vector3 = target - from
	grenade.linear_velocity = Vector3(delta_pos.x / flight, (delta_pos.y + 0.5 * gravity_value * flight * flight) / flight, delta_pos.z / flight)
	grenade.runner_revealed.connect(func(at: Vector3) -> void: weapon_report.emit(self, at))


## Alerted hunters shoot apart any decoy emitter they get close to.
func _check_decoys(delta: float) -> void:
	_decoy_check_left -= delta
	if _decoy_check_left > 0.0 or state == State.PATROL:
		return
	_decoy_check_left = 0.3
	for node: Node in get_tree().get_nodes_in_group(&"decoy_emitters"):
		var decoy := node as Node3D
		if decoy == null or decoy.global_position.distance_to(global_position) > 4.0:
			continue
		if decoy.has_method(&"hunter_disable"):
			HunterFX.beam(get_parent(), global_position + Vector3(0.0, 1.4, 0.0), decoy.global_position + Vector3(0.0, 1.3, 0.0), HunterAgent.state_to_color(state))
			decoy.call(&"hunter_disable")


func _on_catch_body_entered(body: Node3D) -> void:
	if _is_alerted() and body.is_in_group(&"runner"):
		runner_touched.emit(self)
