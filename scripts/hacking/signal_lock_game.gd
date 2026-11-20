class_name SignalLockGame
extends RetroMinigame
## Oscilloscope carrier-matching: tune your waveform's frequency (A/D) and phase (W/S) onto the
## drifting target carrier and hold the lock until the handshake completes.

const FREQ_MIN: float = 1.0
const FREQ_MAX: float = 5.0

var lock_required: float = 1.8
var tolerance: float = 0.09

var _target_freq: float = 3.0
var _target_phase: float = 0.0
var _freq: float = 1.5
var _phase: float = 2.0
var _lock: float = 0.0
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func title() -> String:
	return "SIGNAL LOCK"


func help_text() -> String:
	return "A/D  frequency    W/S  phase    hold the carrier lock"


func _setup() -> void:
	_rng.randomize()
	time_limit = 16.0 / difficulty
	time_left = time_limit
	_target_freq = _rng.randf_range(2.0, 4.2)
	_target_phase = _rng.randf_range(0.0, TAU)
	_freq = clampf(_target_freq + (1.6 if _rng.randf() < 0.5 else -1.6), FREQ_MIN, FREQ_MAX)
	_phase = _target_phase + PI
	tolerance = 0.09 / sqrt(difficulty)


func _tick(delta: float) -> void:
	_time += delta
	if held(KEY_A, KEY_LEFT):
		_freq -= 1.1 * delta
	if held(KEY_D, KEY_RIGHT):
		_freq += 1.1 * delta
	if held(KEY_W, KEY_UP):
		_phase += 1.8 * delta
	if held(KEY_S, KEY_DOWN):
		_phase -= 1.8 * delta
	_freq = clampf(_freq, FREQ_MIN, FREQ_MAX)
	_target_phase += 0.25 * difficulty * delta
	_target_freq = clampf(_target_freq + sin(_time * 0.7) * 0.12 * difficulty * delta, FREQ_MIN + 0.3, FREQ_MAX - 0.3)
	if _error() < tolerance:
		_lock += delta
		if _lock >= lock_required:
			_succeed()
	else:
		_lock = maxf(_lock - delta * 1.5, 0.0)


func _error() -> float:
	var phase_error: float = absf(angle_difference(_phase, _target_phase)) / PI
	return absf(_freq - _target_freq) / (FREQ_MAX - FREQ_MIN) + phase_error * 0.5


func _draw() -> void:
	var area := Rect2(Vector2(20.0, 40.0), Vector2(size.x - 40.0, size.y - 120.0))
	draw_rect(area, Color(0.0, 0.03, 0.01))
	for i: int in 11:
		var x: float = area.position.x + area.size.x * float(i) / 10.0
		draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), FAINT, 1.0)
	for i: int in 7:
		var y: float = area.position.y + area.size.y * float(i) / 6.0
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), FAINT, 1.0)
	frame(area)
	var mid: float = area.get_center().y
	var amp: float = area.size.y * 0.36
	var target_points := PackedVector2Array()
	var player_points := PackedVector2Array()
	var steps: int = 160
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		var x: float = area.position.x + area.size.x * t
		target_points.append(Vector2(x, mid - sin(t * TAU * _target_freq + _target_phase) * amp))
		player_points.append(Vector2(x, mid - sin(t * TAU * _freq + _phase) * amp * 0.94))
	draw_polyline(target_points, AMBER * Color(1, 1, 1, 0.75), 2.0, true)
	var locked: bool = _error() < tolerance
	draw_polyline(player_points, PHOSPHOR if locked else PHOSPHOR * Color(1, 1, 1, 0.7), 2.5, true)
	text(Vector2(20.0, 28.0), "CARRIER  %.2f Hz   PHASE %+04d°" % [_target_freq, int(rad_to_deg(wrapf(_target_phase, -PI, PI)))], 16, AMBER)
	text(Vector2(size.x - 20.0 - 300.0, 28.0), "YOURS  %.2f Hz   %+04d°" % [_freq, int(rad_to_deg(wrapf(_phase, -PI, PI)))], 16, PHOSPHOR, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	var bar := Rect2(Vector2(20.0, size.y - 60.0), Vector2(size.x - 200.0, 16.0))
	frame(bar)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(_lock / lock_required, 0.0, 1.0), bar.size.y)), PHOSPHOR if locked else DIM)
	text(Vector2(bar.position.x, bar.position.y - 6.0), "LOCK" if locked else "SEARCHING...", 14, PHOSPHOR if locked else AMBER)
	draw_timer(Vector2(size.x - 160.0, size.y - 45.0))
