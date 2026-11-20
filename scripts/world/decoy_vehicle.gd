class_name DecoyVehicle
extends AnimatableBody3D
## NPC vehicle that drives along its parent PathFollow3D.
## Implements the CodexSignalSystem "fracture beacon" contract: when a Codex ability is
## fractured onto it, it becomes a fake Codex signal (beacon) until the Runner touches it.

signal runner_contact(vehicle: DecoyVehicle)
signal beacon_changed(vehicle: DecoyVehicle, active: bool, ability: StringName)

const RUNNER_GROUP: StringName = &"runner"
const FRACTURE_GROUP: StringName = &"fracture_targets"

@export var display_name: String = "Vehicle"
@export var speed: float = 9.0
@export var body_color: Color = Color(0.8, 0.6, 0.2)
## Seconds after fracturing before touching the vehicle re-absorbs the ability.
@export var contact_grace: float = 2.0

var fractured_ability: StringName = &""

var _follow: PathFollow3D
var _touch_area: Area3D
var _beacon_root: Node3D
var _beacon_material: StandardMaterial3D
var _beacon_light: OmniLight3D
var _beacon_label: Label3D
var _beacon_time: float = 0.0


func _ready() -> void:
	add_to_group(FRACTURE_GROUP)
	collision_layer = 8
	collision_mask = 0
	sync_to_physics = true
	_follow = get_parent() as PathFollow3D
	_build_body()
	_build_touch_area()
	_build_beacon()


func _physics_process(delta: float) -> void:
	if _follow != null:
		_follow.progress += speed * delta
	if not is_beacon_active():
		return
	_beacon_time += delta
	var pulse: float = 0.5 + 0.5 * sin(_beacon_time * 5.0)
	_beacon_material.albedo_color.a = 0.25 + 0.25 * pulse
	_beacon_light.light_energy = 3.0 + 3.0 * pulse
	if _beacon_time < contact_grace:
		return
	for body: Node3D in _touch_area.get_overlapping_bodies():
		if body.is_in_group(RUNNER_GROUP):
			runner_contact.emit(self)
			return


# --- Fracture beacon contract ------------------------------------------------------

func attach_fractured_ability(ability: StringName, color: Color) -> void:
	fractured_ability = ability
	_beacon_time = 0.0
	_beacon_material.albedo_color = Color(color, 0.4)
	_beacon_material.emission = color
	_beacon_light.light_color = color
	_beacon_label.text = "FAKE CODEX\n%s" % CodexSignalSystem.get_ability_display_name(ability)
	_beacon_label.modulate = color
	_beacon_root.visible = true
	beacon_changed.emit(self, true, ability)


func release_fractured_ability() -> void:
	var previous: StringName = fractured_ability
	fractured_ability = &""
	_beacon_root.visible = false
	beacon_changed.emit(self, false, previous)


func is_beacon_active() -> bool:
	return fractured_ability != &""


func get_display_name() -> String:
	return display_name


# --- Procedural visuals --------------------------------------------------------------

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.3, 1.7, 4.6)
	shape.shape = box
	shape.position = Vector3(0.0, 0.95, 0.0)
	add_child(shape)

	_add_mesh(Vector3(2.3, 1.0, 4.6), Vector3(0.0, 0.7, 0.0), _material(body_color, 0.0))
	_add_mesh(Vector3(2.0, 0.8, 2.4), Vector3(0.0, 1.6, 0.3), _material(body_color.darkened(0.35), 0.0))
	_add_mesh(Vector3(1.9, 0.5, 0.05), Vector3(0.0, 1.65, -0.92), _material(Color(0.5, 0.8, 1.0), 0.6))
	for side: float in [-0.75, 0.75]:
		_add_mesh(Vector3(0.4, 0.2, 0.05), Vector3(side, 0.8, -2.31), _material(Color(1.0, 0.95, 0.7), 4.0))
		_add_mesh(Vector3(0.4, 0.2, 0.05), Vector3(side, 0.8, 2.31), _material(Color(1.0, 0.1, 0.1), 3.0))
	for x: float in [-1.15, 1.15]:
		for z: float in [-1.5, 1.5]:
			var wheel := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.4
			cylinder.bottom_radius = 0.4
			cylinder.height = 0.3
			wheel.mesh = cylinder
			wheel.material_override = _material(Color(0.05, 0.05, 0.05), 0.0)
			wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			wheel.position = Vector3(x, 0.4, z)
			add_child(wheel)

	var name_label := Label3D.new()
	name_label.text = display_name
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 36
	name_label.pixel_size = 0.01
	name_label.outline_size = 6
	name_label.position = Vector3(0.0, 2.5, 0.0)
	add_child(name_label)


func _build_touch_area() -> void:
	_touch_area = Area3D.new()
	_touch_area.collision_layer = 0
	_touch_area.collision_mask = 2
	_touch_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 2.8, 6.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.2, 0.0)
	_touch_area.add_child(shape)
	add_child(_touch_area)


func _build_beacon() -> void:
	_beacon_root = Node3D.new()
	_beacon_root.visible = false
	add_child(_beacon_root)

	_beacon_material = StandardMaterial3D.new()
	_beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_material.emission_enabled = true
	_beacon_material.emission_energy_multiplier = 3.0
	var pillar := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.6
	cylinder.bottom_radius = 1.0
	cylinder.height = 40.0
	pillar.mesh = cylinder
	pillar.material_override = _beacon_material
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.position = Vector3(0.0, 21.0, 0.0)
	_beacon_root.add_child(pillar)

	_beacon_light = OmniLight3D.new()
	_beacon_light.omni_range = 14.0
	_beacon_light.position = Vector3(0.0, 3.0, 0.0)
	_beacon_root.add_child(_beacon_light)

	_beacon_label = Label3D.new()
	_beacon_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_beacon_label.font_size = 64
	_beacon_label.pixel_size = 0.012
	_beacon_label.outline_size = 10
	_beacon_label.no_depth_test = true
	_beacon_label.position = Vector3(0.0, 4.2, 0.0)
	_beacon_root.add_child(_beacon_label)


func _add_mesh(size: Vector3, offset: Vector3, material: StandardMaterial3D) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	instance.position = offset
	add_child(instance)


func _material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material
