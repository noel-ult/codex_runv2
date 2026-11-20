class_name NpcWalker
extends CharacterBody3D
## Ambient pedestrian / lab technician. Walks a waypoint route on the navmesh with a
## procedurally animated HumanoidRig. Sneak up behind one and hold E to clone their ID
## signature - the Runner takes on their appearance (technicians grant facility access).

signal id_cloned(npc: NpcWalker)

@export var style: HumanoidRig.Style = HumanoidRig.Style.CIVILIAN
@export var outfit_seed: int = 0
@export var walk_speed: float = 1.4
@export var pause_chance: float = 0.25

var route: Array[Vector3] = []
var display_role: String = "Civilian"

var _agent: NavigationAgent3D
var _rig: HumanoidRig
var _interactable: Interactable
var _index: int = 0
var _pause_left: float = 0.0
var _dazed_left: float = 0.0
var _rng := RandomNumberGenerator.new()
var _hold_freeze: float = 0.0
var _stuck_time: float = 0.0
var _marker: Label3D
var _runner: Node3D


func _ready() -> void:
	collision_layer = 128
	collision_mask = GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	_rng.seed = outfit_seed * 31 + 5
	if style == HumanoidRig.Style.TECHNICIAN:
		add_to_group(&"facility_staff")
		display_role = "Lab Technician"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.875, 0.0)
	add_child(shape)
	_rig = HumanoidRig.new()
	_rig.style = style
	_rig.outfit_seed = outfit_seed
	_rig.run_speed = 6.0
	add_child(_rig)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.8
	_agent.radius = 0.35
	add_child(_agent)
	_interactable = Interactable.new()
	_interactable.prompt = "Clone %s ID signature" % display_role.to_lower()
	_interactable.hold_time = 1.2
	_interactable.radius = 2.4
	_interactable.position = Vector3(0.0, 1.0, 0.0)
	_interactable.requirement = _actor_is_behind
	_interactable.requirement_hint = "Get behind them to clone their ID"
	add_child(_interactable)
	_interactable.completed.connect(_on_cloned)
	_interactable.hold_progress.connect(func(_i: Interactable, _p: float) -> void: _hold_freeze = 0.35)
	_marker = Label3D.new()
	_marker.text = "◇ CLONE ID"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.font_size = 28
	_marker.pixel_size = 0.0045
	_marker.outline_size = 6
	_marker.no_depth_test = true
	_marker.position = Vector3(0.0, 2.15, 0.0)
	_marker.visible = false
	add_child(_marker)
	walk_speed *= _rng.randf_range(0.85, 1.15)


func _actor_is_behind(actor: Node3D) -> bool:
	var to_actor: Vector3 = actor.global_position - global_position
	to_actor.y = 0.0
	if _dazed_left > 0.0:
		return false
	# Once the clone has started the NPC is frozen, so any angle keeps working.
	return _hold_freeze > 0.0 or (-global_basis.z).dot(to_actor.normalized()) < 0.45


func _on_cloned(_i: Interactable, actor: Node3D) -> void:
	_dazed_left = 8.0
	if actor.has_method(&"apply_disguise"):
		actor.call(&"apply_disguise", int(style), outfit_seed, style == HumanoidRig.Style.TECHNICIAN, display_role)
	id_cloned.emit(self)


## Shows a "clone ID" cue over NPCs near the Runner: green when in position behind them.
func _update_marker() -> void:
	if _runner == null or not is_instance_valid(_runner):
		_runner = get_tree().get_first_node_in_group(&"runner") as Node3D
		return
	var offset: Vector3 = _runner.global_position - global_position
	var near: bool = Vector2(offset.x, offset.z).length() < 7.0 and absf(offset.y) < 2.0 and _dazed_left <= 0.0
	_marker.visible = near
	if not near:
		return
	var in_position: bool = _interactable.is_available_for(_runner) and _actor_is_behind(_runner)
	_marker.modulate = Color(0.4, 1.0, 0.6) if in_position else Color(0.75, 0.78, 0.85, 0.75)
	_marker.text = ("◆ HOLD E · CLONE %s ID" % display_role.to_upper()) if in_position else "◇ %s · get behind" % display_role.to_upper()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	var desired := Vector3.ZERO
	_update_marker()
	if _hold_freeze > 0.0:
		_hold_freeze -= delta
	elif _dazed_left > 0.0:
		_dazed_left -= delta
		rotation.y += sin(_dazed_left * 3.0) * delta
	elif _pause_left > 0.0:
		_pause_left -= delta
	elif not route.is_empty() and NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0:
		if _agent.is_navigation_finished():
			_index = (_index + 1) % route.size()
			_agent.target_position = route[_index]
			if _rng.randf() < pause_chance:
				_pause_left = _rng.randf_range(1.5, 5.0)
		else:
			var next: Vector3 = _agent.get_next_path_position()
			var to_next: Vector3 = next - global_position
			to_next.y = 0.0
			if to_next.length_squared() > 0.0001:
				desired = to_next.normalized() * walk_speed
				rotation.y = lerp_angle(rotation.y, atan2(-to_next.x, -to_next.z), clampf(delta * 5.0, 0.0, 1.0))
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, 8.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	_rig.animate(global_basis.inverse() * velocity, is_on_floor(), delta)
	# Unstick: if we want to walk but aren't moving, skip to the next waypoint.
	if desired.length_squared() > 0.01 and Vector2(velocity.x, velocity.z).length() < 0.2:
		_stuck_time += delta
		if _stuck_time > 2.5 and not route.is_empty():
			_stuck_time = 0.0
			_index = (_index + 1) % route.size()
			_agent.target_position = route[_index]
	else:
		_stuck_time = 0.0
