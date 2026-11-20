class_name PlayerController
extends CharacterBody3D
## Third-person Runner controller.
##
## Movement layer only: all Codex rules (Resonance, Form, locks, Ignition) live in the
## child CodexSignalSystem. This script never references Hunter AI; capture
## notifications arrive through `on_caught()`, wired by the scene's composition root.
## Drives the procedural HumanoidRig, camera feel (FOV kick, shake) and hold-to-interact.

signal fracture_target_changed(has_target: bool, target_name: String)
signal interaction_prompt_changed(text: String, progress: float)
signal captured(total_captures: int)
signal feedback(message: String)

const FRACTURE_GROUP: StringName = &"fracture_targets"

@export_group("Movement")
@export var base_speed: float = 4.5
@export var full_form_speed: float = 12.5
@export var ground_acceleration: float = 40.0
@export var air_acceleration: float = 12.0
@export var gravity: float = 22.0

@export_group("Jumping")
@export var base_jump_velocity: float = 7.0
@export var full_form_jump_velocity: float = 12.0
@export var super_jump_velocity: float = 19.0
@export var super_jump_cooldown: float = 1.4

@export_group("Micro Dash")
@export var micro_dash_speed: float = 26.0
@export var micro_dash_duration: float = 0.2
@export var micro_dash_cooldown: float = 0.9

@export_group("Camera & Aim")
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch_degrees: float = -65.0
@export var max_pitch_degrees: float = 35.0
@export var base_fov: float = 70.0
@export var fracture_range: float = 45.0
## Half-angle of the aim-assist cone used when the raycast narrowly misses a vehicle.
@export var fracture_assist_degrees: float = 6.0
@export var kill_floor_y: float = -25.0

var captures: int = 0
var carrying_device: bool = false
var input_enabled: bool = true

var _spawn_transform: Transform3D
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _super_jump_cooldown_left: float = 0.0
var _air_super_jump_used: bool = false
var _last_micro_fusion: StringName = &""
var _aimed_target: Node3D
var _interactable: Interactable
var _hold_time: float = 0.0
var _prompt_text: String = ""
var _prompt_progress: float = -1.0
var _shake: float = 0.0
var _aura: GPUParticles3D
var _aura_material: StandardMaterial3D
var _dash_trail: GPUParticles3D

@onready var _codex: CodexSignalSystem = $CodexSignalSystem
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _interaction_ray: RayCast3D = $CameraPivot/SpringArm3D/Camera3D/InteractionRay
@onready var _visual: Node3D = $Visual
@onready var _rig: HumanoidRig = $Visual/Rig


func _ready() -> void:
	_spawn_transform = global_transform
	_spring_arm.add_excluded_object(get_rid())
	_interaction_ray.add_exception(self)
	_interaction_ray.target_position = Vector3(0.0, 0.0, -fracture_range)
	_build_effects()
	_codex.form_changed.connect(_on_form_changed)
	_codex.resonance_changed.connect(_on_resonance_changed)
	_codex.codex_ignited.connect(_on_ignited)
	_codex.feedback.connect(_relay_feedback)
	_on_form_changed(_codex.form)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_codex() -> CodexSignalSystem:
	return _codex


func get_view_camera() -> Camera3D:
	return _camera


func get_head_position() -> Vector3:
	return global_position + Vector3(0.0, 1.6, 0.0)


func set_spawn_transform(spawn: Transform3D) -> void:
	_spawn_transform = spawn


func set_carrying_device(carrying: bool) -> void:
	carrying_device = carrying
	_rig.set_carry_visible(carrying)


func teleport(target: Vector3) -> void:
	global_position = target
	velocity = Vector3.ZERO


## Called (via signal wiring in main) when a Hunter reaches the Runner.
func on_caught() -> void:
	captures += 1
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_dash_time_left = 0.0
	_shake = 0.6
	_codex.reset_resonance()
	captured.emit(captures)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_camera_pivot.rotate_y(-motion.relative.x * mouse_sensitivity)
		_spring_arm.rotation.x = clampf(
			_spring_arm.rotation.x - motion.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
	elif event is InputEventMouseButton and event.is_pressed():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	_super_jump_cooldown_left = maxf(_super_jump_cooldown_left - delta, 0.0)

	if is_on_floor():
		_air_super_jump_used = false
	elif _dash_time_left <= 0.0:
		velocity.y -= gravity * delta

	var move_direction: Vector3 = _get_move_direction() if input_enabled else Vector3.ZERO
	if input_enabled:
		_handle_form_toggle()
		_handle_jumps()
		_handle_micro_dash(move_direction)
	_apply_horizontal_movement(move_direction, delta)
	_handle_interaction(delta)

	move_and_slide()
	_face_movement(delta)
	_update_aim_target()
	_animate(delta)

	if global_position.y < kill_floor_y:
		global_transform = _spawn_transform
		velocity = Vector3.ZERO


# --- Movement ----------------------------------------------------------------

func _get_move_direction() -> Vector3:
	var input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var basis: Basis = _camera_pivot.global_basis
	var backward: Vector3 = Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var right: Vector3 = Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	return (right * input.x + backward * input.y).limit_length(1.0)


func _current_speed() -> float:
	return full_form_speed if _codex.is_full_form() else base_speed


func _apply_horizontal_movement(direction: Vector3, delta: float) -> void:
	if _dash_time_left > 0.0:
		_dash_time_left -= delta
		velocity.x = _dash_direction.x * micro_dash_speed
		velocity.z = _dash_direction.z * micro_dash_speed
		velocity.y = maxf(velocity.y, 0.0)
		return
	var target: Vector3 = direction * _current_speed()
	var accel: float = ground_acceleration if is_on_floor() else air_acceleration
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _handle_jumps() -> void:
	var wants_super: bool = Input.is_action_just_pressed(&"super_jump")
	if Input.is_action_just_pressed(&"jump"):
		if is_on_floor():
			velocity.y = full_form_jump_velocity if _codex.is_full_form() else base_jump_velocity
		elif not _air_super_jump_used:
			wants_super = true
	if wants_super and _super_jump_cooldown_left <= 0.0 and _codex.try_micro_fusion(CodexSignalSystem.ABILITY_SUPER_JUMP):
		velocity.y = super_jump_velocity
		_super_jump_cooldown_left = super_jump_cooldown
		_last_micro_fusion = CodexSignalSystem.ABILITY_SUPER_JUMP
		_shake = maxf(_shake, 0.15)
		if not is_on_floor():
			_air_super_jump_used = true


func _handle_micro_dash(move_direction: Vector3) -> void:
	if not Input.is_action_just_pressed(&"micro_dash") or _dash_cooldown_left > 0.0:
		return
	if not _codex.try_micro_fusion(CodexSignalSystem.ABILITY_MICRO_DASH):
		return
	_dash_direction = move_direction.normalized()
	if _dash_direction.is_zero_approx():
		_dash_direction = -_camera_pivot.global_basis.z
		_dash_direction.y = 0.0
		_dash_direction = _dash_direction.normalized()
	_dash_time_left = micro_dash_duration
	_dash_cooldown_left = micro_dash_cooldown
	_last_micro_fusion = CodexSignalSystem.ABILITY_MICRO_DASH
	_dash_trail.restart()
	_dash_trail.emitting = true


func _handle_form_toggle() -> void:
	if Input.is_action_just_pressed(&"toggle_full_form"):
		_codex.toggle_full_form()


func _face_movement(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length_squared() < 0.25:
		return
	var target_yaw: float = atan2(-velocity.x, -velocity.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(12.0 * delta, 0.0, 1.0))


func _animate(delta: float) -> void:
	var local_velocity: Vector3 = _visual.global_basis.inverse() * velocity
	_rig.dashing = _dash_time_left > 0.0
	_rig.crouch_amount = move_toward(_rig.crouch_amount, 1.0 if _interactable != null and _hold_time > 0.0 else 0.0, delta * 4.0)
	_rig.animate(local_velocity, is_on_floor(), delta)

	var target_fov: float = base_fov
	if _codex.is_full_form():
		target_fov += 8.0
	if _dash_time_left > 0.0:
		target_fov += 12.0
	_camera.fov = lerpf(_camera.fov, target_fov, clampf(6.0 * delta, 0.0, 1.0))
	_shake = move_toward(_shake, 0.0, delta * 1.5)
	var t: float = Time.get_ticks_msec() * 0.001
	_camera.h_offset = sin(t * 47.0) * _shake * 0.08
	_camera.v_offset = cos(t * 53.0) * _shake * 0.08
	_aura.emitting = _codex.is_full_form()


# --- Interaction & Codex Fracturing ----------------------------------------------

func _handle_interaction(delta: float) -> void:
	var nearest: Interactable = _find_interactable() if input_enabled else null
	if nearest != _interactable:
		_interactable = nearest
		_hold_time = 0.0

	if _interactable != null:
		var can_use: bool = _interactable.meets_requirement(self)
		if can_use and Input.is_action_pressed(&"fracture_codex"):
			_hold_time += delta
			var progress: float = clampf(_hold_time / maxf(_interactable.hold_time, 0.01), 0.0, 1.0)
			_interactable.report_progress(progress)
			_set_prompt(_interactable.get_prompt_text(self), progress)
			if progress >= 1.0:
				var used: Interactable = _interactable
				_hold_time = 0.0
				used.complete(self)
		else:
			_hold_time = 0.0
			_set_prompt(_interactable.get_prompt_text(self), -1.0)
		return

	_set_prompt("", -1.0)
	if input_enabled and Input.is_action_just_pressed(&"fracture_codex"):
		if _aimed_target == null:
			feedback.emit("Look at a moving vehicle to fracture the Codex onto it.")
			return
		_codex.fracture_onto(_aimed_target, _last_micro_fusion)


func _find_interactable() -> Interactable:
	var best: Interactable = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var candidate := node as Interactable
		if candidate == null or not candidate.is_available_for(self):
			continue
		var distance: float = candidate.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _set_prompt(text: String, progress: float) -> void:
	if text == _prompt_text and is_equal_approx(progress, _prompt_progress):
		return
	_prompt_text = text
	_prompt_progress = progress
	interaction_prompt_changed.emit(text, progress)


func _update_aim_target() -> void:
	var target: Node3D = _find_aimed_target()
	if target == _aimed_target:
		return
	_aimed_target = target
	var target_name: String = ""
	if target != null and target.has_method(&"get_display_name"):
		target_name = str(target.call(&"get_display_name"))
	fracture_target_changed.emit(target != null, target_name)


func _find_aimed_target() -> Node3D:
	if _interaction_ray.is_colliding():
		var hit: Node3D = _resolve_fracture_target(_interaction_ray.get_collider())
		if hit != null:
			return hit

	# Aim assist: pick the vehicle closest to the crosshair inside a narrow cone,
	# provided nothing solid blocks line of sight.
	var origin: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_basis.z
	var best: Node3D = null
	var best_angle: float = deg_to_rad(fracture_assist_degrees)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for node: Node in get_tree().get_nodes_in_group(FRACTURE_GROUP):
		var candidate := node as Node3D
		if candidate == null:
			continue
		var to_target: Vector3 = candidate.global_position + Vector3.UP - origin
		if to_target.length() > fracture_range:
			continue
		var angle: float = forward.angle_to(to_target)
		if angle >= best_angle:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, origin + to_target, _interaction_ray.collision_mask, [get_rid()])
		var result: Dictionary = space.intersect_ray(query)
		if not result.is_empty() and _resolve_fracture_target(result.get("collider")) != candidate:
			continue
		best = candidate
		best_angle = angle
	return best


func _resolve_fracture_target(collider: Object) -> Node3D:
	var node := collider as Node
	while node != null:
		if node.is_in_group(FRACTURE_GROUP):
			return node as Node3D
		node = node.get_parent()
	return null


# --- Visual feedback -------------------------------------------------------------

func _build_effects() -> void:
	_aura_material = MaterialLibrary.emissive(Color(1.0, 0.3, 0.85), 4.0, false)
	_aura_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_material.vertex_color_use_as_albedo = true
	var soft := Gradient.new()
	soft.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	soft.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var sprite := GradientTexture2D.new()
	sprite.gradient = soft
	sprite.fill = GradientTexture2D.FILL_RADIAL
	sprite.fill_from = Vector2(0.5, 0.5)
	sprite.fill_to = Vector2(1.0, 0.5)
	sprite.width = 64
	sprite.height = 64
	_aura_material.albedo_texture = sprite
	_aura = _make_particles(64, 0.9, _aura_material, 0.12)
	var aura_process := _aura.process_material as ParticleProcessMaterial
	aura_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	aura_process.emission_sphere_radius = 0.55
	aura_process.gravity = Vector3(0.0, 1.5, 0.0)
	_aura.position = Vector3(0.0, 1.0, 0.0)
	_aura.emitting = false

	var trail_material := _aura_material.duplicate() as StandardMaterial3D
	trail_material.albedo_color = Color(0.3, 0.95, 1.0)
	trail_material.emission = Color(0.3, 0.95, 1.0)
	_dash_trail = _make_particles(70, 0.45, trail_material, 0.16)
	_dash_trail.one_shot = true
	_dash_trail.explosiveness = 0.0
	var trail_process := _dash_trail.process_material as ParticleProcessMaterial
	trail_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	trail_process.emission_box_extents = Vector3(0.25, 0.8, 0.25)
	_dash_trail.position = Vector3(0.0, 1.0, 0.0)
	_dash_trail.local_coords = false
	_dash_trail.emitting = false


func _make_particles(amount: int, lifetime: float, material: StandardMaterial3D, size: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.8
	process.scale_min = 0.6
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	particles.draw_pass_1 = quad
	add_child(particles)
	return particles


func _on_form_changed(_new_form: StringName) -> void:
	_on_resonance_changed(_codex.resonance, _codex.max_resonance)


func _on_resonance_changed(value: float, max_value: float) -> void:
	var full: bool = _codex.is_full_form()
	var color: Color = CodexSignalSystem.get_ability_color(CodexSignalSystem.ABILITY_FULL_FORM) if full else Color(0.2, 0.9, 1.0)
	_rig.set_accent(color, 0.6 + 4.5 * (value / max_value) + (1.5 if full else 0.0))


func _on_ignited(_broadcasting: bool) -> void:
	_shake = maxf(_shake, 0.5)


func _relay_feedback(message: String) -> void:
	feedback.emit(message)
