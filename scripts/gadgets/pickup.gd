class_name Pickup
extends Area3D
## Collectible (Resonance Cell, Jammer darts, EMP charge). Bobs and glows; collected by the
## Runner on touch through the duck-typed `collect_pickup(kind, amount) -> bool` contract.
## Respawns after `respawn_time` so supplies never soft-lock the run.

const KIND_CELL: StringName = &"cell"
const KIND_DARTS: StringName = &"darts"
const KIND_EMP: StringName = &"emp"

@export var kind: StringName = KIND_CELL
@export var amount: int = 1
@export var respawn_time: float = 75.0

var _visual: Node3D
var _respawn_left: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	shape.shape = sphere
	shape.position = Vector3(0.0, 0.8, 0.0)
	add_child(shape)
	_visual = Node3D.new()
	add_child(_visual)
	_build_visual()
	body_entered.connect(_on_body_entered)
	_time = randf() * TAU


func _process(delta: float) -> void:
	_time += delta
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_visual.visible = true
			set_deferred(&"monitoring", true)
		return
	_visual.rotation.y = _time * 1.2
	_visual.position.y = 0.8 + sin(_time * 2.0) * 0.08


func _build_visual() -> void:
	var color: Color = get_color()
	var glow := MaterialLibrary.emissive(color, 3.0)
	var shell := MaterialLibrary.coated(Color(0.14, 0.15, 0.17), 0.85, 0.3)
	match kind:
		KIND_CELL:
			GeometryKit.cylinder(_visual, Vector3.ZERO, 0.09, 0.09, 0.34, glow, 12)
			GeometryKit.cylinder(_visual, Vector3(0.0, 0.2, 0.0), 0.11, 0.11, 0.06, shell, 12)
			GeometryKit.cylinder(_visual, Vector3(0.0, -0.2, 0.0), 0.11, 0.11, 0.06, shell, 12)
		_:
			GeometryKit.mesh_box(_visual, Vector3.ZERO, Vector3(0.5, 0.3, 0.35), shell)
			GeometryKit.mesh_box(_visual, Vector3(0.0, 0.0, 0.18), Vector3(0.35, 0.08, 0.01), glow)
			GeometryKit.mesh_box(_visual, Vector3(0.0, 0.16, 0.0), Vector3(0.3, 0.02, 0.2), glow)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 3.5
	_visual.add_child(light)


func get_color() -> Color:
	match kind:
		KIND_DARTS:
			return Color(0.3, 0.85, 1.0)
		KIND_EMP:
			return Color(0.55, 0.6, 1.0)
	return Color(1.0, 0.72, 0.25)


func _on_body_entered(body: Node3D) -> void:
	if _respawn_left > 0.0 or not body.has_method(&"collect_pickup"):
		return
	if bool(body.call(&"collect_pickup", kind, amount)):
		_visual.visible = false
		_respawn_left = respawn_time
		set_deferred(&"monitoring", false)
