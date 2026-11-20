class_name BuildingFactory
extends RefCounted
## Builds structured buildings: shader-textured facade mass (brick / concrete / glass),
## stone plinth, cornice and parapet, shop awnings, fire escapes and rooftop clutter
## (water towers, A/C units, stair houses, antennas).

enum Style { BRICK, CONCRETE, GLASS }

const FLOOR_HEIGHT: float = 3.4
const GROUND_FLOOR: float = 4.2

const BRICK_COLORS: Array[Color] = [Color(0.45, 0.2, 0.14), Color(0.52, 0.3, 0.2), Color(0.36, 0.18, 0.13), Color(0.5, 0.42, 0.33)]
const CONCRETE_COLORS: Array[Color] = [Color(0.56, 0.55, 0.52), Color(0.48, 0.47, 0.45), Color(0.62, 0.58, 0.5), Color(0.4, 0.42, 0.45)]
const GLASS_COLORS: Array[Color] = [Color(0.22, 0.25, 0.28), Color(0.3, 0.32, 0.34)]
const AWNING_COLORS: Array[Color] = [Color(0.45, 0.08, 0.07), Color(0.08, 0.25, 0.18), Color(0.1, 0.15, 0.35), Color(0.55, 0.4, 0.1)]


## `center` is the footprint centre at ground level (y = base height).
## `fire_escape_face`: -1 none, 0 +X, 1 -X, 2 +Z, 3 -Z.
static func building(parent: Node3D, center: Vector3, footprint: Vector2, height: float, style: Style, rng: RandomNumberGenerator, storefront: bool = true, fire_escape_face: int = -1, rooftop: bool = true) -> void:
	var root := Node3D.new()
	root.position = center
	parent.add_child(root)
	var wall_color: Color = _pick_color(style, rng)
	var base_y: float = center.y

	var mass := GeometryKit.solid_box(root, Vector3(0.0, height * 0.5, 0.0), Vector3(footprint.x, height, footprint.y), MaterialLibrary.facade())
	var lit: float = rng.randf_range(0.35, 0.65)
	GeometryKit.set_facade(mass, wall_color, float(style), rng.randf_range(0.0, 100.0), lit, base_y, base_y + height, storefront)

	var stone := MaterialLibrary.concrete()
	if storefront:
		var plinth := GeometryKit.mesh_box(root, Vector3(0.0, 0.18, 0.0), Vector3(footprint.x + 0.12, 0.36, footprint.y + 0.12), stone)
		plinth.set_instance_shader_parameter(&"tint", Color(0.32, 0.31, 0.3))
		var band := GeometryKit.mesh_box(root, Vector3(0.0, GROUND_FLOOR - 0.05, 0.0), Vector3(footprint.x + 0.3, 0.22, footprint.y + 0.3), stone)
		band.set_instance_shader_parameter(&"tint", Color(0.55, 0.53, 0.5))
		_add_awnings(root, footprint, rng)

	# Cornice + parapet (parapet is solid so the roof is a safe walkable area).
	var cornice := GeometryKit.mesh_box(root, Vector3(0.0, height - 0.25, 0.0), Vector3(footprint.x + 0.45, 0.5, footprint.y + 0.45), stone)
	cornice.set_instance_shader_parameter(&"tint", wall_color.lerp(Color(0.6, 0.58, 0.55), 0.6))
	var parapet_tint: Color = wall_color.lerp(Color(0.5, 0.5, 0.5), 0.5)
	var ph: float = 0.9
	for side: float in [-1.0, 1.0]:
		var a := GeometryKit.solid_box(root, Vector3(0.0, height + ph * 0.5, side * (footprint.y * 0.5 - 0.15)), Vector3(footprint.x, ph, 0.3), stone)
		a.set_instance_shader_parameter(&"tint", parapet_tint)
		var b := GeometryKit.solid_box(root, Vector3(side * (footprint.x * 0.5 - 0.15), height + ph * 0.5, 0.0), Vector3(0.3, ph, footprint.y - 0.6), stone)
		b.set_instance_shader_parameter(&"tint", parapet_tint)
	var coping := MaterialLibrary.coated(Color(0.25, 0.26, 0.27), 0.8, 0.4)
	GeometryKit.mesh_box(root, Vector3(0.0, height + ph + 0.03, -footprint.y * 0.5 + 0.15), Vector3(footprint.x + 0.05, 0.06, 0.36), coping)
	GeometryKit.mesh_box(root, Vector3(0.0, height + ph + 0.03, footprint.y * 0.5 - 0.15), Vector3(footprint.x + 0.05, 0.06, 0.36), coping)

	if fire_escape_face >= 0 and style == Style.BRICK:
		_add_fire_escape(root, footprint, height, fire_escape_face)
	if rooftop:
		_add_rooftop(root, footprint, height, style, rng)


## Cheap silhouette building for the skyline beyond the playable area.
static func skyline(parent: Node3D, center: Vector3, footprint: Vector2, height: float, rng: RandomNumberGenerator) -> void:
	var style: Style = Style.GLASS if rng.randf() < 0.4 else Style.CONCRETE
	var mass := GeometryKit.mesh_box(parent, center + Vector3(0.0, height * 0.5, 0.0), Vector3(footprint.x, height, footprint.y), MaterialLibrary.facade())
	GeometryKit.set_facade(mass, _pick_color(style, rng), float(style), rng.randf_range(0.0, 100.0), rng.randf_range(0.25, 0.5), center.y, center.y + height, false)
	if rng.randf() < 0.5:
		PropFactory.antenna(parent, center + Vector3(0.0, height, 0.0), rng.randf_range(4.0, 9.0))


static func _pick_color(style: Style, rng: RandomNumberGenerator) -> Color:
	match style:
		Style.BRICK:
			return BRICK_COLORS[rng.randi_range(0, BRICK_COLORS.size() - 1)]
		Style.GLASS:
			return GLASS_COLORS[rng.randi_range(0, GLASS_COLORS.size() - 1)]
	return CONCRETE_COLORS[rng.randi_range(0, CONCRETE_COLORS.size() - 1)]


static func _add_awnings(root: Node3D, footprint: Vector2, rng: RandomNumberGenerator) -> void:
	var frame := MaterialLibrary.coated(Color(0.1, 0.1, 0.1), 0.8, 0.4)
	for face: int in 4:
		var along: float = footprint.x if face < 2 else footprint.y
		var count: int = int(along / 6.5)
		for i: int in count:
			if rng.randf() > 0.45:
				continue
			var t: float = -along * 0.5 + (float(i) + 0.5) * along / float(count)
			var cloth := MaterialLibrary.fabric(AWNING_COLORS[rng.randi_range(0, AWNING_COLORS.size() - 1)])
			var offset: float = (footprint.y if face < 2 else footprint.x) * 0.5 + 0.6
			var normals: Array[Vector3] = [Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0)]
			var tilts: Array[Vector3] = [Vector3(18.0, 0.0, 0.0), Vector3(-18.0, 0.0, 0.0), Vector3(0.0, 0.0, -18.0), Vector3(0.0, 0.0, 18.0)]
			var n: Vector3 = normals[face]
			var tangent := Vector3(1.0, 0.0, 0.0) if face < 2 else Vector3(0.0, 0.0, 1.0)
			var pos: Vector3 = n * offset + tangent * t + Vector3(0.0, 3.45, 0.0)
			var size: Vector3 = Vector3(3.0, 0.05, 1.3) if face < 2 else Vector3(1.3, 0.05, 3.0)
			GeometryKit.tilted_box(root, pos, size, tilts[face], cloth)
			var strip: Vector3 = tangent * 3.0 + n.abs() * 0.03
			GeometryKit.mesh_box(root, pos + n * 0.62 + Vector3(0.0, -0.32, 0.0), strip + Vector3(0.0, 0.25, 0.0), cloth)
			GeometryKit.mesh_box(root, pos - n * 0.6 + Vector3(0.0, 0.22, 0.0), tangent * 3.0 + Vector3(0.04, 0.04, 0.04), frame)


static func _add_fire_escape(root: Node3D, footprint: Vector2, height: float, face: int) -> void:
	var iron := MaterialLibrary.coated(Color(0.09, 0.09, 0.1), 0.85, 0.55)
	var grate := MaterialLibrary.coated(Color(0.12, 0.12, 0.13), 0.9, 0.5)
	var out: Vector3
	var along: Vector3
	var half_depth: float
	match face:
		0:
			out = Vector3(1.0, 0.0, 0.0)
			along = Vector3(0.0, 0.0, 1.0)
			half_depth = footprint.x * 0.5
		1:
			out = Vector3(-1.0, 0.0, 0.0)
			along = Vector3(0.0, 0.0, 1.0)
			half_depth = footprint.x * 0.5
		2:
			out = Vector3(0.0, 0.0, 1.0)
			along = Vector3(1.0, 0.0, 0.0)
			half_depth = footprint.y * 0.5
		_:
			out = Vector3(0.0, 0.0, -1.0)
			along = Vector3(1.0, 0.0, 0.0)
			half_depth = footprint.y * 0.5
	var platform_size: Vector3 = Vector3(0.05, 0.08, 0.0)
	var width: float = 3.6
	var depth: float = 1.2
	var floors: int = int((height - GROUND_FLOOR) / FLOOR_HEIGHT)
	for i: int in floors:
		var y: float = GROUND_FLOOR + float(i) * FLOOR_HEIGHT - 0.05
		var c: Vector3 = out * (half_depth + depth * 0.5) + Vector3(0.0, y, 0.0)
		platform_size = along.abs() * width + out.abs() * depth + Vector3(0.0, 0.06, 0.0)
		GeometryKit.solid_box(root, c, platform_size, grate)
		var rail_c: Vector3 = out * (half_depth + depth) + Vector3(0.0, y + 0.5, 0.0)
		GeometryKit.mesh_box(root, rail_c, along.abs() * width + Vector3(0.04, 0.04, 0.04), iron)
		GeometryKit.mesh_box(root, rail_c - Vector3(0.0, 0.25, 0.0), along.abs() * width + Vector3(0.02, 0.02, 0.02), iron)
		for j: int in 5:
			var p: Vector3 = rail_c + along * (-width * 0.5 + width * float(j) / 4.0) - Vector3(0.0, 0.25, 0.0)
			GeometryKit.mesh_box(root, p, Vector3(0.03, 0.55, 0.03), iron)
		if i < floors - 1:
			# Diagonal stair flight to the next landing.
			var mid: Vector3 = out * (half_depth + depth * 0.5) + Vector3(0.0, y + FLOOR_HEIGHT * 0.5, 0.0)
			var flight := GeometryKit.mesh_box(root, mid, Vector3(0.7, 0.05, 4.3) if face < 2 else Vector3(4.3, 0.05, 0.7), grate)
			if face < 2:
				flight.rotation_degrees = Vector3(-52.0, 0.0, 0.0)
			else:
				flight.rotation_degrees = Vector3(0.0, 0.0, 52.0)
	# Drop ladder.
	var ladder_c: Vector3 = out * (half_depth + depth - 0.1) + along * (width * 0.5 - 0.3) + Vector3(0.0, GROUND_FLOOR * 0.5 + 1.0, 0.0)
	GeometryKit.mesh_box(root, ladder_c, Vector3(0.04, GROUND_FLOOR - 2.0, 0.04) + along.abs() * 0.4, iron)


static func _add_rooftop(root: Node3D, footprint: Vector2, height: float, style: Style, rng: RandomNumberGenerator) -> void:
	var top := Vector3(0.0, height, 0.0)
	var hx: float = footprint.x * 0.5 - 2.0
	var hz: float = footprint.y * 0.5 - 2.0
	if hx < 1.5 or hz < 1.5:
		return
	if style == Style.BRICK and rng.randf() < 0.6:
		PropFactory.water_tower(root, top + Vector3(rng.randf_range(-hx, hx) * 0.6, 0.0, rng.randf_range(-hz, hz) * 0.6))
	else:
		PropFactory.stair_house(root, top + Vector3(rng.randf_range(-hx, hx) * 0.5, 0.0, rng.randf_range(-hz, hz) * 0.5), Color(0.5, 0.49, 0.47))
	for i: int in rng.randi_range(1, 3):
		PropFactory.ac_unit(root, top + Vector3(rng.randf_range(-hx, hx), 0.0, rng.randf_range(-hz, hz)), rng.randf_range(0.0, 90.0))
	if rng.randf() < 0.5:
		PropFactory.antenna(root, top + Vector3(rng.randf_range(-hx, hx), 0.0, rng.randf_range(-hz, hz)), rng.randf_range(3.0, 6.0))
