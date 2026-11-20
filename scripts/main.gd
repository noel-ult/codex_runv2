extends Node3D
## Composition root for the vertical slice.
##
## The only place where systems are introduced to each other. Every cross-system link is
## a signal connection made here, so CodexSignalSystem and PlayerController never hold
## references to Hunter AI, and Hunters never reference the Runner.

## 0 = pick a different genuine uplink relay every run.
@export var mission_seed: int = 0

const GRAPHICS_SETTINGS: String = "user://graphics.cfg"

@onready var _city: GreyboxCityBuilder = $NavigationRegion3D/City
@onready var _player: PlayerController = $Player
@onready var _director: HunterAIDirector = $HunterAIDirector
@onready var _mission: MissionDirector = $MissionDirector
@onready var _hud: HUD = $HUD
@onready var _terminal: HackTerminal = $HackTerminal
@onready var _time: TimeOfDay = $TimeOfDay
@onready var _weather: WeatherSystem = $Weather
@onready var _prep: PrepStationUI = $PrepStation
@onready var _pause: PauseMenu = $PauseMenu
@onready var _echoes: Node3D = $Echoes

var _economy: RunnerEconomy
var _shop: SupplyShopUI
var _jobs: DayJobBoard
var _field_contracts: FieldContracts
var _counter: SupplyCounter
var _rest_in_progress: bool = false


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
	_mission.mission_completed.connect(func(_elapsed: float, _captures: int) -> void:
		if _mission.demo_upload:
			_hud.show_ending_restart_prompt())
	_pause.can_pause = func() -> bool: return not _terminal.is_open and not _prep.is_open and not _shop.is_open and not _rest_in_progress
	_pause.restart_requested.connect(_restart_run)
	_pause.graphics_preset_changed.connect(_save_graphics_preset)
	_load_graphics_preset()
	_setup_services()

	# Hunter AI <- Codex signals; capture -> player respawn -> director grace period.
	_director.bind_codex(codex)
	_director.runner_is_sheltered = _city.hideout.protects_runner.bind(_player)
	_player.shelter_check = _director.runner_is_sheltered
	_director.runner_caught.connect(func() -> void:
		if not _mission.demo_upload:
			_player.on_caught())
	_player.captured.connect(_director.on_runner_respawned)
	_director.spawn_hunters(_city.hunter_spawn_points, _city.patrol_points)

	# Mission: the genuine relay is guarded by Hunters; facility security and the uplink feed
	# positions to the Director; the hacking terminal freezes the Runner while open.
	var run_seed: int = mission_seed if mission_seed != 0 else int(Time.get_unix_time_from_system())
	var genuine: UplinkStation = _mission.setup(_player, _city.facility, _city.uplink_stations, _terminal, _director, run_seed)
	_mission.suit_extraction_changed.connect(_director.set_suit_extraction_enabled)
	_mission.relay_spoofed.connect(_director.deploy_relay_spoof.bind(MissionDirector.RELAY_SPOOF_SECONDS))
	var front: Vector3 = genuine.global_position + genuine.global_basis.z * 4.5
	var side: Vector3 = genuine.global_basis.x * 9.0
	var guard_points: Array[Vector3] = [front + side, front - side, front + genuine.global_basis.z * 4.0]
	_director.set_guarded_site(front, guard_points)
	_mission.signal_reported.connect(_director.report_signal)
	_city.facility.intruder_spotted.connect(_director.report_signal)
	_player.captured.connect(_mission.on_runner_captured)
	_player.captured.connect(func(total: int) -> void:
		if _prep.is_open:
			_prep.close()
		if _shop.is_open:
			_shop.close()
		_jobs.on_runner_captured(total)
		_refresh_modal_input())
	_terminal.opened_changed.connect(func(_open: bool) -> void: _refresh_modal_input())
	_hud.bind_terminal(_terminal)

	# Hideout: prep station + resting through the day.
	var hideout: Hideout = _city.hideout
	_mission.bind_decoder(hideout)
	_prep.setup(_player, _time, _weather)
	hideout.can_rest = _time.is_daytime
	hideout.station_opened.connect(func(_actor: Node3D) -> void: _prep.open())
	hideout.rest_requested.connect(func(_actor: Node3D) -> void: _rest_until_dusk())
	hideout.morning_requested.connect(func(_actor: Node3D) -> void: _wait_until_morning())
	_prep.rest_requested.connect(_rest_until_dusk)
	_prep.opened_changed.connect(func(_open: bool) -> void: _refresh_modal_input())
	_hud.bind_environment(_time, _weather)
	_hud.set_marker(&"hideout", hideout.get_marker_position(), "HIDEOUT", Color(0.95, 0.85, 0.6), true)
	_time.phase_changed.connect(_on_phase_changed)
	_weather.weather_changed.connect(_on_weather_changed)
	_on_phase_changed(_time.phase)
	var intro := IntroCutscene.new()
	add_child(intro)
	_player.input_enabled = false
	_hud.hide()
	get_tree().paused = true
	intro.finished.connect(_finish_intro.bind(intro), CONNECT_ONE_SHOT)
	intro.play()


func _finish_intro(intro: IntroCutscene) -> void:
	intro.queue_free()
	get_tree().paused = false
	_refresh_modal_input()
	_mission.start()


func _setup_services() -> void:
	_economy = RunnerEconomy.new()
	_economy.name = "RunnerEconomy"
	add_child(_economy)
	_economy.feedback.connect(_hud.show_toast)
	_hud.bind_economy(_economy)

	_shop = SupplyShopUI.new()
	_shop.name = "SupplyShop"
	add_child(_shop)
	_shop.setup(_player, _economy)
	_shop.opened_changed.connect(func(_open: bool) -> void: _refresh_modal_input())
	_counter = _city.supply_counter
	_counter.shop_requested.connect(func(_actor: Node3D) -> void:
		if not _mission.completed and not _player.is_driving():
			_shop.open())
	_hud.set_marker(&"shop", _counter.get_marker_position(), "SUPPLIES", Color(0.44, 0.98, 0.78), true)

	_jobs = DayJobBoard.new()
	_jobs.name = "DayJobs"
	_jobs.position = Vector3(-8.1, 0.1, 40.0)
	add_child(_jobs)
	_jobs.payout_requested.connect(func(amount: int) -> void: _economy.earn(amount, "Courier delivery"))
	_jobs.marker_changed.connect(_hud.set_marker)
	_jobs.feedback.connect(_hud.show_radio)
	_jobs.status_changed.connect(_hud.set_job_status)
	_jobs.setup(_player, func() -> bool: return _time.is_daytime() and not _mission.completed and not _rest_in_progress)

	_field_contracts = FieldContracts.new()
	_field_contracts.name = "FieldContracts"
	add_child(_field_contracts)
	_field_contracts.reward_requested.connect(_economy.earn)
	_field_contracts.marker_changed.connect(_hud.set_marker)
	_field_contracts.status_changed.connect(_hud.set_contract_status)
	_field_contracts.feedback.connect(_hud.show_radio)
	_player.captured.connect(_field_contracts.on_runner_captured)
	_field_contracts.setup(_player)
	for vehicle: DriveableVehicle in _city.driveable_vehicles:
		vehicle.telemetry_changed.connect(_hud.set_vehicle_telemetry)


func _refresh_modal_input() -> void:
	_player.input_enabled = not _terminal.is_open and not _prep.is_open and not _shop.is_open and not _rest_in_progress and not _mission.completed and not _mission.demo_upload
	_hud.visible = not _prep.is_open and not _shop.is_open


func _load_graphics_preset() -> void:
	var settings := ConfigFile.new()
	settings.load(GRAPHICS_SETTINGS)
	var preset: int = clampi(int(settings.get_value("graphics", "preset", PauseMenu.GraphicsPreset.DETAIL)), 0, 1)
	_pause.select_graphics_preset(preset)
	_apply_graphics_preset(preset)


func _save_graphics_preset(preset: int) -> void:
	_apply_graphics_preset(preset)
	var settings := ConfigFile.new()
	settings.set_value("graphics", "preset", preset)
	var result: Error = settings.save(GRAPHICS_SETTINGS)
	if result != OK:
		push_warning("Could not save graphics settings: %s" % error_string(result))


func _apply_graphics_preset(preset: int) -> void:
	var detail: bool = preset == PauseMenu.GraphicsPreset.DETAIL
	var environment: Environment = ($WorldEnvironment as WorldEnvironment).environment
	environment.ssr_enabled = detail
	environment.ssao_enabled = detail
	environment.volumetric_fog_enabled = detail
	var viewport: Viewport = get_viewport()
	viewport.scaling_3d_scale = 1.0 if detail else 0.8
	viewport.msaa_3d = Viewport.MSAA_2X if detail else Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if detail else Viewport.SCREEN_SPACE_AA_FXAA


## Daylight is dangerous: Releases reach further and come sooner, so lie low in the hideout.
func _on_phase_changed(phase: StringName) -> void:
	var codex: CodexSignalSystem = _player.get_codex()
	match phase:
		TimeOfDay.PHASE_DAY:
			codex.daylight_radius_scale = 1.5
			codex.daylight_interval_scale = 0.7
			_hud.show_radio("Full daylight. The Codex burns louder in the sun. Take courier work at the southwest depot for credits, or rest at Storage 07 until dusk.")
		TimeOfDay.PHASE_DAWN:
			codex.daylight_radius_scale = 1.2
			codex.daylight_interval_scale = 0.85
			_hud.show_radio("Dawn is breaking. Courier shifts are open at the southwest depot; earn credits for supplies before the night operation.")
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
			_hud.show_radio("Fog rolling in. Cameras and drones have shorter range.")
		"STORM":
			_hud.show_radio("Storm front. Hunter drones are grounded and security range is reduced.")
		"CLEAR":
			_hud.show_radio("Skies clearing. Sensors at full range.")


func _rest_until_dusk() -> void:
	if not _time.is_daytime() or _rest_in_progress:
		return
	_rest_in_progress = true
	_refresh_modal_input()
	var midpoint: Callable = func() -> void:
		_time.skip_to(19.0)
		_player.get_codex().reset_resonance()
	var finished: Callable = func() -> void:
		_rest_in_progress = false
		_refresh_modal_input()
	_prep.play_rest_fade(midpoint, finished)


func _wait_until_morning() -> void:
	if _time.is_daytime() or _rest_in_progress:
		return
	_rest_in_progress = true
	_refresh_modal_input()
	var midpoint: Callable = func() -> void:
		_time.skip_to(6.0)
		_player.get_codex().reset_resonance()
	var finished: Callable = func() -> void:
		_rest_in_progress = false
		_refresh_modal_input()
	_prep.play_rest_fade(midpoint, finished)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart_slice"):
		_restart_run()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.ctrl_pressed and key.physical_keycode == KEY_S:
		get_viewport().set_input_as_handled()
		_mission.save_checkpoint()
		return
	if key != null and key.pressed and not key.echo and key.ctrl_pressed and key.shift_pressed and key.physical_keycode == KEY_F10:
		if _player.input_enabled and not _player.is_driving():
			get_viewport().set_input_as_handled()
			_mission.start_demo_upload()


func _restart_run() -> void:
	if _mission.clear_checkpoint():
		get_tree().reload_current_scene()
