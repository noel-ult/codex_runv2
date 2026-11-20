class_name FacilityCompound
extends Node3D
## Guarded research compound that holds the Codex Uplink Key (the Device).
##
## Ways in:
##   1. South vehicle gate - opens only for Hunters; slip through behind one.
##   2. West side door     - hold E at the panel to hack it (Resonance spike).
##   3. Over the wall / onto the 10 m roof - Full Form + Super Jump, then the roof hatch.
## Inside: yard with cover, a searchlight tower, CCTV, a loading-bay hall and a vault
## (hack the vault console, or drop in through the hatch) with the Device on a pedestal.
## The compound never references Hunters; it only emits signals.

signal intruder_spotted(world_position: Vector3)
signal hack_completed(label: String, resonance_cost: float)
signal device_collected()
signal entered_via_hatch()

const HALF: float = 20.6
const WALL_HEIGHT: float = 6.0
const WALL_THICK: float = 0.8
const BUILDING_MIN: Vector2 = Vector2(-11.0, -15.0)
const BUILDING_MAX: Vector2 = Vector2(13.0, 3.0)
const BUILDING_HEIGHT: float = 10.0
const SKIN: float = 0.5
const VAULT_WALL_Z: float = -6.0
const DEVICE_LOCAL: Vector3 = Vector3(7.0, 0.0, -11.0)
const HATCH_LOCAL: Vector3 = Vector3(-7.0, 0.0, -11.0)

@export var side_door_resonance: float = 30.0
@export var vault_resonance: float = 25.0

var gate: AutoGate
var side_door: SlidingDoor
var vault_door: SlidingDoor
var device_interactable: Interactable

var _device_visual: Node3D
var _device_spin: Node3D
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 4242
	_build_ground()
	_build_perimeter()
	_build_building()
	_build_vault()
	_build_yard()
	_build_security()
	_build_signage()


func _process(delta: float) -> void:
	_time += delta
	if _device_spin != null and _device_visual.visible:
		_device_spin.rotation.y = _time * 0.8
		_device_spin.position.y = 1.45 + sin(_time * 2.0) * 0.04


## World-space waypoints for hunter patrols inside the compound.
func get_patrol_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for local: Vector3 in [Vector3(0.0, 0.0, 12.0), Vector3(2.0, 0.0, -2.0), Vector3(-16.0, 0.0, -18.0), Vector3(17.0, 0.0, -18.0), Vector3(-15.0, 0.0, 2.0)]:
		points.append(to_global(local))
	return points


func get_device_position() -> Vector3:
	return to_global(DEVICE_LOCAL + Vector3(0.0, 1.4, 0.0))


func get_entrance_position() -> Vector3:
	return to_global(Vector3(0.0, 0.0, HALF + 2.0))


## Returns the Device to its pedestal (after the Runner is captured while carrying it).
func reset_device() -> void:
	_device_visual.visible = true
	device_interactable.enabled = true


# --- Ground & perimeter --------------------------------------------------------------

func _build_ground() -> void:
	var slab := GeometryKit.solid_box(self, Vector3(0.0, 0.05, 0.0), Vector3(44.0, 0.1, 44.0), MaterialLibrary.concrete())
	slab.set_instance_shader_parameter(&"tint", Color(0.36, 0.36, 0.35))
	var paint := MaterialLibrary.road_paint()
	for x: float in [-6.0, -2.0, 2.0, 6.0]:
		var line := GeometryKit.mesh_box(self, Vector3(x, 0.105, 12.0), Vector3(0.15, 0.01, 6.0), paint)
		line.set_instance_shader_parameter(&"paint", Color(0.85, 0.7, 0.15))


func _build_perimeter() -> void:
	var wall := MaterialLibrary.concrete()
	var tint := Color(0.47, 0.46, 0.44)
	var gate_half: float = 3.6
	var door_min: float = -10.0
	var door_max: float = -8.0
	var y: float = WALL_HEIGHT * 0.5
	# North + east: full walls.
	_wall_segment(Vector3(0.0, y, -HALF), Vector3(HALF * 2.0 + WALL_THICK, WALL_HEIGHT, WALL_THICK), wall, tint)
	_wall_segment(Vector3(HALF, y, 0.0), Vector3(WALL_THICK, WALL_HEIGHT, HALF * 2.0), wall, tint)
	# South: gate opening.
	var south_len: float = HALF - gate_half
	for side: float in [-1.0, 1.0]:
		_wall_segment(Vector3(side * (gate_half + south_len * 0.5), y, HALF), Vector3(south_len + WALL_THICK * 0.5, WALL_HEIGHT, WALL_THICK), wall, tint)
	# West: side-door opening.
	var north_len: float = door_min + HALF
	var south_len_w: float = HALF - door_max
	_wall_segment(Vector3(-HALF, y, -HALF + north_len * 0.5), Vector3(WALL_THICK, WALL_HEIGHT, north_len), wall, tint)
	_wall_segment(Vector3(-HALF, y, door_max + south_len_w * 0.5), Vector3(WALL_THICK, WALL_HEIGHT, south_len_w), wall, tint)
	_wall_segment(Vector3(-HALF, 3.0 + (WALL_HEIGHT - 3.0) * 0.5, (door_min + door_max) * 0.5), Vector3(WALL_THICK, WALL_HEIGHT - 3.0, door_max - door_min), wall, tint)

	# Razor wire + wall lights along the top.
	var wire := MaterialLibrary.coated(Color(0.55, 0.56, 0.58), 1.0, 0.3)
	var corners: Array[Vector3] = [Vector3(-HALF, 0.0, -HALF), Vector3(HALF, 0.0, -HALF), Vector3(HALF, 0.0, HALF), Vector3(-HALF, 0.0, HALF)]
	for i: int in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var length: float = a.distance_to(b)
		var coils: int = int(length / 0.9)
		for c: int in coils:
			var p: Vector3 = a.lerp(b, (float(c) + 0.5) / float(coils))
			if i == 2 and absf(p.x) < gate_half:
				continue
			var coil := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.24
			torus.outer_radius = 0.28
			torus.rings = 12
			torus.ring_segments = 4
			coil.mesh = torus
			coil.material_override = wire
			coil.position = p + Vector3(0.0, WALL_HEIGHT + 0.3, 0.0)
			coil.rotation_degrees = Vector3(90.0, 0.0, 0.0) if i % 2 == 0 else Vector3(0.0, 0.0, 90.0)
			coil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(coil)

	gate = AutoGate.new()
	gate.name = "VehicleGate"
	gate.size = Vector3(gate_half * 2.0, 4.6, 0.3)
	gate.slide = Vector3(gate_half * 2.0 + 0.2, 0.0, 0.0)
	gate.collision_layer = GeometryKit.DOOR_LAYER
	gate.hazard_stripes = true
	gate.position = Vector3(0.0, 2.3, HALF + WALL_THICK * 0.5 + 0.25)
	add_child(gate)

	side_door = SlidingDoor.new()
	side_door.name = "SideDoor"
	side_door.size = Vector3(0.25, 3.0, door_max - door_min)
	side_door.slide = Vector3(0.0, 3.1, 0.0)
	side_door.paint = Color(0.2, 0.24, 0.3)
	side_door.position = Vector3(-HALF, 1.5, (door_min + door_max) * 0.5)
	add_child(side_door)

	var panel := Interactable.new()
	panel.name = "SideDoorPanel"
	panel.prompt = "Hack the side door (+%d Resonance)" % int(side_door_resonance)
	panel.hold_time = 3.0
	panel.radius = 2.0
	panel.one_shot = true
	panel.position = Vector3(-HALF - WALL_THICK * 0.5 - 0.1, 1.3, door_max + 1.0)
	add_child(panel)
	_build_keypad(panel)
	panel.completed.connect(func(_i: Interactable, _actor: Node3D) -> void:
		side_door.open()
		hack_completed.emit("Side door hacked", side_door_resonance))


func _wall_segment(center: Vector3, size: Vector3, material: Material, tint: Color) -> void:
	var mesh := GeometryKit.solid_box(self, center, size, material)
	mesh.set_instance_shader_parameter(&"tint", tint)
	var cap := GeometryKit.mesh_box(self, center + Vector3(0.0, size.y * 0.5 + 0.08, 0.0), Vector3(size.x + 0.1, 0.16, size.z + 0.1), material)
	cap.set_instance_shader_parameter(&"tint", tint.darkened(0.2))


func _build_keypad(parent: Node3D) -> void:
	var housing := MaterialLibrary.coated(Color(0.1, 0.1, 0.11), 0.6, 0.4)
	GeometryKit.mesh_box(parent, Vector3.ZERO, Vector3(0.08, 0.4, 0.28), housing)
	GeometryKit.mesh_box(parent, Vector3(-0.045, 0.08, 0.0), Vector3(0.01, 0.12, 0.2), MaterialLibrary.emissive(Color(0.2, 0.8, 1.0), 2.5))
	GeometryKit.mesh_box(parent, Vector3(-0.045, -0.08, 0.0), Vector3(0.01, 0.14, 0.2), MaterialLibrary.emissive(Color(1.0, 0.25, 0.15), 1.5))


# --- Main building + vault -------------------------------------------------------------

func _build_building() -> void:
	var clad := MaterialLibrary.metal_panel()
	var cladding := Color(0.3, 0.33, 0.35)
	var min_x: float = BUILDING_MIN.x
	var max_x: float = BUILDING_MAX.x
	var min_z: float = BUILDING_MIN.y
	var max_z: float = BUILDING_MAX.y
	var h: float = BUILDING_HEIGHT
	var width: float = max_x - min_x
	var depth: float = max_z - min_z
	var cx: float = (min_x + max_x) * 0.5
	var cz: float = (min_z + max_z) * 0.5

	var walls: Array[MeshInstance3D] = []
	walls.append(GeometryKit.solid_box(self, Vector3(cx, h * 0.5, min_z), Vector3(width, h, SKIN), clad))
	walls.append(GeometryKit.solid_box(self, Vector3(min_x, h * 0.5, cz), Vector3(SKIN, h, depth), clad))
	walls.append(GeometryKit.solid_box(self, Vector3(max_x, h * 0.5, cz), Vector3(SKIN, h, depth), clad))
	# South facade with loading bay opening (x -5..0, 4.5 m tall).
	var bay_min: float = -5.0
	var bay_max: float = 0.0
	walls.append(GeometryKit.solid_box(self, Vector3((min_x + bay_min) * 0.5, h * 0.5, max_z), Vector3(bay_min - min_x, h, SKIN), clad))
	walls.append(GeometryKit.solid_box(self, Vector3((bay_max + max_x) * 0.5, h * 0.5, max_z), Vector3(max_x - bay_max, h, SKIN), clad))
	walls.append(GeometryKit.solid_box(self, Vector3((bay_min + bay_max) * 0.5, (4.5 + h) * 0.5, max_z), Vector3(bay_max - bay_min, h - 4.5, SKIN), clad))
	for wall: MeshInstance3D in walls:
		wall.set_instance_shader_parameter(&"paint_color", cladding)

	var roof := GeometryKit.solid_box(self, Vector3(cx, h + 0.2, cz), Vector3(width + 0.4, 0.4, depth + 0.4), MaterialLibrary.concrete())
	roof.set_instance_shader_parameter(&"tint", Color(0.3, 0.3, 0.3))
	var floor_mat := MaterialLibrary.surface(Color(0.33, 0.34, 0.34), 0.35, 0.0, 0.4, 0.6)
	GeometryKit.mesh_box(self, Vector3(cx, 0.11, cz), Vector3(width - 0.4, 0.02, depth - 0.4), floor_mat)

	# Rolling shutter (half open) + bay lights + hazard frame.
	var shutter := GeometryKit.mesh_box(self, Vector3((bay_min + bay_max) * 0.5, 3.9, max_z + 0.05), Vector3(bay_max - bay_min, 1.2, 0.1), MaterialLibrary.metal_panel())
	shutter.set_instance_shader_parameter(&"paint_color", Color(0.45, 0.46, 0.44))
	for x: float in [bay_min - 0.15, bay_max + 0.15]:
		var post := GeometryKit.mesh_box(self, Vector3(x, 2.25, max_z + 0.3), Vector3(0.3, 4.5, 0.3), MaterialLibrary.metal_panel())
		post.set_instance_shader_parameter(&"hazard", 1.0)
	GeometryKit.mesh_box(self, Vector3((bay_min + bay_max) * 0.5, 4.75, max_z + 0.4), Vector3(1.2, 0.15, 0.3), MaterialLibrary.emissive(Color(1.0, 0.8, 0.5), 4.0))

	# Facade windows (high strip) and roof details.
	for i: int in 6:
		var x: float = min_x + 2.0 + i * 3.8
		if x > bay_min - 1.0 and x < bay_max + 1.0:
			continue
		GeometryKit.mesh_box(self, Vector3(x, 7.6, max_z + SKIN * 0.5 + 0.01), Vector3(2.6, 0.9, 0.02), MaterialLibrary.emissive(Color(0.75, 0.85, 1.0), 1.2))
	PropFactory.ac_unit(self, Vector3(8.0, h + 0.4, -2.0), 0.0)
	PropFactory.ac_unit(self, Vector3(4.0, h + 0.4, -1.0), 90.0)
	PropFactory.antenna(self, Vector3(10.0, h + 0.4, -12.0), 7.0)

	# Interior: hall lighting, racking, crates.
	for x: float in [-6.0, 1.0, 8.0]:
		GeometryKit.mesh_box(self, Vector3(x, h - 0.3, -1.5), Vector3(4.0, 0.1, 0.4), MaterialLibrary.emissive(Color(0.9, 0.95, 1.0), 3.0))
		var hall_light := OmniLight3D.new()
		hall_light.light_color = Color(0.85, 0.92, 1.0)
		hall_light.light_energy = 1.6
		hall_light.omni_range = 11.0
		hall_light.position = Vector3(x, h - 1.0, -1.5)
		add_child(hall_light)
	for x: float in [-9.0, 10.5]:
		_build_rack(Vector3(x, 0.1, -1.5))
	for local: Vector3 in [Vector3(-3.0, 0.1, -3.5), Vector3(-1.6, 0.1, -3.8), Vector3(5.0, 0.1, 0.5)]:
		PropFactory.crate(self, local, 1.3, _rng)


func _build_rack(base: Vector3) -> void:
	var steel := MaterialLibrary.coated(Color(0.15, 0.25, 0.45), 0.7, 0.4)
	var shelf := MaterialLibrary.coated(Color(0.5, 0.36, 0.15), 0.4, 0.6)
	GeometryKit.collider_box(self, base + Vector3(0.0, 2.0, 0.0), Vector3(1.2, 4.0, 5.0))
	for z: float in [-2.4, 2.4]:
		for x: float in [-0.55, 0.55]:
			GeometryKit.mesh_box(self, base + Vector3(x, 2.0, z), Vector3(0.1, 4.0, 0.1), steel)
	for y: float in [0.3, 1.6, 2.9]:
		GeometryKit.mesh_box(self, base + Vector3(0.0, y, 0.0), Vector3(1.2, 0.06, 5.0), shelf)
		for z: float in [-1.6, 0.0, 1.6]:
			if _rng.randf() < 0.7:
				PropFactory.crate(self, base + Vector3(0.0, y + 0.03, z), 0.9, _rng)


func _build_vault() -> void:
	var clad := MaterialLibrary.metal_panel()
	var tint := Color(0.22, 0.24, 0.26)
	var h: float = BUILDING_HEIGHT
	var door_min: float = 5.0
	var door_max: float = 8.0
	var z: float = VAULT_WALL_Z
	var parts: Array[MeshInstance3D] = []
	parts.append(GeometryKit.solid_box(self, Vector3((BUILDING_MIN.x + door_min) * 0.5, h * 0.5, z), Vector3(door_min - BUILDING_MIN.x, h, 0.6), clad))
	parts.append(GeometryKit.solid_box(self, Vector3((door_max + BUILDING_MAX.x) * 0.5, h * 0.5, z), Vector3(BUILDING_MAX.x - door_max, h, 0.6), clad))
	parts.append(GeometryKit.solid_box(self, Vector3((door_min + door_max) * 0.5, (3.5 + h) * 0.5, z), Vector3(door_max - door_min, h - 3.5, 0.6), clad))
	for part: MeshInstance3D in parts:
		part.set_instance_shader_parameter(&"paint_color", tint)

	vault_door = SlidingDoor.new()
	vault_door.name = "VaultDoor"
	vault_door.size = Vector3(door_max - door_min, 3.5, 0.5)
	vault_door.slide = Vector3(door_max - door_min + 0.1, 0.0, 0.0)
	vault_door.hazard_stripes = true
	vault_door.open_time = 2.5
	vault_door.position = Vector3((door_min + door_max) * 0.5, 1.75, z + 0.6)
	add_child(vault_door)

	var console := Interactable.new()
	console.name = "VaultConsole"
	console.prompt = "Override the vault lock (+%d Resonance)" % int(vault_resonance)
	console.hold_time = 4.0
	console.radius = 2.0
	console.one_shot = true
	console.position = Vector3(3.6, 0.0, z + 0.9)
	add_child(console)
	var desk := MaterialLibrary.coated(Color(0.12, 0.12, 0.13), 0.5, 0.4)
	GeometryKit.solid_box(console, Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 0.6), desk)
	GeometryKit.tilted_box(console, Vector3(0.0, 1.25, -0.05), Vector3(0.8, 0.5, 0.04), Vector3(-20.0, 0.0, 0.0), MaterialLibrary.emissive(Color(0.25, 0.75, 1.0), 2.0))
	console.completed.connect(func(_i: Interactable, _actor: Node3D) -> void:
		vault_door.open()
		hack_completed.emit("Vault override", vault_resonance))

	# Vault interior: red security lighting + pedestal with the Device.
	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.25, 0.2)
	red.light_energy = 1.4
	red.omni_range = 12.0
	red.position = Vector3(1.0, h - 2.0, -11.0)
	add_child(red)
	GeometryKit.mesh_box(self, Vector3(1.0, h - 0.3, -11.0), Vector3(10.0, 0.08, 0.3), MaterialLibrary.emissive(Color(1.0, 0.2, 0.15), 2.0))

	var pedestal_mat := MaterialLibrary.coated(Color(0.15, 0.15, 0.17), 0.8, 0.3)
	GeometryKit.cylinder(self, DEVICE_LOCAL + Vector3(0.0, 0.5, 0.0), 0.45, 0.6, 1.0, pedestal_mat, 24)
	GeometryKit.collider_box(self, DEVICE_LOCAL + Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 1.0))
	GeometryKit.cylinder(self, DEVICE_LOCAL + Vector3(0.0, 1.01, 0.0), 0.42, 0.42, 0.02, MaterialLibrary.emissive(Color(1.0, 0.75, 0.25), 2.0), 24)
	var beam := GeometryKit.cylinder(self, DEVICE_LOCAL + Vector3(0.0, 3.0, 0.0), 0.35, 0.35, 4.0, MaterialLibrary.hologram(Color(1.0, 0.75, 0.3), 0.08), 20)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_device_visual = Node3D.new()
	_device_visual.position = DEVICE_LOCAL
	add_child(_device_visual)
	_device_spin = Node3D.new()
	_device_spin.position = Vector3(0.0, 1.45, 0.0)
	_device_visual.add_child(_device_spin)
	GeometryKit.mesh_box(_device_spin, Vector3.ZERO, Vector3(0.32, 0.32, 0.32), MaterialLibrary.coated(Color(0.75, 0.6, 0.22), 0.95, 0.2))
	GeometryKit.mesh_box(_device_spin, Vector3.ZERO, Vector3(0.34, 0.08, 0.34), MaterialLibrary.emissive(Color(1.0, 0.75, 0.25), 5.0))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.32
	torus.outer_radius = 0.36
	ring.mesh = torus
	ring.material_override = MaterialLibrary.emissive(Color(1.0, 0.8, 0.35), 4.0)
	ring.rotation_degrees = Vector3(70.0, 0.0, 0.0)
	_device_spin.add_child(ring)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.75, 0.3)
	glow.light_energy = 2.0
	glow.omni_range = 5.0
	_device_spin.add_child(glow)

	device_interactable = Interactable.new()
	device_interactable.name = "DeviceInteractable"
	device_interactable.prompt = "Take the Codex Uplink Key"
	device_interactable.hold_time = 1.5
	device_interactable.radius = 2.2
	device_interactable.position = DEVICE_LOCAL + Vector3(0.0, 0.2, 0.0)
	add_child(device_interactable)
	device_interactable.completed.connect(func(_i: Interactable, _actor: Node3D) -> void:
		_device_visual.visible = false
		device_interactable.enabled = false
		device_collected.emit())

	# Roof hatch: from the roof, drop straight into the vault room.
	var hatch_top: Vector3 = HATCH_LOCAL + Vector3(0.0, BUILDING_HEIGHT + 0.4, 0.0)
	var hatch_mat := MaterialLibrary.metal_panel()
	var hatch := GeometryKit.mesh_box(self, hatch_top + Vector3(0.0, 0.15, 0.0), Vector3(1.6, 0.3, 1.6), hatch_mat)
	hatch.set_instance_shader_parameter(&"hazard", 1.0)
	GeometryKit.mesh_box(self, hatch_top + Vector3(0.0, 0.31, 0.0), Vector3(1.2, 0.04, 1.2), MaterialLibrary.coated(Color(0.2, 0.22, 0.24), 0.8, 0.4))
	var hatch_use := Interactable.new()
	hatch_use.name = "RoofHatch"
	hatch_use.prompt = "Pry open the roof hatch and drop in"
	hatch_use.hold_time = 2.0
	hatch_use.radius = 2.2
	hatch_use.position = hatch_top + Vector3(0.0, 0.4, 0.0)
	add_child(hatch_use)
	hatch_use.completed.connect(func(_i: Interactable, actor: Node3D) -> void:
		var runner := actor as PlayerController
		if runner != null:
			runner.teleport(to_global(HATCH_LOCAL + Vector3(0.0, 0.3, 0.0)))
		entered_via_hatch.emit())


# --- Yard, security, signage -----------------------------------------------------------

func _build_yard() -> void:
	PropFactory.shipping_container(self, Vector3(-15.0, 0.1, 10.0), 0.0, Color(0.55, 0.2, 0.08))
	PropFactory.shipping_container(self, Vector3(-15.0, 2.7, 10.0), 0.0, Color(0.1, 0.3, 0.45))
	PropFactory.shipping_container(self, Vector3(-9.0, 0.1, 15.5), 90.0, Color(0.15, 0.35, 0.2))
	PropFactory.shipping_container(self, Vector3(13.0, 0.1, 10.5), 0.0, Color(0.6, 0.55, 0.5))
	PropFactory.jersey_barrier(self, Vector3(-5.5, 0.1, 17.0), 90.0)
	PropFactory.jersey_barrier(self, Vector3(5.5, 0.1, 17.0), 90.0)
	for local: Vector3 in [Vector3(6.0, 0.1, 6.0), Vector3(7.4, 0.1, 6.3), Vector3(-6.0, 0.1, 6.5)]:
		PropFactory.crate(self, local, 1.2, _rng)

	# Guard booth next to the gate.
	var booth := Vector3(8.0, 0.1, 17.5)
	var booth_walls := GeometryKit.solid_box(self, booth + Vector3(0.0, 1.3, 0.0), Vector3(3.0, 2.6, 2.6), MaterialLibrary.concrete())
	booth_walls.set_instance_shader_parameter(&"tint", Color(0.6, 0.6, 0.58))
	GeometryKit.mesh_box(self, booth + Vector3(0.0, 1.7, 1.31), Vector3(2.4, 0.9, 0.04), MaterialLibrary.emissive(Color(0.9, 0.95, 0.8), 1.4))
	GeometryKit.mesh_box(self, booth + Vector3(0.0, 2.68, 0.0), Vector3(3.4, 0.15, 3.0), MaterialLibrary.coated(Color(0.15, 0.15, 0.16), 0.6, 0.5))

	# Floodlights on the building corners.
	for x: float in [BUILDING_MIN.x - 0.3, BUILDING_MAX.x + 0.3]:
		var flood := SpotLight3D.new()
		flood.light_color = Color(0.95, 0.97, 1.0)
		flood.light_energy = 5.0
		flood.spot_range = 24.0
		flood.spot_angle = 45.0
		flood.position = Vector3(x, 8.5, BUILDING_MAX.y + 0.5)
		flood.rotation_degrees = Vector3(-55.0, 180.0, 0.0)
		add_child(flood)
		GeometryKit.mesh_box(self, Vector3(x, 8.6, BUILDING_MAX.y + 0.4), Vector3(0.6, 0.3, 0.3), MaterialLibrary.emissive(Color(0.95, 0.97, 1.0), 5.0))


func _build_security() -> void:
	# Yaw: camera looks along -Z rotated by yaw (135 = towards +Z/-X, 225 = towards +Z/+X).
	_add_camera(Vector3(BUILDING_MAX.x + 0.4, 6.5, BUILDING_MAX.y + 0.4), 135.0)
	_add_camera(Vector3(BUILDING_MIN.x - 0.4, 6.5, BUILDING_MAX.y + 0.4), 225.0)
	_add_camera(Vector3(-HALF + 0.6, 5.0, HALF - 0.6), -45.0)
	_add_camera(Vector3(BUILDING_MAX.x - 0.6, 4.5, -0.4), 90.0)
	_add_camera(Vector3(BUILDING_MIN.x + 0.6, 4.2, BUILDING_MIN.y + 0.6), 225.0)

	var tower := SearchlightTower.new()
	tower.name = "SearchlightTower"
	tower.position = Vector3(16.5, 0.1, 16.5)
	tower.sweep_center = Vector3(-16.0, 0.0, -6.0)
	tower.sweep_extent = Vector2(13.0, 6.0)
	add_child(tower)
	tower.intruder_spotted.connect(_relay_spotted)


func _add_camera(local: Vector3, yaw_degrees: float) -> void:
	var cam := SecurityCamera.new()
	cam.position = local
	cam.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	add_child(cam)
	cam.intruder_spotted.connect(_relay_spotted)


func _relay_spotted(world_position: Vector3) -> void:
	intruder_spotted.emit(world_position)


func _build_signage() -> void:
	var company_sign := Label3D.new()
	company_sign.double_sided = false
	company_sign.text = "MERIDIAN SIGNAL LABS"
	company_sign.font_size = 160
	company_sign.pixel_size = 0.01
	company_sign.outline_size = 0
	company_sign.modulate = Color(0.75, 0.88, 1.0)
	company_sign.position = Vector3(1.0, 8.8, BUILDING_MAX.y + 0.3)
	add_child(company_sign)
	var warning := Label3D.new()
	warning.double_sided = false
	warning.text = "RESTRICTED AREA\nAUTHORISED PERSONNEL ONLY"
	warning.font_size = 48
	warning.pixel_size = 0.01
	warning.modulate = Color(1.0, 0.85, 0.3)
	warning.position = Vector3(-6.5, 3.2, HALF + WALL_THICK * 0.5 + 0.02)
	add_child(warning)
	var door_sign := Label3D.new()
	door_sign.double_sided = false
	door_sign.text = "SERVICE"
	door_sign.font_size = 40
	door_sign.pixel_size = 0.01
	door_sign.modulate = Color(0.85, 0.9, 1.0)
	door_sign.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	door_sign.position = Vector3(-HALF - WALL_THICK * 0.5 - 0.02, 3.4, -9.0)
	add_child(door_sign)
