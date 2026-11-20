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
@onready var _echoes: Node3D = $Echoes


func _ready() -> void:
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
	_mission.start()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart_slice"):
		get_tree().reload_current_scene()
