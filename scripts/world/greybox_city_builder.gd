class_name GreyboxCityBuilder
extends Node3D
## Procedurally builds the night-time city at runtime and bakes navigation for it.
##
## Layout (top-down, metres): a 2x2 grid of 44 m city blocks separated by 14 m centre
## streets and wrapped by a 14 m ring road, with a verge and four uplink relays beyond it.
## - NW: brick residential towers with fire escapes around cross alleys.
## - NE: Meridian Signal Labs - the guarded facility holding the Uplink Key.
## - SW: industrial warehouse (Dead Zone 1) + tower + sheds.
## - SE: commercial block with glass office tower and a rooftop bridge.
## - East ring road: covered tunnel (Dead Zone 2).
## - 3 traffic vehicles loop on Path3D routes; parked cars, lamps, trees and street furniture.
## This node must be a child of a NavigationRegion3D; it bakes the parent after building.

signal city_built()

const BLOCK_SIZE: float = 44.0
const STREET_WIDTH: float = 14.0
const RING_WIDTH: float = 14.0
const MAP_HALF_EXTENT: float = 75.0
const ALLEY: float = 5.0
const SIDEWALK_HEIGHT: float = 0.1

@export var random_seed: int = 1337

var dead_zones: Array[DeadZone] = []
var traffic_vehicles: Array[TrafficVehicle] = []
var uplink_stations: Array[UplinkStation] = []
var facility: FacilityCompound
var npcs: Array[NpcWalker] = []
var patrol_points: Array[Vector3] = []
var hunter_spawn_points: Array[Vector3] = []
var player_spawn_point: Vector3 = Vector3(0.0, 0.2, 29.0)

var _rng := RandomNumberGenerator.new()
var _geometry: Node3D


func _ready() -> void:
	_rng.seed = random_seed
	_geometry = Node3D.new()
	_geometry.name = "Geometry"
	add_child(_geometry)

	_build_ground()
	_build_road_markings()
	_build_blocks()
	_build_facility()
	_build_tunnel()
	_build_perimeter_and_skyline()
	_build_street_furniture()
	_build_parked_cars()
	_build_uplinks()
	_build_pickups()
	_build_vehicle_routes()
	_collect_points()
	_bake_navigation()
	_spawn_npcs()
	city_built.emit()


# --- Layout helpers ------------------------------------------------------------------

func _block_center(ix: int, iz: int) -> Vector3:
	var offset: float = BLOCK_SIZE * 0.5 + STREET_WIDTH * 0.5
	return Vector3(offset * float(ix), 0.0, offset * float(iz))


func _ring_inner() -> float:
	return STREET_WIDTH * 0.5 + BLOCK_SIZE


func _ring_mid() -> float:
	return _ring_inner() + RING_WIDTH * 0.5


# --- Ground, sidewalks, markings -----------------------------------------------------------

func _build_ground() -> void:
	var size: float = MAP_HALF_EXTENT * 2.0
	GeometryKit.solid_box(_geometry, Vector3(0.0, -0.5, 0.0), Vector3(size, 1.0, size), MaterialLibrary.asphalt())

	var grass := MaterialLibrary.surface(Color(0.09, 0.13, 0.07), 0.95, 0.0, 1.6, 0.5)
	var ring_outer: float = _ring_inner() + RING_WIDTH
	var verge: float = MAP_HALF_EXTENT - ring_outer
	for sign_value: float in [-1.0, 1.0]:
		var c: float = sign_value * (ring_outer + verge * 0.5)
		GeometryKit.mesh_box(_geometry, Vector3(0.0, 0.01, c), Vector3(size, 0.02, verge), grass, false)
		GeometryKit.mesh_box(_geometry, Vector3(c, 0.012, 0.0), Vector3(verge, 0.02, size), grass, false)
		var kerb_a := GeometryKit.mesh_box(_geometry, Vector3(0.0, 0.06, sign_value * (ring_outer + 0.15)), Vector3(ring_outer * 2.0, 0.12, 0.3), MaterialLibrary.concrete())
		kerb_a.set_instance_shader_parameter(&"tint", Color(0.55, 0.54, 0.52))
		var kerb_b := GeometryKit.mesh_box(_geometry, Vector3(sign_value * (ring_outer + 0.15), 0.06, 0.0), Vector3(0.3, 0.12, ring_outer * 2.0), MaterialLibrary.concrete())
		kerb_b.set_instance_shader_parameter(&"tint", Color(0.55, 0.54, 0.52))

	for ix: int in [-1, 1]:
		for iz: int in [-1, 1]:
			if ix == 1 and iz == -1:
				continue
			var center: Vector3 = _block_center(ix, iz)
			GeometryKit.solid_box(_geometry, center + Vector3(0.0, SIDEWALK_HEIGHT * 0.5, 0.0), Vector3(BLOCK_SIZE, SIDEWALK_HEIGHT, BLOCK_SIZE), MaterialLibrary.pavement())
			_add_kerb_frame(center, BLOCK_SIZE)


func _add_kerb_frame(center: Vector3, size: float) -> void:
	var kerb := MaterialLibrary.concrete()
	var half: float = size * 0.5
	for side: float in [-1.0, 1.0]:
		var a := GeometryKit.mesh_box(_geometry, center + Vector3(0.0, SIDEWALK_HEIGHT * 0.5 + 0.005, side * (half - 0.12)), Vector3(size, SIDEWALK_HEIGHT + 0.01, 0.25), kerb)
		a.set_instance_shader_parameter(&"tint", Color(0.6, 0.59, 0.56))
		var b := GeometryKit.mesh_box(_geometry, center + Vector3(side * (half - 0.12), SIDEWALK_HEIGHT * 0.5 + 0.005, 0.0), Vector3(0.25, SIDEWALK_HEIGHT + 0.01, size), kerb)
		b.set_instance_shader_parameter(&"tint", Color(0.6, 0.59, 0.56))


func _paint(center: Vector3, size: Vector3, color: Color) -> void:
	var stripe := GeometryKit.mesh_box(_geometry, center, size, MaterialLibrary.road_paint(), false)
	stripe.set_instance_shader_parameter(&"paint", color)


func _build_road_markings() -> void:
	var white := Color(0.85, 0.85, 0.8)
	var yellow := Color(0.85, 0.65, 0.12)
	var ring_mid: float = _ring_mid()
	var inner: float = _ring_inner()
	var y: float = 0.012
	# Ring road: double yellow centre line + dashed lane edges.
	for side: float in [-1.0, 1.0]:
		for off: float in [-0.15, 0.15]:
			_paint(Vector3(0.0, y, side * (ring_mid + off)), Vector3(inner * 2.0 + RING_WIDTH, 0.01, 0.1), yellow)
			_paint(Vector3(side * (ring_mid + off), y, 0.0), Vector3(0.1, 0.01, inner * 2.0 + RING_WIDTH), yellow)
	# Centre streets: dashed white centre lines.
	var dash_len: float = 3.0
	var t: float = -inner + 2.0
	while t < inner - 2.0:
		if absf(t) > STREET_WIDTH * 0.5 + 3.0:
			_paint(Vector3(t, y, 0.0), Vector3(dash_len, 0.01, 0.15), white)
			_paint(Vector3(0.0, y, t), Vector3(0.15, 0.01, dash_len), white)
		t += dash_len * 2.0
	# Crosswalks at the central intersection and the four ring junctions.
	var half_street: float = STREET_WIDTH * 0.5
	_crosswalk(Vector3(0.0, y, -half_street - 1.6), true)
	_crosswalk(Vector3(0.0, y, half_street + 1.6), true)
	_crosswalk(Vector3(-half_street - 1.6, y, 0.0), false)
	_crosswalk(Vector3(half_street + 1.6, y, 0.0), false)
	_crosswalk(Vector3(0.0, y, -inner + 1.6), true)
	_crosswalk(Vector3(0.0, y, inner - 1.6), true)
	_crosswalk(Vector3(-inner + 1.6, y, 0.0), false)
	_crosswalk(Vector3(inner - 1.6, y, 0.0), false)


func _crosswalk(center: Vector3, across_x: bool) -> void:
	var white := Color(0.88, 0.88, 0.84)
	for i: int in 7:
		var o: float = -5.4 + i * 1.8
		if across_x:
			_paint(center + Vector3(o, 0.0, 0.0), Vector3(0.9, 0.01, 3.0), white)
		else:
			_paint(center + Vector3(0.0, 0.0, o), Vector3(3.0, 0.01, 0.9), white)


# --- City blocks -----------------------------------------------------------------------------

func _build_blocks() -> void:
	var half_lot: float = (BLOCK_SIZE - 6.0 - ALLEY) * 0.25
	var lot: float = half_lot * 2.0
	var lot_offset: float = half_lot + ALLEY * 0.5
	var full: float = BLOCK_SIZE - 6.0
	var base_y: float = SIDEWALK_HEIGHT

	# North-west: brick residential towers on a cross of alleys, fire escapes facing the alleys.
	var nw: Vector3 = _block_center(-1, -1) + Vector3(0.0, base_y, 0.0)
	BuildingFactory.building(_geometry, nw + Vector3(-lot_offset, 0.0, -lot_offset), Vector2(lot, lot), 12.0, BuildingFactory.Style.BRICK, _rng, true, 0)
	BuildingFactory.building(_geometry, nw + Vector3(lot_offset, 0.0, -lot_offset), Vector2(lot, lot), 18.6, BuildingFactory.Style.BRICK, _rng, true, 3)
	BuildingFactory.building(_geometry, nw + Vector3(-lot_offset, 0.0, lot_offset), Vector2(lot, lot), 9.0, BuildingFactory.Style.BRICK, _rng, true, 2)
	BuildingFactory.building(_geometry, nw + Vector3(lot_offset, 0.0, lot_offset), Vector2(lot, lot), 7.6, BuildingFactory.Style.CONCRETE, _rng, true, -1, false)
	BuildingFactory.building(_geometry, nw + Vector3(lot_offset + 1.5, 7.6, lot_offset + 1.5), Vector2(lot - 6.0, lot - 6.0), 18.0, BuildingFactory.Style.GLASS, _rng, false)
	for i: int in 3:
		PropFactory.crate(_geometry, nw + Vector3(-1.2 + i * 0.1, 0.0, -lot_offset - 4.0 + i * 1.3), 1.1, _rng)
	_alley_clutter(nw + Vector3(1.4, 0.0, lot_offset + 2.0))

	# South-west: industrial warehouse (Dead Zone), slim concrete tower, low sheds.
	var sw: Vector3 = _block_center(-1, 1) + Vector3(0.0, base_y, 0.0)
	_build_warehouse(sw + Vector3(-7.0, 0.0, 0.0))
	BuildingFactory.building(_geometry, sw + Vector3(15.0, 0.0, 0.0), Vector2(9.0, full), 15.0, BuildingFactory.Style.CONCRETE, _rng, true)
	var shed_n := GeometryKit.solid_box(_geometry, sw + Vector3(-7.0, 1.5, -17.5), Vector3(24.0, 3.0, 4.0), MaterialLibrary.metal_panel())
	shed_n.set_instance_shader_parameter(&"paint_color", Color(0.35, 0.4, 0.42))
	var shed_s := GeometryKit.solid_box(_geometry, sw + Vector3(-7.0, 2.25, 17.5), Vector3(24.0, 4.5, 4.0), MaterialLibrary.metal_panel())
	shed_s.set_instance_shader_parameter(&"paint_color", Color(0.45, 0.35, 0.25))
	PropFactory.shipping_container(_geometry, sw + Vector3(8.5, 0.0, -14.0), 0.0, Color(0.2, 0.35, 0.5))

	# South-east: commercial - glass office tower, low shops, long concrete slab, rooftop bridge.
	var se: Vector3 = _block_center(1, 1) + Vector3(0.0, base_y, 0.0)
	BuildingFactory.building(_geometry, se + Vector3(-lot_offset, 0.0, -lot_offset), Vector2(lot, lot), 26.0, BuildingFactory.Style.GLASS, _rng, true)
	BuildingFactory.building(_geometry, se + Vector3(lot_offset, 0.0, -lot_offset), Vector2(lot, lot), 8.4, BuildingFactory.Style.BRICK, _rng, true, 1)
	BuildingFactory.building(_geometry, se + Vector3(0.0, 0.0, lot_offset), Vector2(full, lot), 12.0, BuildingFactory.Style.CONCRETE, _rng, true)
	var bridge := GeometryKit.solid_box(_geometry, se + Vector3(0.0, 8.15, -lot_offset), Vector3(ALLEY + 2.0, 0.5, 3.0), MaterialLibrary.metal_panel())
	bridge.set_instance_shader_parameter(&"paint_color", Color(0.3, 0.3, 0.32))
	var rail := MaterialLibrary.coated(Color(0.1, 0.1, 0.11), 0.8, 0.5)
	for side: float in [-1.4, 1.4]:
		GeometryKit.mesh_box(_geometry, se + Vector3(0.0, 9.3, -lot_offset + side), Vector3(ALLEY + 2.0, 0.06, 0.06), rail)
	_alley_clutter(se + Vector3(-1.4, 0.0, -lot_offset + 3.0))


func _alley_clutter(base: Vector3) -> void:
	var dumpster := GeometryKit.solid_box(_geometry, base + Vector3(0.0, 0.7, 0.0), Vector3(1.4, 1.4, 2.2), MaterialLibrary.metal_panel())
	dumpster.set_instance_shader_parameter(&"paint_color", Color(0.12, 0.3, 0.2))
	GeometryKit.tilted_box(_geometry, base + Vector3(0.0, 1.5, 0.3), Vector3(1.45, 0.06, 1.4), Vector3(-12.0, 0.0, 0.0), MaterialLibrary.coated(Color(0.06, 0.06, 0.06), 0.4, 0.6))
	PropFactory.bin(_geometry, base + Vector3(0.0, 0.0, 1.8))
	var puddle_light := OmniLight3D.new()
	puddle_light.light_color = Color(1.0, 0.6, 0.35)
	puddle_light.light_energy = 1.2
	puddle_light.omni_range = 7.0
	puddle_light.position = base + Vector3(-1.0, 3.2, 0.0)
	add_child(puddle_light)
	GeometryKit.mesh_box(_geometry, base + Vector3(-1.2, 3.3, 0.0), Vector3(0.2, 0.25, 0.35), MaterialLibrary.emissive(Color(1.0, 0.65, 0.35), 4.0))


func _build_warehouse(center: Vector3) -> void:
	var size: float = 26.0
	var height: float = 7.5
	var wall: float = 0.6
	var door: float = 5.0
	var door_height: float = 4.5
	var cladding := Color(0.38, 0.4, 0.38)
	var half: float = size * 0.5
	var segment: float = (size - door) * 0.5
	var clad := MaterialLibrary.metal_panel()

	for side: float in [-1.0, 1.0]:
		var x: float = side * (half - wall * 0.5)
		for end: float in [-1.0, 1.0]:
			var z: float = end * (door * 0.5 + segment * 0.5)
			var w := GeometryKit.solid_box(_geometry, center + Vector3(x, height * 0.5, z), Vector3(wall, height, segment), clad)
			w.set_instance_shader_parameter(&"paint_color", cladding)
		var lintel := GeometryKit.solid_box(_geometry, center + Vector3(x, (door_height + height) * 0.5, 0.0), Vector3(wall, height - door_height, door), clad)
		lintel.set_instance_shader_parameter(&"paint_color", cladding)
		var nz := GeometryKit.solid_box(_geometry, center + Vector3(0.0, height * 0.5, side * (half - wall * 0.5)), Vector3(size, height, wall), clad)
		nz.set_instance_shader_parameter(&"paint_color", cladding)
		var frame := GeometryKit.mesh_box(_geometry, center + Vector3(x + side * 0.35, door_height + 0.15, 0.0), Vector3(0.12, 0.3, door + 0.4), clad)
		frame.set_instance_shader_parameter(&"hazard", 1.0)
		var sign_label := Label3D.new()
		sign_label.double_sided = false
		sign_label.text = "NO SIGNAL ZONE"
		sign_label.font_size = 64
		sign_label.pixel_size = 0.01
		sign_label.modulate = Color(0.8, 0.7, 1.0)
		sign_label.position = center + Vector3(x + side * 0.36, door_height + 0.9, 0.0)
		sign_label.rotation_degrees = Vector3(0.0, 90.0 * side, 0.0)
		add_child(sign_label)
	var roof := GeometryKit.solid_box(_geometry, center + Vector3(0.0, height + 0.2, 0.0), Vector3(size + 0.6, 0.4, size + 0.6), clad)
	roof.set_instance_shader_parameter(&"paint_color", Color(0.25, 0.27, 0.26))
	for i: int in 5:
		GeometryKit.mesh_box(_geometry, center + Vector3(0.0, height + 0.45, -10.0 + i * 5.0), Vector3(size - 2.0, 0.12, 0.8), MaterialLibrary.glass(Color(0.1, 0.12, 0.14)))
	for x: float in [-6.0, 6.0]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.55, 0.45, 1.0)
		lamp.light_energy = 1.0
		lamp.omni_range = 10.0
		lamp.position = center + Vector3(x, height - 1.0, 0.0)
		add_child(lamp)
		GeometryKit.mesh_box(_geometry, center + Vector3(x, height - 0.3, 0.0), Vector3(0.3, 0.1, 6.0), MaterialLibrary.emissive(Color(0.6, 0.5, 1.0), 2.0))
	for offset: Vector3 in [Vector3(-6.0, 0.0, -6.0), Vector3(5.0, 0.0, 6.5), Vector3(-4.0, 0.0, 7.0), Vector3(6.0, 0.0, -7.0)]:
		PropFactory.crate(_geometry, center + offset, 1.4, _rng)
	PropFactory.shipping_container(_geometry, center + Vector3(-2.0, 0.0, -8.0), 90.0, Color(0.5, 0.15, 0.1))
	_add_dead_zone(center + Vector3(0.0, 3.0, 0.0), Vector3(size - 2.0 * wall, 6.0, size - 2.0 * wall), "WAREHOUSE")


func _build_facility() -> void:
	facility = FacilityCompound.new()
	facility.name = "MeridianSignalLabs"
	facility.position = _block_center(1, -1)
	add_child(facility)
	dead_zones.append_array(facility.dead_zones)


func _build_tunnel() -> void:
	var inner: float = _ring_inner()
	var outer: float = inner + RING_WIDTH
	var half_length: float = 15.0
	var height: float = 6.0
	var street_half: float = STREET_WIDTH * 0.5
	var segment: float = half_length - street_half
	var concrete := MaterialLibrary.concrete()
	var tint := Color(0.42, 0.42, 0.41)

	for end: float in [-1.0, 1.0]:
		var z: float = end * (street_half + segment * 0.5)
		var w := GeometryKit.solid_box(_geometry, Vector3(inner + 0.5, height * 0.5, z), Vector3(1.0, height, segment), concrete)
		w.set_instance_shader_parameter(&"tint", tint)
	var outer_wall := GeometryKit.solid_box(_geometry, Vector3(outer + 0.5, height * 0.5, 0.0), Vector3(1.0, height, half_length * 2.0), concrete)
	outer_wall.set_instance_shader_parameter(&"tint", tint)
	var roof := GeometryKit.solid_box(_geometry, Vector3((inner + outer + 1.0) * 0.5, height + 0.4, 0.0), Vector3(RING_WIDTH + 1.0, 0.8, half_length * 2.0), concrete)
	roof.set_instance_shader_parameter(&"tint", tint.darkened(0.15))
	for end: float in [-1.0, 1.0]:
		var portal := GeometryKit.mesh_box(_geometry, Vector3((inner + outer + 1.0) * 0.5, height + 0.3, end * (half_length + 0.3)), Vector3(RING_WIDTH + 1.6, 1.4, 0.6), concrete)
		portal.set_instance_shader_parameter(&"tint", Color(0.5, 0.49, 0.47))
		var plate := Label3D.new()
		plate.double_sided = false
		plate.text = "TUNNEL  -  NO SIGNAL"
		plate.font_size = 72
		plate.pixel_size = 0.01
		plate.modulate = Color(0.85, 0.75, 1.0)
		plate.position = Vector3((inner + outer + 1.0) * 0.5, height + 0.3, end * (half_length + 0.62))
		plate.rotation_degrees = Vector3(0.0, 0.0 if end > 0.0 else 180.0, 0.0)
		add_child(plate)
	for z: float in [-11.0, -5.5, 0.0, 5.5, 11.0]:
		GeometryKit.mesh_box(_geometry, Vector3((inner + outer) * 0.5 + 0.5, height - 0.02, z), Vector3(6.0, 0.08, 0.3), MaterialLibrary.emissive(Color(1.0, 0.7, 0.4), 3.0))
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.68, 0.38)
		lamp.light_energy = 1.4
		lamp.omni_range = 8.0
		lamp.position = Vector3((inner + outer) * 0.5 + 0.5, height - 0.6, z)
		add_child(lamp)
	_add_dead_zone(Vector3((inner + outer) * 0.5 + 0.5, 2.75, 0.0), Vector3(RING_WIDTH - 0.5, 5.5, half_length * 2.0), "EAST TUNNEL")


func _add_dead_zone(center: Vector3, size: Vector3, zone_name: String) -> void:
	var zone := DeadZone.new()
	zone.name = "DeadZone_%s" % zone_name.replace(" ", "_")
	zone.size = size
	zone.zone_name = zone_name
	zone.position = center
	add_child(zone)
	dead_zones.append(zone)


func _build_perimeter_and_skyline() -> void:
	var height: float = 4.0
	var length: float = MAP_HALF_EXTENT * 2.0 + 2.0
	var tint := Color(0.4, 0.4, 0.39)
	for sign_value: float in [-1.0, 1.0]:
		var c: float = sign_value * (MAP_HALF_EXTENT + 0.5)
		var a := GeometryKit.solid_box(_geometry, Vector3(0.0, height * 0.5, c), Vector3(length, height, 1.0), MaterialLibrary.concrete())
		a.set_instance_shader_parameter(&"tint", tint)
		var b := GeometryKit.solid_box(_geometry, Vector3(c, height * 0.5, 0.0), Vector3(1.0, height, length), MaterialLibrary.concrete())
		b.set_instance_shader_parameter(&"tint", tint)
		GeometryKit.collider_box(_geometry, Vector3(0.0, 15.0, c), Vector3(length, 30.0, 1.0))
		GeometryKit.collider_box(_geometry, Vector3(c, 15.0, 0.0), Vector3(1.0, 30.0, length))
	# Distant skyline ring so the city reads as part of a larger metropolis.
	for i: int in 44:
		var angle: float = TAU * float(i) / 44.0 + _rng.randf_range(-0.05, 0.05)
		var radius: float = _rng.randf_range(105.0, 150.0)
		var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var footprint := Vector2(_rng.randf_range(14.0, 26.0), _rng.randf_range(14.0, 26.0))
		BuildingFactory.skyline(_geometry, pos, footprint, _rng.randf_range(25.0, 85.0), _rng)
	var outside := MaterialLibrary.surface(Color(0.05, 0.05, 0.055), 0.9, 0.0, 0.0)
	GeometryKit.mesh_box(_geometry, Vector3(0.0, -0.05, 0.0), Vector3(400.0, 0.02, 400.0), outside, false)


# --- Street furniture ---------------------------------------------------------------------------

func _build_street_furniture() -> void:
	var y: float = SIDEWALK_HEIGHT
	var half: float = BLOCK_SIZE * 0.5
	for ix: int in [-1, 1]:
		for iz: int in [-1, 1]:
			var c: Vector3 = _block_center(ix, iz)
			var facility_block: bool = ix == 1 and iz == -1
			var inset: float = half - 1.0 if not facility_block else half - 0.6
			for t: float in [-11.0, 11.0]:
				PropFactory.street_lamp(_geometry, c + Vector3(inset, y, t), -90.0)
				PropFactory.street_lamp(_geometry, c + Vector3(-inset, y, t), 90.0)
				PropFactory.street_lamp(_geometry, c + Vector3(t, y, inset), 180.0)
				PropFactory.street_lamp(_geometry, c + Vector3(t, y, -inset), 0.0)
			if facility_block:
				continue
			# Trees and furniture on the centre-street-facing sidewalks.
			var towards_x: float = -float(ix)
			var towards_z: float = -float(iz)
			for t: float in [-17.0, -4.0, 4.0, 17.0]:
				PropFactory.tree(_geometry, c + Vector3(towards_x * (half - 1.4), y, t), _rng)
				PropFactory.tree(_geometry, c + Vector3(t, y, towards_z * (half - 1.4)), _rng)
			PropFactory.bench(_geometry, c + Vector3(towards_x * (half - 1.3), y, 0.0), 90.0 * towards_x)
			PropFactory.bin(_geometry, c + Vector3(towards_x * (half - 1.0), y, 7.5))
			PropFactory.hydrant(_geometry, c + Vector3(-7.5, y, towards_z * (half - 0.8)))
			PropFactory.bin(_geometry, c + Vector3(10.0, y, towards_z * (half - 1.0)))
	PropFactory.bus_stop(_geometry, _block_center(-1, 1) + Vector3(half - 1.6, SIDEWALK_HEIGHT, -9.0), -90.0)
	PropFactory.bus_stop(_geometry, _block_center(1, 1) + Vector3(-9.0, SIDEWALK_HEIGHT, -half + 1.6), 0.0)

	var corner: float = STREET_WIDTH * 0.5 + 0.8
	PropFactory.traffic_light(_geometry, Vector3(corner, SIDEWALK_HEIGHT, corner), 225.0, 0)
	PropFactory.traffic_light(_geometry, Vector3(-corner, SIDEWALK_HEIGHT, corner), 135.0, 2)
	PropFactory.traffic_light(_geometry, Vector3(-corner, SIDEWALK_HEIGHT, -corner), 45.0, 0)
	PropFactory.traffic_light(_geometry, Vector3(corner, SIDEWALK_HEIGHT, -corner), -45.0, 2)

	var ring_outer: float = _ring_inner() + RING_WIDTH
	for t: float in [-40.0, 0.0, 40.0]:
		PropFactory.street_lamp(_geometry, Vector3(t, 0.0, ring_outer + 1.2), 0.0)
		PropFactory.street_lamp(_geometry, Vector3(t, 0.0, -ring_outer - 1.2), 180.0)
		PropFactory.street_lamp(_geometry, Vector3(ring_outer + 1.2, 0.0, t + 20.0), 90.0)
		PropFactory.street_lamp(_geometry, Vector3(-ring_outer - 1.2, 0.0, t - 20.0), -90.0)
	for i: int in 10:
		var angle: float = TAU * float(i) / 10.0 + 0.3
		var r: float = ring_outer + 5.5
		var p := Vector3(cos(angle), 0.0, sin(angle)) * r
		p = p.clamp(Vector3(-ring_outer - 6.0, 0.0, -ring_outer - 6.0), Vector3(ring_outer + 6.0, 0.0, ring_outer + 6.0))
		PropFactory.tree(_geometry, p, _rng)


func _build_parked_cars() -> void:
	var slots: Array[Vector3] = [
		Vector3(5.3, 0.0, 16.0), Vector3(5.3, 0.0, 24.0), Vector3(-5.3, 0.0, 34.0), Vector3(-5.3, 0.0, 42.0),
		Vector3(5.3, 0.0, -18.0), Vector3(-5.3, 0.0, -24.0), Vector3(-5.3, 0.0, -40.0), Vector3(5.3, 0.0, -44.0),
	]
	for slot: Vector3 in slots:
		var body := StaticBody3D.new()
		body.collision_layer = GeometryKit.WORLD_LAYER
		body.collision_mask = 0
		body.position = slot
		body.rotation_degrees = Vector3(0.0, 0.0 if slot.x > 0.0 else 180.0, 0.0)
		_geometry.add_child(body)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.9, 1.4, 4.4)
		shape.shape = box
		shape.position = Vector3(0.0, 0.7, 0.0)
		body.add_child(shape)
		var kind: VehicleModel.Kind = VehicleModel.Kind.VAN if _rng.randf() < 0.2 else VehicleModel.Kind.SEDAN
		VehicleModel.build(body, kind, VehicleModel.random_paint(_rng), false)


func _build_uplinks() -> void:
	var r: float = MAP_HALF_EXTENT - 5.0
	var specs: Array[Vector4] = [
		Vector4(-20.0, -r, 0.0, 0.0), Vector4(r, -35.0, -90.0, 1.0),
		Vector4(35.0, r, 180.0, 2.0), Vector4(-r, 20.0, 90.0, 3.0),
	]
	var labels: PackedStringArray = ["RELAY-N7", "RELAY-E2", "RELAY-S4", "RELAY-W9"]
	for spec: Vector4 in specs:
		var station := UplinkStation.new()
		station.station_label = labels[int(spec.w)]
		station.name = station.station_label.replace("-", "_")
		station.position = Vector3(spec.x, 0.0, spec.y)
		station.rotation_degrees = Vector3(0.0, spec.z, 0.0)
		add_child(station)
		uplink_stations.append(station)


# --- NPCs ------------------------------------------------------------------------------

func _spawn_npcs() -> void:
	var seed_value: int = 1
	for ix: int in [-1, 1]:
		for iz: int in [-1, 1]:
			if ix == 1 and iz == -1:
				continue
			var c: Vector3 = _block_center(ix, iz) + Vector3(0.0, SIDEWALK_HEIGHT, 0.0)
			var e: float = BLOCK_SIZE * 0.5 - 1.6
			var loop: Array[Vector3] = [c + Vector3(-e, 0.0, -e), c + Vector3(e, 0.0, -e), c + Vector3(e, 0.0, e), c + Vector3(-e, 0.0, e)]
			for n: int in 2:
				var route: Array[Vector3] = loop.duplicate()
				if n == 1:
					route.reverse()
				_add_npc(HumanoidRig.Style.CIVILIAN, seed_value, route, n * 2)
				seed_value += 1
	# Lab technicians commute between the SE bus stop and the facility through its gate.
	var lab: Vector3 = facility.global_position
	var commute: Array[Vector3] = [
		Vector3(20.0, SIDEWALK_HEIGHT, 9.5), Vector3(29.0, 0.0, -4.0), lab + Vector3(0.0, 0.1, 14.0),
		lab + Vector3(-3.0, 0.1, 6.0), lab + Vector3(6.0, 0.1, 10.0), lab + Vector3(0.0, 0.1, 16.0), Vector3(29.0, 0.0, -4.0),
	]
	for t: int in 3:
		var route: Array[Vector3] = commute.duplicate()
		for k: int in t * 2:
			route.push_back(route.pop_front())
		_add_npc(HumanoidRig.Style.TECHNICIAN, 100 + t, route, 0)


func _add_npc(npc_style: HumanoidRig.Style, seed_value: int, route: Array[Vector3], start_index: int) -> void:
	var npc := NpcWalker.new()
	npc.style = npc_style
	npc.outfit_seed = seed_value
	npc.route = route
	npc.name = "NPC_%d" % seed_value
	add_child(npc)
	npc.global_position = route[start_index % route.size()] + Vector3(0.0, 0.2, 0.0)
	npcs.append(npc)


# --- Pickups ---------------------------------------------------------------------------

func _build_pickups() -> void:
	var cells: Array[Vector3] = [
		Vector3(-29.0, 0.1, -29.0), Vector3(-39.75, 12.1, -39.75), Vector3(-36.0, 0.1, 35.0),
		Vector3(58.5, 0.0, 9.0), Vector3(29.0, 8.4, 18.25), Vector3(29.0, 0.1, 23.0),
		Vector3(-60.0, 0.0, -68.0), Vector3(66.0, 0.0, 52.0), Vector3(-36.0, 3.1, 11.5),
	]
	for at: Vector3 in cells:
		_add_pickup(at, Pickup.KIND_CELL, 1)
	for at: Vector3 in [Vector3(-10.0, 0.1, 10.0), Vector3(10.0, 0.1, 40.0), Vector3(-40.0, 0.1, -10.0)]:
		_add_pickup(at, Pickup.KIND_DARTS, 3)
	for at: Vector3 in [Vector3(-30.0, 0.1, 25.0), Vector3(58.5, 0.0, -10.0)]:
		_add_pickup(at, Pickup.KIND_EMP, 1)


func _add_pickup(at: Vector3, kind: StringName, amount: int) -> void:
	var pickup := Pickup.new()
	pickup.kind = kind
	pickup.amount = amount
	pickup.position = at
	add_child(pickup)


# --- Traffic ----------------------------------------------------------------------

func _build_vehicle_routes() -> void:
	var inner: float = _ring_inner()
	var outer_lane: float = inner + RING_WIDTH * 0.5 + 3.0
	var inner_lane: float = inner + RING_WIDTH * 0.5 - 3.0
	var centre_lane: float = 3.5

	_add_route("Courier", Color(0.8, 0.45, 0.08), VehicleModel.Kind.VAN, 10.0, 0.0, [
		Vector3(-outer_lane, 0.0, -outer_lane), Vector3(outer_lane, 0.0, -outer_lane),
		Vector3(outer_lane, 0.0, outer_lane), Vector3(-outer_lane, 0.0, outer_lane),
	])
	_add_route("Sedan", Color(0.1, 0.18, 0.4), VehicleModel.Kind.SEDAN, 8.0, 0.35, [
		Vector3(-inner_lane, 0.0, -inner_lane), Vector3(inner_lane, 0.0, -inner_lane),
		Vector3(inner_lane, 0.0, -centre_lane), Vector3(-inner_lane, 0.0, -centre_lane),
	])
	_add_route("Taxi", Color(0.95, 0.75, 0.1), VehicleModel.Kind.TAXI, 9.0, 0.6, [
		Vector3(-inner_lane, 0.0, centre_lane), Vector3(inner_lane, 0.0, centre_lane),
		Vector3(inner_lane, 0.0, inner_lane), Vector3(-inner_lane, 0.0, inner_lane),
	])


func _add_route(vehicle_name: String, color: Color, kind: VehicleModel.Kind, speed: float, start_ratio: float, corners: Array[Vector3]) -> void:
	var path := Path3D.new()
	path.name = "Route_%s" % vehicle_name
	var curve := Curve3D.new()
	var chamfer: float = 5.0
	var count: int = corners.size()
	for i: int in count:
		var previous: Vector3 = corners[(i - 1 + count) % count]
		var corner: Vector3 = corners[i]
		var next: Vector3 = corners[(i + 1) % count]
		curve.add_point(corner + (previous - corner).normalized() * chamfer)
		curve.add_point(corner + (next - corner).normalized() * chamfer)
	curve.add_point(curve.get_point_position(0))
	path.curve = curve
	add_child(path)

	var follow := PathFollow3D.new()
	follow.loop = true
	follow.rotation_mode = PathFollow3D.ROTATION_Y
	follow.cubic_interp = false
	path.add_child(follow)
	follow.progress_ratio = start_ratio

	var vehicle := TrafficVehicle.new()
	vehicle.name = vehicle_name
	vehicle.display_name = vehicle_name
	vehicle.body_color = color
	vehicle.kind = kind
	vehicle.speed = speed
	follow.add_child(vehicle)
	traffic_vehicles.append(vehicle)


# --- Navigation ------------------------------------------------------------------------

func _collect_points() -> void:
	var ring_mid: float = _ring_mid()
	var b: float = BLOCK_SIZE * 0.5 + STREET_WIDTH * 0.5
	patrol_points = [
		Vector3.ZERO,
		Vector3(-b, 0.0, 0.0), Vector3(b, 0.0, 0.0), Vector3(0.0, 0.0, -b), Vector3(0.0, 0.0, b),
		Vector3(-ring_mid, 0.0, -ring_mid), Vector3(ring_mid, 0.0, -ring_mid),
		Vector3(-ring_mid, 0.0, ring_mid), Vector3(ring_mid, 0.0, ring_mid),
		Vector3(0.0, 0.0, -ring_mid), Vector3(0.0, 0.0, ring_mid),
		Vector3(-ring_mid, 0.0, 0.0), Vector3(ring_mid, 0.0, 0.0),
		_block_center(-1, -1), _block_center(-1, 1) + Vector3(-7.0, 0.0, 0.0),
		_block_center(1, 1) + Vector3(0.0, 0.0, -10.0),
	]
	patrol_points.append_array(facility.get_patrol_points())
	for station: UplinkStation in uplink_stations:
		patrol_points.append(station.global_position + station.global_basis.z * 6.0)
	hunter_spawn_points = [
		Vector3(-ring_mid, 0.0, -ring_mid), Vector3(ring_mid, 0.0, -ring_mid),
		Vector3(ring_mid, 0.0, ring_mid), Vector3(-ring_mid, 0.0, ring_mid),
	]


func _bake_navigation() -> void:
	var region := get_parent() as NavigationRegion3D
	if region == null:
		push_warning("GreyboxCityBuilder: parent is not a NavigationRegion3D; hunters will not navigate.")
		return
	if region.navigation_mesh == null:
		var nav_mesh := NavigationMesh.new()
		nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nav_mesh.geometry_collision_mask = GeometryKit.WORLD_LAYER
		nav_mesh.agent_radius = 0.5
		nav_mesh.agent_height = 2.0
		nav_mesh.agent_max_climb = 0.5
		nav_mesh.filter_baking_aabb = AABB(Vector3(-80.0, -2.0, -80.0), Vector3(160.0, 5.0, 160.0))
		region.navigation_mesh = nav_mesh
	region.bake_navigation_mesh(false)
