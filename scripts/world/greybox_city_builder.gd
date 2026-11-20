class_name GreyboxCityBuilder
extends Node3D
## Procedurally builds the greybox city at runtime and bakes navigation for it.
##
## Layout (top-down, metres): a 2x2 grid of 44 m city blocks separated by 14 m centre
## streets and wrapped by a 14 m ring road. Blocks contain buildings split by 5 m alleys.
## - Dead Zone 1: covered tunnel over the east ring road.
## - Dead Zone 2: hollow warehouse interior in the south-west block.
## - 3 decoy vehicles loop on Path3D routes (outer ring, north half, south half).
## This node must be a child of a NavigationRegion3D; it bakes the parent after building.

signal city_built()

const WORLD_LAYER: int = 1
const BLOCK_SIZE: float = 44.0
const STREET_WIDTH: float = 14.0
const RING_WIDTH: float = 14.0
const MAP_HALF_EXTENT: float = 75.0
const ALLEY: float = 5.0

@export var random_seed: int = 1337
@export var show_window_lights: bool = true

var dead_zones: Array[DeadZone] = []
var decoy_vehicles: Array[DecoyVehicle] = []
var patrol_points: Array[Vector3] = []
var hunter_spawn_points: Array[Vector3] = []

var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}
var _geometry: Node3D


func _ready() -> void:
	_rng.seed = random_seed
	_geometry = Node3D.new()
	_geometry.name = "Geometry"
	add_child(_geometry)

	_build_ground()
	_build_blocks()
	_build_tunnel()
	_build_perimeter()
	_build_street_lights()
	_build_vehicle_routes()
	_collect_points()
	_bake_navigation()
	city_built.emit()


# --- Layout helpers ------------------------------------------------------------------

func _block_center(ix: int, iz: int) -> Vector3:
	var offset: float = BLOCK_SIZE * 0.5 + STREET_WIDTH * 0.5
	return Vector3(offset * float(ix), 0.0, offset * float(iz))


func _ring_inner() -> float:
	return STREET_WIDTH * 0.5 + BLOCK_SIZE


# --- Ground & streets ----------------------------------------------------------------

func _build_ground() -> void:
	var size: float = MAP_HALF_EXTENT * 2.0
	_add_box(_geometry, Vector3(0.0, -0.5, 0.0), Vector3(size, 1.0, size), Color(0.13, 0.13, 0.15))

	var verge_color := Color(0.12, 0.2, 0.13)
	var ring_outer: float = _ring_inner() + RING_WIDTH
	var verge: float = MAP_HALF_EXTENT - ring_outer
	for sign_value: float in [-1.0, 1.0]:
		var c: float = sign_value * (ring_outer + verge * 0.5)
		_add_box(_geometry, Vector3(0.0, 0.015, c), Vector3(size, 0.03, verge), verge_color, false)
		_add_box(_geometry, Vector3(c, 0.016, 0.0), Vector3(verge, 0.03, size), verge_color, false)

	var lane_color := Color(0.9, 0.75, 0.3)
	var ring_mid: float = _ring_inner() + RING_WIDTH * 0.5
	var dash_count: int = 22
	for i: int in dash_count:
		var t: float = lerpf(-ring_mid, ring_mid, (float(i) + 0.5) / float(dash_count))
		for side: float in [-1.0, 1.0]:
			_add_glow_box(_geometry, Vector3(t, 0.02, side * ring_mid), Vector3(2.5, 0.02, 0.2), lane_color, 0.6)
			_add_glow_box(_geometry, Vector3(side * ring_mid, 0.02, t), Vector3(0.2, 0.02, 2.5), lane_color, 0.6)
		if absf(t) > STREET_WIDTH * 0.5:
			_add_glow_box(_geometry, Vector3(t, 0.02, 0.0), Vector3(2.5, 0.02, 0.2), lane_color, 0.6)
			_add_glow_box(_geometry, Vector3(0.0, 0.02, t), Vector3(0.2, 0.02, 2.5), lane_color, 0.6)


# --- City blocks -----------------------------------------------------------------------

func _build_blocks() -> void:
	var sidewalk := Color(0.32, 0.32, 0.35)
	for ix: int in [-1, 1]:
		for iz: int in [-1, 1]:
			var center: Vector3 = _block_center(ix, iz)
			_add_box(_geometry, center + Vector3(0.0, 0.02, 0.0), Vector3(BLOCK_SIZE, 0.04, BLOCK_SIZE), sidewalk, false)

	var half_lot: float = (BLOCK_SIZE - 4.0 - ALLEY) * 0.25
	var lot: float = half_lot * 2.0
	var lot_offset: float = half_lot + ALLEY * 0.5
	var full: float = BLOCK_SIZE - 4.0

	# North-west: four towers on a cross of alleys.
	var nw: Vector3 = _block_center(-1, -1)
	_add_building(nw + Vector3(-lot_offset, 0.0, -lot_offset), Vector2(lot, lot), 9.0)
	_add_building(nw + Vector3(lot_offset, 0.0, -lot_offset), Vector2(lot, lot), 16.0)
	_add_building(nw + Vector3(-lot_offset, 0.0, lot_offset), Vector2(lot, lot), 12.0)
	_add_building(nw + Vector3(lot_offset, 0.0, lot_offset), Vector2(lot, lot), 22.0)
	_add_crate_stack(nw + Vector3(-1.6, 0.0, -lot_offset - 4.0))

	# North-east: long slab + two low-rises, with climbable crates.
	var ne: Vector3 = _block_center(1, -1)
	_add_building(ne + Vector3(0.0, 0.0, -lot_offset), Vector2(full, lot), 10.0)
	_add_building(ne + Vector3(-lot_offset, 0.0, lot_offset), Vector2(lot, lot), 6.0)
	_add_building(ne + Vector3(lot_offset, 0.0, lot_offset), Vector2(lot, lot), 13.0)
	_add_crate_stack(ne + Vector3(-lot_offset, 0.0, lot_offset + half_lot + 1.0))

	# South-west: warehouse interior (Dead Zone) + slim tower + low sheds.
	var sw: Vector3 = _block_center(-1, 1)
	_build_warehouse(sw + Vector3(-7.0, 0.0, 0.0))
	_add_building(sw + Vector3(15.5, 0.0, 0.0), Vector2(9.0, full), 15.0)
	_add_building(sw + Vector3(-7.0, 0.0, -17.5), Vector2(26.0, 5.0), 3.0)
	_add_building(sw + Vector3(-7.0, 0.0, 17.5), Vector2(26.0, 5.0), 4.5)

	# South-east: L of buildings with a rooftop bridge across the alley.
	var se: Vector3 = _block_center(1, 1)
	_add_building(se + Vector3(-lot_offset, 0.0, -lot_offset), Vector2(lot, lot), 18.0)
	_add_building(se + Vector3(lot_offset, 0.0, -lot_offset), Vector2(lot, lot), 8.0)
	_add_building(se + Vector3(0.0, 0.0, lot_offset), Vector2(full, lot), 12.0)
	_add_box(_geometry, se + Vector3(0.0, 7.75, -lot_offset), Vector3(ALLEY + 2.0, 0.5, 3.0), Color(0.45, 0.4, 0.35))
	_add_crate_stack(se + Vector3(lot_offset + half_lot + 1.0, 0.0, -lot_offset))


func _add_building(center: Vector3, footprint: Vector2, height: float) -> void:
	var tint: float = _rng.randf_range(0.0, 0.12)
	var color := Color(0.36 + tint, 0.37 + tint, 0.42 + tint * 1.5)
	_add_box(_geometry, center + Vector3(0.0, height * 0.5, 0.0), Vector3(footprint.x, height, footprint.y), color)

	var parapet_color: Color = color.darkened(0.25)
	var top: float = height + 0.2
	_add_box(_geometry, center + Vector3(0.0, top, -footprint.y * 0.5 + 0.15), Vector3(footprint.x, 0.4, 0.3), parapet_color)
	_add_box(_geometry, center + Vector3(0.0, top, footprint.y * 0.5 - 0.15), Vector3(footprint.x, 0.4, 0.3), parapet_color)
	_add_box(_geometry, center + Vector3(-footprint.x * 0.5 + 0.15, top, 0.0), Vector3(0.3, 0.4, footprint.y), parapet_color)
	_add_box(_geometry, center + Vector3(footprint.x * 0.5 - 0.15, top, 0.0), Vector3(0.3, 0.4, footprint.y), parapet_color)
	if footprint.x > 8.0 and footprint.y > 8.0:
		_add_box(_geometry, center + Vector3(_rng.randf_range(-2.0, 2.0), height + 0.75, _rng.randf_range(-2.0, 2.0)), Vector3(2.5, 1.5, 2.0), Color(0.5, 0.5, 0.52))

	if not show_window_lights:
		return
	var floors: int = int(height / 3.5)
	for f: int in floors:
		var y: float = 2.0 + float(f) * 3.5
		var lit: bool = _rng.randf() < 0.7
		var window_color: Color = Color(1.0, 0.8, 0.45) if _rng.randf() < 0.6 else Color(0.45, 0.8, 1.0)
		var energy: float = 1.6 if lit else 0.05
		_add_glow_box(_geometry, center + Vector3(0.0, y, -footprint.y * 0.5 - 0.03), Vector3(footprint.x * 0.8, 1.0, 0.05), window_color, energy)
		_add_glow_box(_geometry, center + Vector3(0.0, y, footprint.y * 0.5 + 0.03), Vector3(footprint.x * 0.8, 1.0, 0.05), window_color, energy)
		_add_glow_box(_geometry, center + Vector3(-footprint.x * 0.5 - 0.03, y, 0.0), Vector3(0.05, 1.0, footprint.y * 0.8), window_color, energy)
		_add_glow_box(_geometry, center + Vector3(footprint.x * 0.5 + 0.03, y, 0.0), Vector3(0.05, 1.0, footprint.y * 0.8), window_color, energy)


func _add_crate_stack(base: Vector3) -> void:
	var crate := Color(0.55, 0.42, 0.25)
	_add_box(_geometry, base + Vector3(0.0, 0.5, 0.0), Vector3(1.6, 1.0, 1.6), crate)
	_add_box(_geometry, base + Vector3(1.6, 1.0, 0.0), Vector3(1.6, 2.0, 1.6), crate.darkened(0.15))


func _build_warehouse(center: Vector3) -> void:
	var size: float = 26.0
	var height: float = 7.0
	var wall: float = 1.0
	var door: float = 5.0
	var door_height: float = 4.5
	var color := Color(0.42, 0.36, 0.33)
	var half: float = size * 0.5
	var segment: float = (size - door) * 0.5

	for side: float in [-1.0, 1.0]:
		var x: float = side * (half - wall * 0.5)
		for end: float in [-1.0, 1.0]:
			var z: float = end * (door * 0.5 + segment * 0.5)
			_add_box(_geometry, center + Vector3(x, height * 0.5, z), Vector3(wall, height, segment), color)
		_add_box(_geometry, center + Vector3(x, (door_height + height) * 0.5, 0.0), Vector3(wall, height - door_height, door), color)
		_add_box(_geometry, center + Vector3(0.0, height * 0.5, side * (half - wall * 0.5)), Vector3(size, height, wall), color)
		_add_glow_box(_geometry, center + Vector3(x + side * 0.55, door_height + 0.3, 0.0), Vector3(0.05, 0.3, door), Color(0.6, 0.4, 1.0), 2.0)
	_add_box(_geometry, center + Vector3(0.0, height + 0.25, 0.0), Vector3(size, 0.5, size), color.darkened(0.2))

	for offset: Vector3 in [Vector3(-6.0, 0.0, -6.0), Vector3(5.0, 0.0, 6.5), Vector3(-4.0, 0.0, 7.0)]:
		_add_box(_geometry, center + offset + Vector3(0.0, 0.75, 0.0), Vector3(2.5, 1.5, 2.5), Color(0.5, 0.4, 0.25))

	_add_dead_zone(center + Vector3(0.0, 3.0, 0.0), Vector3(size - 2.0 * wall, 6.0, size - 2.0 * wall), "WAREHOUSE")


func _build_tunnel() -> void:
	var inner: float = _ring_inner()
	var outer: float = inner + RING_WIDTH
	var half_length: float = 15.0
	var height: float = 6.0
	var color := Color(0.3, 0.3, 0.34)
	var street_half: float = STREET_WIDTH * 0.5
	var segment: float = half_length - street_half

	for end: float in [-1.0, 1.0]:
		var z: float = end * (street_half + segment * 0.5)
		_add_box(_geometry, Vector3(inner + 0.5, height * 0.5, z), Vector3(1.0, height, segment), color)
	_add_box(_geometry, Vector3(outer + 0.5, height * 0.5, 0.0), Vector3(1.0, height, half_length * 2.0), color)
	_add_box(_geometry, Vector3((inner + outer + 1.0) * 0.5, height + 0.3, 0.0), Vector3(RING_WIDTH + 1.0, 0.6, half_length * 2.0), color.darkened(0.2))
	for z: float in [-10.0, 0.0, 10.0]:
		_add_glow_box(_geometry, Vector3((inner + outer) * 0.5, height - 0.05, z), Vector3(6.0, 0.1, 0.4), Color(0.6, 0.4, 1.0), 2.5)

	_add_dead_zone(Vector3((inner + outer) * 0.5 + 0.5, 2.75, 0.0), Vector3(RING_WIDTH - 0.5, 5.5, half_length * 2.0), "EAST TUNNEL")


func _add_dead_zone(center: Vector3, size: Vector3, zone_name: String) -> void:
	var zone := DeadZone.new()
	zone.name = "DeadZone_%s" % zone_name.replace(" ", "_")
	zone.size = size
	zone.zone_name = zone_name
	zone.position = center
	add_child(zone)
	dead_zones.append(zone)


func _build_perimeter() -> void:
	var height: float = 10.0
	var length: float = MAP_HALF_EXTENT * 2.0 + 2.0
	var color := Color(0.2, 0.2, 0.25)
	for sign_value: float in [-1.0, 1.0]:
		var c: float = sign_value * (MAP_HALF_EXTENT + 0.5)
		_add_box(_geometry, Vector3(0.0, height * 0.5, c), Vector3(length, height, 1.0), color)
		_add_box(_geometry, Vector3(c, height * 0.5, 0.0), Vector3(1.0, height, length), color)


func _build_street_lights() -> void:
	var ring_mid: float = _ring_inner() + RING_WIDTH * 0.5
	var spots: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0), Vector3(-29.0, 0.0, 0.0), Vector3(29.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -29.0), Vector3(0.0, 0.0, 29.0),
		Vector3(-ring_mid, 0.0, -ring_mid), Vector3(ring_mid, 0.0, ring_mid),
		Vector3(-ring_mid, 0.0, ring_mid), Vector3(ring_mid, 0.0, -ring_mid),
	]
	for spot: Vector3 in spots:
		var pole_base: Vector3 = spot + Vector3(STREET_WIDTH * 0.5 - 0.6, 0.0, STREET_WIDTH * 0.5 - 0.6)
		_add_box(_geometry, pole_base + Vector3(0.0, 2.75, 0.0), Vector3(0.25, 5.5, 0.25), Color(0.25, 0.25, 0.28), false)
		_add_glow_box(_geometry, pole_base + Vector3(0.0, 5.6, 0.0), Vector3(0.7, 0.2, 0.7), Color(1.0, 0.85, 0.6), 4.0)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.6)
		light.light_energy = 2.0
		light.omni_range = 16.0
		light.position = pole_base + Vector3(0.0, 5.2, 0.0)
		add_child(light)


# --- Decoy vehicles ----------------------------------------------------------------------

func _build_vehicle_routes() -> void:
	var inner: float = _ring_inner()
	var outer_lane: float = inner + RING_WIDTH * 0.5 + 3.0
	var inner_lane: float = inner + RING_WIDTH * 0.5 - 3.0
	var centre_lane: float = 3.5

	_add_route("Courier", Color(0.95, 0.65, 0.15), 10.0, 0.0, [
		Vector3(-outer_lane, 0.0, -outer_lane), Vector3(outer_lane, 0.0, -outer_lane),
		Vector3(outer_lane, 0.0, outer_lane), Vector3(-outer_lane, 0.0, outer_lane),
	])
	_add_route("Hauler", Color(0.2, 0.55, 0.95), 8.0, 0.35, [
		Vector3(-inner_lane, 0.0, -inner_lane), Vector3(inner_lane, 0.0, -inner_lane),
		Vector3(inner_lane, 0.0, -centre_lane), Vector3(-inner_lane, 0.0, -centre_lane),
	])
	_add_route("Taxi", Color(0.95, 0.9, 0.2), 9.0, 0.6, [
		Vector3(-inner_lane, 0.0, centre_lane), Vector3(inner_lane, 0.0, centre_lane),
		Vector3(inner_lane, 0.0, inner_lane), Vector3(-inner_lane, 0.0, inner_lane),
	])


func _add_route(vehicle_name: String, color: Color, speed: float, start_ratio: float, corners: Array[Vector3]) -> void:
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

	var vehicle := DecoyVehicle.new()
	vehicle.name = vehicle_name
	vehicle.display_name = vehicle_name
	vehicle.body_color = color
	vehicle.speed = speed
	follow.add_child(vehicle)
	decoy_vehicles.append(vehicle)


# --- Navigation ------------------------------------------------------------------------

func _collect_points() -> void:
	var ring_mid: float = _ring_inner() + RING_WIDTH * 0.5
	var b: float = BLOCK_SIZE * 0.5 + STREET_WIDTH * 0.5
	patrol_points = [
		Vector3.ZERO,
		Vector3(-b, 0.0, 0.0), Vector3(b, 0.0, 0.0), Vector3(0.0, 0.0, -b), Vector3(0.0, 0.0, b),
		Vector3(-ring_mid, 0.0, -ring_mid), Vector3(ring_mid, 0.0, -ring_mid),
		Vector3(-ring_mid, 0.0, ring_mid), Vector3(ring_mid, 0.0, ring_mid),
		Vector3(0.0, 0.0, -ring_mid), Vector3(0.0, 0.0, ring_mid),
		Vector3(-ring_mid, 0.0, 0.0), Vector3(ring_mid, 0.0, 0.0),
		_block_center(-1, -1), _block_center(1, -1) + Vector3(0.0, 0.0, 10.0),
		_block_center(-1, 1) + Vector3(-7.0, 0.0, 0.0), _block_center(1, 1) + Vector3(0.0, 0.0, -10.0),
	]
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
		nav_mesh.geometry_collision_mask = WORLD_LAYER
		nav_mesh.agent_radius = 0.5
		nav_mesh.agent_height = 2.0
		nav_mesh.agent_max_climb = 0.5
		nav_mesh.filter_baking_aabb = AABB(Vector3(-80.0, -2.0, -80.0), Vector3(160.0, 5.0, 160.0))
		region.navigation_mesh = nav_mesh
	region.bake_navigation_mesh(false)


# --- Primitive factories -------------------------------------------------------------------

func _add_box(parent: Node3D, center: Vector3, size: Vector3, color: Color, collide: bool = true) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _get_material(color, 0.0)
	if not collide:
		mesh_instance.position = center
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh_instance)
		return
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.add_child(mesh_instance)
	parent.add_child(body)


func _add_glow_box(parent: Node3D, center: Vector3, size: Vector3, color: Color, energy: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _get_material(color, energy)
	mesh_instance.position = center
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_instance)


func _get_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var key: String = "%s|%.2f" % [color.to_html(), emission_energy]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	_materials[key] = material
	return material
