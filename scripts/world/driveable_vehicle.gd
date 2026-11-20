class_name DriveableVehicle
extends CharacterBody3D
## Collision-aware, reusable city vehicle. Driver state stays on the Runner for Codex rules.

signal driver_changed(vehicle: DriveableVehicle, driver: PlayerController)
signal telemetry_changed(speed_kmh: float, vehicle_name: String)

@export var display_name: String = "City sedan"
@export var body_color: Color = Color(0.13, 0.43, 0.4)
@export var kind: VehicleModel.Kind = VehicleModel.Kind.SEDAN
@export var forward_speed: float = 22.0
@export var reverse_speed: float = 7.0
@export var acceleration: float = 10.0
@export var braking: float = 27.0
@export var steering_rate: float = 1.35

var driver: PlayerController
var speed: float = 0.0
var interactable: Interactable
var _wheels: Array[Node3D] = []
var _body_shape: CollisionShape3D
var _camera_pivot: Node3D
var _camera: Camera3D
var _spring_arm: SpringArm3D
var _cue: Label3D
var _exit_armed: bool = false
var _telemetry_left: float = 0.0
var _spawn_transform: Transform3D


func _ready() -> void:
	collision_layer = 8
	collision_mask = GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER | 4 | 8 | 128
	floor_snap_length = 0.65
	floor_max_angle = deg_to_rad(48.0)
	_spawn_transform = global_transform
	_body_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.88, 1.35 if kind != VehicleModel.Kind.VAN else 1.95, 4.35 if kind != VehicleModel.Kind.VAN else 4.85)
	_body_shape.shape = box
	_body_shape.position.y = box.size.y * 0.5
	add_child(_body_shape)
	_wheels = VehicleModel.build(self, kind, body_color, true)
	_build_camera()
	_build_access()


func _build_camera() -> void:
	_camera_pivot = Node3D.new()
	_camera_pivot.position = Vector3(0.0, 1.8, 0.0)
	add_child(_camera_pivot)
	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = 7.8
	_spring_arm.margin = 0.35
	_spring_arm.collision_mask = GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER | 8
	_spring_arm.rotation.x = deg_to_rad(-13.0)
	_camera_pivot.add_child(_spring_arm)
	_spring_arm.add_excluded_object(get_rid())
	_camera = Camera3D.new()
	_camera.fov = 76.0
	_camera.far = 700.0
	_spring_arm.add_child(_camera)


func _build_access() -> void:
	interactable = Interactable.new()
	interactable.name = "DriverDoor"
	interactable.prompt = "Drive %s" % display_name
	interactable.hold_time = 0.45
	interactable.radius = 1.6
	interactable.height_tolerance = 1.8
	interactable.position = Vector3(-1.15, 0.7, 0.2)
	interactable.requirement = _can_enter
	interactable.requirement_hint = "Stop beside the driver's door to enter"
	add_child(interactable)
	interactable.completed.connect(_on_enter_requested)
	_cue = Label3D.new()
	_cue.text = "%s\nHOLD E  ·  DRIVE" % display_name.to_upper()
	_cue.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cue.position.y = 2.6 if kind == VehicleModel.Kind.VAN else 2.0
	_cue.font_size = 28
	_cue.pixel_size = 0.006
	_cue.modulate = Color(0.45, 1.0, 0.83)
	_cue.outline_modulate = Color(0.01, 0.03, 0.035)
	add_child(_cue)


func _can_enter(actor: Node3D) -> bool:
	var runner := actor as PlayerController
	if runner == null or driver != null or absf(speed) > 0.5 or not runner.input_enabled or runner.is_driving():
		return false
	var from: Vector3 = runner.get_head_position()
	var target: Vector3 = to_global(Vector3(-1.02, 0.95, 0.2))
	var query := PhysicsRayQueryParameters3D.create(from, target, GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER | 8, [get_rid(), runner.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_enter_requested(port: Interactable, actor: Node3D) -> void:
	if not port.is_available_for(actor) or not _can_enter(actor):
		return
	var runner := actor as PlayerController
	if not runner.enter_vehicle(self):
		return
	driver = runner
	_exit_armed = false
	interactable.enabled = false
	_cue.hide()
	_camera_pivot.rotation.y = 0.0
	_camera.make_current()
	_sync_driver()
	driver.feedback.emit("%s: W/S drive · A/D steer · Space brake · E exit when stopped." % display_name)
	driver_changed.emit(self, driver)
	telemetry_changed.emit(0.0, display_name)


func get_drive_camera() -> Camera3D:
	return _camera


func _unhandled_input(event: InputEvent) -> void:
	if driver == null or not driver.input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_camera_pivot.rotation.y = clampf(_camera_pivot.rotation.y - motion.relative.x * driver.mouse_sensitivity, -PI * 0.75, PI * 0.75)
		_spring_arm.rotation.x = clampf(_spring_arm.rotation.x - motion.relative.y * driver.mouse_sensitivity, deg_to_rad(-50.0), deg_to_rad(12.0))


func _physics_process(delta: float) -> void:
	if driver != null and not is_instance_valid(driver):
		driver = null
		interactable.enabled = true
		_cue.show()
	var enabled: bool = driver != null and driver.input_enabled
	var throttle: float = Input.get_axis(&"move_back", &"move_forward") if enabled else 0.0
	var steer: float = Input.get_axis(&"move_right", &"move_left") if enabled else 0.0
	var handbrake: bool = enabled and Input.is_action_pressed(&"jump")
	var target_speed: float = throttle * (forward_speed if throttle >= 0.0 else reverse_speed)
	var change: float = acceleration
	if handbrake or not enabled:
		target_speed = 0.0
		change = braking
	elif is_zero_approx(throttle):
		change = 5.0
	elif speed * throttle < 0.0:
		change = braking * 0.8
	speed = move_toward(speed, target_speed, change * delta)
	if absf(speed) > 0.08:
		var steering: float = steer * signf(speed) * steering_rate * minf(absf(speed) / 6.0, 1.0) * delta
		_try_steer(steering)
	var forward: Vector3 = -global_basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	velocity.y = -1.5 if is_on_floor() else velocity.y - 22.0 * delta
	move_and_slide()
	if is_on_wall():
		speed = Vector3(velocity.x, 0.0, velocity.z).dot(forward)
	for wheel: Node3D in _wheels:
		wheel.rotation.x -= speed * delta / 0.36
	if driver != null:
		_sync_driver()
		_update_exit()
		_telemetry_left -= delta
		if _telemetry_left <= 0.0:
			_telemetry_left = 0.12
			telemetry_changed.emit(absf(speed) * 3.6, display_name)
	if global_position.y < -20.0:
		global_transform = _spawn_transform
		velocity = Vector3.ZERO
		speed = 0.0
		if driver != null:
			_sync_driver()
			driver.feedback.emit("Vehicle recovered to its parking spot.")


func _try_steer(angle: float) -> void:
	if is_zero_approx(angle):
		return
	var before: float = rotation.y
	rotation.y += angle
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _body_shape.shape
	query.transform = _body_shape.global_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	if driver != null:
		query.exclude.append(driver.get_rid())
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		rotation.y = before


func _sync_driver() -> void:
	driver.global_position = to_global(Vector3(-0.28, 0.15, 0.3))
	driver.velocity = velocity


func _update_exit() -> void:
	if not Input.is_action_pressed(&"interact"):
		_exit_armed = true
	if not _exit_armed or not driver.input_enabled or not Input.is_action_just_pressed(&"interact"):
		return
	if absf(speed) > 1.0:
		driver.feedback.emit("Brake to a stop before leaving the vehicle.")
		return
	var exit: Vector3 = find_exit_position()
	if not exit.is_finite():
		driver.feedback.emit("The doors are blocked. Move to a clear space before exiting.")
		return
	_detach_driver(exit)


func find_exit_position() -> Vector3:
	if driver == null:
		return Vector3.INF
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.85
	var offsets: Array[Vector3] = [Vector3(-1.7, 0.0, 0.2), Vector3(1.7, 0.0, 0.2), Vector3(-1.7, 0.0, 1.5), Vector3(1.7, 0.0, 1.5), Vector3(0.0, 0.0, 3.2)]
	for offset: Vector3 in offsets:
		var point: Vector3 = to_global(offset)
		var ground_ray := PhysicsRayQueryParameters3D.create(point + Vector3(0.0, 1.4, 0.0), point - Vector3(0.0, 1.3, 0.0), GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER, [get_rid(), driver.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ground_ray)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		if normal.y < 0.75:
			continue
		var floor_point: Vector3 = hit.get("position", point)
		point = floor_point + Vector3(0.0, 0.06, 0.0)
		var doorway_ray := PhysicsRayQueryParameters3D.create(to_global(Vector3(0.0, 1.0, 0.2)), point + Vector3(0.0, 0.95, 0.0), GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER | 8, [get_rid(), driver.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(doorway_ray).is_empty():
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3(0.0, 0.95, 0.0))
		query.collision_mask = GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER | 4 | 8 | 128
		query.exclude = [get_rid(), driver.get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return point
	return Vector3.INF


func _detach_driver(exit_position: Vector3) -> void:
	var previous: PlayerController = driver
	driver = null
	speed = 0.0
	velocity = Vector3.ZERO
	interactable.enabled = true
	_cue.show()
	previous.leave_vehicle(exit_position)
	driver_changed.emit(self, null)
	telemetry_changed.emit(0.0, "")


## Capture/teleport must release ownership before the Runner changes position.
func force_exit_for_capture() -> void:
	if driver == null:
		return
	_detach_driver(driver.global_position)
