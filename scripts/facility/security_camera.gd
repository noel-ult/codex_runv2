class_name SecurityCamera
extends Node3D
## Wall-mounted sweeping CCTV camera with a visible vision cone. Unlike Hunters, cameras
## *see* the Runner in any Form. A sustained sighting raises the alarm by emitting the
## Runner's position every frame it stays in view (wired to HunterAIDirector.report_signal).

signal intruder_spotted(world_position: Vector3)

@export var sweep_degrees: float = 45.0
@export var sweep_speed: float = 0.45
@export var view_range: float = 17.0
@export var half_fov_degrees: float = 20.0
@export var pitch_degrees: float = -28.0
@export var detect_time: float = 0.8

var _head: Node3D
var _cone_material: StandardMaterial3D
var _lens_material: StandardMaterial3D
var _light: SpotLight3D
var _detect: float = 0.0
var _time: float = 0.0
var _runner: Node3D
var _phase: float = 0.0
var _disabled_left: float = 0.0
var _cone: MeshInstance3D


func _ready() -> void:
	add_to_group(Electronics.ELECTRONICS_GROUP)
	_phase = randf() * TAU
	var body := MaterialLibrary.coated(Color(0.85, 0.85, 0.83), 0.3, 0.4)
	var dark := MaterialLibrary.coated(Color(0.08, 0.08, 0.09), 0.6, 0.4)
	GeometryKit.mesh_box(self, Vector3(0.0, 0.0, 0.0), Vector3(0.25, 0.25, 0.1), dark)
	GeometryKit.mesh_box(self, Vector3(0.0, 0.0, -0.2), Vector3(0.06, 0.06, 0.35), dark)
	_head = Node3D.new()
	_head.position = Vector3(0.0, -0.05, -0.4)
	add_child(_head)
	GeometryKit.mesh_box(_head, Vector3(0.0, 0.0, -0.15), Vector3(0.2, 0.18, 0.45), body)
	GeometryKit.mesh_box(_head, Vector3(0.0, 0.1, -0.2), Vector3(0.26, 0.03, 0.55), dark)
	_lens_material = MaterialLibrary.emissive(Color(1.0, 0.85, 0.3), 3.0, false)
	var lens := GeometryKit.cylinder(_head, Vector3(0.0, 0.0, -0.385), 0.06, 0.06, 0.03, _lens_material, 12)
	lens.rotation_degrees = Vector3(90.0, 0.0, 0.0)

	_cone_material = MaterialLibrary.hologram(Color(1.0, 0.9, 0.5), 0.05)
	Electronics.add_hitbox(_head, Vector3(0.0, 0.0, -0.15), Vector3(0.4, 0.35, 0.6))
	var cone := MeshInstance3D.new()
	_cone = cone
	var mesh := CylinderMesh.new()
	mesh.top_radius = view_range * tan(deg_to_rad(half_fov_degrees))
	mesh.bottom_radius = 0.02
	mesh.height = view_range
	mesh.radial_segments = 20
	mesh.cap_top = false
	mesh.cap_bottom = false
	cone.mesh = mesh
	cone.material_override = _cone_material
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cone.position = Vector3(0.0, 0.0, -0.4 - view_range * 0.5)
	_head.add_child(cone)

	_light = SpotLight3D.new()
	_light.light_color = Color(1.0, 0.9, 0.6)
	_light.light_energy = 1.5
	_light.spot_range = view_range
	_light.spot_angle = half_fov_degrees
	_light.position = Vector3(0.0, 0.0, -0.4)
	_head.add_child(_light)


func disable_for(seconds: float) -> void:
	_disabled_left = maxf(_disabled_left, seconds)
	_detect = 0.0


func is_disabled() -> bool:
	return _disabled_left > 0.0


func _physics_process(delta: float) -> void:
	if _disabled_left > 0.0:
		_disabled_left -= delta
		var flicker: bool = fmod(_disabled_left, 0.8) < 0.08
		_cone.visible = false
		_light.visible = false
		_lens_material.emission_energy_multiplier = 3.0 if flicker else 0.0
		return
	_cone.visible = true
	_light.visible = true
	_lens_material.emission_energy_multiplier = 3.0
	_time += delta
	_head.rotation = Vector3(deg_to_rad(pitch_degrees), deg_to_rad(sweep_degrees) * sin(_time * sweep_speed + _phase), 0.0)
	if _runner == null or not is_instance_valid(_runner):
		_runner = get_tree().get_first_node_in_group(&"runner") as Node3D
		return

	var seen: bool = _can_see(_runner.global_position + Vector3(0.0, 1.0, 0.0))
	_detect = clampf(_detect + (delta / detect_time if seen else -delta * 0.6), 0.0, 1.2)
	var alarm: bool = _detect >= 1.0
	var color: Color = Color(1.0, 0.12, 0.08) if alarm else Color(1.0, 0.9, 0.5).lerp(Color(1.0, 0.4, 0.1), clampf(_detect, 0.0, 1.0))
	_cone_material.albedo_color = Color(color, 0.05 + 0.12 * clampf(_detect, 0.0, 1.0))
	_lens_material.albedo_color = color
	_lens_material.emission = color
	_light.light_color = color
	if alarm and seen:
		intruder_spotted.emit(_runner.global_position)


func _can_see(target: Vector3) -> bool:
	var origin: Vector3 = _head.global_position
	var to_target: Vector3 = target - origin
	if to_target.length() > view_range:
		return false
	if (-_head.global_basis.z).angle_to(to_target) > deg_to_rad(half_fov_degrees):
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, target, GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
