class_name HumanoidRig
extends Node3D
## Procedurally modelled and procedurally animated humanoid.
##
## The body is a hierarchy of joint nodes (hips > spine > chest > neck/shoulders, hips > legs)
## dressed with primitive meshes and procedural materials. `animate()` is called every physics
## frame by the owning controller and drives a gait cycle (idle / walk / run), jump, fall,
## landing squash, dash lean and a hunter "scan" pose, all blended smoothly.
## The rig faces -Z; the owner rotates it to face the travel direction.

enum Style { RUNNER, HUNTER }

@export var style: Style = Style.RUNNER
@export var run_speed: float = 8.0
@export var joint_smoothing: float = 16.0

## Extra pose inputs set by the owner before calling animate().
var dashing: bool = false
var scanning: bool = false
var crouch_amount: float = 0.0

var _accent_materials: Array[StandardMaterial3D] = []
var _carry_item: Node3D

var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _neck: Node3D
var _head: Node3D
var _shoulder_l: Node3D
var _shoulder_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _hip_l: Node3D
var _hip_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _ankle_l: Node3D
var _ankle_r: Node3D

var _phase: float = 0.0
var _time: float = 0.0
var _air_blend: float = 0.0
var _land_squash: float = 0.0
var _was_on_floor: bool = true
var _hip_height: float = 0.96


func _ready() -> void:
	_build_skeleton()
	if style == Style.RUNNER:
		_dress_runner()
	else:
		_dress_hunter()


## Updates the pose. `local_velocity` is the velocity expressed in the rig's facing frame
## (forward = -Z) so leaning works for strafing too.
func animate(local_velocity: Vector3, on_floor: bool, delta: float) -> void:
	_time += delta
	var planar: Vector2 = Vector2(local_velocity.x, local_velocity.z)
	var speed: float = planar.length()
	var move: float = clampf(speed / 1.6, 0.0, 1.0)
	var run: float = clampf((speed - 2.5) / (run_speed - 2.5), 0.0, 1.0)
	var stride: float = lerpf(1.25, 2.7, run)
	_phase = fmod(_phase + speed / stride * TAU * delta, TAU)

	_air_blend = move_toward(_air_blend, 0.0 if on_floor else 1.0, delta * 7.0)
	if on_floor and not _was_on_floor:
		_land_squash = clampf(-local_velocity.y * 0.03, 0.08, 0.3)
	_was_on_floor = on_floor
	_land_squash = move_toward(_land_squash, 0.0, delta * 1.2)

	var s: float = sin(_phase)
	var c: float = cos(_phase)
	var thigh_amp: float = lerpf(0.42, 0.85, run) * move
	var knee_amp: float = lerpf(0.55, 1.5, run) * move
	var arm_amp: float = lerpf(0.35, 0.95, run) * move
	var breathe: float = sin(_time * 1.9) * 0.012 * (1.0 - move)

	# Ground pose.
	var hip_l_x: float = s * thigh_amp + run * 0.12
	var hip_r_x: float = -s * thigh_amp + run * 0.12
	var knee_l_x: float = -(0.08 + maxf(0.0, c) * knee_amp)
	var knee_r_x: float = -(0.08 + maxf(0.0, -c) * knee_amp)
	var shoulder_l_x: float = -s * arm_amp
	var shoulder_r_x: float = s * arm_amp
	var elbow_x: float = lerpf(0.25, 1.35, run) * move + 0.18
	var spine_x: float = -lerpf(0.04, 0.24, run) * move
	var chest_y: float = s * 0.16 * move
	var hips_y_rot: float = -s * 0.1 * move
	var bob: float = absf(s) * lerpf(0.025, 0.07, run) * move
	var hips_y: float = _hip_height - lerpf(0.0, 0.05, run) * move + bob
	var arm_out: float = 0.08

	# Airborne pose (rising: tuck, falling: reach down / arms out).
	var rising: float = clampf(local_velocity.y / 6.0, 0.0, 1.0)
	var air_hip_l: float = lerpf(0.25, 0.9, rising)
	var air_hip_r: float = lerpf(-0.1, 0.2, rising)
	var air_knee_l: float = -lerpf(0.5, 1.6, rising)
	var air_knee_r: float = -lerpf(0.3, 0.9, rising)
	var air_shoulder: float = lerpf(0.35, -0.55, rising)
	hip_l_x = lerpf(hip_l_x, air_hip_l, _air_blend)
	hip_r_x = lerpf(hip_r_x, air_hip_r, _air_blend)
	knee_l_x = lerpf(knee_l_x, air_knee_l, _air_blend)
	knee_r_x = lerpf(knee_r_x, air_knee_r, _air_blend)
	shoulder_l_x = lerpf(shoulder_l_x, air_shoulder, _air_blend)
	shoulder_r_x = lerpf(shoulder_r_x, air_shoulder * 0.8, _air_blend)
	elbow_x = lerpf(elbow_x, lerpf(0.5, 1.1, rising), _air_blend)
	arm_out = lerpf(arm_out, lerpf(0.85, 0.3, rising), _air_blend)
	spine_x = lerpf(spine_x, lerpf(0.05, -0.15, rising), _air_blend)
	hips_y = lerpf(hips_y, _hip_height, _air_blend)

	# Dash: aggressive forward lean, arms swept back, legs split.
	if dashing:
		spine_x = -0.75
		shoulder_l_x = -1.1
		shoulder_r_x = -1.1
		elbow_x = 0.2
		arm_out = 0.35
		hip_l_x = 0.9
		hip_r_x = -0.6
		knee_l_x = -0.6
		knee_r_x = -0.3

	# Hunter scan: right arm raised holding the scanner, head sweeps.
	var head_y: float = sin(_time * 0.7) * 0.15 * (1.0 - move)
	if scanning:
		shoulder_r_x = 1.45
		elbow_x = 0.15
		head_y = sin(_time * 1.6) * 0.9

	var squash: float = _land_squash + crouch_amount * 0.35
	hips_y -= squash * 0.5
	knee_l_x -= squash * 1.6
	knee_r_x -= squash * 1.6
	hip_l_x += squash * 0.8
	hip_r_x += squash * 0.8
	spine_x -= squash * 0.5

	# Lateral lean when strafing.
	var lean_z: float = clampf(-local_velocity.x * 0.02, -0.2, 0.2)

	var k: float = clampf(joint_smoothing * delta, 0.0, 1.0)
	_hips.position.y = lerpf(_hips.position.y, hips_y, k)
	_hips.rotation.y = lerp_angle(_hips.rotation.y, hips_y_rot, k)
	_hips.rotation.z = lerp_angle(_hips.rotation.z, lean_z, k)
	_spine.rotation.x = lerp_angle(_spine.rotation.x, spine_x, k)
	_chest.rotation.y = lerp_angle(_chest.rotation.y, chest_y, k)
	_chest.scale = Vector3(1.0, 1.0 + breathe, 1.0 + breathe)
	_head.rotation.x = lerp_angle(_head.rotation.x, -spine_x * 0.6, k)
	_head.rotation.y = lerp_angle(_head.rotation.y, head_y, k)
	_hip_l.rotation.x = lerp_angle(_hip_l.rotation.x, hip_l_x, k)
	_hip_r.rotation.x = lerp_angle(_hip_r.rotation.x, hip_r_x, k)
	_knee_l.rotation.x = lerp_angle(_knee_l.rotation.x, knee_l_x, k)
	_knee_r.rotation.x = lerp_angle(_knee_r.rotation.x, knee_r_x, k)
	_ankle_l.rotation.x = lerp_angle(_ankle_l.rotation.x, -(hip_l_x + knee_l_x) * 0.5, k)
	_ankle_r.rotation.x = lerp_angle(_ankle_r.rotation.x, -(hip_r_x + knee_r_x) * 0.5, k)
	_shoulder_l.rotation.x = lerp_angle(_shoulder_l.rotation.x, shoulder_l_x, k)
	_shoulder_r.rotation.x = lerp_angle(_shoulder_r.rotation.x, shoulder_r_x, k)
	_shoulder_l.rotation.z = lerp_angle(_shoulder_l.rotation.z, -arm_out, k)
	_shoulder_r.rotation.z = lerp_angle(_shoulder_r.rotation.z, arm_out, k)
	_elbow_l.rotation.x = lerp_angle(_elbow_l.rotation.x, elbow_x, k)
	_elbow_r.rotation.x = lerp_angle(_elbow_r.rotation.x, elbow_x if not scanning else 0.15, k)


## Colour/intensity of the emissive accents (Codex veins / hunter visor & lamps).
func set_accent(color: Color, energy: float) -> void:
	for material: StandardMaterial3D in _accent_materials:
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = energy


func set_carry_visible(visible_state: bool) -> void:
	if _carry_item != null:
		_carry_item.visible = visible_state


func get_chest() -> Node3D:
	return _chest


func get_right_hand() -> Node3D:
	return _elbow_r


# --- Skeleton -------------------------------------------------------------------------

func _build_skeleton() -> void:
	_hips = _joint(self, Vector3(0.0, _hip_height, 0.0))
	_spine = _joint(_hips, Vector3(0.0, 0.08, 0.0))
	_chest = _joint(_spine, Vector3(0.0, 0.24, 0.0))
	_neck = _joint(_chest, Vector3(0.0, 0.3, 0.0))
	_head = _joint(_neck, Vector3(0.0, 0.08, 0.0))
	_shoulder_l = _joint(_chest, Vector3(-0.21, 0.24, 0.0))
	_shoulder_r = _joint(_chest, Vector3(0.21, 0.24, 0.0))
	_elbow_l = _joint(_shoulder_l, Vector3(0.0, -0.29, 0.0))
	_elbow_r = _joint(_shoulder_r, Vector3(0.0, -0.29, 0.0))
	_hip_l = _joint(_hips, Vector3(-0.1, -0.04, 0.0))
	_hip_r = _joint(_hips, Vector3(0.1, -0.04, 0.0))
	_knee_l = _joint(_hip_l, Vector3(0.0, -0.43, 0.0))
	_knee_r = _joint(_hip_r, Vector3(0.0, -0.43, 0.0))
	_ankle_l = _joint(_knee_l, Vector3(0.0, -0.42, 0.0))
	_ankle_r = _joint(_knee_r, Vector3(0.0, -0.42, 0.0))


func _joint(parent: Node3D, offset: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.position = offset
	parent.add_child(joint)
	return joint


func _accent(energy: float) -> StandardMaterial3D:
	var material := MaterialLibrary.emissive(Color(0.2, 0.9, 1.0), energy, false)
	_accent_materials.append(material)
	return material


# --- Runner outfit: hooded techwear jacket, cargo trousers, trainers, Codex veins ------

func _dress_runner() -> void:
	var jacket := MaterialLibrary.fabric(Color(0.2, 0.23, 0.2))
	var jacket_panel := MaterialLibrary.fabric(Color(0.42, 0.4, 0.34))
	var trousers := MaterialLibrary.fabric(Color(0.13, 0.14, 0.17))
	var hair := MaterialLibrary.surface(Color(0.05, 0.035, 0.025), 0.7, 0.0, 0.8, 8.0)
	var skin := MaterialLibrary.skin()
	var shoe := MaterialLibrary.surface(Color(0.75, 0.75, 0.73), 0.6, 0.0, 0.4)
	var sole := MaterialLibrary.surface(Color(0.08, 0.08, 0.08), 0.9, 0.0, 0.0)
	var strap := MaterialLibrary.surface(Color(0.05, 0.05, 0.06), 0.5, 0.2, 0.3)
	var vein := _accent(1.5)

	# Pelvis + torso.
	GeometryKit.capsule(_hips, Vector3(0.0, 0.0, 0.0), 0.15, 0.36, trousers, Vector3(1.15, 0.6, 0.8))
	GeometryKit.capsule(_spine, Vector3(0.0, 0.1, 0.0), 0.15, 0.4, jacket, Vector3(1.05, 1.0, 0.82))
	GeometryKit.capsule(_chest, Vector3(0.0, 0.12, 0.0), 0.19, 0.44, jacket, Vector3(1.12, 1.0, 0.76))
	GeometryKit.mesh_box(_chest, Vector3(0.0, 0.1, -0.135), Vector3(0.16, 0.3, 0.02), jacket_panel)
	GeometryKit.mesh_box(_chest, Vector3(0.0, 0.1, -0.148), Vector3(0.012, 0.32, 0.012), vein)
	GeometryKit.tilted_box(_chest, Vector3(-0.11, 0.06, -0.12), Vector3(0.012, 0.2, 0.012), Vector3(0.0, 0.0, 25.0), vein)
	GeometryKit.tilted_box(_chest, Vector3(0.11, 0.06, -0.12), Vector3(0.012, 0.2, 0.012), Vector3(0.0, 0.0, -25.0), vein)

	# Codex core backpack (also the carried Device slot).
	var pack := Node3D.new()
	pack.position = Vector3(0.0, 0.12, 0.16)
	_chest.add_child(pack)
	GeometryKit.mesh_box(pack, Vector3.ZERO, Vector3(0.26, 0.32, 0.12), MaterialLibrary.coated(Color(0.12, 0.13, 0.15), 0.4, 0.45))
	GeometryKit.mesh_box(pack, Vector3(0.0, 0.0, 0.062), Vector3(0.18, 0.02, 0.004), vein)
	GeometryKit.mesh_box(pack, Vector3(0.0, 0.07, 0.062), Vector3(0.12, 0.012, 0.004), vein)
	for side: float in [-0.12, 0.12]:
		GeometryKit.mesh_box(_chest, Vector3(side, 0.18, 0.0), Vector3(0.035, 0.03, 0.36), strap)
	_carry_item = Node3D.new()
	_carry_item.position = Vector3(0.0, 0.0, 0.11)
	pack.add_child(_carry_item)
	GeometryKit.mesh_box(_carry_item, Vector3.ZERO, Vector3(0.2, 0.2, 0.1), MaterialLibrary.coated(Color(0.75, 0.6, 0.2), 0.9, 0.25))
	GeometryKit.mesh_box(_carry_item, Vector3(0.0, 0.0, 0.052), Vector3(0.12, 0.12, 0.004), MaterialLibrary.emissive(Color(1.0, 0.75, 0.25), 4.0))
	_carry_item.visible = false

	# Head + hood.
	GeometryKit.cylinder(_neck, Vector3(0.0, 0.02, 0.0), 0.05, 0.06, 0.1, skin)
	GeometryKit.sphere(_head, Vector3(0.0, 0.1, -0.01), 0.1, skin, Vector3(0.9, 1.15, 1.0))
	GeometryKit.sphere(_head, Vector3(0.0, 0.035, -0.05), 0.06, skin, Vector3(1.1, 0.7, 0.9))
	GeometryKit.sphere(_head, Vector3(0.0, 0.15, 0.005), 0.098, hair, Vector3(0.95, 0.8, 1.02))
	GeometryKit.mesh_box(_head, Vector3(0.0, 0.115, -0.1), Vector3(0.16, 0.035, 0.02), MaterialLibrary.glass(Color(0.02, 0.05, 0.06)))
	GeometryKit.mesh_box(_head, Vector3(0.0, 0.115, -0.111), Vector3(0.14, 0.006, 0.004), vein)
	GeometryKit.sphere(_neck, Vector3(0.0, 0.03, 0.09), 0.12, jacket, Vector3(1.25, 0.75, 0.7))
	GeometryKit.capsule(_neck, Vector3(0.0, -0.01, 0.0), 0.1, 0.2, jacket, Vector3(1.25, 0.5, 1.1))

	# Arms.
	for shoulder: Node3D in [_shoulder_l, _shoulder_r]:
		GeometryKit.sphere(shoulder, Vector3.ZERO, 0.075, jacket)
		GeometryKit.cylinder(shoulder, Vector3(0.0, -0.145, 0.0), 0.06, 0.05, 0.29, jacket)
	for elbow: Node3D in [_elbow_l, _elbow_r]:
		GeometryKit.sphere(elbow, Vector3.ZERO, 0.05, jacket)
		GeometryKit.cylinder(elbow, Vector3(0.0, -0.13, 0.0), 0.048, 0.04, 0.26, jacket)
		GeometryKit.mesh_box(elbow, Vector3(0.0, -0.15, -0.045), Vector3(0.012, 0.18, 0.008), vein)
		GeometryKit.cylinder(elbow, Vector3(0.0, -0.25, 0.0), 0.042, 0.042, 0.04, strap)
		GeometryKit.sphere(elbow, Vector3(0.0, -0.31, 0.0), 0.045, skin, Vector3(0.8, 1.15, 0.6))

	# Legs.
	for hip: Node3D in [_hip_l, _hip_r]:
		GeometryKit.cylinder(hip, Vector3(0.0, -0.21, 0.0), 0.085, 0.064, 0.44, trousers)
		GeometryKit.mesh_box(hip, Vector3(0.0, -0.25, 0.0), Vector3(0.15, 0.12, 0.13), trousers)
	for knee: Node3D in [_knee_l, _knee_r]:
		GeometryKit.sphere(knee, Vector3.ZERO, 0.066, trousers)
		GeometryKit.cylinder(knee, Vector3(0.0, -0.2, 0.0), 0.06, 0.048, 0.4, trousers)
	for ankle: Node3D in [_ankle_l, _ankle_r]:
		GeometryKit.mesh_box(ankle, Vector3(0.0, -0.035, -0.05), Vector3(0.1, 0.07, 0.25), shoe)
		GeometryKit.mesh_box(ankle, Vector3(0.0, -0.068, -0.05), Vector3(0.105, 0.02, 0.26), sole)


# --- Hunter outfit: armoured enforcer with helmet visor, pauldrons, chest lamp ----------

func _dress_hunter() -> void:
	var armour := MaterialLibrary.coated(Color(0.34, 0.36, 0.38), 0.7, 0.3)
	var armour_dark := MaterialLibrary.coated(Color(0.1, 0.105, 0.115), 0.55, 0.38)
	var suit := MaterialLibrary.fabric(Color(0.08, 0.085, 0.09))
	var rubber := MaterialLibrary.surface(Color(0.04, 0.04, 0.045), 0.85, 0.0, 0.5)
	var visor := _accent(4.0)
	var lamp := _accent(3.0)

	GeometryKit.capsule(_hips, Vector3.ZERO, 0.16, 0.38, suit, Vector3(1.15, 0.6, 0.85))
	GeometryKit.mesh_box(_hips, Vector3(0.0, 0.0, -0.12), Vector3(0.24, 0.16, 0.04), armour_dark)
	GeometryKit.capsule(_spine, Vector3(0.0, 0.1, 0.0), 0.16, 0.4, suit, Vector3(1.05, 1.0, 0.85))
	GeometryKit.capsule(_chest, Vector3(0.0, 0.12, 0.0), 0.2, 0.46, suit, Vector3(1.15, 1.0, 0.8))
	GeometryKit.mesh_box(_chest, Vector3(0.0, 0.13, -0.15), Vector3(0.36, 0.34, 0.06), armour)
	GeometryKit.mesh_box(_chest, Vector3(0.0, 0.13, 0.15), Vector3(0.34, 0.36, 0.06), armour)
	GeometryKit.mesh_box(_chest, Vector3(0.0, -0.06, -0.14), Vector3(0.3, 0.08, 0.05), armour_dark)
	GeometryKit.mesh_box(_chest, Vector3(0.09, 0.2, -0.185), Vector3(0.05, 0.03, 0.01), lamp)
	GeometryKit.mesh_box(_chest, Vector3(0.0, 0.29, -0.182), Vector3(0.3, 0.012, 0.006), lamp)
	GeometryKit.mesh_box(_chest, Vector3(0.0, 0.16, 0.22), Vector3(0.24, 0.3, 0.12), armour_dark)
	GeometryKit.cylinder(_chest, Vector3(0.09, 0.45, 0.24), 0.006, 0.008, 0.4, armour_dark)
	GeometryKit.sphere(_chest, Vector3(0.09, 0.66, 0.24), 0.014, lamp)

	GeometryKit.cylinder(_neck, Vector3(0.0, 0.02, 0.0), 0.06, 0.07, 0.1, suit)
	GeometryKit.sphere(_head, Vector3(0.0, 0.12, 0.0), 0.14, armour, Vector3(0.95, 1.05, 1.08))
	GeometryKit.mesh_box(_head, Vector3(0.0, 0.12, -0.13), Vector3(0.2, 0.05, 0.05), armour_dark)
	GeometryKit.mesh_box(_head, Vector3(0.0, 0.122, -0.157), Vector3(0.17, 0.022, 0.004), visor)
	GeometryKit.mesh_box(_head, Vector3(0.0, 0.035, -0.11), Vector3(0.12, 0.07, 0.06), armour_dark)
	GeometryKit.mesh_box(_head, Vector3(0.0, 0.23, 0.0), Vector3(0.03, 0.05, 0.22), armour_dark)

	for shoulder: Node3D in [_shoulder_l, _shoulder_r]:
		var side: float = -1.0 if shoulder == _shoulder_l else 1.0
		GeometryKit.sphere(shoulder, Vector3(side * 0.02, 0.03, 0.0), 0.11, armour, Vector3(1.1, 0.75, 1.1))
		GeometryKit.cylinder(shoulder, Vector3(0.0, -0.145, 0.0), 0.065, 0.055, 0.29, suit)
		GeometryKit.mesh_box(shoulder, Vector3(side * 0.03, -0.14, 0.0), Vector3(0.05, 0.18, 0.1), armour_dark)
	for elbow: Node3D in [_elbow_l, _elbow_r]:
		GeometryKit.sphere(elbow, Vector3.ZERO, 0.058, armour_dark)
		GeometryKit.cylinder(elbow, Vector3(0.0, -0.13, 0.0), 0.06, 0.05, 0.26, armour)
		GeometryKit.sphere(elbow, Vector3(0.0, -0.3, 0.0), 0.055, rubber, Vector3(0.85, 1.1, 0.7))
	var scanner := GeometryKit.mesh_box(_elbow_r, Vector3(0.0, -0.33, -0.06), Vector3(0.06, 0.05, 0.16), armour_dark)
	GeometryKit.mesh_box(scanner, Vector3(0.0, 0.0, -0.081), Vector3(0.04, 0.03, 0.004), lamp)

	for hip: Node3D in [_hip_l, _hip_r]:
		GeometryKit.cylinder(hip, Vector3(0.0, -0.21, 0.0), 0.09, 0.07, 0.44, suit)
		GeometryKit.mesh_box(hip, Vector3(0.0, -0.2, -0.07), Vector3(0.13, 0.26, 0.04), armour)
	for knee: Node3D in [_knee_l, _knee_r]:
		GeometryKit.sphere(knee, Vector3(0.0, 0.0, -0.03), 0.07, armour_dark)
		GeometryKit.cylinder(knee, Vector3(0.0, -0.2, 0.0), 0.065, 0.055, 0.4, suit)
		GeometryKit.mesh_box(knee, Vector3(0.0, -0.17, -0.06), Vector3(0.11, 0.26, 0.04), armour)
	for ankle: Node3D in [_ankle_l, _ankle_r]:
		GeometryKit.mesh_box(ankle, Vector3(0.0, -0.03, -0.045), Vector3(0.12, 0.09, 0.27), rubber)
		GeometryKit.mesh_box(ankle, Vector3(0.0, 0.04, 0.0), Vector3(0.12, 0.1, 0.13), armour_dark)
