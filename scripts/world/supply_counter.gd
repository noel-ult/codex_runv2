class_name SupplyCounter
extends Node3D
## Street-side supply counter. The inventory and credits live in the shop and economy nodes.

signal shop_requested(actor: Node3D)

var interactable: Interactable


func _ready() -> void:
	var shell: StandardMaterial3D = MaterialLibrary.coated(Color(0.08, 0.17, 0.19), 0.55, 0.36)
	var trim: StandardMaterial3D = MaterialLibrary.coated(Color(0.23, 0.35, 0.35), 0.7, 0.28)
	var display: StandardMaterial3D = MaterialLibrary.emissive(Color(0.22, 0.9, 0.72), 2.6)
	var amber: StandardMaterial3D = MaterialLibrary.emissive(Color(1.0, 0.64, 0.23), 2.3)
	GeometryKit.collider_box(self, Vector3(0.0, 0.6, 0.0), Vector3(0.86, 1.2, 1.45))
	GeometryKit.mesh_box(self, Vector3(0.0, 0.6, 0.0), Vector3(0.86, 1.2, 1.45), shell)
	GeometryKit.mesh_box(self, Vector3(-0.46, 0.94, 0.0), Vector3(0.07, 0.78, 1.19), trim)
	GeometryKit.mesh_box(self, Vector3(-0.51, 1.0, 0.0), Vector3(0.02, 0.52, 0.96), display)
	GeometryKit.mesh_box(self, Vector3(0.0, 1.43, 0.0), Vector3(1.0, 0.15, 1.65), trim)
	GeometryKit.mesh_box(self, Vector3(-0.47, 1.34, 0.0), Vector3(0.06, 0.045, 1.35), amber)
	for index: int in 3:
		var z: float = -0.34 + float(index) * 0.34
		GeometryKit.mesh_box(self, Vector3(-0.526, 0.84, z), Vector3(0.02, 0.06, 0.17), shell)
	var sign: Label3D = Label3D.new()
	sign.text = "SUPPLY / AMMUNITION\nDARTS  ·  EMP  ·  CELLS"
	sign.font_size = 29
	sign.pixel_size = 0.005
	sign.modulate = Color(0.86, 1.0, 0.94)
	sign.outline_modulate = Color(0.01, 0.06, 0.07)
	sign.rotation_degrees.y = -90.0
	sign.position = Vector3(-0.52, 1.73, 0.0)
	add_child(sign)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.light_color = Color(0.25, 1.0, 0.8)
	lamp.light_energy = 0.7
	lamp.omni_range = 4.5
	lamp.position = Vector3(-0.3, 1.6, 0.0)
	add_child(lamp)
	interactable = Interactable.new()
	interactable.name = "SupplyCounterInteraction"
	interactable.prompt = "Browse supplies"
	interactable.hold_time = 0.5
	interactable.radius = 1.7
	interactable.position = Vector3(-0.85, 0.45, 0.0)
	interactable.requirement = _can_shop
	interactable.requirement_hint = "Leave the vehicle to shop"
	add_child(interactable)
	interactable.completed.connect(_on_completed)


func get_marker_position() -> Vector3:
	return to_global(Vector3(0.0, 2.1, 0.0))


func _can_shop(actor: Node3D) -> bool:
	var runner: PlayerController = actor as PlayerController
	if runner == null or runner.is_driving() or not runner.input_enabled:
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		runner.get_head_position(), interactable.global_position + Vector3.UP * 0.6,
		GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER, [runner.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_completed(port: Interactable, actor: Node3D) -> void:
	if port.is_available_for(actor) and _can_shop(actor):
		shop_requested.emit(actor)
