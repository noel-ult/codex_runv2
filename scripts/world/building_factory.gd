class_name BuildingFactory
extends RefCounted
## Builds structured buildings: shader-textured facade mass (brick / concrete / glass),
## stone plinth, cornice and parapet, shop awnings, fire escapes and rooftop clutter
## (water towers, A/C units, stair houses, antennas).

enum Style { BRICK, CONCRETE, GLASS }

const FLOOR_HEIGHT: float = 3.4
const GROUND_FLOOR: float = 4.2
const WINDOW_SPACING: float = 2.7
const SHOP_SPACING: float = 3.4

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
	_add_facade_trim(root, footprint, height, style, storefront)


## Build trim in the same world aligned bays as facade.gdshader. The existing wall
## provides the glass and interiors behind the trim, plus all of the collision.
static func _add_facade_trim(root: Node3D, footprint: Vector2, height: float, style: Style, storefront: bool) -> void:
	var trim: Array[Transform3D] = []
	var frames: Array[Transform3D] = []
	var glass: bool = style == Style.GLASS
	var floor_base: float = GROUND_FLOOR if storefront else 0.0
	var top: float = height - 0.9
	for normal: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var tangent: Vector3 = normal.cross(Vector3.UP)
		var half_width: float = absf(tangent.x) * footprint.x * 0.5 + absf(tangent.z) * footprint.y * 0.5
		var wall_depth: float = absf(normal.x) * footprint.x * 0.5 + absf(normal.z) * footprint.y * 0.5
		var face := Transform3D(Basis(tangent, Vector3.UP, -normal), normal * wall_depth)
		var world_u: float = root.global_position.dot(tangent)
		for column: int in range(floori((world_u - half_width) / WINDOW_SPACING), ceili((world_u + half_width) / WINDOW_SPACING)):
			var bay: float = float(column) * WINDOW_SPACING - world_u
			var left: float = bay + WINDOW_SPACING * (0.04 if glass else 0.24)
			var right: float = bay + WINDOW_SPACING * (0.96 if glass else 0.76)
			for level: int in ceili((top - floor_base) / FLOOR_HEIGHT):
				var floor_y: float = floor_base + float(level) * FLOOR_HEIGHT
				var bottom: float = maxf(floor_y + FLOOR_HEIGHT * (0.06 if glass else 0.30), 0.6)
				var end_y: float = minf(floor_y + FLOOR_HEIGHT * (0.96 if glass else 0.86), top)
				if end_y - bottom < 0.35:
					continue
				if glass:
					var opening := Rect2(left, bottom, right - left, end_y - bottom)
					_add_frame(frames, face, opening, half_width, 0.085, 0.11, 0.12)
					_add_trim_box(frames, face, Rect2((left + right) * 0.5 - 0.025, bottom, 0.05, end_y - bottom), half_width, 0.065)
				else:
					var opening := Rect2(left - 0.045, bottom, right - left + 0.09, end_y - bottom)
					_add_frame(frames, face, opening, half_width, 0.065, 0.095, 0.07)
					_add_trim_box(trim, face, Rect2(left - 0.17, bottom - 0.15, right - left + 0.34, 0.145), half_width, 0.29)
					_add_trim_box(trim, face, Rect2(left - 0.11, end_y - 0.035, right - left + 0.22, 0.17), half_width, 0.19)
		if storefront:
			for column: int in range(floori((world_u - half_width) / SHOP_SPACING), ceili((world_u + half_width) / SHOP_SPACING)):
				var bay: float = float(column) * SHOP_SPACING - world_u
				var opening := Rect2(bay + 0.33, 0.39, 2.74, 3.47)
				_add_frame(frames, face, opening, half_width, 0.11, 0.12, 0.18)
				_add_trim_box(frames, face, Rect2(bay + 1.66, 0.39, 0.08, 2.66), half_width, 0.15)
				_add_trim_box(trim, face, Rect2(bay + 0.24, 2.98, 2.92, 0.14), half_width, 0.24)
				_add_trim_box(trim, face, Rect2(bay + 0.23, 0.30, 2.94, 0.15), half_width, 0.27)
				_add_trim_box(trim, face, Rect2(bay - 0.16, 0.39, 0.32, 3.64), half_width, 0.21)
	var masonry: Color = Color(0.48, 0.42, 0.35) if style == Style.BRICK else Color(0.42, 0.43, 0.44)
	var metal: Color = Color(0.32, 0.38, 0.44) if glass else Color(0.19, 0.20, 0.21)
	_add_trim_batch(root, "StoneTrim", MaterialLibrary.surface(masonry, 0.87, 0.0, 0.45, 6.0), trim)
	_add_trim_batch(root, "WindowFrames", MaterialLibrary.surface(metal, 0.46, 0.34, 0.16, 8.0), frames)


static func _add_frame(parts: Array[Transform3D], face: Transform3D, opening: Rect2, half_width: float, stile: float, rail: float, depth: float) -> void:
	_add_trim_box(parts, face, Rect2(opening.position.x, opening.position.y, stile, opening.size.y), half_width, depth)
	_add_trim_box(parts, face, Rect2(opening.end.x - stile, opening.position.y, stile, opening.size.y), half_width, depth)
	_add_trim_box(parts, face, Rect2(opening.position.x + stile, opening.position.y, opening.size.x - stile * 2.0, rail), half_width, depth)
	_add_trim_box(parts, face, Rect2(opening.position.x + stile, opening.end.y - rail, opening.size.x - stile * 2.0, rail), half_width, depth)


static func _add_trim_box(parts: Array[Transform3D], face: Transform3D, rect: Rect2, half_width: float, depth: float) -> void:
	var left: float = maxf(rect.position.x, -half_width + 0.035)
	var right: float = minf(rect.end.x, half_width - 0.035)
	if right - left < 0.025:
		return
	var center := Vector3((left + right) * 0.5, rect.get_center().y, 0.018 - depth * 0.5)
	parts.append(face * Transform3D(Basis.from_scale(Vector3(right - left, rect.size.y, depth)), center))


static func _add_trim_batch(parent: Node3D, node_name: String, material: Material, parts: Array[Transform3D]) -> void:
	if parts.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = material
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = box
	batch.instance_count = parts.size()
	for index: int in parts.size():
		batch.set_instance_transform(index, parts[index])
	var detail := MultiMeshInstance3D.new()
	detail.name = node_name
	detail.multimesh = batch
	parent.add_child(detail)


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
			for side: float in [-1.18, 1.18]:
				var foot: Vector3 = pos - n * 0.59 + tangent * side - Vector3.UP * 0.75
				var tip: Vector3 = pos + n * 0.49 + tangent * side - Vector3.UP * 0.2
				var brace: Vector3 = tip - foot
				var support: MeshInstance3D = GeometryKit.mesh_box(root, (foot + tip) * 0.5, Vector3(0.065, 0.065, brace.length()), frame)
				support.basis = Basis.looking_at(brace.normalized())


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
