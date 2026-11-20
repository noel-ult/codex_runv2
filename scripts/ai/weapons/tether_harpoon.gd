class_name TetherHarpoon
extends Area3D
## Hunter weapon: an energy harpoon fired at the Runner's broadcast position. On a hit it
## latches on, slowing the Runner and reeling them toward the Hunter for `tether_time`.

@export var speed: float = 26.0
@export var lifetime: float = 1.3
@export var tether_time: float = 2.6

var shooter: Node3D
var _direction: Vector3 = Vector3.FORWARD
var _age: float = 0.0
var _victim: Node3D
var _tether_left: float = 0.0


func launch(from: Vector3, target: Vector3, owner_node: Node3D) -> void:
	shooter = owner_node
	global_position = from
	_direction = (target - from).normalized()
	look_at(global_position + _direction, Vector3.UP if absf(_direction.y) < 0.99 else Vector3.RIGHT)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 | GeometryKit.WORLD_LAYER
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	add_child(shape)
	var bolt := GeometryKit.cylinder(self, Vector3.ZERO, 0.02, 0.06, 0.7, MaterialLibrary.emissive(Color(1.0, 0.3, 0.15), 8.0), 8)
	bolt.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.35, 0.2)
	light.light_energy = 2.0
	light.omni_range = 4.0
	add_child(light)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _victim != null:
		_tether_left -= delta
		if not is_instance_valid(_victim) or not is_instance_valid(shooter) or _tether_left <= 0.0:
			queue_free()
			return
		global_position = _victim.global_position + Vector3(0.0, 1.1, 0.0)
		HunterFX.beam(get_parent(), shooter.global_position + Vector3(0.0, 1.4, 0.0), global_position, Color(1.0, 0.3, 0.15), 0.05)
		return
	_age += delta
	global_position += _direction * speed * delta
	if _age >= lifetime:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _victim != null:
		return
	if body.is_in_group(&"runner") and body.has_method(&"apply_tether") and is_instance_valid(shooter):
		_victim = body
		_tether_left = tether_time
		body.call(&"apply_tether", shooter.global_position, tether_time)
		set_deferred(&"monitoring", false)
	elif not body.is_in_group(&"hunters"):
		Electronics.sparks(get_parent(), global_position, Color(1.0, 0.4, 0.2))
		queue_free()
