class_name FirewallOverrideGame
extends RetroMinigame
## Override the firewall by confirming three numbered prompts.

const PROMPT_COUNT: int = 3
const WRONG_KEY_TRACE: float = 10.0

var _prompts: Array[int] = []
var _confirmed: int = 0
var _wrong_key: bool = false


func title() -> String:
	return "FIREWALL OVERRIDE"


func help_text() -> String:
	return "1–3  match the displayed number"


func _setup() -> void:
	time_limit = 25.0 / difficulty
	time_left = time_limit
	for index: int in PROMPT_COUNT:
		_prompts.append(randi_range(1, 3))


func key_pressed(keycode: Key) -> void:
	if finished or keycode < KEY_1 or keycode > KEY_3:
		return
	if keycode - KEY_1 + 1 != _prompts[_confirmed]:
		_wrong_key = true
		trace_spike.emit(WRONG_KEY_TRACE)
		return
	_wrong_key = false
	_confirmed += 1
	if _confirmed == _prompts.size():
		_succeed()


func _draw() -> void:
	var panel := Rect2(20.0, 45.0, size.x - 40.0, size.y - 75.0)
	draw_rect(panel, Color("04110a"))
	frame(panel)
	text(Vector2(20.0, 28.0), "CONFIRMED  %d / %d" % [_confirmed, PROMPT_COUNT])
	draw_timer(Vector2(size.x - 130.0, 28.0))
	if _confirmed == _prompts.size():
		return
	text(Vector2(0.0, 145.0), "PRESS THE DISPLAYED NUMBER", 18, PHOSPHOR,
		HORIZONTAL_ALIGNMENT_CENTER, size.x)
	text(Vector2(0.0, 300.0), "[ %d ]" % _prompts[_confirmed], 64, AMBER,
		HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if _wrong_key:
		text(Vector2(0.0, 367.0), "WRONG KEY  ·  TRACE +%d%%" % int(WRONG_KEY_TRACE),
			16, RED, HORIZONTAL_ALIGNMENT_CENTER, size.x)
