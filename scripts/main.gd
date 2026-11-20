extends Node3D
## Composition root for the vertical slice.
##
## The only place where systems are introduced to each other. Every cross-system link is
## a signal connection made here, so CodexSignalSystem and PlayerController never hold
## references to Hunter AI, and Hunters never reference the Runner.

@onready var _city: GreyboxCityBuilder = $NavigationRegion3D/City
@onready var _player: PlayerController = $Player
@onready var _director: HunterAIDirector = $HunterAIDirector
@onready var _hud: HUD = $HUD
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

	_director.bind_codex(codex)
	_director.runner_caught.connect(_player.on_caught)
	_player.captured.connect(_director.on_runner_respawned)
	_director.spawn_hunters(_city.hunter_spawn_points, _city.patrol_points)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart_slice"):
		get_tree().reload_current_scene()
