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
	# Signal-masking haze (volumetric fog volume tinted violet).
	var haze := FogVolume.new()
	haze.size = size
	haze.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var fog := FogMaterial.new()
	fog.density = 0.05
	fog.albedo = Color(0.55, 0.45, 0.85)
	fog.emission = Color(0.05, 0.02, 0.1)
	fog.edge_fade = 0.4
	haze.material = fog
	add_child(haze)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(RUNNER_GROUP):
		runner_entered.emit(self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group(RUNNER_GROUP):
		runner_exited.emit(self)
