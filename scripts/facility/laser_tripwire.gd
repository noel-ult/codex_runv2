class_name LaserTripwire
extends Node3D
## Pair of emitter posts with horizontal laser beams between them. Breaking a beam trips the
## alarm (reports the Runner's position). `sweep` makes the whole beam set travel up and down.
## Electronics: a Jammer Dart on either post or an EMP shuts the grid down temporarily.

signal tripped(world_position: Vector3)

@export var span: float = 5.0
@export var beam_heights: PackedFloat32Array = PackedFloat32Array([0.35, 0.9, 1.5])
@export var sweep: bool = false
@export var sweep_range: float = 1.4
@export var sweep_speed: float = 1.1

var _beams: Node3D
var _area: Area3D
var _beam_material: StandardMaterial3D
var _disabled_left: float = 0.0
var _time: float = 0.0
var _cooldown: float = 0.0


func _ready() -> void:
	add_to_group(Electronics.ELECTRONICS_GROUP)
	var post := MaterialLibrary.coated(Color(0.12, 0.12, 0.13), 0.8, 0.35)
	var lens := MaterialLibrary.emissive(Color(1.0, 0.1, 0.08), 4.0)
	for side: float in [-0.5, 0.5]:
		GeometryKit.solid_box(self, Vector3(side * span, 1.0, 0.0), Vector3(0.18, 2.0, 0.18), post)
		GeometryKit.mesh_box(self, Vector3(side * span, 1.95, 0.0), Vector3(0.2, 0.06, 0.2), lens)
		Electronics.add_hitbox(self, Vector3(side * span, 1.0, 0.0), Vector3(0.4, 2.0, 0.4))
	_beams = Node3D.new()
	add_child(_beams)
	_beam_material = MaterialLibrary.emissive(Color(1.0, 0.08, 0.05), 6.0, false)
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.albedo_color.a = 0.75
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	_beams.add_child(_area)
	for h: float in beam_heights:
		var beam := GeometryKit.cylinder(_beams, Vector3(0.0, h, 0.0), 0.012, 0.012, span, _beam_material, 6)
		beam.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(span, 0.08, 0.12)
		shape.shape = box
		shape.position = Vector3(0.0, h, 0.0)
		_area.add_child(shape)


func disable_for(seconds: float) -> void:
	_disabled_left = maxf(_disabled_left, seconds)


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _disabled_left > 0.0:
		_disabled_left -= delta
		_beams.visible = false
		_area.monitoring = false
		return
	_beams.visible = true
	_area.monitoring = true
	_time += delta
	if sweep:
		_beams.position.y = (sin(_time * sweep_speed) * 0.5 + 0.5) * sweep_range
	_beam_material.albedo_color.a = 0.6 + 0.25 * sin(_time * 20.0)
	if _cooldown > 0.0:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body.is_in_group(&"runner"):
			_cooldown = 0.25
			tripped.emit(body.global_position)
			return
