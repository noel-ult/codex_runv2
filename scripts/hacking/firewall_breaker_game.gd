class_name FirewallBreakerGame
extends RetroMinigame
## Breakout against the HunterNet firewall: bounce the probe packet (A/D paddle, Space to
## launch) through the ICE layers and destroy every CORE node. Dropped packets raise the trace.

const COLS: int = 9
const ROWS: int = 4

var lives: int = 3

var _bricks: Array[Rect2] = []
var _brick_kind: PackedInt32Array = PackedInt32Array()
var _paddle_x: float = 0.0
var _ball: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _launched: bool = false
var _field: Rect2


func title() -> String:
	return "FIREWALL BREAKER"


func help_text() -> String:
	return "A/D  move    SPACE  launch probe    destroy all CORE nodes"


func _setup() -> void:
	time_limit = 70.0 / difficulty
	time_left = time_limit
	_field = Rect2(Vector2(20.0, 40.0), Vector2(maxf(size.x - 40.0, 600.0), maxf(size.y - 110.0, 300.0)))
	var w: float = _field.size.x / float(COLS)
	for row: int in ROWS:
		for col: int in COLS:
			_bricks.append(Rect2(_field.position + Vector2(col * w + 3.0, 30.0 + row * 24.0), Vector2(w - 6.0, 18.0)))
			_brick_kind.append(2 if row == 0 else (1 if row == 1 else 0))
	_paddle_x = _field.get_center().x
	_reset_ball()


func _reset_ball() -> void:
	_launched = false
	_ball = Vector2(_paddle_x, _field.end.y - 34.0)
	_velocity = Vector2.ZERO


func key_pressed(keycode: Key) -> void:
	if keycode == KEY_SPACE and not _launched and not finished:
		_launched = true
		var speed: float = 340.0 * difficulty
		_velocity = Vector2(randf_range(-0.5, 0.5), -1.0).normalized() * speed


func _tick(delta: float) -> void:
	if _cores_left() == 0:
		_succeed()
		return
	if _field.size.x < size.x - 60.0 and size.x > 0.0:
		_field.size.x = size.x - 40.0
	var move: float = 0.0
	if held(KEY_A, KEY_LEFT):
		move -= 1.0
	if held(KEY_D, KEY_RIGHT):
		move += 1.0
	_paddle_x = clampf(_paddle_x + move * 560.0 * delta, _field.position.x + 60.0, _field.end.x - 60.0)
	if not _launched:
		_ball = Vector2(_paddle_x, _field.end.y - 34.0)
		return
	var substeps: int = 3
	for i: int in substeps:
		_step(delta / float(substeps))


func _step(dt: float) -> void:
	_ball += _velocity * dt
	if _ball.x < _field.position.x + 6.0 or _ball.x > _field.end.x - 6.0:
		_velocity.x = -_velocity.x
		_ball.x = clampf(_ball.x, _field.position.x + 6.0, _field.end.x - 6.0)
	if _ball.y < _field.position.y + 6.0:
		_velocity.y = absf(_velocity.y)
	var paddle := Rect2(Vector2(_paddle_x - 55.0, _field.end.y - 24.0), Vector2(110.0, 10.0))
	if _velocity.y > 0.0 and paddle.grow(6.0).has_point(_ball):
		var offset: float = (_ball.x - _paddle_x) / 55.0
		_velocity = Vector2(offset * 0.9, -1.0).normalized() * _velocity.length() * 1.02
	for i: int in _bricks.size():
		if _brick_kind[i] < 0:
			continue
		var brick: Rect2 = _bricks[i]
		if brick.grow(6.0).has_point(_ball):
			if _brick_kind[i] == 1:
				_brick_kind[i] = 0
			else:
				_brick_kind[i] = -1
			var from_side: bool = _ball.x < brick.position.x or _ball.x > brick.end.x
			if from_side:
				_velocity.x = -_velocity.x
			else:
				_velocity.y = -_velocity.y
			break
	if _cores_left() == 0:
		_succeed()
		return
	if _ball.y > _field.end.y:
		lives -= 1
		trace_spike.emit(12.0)
		if lives <= 0:
			_fail("PROBE LOST")
		else:
			_reset_ball()


func _cores_left() -> int:
	var count: int = 0
	for kind: int in _brick_kind:
		if kind == 2:
			count += 1
	return count


func _draw() -> void:
	draw_rect(_field, Color(0.0, 0.03, 0.01))
	frame(_field)
	for i: int in _bricks.size():
		var kind: int = _brick_kind[i]
		if kind < 0:
			continue
		var color: Color = RED if kind == 2 else (AMBER if kind == 1 else DIM.lightened(0.3))
		draw_rect(_bricks[i], color * Color(1, 1, 1, 0.85))
		frame(_bricks[i], color.lightened(0.3))
		if kind == 2:
			text(_bricks[i].position + Vector2(4.0, 14.0), "CORE", 11, Color(0.05, 0.0, 0.0), HORIZONTAL_ALIGNMENT_CENTER, _bricks[i].size.x - 8.0)
	draw_rect(Rect2(Vector2(_paddle_x - 55.0, _field.end.y - 24.0), Vector2(110.0, 10.0)), PHOSPHOR)
	draw_circle(_ball, 6.0, PHOSPHOR)
	text(Vector2(20.0, 28.0), "CORE NODES %d    PROBES %d" % [_cores_left(), lives], 16, PHOSPHOR)
	if not _launched and not finished:
		text(Vector2(_field.position.x, _field.end.y - 50.0), "[SPACE] LAUNCH PROBE", 16, AMBER, HORIZONTAL_ALIGNMENT_CENTER, _field.size.x)
	draw_timer(Vector2(size.x - 160.0, 28.0))
