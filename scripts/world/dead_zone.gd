class_name DeadZone
extends Area3D
## Signal-masking volume (tunnels, interiors).
## While the Runner is inside, Codex Ignition broadcasts are suppressed, Residual Echo
## drops halt and Resonance decay is multiplied. The zone only reports enter/exit via
## signals; the composition root connects them to the CodexSignalSystem.

signal runner_entered(zone: DeadZone)
signal runner_exited(zone: DeadZone)

const RUNNER_GROUP: StringName = &"runner"

@export var size: Vector3 = Vector3(10.0, 5.0, 20.0)
@export var zone_name: String = "Dead Zone"
@export var show_volume: bool = true


func _ready() -> void:
	collision_layer = 16
	collision_mask = 2
	monitoring = true
	monitorable = false

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	if show_volume:
		_build_visuals()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _build_visuals() -> void:
	var volume := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	volume.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.35, 0.2, 0.8, 0.08)
	volume.material_override = material
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(volume)

	var label := Label3D.new()
	label.text = "DEAD ZONE\n%s" % zone_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.7, 0.55, 1.0)
	label.outline_size = 8
	label.font_size = 48
	label.pixel_size = 0.01
	label.position = Vector3(0.0, size.y * 0.5 - 0.6, 0.0)
	add_child(label)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(RUNNER_GROUP):
		runner_entered.emit(self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group(RUNNER_GROUP):
		runner_exited.emit(self)
