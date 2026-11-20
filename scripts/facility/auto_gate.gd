class_name AutoGate
extends SlidingDoor
## Compound vehicle gate: opens automatically for Hunters (and only Hunters) passing through,
## then closes after `hold_open_time`. The Runner has to slip through behind them.

@export var trigger_size: Vector3 = Vector3(9.0, 4.0, 16.0)
@export var hold_open_time: float = 3.0

var _trigger: Area3D
var _hold_left: float = 0.0


func _ready() -> void:
	super._ready()
	_trigger = Area3D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask = 4
	_trigger.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = trigger_size
	shape.shape = box
	_trigger.add_child(shape)
	add_child(_trigger)


func _physics_process(delta: float) -> void:
	var hunter_near: bool = false
	for body: Node3D in _trigger.get_overlapping_bodies():
		if body.is_in_group(&"hunters"):
			hunter_near = true
			break
	if hunter_near:
		_hold_left = hold_open_time
		open()
	else:
		_hold_left -= delta
		if _hold_left <= 0.0:
			close()
	super._physics_process(delta)
