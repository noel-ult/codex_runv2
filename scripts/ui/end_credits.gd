class_name EndCredits
extends CanvasLayer
## A closing shot of the live relay, with credits over the city skyline.

signal finished()

const DURATION: float = 12.0
const TEXT_COLOR: Color = Color("f1f6f5")
const DETAIL_COLOR: Color = Color("c7d5d6")

var _relay: UplinkStation
var _camera: Camera3D
var _previous_camera: Camera3D
var _fade: ColorRect
var _title: Label
var _credit: Label
var _thanks: Label
var _skip: Label
var _elapsed: float = 0.0
var _active: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	set_process(false)
	set_process_input(false)
	_build_overlay()
	get_viewport().size_changed.connect(_layout)
	_layout()


func play(relay: UplinkStation) -> void:
	if _active:
		return
	_relay = relay
	_previous_camera = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.fov = 58.0
	add_child(_camera)
	_elapsed = 0.0
	_active = true
	_update_shot()
	_camera.make_current()
	show()
	set_process(true)
	set_process_input(true)


func _input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_SPACE or code == KEY_ESCAPE:
			_finish()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		_finish()
		return
	_update_shot()


func _update_shot() -> void:
	# Relay-local negative Z is outside the city at all four relay sites.
	var drift: float = smoothstep(0.0, DURATION, _elapsed)
	var rise: float = smoothstep(0.7, 9.4, _elapsed)
	var offset := Vector3(lerpf(18.0, 24.0, drift), lerpf(8.0, 21.0, rise), lerpf(-24.0, -32.0, drift))
	var target := Vector3(6.2, lerpf(11.0, 34.0, rise), 0.0)
	_camera.global_position = _relay.to_global(offset)
	_camera.look_at(_relay.to_global(target))
	_fade.color.a = maxf(1.0 - smoothstep(0.0, 0.75, _elapsed), smoothstep(11.0, DURATION, _elapsed))
	_title.modulate.a = _credit_alpha(3.0, 8.4)
	_credit.modulate.a = _credit_alpha(3.7, 8.4)
	_thanks.modulate.a = _credit_alpha(8.5, 11.5)
	_skip.modulate.a = 0.82 * _credit_alpha(1.0, DURATION)


func _credit_alpha(start: float, end: float) -> float:
	return smoothstep(start, start + 0.85, _elapsed) * (1.0 - smoothstep(end - 0.75, end, _elapsed))


func _finish() -> void:
	_active = false
	set_process(false)
	set_process_input(false)
	if is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	_camera.queue_free()
	hide()
	finished.emit()


func _build_overlay() -> void:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.015, 0.024, 0.029, 0.0))
	gradient.set_color(1, Color(0.015, 0.024, 0.029, 0.72))
	var shading := GradientTexture2D.new()
	shading.gradient = gradient
	shading.fill_from = Vector2(0.0, 0.48)
	shading.fill_to = Vector2(0.0, 1.0)
	var shade := TextureRect.new()
	shade.texture = shading
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var typeface := SystemFont.new()
	typeface.font_names = PackedStringArray(["Inter", "Noto Sans", "DejaVu Sans"])
	_title = _make_label(overlay, typeface, "Codex Run", TEXT_COLOR)
	_credit = _make_label(overlay, typeface, "noel-ult  ·  Built with Godot", DETAIL_COLOR)
	_thanks = _make_label(overlay, typeface, "Thank you for playing", TEXT_COLOR)
	_skip = _make_label(overlay, typeface, "Space / Esc  ·  Skip", DETAIL_COLOR)
	_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _make_label(parent: Control, font: Font, content: String, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.015, 0.024, 0.029, 0.8))
	label.add_theme_constant_override(&"outline_size", 3)
	parent.add_child(label)
	return label


func _layout() -> void:
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var ui_scale: float = clampf(minf(view_size.x / 1100.0, view_size.y / 690.0), 0.65, 1.4)
	var margin: float = 37.0 * ui_scale
	var baseline: float = view_size.y - margin
	_title.add_theme_font_size_override(&"font_size", roundi(39.0 * ui_scale))
	_credit.add_theme_font_size_override(&"font_size", maxi(12, roundi(17.0 * ui_scale)))
	_thanks.add_theme_font_size_override(&"font_size", roundi(28.0 * ui_scale))
	_skip.add_theme_font_size_override(&"font_size", maxi(12, roundi(14.0 * ui_scale)))
	_title.position = Vector2(margin, baseline - 76.0 * ui_scale)
	_credit.position = Vector2(margin, baseline - 26.0 * ui_scale)
	_thanks.position = Vector2(margin, baseline - 43.0 * ui_scale)
	_skip.position = Vector2(view_size.x - margin - _skip.get_minimum_size().x, baseline + 7.0 * ui_scale)
