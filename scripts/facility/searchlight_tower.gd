class_name SearchlightTower
extends Node3D
## Guard tower whose searchlight sweeps a Lissajous pattern across the yard.
## Anyone standing in the pool of light (with line of sight to the lamp) is spotted.

signal intruder_spotted(world_position: Vector3)

@export var height: float = 8.0
## Centre and half-extents of the swept area, relative to the tower base.
@export var sweep_center: Vector3 = Vector3(-14.0, 0.0, -5.0)
@export var sweep_extent: Vector2 = Vector2(12.0, 7.0)
@export var sweep_speed: float = 0.3
@export var beam_radius: float = 3.2
@export var detect_time: float = 0.5

var _lamp: Node3D
var _light: SpotLight3D
var _time: float = 0.0
var _detect: float = 0.0
var _runner: Node3D
var _disabled_left: float = 0.0


func _ready() -> void:
	add_to_group(Electronics.ELECTRONICS_GROUP)
	var steel := MaterialLibrary.coated(Color(0.2, 0.21, 0.22), 0.85, 0.45)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			GeometryKit.tilted_box(self, Vector3(x * 0.9, height * 0.5, z * 0.9), Vector3(0.15, height, 0.15), Vector3(z * 3.0, 0.0, -x * 3.0), steel)
	for i: int in 4:
		var y: float = 1.5 + i * (height - 2.0) / 4.0
		GeometryKit.mesh_box(self, Vector3(0.0, y, 0.95), Vector3(1.9, 0.08, 0.08), steel)
		GeometryKit.mesh_box(self, Vector3(0.0, y, -0.95), Vector3(1.9, 0.08, 0.08), steel)
		GeometryKit.mesh_box(self, Vector3(0.95, y, 0.0), Vector3(0.08, 0.08, 1.9), steel)
		GeometryKit.mesh_box(self, Vector3(-0.95, y, 0.0), Vector3(0.08, 0.08, 1.9), steel)
	GeometryKit.collider_box(self, Vector3(0.0, height * 0.5, 0.0), Vector3(2.0, height, 2.0))
	GeometryKit.solid_box(self, Vector3(0.0, height, 0.0), Vector3(3.0, 0.2, 3.0), MaterialLibrary.metal_panel())
	for side: float in [-1.0, 1.0]:
		GeometryKit.mesh_box(self, Vector3(0.0, height + 0.55, side * 1.45), Vector3(3.0, 0.06, 0.06), steel)
		GeometryKit.mesh_box(self, Vector3(side * 1.45, height + 0.55, 0.0), Vector3(0.06, 0.06, 3.0), steel)
	GeometryKit.mesh_box(self, Vector3(0.0, height + 2.4, 0.0), Vector3(3.2, 0.12, 3.2), steel)
	for x: float in [-1.4, 1.4]:
		for z: float in [-1.4, 1.4]:
			GeometryKit.mesh_box(self, Vector3(x, height + 1.2, z), Vector3(0.08, 2.4, 0.08), steel)

	_lamp = Node3D.new()
	_lamp.position = Vector3(0.0, height + 1.0, 0.0)
	add_child(_lamp)
	var housing := GeometryKit.cylinder(_lamp, Vector3(0.0, 0.0, -0.1), 0.35, 0.3, 0.6, steel, 16)
	housing.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var lamp_glass := GeometryKit.cylinder(_lamp, Vector3(0.0, 0.0, -0.41), 0.3, 0.3, 0.02, MaterialLibrary.emissive(Color(1.0, 0.97, 0.9), 8.0), 16)
	lamp_glass.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_light = SpotLight3D.new()
	_light.light_color = Color(1.0, 0.97, 0.9)
	_light.light_energy = 16.0
	_light.spot_range = 40.0
	_light.spot_angle = 7.5
	_light.light_volumetric_fog_energy = 3.0
	_light.shadow_enabled = true
	_lamp.add_child(_light)
	Electronics.add_hitbox(_lamp, Vector3.ZERO, Vector3(0.9, 0.9, 0.9))


func disable_for(seconds: float) -> void:
	_disabled_left = maxf(_disabled_left, seconds)
	_detect = 0.0


func _physics_process(delta: float) -> void:
	if _disabled_left > 0.0:
		_disabled_left -= delta
		_light.visible = false
		return
	_light.visible = true
	_time += delta
	var target: Vector3 = global_position + sweep_center + Vector3(sin(_time * sweep_speed) * sweep_extent.x, 0.0, sin(_time * sweep_speed * 1.7 + 0.6) * sweep_extent.y)
	_lamp.look_at(target, Vector3.UP)
	if _runner == null or not is_instance_valid(_runner):
		_runner = get_tree().get_first_node_in_group(&"runner") as Node3D
		return
	if _runner.has_method(&"is_disguise_convincing") and bool(_runner.call(&"is_disguise_convincing")):
		_detect = 0.0
		return
	var offset: Vector3 = _runner.global_position - target
	var lit: bool = Vector2(offset.x, offset.z).length() <= beam_radius and _line_of_sight(_runner.global_position + Vector3(0.0, 1.0, 0.0))
	_detect = clampf(_detect + (delta / detect_time if lit else -delta), 0.0, 1.2)
	var alarm: bool = _detect >= 1.0
	_light.light_color = Color(1.0, 0.2, 0.15) if alarm else Color(1.0, 0.97, 0.9)
	if alarm and lit:
		intruder_spotted.emit(_runner.global_position)


func _line_of_sight(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(_lamp.global_position, point, GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
