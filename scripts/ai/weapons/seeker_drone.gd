class_name SeekerDrone
extends Node3D
## Hunter weapon: a quad-rotor search drone dispatched to the last known position. It hugs
## terrain/rooftops at `hover_height`, sweeps an expanding spiral with a downward spotlight and
## reports the Runner whenever they're caught in the light. Electronics: darts/EMP down it.

signal runner_spotted(world_position: Vector3)
signal expired(drone: SeekerDrone)

@export var cruise_speed: float = 11.0
@export var hover_height: float = 7.5
@export var search_time: float = 18.0
@export var light_half_angle: float = 28.0

var search_center: Vector3 = Vector3.ZERO

var _searching: bool = false
var _search_age: float = 0.0
var _time: float = 0.0
var _rotors: Array[Node3D] = []
var _light: SpotLight3D
var _cone_material: StandardMaterial3D
var _falling: float = -1.0
var _target_y: float = 20.0


func _ready() -> void:
	add_to_group(Electronics.ELECTRONICS_GROUP)
	var body := MaterialLibrary.coated(Color(0.15, 0.16, 0.18), 0.7, 0.35)
	var dark := MaterialLibrary.coated(Color(0.05, 0.05, 0.06), 0.5, 0.5)
	GeometryKit.mesh_box(self, Vector3.ZERO, Vector3(0.5, 0.16, 0.5), body)
	GeometryKit.sphere(self, Vector3(0.0, -0.12, 0.0), 0.12, MaterialLibrary.glass(Color(0.05, 0.05, 0.08)))
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			GeometryKit.tilted_box(self, Vector3(x * 0.32, 0.0, z * 0.32), Vector3(0.06, 0.05, 0.5), Vector3(0.0, 45.0 * x * z, 0.0), dark)
			var rotor := Node3D.new()
			rotor.position = Vector3(x * 0.5, 0.08, z * 0.5)
			add_child(rotor)
			GeometryKit.cylinder(rotor, Vector3.ZERO, 0.24, 0.24, 0.01, MaterialLibrary.hologram(Color(0.7, 0.7, 0.75), 0.25), 16)
			_rotors.append(rotor)
	GeometryKit.mesh_box(self, Vector3(0.0, 0.0, -0.26), Vector3(0.18, 0.04, 0.02), MaterialLibrary.emissive(Color(1.0, 0.15, 0.1), 5.0))
	Electronics.add_hitbox(self, Vector3.ZERO, Vector3(1.2, 0.5, 1.2))
	_light = SpotLight3D.new()
	_light.light_color = Color(0.9, 0.95, 1.0)
	_light.light_energy = 8.0
	_light.spot_range = hover_height * 2.2
	_light.spot_angle = light_half_angle
	_light.light_volumetric_fog_energy = 2.0
	_light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_light.position = Vector3(0.0, -0.2, 0.0)
	add_child(_light)
	_cone_material = MaterialLibrary.hologram(Color(0.85, 0.9, 1.0), 0.05)
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.05
	mesh.bottom_radius = hover_height * tan(deg_to_rad(light_half_angle))
	mesh.height = hover_height
	mesh.cap_top = false
	mesh.cap_bottom = false
	cone.mesh = mesh
	cone.material_override = _cone_material
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.position = Vector3(0.0, -hover_height * 0.5, 0.0)
	add_child(cone)


func disable_for(_seconds: float) -> void:
	if _falling < 0.0:
		_falling = 0.0
		_light.visible = false
		Electronics.sparks(get_parent(), global_position, Color(0.6, 0.8, 1.0))


func _physics_process(delta: float) -> void:
	_time += delta
	for rotor: Node3D in _rotors:
		rotor.rotation.y += delta * (40.0 if _falling < 0.0 else 4.0)
	if _falling >= 0.0:
		_falling += delta
		global_position.y -= delta * (2.0 + _falling * 12.0)
		rotation.z += delta * 3.0
		if _falling > 1.6:
			expired.emit(self)
			queue_free()
		return

	var goal: Vector3 = search_center
	if _searching:
		_search_age += delta
		var r: float = 2.0 + _search_age * 0.7
		goal = search_center + Vector3(cos(_time * 0.9) * r, 0.0, sin(_time * 0.9) * r)
		if _search_age >= search_time:
			expired.emit(self)
			queue_free()
			return
	_target_y = lerpf(_target_y, _ground_height(goal) + hover_height, clampf(delta * 2.0, 0.0, 1.0))
	var flat := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	if not _searching and flat.length() < 1.5:
		_searching = true
	var step: Vector3 = flat.limit_length(cruise_speed * delta)
	global_position += step
	global_position.y = move_toward(global_position.y, _target_y, delta * 6.0)
	if flat.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), clampf(delta * 4.0, 0.0, 1.0))
	rotation.x = -step.length() / maxf(cruise_speed * delta, 0.001) * 0.15
	_scan()


func _ground_height(at: Vector3) -> float:
	var from := Vector3(at.x, 45.0, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(at.x, -2.0, at.z), GeometryKit.WORLD_LAYER)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3 = hit.get("position", Vector3.ZERO)
	return point.y


func _scan() -> void:
	var runner := get_tree().get_first_node_in_group(&"runner") as Node3D
	if runner == null:
		return
	if runner.has_method(&"is_disguise_convincing") and bool(runner.call(&"is_disguise_convincing")):
		return
	var to_runner: Vector3 = runner.global_position + Vector3(0.0, 1.0, 0.0) - global_position
	if to_runner.length() > hover_height * 2.2 or Vector3.DOWN.angle_to(to_runner) > deg_to_rad(light_half_angle):
		_cone_material.albedo_color = Color(0.85, 0.9, 1.0, 0.05)
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, runner.global_position + Vector3(0.0, 1.0, 0.0), GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return
	_cone_material.albedo_color = Color(1.0, 0.2, 0.15, 0.12)
	_light.light_color = Color(1.0, 0.3, 0.25)
	runner_spotted.emit(runner.global_position)
