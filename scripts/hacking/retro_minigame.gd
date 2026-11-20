class_name RetroMinigame
extends Control
## Base class for HackTerminal minigames: phosphor palette, text helpers, timing and the
## success / failure / trace signals. Subclasses implement `_tick`, `_draw` and `key_pressed`.

signal succeeded()
signal failed(reason: String)
signal trace_spike(amount: float)

const PHOSPHOR: Color = Color(0.35, 1.0, 0.5)
const DIM: Color = Color(0.08, 0.32, 0.14)
const FAINT: Color = Color(0.05, 0.16, 0.08)
const AMBER: Color = Color(1.0, 0.76, 0.22)
const RED: Color = Color(1.0, 0.3, 0.25)

var difficulty: float = 1.0
var time_limit: float = 30.0
var time_left: float = 30.0
var finished: bool = false
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_left = time_limit
	_setup()


func _process(delta: float) -> void:
	if finished:
		queue_redraw()
		return
	time_left -= delta
	if time_left <= 0.0:
		_fail("TIMEOUT")
		return
	_tick(delta)
	queue_redraw()


func title() -> String:
	return "MINIGAME"


func help_text() -> String:
	return ""


func key_pressed(_keycode: Key) -> void:
	pass


func _setup() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _succeed() -> void:
	if finished:
		return
	finished = true
	succeeded.emit()


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	failed.emit(reason)


func held(primary: Key, secondary: Key) -> bool:
	return Input.is_physical_key_pressed(primary) or Input.is_physical_key_pressed(secondary)


func text(at: Vector2, value: String, font_size: int = 16, color: Color = PHOSPHOR, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	if font == null:
		return
	draw_string(font, at, value, align, width, font_size, color)


func frame(rect: Rect2, color: Color = DIM, width: float = 1.0) -> void:
	draw_rect(rect, color, false, width)


func draw_timer(at: Vector2) -> void:
	var ratio: float = clampf(time_left / time_limit, 0.0, 1.0)
	var color: Color = PHOSPHOR if ratio > 0.3 else AMBER if ratio > 0.12 else RED
	text(at, "T-%05.1f" % maxf(time_left, 0.0), 16, color)
