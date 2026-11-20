class_name TrafficVehicle
extends AnimatableBody3D
## NPC traffic that drives along its parent PathFollow3D. Solid (the Runner can ride on
## the roof) with spinning wheels and working head/tail lights.

@export var display_name: String = "Vehicle"
@export var speed: float = 9.0
@export var body_color: Color = Color(0.8, 0.6, 0.2)
@export var kind: VehicleModel.Kind = VehicleModel.Kind.SEDAN

var _follow: PathFollow3D
var _wheels: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	sync_to_physics = true
	_follow = get_parent() as PathFollow3D
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.7 if kind != VehicleModel.Kind.VAN else 2.3, 4.6 if kind != VehicleModel.Kind.VAN else 5.0)
	shape.shape = box
	shape.position = Vector3(0.0, box.size.y * 0.5 + 0.1, 0.0)
	add_child(shape)
	_wheels = VehicleModel.build(self, kind, body_color, true)


func _physics_process(delta: float) -> void:
	if _follow != null:
		_follow.progress += speed * delta
	for wheel: Node3D in _wheels:
		wheel.rotation.x -= speed * delta / 0.36
