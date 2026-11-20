class_name PropFactory
extends RefCounted
## Street furniture and rooftop clutter built from primitives + procedural materials.
## Props that should block movement get world-layer colliders (and thus carve the navmesh).

static func street_lamp(parent: Node3D, base: Vector3, facing_yaw_degrees: float) -> void:
	var pole_mat := MaterialLibrary.coated(Color(0.12, 0.13, 0.14), 0.7, 0.45)
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees = Vector3(0.0, facing_yaw_degrees, 0.0)
	parent.add_child(root)
	GeometryKit.collider_box(root, Vector3(0.0, 2.0, 0.0), Vector3(0.25, 4.0, 0.25))
	GeometryKit.cylinder(root, Vector3(0.0, 0.25, 0.0), 0.16, 0.2, 0.5, pole_mat, 10)
	GeometryKit.cylinder(root, Vector3(0.0, 3.2, 0.0), 0.07, 0.1, 5.9, pole_mat, 10)
	GeometryKit.tilted_box(root, Vector3(0.0, 6.05, -0.75), Vector3(0.08, 0.08, 1.6), Vector3(-8.0, 0.0, 0.0), pole_mat)
	GeometryKit.mesh_box(root, Vector3(0.0, 5.98, -1.5), Vector3(0.36, 0.12, 0.6), pole_mat)
	GeometryKit.mesh_box(root, Vector3(0.0, 5.91, -1.5), Vector3(0.3, 0.03, 0.5), MaterialLibrary.emissive(Color(1.0, 0.78, 0.5), 6.0))
	var light := SpotLight3D.new()
	light.light_color = Color(1.0, 0.76, 0.48)
	light.light_energy = 14.0
	light.spot_range = 16.0
	light.spot_angle = 66.0
	light.spot_attenuation = 0.9
	light.light_volumetric_fog_energy = 1.5
	light.position = Vector3(0.0, 5.85, -1.5)
	light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	root.add_child(light)


static func tree(parent: Node3D, base: Vector3, rng: RandomNumberGenerator) -> void:
	var bark := MaterialLibrary.surface(Color(0.2, 0.15, 0.11), 0.95, 0.0, 1.4, 5.0)
	var soil := MaterialLibrary.surface(Color(0.12, 0.09, 0.07), 1.0, 0.0, 1.0, 4.0)
	var grate := MaterialLibrary.coated(Color(0.08, 0.08, 0.085), 0.8, 0.5)
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
	parent.add_child(root)
	GeometryKit.mesh_box(root, Vector3(0.0, 0.01, 0.0), Vector3(1.4, 0.04, 1.4), grate)
	GeometryKit.mesh_box(root, Vector3(0.0, 0.0, 0.0), Vector3(1.2, 0.04, 1.2), soil)
	GeometryKit.collider_box(root, Vector3(0.0, 1.5, 0.0), Vector3(0.4, 3.0, 0.4))
	var height: float = rng.randf_range(3.2, 4.2)
	GeometryKit.cylinder(root, Vector3(0.0, height * 0.5, 0.0), 0.12, 0.2, height, bark, 10)
	GeometryKit.tilted_box(root, Vector3(0.35, height - 0.4, 0.0), Vector3(0.09, 1.1, 0.09), Vector3(0.0, 0.0, -40.0), bark)
	GeometryKit.tilted_box(root, Vector3(-0.3, height - 0.2, 0.2), Vector3(0.08, 1.0, 0.08), Vector3(25.0, 0.0, 35.0), bark)
	var leaves := MaterialLibrary.foliage()
	var clusters: int = 7
	for i: int in clusters:
		var angle: float = TAU * float(i) / float(clusters) + rng.randf_range(-0.3, 0.3)
		var r: float = rng.randf_range(0.6, 1.2)
		var y: float = height + rng.randf_range(-0.2, 1.1)
		var size: float = rng.randf_range(0.8, 1.25)
		GeometryKit.sphere(root, Vector3(cos(angle) * r, y, sin(angle) * r), size, leaves, Vector3(1.0, 0.8, 1.0))
	GeometryKit.sphere(root, Vector3(0.0, height + 1.2, 0.0), 1.2, leaves, Vector3(1.0, 0.85, 1.0))


static func bench(parent: Node3D, base: Vector3, yaw: float) -> void:
	var wood := MaterialLibrary.surface(Color(0.32, 0.2, 0.11), 0.75, 0.0, 1.0, 6.0)
	var iron := MaterialLibrary.coated(Color(0.1, 0.1, 0.11), 0.8, 0.45)
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees = Vector3(0.0, yaw, 0.0)
	parent.add_child(root)
	for i: int in 3:
		GeometryKit.mesh_box(root, Vector3(0.0, 0.45, -0.15 + i * 0.15), Vector3(1.8, 0.04, 0.12), wood)
	for i: int in 2:
		GeometryKit.tilted_box(root, Vector3(0.0, 0.72 + i * 0.16, 0.24), Vector3(1.8, 0.12, 0.04), Vector3(-12.0, 0.0, 0.0), wood)
	for x: float in [-0.75, 0.75]:
		GeometryKit.mesh_box(root, Vector3(x, 0.22, 0.0), Vector3(0.06, 0.44, 0.5), iron)
		GeometryKit.mesh_box(root, Vector3(x, 0.6, 0.25), Vector3(0.06, 0.5, 0.05), iron)


static func bin(parent: Node3D, base: Vector3) -> void:
	var body := MaterialLibrary.coated(Color(0.1, 0.2, 0.14), 0.4, 0.5)
	GeometryKit.cylinder(parent, base + Vector3(0.0, 0.45, 0.0), 0.28, 0.25, 0.9, body, 14)
	GeometryKit.cylinder(parent, base + Vector3(0.0, 0.93, 0.0), 0.3, 0.3, 0.06, MaterialLibrary.coated(Color(0.06, 0.06, 0.06), 0.5, 0.5), 14)


static func hydrant(parent: Node3D, base: Vector3) -> void:
	var red := MaterialLibrary.coated(Color(0.6, 0.06, 0.04), 0.4, 0.45)
	GeometryKit.cylinder(parent, base + Vector3(0.0, 0.3, 0.0), 0.12, 0.14, 0.6, red, 12)
	GeometryKit.sphere(parent, base + Vector3(0.0, 0.62, 0.0), 0.12, red)
	var nozzle := GeometryKit.cylinder(parent, base + Vector3(0.0, 0.4, 0.0), 0.06, 0.06, 0.4, red, 8)
	nozzle.rotation_degrees = Vector3(0.0, 0.0, 90.0)


static func traffic_light(parent: Node3D, base: Vector3, yaw: float, phase: int) -> void:
	var pole := MaterialLibrary.coated(Color(0.15, 0.16, 0.17), 0.7, 0.4)
	var housing := MaterialLibrary.coated(Color(0.05, 0.05, 0.05), 0.3, 0.6)
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees = Vector3(0.0, yaw, 0.0)
	parent.add_child(root)
	GeometryKit.collider_box(root, Vector3(0.0, 1.8, 0.0), Vector3(0.2, 3.6, 0.2))
	GeometryKit.cylinder(root, Vector3(0.0, 2.4, 0.0), 0.07, 0.08, 4.8, pole, 10)
	GeometryKit.mesh_box(root, Vector3(0.0, 4.2, -0.2), Vector3(0.32, 0.95, 0.28), housing)
	var colors: Array[Color] = [Color(1.0, 0.1, 0.05), Color(1.0, 0.65, 0.05), Color(0.1, 1.0, 0.35)]
	for i: int in 3:
		var lit: bool = i == phase
		var lens := GeometryKit.cylinder(root, Vector3(0.0, 4.5 - i * 0.3, -0.35), 0.09, 0.09, 0.03, MaterialLibrary.emissive(colors[i], 5.0 if lit else 0.15), 12)
		lens.rotation_degrees = Vector3(90.0, 0.0, 0.0)


static func bus_stop(parent: Node3D, base: Vector3, yaw: float) -> void:
	var frame := MaterialLibrary.coated(Color(0.2, 0.21, 0.22), 0.8, 0.35)
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees = Vector3(0.0, yaw, 0.0)
	parent.add_child(root)
	GeometryKit.collider_box(root, Vector3(0.0, 1.2, 0.6), Vector3(3.6, 2.4, 0.1))
	GeometryKit.mesh_box(root, Vector3(0.0, 2.5, 0.0), Vector3(3.8, 0.08, 1.5), frame)
	GeometryKit.mesh_box(root, Vector3(0.0, 1.25, 0.65), Vector3(3.6, 2.3, 0.04), MaterialLibrary.glass(Color(0.08, 0.1, 0.12)))
	GeometryKit.mesh_box(root, Vector3(1.2, 1.4, 0.6), Vector3(1.0, 1.6, 0.08), MaterialLibrary.emissive(Color(0.85, 0.9, 1.0), 2.2))
	for x: float in [-1.85, 1.85]:
		GeometryKit.mesh_box(root, Vector3(x, 1.25, 0.0), Vector3(0.08, 2.5, 1.4), frame)
	bench(root, Vector3(-0.6, 0.0, 0.25), 180.0)


static func water_tower(parent: Node3D, base: Vector3) -> void:
	var wood := MaterialLibrary.surface(Color(0.33, 0.24, 0.16), 0.9, 0.0, 1.6, 2.0)
	var steel := MaterialLibrary.coated(Color(0.12, 0.12, 0.12), 0.8, 0.5)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			GeometryKit.mesh_box(parent, base + Vector3(x, 1.2, z), Vector3(0.12, 2.4, 0.12), steel)
	GeometryKit.mesh_box(parent, base + Vector3(0.0, 2.4, 0.0), Vector3(2.4, 0.1, 2.4), steel)
	GeometryKit.cylinder(parent, base + Vector3(0.0, 3.6, 0.0), 1.3, 1.35, 2.4, wood, 18)
	GeometryKit.cylinder(parent, base + Vector3(0.0, 5.2, 0.0), 0.05, 1.4, 0.8, steel, 18)
	for y: float in [2.8, 4.4]:
		GeometryKit.cylinder(parent, base + Vector3(0.0, y, 0.0), 1.37, 1.37, 0.05, steel, 18)


static func ac_unit(parent: Node3D, base: Vector3, yaw: float) -> void:
	var metal := MaterialLibrary.metal_panel()
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees = Vector3(0.0, yaw, 0.0)
	parent.add_child(root)
	var box := GeometryKit.solid_box(root, Vector3(0.0, 0.6, 0.0), Vector3(1.8, 1.2, 1.2), metal)
	box.set_instance_shader_parameter(&"paint_color", Color(0.55, 0.56, 0.55))
	GeometryKit.cylinder(root, Vector3(0.0, 1.21, 0.0), 0.45, 0.45, 0.02, MaterialLibrary.coated(Color(0.05, 0.05, 0.05), 0.5, 0.6), 18)
	GeometryKit.mesh_box(root, Vector3(1.0, 0.25, 0.0), Vector3(0.2, 0.15, 0.15), MaterialLibrary.coated(Color(0.4, 0.4, 0.4), 0.9, 0.3))


static func antenna(parent: Node3D, base: Vector3, height: float) -> void:
	var steel := MaterialLibrary.coated(Color(0.2, 0.2, 0.21), 0.9, 0.35)
	GeometryKit.cylinder(parent, base + Vector3(0.0, height * 0.5, 0.0), 0.03, 0.06, height, steel, 8)
	for i: int in 3:
		GeometryKit.mesh_box(parent, base + Vector3(0.0, height * (0.55 + i * 0.12), 0.0), Vector3(0.9 - i * 0.2, 0.03, 0.03), steel)
	GeometryKit.sphere(parent, base + Vector3(0.0, height, 0.0), 0.06, MaterialLibrary.emissive(Color(1.0, 0.1, 0.05), 6.0))


static func stair_house(parent: Node3D, base: Vector3, color: Color) -> void:
	var walls := GeometryKit.solid_box(parent, base + Vector3(0.0, 1.4, 0.0), Vector3(3.0, 2.8, 3.4), MaterialLibrary.concrete())
	walls.set_instance_shader_parameter(&"tint", color)
	GeometryKit.mesh_box(parent, base + Vector3(0.0, 1.05, -1.71), Vector3(1.0, 2.1, 0.04), MaterialLibrary.coated(Color(0.25, 0.2, 0.15), 0.4, 0.5))
	GeometryKit.mesh_box(parent, base + Vector3(0.0, 2.3, -1.75), Vector3(0.3, 0.12, 0.12), MaterialLibrary.emissive(Color(1.0, 0.85, 0.6), 3.0))


static func crate(parent: Node3D, base: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var wood := MaterialLibrary.surface(Color(0.45, 0.33, 0.2).darkened(rng.randf_range(0.0, 0.3)), 0.85, 0.0, 1.6, 3.0)
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees = Vector3(0.0, rng.randf_range(-12.0, 12.0), 0.0)
	parent.add_child(root)
	GeometryKit.solid_box(root, Vector3(0.0, size * 0.5, 0.0), Vector3.ONE * size, wood)
	var slat := MaterialLibrary.surface(Color(0.3, 0.22, 0.13), 0.85, 0.0, 1.0, 3.0)
	for side: float in [-1.0, 1.0]:
		GeometryKit.mesh_box(root, Vector3(0.0, size * 0.5, side * (size * 0.5 + 0.01)), Vector3(size, 0.1, 0.02), slat)
		GeometryKit.mesh_box(root, Vector3(side * (size * 0.5 + 0.01), size * 0.5, 0.0), Vector3(0.02, 0.1, size), slat)


static func shipping_container(parent: Node3D, base: Vector3, yaw: float, color: Color) -> void:
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees = Vector3(0.0, yaw, 0.0)
	parent.add_child(root)
	var body := GeometryKit.solid_box(root, Vector3(0.0, 1.3, 0.0), Vector3(2.44, 2.6, 6.1), MaterialLibrary.metal_panel())
	body.set_instance_shader_parameter(&"paint_color", color)
	var rib := MaterialLibrary.coated(color.darkened(0.3), 0.6, 0.5)
	for i: int in 9:
		var z: float = -2.8 + i * 0.7
		for side: float in [-1.0, 1.0]:
			GeometryKit.mesh_box(root, Vector3(side * 1.23, 1.3, z), Vector3(0.04, 2.5, 0.12), rib)
	GeometryKit.mesh_box(root, Vector3(0.0, 1.3, 3.06), Vector3(2.3, 2.4, 0.04), rib)
	for x: float in [-0.4, 0.4]:
		GeometryKit.mesh_box(root, Vector3(x, 1.3, 3.1), Vector3(0.05, 2.3, 0.05), MaterialLibrary.coated(Color(0.6, 0.6, 0.6), 1.0, 0.3))


static func jersey_barrier(parent: Node3D, base: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees = Vector3(0.0, yaw, 0.0)
	parent.add_child(root)
	var low := GeometryKit.solid_box(root, Vector3(0.0, 0.25, 0.0), Vector3(0.6, 0.5, 3.0), MaterialLibrary.concrete())
	low.set_instance_shader_parameter(&"tint", Color(0.62, 0.6, 0.56))
	var top := GeometryKit.mesh_box(root, Vector3(0.0, 0.7, 0.0), Vector3(0.25, 0.4, 3.0), MaterialLibrary.concrete())
	top.set_instance_shader_parameter(&"tint", Color(0.62, 0.6, 0.56))
	GeometryKit.mesh_box(root, Vector3(0.0, 0.88, 0.0), Vector3(0.26, 0.08, 3.0), MaterialLibrary.emissive(Color(1.0, 0.5, 0.05), 1.0))
