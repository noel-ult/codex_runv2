class_name SentryTurret
extends Node3D
## Hunter-tech automated sentry. Sweeps its arc; on sighting the Runner (unless convincingly
## disguised) it raises the alarm and fires stun bolts that slow the Runner on impact.
## Electronics: Jammer Dart / EMP knock it offline.

signal intruder_spotted(world_position: Vector3)

@export var sweep_degrees: float = 55.0
@export var sweep_speed: float = 0.6
@export var view_range: float = 18.0
@export var half_fov_degrees: float = 24.0
@export var fire_interval: float = 1.3

var _head: Node3D
var _barrel_tip: Node3D
var _eye: StandardMaterial3D
var _disabled_left: float = 0.0
var _fire_left: float = 0.0
var _time: float = 0.0
var _tracking: bool = false
var _runner: Node3D


func _ready() -> void:
	add_to_group(Electronics.ELECTRONICS_GROUP)
	_time = randf() * TAU
	var armour := MaterialLibrary.coated(Color(0.28, 0.3, 0.32), 0.75, 0.3)
	var dark := MaterialLibrary.coated(Color(0.07, 0.07, 0.08), 0.6, 0.4)
	GeometryKit.solid_box(self, Vector3(0.0, 0.3, 0.0), Vector3(0.9, 0.6, 0.9), armour)
	GeometryKit.cylinder(self, Vector3(0.0, 0.8, 0.0), 0.14, 0.18, 0.5, dark, 12)
	_head = Node3D.new()
	_head.position = Vector3(0.0, 1.15, 0.0)
	add_child(_head)
	GeometryKit.mesh_box(_head, Vector3.ZERO, Vector3(0.55, 0.32, 0.6), armour)
	GeometryKit.mesh_box(_head, Vector3(0.0, 0.18, 0.05), Vector3(0.45, 0.06, 0.45), dark)
	for side: float in [-0.13, 0.13]:
		var barrel := GeometryKit.cylinder(_head, Vector3(side, -0.02, -0.5), 0.035, 0.045, 0.5, dark, 10)
		barrel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_eye = MaterialLibrary.emissive(Color(1.0, 0.75, 0.2), 4.0, false)
	GeometryKit.mesh_box(_head, Vector3(0.0, 0.05, -0.305), Vector3(0.22, 0.06, 0.01), _eye)
	_barrel_tip = Node3D.new()
	_barrel_tip.position = Vector3(0.0, -0.02, -0.8)
	_head.add_child(_barrel_tip)
	Electronics.add_hitbox(_head, Vector3.ZERO, Vector3(0.8, 0.6, 0.9))


func disable_for(seconds: float) -> void:
	_disabled_left = maxf(_disabled_left, seconds)
	_tracking = false


func _physics_process(delta: float) -> void:
	if _disabled_left > 0.0:
		_disabled_left -= delta
		_eye.emission_energy_multiplier = 3.0 if fmod(_disabled_left, 0.7) < 0.08 else 0.0
		_head.rotation.x = lerp_angle(_head.rotation.x, 0.5, clampf(delta * 3.0, 0.0, 1.0))
		return
	_eye.emission_energy_multiplier = 4.0
	_time += delta
	_fire_left -= delta
	if _runner == null or not is_instance_valid(_runner):
		_runner = get_tree().get_first_node_in_group(&"runner") as Node3D
	var target: Vector3 = _runner.global_position + Vector3(0.0, 1.0, 0.0) if _runner != null else Vector3.ZERO
	_tracking = _runner != null and _can_see(target)
	if _tracking:
		var local: Vector3 = to_local(target)
		var yaw: float = atan2(-local.x, -local.z)
		_head.rotation.y = lerp_angle(_head.rotation.y, yaw, clampf(delta * 6.0, 0.0, 1.0))
		_head.rotation.x = lerp_angle(_head.rotation.x, atan2(local.y - 1.15, Vector2(local.x, local.z).length()), clampf(delta * 6.0, 0.0, 1.0))
		_eye.albedo_color = Color(1.0, 0.1, 0.08)
		_eye.emission = Color(1.0, 0.1, 0.08)
		intruder_spotted.emit(_runner.global_position)
		if _fire_left <= 0.0:
			_fire_left = fire_interval
			_fire(target)
	else:
		_head.rotation.y = lerp_angle(_head.rotation.y, deg_to_rad(sweep_degrees) * sin(_time * sweep_speed), clampf(delta * 2.0, 0.0, 1.0))
		_head.rotation.x = lerp_angle(_head.rotation.x, -0.1, clampf(delta * 2.0, 0.0, 1.0))
		_eye.albedo_color = Color(1.0, 0.75, 0.2)
		_eye.emission = Color(1.0, 0.75, 0.2)


func _can_see(target: Vector3) -> bool:
	if _runner.has_method(&"is_disguise_convincing") and bool(_runner.call(&"is_disguise_convincing")):
		return false
	var origin: Vector3 = _head.global_position
	var to_target: Vector3 = target - origin
	if to_target.length() > Electronics.sensor_range(_runner, view_range):
		return false
	var forward: Vector3 = -global_basis.z
	var flat_angle: float = Vector2(forward.x, forward.z).angle_to(Vector2(to_target.x, to_target.z))
	if absf(flat_angle) > deg_to_rad(sweep_degrees + half_fov_degrees):
		return false
	if not _tracking and (-_head.global_basis.z).angle_to(to_target) > deg_to_rad(half_fov_degrees):
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, target, GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _fire(target: Vector3) -> void:
	var from: Vector3 = _barrel_tip.global_position
	HunterFX.beam(get_parent(), from, target, Color(1.0, 0.75, 0.2), 0.12)
	HunterFX.flash(get_parent(), from, Color(1.0, 0.75, 0.2), 3.0)
	var query := PhysicsRayQueryParameters3D.create(from, target + (target - from).normalized() * 0.5, GeometryKit.WORLD_LAYER | 2)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var body := hit.get("collider") as Node
	if body != null and body.is_in_group(&"runner") and body.has_method(&"apply_slow"):
		body.call(&"apply_slow", 2.2, 0.5)
