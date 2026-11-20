class_name UplinkStation
extends Node3D
## Dormant relay mast on the city edge. Exactly one station per run is genuine: only that one
## can carry the Codex to safety, and only Hunters know which one it is (they sweep it).
## Visual states: dormant (red), handshake (blue pulses while a Hunter scans it),
## revealed (green), transmitting (rising beam).

@export var station_label: String = "RELAY"

var is_genuine: bool = false
var revealed: bool = false
var interactable: Interactable

var _status_material: StandardMaterial3D
var _status_light: OmniLight3D
var _beam: MeshInstance3D
var _beam_material: StandardMaterial3D
var _dish: Node3D
var _handshake: bool = false
var _transmit: float = -1.0
var _time: float = 0.0


func _ready() -> void:
	_build()
	interactable = Interactable.new()
	interactable.name = "UplinkInteract"
	interactable.prompt = "Begin uplink transmission"
	interactable.hold_time = 1.0
	interactable.radius = 3.2
	interactable.position = Vector3(0.0, 0.0, 2.2)
	add_child(interactable)
	_set_status(Color(1.0, 0.15, 0.1), 2.0)


func _process(delta: float) -> void:
	_time += delta
	_dish.rotation.y = sin(_time * 0.2) * 0.6
	if _transmit >= 0.0:
		var pulse: float = 0.6 + 0.4 * sin(_time * 8.0)
		_beam.visible = true
		_beam.scale = Vector3(1.0 + _transmit, 1.0, 1.0 + _transmit)
		_beam_material.albedo_color = Color(0.4, 1.0, 0.6, (0.08 + 0.25 * _transmit) * pulse)
		_status_light.light_energy = 3.0 + 3.0 * pulse
	elif _handshake:
		var blink: float = step_pulse(_time * 3.0)
		_set_status(Color(0.25, 0.55, 1.0), 1.0 + 5.0 * blink)
		_status_light.light_energy = 1.0 + 4.0 * blink


static func step_pulse(t: float) -> float:
	return 1.0 if fmod(t, 1.0) < 0.35 else 0.0


func set_handshake(active: bool) -> void:
	_handshake = active
	if not active:
		_restore_status()


func set_revealed() -> void:
	revealed = true
	_restore_status()


func set_transmission(progress: float) -> void:
	_transmit = progress
	if progress < 0.0:
		_beam.visible = false
		_restore_status()
	else:
		_set_status(Color(0.3, 1.0, 0.55), 6.0)


func get_marker_position() -> Vector3:
	return global_position + Vector3(0.0, 4.0, 0.0)


func _restore_status() -> void:
	if revealed:
		_set_status(Color(0.3, 1.0, 0.45), 4.0)
	else:
		_set_status(Color(1.0, 0.15, 0.1), 2.0)


func _set_status(color: Color, energy: float) -> void:
	_status_material.albedo_color = color
	_status_material.emission = color
	_status_material.emission_energy_multiplier = energy
	_status_light.light_color = color


func _build() -> void:
	var pad := GeometryKit.solid_box(self, Vector3(0.0, 0.1, 0.0), Vector3(7.0, 0.2, 7.0), MaterialLibrary.concrete())
	pad.set_instance_shader_parameter(&"tint", Color(0.45, 0.45, 0.43))
	var steel := MaterialLibrary.coated(Color(0.55, 0.57, 0.6), 0.9, 0.35)
	var red_white := MaterialLibrary.coated(Color(0.75, 0.12, 0.08), 0.4, 0.45)

	# Lattice mast (4 tapering legs + bracing).
	var mast_h: float = 14.0
	GeometryKit.collider_box(self, Vector3(0.0, mast_h * 0.5, 0.0), Vector3(1.6, mast_h, 1.6))
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			GeometryKit.tilted_box(self, Vector3(x * 0.55, mast_h * 0.5, z * 0.55), Vector3(0.09, mast_h, 0.09), Vector3(z * 1.4, 0.0, -x * 1.4), steel)
	for i: int in 7:
		var y: float = 1.0 + i * 1.9
		var w: float = 1.5 - i * 0.07
		var mat: Material = red_white if i % 2 == 0 else steel
		GeometryKit.mesh_box(self, Vector3(0.0, y, w * 0.5), Vector3(w, 0.06, 0.06), mat)
		GeometryKit.mesh_box(self, Vector3(0.0, y, -w * 0.5), Vector3(w, 0.06, 0.06), mat)
		GeometryKit.mesh_box(self, Vector3(w * 0.5, y, 0.0), Vector3(0.06, 0.06, w), mat)
		GeometryKit.mesh_box(self, Vector3(-w * 0.5, y, 0.0), Vector3(0.06, 0.06, w), mat)
		GeometryKit.tilted_box(self, Vector3(0.0, y + 0.95, w * 0.5), Vector3(0.04, 2.2, 0.04), Vector3(0.0, 0.0, 38.0), steel)
		GeometryKit.tilted_box(self, Vector3(w * 0.5, y + 0.95, 0.0), Vector3(0.04, 2.2, 0.04), Vector3(38.0, 0.0, 0.0), steel)
	PropFactory.antenna(self, Vector3(0.0, mast_h, 0.0), 3.0)

	# Dish.
	_dish = Node3D.new()
	_dish.position = Vector3(0.0, 10.0, 0.0)
	add_child(_dish)
	var dish := GeometryKit.cylinder(_dish, Vector3(0.0, 0.0, -0.9), 1.3, 0.25, 0.45, MaterialLibrary.coated(Color(0.85, 0.86, 0.85), 0.4, 0.35), 24)
	dish.rotation_degrees = Vector3(-70.0, 0.0, 0.0)
	GeometryKit.mesh_box(_dish, Vector3(0.0, 0.0, -0.45), Vector3(0.12, 0.12, 0.9), steel)

	# Equipment cabinets with blinking status LEDs.
	for x: float in [-2.2, 2.2]:
		var cab := GeometryKit.solid_box(self, Vector3(x, 1.1, -1.8), Vector3(1.4, 1.8, 0.9), MaterialLibrary.metal_panel())
		cab.set_instance_shader_parameter(&"paint_color", Color(0.6, 0.62, 0.6))
		for i: int in 3:
			GeometryKit.mesh_box(self, Vector3(x - 0.4 + i * 0.2, 1.7, -1.34), Vector3(0.06, 0.06, 0.02), MaterialLibrary.emissive(Color(0.2, 1.0, 0.4) if i != 1 else Color(1.0, 0.6, 0.1), 3.0))

	# Chain-link fence with a gate gap on the south side.
	var post_mat := MaterialLibrary.coated(Color(0.4, 0.42, 0.44), 0.9, 0.4)
	var mesh_mat := MaterialLibrary.hologram(Color(0.6, 0.65, 0.7), 0.12)
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for side: int in 4:
		for i: int in 5:
			var t: float = -3.4 + i * 1.7
			var p: Vector3
			match side:
				0:
					p = Vector3(t, 1.0, -3.4)
				1:
					p = Vector3(3.4, 1.0, t)
				2:
					p = Vector3(-3.4, 1.0, t)
				_:
					p = Vector3(t, 1.0, 3.4)
			GeometryKit.mesh_box(self, p, Vector3(0.06, 2.0, 0.06), post_mat)
	GeometryKit.mesh_box(self, Vector3(0.0, 1.0, -3.4), Vector3(6.8, 1.8, 0.02), mesh_mat)
	GeometryKit.mesh_box(self, Vector3(3.4, 1.0, 0.0), Vector3(0.02, 1.8, 6.8), mesh_mat)
	GeometryKit.mesh_box(self, Vector3(-3.4, 1.0, 0.0), Vector3(0.02, 1.8, 6.8), mesh_mat)
	for x: float in [-2.6, 2.6]:
		GeometryKit.mesh_box(self, Vector3(x, 1.0, 3.4), Vector3(1.6, 1.8, 0.02), mesh_mat)

	var plate := Label3D.new()
	plate.double_sided = false
	plate.text = "%s\nDORMANT RELAY" % station_label
	plate.font_size = 40
	plate.pixel_size = 0.01
	plate.modulate = Color(0.9, 0.9, 0.85)
	plate.position = Vector3(0.0, 2.2, -1.34)
	plate.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	add_child(plate)

	_status_material = MaterialLibrary.emissive(Color(1.0, 0.15, 0.1), 2.0, false)
	GeometryKit.sphere(self, Vector3(0.0, mast_h + 3.1, 0.0), 0.18, _status_material)
	GeometryKit.mesh_box(self, Vector3(0.0, 2.6, -1.3), Vector3(0.6, 0.12, 0.05), _status_material)
	_status_light = OmniLight3D.new()
	_status_light.light_energy = 2.0
	_status_light.omni_range = 9.0
	_status_light.position = Vector3(0.0, 3.0, 0.0)
	add_child(_status_light)

	_beam_material = MaterialLibrary.hologram(Color(0.4, 1.0, 0.6), 0.1)
	_beam = MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.6
	beam_mesh.bottom_radius = 0.6
	beam_mesh.height = 120.0
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	_beam.mesh = beam_mesh
	_beam.material_override = _beam_material
	_beam.position = Vector3(0.0, 60.0, 0.0)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
