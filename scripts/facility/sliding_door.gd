class_name SlidingDoor
extends Node3D
## Motorised steel door/gate panel. The panel is an AnimatableBody3D so it pushes and
## blocks characters while moving. `slide` is the local offset of the fully open panel.

signal opened(door: SlidingDoor)
signal closed(door: SlidingDoor)

@export var size: Vector3 = Vector3(2.0, 3.0, 0.25)
@export var slide: Vector3 = Vector3(0.0, 3.1, 0.0)
@export var open_time: float = 1.4
@export var collision_layer: int = GeometryKit.WORLD_LAYER
@export var hazard_stripes: bool = false
@export var paint: Color = Color(0.25, 0.28, 0.3)

var is_open: bool = false

var _panel: AnimatableBody3D
var _t: float = 0.0
var _lamp_material: StandardMaterial3D


func _ready() -> void:
	_panel = AnimatableBody3D.new()
	_panel.collision_layer = collision_layer
	_panel.collision_mask = 0
	add_child(_panel)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_panel.add_child(shape)
	var mesh := GeometryKit.mesh_box(_panel, Vector3.ZERO, size, MaterialLibrary.metal_panel())
	mesh.set_instance_shader_parameter(&"paint_color", paint)
	mesh.set_instance_shader_parameter(&"hazard", 1.0 if hazard_stripes else 0.0)
	var frame := MaterialLibrary.coated(Color(0.08, 0.08, 0.09), 0.8, 0.45)
	GeometryKit.mesh_box(_panel, Vector3(0.0, size.y * 0.5 - 0.06, 0.0), Vector3(size.x, 0.12, size.z + 0.04), frame)
	GeometryKit.mesh_box(_panel, Vector3(0.0, -size.y * 0.5 + 0.06, 0.0), Vector3(size.x, 0.12, size.z + 0.04), frame)
	_lamp_material = MaterialLibrary.emissive(Color(1.0, 0.15, 0.1), 3.0, false)
	GeometryKit.mesh_box(self, Vector3(0.0, size.y * 0.5 + 0.25, size.z * 0.5 + 0.08), Vector3(0.25, 0.12, 0.1), _lamp_material)


func open() -> void:
	set_open(true)


func close() -> void:
	set_open(false)


func set_open(value: bool) -> void:
	if is_open == value:
		return
	is_open = value
	var color: Color = Color(0.2, 1.0, 0.35) if value else Color(1.0, 0.15, 0.1)
	_lamp_material.albedo_color = color
	_lamp_material.emission = color
	if value:
		opened.emit(self)
	else:
		closed.emit(self)


func _physics_process(delta: float) -> void:
	var target: float = 1.0 if is_open else 0.0
	if is_equal_approx(_t, target):
		return
	_t = move_toward(_t, target, delta / maxf(open_time, 0.01))
	_panel.position = slide * smoothstep(0.0, 1.0, _t)
