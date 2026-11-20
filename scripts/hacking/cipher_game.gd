class_name CipherGame
extends RetroMinigame
## Mastermind-style key recovery: deduce the 4-glyph database cipher. A/D select a slot,
## W/S cycle glyphs, ENTER submits. ● = right glyph in the right slot, ○ = right glyph elsewhere.
## Every wrong guess leaks trace; running out of attempts fails the stage.

const GLYPHS: PackedStringArray = ["3", "7", "A", "C", "E", "F"]
const SLOTS: int = 4

var max_attempts: int = 8

var _code: PackedInt32Array = PackedInt32Array()
var _guess: PackedInt32Array = PackedInt32Array([0, 1, 2, 3])
var _cursor: int = 0
var _history: Array[PackedInt32Array] = []
var _feedback: Array[Vector2i] = []


func title() -> String:
	return "CIPHER RECOVERY"


func help_text() -> String:
	return "A/D  slot    W/S  glyph    ENTER  submit    ● exact  ○ misplaced    no repeats"


func _setup() -> void:
	time_limit = 90.0 / difficulty
	time_left = time_limit
	max_attempts = 8 if difficulty < 1.2 else 7
	var pool: Array[int] = [0, 1, 2, 3, 4, 5]
	pool.shuffle()
	_code = PackedInt32Array(pool.slice(0, SLOTS))


func get_code() -> PackedInt32Array:
	return _code


func key_pressed(keycode: Key) -> void:
	if finished:
		return
	match keycode:
		KEY_A, KEY_LEFT:
			_cursor = wrapi(_cursor - 1, 0, SLOTS)
		KEY_D, KEY_RIGHT:
			_cursor = wrapi(_cursor + 1, 0, SLOTS)
		KEY_W, KEY_UP:
			_guess[_cursor] = wrapi(_guess[_cursor] + 1, 0, GLYPHS.size())
		KEY_S, KEY_DOWN:
			_guess[_cursor] = wrapi(_guess[_cursor] - 1, 0, GLYPHS.size())
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_submit()


func _submit() -> void:
	var exact: int = 0
	var partial: int = 0
	var matched: PackedByteArray = PackedByteArray()
	matched.resize(SLOTS)
	for i: int in SLOTS:
		if _guess[i] == _code[i]:
			exact += 1
			matched[i] = 1
	for i: int in SLOTS:
		if _guess[i] == _code[i]:
			continue
		for j: int in SLOTS:
			if matched[j] == 0 and _guess[i] == _code[j]:
				partial += 1
				matched[j] = 1
				break
	_history.append(_guess.duplicate())
	_feedback.append(Vector2i(exact, partial))
	if exact == SLOTS:
		_succeed()
		return
	trace_spike.emit(5.0)
	if _history.size() >= max_attempts:
		_fail("CIPHER REJECTED")


func _draw() -> void:
	text(Vector2(20.0, 28.0), "ATTEMPTS %d / %d" % [_history.size(), max_attempts], 16, PHOSPHOR)
	draw_timer(Vector2(size.x - 160.0, 28.0))
	var cell: float = 46.0
	var left: float = size.x * 0.5 - (SLOTS * cell + 160.0) * 0.5
	var y: float = 50.0
	for row: int in max_attempts:
		var row_y: float = y + row * 38.0
		var current: bool = row == _history.size()
		for i: int in SLOTS:
			var rect := Rect2(Vector2(left + i * cell, row_y), Vector2(cell - 8.0, 30.0))
			var glyph: String = ""
			var color: Color = FAINT
			if row < _history.size():
				glyph = GLYPHS[_history[row][i]]
				color = PHOSPHOR
			elif current:
				glyph = GLYPHS[_guess[i]]
				color = AMBER if i == _cursor else PHOSPHOR
			frame(rect, color if current or row < _history.size() else FAINT, 2.0 if current and i == _cursor else 1.0)
			text(rect.position + Vector2(0.0, 23.0), glyph, 20, color, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		if row < _feedback.size():
			var fb: Vector2i = _feedback[row]
			for p: int in SLOTS:
				var at := Vector2(left + SLOTS * cell + 20.0 + p * 18.0, row_y + 15.0)
				if p < fb.x:
					draw_circle(at, 6.0, PHOSPHOR)
				elif p < fb.x + fb.y:
					draw_arc(at, 6.0, 0.0, TAU, 16, AMBER, 2.0)
				else:
					draw_arc(at, 6.0, 0.0, TAU, 16, FAINT, 1.0)
