extends Node3D
## Composition root for the vertical slice.
##
## The only place where systems are introduced to each other. Every cross-system link is
## a signal connection made here, so CodexSignalSystem and PlayerController never hold
## references to Hunter AI, and Hunters never reference the Runner.

## 0 = pick a different genuine uplink relay every run.
@export var mission_seed: int = 0

@onready var _city: GreyboxCityBuilder = $NavigationRegion3D/City
@onready var _player: PlayerController = $Player
@onready var _director: HunterAIDirector = $HunterAIDirector
@onready var _mission: MissionDirector = $MissionDirector
@onready var _hud: HUD = $HUD
@onready var _terminal: HackTerminal = $HackTerminal
@onready var _time: TimeOfDay = $TimeOfDay
@onready var _weather: WeatherSystem = $Weather
@onready var _prep: PrepStationUI = $PrepStation
@onready var _echoes: Node3D = $Echoes


func _ready() -> void:
	WorldConditions.reset()
	_weather.setup($Rain as RainWeather)
	_time.setup($WorldEnvironment as WorldEnvironment, $Moon as DirectionalLight3D, _weather)
	var codex: CodexSignalSystem = _player.get_codex()
	codex.echo_container = _echoes

	for zone: DeadZone in _city.dead_zones:
		zone.runner_entered.connect(codex.enter_dead_zone)
		zone.runner_exited.connect(codex.exit_dead_zone)

	_hud.bind_codex(codex)
	_hud.bind_player(_player)
	_hud.bind_director(_director)
	_hud.bind_mission(_mission)

	# Hunter AI <- Codex signals; capture -> player respawn -> director grace period.
	_director.bind_codex(codex)
	_director.runner_caught.connect(_player.on_caught)
	_player.captured.connect(_director.on_runner_respawned)
	_director.spawn_hunters(_city.hunter_spawn_points, _city.patrol_points)

	# Mission: the genuine relay is guarded by Hunters; facility security and the uplink feed
	# positions to the Director; the hacking terminal freezes the Runner while open.
	var run_seed: int = mission_seed if mission_seed != 0 else int(Time.get_unix_time_from_system())
	var genuine: UplinkStation = _mission.setup(_player, _city.facility, _city.uplink_stations, _terminal, _director, run_seed)
	var front: Vector3 = genuine.global_position + genuine.global_basis.z * 4.5
	var side: Vector3 = genuine.global_basis.x * 9.0
	var guard_points: Array[Vector3] = [front + side, front - side, front + genuine.global_basis.z * 4.0]
	_director.set_guarded_site(front, guard_points)
	_mission.signal_reported.connect(_director.report_signal)
	_city.facility.intruder_spotted.connect(_director.report_signal)
	_player.captured.connect(_mission.on_runner_captured)
	_terminal.opened_changed.connect(func(open: bool) -> void: _player.input_enabled = not open)
	_hud.bind_terminal(_terminal)

	# Hideout: prep station + resting through the day.
	var hideout: Hideout = _city.hideout
	_prep.setup(_player, _time, _weather)
	hideout.can_rest = _time.is_daytime
	hideout.station_opened.connect(func(_actor: Node3D) -> void: _prep.open())
	hideout.rest_requested.connect(func(_actor: Node3D) -> void: _rest_until_dusk())
	_prep.rest_requested.connect(_rest_until_dusk)
	_prep.opened_changed.connect(func(open: bool) -> void:
		_player.input_enabled = not open
		_hud.visible = not open)
	_hud.bind_environment(_time, _weather)
	_hud.set_marker(&"hideout", hideout.get_marker_position(), "HIDEOUT", Color(0.95, 0.85, 0.6), true)
	_time.phase_changed.connect(_on_phase_changed)
	_weather.weather_changed.connect(_on_weather_changed)
	_on_phase_changed(_time.phase)
	_mission.start()


## Daylight is dangerous: Releases reach further and come sooner, so lie low in the hideout.
func _on_phase_changed(phase: StringName) -> void:
	var codex: CodexSignalSystem = _player.get_codex()
	match phase:
		TimeOfDay.PHASE_DAY:
			codex.daylight_radius_scale = 1.5
			codex.daylight_interval_scale = 0.7
			_hud.show_radio("Full daylight. The Codex burns louder in the sun - Releases reach further and come faster. Lie low at the hideout (west edge) or rest until dusk.")
		TimeOfDay.PHASE_DAWN:
			codex.daylight_radius_scale = 1.2
			codex.daylight_interval_scale = 0.85
			_hud.show_radio("Dawn is breaking. Get to the hideout before the city wakes up.")
		TimeOfDay.PHASE_DUSK:
			codex.daylight_radius_scale = 1.2
			codex.daylight_interval_scale = 0.85
			_hud.show_radio("Dusk. Prep your gear - night is when the Runner moves.")
		_:
			codex.daylight_radius_scale = 1.0
			codex.daylight_interval_scale = 1.0


func _on_weather_changed(weather_name: String) -> void:
	match weather_name:
		"FOG":
			_hud.show_radio("Fog rolling in - cameras and drones can barely see. Good cover.")
		"STORM":
			_hud.show_radio("Storm front - Hunter drones are grounded and sensors are half-blind.")
		"CLEAR":
			_hud.show_radio("Skies clearing. Sensors at full range.")


func _rest_until_dusk() -> void:
	if not _time.is_daytime():
		return
	_player.input_enabled = false
	_prep.play_rest_fade(func() -> void:
		_time.skip_to(19.0)
		_player.get_codex().reset_resonance()
		_player.input_enabled = true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart_slice"):
		get_tree().reload_current_scene()
