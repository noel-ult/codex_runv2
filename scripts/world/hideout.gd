class_name Hideout
extends Node3D
## The Runner's safehouse: a shielded concrete lock-up on the west verge. Inside, the Codex is
## masked (Dead Zone), so it's the place to sit out the dangerous daylight hours.
##   - Prep station (workbench): fabricate gear, buy upgrades, rest until dusk.
##   - Cot: rest until dusk by day, or wait for morning overnight.
##   - Packet decoder: process a copied HunterNet packet while in shelter.
## Main wires these interactions into their respective systems.

signal station_opened(actor: Node3D)
signal rest_requested(actor: Node3D)
signal morning_requested(actor: Node3D)

const SIZE: Vector3 = Vector3(7.0, 3.4, 8.0)
const WALL_THICKNESS: float = 0.4
const SHIELD_INSET: Vector3 = Vector3(WALL_THICKNESS, 0.2, WALL_THICKNESS)
const DECODER_MOUNT: Vector3 = Vector3(-2.94, 1.16, 1.0)

var dead_zone: DeadZone
var station: Interactable
var cot: Interactable
var decoder: Interactable
## Set by main: whether resting is currently allowed (daytime).
var can_rest: Callable

var _screen: StandardMaterial3D
var _decoder_indicator: StandardMaterial3D
var _time: float = 0.0
var _cot_released: bool = true


func _ready() -> void:
	_build_shell()
	_build_interior()
	_build_decoder()
	dead_zone = DeadZone.new()
	dead_zone.name = "DeadZone_SAFEHOUSE"
	dead_zone.zone_name = "SAFEHOUSE"
	dead_zone.size = SIZE - SHIELD_INSET * 2.0
	dead_zone.position = Vector3(0.0, SIZE.y * 0.5, 0.0)
	dead_zone.show_volume = false
	add_child(dead_zone)


func _process(delta: float) -> void:
	_time += delta
	if _screen != null:
		_screen.emission_energy_multiplier = 1.4 + 0.25 * sin(_time * 3.0)
	_decoder_indicator.emission_energy_multiplier = 3.0 + 0.45 * sin(_time * 4.0) if decoder.enabled else 0.35
	if cot != null:
		if not Input.is_action_pressed(&"interact"):
			_cot_released = true
		cot.prompt = "Rest until dusk (19:00)" if can_rest.is_valid() and bool(can_rest.call()) else "Wait until morning (06:00)"
		cot.requirement_hint = "Release E before resting again" if not _cot_released else "Leave the vehicle to use the cot"


func get_marker_position() -> Vector3:
	return to_global(Vector3(0.0, SIZE.y + 1.0, 0.0))


## Check immediately in local space, including on the frame an actor is teleported.
func protects_runner(actor: Node3D) -> bool:
	if not is_instance_valid(actor):
		return false
	var local: Vector3 = to_local(actor.global_position)
	var extent: Vector3 = SIZE * 0.5 - SHIELD_INSET
	return absf(local.x) < extent.x and absf(local.z) < extent.z and local.y >= 0.0 and local.y < SIZE.y - SHIELD_INSET.y


func get_decoder_marker_position() -> Vector3:
	return to_global(DECODER_MOUNT + Vector3(0.24, 0.87, 0.0))


func get_checkpoint_position() -> Vector3:
	return to_global(Vector3(0.0, 0.2, 0.0))


func _build_shell() -> void:
	var concrete := MaterialLibrary.concrete()
	var tint := Color(0.44, 0.43, 0.41)
	var hx: float = SIZE.x * 0.5
	var hz: float = SIZE.z * 0.5
	var wall: float = WALL_THICKNESS
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
	cot.requirement = func(actor: Node3D) -> bool:
		var runner: PlayerController = actor as PlayerController
		return runner != null and not runner.is_driving() and runner.input_enabled and _cot_released
	cot.requirement_hint = "Leave the vehicle to use the cot"
	add_child(cot)
	cot.completed.connect(_on_cot_completed)

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


func _on_cot_completed(port: Interactable, actor: Node3D) -> void:
	if not port.is_available_for(actor) or not port.meets_requirement(actor):
		return
	_cot_released = false
	if can_rest.is_valid() and bool(can_rest.call()):
		rest_requested.emit(actor)
	else:
		morning_requested.emit(actor)


func _build_decoder() -> void:
	# The west wall mount leaves the central aisle clear of the bench and cot.
	var steel: StandardMaterial3D = MaterialLibrary.coated(Color(0.13, 0.17, 0.17), 0.8, 0.42)
	var face: StandardMaterial3D = MaterialLibrary.coated(Color(0.23, 0.31, 0.3), 0.45, 0.45)
	var glass: StandardMaterial3D = MaterialLibrary.surface(Color(0.025, 0.065, 0.07), 0.35, 0.2, 0.0)
	_decoder_indicator = MaterialLibrary.emissive(Color(0.25, 1.0, 0.76), 0.35, false)
	GeometryKit.mesh_box(self, DECODER_MOUNT, Vector3(0.30, 0.43, 0.68), steel)
	GeometryKit.mesh_box(self, DECODER_MOUNT + Vector3(0.156, 0.0, 0.0), Vector3(0.035, 0.39, 0.64), face)
	GeometryKit.mesh_box(self, DECODER_MOUNT + Vector3(0.176, 0.055, 0.02), Vector3(0.013, 0.18, 0.46), glass)
	GeometryKit.mesh_box(self, DECODER_MOUNT + Vector3(0.186, 0.055, 0.02), Vector3(0.007, 0.025, 0.36), _decoder_indicator)
	GeometryKit.mesh_box(self, DECODER_MOUNT + Vector3(0.176, -0.115, 0.08), Vector3(0.014, 0.043, 0.28), steel)
	GeometryKit.mesh_box(self, DECODER_MOUNT + Vector3(0.177, -0.115, -0.18), Vector3(0.014, 0.037, 0.047), _decoder_indicator)
	var sign_label := Label3D.new()
	sign_label.double_sided = false
	sign_label.text = "HUNTERNET DECODER"
	sign_label.font_size = 27
	sign_label.pixel_size = 0.0036
	sign_label.modulate = Color(0.72, 0.94, 0.86)
	sign_label.rotation_degrees.y = 90.0
	sign_label.position = DECODER_MOUNT + Vector3(0.18, 0.31, 0.0)
	add_child(sign_label)

	decoder = Interactable.new()
	decoder.name = "PacketDecoder"
	decoder.prompt = "Decode the HunterNet packet"
	decoder.hold_time = 0.6
	decoder.radius = 0.9
	decoder.height_tolerance = 0.6
	decoder.position = Vector3(-2.13, 0.64, 0.76)
	decoder.requirement = protects_runner
	decoder.enabled = false
	add_child(decoder)
