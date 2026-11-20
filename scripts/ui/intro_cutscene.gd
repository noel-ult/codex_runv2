class_name IntroCutscene
extends CanvasLayer
## Four camera shots in an isolated world, with the mission scene paused underneath.

signal finished()

const SHOT_SECONDS: float = 5.75
const DURATION: float = SHOT_SECONDS * 4.0
const CAPTIONS: PackedStringArray = [
	"I slipped into Meridian Labs looking for proof of what the Hunters were building.",
	"Behind a sealed door, I found the Codex. It started pulsing before I even touched it.",
	"One touch. The pulse went through my hand and lit up my nerves.",
	"I could feel the power building. So could the Hunters.",
]
const CYAN: Color = Color("69e8de")
const AMBER: Color = Color("ff9b66")
const CORE_POSITION: Vector3 = Vector3(0.2, 1.24, 0.0)
const CONTACT_POSITION: Vector3 = Vector3(-0.39, 0.0, 0.19)

var _screen: SubViewportContainer
var _view: SubViewport
var _camera: Camera3D
var _runner: HumanoidRig
var _runner_root: Node3D
var _skeleton: Skeleton3D
var _artifact: Node3D
var _pulse: OmniLight3D
var _alarm: OmniLight3D
var _alarm_strips: StandardMaterial3D
var _rings: Array[MeshInstance3D] = []
var _caption: Label
var _location: Label
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
		if shot == 3:
			_location.text = "MERIDIAN LABS   /   CONTAINMENT BREACH"
			_location.add_theme_color_override(&"font_color", AMBER)
	var target: Vector3 = CORE_POSITION
	var runner_position: Vector3 = CONTACT_POSITION
	var stride: float = 0.0
	var reach: float = 0.0
	var recoil: float = 0.0
	var pulse: float = 0.0
	var ring_origin: Vector3 = CORE_POSITION
	var artifact_energy: float = 0.0
	match shot:
		0:
			_camera.position = Vector3(0.8, 2.65, -6.8).lerp(Vector3(1.1, 2.12, -4.1), t)
			target = Vector3(-0.95, 1.0, 0.1)
			var approach: float = smoothstep(0.3, 5.2, age)
			runner_position.x = lerpf(-2.9, -0.82, approach)
			stride = 0.64 * smoothstep(0.0, 1.0, age) * (1.0 - smoothstep(3.8, 5.2, age))
		1:
			_camera.position = Vector3(-1.2, 1.71, -1.65).lerp(Vector3(-0.55, 1.47, -1.42), t)
			target = CORE_POSITION + Vector3(-0.16, 0.04, 0.0)
			var step: float = smoothstep(2.2, 4.3, age)
			runner_position.x = lerpf(-0.82, CONTACT_POSITION.x, step)
			stride = 0.4 * smoothstep(2.2, 2.8, age) * (1.0 - smoothstep(3.8, 4.3, age))
			reach = smoothstep(4.0, 5.65, age) * 0.35
			artifact_energy = 0.35 + 0.2 * sin(age * 3.4)
		2:
			_camera.position = Vector3(-0.22, 1.57, -1.81).lerp(Vector3(-0.36, 1.59, -2.36), t)
			target = Vector3(-0.21, 1.29, 0.13)
			reach = lerpf(0.35, 1.0, smoothstep(0.1, 2.05, age)) * (1.0 - smoothstep(2.35, 3.35, age))
			recoil = smoothstep(2.2, 2.65, age) * (1.0 - smoothstep(3.25, 5.6, age))
			runner_position.x -= 0.5 * smoothstep(2.23, 3.55, age)
			pulse = smoothstep(2.05, 2.42, age) * (1.0 - 0.68 * smoothstep(2.65, 5.6, age))
			artifact_energy = 0.28 + pulse * 1.6
		_:
			runner_position.x = -0.89
			_camera.position = Vector3(-1.86, 1.44, -2.07).lerp(Vector3(-1.42, 1.60, -2.6), t)
			target = runner_position + Vector3(0.02, 1.06, 0.0)
			pulse = 0.45 + 0.3 * sin(age * 2.8)
			ring_origin = runner_position + Vector3(0.0, 0.34, 0.0)
	_camera.look_at(target)
	_runner_root.position = runner_position
	_runner_root.rotation.y = -PI * 0.5 if shot < 3 else lerpf(-PI * 0.5, -0.12, smoothstep(0.1, 4.0, age))
	_runner.crouch_amount = recoil * 0.85
	_runner.set_accent(CYAN, 0.12 + pulse * 3.6)
	_runner.animate(Vector3(0.0, 0.0, -stride), true, delta)
	if reach > 0.0:
		_pose_reach(reach)
	_artifact.rotation.y = elapsed * 0.65
	_artifact.position.y = CORE_POSITION.y + 0.055 * sin(elapsed * 2.0)
	_pulse.light_energy = 1.3 + artifact_energy * 3.5 + pulse * 2.0
	_pulse.position = CORE_POSITION + Vector3(0.0, 0.0, -0.15) if shot < 3 else runner_position + Vector3(0.0, 1.10, -0.55)
	var alarm: float = (0.55 + 0.45 * sin(age * 3.1)) * smoothstep(0.0, 0.5, age) if shot == 3 else 0.0
	_alarm.light_energy = alarm * 5.0
	_alarm_strips.emission_energy_multiplier = alarm * 3.0
	for index: int in _rings.size():
		var phase: float = fmod(age * 0.63 + float(index) / _rings.size(), 1.0)
		var ring: MeshInstance3D = _rings[index]
		ring.position = ring_origin + Vector3.UP * float(index) * 0.06
		ring.scale = Vector3.ONE * lerpf(0.25, 3.55, phase)
		ring.transparency = 1.0 - (1.0 - phase) * pulse
	var fade_alpha: float = maxf(1.0 - smoothstep(0.0, 0.4, age), smoothstep(SHOT_SECONDS - 0.45, SHOT_SECONDS, age))
	var flash: float = 0.3 * (1.0 - smoothstep(0.0, 0.42, absf(age - 2.37))) if shot == 2 else 0.0
	_fade.color = Color(0.47, 0.96, 1.0, flash) if flash > 0.0 else Color(0.0, 0.0, 0.0, fade_alpha)


func _pose_reach(weight: float) -> void:
	var shoulder: int = HumanoidRig.B_SHOULDER_L
	var elbow: int = HumanoidRig.B_ELBOW_L
	var head: int = HumanoidRig.B_HEAD
	_skeleton.set_bone_pose_rotation(shoulder, _skeleton.get_bone_pose_rotation(shoulder).slerp(
		Quaternion.from_euler(Vector3(1.04, 0.0, 0.0)), weight))
	_skeleton.set_bone_pose_rotation(elbow, _skeleton.get_bone_pose_rotation(elbow).slerp(
		Quaternion.from_euler(Vector3(0.23, 0.0, 0.0)), weight))
	_skeleton.set_bone_pose_rotation(head, _skeleton.get_bone_pose_rotation(head).slerp(
		Quaternion.from_euler(Vector3(-0.2, 0.0, 0.0)), weight))


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
	_alarm_strips = MaterialLibrary.emissive(AMBER.darkened(0.38), 0.0, false)
	GeometryKit.mesh_box(stage, Vector3(0.0, -0.16, 0.0), Vector3(14.0, 0.3, 14.0), concrete)
	GeometryKit.mesh_box(stage, Vector3(0.0, 2.0, 3.7), Vector3(14.0, 4.0, 0.3), concrete)
	for index: int in range(-4, 5):
		var x: float = float(index) * 1.45
		GeometryKit.mesh_box(stage, Vector3(x, 1.62, 3.45), Vector3(0.13, 3.25, 0.38), metal)
		GeometryKit.mesh_box(stage, Vector3(x, 2.61, 3.22), Vector3(0.045, 0.45, 0.024), glass, false)
	GeometryKit.mesh_box(stage, Vector3(0.0, 3.34, 3.0), Vector3(10.0, 0.09, 0.04), _alarm_strips, false)
	GeometryKit.mesh_box(stage, Vector3(-3.3, 1.13, 2.74), Vector3(2.4, 2.28, 0.32), metal)
	GeometryKit.mesh_box(stage, Vector3(-3.3, 1.13, 2.55), Vector3(2.12, 2.08, 0.04), concrete)
	GeometryKit.mesh_box(stage, Vector3(-3.3, 1.13, 2.50), Vector3(0.018, 2.08, 0.04), glass, false)
	for side: float in [-1.0, 1.0]:
		GeometryKit.mesh_box(stage, Vector3(0.2 + side * 1.22, 0.0, 0.0), Vector3(0.025, 0.019, 4.4), metal)
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
	_alarm = _add_light(stage, Vector3(0.0, 2.8, 1.8), AMBER, 0.0, 8.0)
	_add_light(stage, Vector3(-2.4, 2.1, -2.0), Color("e6b28a"), 2.5, 7.0)
	_add_light(stage, Vector3(-0.8, 2.6, 1.8), Color("639ee8"), 3.8, 7.0)
	for index: int in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.44
		torus.outer_radius = 0.45
		ring.mesh = torus
		ring.material_override = glass
		stage.add_child(ring)
		_rings.append(ring)

	_runner_root = Node3D.new()
	stage.add_child(_runner_root)
	_runner = HumanoidRig.new()
	_runner.style = HumanoidRig.Style.RUNNER
	_runner_root.add_child(_runner)
	_skeleton = _runner.get_node("Skeleton3D") as Skeleton3D
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
	top.offset_bottom = 43.0
	bars.add_child(top)
	_location = _make_label(top, 13, CYAN)
	_location.text = "MERIDIAN LABS   /   CONTAINMENT LEVEL"
	_location.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_location.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
