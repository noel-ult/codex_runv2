class_name HumanoidRig
extends Node3D
## Procedurally generated, skinned and procedurally animated humanoid.
##
## Body and clothing surfaces are lofted from shaped cross-sections into an ArrayMesh.
## Blended weights on a Skeleton3D deform the shoulders, elbows, wrists, hips and knees.
## Clothing surfaces use the `suit` shader (seams, zipper, glowing Codex veins); armour,
## hoods, hair, gear and props are rigid pieces on BoneAttachment3D sockets.
## `animate()` is called every physics frame by the owner and drives idle / walk / run, jump,
## fall, landing squash, dash lean, crouch, crawl and scan poses through bone rotations.
## The rig faces -Z; the owner rotates it to face the travel direction.

enum Style { RUNNER, HUNTER, CIVILIAN, TECHNICIAN }

const SUIT_SHADER: String = "res://shaders/suit.gdshader"
const SEGMENTS: int = 18
const THIGH_LENGTH: float = 0.43
const SHIN_LENGTH: float = 0.42
const ANKLE_HEIGHT: float = 0.07

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
var _hips_x: float = 0.0
var _sockets: Dictionary = {}
var _accent_materials: Array[StandardMaterial3D] = []
var _accent_meshes: Array[MeshInstance3D] = []
var _carry_item: Node3D
var _accent_color: Color = Color(0.2, 0.9, 1.0)
var _accent_energy: float = 1.0
var _bulk: float = 1.0

var _phase: float = 0.0
var _time: float = 0.0
var _gait_speed: float = 0.0
var _last_vertical_speed: float = 0.0
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
	var acceleration_lean: float = clampf((speed - _gait_speed) * 0.045, -0.1, 0.14)
	_gait_speed = lerpf(_gait_speed, speed, 1.0 - exp(-18.0 * delta))
	var move: float = smoothstep(0.0, 1.3, _gait_speed)
	var run: float = smoothstep(2.2, maxf(run_speed, 2.3), _gait_speed)
	var stride: float = lerpf(1.35, 2.45, run)
	var cadence: float = minf(_gait_speed / stride, 3.4)
	_phase = fmod(_phase + cadence * TAU * delta, TAU)

	_air_blend = move_toward(_air_blend, 0.0 if on_floor else 1.0, delta * 7.0)
	if on_floor and not _was_on_floor:
		_land_squash = clampf(-_last_vertical_speed * 0.022, 0.06, 0.24)
	_was_on_floor = on_floor
	_last_vertical_speed = local_velocity.y
	_land_squash = move_toward(_land_squash, 0.0, delta * 1.2)

	var ground: float = (1.0 - _air_blend) * (1.0 - prone_amount)
	var cycle: float = _phase / TAU
	var sway: float = sin(_phase)
	var step: float = cos(_phase)
	var idle: float = (1.0 - move) * ground
	var breathe: float = sin(_time * 2.15) * idle
	var support: float = lerpf(0.62, 0.43, run)
	var stride_reach: float = stride * support * 0.5 * move * (1.0 - crouch_amount * 0.25)
	var lift: float = lerpf(0.105, 0.34, run) * move
	var foot_l: Vector3 = _stride_foot(cycle, support, stride_reach, lift, move)
	var foot_r: Vector3 = _stride_foot(fmod(cycle + 0.5, 1.0), support, stride_reach, lift, move)
	var squash: float = _land_squash + crouch_amount * 0.35 * (1.0 - prone_amount)
	var hips_y: float = 0.955 + breathe * 0.006
	hips_y += (lerpf(-0.025, -0.048, run) - cos(_phase * 2.0 - 0.5) * lerpf(0.022, 0.048, run)) * move
	hips_y = minf(hips_y - squash * 0.5, minf(_reachable_hip_height(foot_l), _reachable_hip_height(foot_r)))

	var leg_l: Vector2 = _solve_leg(foot_l, hips_y)
	var leg_r: Vector2 = _solve_leg(foot_r, hips_y)
	var hip_l: float = leg_l.x
	var hip_r: float = leg_r.x
	var knee_l: float = leg_l.y
	var knee_r: float = leg_r.y
	var arm_amp: float = lerpf(0.34, 0.69, run) * move
	var arm_cycle: float = cos(_phase - 0.24)
	var shoulder_l: float = -arm_cycle * arm_amp + breathe * 0.025
	var shoulder_r: float = arm_cycle * arm_amp + breathe * 0.018
	var elbow: float = lerpf(0.25, 1.08, run) * move + 0.12
	var spine: float = -lerpf(0.045, 0.23, run) * move - acceleration_lean * ground + breathe * 0.023
	var chest_twist: float = -step * lerpf(0.16, 0.26, run) * move * ground
	var hips_twist: float = step * lerpf(0.095, 0.13, run) * move * ground
	var hips_roll: float = -sway * 0.055 * move * ground
	var hips_x: float = (sway * 0.037 * move + sin(_time * 0.83) * 0.015 * idle) * ground
	var arm_out: float = lerpf(0.08, 0.16, run) + 0.025 * idle
	var head_y: float = sin(_time * 0.69) * 0.16 * idle - chest_twist * 0.5
	var head_pitch: float = (-cos(_phase * 2.0 - 0.32) * 0.045 * move + breathe * 0.014) * ground

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
	var foot_roll_l: float = foot_l.z * ground
	var foot_roll_r: float = foot_r.z * ground

	var elbow_r: float = elbow + maxf(arm_cycle, 0.0) * 0.18 * move * ground
	elbow += maxf(-arm_cycle, 0.0) * 0.18 * move * ground
	if dashing:
		spine = -0.75
		shoulder_l = -1.1
		shoulder_r = -1.1
		elbow = 0.2
		elbow_r = 0.2
		arm_out = 0.35
		hip_l = 0.9
		hip_r = -0.6
		knee_l = -0.6
		knee_r = -0.3
		foot_roll_l = 0.0
		foot_roll_r = 0.0

	if scanning:
		shoulder_r = 1.45
		elbow_r = 0.15
		head_y = sin(_time * 1.6) * 0.9

	# Prone crawl: arms reach overhead alternately, legs push, head tilts up to look ahead.
	if prone_amount > 0.01:
		var p: float = prone_amount
		var crawl: float = sway
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
	rotation.x = -PI * 0.5 * prone_amount
	position = Vector3(0.0, 0.14 * prone_amount, 0.85 * prone_amount)

	spine -= squash * 0.5
	var lean_z: float = clampf(-local_velocity.x * 0.02, -0.2, 0.2)

	var k: float = 1.0 - exp(-joint_smoothing * delta)
	var leg_k: float = 1.0 - exp(-joint_smoothing * 1.8 * delta)
	_hips_y = lerpf(_hips_y, hips_y, leg_k)
	_hips_x = lerpf(_hips_x, hips_x, k)
	_blend(B_HIPS, Vector3(0.0, hips_twist, lean_z + hips_roll), k)
	_blend(B_SPINE, Vector3(spine, 0.0, 0.0), k)
	_blend(B_CHEST, Vector3(breathe * 0.032, chest_twist, -hips_roll * 1.5), k)
	_blend(B_NECK, Vector3(-spine * 0.3 + prone_amount * 0.6, head_y * 0.4, -lean_z * 0.3), k)
	_blend(B_HEAD, Vector3(-spine * 0.35 + prone_amount * 0.5 + head_pitch, head_y * 0.6, -lean_z * 0.45), k)
	_blend(B_HIP_L, Vector3(hip_l, 0.0, 0.0), leg_k)
	_blend(B_HIP_R, Vector3(hip_r, 0.0, 0.0), leg_k)
	_blend(B_KNEE_L, Vector3(knee_l, 0.0, 0.0), leg_k)
	_blend(B_KNEE_R, Vector3(knee_r, 0.0, 0.0), leg_k)
	var ankle_balance: float = lerpf(0.5, 1.0, ground if not dashing else 0.0)
	_blend(B_ANKLE_L, Vector3(foot_roll_l - (hip_l + knee_l) * ankle_balance, 0.0, 0.0), leg_k)
	_blend(B_ANKLE_R, Vector3(foot_roll_r - (hip_r + knee_r) * ankle_balance, 0.0, 0.0), leg_k)
	_blend(B_SHOULDER_L, Vector3(shoulder_l, 0.0, -arm_out), k)
	_blend(B_SHOULDER_R, Vector3(shoulder_r, 0.0, arm_out), k)
	_blend(B_ELBOW_L, Vector3(elbow, 0.0, 0.0), k)
	_blend(B_ELBOW_R, Vector3(elbow_r, 0.0, 0.0), k)
	var wrist_swing: float = -sway * 0.10 * move * ground
	_blend(B_WRIST_L, Vector3(wrist_swing, 0.0, -breathe * 0.035), k)
	_blend(B_WRIST_R, Vector3(0.0 if scanning else -wrist_swing, 0.0, breathe * 0.03), k)

	_skeleton.set_bone_pose_position(B_HIPS, Vector3(_hips_x, _hips_y, 0.0))
	for i: int in BONE_COUNT:
		_skeleton.set_bone_pose_rotation(i, Quaternion.from_euler(_euler[i]))


## Returns the forward offset, ankle height and shoe pitch over one step cycle.
func _stride_foot(cycle: float, support: float, reach: float, lift: float, move: float) -> Vector3:
	var forward: float
	var height: float = ANKLE_HEIGHT
	var pitch: float
	if cycle < support:
		var contact: float = cycle / support
		forward = lerpf(reach, -reach, contact)
		pitch = (0.24 * (1.0 - smoothstep(0.0, 0.28, contact)) - 0.40 * smoothstep(0.68, 1.0, contact)) * move
	else:
		var swing: float = (cycle - support) / (1.0 - support)
		forward = lerpf(-reach, reach, smoothstep(0.0, 1.0, swing))
		height += sin(swing * PI) * lift
		pitch = lerpf(-0.40, 0.24, smoothstep(0.05, 0.91, swing)) * move
	# Keep the rocking heel and toe above the sole's neutral plane.
	height += maxf(sin(pitch) * 0.06, -sin(pitch) * 0.16)
	return Vector3(forward, height, pitch)


func _reachable_hip_height(foot: Vector3) -> float:
	var reach_sq: float = pow(THIGH_LENGTH + SHIN_LENGTH - 0.004, 2.0)
	return foot.y + sqrt(maxf(reach_sq - foot.x * foot.x, 0.0)) - BONE_OFFSETS[B_HIP_L].y


## In the sagittal plane, solve thigh and knee angles for the ankle target.
func _solve_leg(foot: Vector3, hips_y: float) -> Vector2:
	var drop: float = hips_y + BONE_OFFSETS[B_HIP_L].y - foot.y
	var distance_sq: float = drop * drop + foot.x * foot.x
	var cosine: float = (distance_sq - THIGH_LENGTH * THIGH_LENGTH - SHIN_LENGTH * SHIN_LENGTH) / (2.0 * THIGH_LENGTH * SHIN_LENGTH)
	var bend: float = acos(clampf(cosine, -1.0, 1.0))
	var hip: float = atan2(foot.x, drop) + atan2(SHIN_LENGTH * sin(bend), THIGH_LENGTH + SHIN_LENGTH * cos(bend))
	return Vector2(hip, -bend)


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
	var jaw_shape: float = 1.0
	var face_shape: Vector3 = Vector3.ZERO
	var hairline_drop: float = 0.0

	func _init(c: Vector3, radius_x: float, radius_z: float, b: PackedInt32Array, w: PackedFloat32Array) -> void:
		center = c
		rx = radius_x
		rz = radius_z
		bones = b
		weights = w


func _ring(c: Vector3, rx: float, rz: float, a: int, b: int, t: float) -> Ring:
	return Ring.new(c, rx, rz, PackedInt32Array([a, b, 0, 0]), PackedFloat32Array([1.0 - t, t, 0.0, 0.0]))


## Lofts a closed tube through `rings` into SurfaceTool `st` (clockwise front faces).
func _loft(st: SurfaceTool, rings: Array[Ring], cap_start: bool, cap_end: bool, segments: int = SEGMENTS) -> void:
	var base: int = _vertex_count(st)
	var count: int = rings.size()
	var reverse_side: bool = _reverse_loft(rings)
	for r: int in count:
		var ring: Ring = rings[r]
		for j: int in segments + 1:
			var u: float = float(j) / float(segments)
			st.set_uv(Vector2(u, float(r) / float(maxi(count - 1, 1))))
			st.set_bones(ring.bones)
			st.set_weights(ring.weights)
			st.add_vertex(_ring_position(ring, TAU * u))
	for r: int in count - 1:
		for j: int in segments:
			_loft_quad(st, base + r * (segments + 1) + j, segments + 1, reverse_side)
	_vertex_counts[st] = base + count * (segments + 1)
	if cap_start:
		_cap(st, rings[0], base, reverse_side, segments)
	if cap_end:
		_cap(st, rings[count - 1], base + (count - 1) * (segments + 1), not reverse_side, segments)


var _vertex_counts: Dictionary = {}


## Lofts an open sheet covering angles [a_start, a_end] of each ring (hoods, visors, collars).
func _loft_arc(st: SurfaceTool, rings: Array[Ring], a_start: float, a_end: float, steps: int, hem_angle: Vector2 = Vector2.ZERO) -> void:
	var base: int = _vertex_count(st)
	var count: int = rings.size()
	var reverse_side: bool = _reverse_loft(rings) != (a_end < a_start)
	for r: int in count:
		var ring: Ring = rings[r]
		var along: float = float(r) / float(maxi(count - 1, 1))
		for j: int in steps + 1:
			var t: float = float(j) / float(steps)
			var a: float = lerpf(a_start, a_end, t) + lerpf(hem_angle.x, hem_angle.y, t) * along * along
			st.set_uv(Vector2(t, along))
			st.set_bones(ring.bones)
			st.set_weights(ring.weights)
			st.add_vertex(_ring_position(ring, a))
	for r: int in count - 1:
		for j: int in steps:
			_loft_quad(st, base + r * (steps + 1) + j, steps + 1, reverse_side)
	_vertex_counts[st] = base + count * (steps + 1)


func _ring_position(ring: Ring, angle: float) -> Vector3:
	var lateral: float = cos(angle)
	var front: float = sin(angle)
	var width: float = lateral if is_equal_approx(ring.jaw_shape, 1.0) else signf(lateral) * pow(absf(lateral), ring.jaw_shape)
	var position: Vector3 = ring.center + ring.right * width * ring.rx + ring.depth * front * ring.rz
	if ring.face_shape != Vector3.ZERO and front < 0.0:
		# Local changes to the front profile form the lips, bridge and cheek/eye planes.
		var center_line: float = 1.0 - smoothstep(0.03, 0.29, absf(lateral))
		var cheeks: float = 1.0 - smoothstep(0.05, 0.45, absf(absf(lateral) - 0.48))
		position.z -= ring.face_shape.x * center_line + ring.face_shape.y * cheeks
		position.z -= ring.face_shape.z * smoothstep(0.0, 0.96, -front)
	position.y -= ring.hairline_drop * (front * 0.5 + 0.5)
	return position


func _reverse_loft(rings: Array[Ring]) -> bool:
	var start: Ring = rings[0]
	var axis: Vector3 = rings[rings.size() - 1].center - start.center
	return axis.dot(start.right.cross(start.depth)) < 0.0


func _loft_quad(st: SurfaceTool, first: int, stride: int, reverse: bool) -> void:
	var next_ring: int = first + stride
	var b: int = first + 1 if reverse else next_ring
	var c: int = next_ring if reverse else first + 1
	st.add_index(first)
	st.add_index(b)
	st.add_index(c)
	st.add_index(c)
	st.add_index(b)
	st.add_index(next_ring + 1)


func _vertex_count(st: SurfaceTool) -> int:
	return int(_vertex_counts.get(st, 0))


func _cap(st: SurfaceTool, ring: Ring, ring_start: int, flip: bool, segments: int) -> void:
	var center_index: int = _vertex_count(st)
	st.set_uv(Vector2(0.5, 0.0 if flip else 1.0))
	st.set_bones(ring.bones)
	st.set_weights(ring.weights)
	st.add_vertex(ring.center)
	_vertex_counts[st] = center_index + 1
	for j: int in segments:
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
	_vertex_counts.erase(st)


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
func _torso(st: SurfaceTool, girth: float, chest_scale: float, hem_flare: float, has_split_hem: bool = false) -> void:
	var g: float = girth * _bulk
	var bottom: Ring = _ring(Vector3(0.0, 0.907, 0.013), 0.171 * g + hem_flare, 0.127 * g + hem_flare * 0.45, B_HIPS, B_HIPS, 0.0)
	if has_split_hem:
		bottom = _ring(Vector3(0.0, 0.953, 0.013), 0.172 * g, 0.128 * g, B_HIPS, B_HIPS, 0.0)
	var rings: Array[Ring] = [
		bottom,
		_ring(Vector3(0.0, 0.966, 0.012), 0.164 * g, 0.118 * g, B_HIPS, B_HIPS, 0.0),
		_ring(Vector3(0.0, 1.03, 0.0), 0.152 * g, 0.105 * g, B_HIPS, B_SPINE, 0.5),
		_ring(Vector3(0.0, 1.13, 0.0), 0.148 * g, 0.102 * g, B_SPINE, B_SPINE, 0.0),
		_ring(Vector3(0.0, 1.24, -0.005), 0.165 * g * chest_scale, 0.112 * g, B_SPINE, B_CHEST, 0.6),
		_ring(Vector3(0.0, 1.35, -0.01), 0.185 * g * chest_scale, 0.118 * g, B_CHEST, B_CHEST, 0.0),
		_ring(Vector3(0.0, 1.43, 0.0), 0.192 * g * chest_scale, 0.112 * g, B_CHEST, B_CHEST, 0.0),
		_ring(Vector3(0.0, 1.485, 0.005), 0.171 * g, 0.096 * g, B_CHEST, B_CHEST, 0.0),
		_ring(Vector3(0.0, 1.525, 0.008), 0.105 * g, 0.08 * g, B_CHEST, B_CHEST, 0.0),
		_ring(Vector3(0.0, 1.545, 0.01), 0.07 * g, 0.065 * g, B_CHEST, B_NECK, 0.3),
	]
	_loft(st, rings, true, true)


func _neck_and_head(skin_st: SurfaceTool, neck_girth: float) -> void:
	var n: float = neck_girth
	var parts: Array[Ring] = [
		_ring(Vector3(0.0, 1.505, 0.009), 0.057 * n, 0.055 * n, B_CHEST, B_NECK, 0.3),
		_ring(Vector3(0.0, 1.572, 0.008), 0.049 * n, 0.053 * n, B_NECK, B_NECK, 0.0),
		_ring(Vector3(0.0, 1.619, 0.006), 0.051 * n, 0.058 * n, B_NECK, B_HEAD, 0.65),
		_ring(Vector3(0.0, 1.665, 0.004), 0.050 * n, 0.059 * n, B_HEAD, B_HEAD, 0.0),
	]
	_loft(skin_st, parts, true, true)
	var head: Array[Ring] = []
	var profile: Array[Vector4] = [
		Vector4(1.605, 0.036, 0.050, -0.018), Vector4(1.626, 0.056, 0.075, -0.010),
		Vector4(1.651, 0.068, 0.083, -0.006), Vector4(1.671, 0.073, 0.087, -0.003),
		Vector4(1.693, 0.077, 0.089, 0.001), Vector4(1.711, 0.081, 0.090, 0.002),
		Vector4(1.726, 0.084, 0.092, 0.002), Vector4(1.744, 0.084, 0.092, 0.003),
		Vector4(1.757, 0.083, 0.092, 0.004), Vector4(1.776, 0.082, 0.095, 0.004),
		Vector4(1.811, 0.074, 0.091, 0.007), Vector4(1.841, 0.057, 0.069, 0.009),
		Vector4(1.863, 0.026, 0.035, 0.010), Vector4(1.869, 0.006, 0.009, 0.012),
	]
	# X projects the center, Y models cheeks or recessed eyes, and Z shifts the front plane.
	var features: Array[Vector3] = [
		Vector3.ZERO, Vector3(0.004, 0.0, 0.0), Vector3(0.007, 0.001, 0.002), Vector3(0.009, 0.001, 0.004),
		Vector3(0.005, 0.005, 0.0), Vector3(0.028, 0.007, 0.0), Vector3(0.017, 0.005, 0.0),
		Vector3(0.010, -0.006, 0.0), Vector3(0.006, -0.005, 0.0), Vector3(0.002, 0.002, 0.003),
		Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
	]
	for index: int in profile.size():
		var p: Vector4 = profile[index]
		var section: Ring = _ring(Vector3(0.0, p.x, p.w), p.y, p.z, B_HEAD, B_HEAD, 0.0)
		section.face_shape = features[index]
		section.jaw_shape = 0.79 if index < 5 else 1.0
		head.append(section)
	_loft(skin_st, head, true, true, 36)


func _arm(st: SurfaceTool, side: float, girth: float) -> void:
	var g: float = girth * _bulk
	var shoulder: int = B_SHOULDER_L if side < 0.0 else B_SHOULDER_R
	var elbow: int = B_ELBOW_L if side < 0.0 else B_ELBOW_R
	var wrist: int = B_WRIST_L if side < 0.0 else B_WRIST_R
	var x: float = _rest[shoulder].x
	var parts: Array[Ring] = [
		_ring(Vector3(x * 0.72, 1.51, 0.006), 0.033 * g, 0.039 * g, B_CHEST, shoulder, 0.15),
		_ring(Vector3(x * 0.93, 1.478, 0.004), 0.063 * g, 0.063 * g, B_CHEST, shoulder, 0.64),
		_ring(Vector3(x, 1.42, 0.001), 0.066 * g, 0.061 * g, shoulder, shoulder, 0.0),
		_ring(Vector3(x, 1.36, -0.004), 0.055 * g, 0.056 * g, shoulder, shoulder, 0.0),
		_ring(Vector3(x, 1.26, 0.0), 0.047 * g, 0.047 * g, shoulder, elbow, 0.15),
		_ring(Vector3(x, 1.2, 0.0), 0.043 * g, 0.044 * g, shoulder, elbow, 0.5),
		_ring(Vector3(x, 1.14, 0.0), 0.046 * g, 0.046 * g, elbow, elbow, 0.0),
		_ring(Vector3(x, 1.095, -0.003), 0.043 * g, 0.041 * g, elbow, elbow, 0.0),
		_ring(Vector3(x, 1.025, 0.0), 0.038 * g, 0.035 * g, elbow, wrist, 0.15),
		_ring(Vector3(x, 0.965, 0.0), 0.031 * g, 0.031 * g, elbow, wrist, 0.67),
	]
	_loft(st, parts, true, true)


func _hand(skin_st: SurfaceTool, side: float, scale_value: float) -> void:
	var elbow: int = B_ELBOW_L if side < 0.0 else B_ELBOW_R
	var wrist: int = B_WRIST_L if side < 0.0 else B_WRIST_R
	var x: float = _rest[wrist].x
	var s: float = scale_value
	var y: float = _rest[wrist].y
	var parts: Array[Ring] = [
		_ring(Vector3(x, y + 0.019, 0.0), 0.027 * s, 0.028 * s, elbow, wrist, 0.6),
		_ring(Vector3(x, y - 0.009, -0.001), 0.022 * s, 0.032 * s, wrist, wrist, 0.0),
		_ring(Vector3(x, y - 0.042 * s, -0.006 * s), 0.022 * s, 0.042 * s, wrist, wrist, 0.0),
		_ring(Vector3(x - side * 0.006 * s, y - 0.074 * s, -0.007 * s), 0.015 * s, 0.036 * s, wrist, wrist, 0.0),
	]
	_loft(skin_st, parts, true, true)
	var thumb: Array[Ring] = [
		_ring(Vector3(x - side * 0.01, y - 0.026 * s, -0.021 * s), 0.015 * s, 0.016 * s, wrist, wrist, 0.0),
		_ring(Vector3(x - side * 0.020, y - 0.054 * s, -0.041 * s), 0.013 * s, 0.014 * s, wrist, wrist, 0.0),
		_ring(Vector3(x - side * 0.027, y - 0.082 * s, -0.047 * s), 0.009 * s, 0.009 * s, wrist, wrist, 0.0),
		_ring(Vector3(x - side * 0.027, y - 0.089 * s, -0.043 * s), 0.004 * s, 0.005 * s, wrist, wrist, 0.0),
	]
	_loft(skin_st, thumb, true, true, 10)
	var finger_lengths: Array[float] = [0.069, 0.077, 0.068, 0.051]
	for index: int in finger_lengths.size():
		var z: float = (-0.031 + 0.017 * float(index)) * s
		var length: float = finger_lengths[index] * s
		var radius: float = (0.011 if index < 3 else 0.009) * s
		var knuckle: float = y - 0.064 * s
		var finger: Array[Ring] = [
			_ring(Vector3(x, knuckle, z), radius, radius * 0.88, wrist, wrist, 0.0),
			_ring(Vector3(x - side * 0.007 * s, knuckle - length * 0.50, z), radius * 0.87, radius * 0.75, wrist, wrist, 0.0),
			_ring(Vector3(x - side * 0.016 * s, knuckle - length * 0.88, z), radius * 0.69, radius * 0.58, wrist, wrist, 0.0),
			_ring(Vector3(x - side * 0.020 * s, knuckle - length, z), radius * 0.32, radius * 0.29, wrist, wrist, 0.0),
		]
		_loft(skin_st, finger, true, true, 8)


func _trouser_waist(st: SurfaceTool, girth: float) -> void:
	var g: float = girth * _bulk
	var pelvis: Array[Ring] = [
		_ring(Vector3(0.0, 0.824, 0.009), 0.153 * g, 0.091 * g, B_HIPS, B_HIPS, 0.0),
		_ring(Vector3(0.0, 0.864, 0.011), 0.172 * g, 0.105 * g, B_HIPS, B_HIPS, 0.0),
		_ring(Vector3(0.0, 0.911, 0.009), 0.167 * g, 0.113 * g, B_HIPS, B_HIPS, 0.0),
		_ring(Vector3(0.0, 0.967, 0.009), 0.151 * g, 0.103 * g, B_HIPS, B_HIPS, 0.0),
	]
	_loft(st, pelvis, true, true)


func _leg(st: SurfaceTool, side: float, girth: float, taper: float) -> void:
	var g: float = girth * _bulk
	var hip: int = B_HIP_L if side < 0.0 else B_HIP_R
	var knee: int = B_KNEE_L if side < 0.0 else B_KNEE_R
	var ankle: int = B_ANKLE_L if side < 0.0 else B_ANKLE_R
	var x: float = _rest[hip].x
	var parts: Array[Ring] = [
		_ring(Vector3(x * 0.77, 0.936, 0.005), 0.062 * g, 0.074 * g, B_HIPS, hip, 0.18),
		_ring(Vector3(x * 0.92, 0.869, 0.003), 0.082 * g, 0.087 * g, B_HIPS, hip, 0.72),
		_ring(Vector3(x, 0.74, 0.0), 0.076 * g, 0.074 * g, hip, hip, 0.0),
		_ring(Vector3(x, 0.58, -0.005), 0.06 * g, 0.06 * g, hip, knee, 0.15),
		_ring(Vector3(x, 0.5, -0.01), 0.056 * g, 0.058 * g, hip, knee, 0.5),
		_ring(Vector3(x, 0.43, 0.0), 0.058 * g, 0.06 * g, knee, knee, 0.0),
		_ring(Vector3(x, 0.33, 0.01), 0.06 * g * taper, 0.064 * g * taper, knee, knee, 0.0),
		_ring(Vector3(x, 0.2, 0.0), 0.045 * g * taper, 0.046 * g * taper, knee, knee, 0.0),
		_ring(Vector3(x, 0.1, 0.0), 0.04 * g * taper, 0.04 * g * taper, knee, ankle, 0.6),
	]
	_loft(st, parts, true, true)


func _foot(st: SurfaceTool, side: float, width: float, height: float) -> void:
	var ankle: int = B_ANKLE_L if side < 0.0 else B_ANKLE_R
	var x: float = _rest[ankle].x
	var profile: Array[Vector4] = [
		Vector4(0.063, 0.031, 0.044, 0.051), Vector4(0.038, 0.043, 0.054, 0.059),
		Vector4(-0.017, 0.046, 0.053, 0.055), Vector4(-0.074, 0.053, 0.038, 0.040),
		Vector4(-0.132, 0.052, 0.025, 0.030), Vector4(-0.165, 0.033, 0.016, 0.025),
		Vector4(-0.175, 0.017, 0.008, 0.024),
	]
	var rings: Array[Ring] = []
	for p: Vector4 in profile:
		var ring := _ring(Vector3(x, p.w * height / 0.05, p.x), p.y * width, p.z * height / 0.05, ankle, ankle, 0.0)
		ring.right = Vector3.RIGHT
		ring.depth = Vector3.UP
		rings.append(ring)
	_loft(st, rings, true, true)


func _shoe_soles(mesh: ArrayMesh, width: float, color: Color) -> void:
	var soles: SurfaceTool = _new_surface()
	for side: float in [-1.0, 1.0]:
		var ankle: int = B_ANKLE_L if side < 0.0 else B_ANKLE_R
		var x: float = _rest[ankle].x
		var profile: Array[Vector2] = [
			Vector2(0.064, 0.033), Vector2(0.031, 0.046), Vector2(-0.015, 0.049),
			Vector2(-0.075, 0.055), Vector2(-0.137, 0.054), Vector2(-0.171, 0.033),
			Vector2(-0.181, 0.014),
		]
		var rings: Array[Ring] = []
		for section: Vector2 in profile:
			var ring: Ring = _ring(Vector3(x, 0.010, section.x), section.y * width, 0.013, ankle, ankle, 0.0)
			ring.depth = Vector3.UP
			ring.jaw_shape = 0.70
			rings.append(ring)
		_loft(soles, rings, true, true)
	_commit(soles, mesh, MaterialLibrary.surface(color, 0.72, 0.0, 0.15))


## Split, tapered cloth panels overlap the torso and deform with the upper thighs.
func _coat_hem(st: SurfaceTool, girth: float, length: float) -> void:
	var back: float = PI * 0.5
	var front: float = PI * 1.5
	# The continuous waist band overlaps the jacket. Below it, each panel is
	# centered on its thigh and follows that thigh progressively down the hem.
	var band: Array[Ring] = [
		_ring(Vector3(0.0, 0.975, 0.011), 0.157 * girth, 0.114 * girth, B_HIPS, B_HIPS, 0.0),
		_ring(Vector3(0.0, 0.945, 0.012), 0.180 * girth, 0.132 * girth, B_HIPS, B_HIPS, 0.0),
		_ring(Vector3(0.0, 0.882, 0.010), 0.195 * girth, 0.133 * girth, B_HIPS, B_HIPS, 0.0),
	]
	_loft(st, band, false, false)
	for side: float in [-1.0, 1.0]:
		var hip: int = B_HIP_L if side < 0.0 else B_HIP_R
		var x: float = _rest[hip].x
		var panels: Array[Ring] = [
			_ring(Vector3(0.0, 0.901, 0.011), 0.190 * girth, 0.123 * girth, B_HIPS, B_HIPS, 0.0),
			_ring(Vector3(x * 0.46, 0.856, 0.009), 0.151 * girth, 0.137 * girth, B_HIPS, hip, 0.47),
			_ring(Vector3(x, 0.784, 0.003), 0.105 * girth, 0.128 * girth, B_HIPS, hip, 0.83),
			_ring(Vector3(x, 0.80 - length, 0.003), 0.104 * girth, 0.115 * girth, B_HIPS, hip, 0.95),
		]
		if side < 0.0:
			_loft_arc(st, panels, back - 0.88, front + 0.11, 22, Vector2(0.0, 0.30))
		else:
			_loft_arc(st, panels, front - 0.11, back + TAU + 0.88, 22, Vector2(-0.30, 0.0))


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
	_trouser_waist(pants, 1.1)
	_leg(pants, -1.0, 1.1, 0.95)
	_leg(pants, 1.0, 1.1, 0.95)
	_commit(pants, mesh, _suit_material(Color(0.1, 0.11, 0.14), Color(0.16, 0.17, 0.2), 2.0, 0.9))
	var skin := _new_surface()
	var skin_color: Color = Color(0.70, 0.52, 0.42)
	_neck_and_head(skin, 1.0)
	_commit(skin, mesh, MaterialLibrary.skin(skin_color))
	var gloves: SurfaceTool = _new_surface()
	_hand(gloves, -1.0, 1.05)
	_hand(gloves, 1.0, 1.05)
	_commit(gloves, mesh, MaterialLibrary.coated(Color(0.09, 0.12, 0.13), 0.04, 0.72))
	var shoes := _new_surface()
	_foot(shoes, -1.0, 1.05, 0.05)
	_foot(shoes, 1.0, 1.05, 0.05)
	_commit(shoes, mesh, MaterialLibrary.surface(Color(0.22, 0.26, 0.26), 0.58, 0.0, 0.25))
	_shoe_soles(mesh, 1.05, Color(0.58, 0.62, 0.58))
	_finish_body(mesh, true)

	_build_hood(Color(0.15, 0.18, 0.16))
	_face(Color(0.05, 0.035, 0.025), skin_color, -1)
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
	var strap: StandardMaterial3D = MaterialLibrary.fabric(Color(0.092, 0.12, 0.13))
	for side: float in [-1.0, 1.0]:
		var hip: int = B_HIP_L if side < 0.0 else B_HIP_R
		var wrist: int = B_WRIST_L if side < 0.0 else B_WRIST_R
		_gear(hip, "capsule", Vector3(_rest[hip].x + side * 0.072, 0.72, 0.0), Vector3(0.03, 0.12, 0.09), pocket)
		_gear(B_CHEST, "capsule", Vector3(side * 0.123, 1.401, -0.105), Vector3(0.030, 0.194, 0.031), strap, Vector3(-9.0, 0.0, -side * 14.0))
		_gear(wrist, "capsule", Vector3(_rest[wrist].x, 0.954, 0.0), Vector3(0.073, 0.034, 0.066), strap)
	_gear(B_CHEST, "box", Vector3(0.105, 1.387, -0.124), Vector3(0.037, 0.023, 0.009), pack_mat)


func _dress_hunter() -> void:
	var mesh := ArrayMesh.new()
	var suit := _new_surface()
	_torso(suit, 1.0, 1.05, 0.0)
	_arm(suit, -1.0, 1.0)
	_arm(suit, 1.0, 1.0)
	_trouser_waist(suit, 1.0)
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
	_shoe_soles(mesh, 1.17, Color(0.065, 0.073, 0.075))
	_finish_body(mesh, true)

	var plate := MaterialLibrary.coated(Color(0.3, 0.32, 0.35), 0.75, 0.28)
	var plate_dark := MaterialLibrary.coated(Color(0.1, 0.105, 0.115), 0.6, 0.35)
	var visor := _accent(4.0)
	var lamp := _accent(3.0)
	_gear(B_HEAD, "sphere", Vector3(0.0, 1.743, 0.006), Vector3(0.205, 0.257, 0.245), plate)
	_gear(B_HEAD, "capsule", Vector3(0.0, 1.668, -0.074), Vector3(0.086, 0.144, 0.115), plate_dark, Vector3(0.0, 0.0, 90.0))
	_build_visor(plate_dark, visor)
	for side: float in [-1.0, 1.0]:
		_gear(B_HEAD, "sphere", Vector3(side * 0.094, 1.732, 0.014), Vector3(0.032, 0.070, 0.071), plate_dark)
		_gear(B_HEAD, "box", Vector3(side * 0.111, 1.727, 0.018), Vector3(0.004, 0.019, 0.016), lamp)
	# Torso armour: chest + back plates, collar, abdominal bands, belt.
	_gear(B_CHEST, "capsule", Vector3(0.0, 1.37, -0.085), Vector3(0.38, 0.32, 0.12), plate)
	_gear(B_CHEST, "capsule", Vector3(0.0, 1.37, 0.085), Vector3(0.36, 0.32, 0.12), plate)
	_gear(B_CHEST, "capsule", Vector3(0.0, 1.52, 0.0), Vector3(0.089, 0.23, 0.19), plate_dark, Vector3(0.0, 0.0, 90.0))
	_gear(B_CHEST, "box", Vector3(0.09, 1.42, -0.15), Vector3(0.05, 0.025, 0.01), lamp)
	_gear(B_CHEST, "box", Vector3(0.0, 1.3, -0.148), Vector3(0.26, 0.008, 0.005), lamp)
	_gear(B_CHEST, "box", Vector3(0.0, 1.38, 0.21), Vector3(0.22, 0.26, 0.1), plate_dark)
	_gear(B_CHEST, "cylinder", Vector3(0.08, 1.7, 0.22), Vector3(0.012, 0.4, 0.012), plate_dark)
	_gear(B_CHEST, "sphere", Vector3(0.08, 1.9, 0.22), Vector3(0.025, 0.025, 0.025), lamp)
	for y: float in [1.2, 1.12]:
		_gear(B_SPINE, "capsule", Vector3(0.0, y, -0.060), Vector3(0.053, 0.29, 0.17), plate_dark, Vector3(0.0, 0.0, 90.0))
	_gear(B_HIPS, "capsule", Vector3(0.0, 0.97, 0.0), Vector3(0.080, 0.36, 0.277), plate_dark, Vector3(0.0, 0.0, 90.0))
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
		_gear(ankle, "capsule", Vector3(x, 0.078, -0.034), Vector3(0.112, 0.228, 0.072), plate_dark, Vector3(90.0, 0.0, 0.0))


func _build_visor(frame: Material, optic: Material) -> void:
	var mesh: ArrayMesh = ArrayMesh.new()
	var surround: SurfaceTool = _new_surface()
	var band: Array[Ring] = [
		_ring(Vector3(0.0, 1.707, 0.002), 0.107, 0.139, B_HEAD, B_HEAD, 0.0),
		_ring(Vector3(0.0, 1.724, 0.001), 0.120, 0.148, B_HEAD, B_HEAD, 0.0),
		_ring(Vector3(0.0, 1.756, 0.002), 0.121, 0.150, B_HEAD, B_HEAD, 0.0),
		_ring(Vector3(0.0, 1.773, 0.002), 0.109, 0.135, B_HEAD, B_HEAD, 0.0),
	]
	_loft_arc(surround, band, PI + 0.29, TAU - 0.29, 24)
	_commit(surround, mesh, frame)
	var display: SurfaceTool = _new_surface()
	var strip: Array[Ring] = [
		_ring(Vector3(0.0, 1.736, 0.001), 0.122, 0.152, B_HEAD, B_HEAD, 0.0),
		_ring(Vector3(0.0, 1.748, 0.002), 0.122, 0.153, B_HEAD, B_HEAD, 0.0),
	]
	_loft_arc(display, strip, PI + 0.39, TAU - 0.39, 24)
	var visor_mesh: MeshInstance3D
	_commit(display, mesh, optic)
	visor_mesh = _finish_body(mesh, false)
	visor_mesh.name = "Visor"


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
	_torso(upper, 1.05 if coat else 0.98, 0.98, 0.0, coat)
	_arm(upper, -1.0, 1.06 if coat else 0.98)
	_arm(upper, 1.0, 1.06 if coat else 0.98)
	_commit(upper, mesh, _suit_material(top, top.darkened(0.25), 2.0, 0.85))
	if coat:
		var hem: SurfaceTool = _new_surface()
		_coat_hem(hem, 1.06, 0.13)
		_commit(hem, mesh, _suit_material(top.darkened(0.06), top.darkened(0.25), 2.0, 0.86))
	var legs := _new_surface()
	_trouser_waist(legs, 1.04)
	_leg(legs, -1.0, 1.04, 0.95)
	_leg(legs, 1.0, 1.04, 0.95)
	_commit(legs, mesh, _suit_material(bottom, bottom.darkened(0.2), 2.0, 0.9))
	var skin := _new_surface()
	_neck_and_head(skin, 1.0)
	_hand(skin, -1.0, 1.0)
	_hand(skin, 1.0, 1.0)
	_commit(skin, mesh, MaterialLibrary.skin(skin_color))
	var shoes: SurfaceTool = _new_surface()
	_foot(shoes, -1.0, 1.0, 0.045)
	_foot(shoes, 1.0, 1.0, 0.045)
	var dark_shoes: bool = rng.randf() < 0.6
	_commit(shoes, mesh, MaterialLibrary.surface(Color(0.08, 0.07, 0.06) if dark_shoes else Color(0.56, 0.57, 0.54), 0.55, 0.0, 0.3))
	_shoe_soles(mesh, 1.0, Color(0.16, 0.14, 0.115) if dark_shoes else Color(0.75, 0.74, 0.68))
	_finish_body(mesh, false)
	_face(hairs[rng.randi_range(0, hairs.size() - 1)], skin_color, posmod(outfit_seed, 3))
	if coat:
		_build_lapels(top.darkened(0.12))
	if rng.randf() < 0.35:
		_gear(B_CHEST, "capsule", Vector3(0.0, 1.3, 0.14), Vector3(0.22, 0.28, 0.1), MaterialLibrary.fabric(Color(0.1, 0.1, 0.1)))


func _dress_technician(rng: RandomNumberGenerator) -> void:
	var mesh := ArrayMesh.new()
	var coat := _new_surface()
	_torso(coat, 1.05, 1.0, 0.0, true)
	_arm(coat, -1.0, 1.08)
	_arm(coat, 1.0, 1.08)
	_commit(coat, mesh, _suit_material(Color(0.72, 0.76, 0.75), Color(0.64, 0.68, 0.68), 2.0, 0.8))
	var hem: SurfaceTool = _new_surface()
	_coat_hem(hem, 1.07, 0.19)
	_commit(hem, mesh, _suit_material(Color(0.70, 0.74, 0.73), Color(0.65, 0.68, 0.68), 2.0, 0.8))
	var legs := _new_surface()
	_trouser_waist(legs, 1.03)
	_leg(legs, -1.0, 1.03, 0.95)
	_leg(legs, 1.0, 1.03, 0.95)
	_commit(legs, mesh, _suit_material(Color(0.22, 0.23, 0.26), Color(0.18, 0.19, 0.21), 2.0, 0.9))
	var skin := _new_surface()
	_neck_and_head(skin, 1.0)
	_hand(skin, -1.0, 1.0)
	_hand(skin, 1.0, 1.0)
	var skins: Array[Color] = [Color(0.85, 0.66, 0.54), Color(0.7, 0.52, 0.42), Color(0.45, 0.32, 0.23)]
	var skin_color: Color = skins[rng.randi_range(0, skins.size() - 1)]
	_commit(skin, mesh, MaterialLibrary.skin(skin_color))
	var shoes := _new_surface()
	_foot(shoes, -1.0, 1.0, 0.045)
	_foot(shoes, 1.0, 1.0, 0.045)
	_commit(shoes, mesh, MaterialLibrary.surface(Color(0.11, 0.12, 0.13), 0.47, 0.0, 0.2))
	_shoe_soles(mesh, 1.0, Color(0.06, 0.072, 0.08))
	_finish_body(mesh, false)
	_face(Color(0.1, 0.08, 0.06) if rng.randf() < 0.5 else Color(0.4, 0.35, 0.3), skin_color, posmod(outfit_seed + 1, 3))
	_build_lapels(Color(0.52, 0.59, 0.59))
	var button: StandardMaterial3D = MaterialLibrary.coated(Color(0.47, 0.55, 0.56), 0.0, 0.73)
	_gear(B_CHEST, "sphere", Vector3(0.007, 1.309, -0.127), Vector3(0.012, 0.012, 0.006), button)
	_gear(B_SPINE, "sphere", Vector3(0.007, 1.171, -0.115), Vector3(0.012, 0.012, 0.006), button)
	_gear(B_HIPS, "sphere", Vector3(0.007, 1.030, -0.114), Vector3(0.012, 0.012, 0.006), button)
	# Badge and eyeglass frames sit above their mounting surfaces.
	_gear(B_CHEST, "box", Vector3(0.101, 1.355, -0.114), Vector3(0.052, 0.069, 0.009), MaterialLibrary.surface(Color(0.22, 0.29, 0.30), 0.57, 0.0, 0.0))
	_gear(B_CHEST, "box", Vector3(0.101, 1.371, -0.120), Vector3(0.037, 0.009, 0.002), _accent(1.0))
	var frame: StandardMaterial3D = MaterialLibrary.coated(Color(0.046, 0.058, 0.063), 0.26, 0.45)
	for direction: float in [-1.0, 1.0]:
		var x: float = direction * 0.035
		for y: float in [1.731, 1.756]:
			_gear(B_HEAD, "box", Vector3(x, y, -0.094), Vector3(0.048, 0.003, 0.004), frame, Vector3(0.0, -direction * 14.0, 0.0))
		for edge: float in [-1.0, 1.0]:
			_gear(B_HEAD, "box", Vector3(x + edge * 0.023, 1.743, -0.094 + edge * direction * 0.005), Vector3(0.003, 0.024, 0.004), frame)
		_gear(B_HEAD, "box", Vector3(direction * 0.069, 1.75, -0.047), Vector3(0.004, 0.004, 0.082), frame, Vector3(0.0, -direction * 12.0, 0.0))
	_gear(B_HEAD, "box", Vector3(0.0, 1.751, -0.103), Vector3(0.023, 0.004, 0.004), frame)


func _build_lapels(color: Color) -> void:
	var cloth: StandardMaterial3D = MaterialLibrary.fabric(color)
	for side: float in [-1.0, 1.0]:
		_gear(B_CHEST, "capsule", Vector3(side * 0.048, 1.460, -0.120), Vector3(0.034, 0.140, 0.022), cloth, Vector3(14.0, 0.0, side * -24.0))


## Skinned hood: an open shell around the head (face left open) draping into a collar.
func _build_hood(color: Color) -> void:
	var mesh := ArrayMesh.new()
	var st := _new_surface()
	var front: float = PI * 1.5
	var opening: float = 0.95
	var profile: Array[Vector4] = [
		Vector4(1.53, 0.135, 0.12, 0.03), Vector4(1.59, 0.1, 0.105, 0.025), Vector4(1.66, 0.098, 0.115, 0.02),
		Vector4(1.73, 0.104, 0.122, 0.018), Vector4(1.8, 0.098, 0.115, 0.02), Vector4(1.855, 0.075, 0.09, 0.025),
		Vector4(1.890, 0.047, 0.056, 0.023), Vector4(1.908, 0.005, 0.008, 0.023),
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


## Detail pieces follow the underlay's complexion and curved facial landmarks.
func _face(hair_color: Color, skin_color: Color, haircut: int) -> void:
	var eye: StandardMaterial3D = MaterialLibrary.coated(Color(0.078, 0.062, 0.054), 0.0, 0.33)
	var white: StandardMaterial3D = MaterialLibrary.surface(Color(0.54, 0.51, 0.46), 0.42, 0.0, 0.0)
	var hair: StandardMaterial3D = MaterialLibrary.surface(hair_color, 0.76, 0.0, 0.34, 9.0)
	var ear: StandardMaterial3D = MaterialLibrary.skin(skin_color)
	var ear_inner: StandardMaterial3D = MaterialLibrary.skin(skin_color.lerp(Color(0.25, 0.075, 0.055), 0.26))
	for side: float in [-1.0, 1.0]:
		var x: float = side * 0.036
		_gear(B_HEAD, "sphere", Vector3(x, 1.748, -0.076), Vector3(0.028, 0.011, 0.015), white, Vector3(0.0, -side * 18.0, 0.0))
		_gear(B_HEAD, "sphere", Vector3(x - side * 0.003, 1.748, -0.084), Vector3(0.010, 0.010, 0.005), eye)
		_gear(B_HEAD, "sphere", Vector3(x, 1.766, -0.082), Vector3(0.033, 0.008, 0.010), hair, Vector3(0.0, -side * 22.0, side * -8.0))
		_gear(B_HEAD, "sphere", Vector3(side * 0.078, 1.726, 0.006), Vector3(0.026, 0.047, 0.034), ear, Vector3(-10.0, 0.0, side * -10.0))
		_gear(B_HEAD, "sphere", Vector3(side * 0.090, 1.726, -0.001), Vector3(0.005, 0.023, 0.014), ear_inner)
	var lip: Color = skin_color.lerp(Color(0.24, 0.075, 0.065), 0.34)
	_gear(B_HEAD, "sphere", Vector3(0.0, 1.670, -0.101), Vector3(0.038, 0.006, 0.005), MaterialLibrary.skin(lip))
	if haircut >= 0:
		_build_hair(hair, haircut)


func _build_hair(material: Material, haircut: int) -> void:
	var mesh: ArrayMesh = ArrayMesh.new()
	var hair: SurfaceTool = _new_surface()
	var crown: float = [1.879, 1.897, 1.887][haircut]
	var first: Ring = _ring(Vector3(0.0, 1.783, 0.008), 0.086, 0.096, B_HEAD, B_HEAD, 0.0)
	first.hairline_drop = 0.068
	var second: Ring = _ring(Vector3(0.0, 1.815, 0.009), 0.079, 0.094, B_HEAD, B_HEAD, 0.0)
	second.hairline_drop = 0.033
	var profile: Array[Ring] = [
		first, second,
		_ring(Vector3(0.006 if haircut == 1 else 0.0, 1.851, 0.010), 0.066, 0.080, B_HEAD, B_HEAD, 0.0),
		_ring(Vector3(0.009 if haircut == 1 else 0.0, crown - 0.012, 0.014), 0.045, 0.053, B_HEAD, B_HEAD, 0.0),
		_ring(Vector3(0.011 if haircut == 1 else 0.0, crown, 0.017), 0.005, 0.006, B_HEAD, B_HEAD, 0.0),
	]
	_loft(hair, profile, false, true, 26)
	_commit(hair, mesh, material)
	var hair_mesh: MeshInstance3D = _finish_body(mesh, false)
	hair_mesh.name = "Hair"
