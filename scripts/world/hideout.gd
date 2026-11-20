class_name Hideout
extends Node3D
## The Runner's safehouse: a shielded concrete lock-up on the west verge. Inside, the Codex is
## masked (Dead Zone), so it's the place to sit out the dangerous daylight hours.
##   - Prep station (workbench): fabricate gear, buy upgrades, rest until dusk.
##   - Cot: rest until dusk (daytime only).
## The hideout only emits signals; main wires them to the PrepStationUI / TimeOfDay.

signal station_opened(actor: Node3D)
signal rest_requested(actor: Node3D)

const SIZE: Vector3 = Vector3(7.0, 3.4, 8.0)

var dead_zone: DeadZone
var station: Interactable
var cot: Interactable
## Set by main: whether resting is currently allowed (daytime).
var can_rest: Callable

var _screen: StandardMaterial3D
var _time: float = 0.0


func _ready() -> void:
	_build_shell()
	_build_interior()
	dead_zone = DeadZone.new()
	dead_zone.name = "DeadZone_SAFEHOUSE"
	dead_zone.zone_name = "SAFEHOUSE"
	dead_zone.size = Vector3(SIZE.x - 0.8, SIZE.y - 0.4, SIZE.z - 0.8)
	dead_zone.position = Vector3(0.0, SIZE.y * 0.5, 0.0)
	dead_zone.show_volume = false
	add_child(dead_zone)


func _process(delta: float) -> void:
	_time += delta
	if _screen != null:
		_screen.emission_energy_multiplier = 1.4 + 0.25 * sin(_time * 3.0)


func get_marker_position() -> Vector3:
	return to_global(Vector3(0.0, SIZE.y + 1.0, 0.0))


func _build_shell() -> void:
	var concrete := MaterialLibrary.concrete()
	var tint := Color(0.44, 0.43, 0.41)
	var hx: float = SIZE.x * 0.5
	var hz: float = SIZE.z * 0.5
	var wall: float = 0.4
	var door: float = 1.6
	var door_h: float = 2.4
	var parts: Array[MeshInstance3D] = []
	parts.append(GeometryKit.solid_box(self, Vector3(-hx + wall * 0.5, SIZE.y * 0.5, 0.0), Vector3(wall, SIZE.y, SIZE.z), concrete))
	parts.append(GeometryKit.solid_box(self, Vector3(0.0, SIZE.y * 0.5, -hz + wall * 0.5), Vector3(SIZE.x, SIZE.y, wall), concrete))
	parts.append(GeometryKit.solid_box(self, Vector3(0.0, SIZE.y * 0.5, hz - wall * 0.5), Vector3(SIZE.x, SIZE.y, wall), concrete))
	# East wall (facing the city) with the door.
	var segment: float = (SIZE.z - door) * 0.5
	for side: float in [-1.0, 1.0]:
		parts.append(GeometryKit.solid_box(self, Vector3(hx - wall * 0.5, SIZE.y * 0.5, side * (door * 0.5 + segment * 0.5)), Vector3(wall, SIZE.y, segment), concrete))
	parts.append(GeometryKit.solid_box(self, Vector3(hx - wall * 0.5, (door_h + SIZE.y) * 0.5, 0.0), Vector3(wall, SIZE.y - door_h, door), concrete))
	parts.append(GeometryKit.solid_box(self, Vector3(0.0, SIZE.y + 0.15, 0.0), Vector3(SIZE.x + 0.3, 0.3, SIZE.z + 0.3), concrete))
	for part: MeshInstance3D in parts:
		part.set_instance_shader_parameter(&"tint", tint)
	var floor_mesh := GeometryKit.solid_box(self, Vector3(0.0, 0.05, 0.0), Vector3(SIZE.x - wall * 2.0, 0.1, SIZE.z - wall * 2.0), MaterialLibrary.surface(Color(0.3, 0.3, 0.3), 0.6, 0.0, 0.6, 1.0))
	floor_mesh.name = "Floor"
	# Roller-door frame, cover sign and a dim security lamp outside.
	var frame := MaterialLibrary.coated(Color(0.2, 0.21, 0.22), 0.8, 0.4)
	GeometryKit.mesh_box(self, Vector3(hx + 0.02, door_h + 0.15, 0.0), Vector3(0.12, 0.3, door + 0.3), frame)
	var sign_label := Label3D.new()
	sign_label.double_sided = false
	sign_label.text = "STORAGE 07"
	sign_label.font_size = 48
	sign_label.pixel_size = 0.01
	sign_label.modulate = Color(0.85, 0.8, 0.6)
	sign_label.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	sign_label.position = Vector3(hx + 0.03, door_h + 0.6, 0.0)
	add_child(sign_label)
	GeometryKit.mesh_box(self, Vector3(hx + 0.1, door_h + 0.2, 1.3), Vector3(0.15, 0.12, 0.25), MaterialLibrary.emissive(Color(1.0, 0.7, 0.4), 4.0))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.4)
	lamp.light_energy = 1.2
	lamp.omni_range = 5.0
	lamp.position = Vector3(hx + 0.5, door_h, 1.3)
	add_child(lamp)


func _build_interior() -> void:
	var wood := MaterialLibrary.surface(Color(0.32, 0.22, 0.14), 0.75, 0.0, 1.2, 3.0)
	var steel := MaterialLibrary.coated(Color(0.16, 0.17, 0.19), 0.8, 0.35)
	var hz: float = SIZE.z * 0.5
	# Workbench prep station along the north wall.
	var bench := Vector3(-1.0, 0.0, -hz + 1.0)
	GeometryKit.solid_box(self, bench + Vector3(0.0, 0.85, 0.0), Vector3(3.2, 0.08, 1.0), wood)
	for x: float in [-1.5, 1.5]:
		GeometryKit.mesh_box(self, bench + Vector3(x, 0.42, 0.0), Vector3(0.08, 0.84, 0.9), steel)
	_screen = MaterialLibrary.emissive(Color(0.35, 0.85, 1.0), 1.4, false)
	for i: int in 3:
		var x: float = -0.9 + i * 0.9
		GeometryKit.mesh_box(self, bench + Vector3(x, 1.25, -0.35), Vector3(0.7, 0.42, 0.05), steel)
		GeometryKit.mesh_box(self, bench + Vector3(x, 1.25, -0.32), Vector3(0.64, 0.36, 0.01), _screen)
	GeometryKit.mesh_box(self, bench + Vector3(0.9, 0.95, 0.15), Vector3(0.4, 0.12, 0.3), MaterialLibrary.coated(Color(0.6, 0.45, 0.15), 0.9, 0.3))
	GeometryKit.mesh_box(self, bench + Vector3(-0.8, 0.92, 0.2), Vector3(0.5, 0.06, 0.25), MaterialLibrary.surface(Color(0.1, 0.1, 0.11), 0.4, 0.2, 0.0))
	var desk_light := OmniLight3D.new()
	desk_light.light_color = Color(1.0, 0.82, 0.6)
	desk_light.light_energy = 1.6
	desk_light.omni_range = 6.0
	desk_light.position = bench + Vector3(0.0, 2.2, 0.4)
	add_child(desk_light)
	GeometryKit.mesh_box(self, bench + Vector3(0.0, 2.4, 0.4), Vector3(0.6, 0.05, 0.2), MaterialLibrary.emissive(Color(1.0, 0.85, 0.65), 3.0))
	station = Interactable.new()
	station.name = "PrepStation"
	station.prompt = "Use the prep station"
	station.hold_time = 0.4
	station.radius = 2.0
	station.position = bench + Vector3(0.0, 0.0, 0.9)
	add_child(station)
	station.completed.connect(func(_i: Interactable, actor: Node3D) -> void: station_opened.emit(actor))

	# Cot along the south wall.
	var cot_at := Vector3(-1.6, 0.0, hz - 1.0)
	GeometryKit.solid_box(self, cot_at + Vector3(0.0, 0.35, 0.0), Vector3(2.0, 0.12, 0.85), steel)
	GeometryKit.mesh_box(self, cot_at + Vector3(0.0, 0.45, 0.0), Vector3(1.95, 0.1, 0.8), MaterialLibrary.fabric(Color(0.25, 0.3, 0.25)))
	GeometryKit.mesh_box(self, cot_at + Vector3(-0.75, 0.55, 0.0), Vector3(0.4, 0.1, 0.6), MaterialLibrary.fabric(Color(0.75, 0.74, 0.7)))
	cot = Interactable.new()
	cot.name = "Cot"
	cot.prompt = "Rest until dusk (skip the day)"
	cot.hold_time = 1.5
	cot.radius = 1.8
	cot.position = cot_at + Vector3(0.0, 0.0, -0.8)
	cot.requirement = func(_actor: Node3D) -> bool: return can_rest.is_valid() and bool(can_rest.call())
	cot.requirement_hint = "Too dangerous to sleep at night - the Hunters are out"
	add_child(cot)
	cot.completed.connect(func(_i: Interactable, actor: Node3D) -> void: rest_requested.emit(actor))

	# Map board, crates, a hanging bulb.
	GeometryKit.mesh_box(self, Vector3(-SIZE.x * 0.5 + 0.42, 1.7, -0.5), Vector3(0.04, 1.1, 1.8), MaterialLibrary.surface(Color(0.5, 0.42, 0.3), 0.9, 0.0, 1.0, 2.0))
	var board := Label3D.new()
	board.double_sided = false
	board.text = "MERIDIAN LABS\n+  HUNTER ROUTES\n+  RELAYS N/E/S/W"
	board.font_size = 24
	board.pixel_size = 0.006
	board.modulate = Color(0.15, 0.1, 0.08)
	board.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	board.position = Vector3(-SIZE.x * 0.5 + 0.45, 1.75, -0.5)
	add_child(board)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	PropFactory.crate(self, Vector3(2.2, 0.1, hz - 1.0), 0.9, rng)
	PropFactory.crate(self, Vector3(2.2, 1.0, hz - 1.0), 0.7, rng)
	var bulb := OmniLight3D.new()
	bulb.light_color = Color(1.0, 0.78, 0.5)
	bulb.light_energy = 1.0
	bulb.omni_range = 6.0
	bulb.position = Vector3(0.5, 2.9, 1.2)
	add_child(bulb)
	GeometryKit.sphere(self, Vector3(0.5, 2.95, 1.2), 0.07, MaterialLibrary.emissive(Color(1.0, 0.8, 0.55), 5.0))
