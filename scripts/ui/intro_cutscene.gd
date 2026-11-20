class_name IntroCutscene
extends CanvasLayer
## Three camera shots in an isolated world, with the mission scene paused underneath.

signal finished()

const SHOT_SECONDS: float = 4.0
const DURATION: float = SHOT_SECONDS * 3.0
const CAPTIONS: PackedStringArray = [
	"I found the Codex sealed beneath Meridian Labs.",
	"The moment I touched it, I felt a pulse under my skin.",
	"Now every burst makes me stronger. Every pulse tells the Hunters where I am.",
]
const CYAN: Color = Color("69e8de")

var _screen: SubViewportContainer
var _view: SubViewport
var _camera: Camera3D
var _runner: HumanoidRig
var _artifact: Node3D
var _pulse: OmniLight3D
var _rings: Array[MeshInstance3D] = []
var _caption: Label
var _fade: ColorRect
var _elapsed: float = 0.0
var _shot: int = -1
var _active: bool = false


func play() -> void:
	if _active:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_active = true
	_build()
	_update_shot(0.0, 0.0)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.physical_keycode == KEY_SPACE or key.physical_keycode == KEY_ESCAPE:
			_finish()


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	if _elapsed >= DURATION:
		_finish()
		return
	_update_shot(_elapsed, delta)


func _finish() -> void:
	_active = false
	hide()
	finished.emit()


func _update_shot(elapsed: float, delta: float) -> void:
	var shot: int = int(elapsed / SHOT_SECONDS)
	var age: float = fmod(elapsed, SHOT_SECONDS)
	var t: float = smoothstep(0.0, SHOT_SECONDS, age)
	if shot != _shot:
		_shot = shot
		_caption.text = CAPTIONS[shot]
	var target: Vector3
	var pulse: float = 0.0
	match shot:
		0:
			_camera.position = Vector3(3.6, 2.2, -5.6).lerp(Vector3(2.4, 1.75, -3.7), t)
			target = Vector3(0.0, 0.96, 0.0)
			_runner.position.x = lerpf(-2.2, -0.54, t)
		1:
			_camera.position = Vector3(0.12, 1.68, -2.5).lerp(Vector3(0.03, 1.52, -2.0), t)
			target = Vector3(0.0, 1.25, 0.0)
			pulse = smoothstep(1.05, 2.0, age) * (1.0 - smoothstep(2.65, 4.0, age))
			_runner.position.x = -0.54
		_:
			_camera.position = Vector3(-2.05, 1.35, -2.3).lerp(Vector3(-1.4, 1.72, -3.05), t)
			target = Vector3(-0.7, 0.98, 0.0)
			pulse = 0.6 + 0.25 * sin(age * 5.5)
			_runner.position.x = -0.92
	_camera.look_at(target)
	_artifact.rotation.y = elapsed * (0.65 + pulse * 0.4)
	_artifact.position.y = 1.15 + 0.08 * sin(elapsed * 2.0)
	_pulse.light_energy = 1.6 + pulse * 5.0
	_runner.rotation.y = PI * 0.5 if shot < 2 else lerpf(-0.55, 0.14, t)
	_runner.scanning = shot == 1 and age > 0.3 and age < 2.35
	_runner.crouch_amount = pulse * 0.65 if shot == 1 else 0.0
	_runner.set_accent(CYAN, 0.1 + pulse * 3.5)
	_runner.animate(Vector3(0.0, 0.0, -1.0 + t) if shot == 0 else Vector3.ZERO, true, delta)
	for index: int in _rings.size():
		var phase: float = fmod(age * 0.8 + float(index) / _rings.size(), 1.0)
		var ring: MeshInstance3D = _rings[index]
		ring.visible = pulse > 0.15
		ring.scale = Vector3.ONE * lerpf(0.25, 2.9, phase)
		ring.transparency = lerpf(0.3, 1.0, phase)
	_fade.color.a = maxf(1.0 - smoothstep(0.0, 0.36, age), smoothstep(3.63, 4.0, age))
	if shot == 1:
		_fade.color = Color(0.47, 0.96, 1.0, maxf(0.0, 0.34 - absf(age - 2.1) * 1.2)) if age > 1.8 and age < 2.4 else Color(0.0, 0.0, 0.0, _fade.color.a)
	else:
		_fade.color = Color(0.0, 0.0, 0.0, _fade.color.a)


func _build() -> void:
	_screen = SubViewportContainer.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.stretch = true
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.gui_disable_input = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_screen.add_child(_view)
	var stage := Node3D.new()
	_view.add_child(stage)
	var lighting := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("050b11")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8098b1")
	environment.ambient_light_energy = 0.36
	lighting.environment = environment
	stage.add_child(lighting)

	var concrete: StandardMaterial3D = MaterialLibrary.coated(Color("18232e"), 0.72, 0.26)
	var metal: StandardMaterial3D = MaterialLibrary.coated(Color("34434b"), 0.54, 0.55)
	var glass: StandardMaterial3D = MaterialLibrary.emissive(CYAN, 2.4, false)
	GeometryKit.mesh_box(stage, Vector3(0.0, -0.16, 0.0), Vector3(14.0, 0.3, 14.0), concrete)
	GeometryKit.mesh_box(stage, Vector3(0.0, 2.0, 3.7), Vector3(14.0, 4.0, 0.3), concrete)
	for index: int in range(-4, 5):
		var x: float = float(index) * 1.45
		GeometryKit.mesh_box(stage, Vector3(x, 1.62, 3.45), Vector3(0.13, 3.25, 0.38), metal)
		GeometryKit.mesh_box(stage, Vector3(x, 2.61, 3.22), Vector3(0.045, 0.45, 0.024), glass, false)
	GeometryKit.cylinder(stage, Vector3(0.2, 0.42, 0.0), 0.32, 0.43, 0.84, metal, 32)
	GeometryKit.cylinder(stage, Vector3(0.2, 0.81, 0.0), 0.34, 0.34, 0.025, glass, 32)
	_artifact = Node3D.new()
	_artifact.position.x = 0.2
	stage.add_child(_artifact)
	var core: MeshInstance3D = GeometryKit.mesh_box(
		_artifact, Vector3.ZERO, Vector3(0.19, 0.19, 0.19), glass, false)
	core.rotation = Vector3(0.6, 0.35, 0.65)
	var cage: MeshInstance3D = GeometryKit.mesh_box(
		_artifact, Vector3(0.0, -0.18, 0.0), Vector3(0.31, 0.05, 0.31), metal)
	cage.rotation.y = PI * 0.25
	_pulse = _add_light(stage, Vector3(0.25, 1.25, -0.4), CYAN, 2.1, 4.2)
	_add_light(stage, Vector3(-2.4, 2.1, -2.0), Color("e6b28a"), 2.5, 7.0)
	_add_light(stage, Vector3(-0.8, 2.6, 1.8), Color("639ee8"), 3.8, 7.0)
	for index: int in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.44
		torus.outer_radius = 0.45
		ring.mesh = torus
		ring.material_override = glass
		ring.position = Vector3(0.2, 0.06 + float(index) * 0.055, 0.0)
		stage.add_child(ring)
		_rings.append(ring)

	_runner = HumanoidRig.new()
	_runner.style = HumanoidRig.Style.RUNNER
	stage.add_child(_runner)
	_runner.set_carry_visible(false)
	_camera = Camera3D.new()
	_camera.fov = 48.0
	stage.add_child(_camera)
	_camera.make_current()
	_build_overlay()


func _add_light(stage: Node3D, origin: Vector3, tint: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = origin
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = reach
	stage.add_child(light)
	return light


func _build_overlay() -> void:
	var bars := Control.new()
	bars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bars)
	var top := ColorRect.new()
	top.color = Color("06090e")
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 36.0
	bars.add_child(top)
	var bottom := ColorRect.new()
	bottom.color = top.color
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -110.0
	bars.add_child(bottom)
	_caption = _make_label(bottom, 19, Color("e1eaed"))
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_caption.offset_left = 16.0
	_caption.offset_right = -16.0
	_caption.offset_top = 12.0
	var skip: Label = _make_label(bottom, 13, CYAN)
	skip.text = "SPACE / ESC   SKIP INTRO"
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	skip.offset_top = -30.0
	_fade = ColorRect.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_sibling(_fade)
	move_child(_fade, 1)


func _make_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	parent.add_child(label)
	return label
