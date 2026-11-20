class_name HumanoidRig
extends Node3D
## Procedurally generated, skinned and procedurally animated humanoid.
##
## The body is ONE continuous mesh lofted from elliptical cross-sections (torso, neck, head,
## arms, hands, legs, feet) and skinned to a Skeleton3D with blended weights at every joint,
## so elbows, knees, hips and shoulders bend smoothly instead of looking like stacked parts.
## Clothing surfaces use the `suit` shader (seams, zipper, glowing Codex veins); armour,
## hoods, hair, gear and props are rigid pieces on BoneAttachment3D sockets.
## `animate()` is called every physics frame by the owner and drives idle / walk / run, jump,
## fall, landing squash, dash lean, crouch and a "scan" pose through bone pose rotations.
## The rig faces -Z; the owner rotates it to face the travel direction.

enum Style { RUNNER, HUNTER, CIVILIAN, TECHNICIAN }

const SUIT_SHADER: String = "res://shaders/suit.gdshader"
const SEGMENTS: int = 18

enum { B_HIPS, B_SPINE, B_CHEST, B_NECK, B_HEAD, B_SHOULDER_L, B_ELBOW_L, B_WRIST_L, B_SHOULDER_R, B_ELBOW_R, B_WRIST_R, B_HIP_L, B_KNEE_L, B_ANKLE_L, B_HIP_R, B_KNEE_R, B_ANKLE_R, BONE_COUNT }

const BONE_NAMES: PackedStringArray = ["hips", "spine", "chest", "neck", "head", "shoulder_l", "elbow_l", "wrist_l", "shoulder_r", "elbow_r", "wrist_r", "hip_l", "knee_l", "ankle_l", "hip_r", "knee_r", "ankle_r"]
const BONE_PARENTS: PackedInt32Array = [-1, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9, 0, 11, 12, 0, 14, 15]
const BONE_OFFSETS: PackedVector3Array = [
	Vector3(0.0, 0.96, 0.0), Vector3(0.0, 0.08, 0.0), Vector3(0.0, 0.24, 0.0), Vector3(0.0, 0.28, 0.0), Vector3(0.0, 0.09, 0.0),
	Vector3(-0.19, 0.2, 0.0), Vector3(0.0, -0.28, 0.0), Vector3(0.0, -0.25, 0.0),
	Vector3(0.19, 0.2, 0.0), Vector3(0.0, -0.28, 0.0), Vector3(0.0, -0.25, 0.0),
	Vector3(-0.095, -0.04, 0.0), Vector3(0.0, -0.43, 0.0), Vector3(0.0, -0.42, 0.0),
	Vector3(0.095, -0.04, 0.0), Vector3(0.0, -0.43, 0.0), Vector3(0.0, -0.42, 0.0),
]

@export var style: Style = Style.RUNNER
@export var run_speed: float = 8.0
@export var joint_smoothing: float = 16.0
@export var outfit_seed: int = 0

## Extra pose inputs set by the owner before calling animate().
var dashing: bool = false
var scanning: bool = false
var crouch_amount: float = 0.0
## 0 = upright, 1 = lying face-down (crawl cycle).
var prone_amount: float = 0.0

var _skeleton: Skeleton3D
var _rest: PackedVector3Array = PackedVector3Array()
var _euler: Array[Vector3] = []
var _hips_y: float = 0.96
var _sockets: Dictionary = {}
var _accent_materials: Array[StandardMaterial3D] = []
var _accent_meshes: Array[MeshInstance3D] = []
var _carry_item: Node3D
var _accent_color: Color = Color(0.2, 0.9, 1.0)
var _accent_energy: float = 1.0
var _bulk: float = 1.0

var _phase: float = 0.0
var _time: float = 0.0
var _air_blend: float = 0.0
var _land_squash: float = 0.0
var _was_on_floor: bool = true


func _ready() -> void:
	_build()


## Rebuilds the whole character in another outfit (used by the disguise system).
func apply_style(new_style: Style, new_seed: int) -> void:
	style = new_style
	outfit_seed = new_seed
	for child: Node in get_children():
		child.queue_free()
	_sockets.clear()
	_accent_materials.clear()
	_accent_meshes.clear()
	_carry_item = null
	_build()
	set_accent(_accent_color, _accent_energy)


func _build() -> void:
	_euler.clear()
	for i: int in BONE_COUNT:
		_euler.append(Vector3.ZERO)
	_bulk = 1.12 if style == Style.HUNTER else 1.0
	_build_skeleton()
	var rng := RandomNumberGenerator.new()
	rng.seed = outfit_seed * 7919 + int(style) * 131 + 17
	match style:
		Style.RUNNER:
			_dress_runner()
		Style.HUNTER:
			_dress_hunter()
		Style.CIVILIAN:
			_dress_civilian(rng)
		Style.TECHNICIAN:
			_dress_technician(rng)


# --- Animation -------------------------------------------------------------------------

## Updates the pose. `local_velocity` is the velocity in the rig's facing frame (forward = -Z).
func animate(local_velocity: Vector3, on_floor: bool, delta: float) -> void:
	if _skeleton == null:
		return
	_time += delta
	var speed: float = Vector2(local_velocity.x, local_velocity.z).length()
	var move: float = clampf(speed / 1.6, 0.0, 1.0)
	var run: float = clampf((speed - 2.5) / maxf(run_speed - 2.5, 0.1), 0.0, 1.0)
	var stride: float = lerpf(1.3, 2.7, run)
	_phase = fmod(_phase + speed / stride * TAU * delta, TAU)

	_air_blend = move_toward(_air_blend, 0.0 if on_floor else 1.0, delta * 7.0)
	if on_floor and not _was_on_floor:
		_land_squash = clampf(-local_velocity.y * 0.03, 0.08, 0.3)
	_was_on_floor = on_floor
	_land_squash = move_toward(_land_squash, 0.0, delta * 1.2)

	var s: float = sin(_phase)
	var c: float = cos(_phase)
	var thigh_amp: float = lerpf(0.4, 0.85, run) * move
	var knee_amp: float = lerpf(0.55, 1.45, run) * move
	var arm_amp: float = lerpf(0.3, 0.9, run) * move
	var breathe: float = sin(_time * 1.9) * 0.025 * (1.0 - move)

	var hip_l: float = s * thigh_amp + run * 0.12
	var hip_r: float = -s * thigh_amp + run * 0.12
	var knee_l: float = -(0.06 + maxf(0.0, c) * knee_amp)
	var knee_r: float = -(0.06 + maxf(0.0, -c) * knee_amp)
	var shoulder_l: float = -s * arm_amp
	var shoulder_r: float = s * arm_amp
	var elbow: float = lerpf(0.2, 1.3, run) * move + 0.15
	var spine: float = -lerpf(0.04, 0.22, run) * move + breathe
	var chest_twist: float = s * 0.18 * move
	var hips_twist: float = -s * 0.1 * move
	var bob: float = absf(s) * lerpf(0.02, 0.065, run) * move
	var hips_y: float = 0.96 - lerpf(0.0, 0.05, run) * move + bob
	var arm_out: float = 0.07 + 0.04 * (1.0 - move)
	var head_y: float = sin(_time * 0.7) * 0.12 * (1.0 - move)

	var rising: float = clampf(local_velocity.y / 6.0, 0.0, 1.0)
	hip_l = lerpf(hip_l, lerpf(0.25, 0.9, rising), _air_blend)
	hip_r = lerpf(hip_r, lerpf(-0.1, 0.2, rising), _air_blend)
	knee_l = lerpf(knee_l, -lerpf(0.5, 1.5, rising), _air_blend)
	knee_r = lerpf(knee_r, -lerpf(0.3, 0.9, rising), _air_blend)
	var air_shoulder: float = lerpf(0.35, -0.55, rising)
	shoulder_l = lerpf(shoulder_l, air_shoulder, _air_blend)
	shoulder_r = lerpf(shoulder_r, air_shoulder * 0.8, _air_blend)
	elbow = lerpf(elbow, lerpf(0.5, 1.1, rising), _air_blend)
	arm_out = lerpf(arm_out, lerpf(0.85, 0.3, rising), _air_blend)
	spine = lerpf(spine, lerpf(0.05, -0.15, rising), _air_blend)
	hips_y = lerpf(hips_y, 0.96, _air_blend)

	if dashing:
		spine = -0.75
		shoulder_l = -1.1
		shoulder_r = -1.1
		elbow = 0.2
		arm_out = 0.35
		hip_l = 0.9
		hip_r = -0.6
		knee_l = -0.6
		knee_r = -0.3

	var elbow_r: float = elbow
	if scanning:
		shoulder_r = 1.45
		elbow_r = 0.15
		head_y = sin(_time * 1.6) * 0.9

	# Prone crawl: arms reach overhead alternately, legs push, head tilts up to look ahead.
	if prone_amount > 0.01:
		var p: float = prone_amount
		var crawl: float = sin(_phase * 0.8)
		var reach: float = 0.45 * move
		shoulder_l = lerpf(shoulder_l, 2.75 + crawl * reach, p)
		shoulder_r = lerpf(shoulder_r, 2.75 - crawl * reach, p)
		elbow = lerpf(elbow, 0.55 + maxf(0.0, crawl) * 0.5 * move, p)
		elbow_r = lerpf(elbow_r, 0.55 + maxf(0.0, -crawl) * 0.5 * move, p)
		arm_out = lerpf(arm_out, 0.35, p)
		hip_l = lerpf(hip_l, 0.12 + maxf(0.0, crawl) * 0.35 * move, p)
		hip_r = lerpf(hip_r, 0.12 + maxf(0.0, -crawl) * 0.35 * move, p)
		knee_l = lerpf(knee_l, -0.15 - maxf(0.0, crawl) * 0.7 * move, p)
		knee_r = lerpf(knee_r, -0.15 - maxf(0.0, -crawl) * 0.7 * move, p)
		spine = lerpf(spine, 0.05, p)
		head_y = lerpf(head_y, 0.0, p)
		hips_y = lerpf(hips_y, 0.96, p)
	rotation.x = lerp_angle(rotation.x, -PI * 0.5 * prone_amount, 1.0)
	position = Vector3(0.0, 0.14 * prone_amount, 0.85 * prone_amount)

	var squash: float = _land_squash + crouch_amount * 0.35 * (1.0 - prone_amount)
	hips_y -= squash * 0.5
	knee_l -= squash * 1.6
	knee_r -= squash * 1.6
	hip_l += squash * 0.8
	hip_r += squash * 0.8
	spine -= squash * 0.5
	var lean_z: float = clampf(-local_velocity.x * 0.02, -0.2, 0.2)

	var k: float = clampf(joint_smoothing * delta, 0.0, 1.0)
	_hips_y = lerpf(_hips_y, hips_y, k)
	_blend(B_HIPS, Vector3(0.0, hips_twist, lean_z), k)
	_blend(B_SPINE, Vector3(spine, 0.0, 0.0), k)
	_blend(B_CHEST, Vector3(breathe * 0.5, chest_twist, 0.0), k)
	_blend(B_NECK, Vector3(-spine * 0.3 + prone_amount * 0.6, head_y * 0.4, 0.0), k)
	_blend(B_HEAD, Vector3(-spine * 0.35 + prone_amount * 0.5, head_y * 0.6, 0.0), k)
	_blend(B_HIP_L, Vector3(hip_l, 0.0, 0.0), k)
	_blend(B_HIP_R, Vector3(hip_r, 0.0, 0.0), k)
	_blend(B_KNEE_L, Vector3(knee_l, 0.0, 0.0), k)
	_blend(B_KNEE_R, Vector3(knee_r, 0.0, 0.0), k)
	_blend(B_ANKLE_L, Vector3(-(hip_l + knee_l) * 0.5, 0.0, 0.0), k)
	_blend(B_ANKLE_R, Vector3(-(hip_r + knee_r) * 0.5, 0.0, 0.0), k)
	_blend(B_SHOULDER_L, Vector3(shoulder_l, 0.0, -arm_out), k)
	_blend(B_SHOULDER_R, Vector3(shoulder_r, 0.0, arm_out), k)
	_blend(B_ELBOW_L, Vector3(elbow, 0.0, 0.0), k)
	_blend(B_ELBOW_R, Vector3(elbow_r, 0.0, 0.0), k)

	_skeleton.set_bone_pose_position(B_HIPS, Vector3(0.0, _hips_y, 0.0))
	for i: int in BONE_COUNT:
		_skeleton.set_bone_pose_rotation(i, Quaternion.from_euler(_euler[i]))


func _blend(bone: int, target: Vector3, k: float) -> void:
	var current: Vector3 = _euler[bone]
	_euler[bone] = Vector3(lerp_angle(current.x, target.x, k), lerp_angle(current.y, target.y, k), lerp_angle(current.z, target.z, k))


## Colour/intensity of the emissive accents (Codex veins / hunter visor & traces / badge).
func set_accent(color: Color, energy: float) -> void:
	_accent_color = color
	_accent_energy = energy
	for material: StandardMaterial3D in _accent_materials:
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = energy
	for mesh: MeshInstance3D in _accent_meshes:
		mesh.set_instance_shader_parameter(&"accent_color", color)
		mesh.set_instance_shader_parameter(&"accent_energy", energy * 0.6)


func set_carry_visible(visible_state: bool) -> void:
	if _carry_item != null:
		_carry_item.visible = visible_state


func get_socket(bone: int) -> Node3D:
	return _sockets.get(bone)


# --- Skeleton ---------------------------------------------------------------------------

func _build_skeleton() -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton3D"
	add_child(_skeleton)
	_rest = PackedVector3Array()
	_rest.resize(BONE_COUNT)
	for i: int in BONE_COUNT:
		_skeleton.add_bone(BONE_NAMES[i])
		var offset: Vector3 = BONE_OFFSETS[i]
		if i == B_SHOULDER_L or i == B_SHOULDER_R:
			offset.x *= _bulk
		if BONE_PARENTS[i] >= 0:
			_skeleton.set_bone_parent(i, BONE_PARENTS[i])
		_skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, offset))
		_skeleton.set_bone_pose_position(i, offset)
		_rest[i] = offset + (_rest[BONE_PARENTS[i]] if BONE_PARENTS[i] >= 0 else Vector3.ZERO)
	for i: int in BONE_COUNT:
		var socket := BoneAttachment3D.new()
		socket.bone_name = BONE_NAMES[i]
		_skeleton.add_child(socket)
		_sockets[i] = socket


## Rigid gear piece on a bone socket, positioned in rest (model) space.
func _gear(bone: int, mesh_type: String, rest_position: Vector3, size: Vector3, material: Material, rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var socket: Node3D = _sockets[bone]
	var local: Vector3 = rest_position - _rest[bone]
	var instance: MeshInstance3D
	match mesh_type:
		"sphere":
			instance = GeometryKit.sphere(socket, local, 0.5, material, size)
		"capsule":
			instance = GeometryKit.capsule(socket, local, 0.5, 1.6, material, Vector3(size.x, size.y / 1.6, size.z))
		"cylinder":
			instance = GeometryKit.cylinder(socket, local, 0.5, 0.5, 1.0, material, 16)
			instance.scale = size
		_:
			instance = GeometryKit.mesh_box(socket, local, Vector3.ONE, material)
			instance.scale = size
	instance.rotation_degrees = rotation_deg
	return instance


# --- Skinned body generation ---------------------------------------------------------------

class Ring:
	var center: Vector3
	var rx: float
	var rz: float
	var bones: PackedInt32Array
	var weights: PackedFloat32Array
	var right: Vector3 = Vector3.RIGHT
	var depth: Vector3 = Vector3.BACK

	func _init(c: Vector3, radius_x: float, radius_z: float, b: PackedInt32Array, w: PackedFloat32Array) -> void:
		center = c
		rx = radius_x
		rz = radius_z
		bones = b
		weights = w


func _ring(c: Vector3, rx: float, rz: float, a: int, b: int, t: float) -> Ring:
	return Ring.new(c, rx, rz, PackedInt32Array([a, b, 0, 0]), PackedFloat32Array([1.0 - t, t, 0.0, 0.0]))


## Lofts a closed tube through `rings` into SurfaceTool `st` (clockwise front faces).
func _loft(st: SurfaceTool, rings: Array[Ring], cap_start: bool, cap_end: bool) -> void:
	var base: int = _vertex_count(st)
	var count: int = rings.size()
	for r: int in count:
		var ring: Ring = rings[r]
		for j: int in SEGMENTS + 1:
			var a: float = TAU * float(j) / float(SEGMENTS)
			var p: Vector3 = ring.center + ring.right * cos(a) * ring.rx + ring.depth * sin(a) * ring.rz
			st.set_uv(Vector2(float(j) / float(SEGMENTS), float(r) / float(maxi(count - 1, 1))))
			st.set_bones(ring.bones)
			st.set_weights(ring.weights)
			st.add_vertex(p)
	for r: int in count - 1:
		for j: int in SEGMENTS:
			var i0: int = base + r * (SEGMENTS + 1) + j
			var i1: int = i0 + 1
			var i2: int = i0 + SEGMENTS + 1
			var i3: int = i2 + 1
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)
	_vertex_counts[st] = base + count * (SEGMENTS + 1)
	if cap_start:
		_cap(st, rings[0], base, true)
	if cap_end:
		_cap(st, rings[count - 1], base + (count - 1) * (SEGMENTS + 1), false)


var _vertex_counts: Dictionary = {}


## Lofts an open sheet covering angles [a_start, a_end] of each ring (hoods, visors, collars).
func _loft_arc(st: SurfaceTool, rings: Array[Ring], a_start: float, a_end: float, steps: int) -> void:
	var base: int = _vertex_count(st)
	var count: int = rings.size()
	for r: int in count:
		var ring: Ring = rings[r]
		for j: int in steps + 1:
			var t: float = float(j) / float(steps)
			var a: float = lerpf(a_start, a_end, t)
			st.set_uv(Vector2(t, float(r) / float(maxi(count - 1, 1))))
			st.set_bones(ring.bones)
			st.set_weights(ring.weights)
			st.add_vertex(ring.center + ring.right * cos(a) * ring.rx + ring.depth * sin(a) * ring.rz)
	for r: int in count - 1:
		for j: int in steps:
			var i0: int = base + r * (steps + 1) + j
			var i1: int = i0 + 1
			var i2: int = i0 + steps + 1
			var i3: int = i2 + 1
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)
	_vertex_counts[st] = base + count * (steps + 1)


func _vertex_count(st: SurfaceTool) -> int:
	return int(_vertex_counts.get(st, 0))


func _cap(st: SurfaceTool, ring: Ring, ring_start: int, flip: bool) -> void:
	var center_index: int = _vertex_count(st)
	st.set_uv(Vector2(0.5, 0.0 if flip else 1.0))
	st.set_bones(ring.bones)
	st.set_weights(ring.weights)
	st.add_vertex(ring.center)
	_vertex_counts[st] = center_index + 1
	for j: int in SEGMENTS:
		if flip:
			st.add_index(center_index)
			st.add_index(ring_start + j + 1)
			st.add_index(ring_start + j)
		else:
			st.add_index(center_index)
			st.add_index(ring_start + j)
			st.add_index(ring_start + j + 1)


func _new_surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_vertex_counts[st] = 0
	return st


func _commit(st: SurfaceTool, mesh: ArrayMesh, material: Material) -> void:
	st.generate_normals()
	st.generate_tangents()
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


func _finish_body(mesh: ArrayMesh, accent_on_suit: bool) -> MeshInstance3D:
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh
	_skeleton.add_child(body)
	body.skeleton = NodePath("..")
	body.skin = _skeleton.create_skin_from_rest_transforms()
	if accent_on_suit:
		_accent_meshes.append(body)
	return body


# Body parts. `girth` scales limb/torso radii (clothing looseness / armour bulk).
func _torso(st: SurfaceTool, girth: float, chest_scale: float, hem_flare: float) -> void:
	var g: float = girth * _bulk
	var rings: Array[Ring] = [
		_ring(Vector3(0.0, 0.84, 0.0), 0.14 * g + hem_flare, 0.105 * g + hem_flare * 0.6, B_HIPS, B_HIPS, 0.0),
		_ring(Vector3(0.0, 0.93, 0.005), 0.165 * g, 0.115 * g, B_HIPS, B_HIPS, 0.0),
		_ring(Vector3(0.0, 1.03, 0.0), 0.152 * g, 0.105 * g, B_HIPS, B_SPINE, 0.5),
		_ring(Vector3(0.0, 1.13, 0.0), 0.148 * g, 0.102 * g, B_SPINE, B_SPINE, 0.0),
		_ring(Vector3(0.0, 1.24, -0.005), 0.165 * g * chest_scale, 0.112 * g, B_SPINE, B_CHEST, 0.6),
		_ring(Vector3(0.0, 1.35, -0.01), 0.185 * g * chest_scale, 0.118 * g, B_CHEST, B_CHEST, 0.0),
		_ring(Vector3(0.0, 1.43, 0.0), 0.192 * g * chest_scale, 0.112 * g, B_CHEST, B_CHEST, 0.0),
		_ring(Vector3(0.0, 1.49, 0.005), 0.16 * g, 0.1 * g, B_CHEST, B_CHEST, 0.0),
		_ring(Vector3(0.0, 1.525, 0.008), 0.105 * g, 0.08 * g, B_CHEST, B_CHEST, 0.0),
		_ring(Vector3(0.0, 1.545, 0.01), 0.07 * g, 0.065 * g, B_CHEST, B_NECK, 0.3),
	]
	_loft(st, rings, true, true)


func _neck_and_head(skin_st: SurfaceTool, neck_girth: float) -> void:
	var n: float = neck_girth
	var parts: Array[Ring] = [
		_ring(Vector3(0.0, 1.5, 0.01), 0.052 * n, 0.052 * n, B_CHEST, B_NECK, 0.3),
		_ring(Vector3(0.0, 1.58, 0.0), 0.047 * n, 0.05 * n, B_NECK, B_NECK, 0.0),
		_ring(Vector3(0.0, 1.635, -0.005), 0.05 * n, 0.055 * n, B_NECK, B_HEAD, 0.7),
	]
	_loft(skin_st, parts, false, false)
	var head: Array[Ring] = []
	var profile: Array[Vector4] = [
		Vector4(1.6, 0.03, 0.035, -0.035), Vector4(1.625, 0.058, 0.068, -0.02), Vector4(1.665, 0.074, 0.088, -0.012),
		Vector4(1.715, 0.08, 0.096, -0.008), Vector4(1.765, 0.081, 0.097, -0.004), Vector4(1.81, 0.072, 0.088, 0.0),
		Vector4(1.845, 0.052, 0.066, 0.004), Vector4(1.866, 0.022, 0.03, 0.006),
	]
	for p: Vector4 in profile:
		head.append(_ring(Vector3(0.0, p.x, p.w), p.y, p.z, B_HEAD, B_HEAD, 0.0))
	_loft(skin_st, head, true, true)


func _arm(st: SurfaceTool, side: float, girth: float) -> void:
	var g: float = girth * _bulk
	var shoulder: int = B_SHOULDER_L if side < 0.0 else B_SHOULDER_R
	var elbow: int = B_ELBOW_L if side < 0.0 else B_ELBOW_R
	var x: float = _rest[shoulder].x
	var parts: Array[Ring] = [
		_ring(Vector3(x * 0.82, 1.5, 0.0), 0.06 * g, 0.06 * g, B_CHEST, shoulder, 0.5),
		_ring(Vector3(x, 1.47, 0.0), 0.064 * g, 0.062 * g, shoulder, shoulder, 0.0),
		_ring(Vector3(x, 1.36, 0.0), 0.056 * g, 0.054 * g, shoulder, shoulder, 0.0),
		_ring(Vector3(x, 1.26, 0.0), 0.047 * g, 0.047 * g, shoulder, elbow, 0.15),
		_ring(Vector3(x, 1.2, 0.0), 0.043 * g, 0.044 * g, shoulder, elbow, 0.5),
		_ring(Vector3(x, 1.14, 0.0), 0.046 * g, 0.046 * g, elbow, elbow, 0.0),
		_ring(Vector3(x, 1.04, 0.0), 0.04 * g, 0.038 * g, elbow, elbow, 0.0),
		_ring(Vector3(x, 0.965, 0.0), 0.034 * g, 0.032 * g, elbow, elbow, 0.0),
	]
	_loft(st, parts, false, true)


func _hand(skin_st: SurfaceTool, side: float, scale_value: float) -> void:
	var elbow: int = B_ELBOW_L if side < 0.0 else B_ELBOW_R
	var x: float = _rest[elbow].x
	var s: float = scale_value
	var parts: Array[Ring] = [
		_ring(Vector3(x, 0.97, 0.0), 0.03 * s, 0.03 * s, elbow, elbow, 0.0),
		_ring(Vector3(x, 0.93, -0.003), 0.024 * s, 0.042 * s, elbow, elbow, 0.0),
		_ring(Vector3(x, 0.875, -0.006), 0.022 * s, 0.046 * s, elbow, elbow, 0.0),
		_ring(Vector3(x, 0.83, -0.008), 0.018 * s, 0.04 * s, elbow, elbow, 0.0),
		_ring(Vector3(x, 0.8, -0.01), 0.01 * s, 0.022 * s, elbow, elbow, 0.0),
	]
	_loft(skin_st, parts, false, true)
	var thumb: Array[Ring] = [
		_ring(Vector3(x - side * 0.018, 0.93, -0.03), 0.012 * s, 0.012 * s, elbow, elbow, 0.0),
		_ring(Vector3(x - side * 0.024, 0.89, -0.045), 0.01 * s, 0.01 * s, elbow, elbow, 0.0),
	]
	_loft(skin_st, thumb, true, true)


func _leg(st: SurfaceTool, side: float, girth: float, taper: float) -> void:
	var g: float = girth * _bulk
	var hip: int = B_HIP_L if side < 0.0 else B_HIP_R
	var knee: int = B_KNEE_L if side < 0.0 else B_KNEE_R
	var ankle: int = B_ANKLE_L if side < 0.0 else B_ANKLE_R
	var x: float = _rest[hip].x
	var parts: Array[Ring] = [
		_ring(Vector3(x * 0.85, 0.97, 0.0), 0.088 * g, 0.09 * g, B_HIPS, hip, 0.5),
		_ring(Vector3(x, 0.88, 0.0), 0.088 * g, 0.088 * g, hip, hip, 0.0),
		_ring(Vector3(x, 0.74, 0.0), 0.076 * g, 0.074 * g, hip, hip, 0.0),
		_ring(Vector3(x, 0.58, -0.005), 0.06 * g, 0.06 * g, hip, knee, 0.15),
		_ring(Vector3(x, 0.5, -0.01), 0.056 * g, 0.058 * g, hip, knee, 0.5),
		_ring(Vector3(x, 0.43, 0.0), 0.058 * g, 0.06 * g, knee, knee, 0.0),
		_ring(Vector3(x, 0.33, 0.01), 0.06 * g * taper, 0.064 * g * taper, knee, knee, 0.0),
		_ring(Vector3(x, 0.2, 0.0), 0.045 * g * taper, 0.046 * g * taper, knee, knee, 0.0),
		_ring(Vector3(x, 0.1, 0.0), 0.04 * g * taper, 0.04 * g * taper, knee, ankle, 0.6),
	]
	_loft(st, parts, false, true)


func _foot(st: SurfaceTool, side: float, width: float, height: float) -> void:
	var ankle: int = B_ANKLE_L if side < 0.0 else B_ANKLE_R
	var x: float = _rest[ankle].x
	var profile: Array[Vector4] = [
		Vector4(0.06, 0.04, 0.045, 0.05), Vector4(0.03, 0.048, 0.06, 0.055), Vector4(-0.04, 0.05, 0.045, 0.045),
		Vector4(-0.12, 0.048, 0.03, 0.035), Vector4(-0.175, 0.03, 0.018, 0.025),
	]
	var rings: Array[Ring] = []
	for p: Vector4 in profile:
		var ring := _ring(Vector3(x, p.w * height / 0.05, p.x), p.y * width, p.z * height / 0.05, ankle, ankle, 0.0)
		ring.right = Vector3.RIGHT
		ring.depth = Vector3.UP
		rings.append(ring)
	_loft(st, rings, true, true)


func _suit_material(base: Color, panel: Color, pattern: float, roughness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SUIT_SHADER) as Shader
	material.set_shader_parameter(&"base_color", base)
	material.set_shader_parameter(&"panel_color", panel)
	material.set_shader_parameter(&"pattern", pattern)
	material.set_shader_parameter(&"roughness_value", roughness)
	return material


func _accent(energy: float) -> StandardMaterial3D:
	var material := MaterialLibrary.emissive(Color(0.2, 0.9, 1.0), energy, false)
	_accent_materials.append(material)
	return material


# --- Outfits ------------------------------------------------------------------------------

func _dress_runner() -> void:
	var mesh := ArrayMesh.new()
	var jacket := _new_surface()
	_torso(jacket, 1.06, 1.0, 0.02)
	_arm(jacket, -1.0, 1.12)
	_arm(jacket, 1.0, 1.12)
	_commit(jacket, mesh, _suit_material(Color(0.15, 0.18, 0.16), Color(0.34, 0.35, 0.31), 0.0, 0.86))
	var pants := _new_surface()
	_leg(pants, -1.0, 1.1, 0.95)
	_leg(pants, 1.0, 1.1, 0.95)
	_commit(pants, mesh, _suit_material(Color(0.1, 0.11, 0.14), Color(0.16, 0.17, 0.2), 2.0, 0.9))
	var skin := _new_surface()
	_neck_and_head(skin, 1.0)
	_hand(skin, -1.0, 1.0)
	_hand(skin, 1.0, 1.0)
	_commit(skin, mesh, MaterialLibrary.skin(Color(0.7, 0.52, 0.42)))
	var shoes := _new_surface()
	_foot(shoes, -1.0, 1.05, 0.05)
	_foot(shoes, 1.0, 1.05, 0.05)
	_commit(shoes, mesh, MaterialLibrary.surface(Color(0.82, 0.82, 0.8), 0.55, 0.0, 0.4))
	_finish_body(mesh, true)

	_build_hood(Color(0.15, 0.18, 0.16))
	_face(Color(0.05, 0.035, 0.025), true)
	# Codex neural implant at the temple + jaw line.
	_gear(B_HEAD, "capsule", Vector3(0.079, 1.75, -0.03), Vector3(0.012, 0.05, 0.012), _accent(2.5), Vector3(70.0, 0.0, 0.0))
	_gear(B_HEAD, "sphere", Vector3(0.081, 1.75, 0.0), Vector3(0.018, 0.018, 0.018), MaterialLibrary.coated(Color(0.12, 0.13, 0.15), 0.9, 0.2))

	# Codex core backpack (doubles as the carried Uplink cipher slot).
	var pack_mat := MaterialLibrary.coated(Color(0.1, 0.11, 0.13), 0.5, 0.4)
	_gear(B_CHEST, "capsule", Vector3(0.0, 1.33, 0.165), Vector3(0.24, 0.3, 0.12), pack_mat)
	_gear(B_CHEST, "box", Vector3(0.0, 1.36, 0.228), Vector3(0.16, 0.012, 0.004), _accent(2.0))
	_gear(B_CHEST, "box", Vector3(0.0, 1.3, 0.228), Vector3(0.1, 0.01, 0.004), _accent(2.0))
	_carry_item = Node3D.new()
	var carry_socket: Node3D = _sockets[B_CHEST]
	carry_socket.add_child(_carry_item)
	_carry_item.position = Vector3(0.0, 1.33, 0.24) - _rest[B_CHEST]
	GeometryKit.mesh_box(_carry_item, Vector3.ZERO, Vector3(0.16, 0.16, 0.06), MaterialLibrary.coated(Color(0.75, 0.6, 0.22), 0.9, 0.25))
	GeometryKit.mesh_box(_carry_item, Vector3(0.0, 0.0, 0.032), Vector3(0.1, 0.1, 0.004), MaterialLibrary.emissive(Color(1.0, 0.75, 0.25), 4.0))
	_carry_item.visible = false
	# Cargo pockets, knee panels.
	var pocket := MaterialLibrary.fabric(Color(0.12, 0.13, 0.16))
	for side: float in [-1.0, 1.0]:
		var hip: int = B_HIP_L if side < 0.0 else B_HIP_R
		_gear(hip, "capsule", Vector3(_rest[hip].x + side * 0.072, 0.72, 0.0), Vector3(0.03, 0.12, 0.09), pocket)


func _dress_hunter() -> void:
	var mesh := ArrayMesh.new()
	var suit := _new_surface()
	_torso(suit, 1.0, 1.05, 0.0)
	_arm(suit, -1.0, 1.0)
	_arm(suit, 1.0, 1.0)
	_leg(suit, -1.0, 1.0, 1.0)
	_leg(suit, 1.0, 1.0, 1.0)
	_commit(suit, mesh, _suit_material(Color(0.07, 0.075, 0.085), Color(0.12, 0.13, 0.15), 1.0, 0.7))
	var dark := _new_surface()
	_neck_and_head(dark, 1.15)
	_hand(dark, -1.0, 1.15)
	_hand(dark, 1.0, 1.15)
	_foot(dark, -1.0, 1.15, 0.06)
	_foot(dark, 1.0, 1.15, 0.06)
	_commit(dark, mesh, MaterialLibrary.coated(Color(0.06, 0.06, 0.07), 0.4, 0.5))
	_finish_body(mesh, true)

	var plate := MaterialLibrary.coated(Color(0.3, 0.32, 0.35), 0.75, 0.28)
	var plate_dark := MaterialLibrary.coated(Color(0.1, 0.105, 0.115), 0.6, 0.35)
	var visor := _accent(4.0)
	var lamp := _accent(3.0)
	# Helmet with wrap-around visor and crest.
	_gear(B_HEAD, "sphere", Vector3(0.0, 1.74, 0.0), Vector3(0.2, 0.22, 0.235), plate)
	_gear(B_HEAD, "capsule", Vector3(0.0, 1.735, -0.075), Vector3(0.2, 0.06, 0.1), plate_dark, Vector3(0.0, 0.0, 90.0))
	_gear(B_HEAD, "capsule", Vector3(0.0, 1.737, -0.118), Vector3(0.17, 0.024, 0.02), visor, Vector3(0.0, 0.0, 90.0))
	_gear(B_HEAD, "capsule", Vector3(0.0, 1.645, -0.07), Vector3(0.11, 0.06, 0.07), plate_dark)
	# Torso armour: chest + back plates, collar, abdominal bands, belt.
	_gear(B_CHEST, "capsule", Vector3(0.0, 1.37, -0.085), Vector3(0.38, 0.32, 0.12), plate)
	_gear(B_CHEST, "capsule", Vector3(0.0, 1.37, 0.085), Vector3(0.36, 0.32, 0.12), plate)
	_gear(B_CHEST, "capsule", Vector3(0.0, 1.52, 0.0), Vector3(0.24, 0.08, 0.2), plate_dark, Vector3(0.0, 0.0, 90.0))
	_gear(B_CHEST, "box", Vector3(0.09, 1.42, -0.15), Vector3(0.05, 0.025, 0.01), lamp)
	_gear(B_CHEST, "box", Vector3(0.0, 1.3, -0.148), Vector3(0.26, 0.008, 0.005), lamp)
	_gear(B_CHEST, "box", Vector3(0.0, 1.38, 0.21), Vector3(0.22, 0.26, 0.1), plate_dark)
	_gear(B_CHEST, "cylinder", Vector3(0.08, 1.7, 0.22), Vector3(0.012, 0.4, 0.012), plate_dark)
	_gear(B_CHEST, "sphere", Vector3(0.08, 1.9, 0.22), Vector3(0.025, 0.025, 0.025), lamp)
	for y: float in [1.2, 1.12]:
		_gear(B_SPINE, "capsule", Vector3(0.0, y, -0.045), Vector3(0.3, 0.05, 0.16), plate_dark, Vector3(0.0, 0.0, 90.0))
	_gear(B_HIPS, "capsule", Vector3(0.0, 0.97, 0.0), Vector3(0.38, 0.07, 0.26), plate_dark, Vector3(0.0, 0.0, 90.0))
	_gear(B_HIPS, "box", Vector3(0.0, 0.94, -0.12), Vector3(0.12, 0.06, 0.03), plate)
	# Pauldrons, bracers, gauntlets.
	for side: float in [-1.0, 1.0]:
		var shoulder: int = B_SHOULDER_L if side < 0.0 else B_SHOULDER_R
		var elbow: int = B_ELBOW_L if side < 0.0 else B_ELBOW_R
		var sx: float = _rest[shoulder].x
		_gear(shoulder, "sphere", Vector3(sx + side * 0.02, 1.5, 0.0), Vector3(0.21, 0.15, 0.21), plate)
		_gear(shoulder, "capsule", Vector3(sx + side * 0.01, 1.33, 0.0), Vector3(0.11, 0.17, 0.11), plate_dark)
		_gear(elbow, "capsule", Vector3(sx, 1.06, 0.0), Vector3(0.1, 0.18, 0.1), plate)
		_gear(elbow, "box", Vector3(sx + side * 0.05, 1.06, 0.0), Vector3(0.012, 0.12, 0.03), lamp)
	# Scanner on the right forearm.
	_gear(B_ELBOW_R, "box", Vector3(_rest[B_ELBOW_R].x, 0.98, -0.06), Vector3(0.06, 0.05, 0.14), plate_dark)
	_gear(B_ELBOW_R, "box", Vector3(_rest[B_ELBOW_R].x, 0.98, -0.132), Vector3(0.04, 0.03, 0.004), lamp)
	# Leg armour.
	for side: float in [-1.0, 1.0]:
		var hip: int = B_HIP_L if side < 0.0 else B_HIP_R
		var knee: int = B_KNEE_L if side < 0.0 else B_KNEE_R
		var ankle: int = B_ANKLE_L if side < 0.0 else B_ANKLE_R
		var x: float = _rest[hip].x
		_gear(hip, "capsule", Vector3(x, 0.74, -0.04), Vector3(0.15, 0.27, 0.11), plate)
		_gear(knee, "sphere", Vector3(x, 0.5, -0.05), Vector3(0.1, 0.11, 0.08), plate_dark)
		_gear(knee, "capsule", Vector3(x, 0.28, -0.035), Vector3(0.12, 0.28, 0.1), plate)
		_gear(ankle, "capsule", Vector3(x, 0.07, -0.04), Vector3(0.13, 0.1, 0.27), plate_dark, Vector3(90.0, 0.0, 0.0))


func _dress_civilian(rng: RandomNumberGenerator) -> void:
	var tops: Array[Color] = [Color(0.45, 0.1, 0.1), Color(0.12, 0.25, 0.4), Color(0.35, 0.33, 0.28), Color(0.1, 0.1, 0.11), Color(0.2, 0.35, 0.25), Color(0.6, 0.55, 0.45)]
	var bottoms: Array[Color] = [Color(0.12, 0.17, 0.3), Color(0.22, 0.2, 0.17), Color(0.08, 0.08, 0.09), Color(0.35, 0.3, 0.22)]
	var skins: Array[Color] = [Color(0.85, 0.66, 0.54), Color(0.7, 0.52, 0.42), Color(0.5, 0.35, 0.25), Color(0.32, 0.22, 0.16)]
	var hairs: Array[Color] = [Color(0.05, 0.035, 0.025), Color(0.25, 0.15, 0.08), Color(0.55, 0.45, 0.3), Color(0.12, 0.12, 0.12)]
	var top: Color = tops[rng.randi_range(0, tops.size() - 1)]
	var bottom: Color = bottoms[rng.randi_range(0, bottoms.size() - 1)]
	var skin_color: Color = skins[rng.randi_range(0, skins.size() - 1)]
	var coat: bool = rng.randf() < 0.45
	var mesh := ArrayMesh.new()
	var upper := _new_surface()
	_torso(upper, 1.05 if coat else 1.0, 1.0, 0.05 if coat else 0.0)
	_arm(upper, -1.0, 1.08 if coat else 1.0)
	_arm(upper, 1.0, 1.08 if coat else 1.0)
	_commit(upper, mesh, _suit_material(top, top.darkened(0.25), 2.0, 0.85))
	var legs := _new_surface()
	_leg(legs, -1.0, 1.04, 0.95)
	_leg(legs, 1.0, 1.04, 0.95)
	_commit(legs, mesh, _suit_material(bottom, bottom.darkened(0.2), 2.0, 0.9))
	var skin := _new_surface()
	_neck_and_head(skin, 1.0)
	_hand(skin, -1.0, 1.0)
	_hand(skin, 1.0, 1.0)
	_commit(skin, mesh, MaterialLibrary.skin(skin_color))
	var shoes := _new_surface()
	_foot(shoes, -1.0, 1.0, 0.045)
	_foot(shoes, 1.0, 1.0, 0.045)
	_commit(shoes, mesh, MaterialLibrary.surface(Color(0.08, 0.07, 0.06) if rng.randf() < 0.6 else Color(0.8, 0.8, 0.78), 0.5, 0.0, 0.3))
	_finish_body(mesh, false)
	_face(hairs[rng.randi_range(0, hairs.size() - 1)], false)
	if coat:
		_gear(B_HIPS, "cylinder", Vector3(0.0, 0.78, 0.0), Vector3(0.36, 0.16, 0.26), MaterialLibrary.fabric(top.darkened(0.1)))
	if rng.randf() < 0.35:
		_gear(B_CHEST, "capsule", Vector3(0.0, 1.3, 0.14), Vector3(0.22, 0.28, 0.1), MaterialLibrary.fabric(Color(0.1, 0.1, 0.1)))


func _dress_technician(rng: RandomNumberGenerator) -> void:
	var mesh := ArrayMesh.new()
	var coat := _new_surface()
	_torso(coat, 1.05, 1.0, 0.04)
	_arm(coat, -1.0, 1.08)
	_arm(coat, 1.0, 1.08)
	_commit(coat, mesh, _suit_material(Color(0.82, 0.84, 0.83), Color(0.7, 0.72, 0.72), 2.0, 0.8))
	var legs := _new_surface()
	_leg(legs, -1.0, 1.03, 0.95)
	_leg(legs, 1.0, 1.03, 0.95)
	_commit(legs, mesh, _suit_material(Color(0.22, 0.23, 0.26), Color(0.18, 0.19, 0.21), 2.0, 0.9))
	var skin := _new_surface()
	_neck_and_head(skin, 1.0)
	_hand(skin, -1.0, 1.0)
	_hand(skin, 1.0, 1.0)
	var skins: Array[Color] = [Color(0.85, 0.66, 0.54), Color(0.7, 0.52, 0.42), Color(0.45, 0.32, 0.23)]
	_commit(skin, mesh, MaterialLibrary.skin(skins[rng.randi_range(0, skins.size() - 1)]))
	var shoes := _new_surface()
	_foot(shoes, -1.0, 1.0, 0.045)
	_foot(shoes, 1.0, 1.0, 0.045)
	_commit(shoes, mesh, MaterialLibrary.surface(Color(0.06, 0.06, 0.06), 0.4, 0.0, 0.2))
	_finish_body(mesh, false)
	_face(Color(0.1, 0.08, 0.06) if rng.randf() < 0.5 else Color(0.4, 0.35, 0.3), false)
	# Lab coat skirt, ID badge, glasses.
	var coat_mat := MaterialLibrary.fabric(Color(0.84, 0.86, 0.85))
	_gear(B_HIPS, "cylinder", Vector3(0.0, 0.76, 0.0), Vector3(0.37, 0.24, 0.27), coat_mat)
	_gear(B_CHEST, "box", Vector3(0.1, 1.36, -0.125), Vector3(0.055, 0.075, 0.006), MaterialLibrary.surface(Color(0.95, 0.95, 0.95), 0.4, 0.0, 0.0))
	_gear(B_CHEST, "box", Vector3(0.1, 1.38, -0.129), Vector3(0.04, 0.012, 0.002), _accent(2.0))
	var frame := MaterialLibrary.coated(Color(0.05, 0.05, 0.05), 0.5, 0.4)
	for x: float in [-0.032, 0.032]:
		_gear(B_HEAD, "box", Vector3(x, 1.745, -0.093), Vector3(0.042, 0.026, 0.004), MaterialLibrary.glass(Color(0.2, 0.25, 0.3)))
	_gear(B_HEAD, "box", Vector3(0.0, 1.758, -0.094), Vector3(0.11, 0.005, 0.005), frame)


## Skinned hood: an open shell around the head (face left open) draping into a collar.
func _build_hood(color: Color) -> void:
	var mesh := ArrayMesh.new()
	var st := _new_surface()
	var front: float = PI * 1.5
	var opening: float = 0.95
	var profile: Array[Vector4] = [
		Vector4(1.53, 0.135, 0.12, 0.03), Vector4(1.59, 0.1, 0.105, 0.025), Vector4(1.66, 0.098, 0.115, 0.02),
		Vector4(1.73, 0.104, 0.122, 0.018), Vector4(1.8, 0.098, 0.115, 0.02), Vector4(1.855, 0.075, 0.09, 0.025),
		Vector4(1.895, 0.035, 0.045, 0.03),
	]
	var rings: Array[Ring] = []
	for i: int in profile.size():
		var p: Vector4 = profile[i]
		var bone_a: int = B_CHEST if i == 0 else (B_NECK if i == 1 else B_HEAD)
		var bone_b: int = B_NECK if i == 0 else B_HEAD
		rings.append(_ring(Vector3(0.0, p.x, p.w), p.y, p.z, bone_a, bone_b, 0.0 if i > 1 else 0.6))
	_loft_arc(st, rings, front + opening, front - opening + TAU, 18)
	var cloth := MaterialLibrary.fabric(color).duplicate() as StandardMaterial3D
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_commit(st, mesh, cloth)
	_finish_body(mesh, false).name = "Hood"


## Eyes, brows, nose, ears and hair for unhelmeted characters.
func _face(hair_color: Color, under_hood: bool) -> void:
	var eye := MaterialLibrary.coated(Color(0.03, 0.03, 0.035), 0.0, 0.15)
	var white := MaterialLibrary.surface(Color(0.85, 0.83, 0.8), 0.35, 0.0, 0.0)
	var hair := MaterialLibrary.surface(hair_color, 0.75, 0.0, 1.2, 10.0)
	for x: float in [-0.032, 0.032]:
		_gear(B_HEAD, "sphere", Vector3(x, 1.745, -0.083), Vector3(0.026, 0.016, 0.012), white)
		_gear(B_HEAD, "sphere", Vector3(x, 1.745, -0.088), Vector3(0.012, 0.012, 0.008), eye)
		_gear(B_HEAD, "box", Vector3(x, 1.765, -0.09), Vector3(0.03, 0.006, 0.008), hair, Vector3(0.0, 0.0, -8.0 if x < 0.0 else 8.0))
		_gear(B_HEAD, "sphere", Vector3(x * 2.55, 1.735, 0.0), Vector3(0.018, 0.04, 0.028), MaterialLibrary.skin(Color(0.68, 0.5, 0.4)))
	_gear(B_HEAD, "capsule", Vector3(0.0, 1.715, -0.097), Vector3(0.022, 0.045, 0.026), MaterialLibrary.skin(Color(0.68, 0.5, 0.4)), Vector3(-12.0, 0.0, 0.0))
	_gear(B_HEAD, "box", Vector3(0.0, 1.668, -0.09), Vector3(0.034, 0.006, 0.006), MaterialLibrary.surface(Color(0.45, 0.28, 0.25), 0.5, 0.0, 0.0))
	if not under_hood:
		var cap := _gear(B_HEAD, "sphere", Vector3(0.0, 1.79, 0.012), Vector3(0.172, 0.17, 0.205), hair)
		_make_hemisphere(cap)
		_gear(B_HEAD, "sphere", Vector3(0.0, 1.76, 0.04), Vector3(0.16, 0.13, 0.15), hair)


func _make_hemisphere(instance: MeshInstance3D) -> void:
	var sphere := instance.mesh as SphereMesh
	if sphere == null:
		return
	sphere.is_hemisphere = true
	sphere.height = sphere.radius
