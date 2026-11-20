class_name OperatorPreview
extends SubViewportContainer
## Interactive inspection stage showing the same procedural rigs the city uses.

const INK: Color = Color("#0a151a")
const MINT: Color = Color("#6affdb")
const HOME_ANGLE: float = 0.36
const FLOOR_SHADER: Shader = preload("res://shaders/operator_stage_floor.gdshader")

var _role: HumanoidRig.Style = HumanoidRig.Style.RUNNER
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _rig: HumanoidRig
var _focus_ring: Panel
var _yaw: float = HOME_ANGLE
var _dragging: bool = false


func _ready() -> void:
	stretch = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	accessibility_name = "3D character preview"
	accessibility_description = "Drag or use the left and right arrow keys to rotate."
	_add_focus_ring()
	resized.connect(_fit_camera)
	visibility_changed.connect(_sync_visibility)
	_sync_visibility()


func show_operator(role: HumanoidRig.Style) -> void:
	if role == _role:
		return
	_role = role
	if _stage != null and is_visible_in_tree():
		_build_operator()


func _sync_visibility() -> void:
	var showing: bool = is_visible_in_tree()
	set_process(showing)
	if showing:
		if _stage == null:
			_build_stage()
		if _rig == null or _rig.style != _role:
			_build_operator()
	else:
		_dragging = false
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if showing else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	if _rig == null:
		return
	_rig.rotation.y = lerp_angle(_rig.rotation.y, _yaw, 1.0 - exp(-16.0 * delta))
	_rig.animate(Vector3.ZERO, true, delta)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if _dragging:
				grab_focus()
			accept_event()
	elif _dragging and event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_rotate_by(motion.relative.x * 0.011)
		accept_event()
	elif has_focus() and event is InputEventKey:
		if event.is_action_pressed(&"ui_left", true):
			_rotate_by(-TAU / 24.0)
			accept_event()
		elif event.is_action_pressed(&"ui_right", true):
			_rotate_by(TAU / 24.0)
			accept_event()


func _rotate_by(angle: float) -> void:
	_yaw = wrapf(_yaw + angle, -PI, PI)


func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "InspectionViewport"
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)

	_stage = Node3D.new()
	_stage.name = "InspectionStage"
	_viewport.add_child(_stage)

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = INK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c7e4f2")
	environment.ambient_light_energy = 0.48
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	_stage.add_child(world_environment)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.position = Vector3(0.0, 1.94, -4.5)
	_stage.add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.89, 0.0))
	_fit_camera()
	_camera.make_current()

	_add_light(Vector3(-3.0, 3.8, -4.0), Color("#fff5ea"), 1.05, true)
	_add_light(Vector3(3.0, 2.0, -1.2), Color("#95d9f7"), 0.50)
	_add_light(Vector3(1.8, 3.1, 3.4), Color("#67f6d9"), 1.65)
	_build_platform()
	_build_reticle()


func _fit_camera() -> void:
	if _camera != null:
		_camera.size = maxf(2.65, 1.72 * size.y / maxf(size.x, 1.0))


func _add_focus_ring() -> void:
	var outline: StyleBoxFlat = StyleBoxFlat.new()
	outline.draw_center = false
	outline.border_color = MINT
	outline.set_border_width_all(2)
	_focus_ring = Panel.new()
	_focus_ring.name = "PreviewFocus"
	_focus_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_ring.add_theme_stylebox_override(&"panel", outline)
	_focus_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_focus_ring.hide()
	add_child(_focus_ring)
	focus_entered.connect(_focus_ring.show)
	focus_exited.connect(_focus_ring.hide)


func _build_operator() -> void:
	if _rig != null:
		_stage.remove_child(_rig)
		_rig.queue_free()
	_rig = HumanoidRig.new()
	_rig.name = "Operator"
	_rig.style = _role
	_rig.outfit_seed = 25 if _role == HumanoidRig.Style.CIVILIAN else 0
	_rig.rotation.y = _yaw
	_stage.add_child(_rig)
	match _role:
		HumanoidRig.Style.HUNTER:
			_rig.set_accent(Color("#89f3a2"), 1.30)
		HumanoidRig.Style.TECHNICIAN:
			_rig.set_accent(Color("#77d6ff"), 0.7)
		_:
			_rig.set_accent(MINT, 0.9)


func _add_light(origin: Vector3, tint: Color, energy: float, casts_shadows: bool = false) -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.position = origin
	light.light_color = tint
	light.light_energy = energy
	light.shadow_enabled = casts_shadows
	light.directional_shadow_max_distance = 7.0
	_stage.add_child(light)
	light.look_at(Vector3(0.0, 0.9, 0.0))


func _build_platform() -> void:
	var floor: ShaderMaterial = ShaderMaterial.new()
	floor.shader = FLOOR_SHADER
	var base: StandardMaterial3D = MaterialLibrary.coated(Color("#12272f"), 0.64, 0.42)
	var lip: StandardMaterial3D = MaterialLibrary.coated(Color("#29545a"), 0.45, 0.34)
	var deck: StandardMaterial3D = MaterialLibrary.coated(Color("#19343b"), 0.28, 0.54)
	var floor_plane: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(15.0, 15.0)
	floor_plane.mesh = plane
	floor_plane.position.y = -0.225
	floor_plane.material_override = floor
	floor_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(floor_plane)
	GeometryKit.cylinder(_stage, Vector3(0.0, -0.15, 0.0), 0.57, 0.49, 0.14, base, 48)
	GeometryKit.cylinder(_stage, Vector3(0.0, -0.076, 0.0), 0.64, 0.59, 0.028, lip, 48)
	GeometryKit.cylinder(_stage, Vector3(0.0, -0.0355, 0.0), 0.59, 0.64, 0.068, deck, 48)

	var traces: ImmediateMesh = ImmediateMesh.new()
	traces.surface_begin(Mesh.PRIMITIVE_LINES, _unlit(Color.WHITE, true))
	for index: int in 64:
		var start: float = TAU * float(index) / 64.0
		var end: float = TAU * float(index + 1) / 64.0
		_line(traces, _ring_point(0.615, -0.061, start), _ring_point(0.615, -0.061, end), Color("#3c9390"))
	for index: int in 40:
		var angle: float = TAU * float(index) / 40.0
		var major: bool = index % 5 == 0
		_line(traces, _ring_point(0.72, -0.221, angle), _ring_point(0.80 if major else 0.75, -0.221, angle), Color("#4d9491") if major else Color("#26434a"))
	traces.surface_end()
	_add_traces("StageRings", traces)


func _build_reticle() -> void:
	var guides: ImmediateMesh = ImmediateMesh.new()
	guides.surface_begin(Mesh.PRIMITIVE_LINES, _unlit(Color.WHITE, true))
	var faint: Color = Color("#2a4d53")
	var corner: Color = Color("#3f7475")
	for side: float in [-1.0, 1.0]:
		var x: float = 0.67 * side
		var z: float = 0.29
		_line(guides, Vector3(x, 0.12, z), Vector3(x, 1.94, z), faint)
		for index: int in 10:
			var y: float = 0.13 + float(index) * 0.2
			_line(guides, Vector3(x, y, z), Vector3(x + side * (0.075 if index % 3 == 0 else 0.035), y, z), faint)
		for height: float in [0.12, 1.94]:
			_line(guides, Vector3(x, height, z), Vector3(x - side * 0.10, height, z), corner)
	guides.surface_end()
	_add_traces("HeightGuides", guides)


func _add_traces(label: String, mesh: ImmediateMesh) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(instance)


func _unlit(color: Color, use_vertex_colors: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.vertex_color_use_as_albedo = use_vertex_colors
	material.vertex_color_is_srgb = use_vertex_colors
	return material


func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b)


func _ring_point(radius: float, y: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, y, sin(angle) * radius)
