class_name EndCredits
extends CanvasLayer
## A short, skippable credits sequence drawn entirely in Godot.

signal finished()

const DURATION: float = 12.0

class CreditsFrame extends Control:
	const BACKGROUND: Color = Color("#070f12")
	const PAPER: Color = Color("#eafff9")
	const GREEN: Color = Color("#73f299")
	const MUTED: Color = Color("#a9c3bf")
	const RAIL: Color = Color("#254542")

	var elapsed: float = 0.0
	var display_font: Font
	var mono_font: Font
	var _scale_factor: float

	func _draw() -> void:
		_scale_factor = minf(size.x / 740.0, size.y / 640.0)
		var opacity: float = smoothstep(0.0, 0.8, elapsed) * (1.0 - smoothstep(11.2, DURATION, elapsed))
		draw_rect(Rect2(Vector2.ZERO, size), Color(BACKGROUND, opacity))
		if _scale_factor <= 0.0:
			return

		draw_set_transform(size * 0.5, 0.0, Vector2.ONE * _scale_factor)
		var half_extent: Vector2 = size / (2.0 * _scale_factor)
		var margin: float = 38.0
		var top_left: Vector2 = Vector2(-half_extent.x + margin, -half_extent.y + margin)
		var bottom_right: Vector2 = -top_left
		_draw_frame(top_left, bottom_right, opacity)
		_draw_uplink(Vector2(0.0, -133.0), opacity)

		_draw_card("END CREDITS", "CODEX RUN", "", 0.10, 3.6, opacity)
		_draw_card("PROJECT", "noel-ult", "Built with Godot Engine", 3.6, 7.8, opacity)
		_draw_card("CODEX RUN", "Thank you for playing", "", 7.8, DURATION, opacity)

		var footer_y: float = bottom_right.y - 18.0
		_center_text(mono_font, "SPACE / ESC   SKIP CREDITS", footer_y, 14, MUTED, opacity)
		var total: float = minf(260.0, half_extent.x - margin)
		var progress_y: float = bottom_right.y
		draw_line(Vector2(-total, progress_y), Vector2(total, progress_y), Color(RAIL, opacity), 1.0)
		var progress_x: float = lerpf(-total, total, elapsed / DURATION)
		draw_line(Vector2(-total, progress_y), Vector2(progress_x, progress_y), Color(GREEN, opacity), 1.0)
		draw_circle(Vector2(progress_x, progress_y), 2.5, Color(GREEN, opacity))

	func _draw_frame(top_left: Vector2, bottom_right: Vector2, opacity: float) -> void:
		for x: float in [top_left.x, bottom_right.x]:
			for y: float in [top_left.y, bottom_right.y]:
				var point := Vector2(x, y)
				draw_line(point, point + Vector2(-signf(x) * 26.0, 0.0), Color(RAIL, opacity), 1.0, true)
				draw_line(point, point + Vector2(0.0, -signf(y) * 26.0), Color(RAIL, opacity), 1.0, true)
		var rail_y: float = top_left.y + 31.0
		draw_line(Vector2(-160.0, rail_y), Vector2(-112.0, rail_y), Color(RAIL, opacity), 1.0, true)
		draw_line(Vector2(112.0, rail_y), Vector2(160.0, rail_y), Color(RAIL, opacity), 1.0, true)
		_center_text(mono_font, "UPLINK COMPLETE", rail_y + 5.0, 13, GREEN, opacity)

	func _draw_uplink(center: Vector2, opacity: float) -> void:
		for radius: float in [27.0, 42.0, 58.0]:
			draw_arc(center, radius, 0.0, TAU, 64, Color(RAIL, opacity), 1.0, true)
		var angle: float = elapsed * 0.78 - PI * 0.5
		for point: int in 10:
			var trail_angle: float = angle - float(point) * 0.075
			var alpha: float = opacity * (1.0 - float(point) / 10.0)
			draw_arc(center, 58.0, trail_angle - 0.085, trail_angle, 6, Color(GREEN, alpha), 1.8, true)
		for wave: int in 3:
			var phase: float = fposmod(elapsed * 0.55 - float(wave) / 3.0, 1.0)
			draw_arc(center, lerpf(22.0, 59.0, phase), 0.0, TAU, 64,
				Color(GREEN, opacity * 0.3 * sin(phase * PI)), 0.8, true)
		var node: Vector2 = center + Vector2.from_angle(angle) * 58.0
		draw_circle(node, 3.5, Color(GREEN, opacity))
		var diamond: PackedVector2Array = PackedVector2Array([
			center + Vector2(0.0, -15.0),
			center + Vector2(12.0, 0.0),
			center + Vector2(0.0, 15.0),
			center + Vector2(-12.0, 0.0),
			center + Vector2(0.0, -15.0),
		])
		draw_colored_polygon(diamond.slice(0, 4), Color(GREEN, 0.17 * opacity))
		draw_polyline(diamond, Color(GREEN, opacity), 1.7, true)

	func _draw_card(kicker: String, title: String, detail: String, start: float, end: float, opacity: float) -> void:
		if elapsed < start or elapsed >= end:
			return
		var fade_in: float = smoothstep(start, start + 0.65, elapsed)
		var fade_out: float = smoothstep(end - 0.65, end, elapsed)
		var alpha: float = opacity * fade_in * (1.0 - fade_out)
		var offset: float = (1.0 - fade_in - fade_out) * 12.0
		_center_text(mono_font, kicker, -24.0 + offset, 17, GREEN, alpha)
		_center_text(display_font, title, 43.0 + offset, 52, PAPER, alpha)
		if not detail.is_empty():
			_center_text(display_font, detail, 87.0 + offset, 21, MUTED, alpha)

	func _center_text(font: Font, title: String, y: float, font_size: int, tint: Color, opacity: float) -> void:
		var readable_size: int = maxi(font_size, ceili(11.0 / _scale_factor))
		var width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, readable_size).x
		draw_string(font, Vector2(-width * 0.5, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			readable_size, Color(tint, opacity))


var _frame: CreditsFrame
var _active: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	set_process(false)
	set_process_input(false)
	_frame = CreditsFrame.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var display := SystemFont.new()
	display.font_names = PackedStringArray(["Inter", "Noto Sans", "DejaVu Sans"])
	display.font_weight = 700
	_frame.display_font = display
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["JetBrains Mono", "Noto Sans Mono", "DejaVu Sans Mono"])
	_frame.mono_font = mono
	add_child(_frame)
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func play() -> void:
	if _active:
		return
	_active = true
	_frame.elapsed = 0.0
	_frame.queue_redraw()
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
	_frame.elapsed += delta
	if _frame.elapsed >= DURATION:
		_finish()
		return
	_frame.queue_redraw()


func _finish() -> void:
	_active = false
	set_process(false)
	set_process_input(false)
	hide()
	finished.emit()
