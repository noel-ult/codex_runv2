class_name SonarGrenade
extends RigidBody3D
## Hunter weapon: lobbed at a suspected position. Once settled it emits sonar pings; a Runner
## inside `radius` is revealed (`runner_revealed`). Masks nothing - sonar sees through Forms.

signal runner_revealed(world_position: Vector3)

@export var radius: float = 11.0
@export var pings: int = 3
@export var ping_interval: float = 1.1

var _age: float = 0.0
var _ping_left: float = 0.9
var _pings_done: int = 0
var _lamp: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = GeometryKit.WORLD_LAYER
	mass = 0.8
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	shape.shape = sphere
	add_child(shape)
	GeometryKit.sphere(self, Vector3.ZERO, 0.15, MaterialLibrary.coated(Color(0.12, 0.12, 0.13), 0.8, 0.35))
	_lamp = MaterialLibrary.emissive(Color(1.0, 0.75, 0.15), 5.0, false)
	GeometryKit.cylinder(self, Vector3.ZERO, 0.155, 0.155, 0.05, _lamp, 12)


func _physics_process(delta: float) -> void:
	_age += delta
	_lamp.emission_energy_multiplier = 2.0 + 6.0 * absf(sin(_age * 9.0))
	_ping_left -= delta
	if _ping_left > 0.0:
		return
	_ping_left = ping_interval
	_pings_done += 1
	_ping()
	if _pings_done >= pings:
		queue_free()


func _ping() -> void:
	var at: Vector3 = global_position
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.95
	torus.outer_radius = 1.0
	torus.rings = 48
	ring.mesh = torus
	var material := MaterialLibrary.hologram(Color(1.0, 0.75, 0.2), 0.6)
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(ring)
	ring.global_position = at + Vector3(0.0, 0.1, 0.0)
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.7)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.8)
	tween.chain().tween_callback(ring.queue_free)
	HunterFX.flash(get_parent(), at + Vector3(0.0, 0.5, 0.0), Color(1.0, 0.75, 0.2), 6.0)
	var runner := get_tree().get_first_node_in_group(&"runner") as Node3D
	if runner != null and runner.global_position.distance_to(at) <= radius:
		runner_revealed.emit(runner.global_position)
