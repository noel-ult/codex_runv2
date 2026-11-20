class_name PlayerController
extends CharacterBody3D
## Third-person Runner controller.
##
## Movement layer only: all Codex rules (Resonance, Form, locks, Ignition) live in the
## child CodexSignalSystem. This script never references Hunter AI; capture
## notifications arrive through `on_caught()`, wired by the scene's composition root.

signal fracture_target_changed(has_target: bool, target_name: String)
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
@export var fracture_range: float = 45.0
## Half-angle of the aim-assist cone used when the raycast narrowly misses a vehicle.
@export var fracture_assist_degrees: float = 6.0
@export var kill_floor_y: float = -25.0

var captures: int = 0

var _spawn_transform: Transform3D
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _super_jump_cooldown_left: float = 0.0
var _air_super_jump_used: bool = false
var _last_micro_fusion: StringName = &""
var _aimed_target: Node3D
var _body_material: StandardMaterial3D

@onready var _codex: CodexSignalSystem = $CodexSignalSystem
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _interaction_ray: RayCast3D = $CameraPivot/SpringArm3D/Camera3D/InteractionRay
@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/Body


func _ready() -> void:
	_spawn_transform = global_transform
	_spring_arm.add_excluded_object(get_rid())
	_interaction_ray.add_exception(self)
	_interaction_ray.target_position = Vector3(0.0, 0.0, -fracture_range)
	_body_material = _body_mesh.get_active_material(0).duplicate() as StandardMaterial3D
	_body_mesh.material_override = _body_material
	_codex.form_changed.connect(_on_form_changed)
	_codex.resonance_changed.connect(_on_resonance_changed)
	_codex.feedback.connect(_relay_feedback)
	_on_form_changed(_codex.form)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_codex() -> CodexSignalSystem:
	return _codex


## Called (via signal wiring in main) when a Hunter reaches the Runner.
func on_caught() -> void:
	captures += 1
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_dash_time_left = 0.0
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

	var move_direction: Vector3 = _get_move_direction()
	_handle_form_toggle()
	_handle_jumps()
	_handle_micro_dash(move_direction)
	_apply_horizontal_movement(move_direction, delta)
	_handle_fracture()

	move_and_slide()
	_face_movement(delta)
	_update_aim_target()

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


func _handle_form_toggle() -> void:
	if Input.is_action_just_pressed(&"toggle_full_form"):
		_codex.toggle_full_form()


func _face_movement(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length_squared() < 0.25:
		return
	var target_yaw: float = atan2(-velocity.x, -velocity.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(12.0 * delta, 0.0, 1.0))


# --- Codex Fracturing ----------------------------------------------------------

func _handle_fracture() -> void:
	if not Input.is_action_just_pressed(&"fracture_codex"):
		return
	if _aimed_target == null:
		feedback.emit("Look at a moving vehicle to fracture the Codex onto it.")
		return
	_codex.fracture_onto(_aimed_target, _last_micro_fusion)


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

func _on_form_changed(new_form: StringName) -> void:
	var full: bool = new_form == CodexSignalSystem.FORM_FULL
	_visual.scale = Vector3.ONE * (1.12 if full else 1.0)
	_body_material.albedo_color = Color(0.85, 0.2, 0.75) if full else Color(0.15, 0.55, 0.6)
	_body_material.emission = CodexSignalSystem.get_ability_color(CodexSignalSystem.ABILITY_FULL_FORM) if full else Color(0.1, 0.8, 0.9)


func _on_resonance_changed(value: float, max_value: float) -> void:
	_body_material.emission_energy_multiplier = 0.2 + 3.0 * (value / max_value)


func _relay_feedback(message: String) -> void:
	feedback.emit(message)
