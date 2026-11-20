class_name EmpCharge
extends RigidBody3D
## Thrown EMP grenade. Detonates on impact (after arming) or after its fuse: disables every
## electronic device in `radius` and stuns Hunters. The discharge agitates the Codex.

signal detonated(at: Vector3)

@export var radius: float = 9.0
@export var disable_seconds: float = 15.0
@export var stun_seconds: float = 3.5
@export var fuse: float = 1.6

var _age: float = 0.0
var _done: bool = false
var _core: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER
	contact_monitor = true
	max_contacts_reported = 2
	mass = 0.6
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	shape.shape = sphere
	add_child(shape)
	GeometryKit.sphere(self, Vector3.ZERO, 0.12, MaterialLibrary.coated(Color(0.15, 0.16, 0.2), 0.8, 0.3))
	_core = MaterialLibrary.emissive(Color(0.5, 0.6, 1.0), 4.0, false)
	GeometryKit.cylinder(self, Vector3.ZERO, 0.125, 0.125, 0.04, _core, 12)


func _physics_process(delta: float) -> void:
	_age += delta
	_core.emission_energy_multiplier = 2.0 + 6.0 * absf(sin(_age * 18.0))
	if _done:
		return
	if _age >= fuse or (_age > 0.25 and get_contact_count() > 0):
		_detonate()


func _detonate() -> void:
	_done = true
	var at: Vector3 = global_position
	var parent: Node = get_parent()
	var devices: int = Electronics.disable_in_radius(get_tree(), at, radius, disable_seconds)
	var stunned: int = Electronics.emp_in_radius(get_tree(), at, radius, stun_seconds)
	HunterFX.flash(parent, at, Color(0.5, 0.6, 1.0), radius * 1.5)
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	shell.mesh = sphere
	var material := MaterialLibrary.hologram(Color(0.5, 0.65, 1.0), 0.35)
	shell.material_override = material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shell)
	shell.global_position = at
	var tween := shell.create_tween().set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE * radius, 0.45)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.6)
	tween.chain().tween_callback(shell.queue_free)
	Electronics.sparks(parent, at, Color(0.6, 0.7, 1.0))
	detonated.emit(at)
	print_verbose("EMP: %d devices, %d hunters" % [devices, stunned])
	queue_free()
