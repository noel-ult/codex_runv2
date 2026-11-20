class_name TimeOfDay
extends Node
## Day / night cycle. Advances a 24 h clock (nights run slower than days so operations have
## time, days pass faster) and is the single writer of the sky, sun, moon, ambient light,
## fog, exposure, street lamps and the `night_factor` global shader parameter (lit windows).
## Weather (cloud, fog, rain, lightning) from WeatherSystem is layered on top.

signal phase_changed(phase: StringName)
signal clock_tick(hour: float)

const PHASE_NIGHT: StringName = &"night"
const PHASE_DAWN: StringName = &"dawn"
const PHASE_DAY: StringName = &"day"
const PHASE_DUSK: StringName = &"dusk"
const ENVIRONMENT_INTERVAL: float = 0.1

@export var start_hour: float = 21.5
@export var night_seconds_per_hour: float = 50.0
@export var day_seconds_per_hour: float = 22.0

var hour: float = 21.5
var phase: StringName = PHASE_NIGHT
var night: float = 1.0

var _env: Environment
var _sky: ProceduralSkyMaterial
var _moon: DirectionalLight3D
var _sun: DirectionalLight3D
var _weather: WeatherSystem
var _lamps_on: bool = true
var _bulb: StandardMaterial3D
var _tick_left: float = 0.0
var _environment_left: float = 0.0
var _moon_energy: float = 0.7


func setup(world_environment: WorldEnvironment, moon: DirectionalLight3D, weather: WeatherSystem) -> void:
	_env = world_environment.environment
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_moon = moon
	_moon_energy = moon.light_energy
	_weather = weather
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 140.0
	_sun.light_volumetric_fog_energy = 0.6
	_moon.get_parent().add_child(_sun)
	_bulb = MaterialLibrary.emissive(Color(1.0, 0.78, 0.5), 6.0)
	hour = start_hour
	phase = _phase_for(hour)
	_apply_environment()
	_publish_conditions()


## Jumps the clock forward to `target_hour` (wrapping past midnight).
func skip_to(target_hour: float) -> void:
	hour = wrapf(target_hour, 0.0, 24.0)
	_apply_environment()
	_publish_conditions()


func is_daytime() -> bool:
	return phase == PHASE_DAY or phase == PHASE_DAWN


static func format_clock(h: float) -> String:
	var total_minutes: int = int(h * 60.0) % (24 * 60)
	return "%02d:%02d" % [floori(total_minutes / 60.0), total_minutes % 60]


func _process(delta: float) -> void:
	if _env == null:
		return
	var seconds_per_hour: float = lerpf(day_seconds_per_hour, night_seconds_per_hour, night)
	hour = wrapf(hour + delta / seconds_per_hour, 0.0, 24.0)
	_environment_left -= delta
	# Sky, ambient and fog change slowly. Batch those RenderingServer setters while
	# keeping time, sensor visibility, phase transitions and lightning responsive.
	if _environment_left <= 0.0 or phase != _phase_for(hour) or (_weather != null and _weather.lightning > 0.0):
		_apply_environment()
	_publish_conditions()
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = 0.25
		clock_tick.emit(hour)


static func night_factor_for(h: float) -> float:
	if h >= 7.0 and h < 18.0:
		return 0.0
	if h >= 5.5 and h < 7.0:
		return 1.0 - (h - 5.5) / 1.5
	if h >= 18.0 and h < 19.5:
		return (h - 18.0) / 1.5
	return 1.0


func _phase_for(h: float) -> StringName:
	if h >= 5.5 and h < 7.0:
		return PHASE_DAWN
	if h >= 7.0 and h < 18.0:
		return PHASE_DAY
	if h >= 18.0 and h < 19.5:
		return PHASE_DUSK
	return PHASE_NIGHT


func _apply_environment() -> void:
	_environment_left = ENVIRONMENT_INTERVAL
	night = night_factor_for(hour)
	var new_phase: StringName = _phase_for(hour)
	if new_phase != phase:
		phase = new_phase
		phase_changed.emit(phase)
	var cloud: float = _weather.cloud if _weather != null else 0.2
	var fog: float = _weather.fog if _weather != null else 0.0
	var flash: float = _weather.lightning if _weather != null else 0.0
	var twilight: float = 1.0 - absf(night * 2.0 - 1.0)
	var day: float = 1.0 - night

	# Sun arc: rises in the east at 06:00, sets in the west at 18:00.
	var elevation: float = (hour - 6.0) / 12.0 * PI
	var to_sun := Vector3(cos(elevation), sin(elevation), 0.35).normalized()
	_sun.global_basis = Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.BACK)
	var height: float = clampf(sin(elevation) * 2.5, 0.0, 1.0)
	_sun.light_energy = height * 1.95 * (1.0 - cloud * 0.45)
	_sun.light_color = Color(1.0, 0.55, 0.32).lerp(Color(1.0, 0.96, 0.9), clampf(sin(elevation) * 2.0, 0.0, 1.0))
	_sun.visible = _sun.light_energy > 0.01
	_sun.shadow_enabled = night < 0.5
	_moon.light_energy = _moon_energy * 1.3 * night * (1.0 - cloud * 0.28)
	_moon.shadow_enabled = night >= 0.5
	_moon.visible = _moon.light_energy > 0.01

	var top: Color = Color(0.28, 0.5, 0.82).lerp(Color(0.07, 0.09, 0.15), night)
	var horizon: Color = Color(0.68, 0.76, 0.87).lerp(Color(0.29, 0.33, 0.42), night)
	horizon = horizon.lerp(Color(0.92, 0.52, 0.34), twilight * 0.75 * (1.0 - cloud * 0.6))
	var overcast: Color = Color(0.49, 0.53, 0.58).lerp(Color(0.11, 0.13, 0.17), night)
	top = top.lerp(overcast, cloud * 0.85)
	horizon = horizon.lerp(overcast * 1.15, cloud * 0.7)
	var lightning_tint: Color = Color(0.6, 0.65, 0.85) * flash
	_sky.sky_top_color = top + lightning_tint
	_sky.sky_horizon_color = horizon + lightning_tint
	_sky.ground_horizon_color = horizon * 0.6
	_sky.ground_bottom_color = horizon * 0.15

	_env.ambient_light_color = Color(0.68, 0.73, 0.8).lerp(Color(0.62, 0.69, 0.82), night).lerp(Color(0.54, 0.58, 0.63), cloud * 0.35 * day)
	_env.ambient_light_energy = lerpf(1.18, 1.62, night) + flash * 2.5
	_env.ambient_light_sky_contribution = lerpf(0.62, 0.48, night)
	_env.tonemap_exposure = lerpf(1.04, 1.55, night)
	_env.glow_intensity = lerpf(0.35, 0.7, night)
	_env.fog_density = 0.0012 + fog * 0.18
	_env.fog_light_color = Color(0.65, 0.7, 0.78).lerp(Color(0.18, 0.21, 0.28), night).lerp(Color(0.56, 0.6, 0.66) * lerpf(1.0, 0.35, night), cloud * 0.45)
	_env.volumetric_fog_density = 0.0023 + fog * 0.35
	_env.volumetric_fog_emission = Color(0.035, 0.042, 0.05).lerp(Color(0.016, 0.02, 0.03), night)

	var lamps: bool = night > 0.35
	if lamps != _lamps_on:
		_lamps_on = lamps
		for node: Node in get_tree().get_nodes_in_group(&"street_lights"):
			var lamp := node as Light3D
			if lamp != null:
				lamp.visible = lamps
	_bulb.emission_energy_multiplier = 6.0 if lamps else 0.3

	RenderingServer.global_shader_parameter_set(&"night_factor", night)


func _publish_conditions() -> void:
	var factor: float = night_factor_for(hour)
	WorldConditions.hour = hour
	WorldConditions.night_factor = factor
	WorldConditions.is_day = factor < 0.5
	WorldConditions.visibility = (_weather.visibility if _weather != null else 1.0) * lerpf(1.2, 1.0, factor)
