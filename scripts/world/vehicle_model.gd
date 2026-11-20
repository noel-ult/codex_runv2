class_name VehicleModel
extends RefCounted
## Procedural car / van / taxi bodies built from primitives with clear-coat paint,
## glass, chrome trim, tyres with hubs, head/tail lights. Used by moving decoy vehicles
## and by parked cars. The model faces -Z (front) and sits on y = 0.

enum Kind { SEDAN, VAN, TAXI }


## Builds the body under `parent` and returns the wheel pivots (spin them around X).
static func build(parent: Node3D, kind: Kind, paint_color: Color, with_lights: bool) -> Array[Node3D]:
	var paint := MaterialLibrary.coated(paint_color, 0.55, 0.28)
	var trim := MaterialLibrary.coated(Color(0.04, 0.04, 0.045), 0.3, 0.5)
	var chrome := MaterialLibrary.coated(Color(0.75, 0.76, 0.78), 1.0, 0.15)
	var glass := MaterialLibrary.glass(Color(0.03, 0.045, 0.06))
	var tyre := MaterialLibrary.surface(Color(0.03, 0.03, 0.03), 0.9, 0.0, 0.6, 6.0)
	var head := MaterialLibrary.emissive(Color(1.0, 0.95, 0.82), 5.0 if with_lights else 0.4)
	var tail := MaterialLibrary.emissive(Color(1.0, 0.06, 0.04), 3.0 if with_lights else 0.3)

	var length: float = 4.5 if kind != Kind.VAN else 5.0
	var width: float = 1.9 if kind != Kind.VAN else 2.05
	var half_l: float = length * 0.5

	# Lower body + bumpers + sills.
	GeometryKit.mesh_box(parent, Vector3(0.0, 0.62, 0.0), Vector3(width, 0.55, length), paint)
	GeometryKit.mesh_box(parent, Vector3(0.0, 0.42, -half_l + 0.05), Vector3(width + 0.04, 0.22, 0.14), trim)
	GeometryKit.mesh_box(parent, Vector3(0.0, 0.42, half_l - 0.05), Vector3(width + 0.04, 0.22, 0.14), trim)
	GeometryKit.mesh_box(parent, Vector3(0.0, 0.36, 0.0), Vector3(width + 0.02, 0.1, length - 1.6), trim)
	GeometryKit.mesh_box(parent, Vector3(0.0, 0.84, 0.0), Vector3(width + 0.01, 0.03, length - 0.3), chrome)

	if kind == Kind.VAN:
		GeometryKit.mesh_box(parent, Vector3(0.0, 1.55, 0.45), Vector3(width - 0.05, 1.35, length - 1.3), paint)
		GeometryKit.tilted_box(parent, Vector3(0.0, 1.35, -half_l + 0.9), Vector3(width - 0.2, 0.9, 0.06), Vector3(-28.0, 0.0, 0.0), glass)
		for side: float in [-1.0, 1.0]:
			GeometryKit.mesh_box(parent, Vector3(side * (width * 0.5 - 0.02), 1.5, -half_l + 1.5), Vector3(0.05, 0.6, 0.9), glass)
			GeometryKit.mesh_box(parent, Vector3(side * (width * 0.5), 1.0, 0.6), Vector3(0.02, 0.04, 2.6), chrome)
	else:
		# Cabin: roof, A/C pillars, slanted screens, side glass.
		GeometryKit.mesh_box(parent, Vector3(0.0, 1.32, 0.25), Vector3(width - 0.22, 0.06, 1.9), paint)
		GeometryKit.tilted_box(parent, Vector3(0.0, 1.1, -0.95), Vector3(width - 0.28, 0.05, 0.95), Vector3(-36.0, 0.0, 0.0), glass)
		GeometryKit.tilted_box(parent, Vector3(0.0, 1.08, 1.45), Vector3(width - 0.3, 0.05, 0.85), Vector3(30.0, 0.0, 0.0), glass)
		for side: float in [-1.0, 1.0]:
			GeometryKit.tilted_box(parent, Vector3(side * (width * 0.5 - 0.14), 1.08, 0.25), Vector3(0.04, 0.42, 2.3), Vector3(0.0, 0.0, side * 8.0), glass)
			GeometryKit.mesh_box(parent, Vector3(side * (width * 0.5 - 0.12), 1.08, 0.25), Vector3(0.05, 0.46, 0.06), paint)
			GeometryKit.mesh_box(parent, Vector3(side * (width * 0.5 + 0.08), 1.0, -0.6), Vector3(0.12, 0.09, 0.18), paint)
		if kind == Kind.TAXI:
			GeometryKit.mesh_box(parent, Vector3(0.0, 1.45, 0.25), Vector3(0.7, 0.2, 0.3), MaterialLibrary.emissive(Color(1.0, 0.85, 0.3), 2.5))

	# Lights + plates.
	for side: float in [-1.0, 1.0]:
		GeometryKit.mesh_box(parent, Vector3(side * (width * 0.5 - 0.28), 0.72, -half_l - 0.005), Vector3(0.42, 0.13, 0.04), head)
		GeometryKit.mesh_box(parent, Vector3(side * (width * 0.5 - 0.22), 0.76, half_l + 0.005), Vector3(0.36, 0.12, 0.04), tail)
	GeometryKit.mesh_box(parent, Vector3(0.0, 0.48, half_l + 0.04), Vector3(0.52, 0.12, 0.02), MaterialLibrary.surface(Color(0.9, 0.9, 0.85), 0.5, 0.0, 0.0))
	GeometryKit.mesh_box(parent, Vector3(0.0, 0.66, -half_l - 0.01), Vector3(0.8, 0.14, 0.02), chrome)

	if with_lights:
		for side: float in [-1.0, 1.0]:
			var beam := SpotLight3D.new()
			beam.light_color = Color(1.0, 0.93, 0.8)
			beam.light_energy = 4.0
			beam.spot_range = 22.0
			beam.spot_angle = 28.0
			beam.position = Vector3(side * 0.6, 0.75, -half_l - 0.1)
			beam.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
			parent.add_child(beam)

	# Wheels with arches and hubs.
	var wheels: Array[Node3D] = []
	var axle: float = half_l - 0.85
	for x: float in [-1.0, 1.0]:
		for z: float in [-axle, axle]:
			GeometryKit.mesh_box(parent, Vector3(x * (width * 0.5 - 0.05), 0.62, z), Vector3(0.14, 0.5, 0.9), trim)
			var pivot := Node3D.new()
			pivot.position = Vector3(x * (width * 0.5 - 0.12), 0.36, z)
			parent.add_child(pivot)
			var wheel := GeometryKit.cylinder(pivot, Vector3.ZERO, 0.36, 0.36, 0.24, tyre, 20)
			wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			var hub := GeometryKit.cylinder(pivot, Vector3(x * 0.125, 0.0, 0.0), 0.22, 0.22, 0.02, chrome, 12)
			hub.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			GeometryKit.mesh_box(pivot, Vector3(x * 0.13, 0.0, 0.0), Vector3(0.02, 0.3, 0.05), trim)
			wheels.append(pivot)
	return wheels


static func random_paint(rng: RandomNumberGenerator) -> Color:
	var palette: Array[Color] = [
		Color(0.55, 0.06, 0.06), Color(0.08, 0.12, 0.25), Color(0.75, 0.75, 0.73), Color(0.05, 0.05, 0.055),
		Color(0.25, 0.27, 0.28), Color(0.1, 0.22, 0.17), Color(0.5, 0.42, 0.3), Color(0.9, 0.9, 0.88),
	]
	return palette[rng.randi_range(0, palette.size() - 1)]
