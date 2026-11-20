class_name WeatherSystem
extends Node
## Cycling weather. Each state defines rain, fog, cloud cover, street wetness and sensor
## visibility; the system blends smoothly between states and picks the next one with weights
## that depend on the time of day (mornings favour fog, evenings rain). Storms add lightning.
## TimeOfDay reads the blended values to compose the final sky / light / fog.

signal weather_changed(weather_name: String)
signal lightning_struck()

enum Kind { CLEAR, OVERCAST, FOG, DRIZZLE, STORM }

const NAMES: PackedStringArray = ["CLEAR", "OVERCAST", "FOG", "DRIZZLE", "STORM"]
## rain, fog density, cloud cover, wetness, visibility, lightning
static func profile(weather: Kind) -> PackedFloat32Array:
	match weather:
		Kind.CLEAR:
			return PackedFloat32Array([0.0, 0.0, 0.12, 0.22, 1.0, 0.0])
		Kind.OVERCAST:
			return PackedFloat32Array([0.0, 0.0015, 0.58, 0.3, 0.96, 0.0])
		Kind.FOG:
			return PackedFloat32Array([0.0, 0.012, 0.48, 0.38, 0.82, 0.0])
		Kind.DRIZZLE:
			return PackedFloat32Array([0.35, 0.002, 0.62, 0.68, 0.93, 0.0])
	return PackedFloat32Array([0.85, 0.006, 0.88, 0.95, 0.8, 1.0])

@export var start_kind: Kind = Kind.CLEAR
@export var min_duration: float = 70.0
@export var max_duration: float = 150.0
@export var blend_time: float = 22.0

var kind: Kind = Kind.CLEAR
var rain: float = 0.0
var fog: float = 0.0
var cloud: float = 0.12
var wetness: float = 0.22
var visibility: float = 1.0
var lightning: float = 0.0

var _target: PackedFloat32Array
var _left: float = 90.0
var _strike_left: float = 6.0
var _rng := RandomNumberGenerator.new()
var _rain_node: RainWeather
var _published_wetness: float = -1.0
var _published_rain: float = -1.0


func setup(rain_node: RainWeather) -> void:
	_rain_node = rain_node


func _ready() -> void:
	_rng.randomize()
	kind = start_kind
	_target = profile(kind)
	rain = _target[0]
	fog = _target[1]
	cloud = _target[2]
	wetness = _target[3]
	visibility = _target[4]
	_left = _rng.randf_range(min_duration, max_duration)


func force(new_kind: Kind) -> void:
	kind = new_kind
	_target = profile(kind)
	_left = _rng.randf_range(min_duration, max_duration)
	weather_changed.emit(NAMES[int(kind)])


func get_weather_name() -> String:
	return NAMES[int(kind)]


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		force(_pick_next())
	var k: float = clampf(delta / blend_time, 0.0, 1.0)
	rain = lerpf(rain, _target[0], k)
	fog = lerpf(fog, _target[1], k)
	cloud = lerpf(cloud, _target[2], k)
	visibility = lerpf(visibility, _target[4], k)
	# Streets soak quickly in rain and dry slowly afterwards.
	var wet_rate: float = 0.05 if _target[3] > wetness else 0.008
	wetness = move_toward(wetness, _target[3], wet_rate * delta)
	lightning = move_toward(lightning, 0.0, delta * 5.0)
	if _target[5] > 0.5 and rain > 0.6:
		_strike_left -= delta
		if _strike_left <= 0.0:
			_strike_left = _rng.randf_range(5.0, 14.0)
			lightning = 1.0
			lightning_struck.emit()
	if _rain_node != null and not is_equal_approx(rain, _published_rain):
		_rain_node.set_intensity(rain)
		_published_rain = rain
	if not is_equal_approx(wetness, _published_wetness):
		RenderingServer.global_shader_parameter_set(&"wetness", wetness)
		_published_wetness = wetness
	WorldConditions.weather_name = NAMES[int(kind)]
	WorldConditions.drones_grounded = kind == Kind.STORM and rain > 0.6


func _pick_next() -> Kind:
	var h: float = WorldConditions.hour
	var weights := PackedFloat32Array([3.0, 2.0, 1.0, 2.5, 1.0])
	if h >= 4.5 and h < 9.5:
		weights[int(Kind.FOG)] = 1.6
	if h >= 17.0 or h < 2.0:
		weights[int(Kind.DRIZZLE)] = 3.5
		weights[int(Kind.STORM)] = 1.6
	weights[int(kind)] *= 0.25
	var total: float = 0.0
	for w: float in weights:
		total += w
	var roll: float = _rng.randf() * total
	for i: int in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i as Kind
	return Kind.CLEAR
