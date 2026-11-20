class_name CodexSignalSystem
extends Node
## Single source of truth for the Runner's Codex: Resonance, Form, Codex Ignition,
## the periodic Codex Release pulse, Residual Echo drops, Dead Zone masking and decoys.
##
## Decoupling rules:
## - Talks to the outside world ONLY through the signals declared below.
## - Never references Hunter AI. Hunters learn about the Runner exclusively by listening to
##   `codex_released`, `ignition_broadcast`, `echo_dropped` and `decoy_beacon_*`.
## - Decoys are generic Node3D "decoy emitters" implementing the DECOY_* contract, so this
##   system does not depend on any concrete world class.

signal resonance_changed(value: float, max_value: float)
signal form_changed(form: StringName)
signal micro_fusion_triggered(ability: StringName, spike: float)
signal codex_ignited(broadcasting: bool)
signal codex_ignition_ended()
## Live 3D coordinates of the Runner, emitted continuously while Ignited and not masked.
signal ignition_broadcast(world_position: Vector3)
## The Codex cannot be contained: every `release_interval` seconds it vents a pulse that
## pings every Hunter within `radius`. `from_decoy` = the pulse was redirected to a decoy.
signal codex_released(world_position: Vector3, radius: float, from_decoy: bool)
signal release_masked(reason: String)
signal release_countdown(seconds_left: float, interval: float)
signal broadcast_suppression_changed(suppressed: bool)
signal dead_zone_changed(inside: bool)
signal echo_dropped(echo: ResidualEcho)
signal decoy_beacon_activated(beacon: Node3D, ability: StringName)
signal decoy_beacon_deactivated(beacon: Node3D, ability: StringName)
signal feedback(message: String)

const FORM_BASE: StringName = &"base"
const FORM_FULL: StringName = &"full"
const ABILITY_MICRO_DASH: StringName = &"micro_dash"
const ABILITY_SUPER_JUMP: StringName = &"super_jump"
const ABILITY_FULL_FORM: StringName = &"full_form"
const ABILITY_DECOY: StringName = &"decoy"

## Decoy emitter contract (implemented by DecoyEmitter).
const DECOY_CHARGE_METHOD: StringName = &"get_charge"
const DECOY_CONSUME_METHOD: StringName = &"consume_charge"
const DECOY_PULSE_METHOD: StringName = &"play_pulse"

@export_group("Resonance")
@export var max_resonance: float = 100.0
@export var base_decay_rate: float = 8.0
@export var dead_zone_decay_multiplier: float = 3.0
@export var full_form_build_rate: float = 27.0
@export var micro_dash_spike: float = 20.0
@export var super_jump_spike: float = 26.0

@export_group("Ignition")
## Seconds Resonance is pinned at max after Ignition before it may decay again.
@export var ignition_hold_time: float = 2.5
## Ignition ends once Resonance falls below this value.
@export var ignition_release_threshold: float = 60.0
@export var broadcast_interval: float = 0.05
@export var echo_interval: float = 2.5

@export_group("Codex Release")
@export var release_interval: float = 30.0
@export var release_base_radius: float = 55.0
@export var release_radius_per_resonance: float = 0.9
## Charge an armed decoy spends to take a Release in the Runner's place.
@export var decoy_release_cost: float = 20.0
## Charge drained per second while a decoy echoes an Ignition broadcast.
@export var decoy_echo_drain: float = 4.0

var resonance: float = 0.0
var form: StringName = FORM_BASE
var is_ignited: bool = false
## Node that receives spawned Residual Echoes. Falls back to the current scene.
var echo_container: Node
## Multiplier on passive decay set by gameplay (e.g. lockdown makes the Codex agitated).
var decay_scale: float = 1.0
## Multiplier on Release radius set by gameplay (e.g. a disguise dampens the pulse).
var release_radius_scale: float = 1.0
## Permanent multiplier from the hideout "signature dampener" upgrade.
var upgrade_radius_scale: float = 1.0
## Daylight exposure: Releases reach further and come sooner during the day.
var daylight_radius_scale: float = 1.0
var daylight_interval_scale: float = 1.0

var _host: Node3D
var _dead_zone_count: int = 0
var _ignition_hold_left: float = 0.0
var _broadcast_timer: float = 0.0
var _echo_timer: float = 0.0
var _release_left: float = 0.0
var _countdown_tick: float = 0.0
var _decoys: Array[Node3D] = []
var _echoing: Array[Node3D] = []


func _ready() -> void:
	_host = get_parent() as Node3D
	_release_left = release_interval
	if _host == null:
		push_error("CodexSignalSystem must be the child of a Node3D (the Runner).")


func _physics_process(delta: float) -> void:
	if form == FORM_FULL:
		_change_resonance(full_form_build_rate * delta)

	if _ignition_hold_left > 0.0:
		_ignition_hold_left -= delta
	elif resonance < max_resonance or form != FORM_FULL:
		_change_resonance(-base_decay_rate * _decay_multiplier() * delta)

	_update_ignition(delta)
	_update_release(delta)
	_update_decoy_echo(delta)


# --- Queries -----------------------------------------------------------------

func is_in_dead_zone() -> bool:
	return _dead_zone_count > 0


func is_broadcast_suppressed() -> bool:
	return is_in_dead_zone()


func is_full_form() -> bool:
	return form == FORM_FULL


func get_release_time_left() -> float:
	return _release_left


func get_release_radius() -> float:
	return (release_base_radius + resonance * release_radius_per_resonance) * release_radius_scale * upgrade_radius_scale * daylight_radius_scale


static func get_ability_display_name(ability: StringName) -> String:
	match ability:
		ABILITY_MICRO_DASH:
			return "DASH"
		ABILITY_SUPER_JUMP:
			return "LEAP"
		ABILITY_FULL_FORM:
			return "FULL FORM"
		ABILITY_DECOY:
			return "DECOY"
	return String(ability).to_upper()


static func get_ability_color(ability: StringName) -> Color:
	match ability:
		ABILITY_MICRO_DASH:
			return Color(0.2, 0.9, 1.0)
		ABILITY_SUPER_JUMP:
			return Color(0.55, 1.0, 0.25)
		ABILITY_FULL_FORM:
			return Color(1.0, 0.25, 0.85)
		ABILITY_DECOY:
			return Color(1.0, 0.7, 0.2)
	return Color.WHITE


# --- Commands (called by the owning PlayerController / gadgets / mission) ---------

## Attempts a Micro-Fusion burst.
func try_micro_fusion(ability: StringName) -> bool:
	var spike: float = micro_dash_spike if ability == ABILITY_MICRO_DASH else super_jump_spike
	_change_resonance(spike)
	micro_fusion_triggered.emit(ability, spike)
	return true


func toggle_full_form() -> bool:
	return set_full_form(form != FORM_FULL)


func set_full_form(active: bool) -> bool:
	_set_form(FORM_FULL if active else FORM_BASE)
	return true


## External Resonance change (hacking, gadgets, imprinting decoys...).
func add_resonance(amount: float, reason: String = "") -> void:
	_change_resonance(amount)
	if reason != "":
		feedback.emit("%s  %+d Resonance" % [reason, int(amount)])
	_update_ignition(0.0)


## Moves up to `amount` Resonance out of the Codex (used to imprint decoys). Returns moved amount.
func drain_resonance(amount: float) -> float:
	var moved: float = minf(amount, resonance)
	_change_resonance(-moved)
	_update_ignition(0.0)
	return moved


func register_decoy(decoy: Node3D) -> void:
	if not _decoys.has(decoy):
		_decoys.append(decoy)


func unregister_decoy(decoy: Node3D) -> void:
	_decoys.erase(decoy)
	if _echoing.has(decoy):
		_echoing.erase(decoy)
		decoy_beacon_deactivated.emit(decoy, ABILITY_DECOY)


func enter_dead_zone(_zone: Node) -> void:
	_dead_zone_count += 1
	if _dead_zone_count == 1:
		dead_zone_changed.emit(true)
		broadcast_suppression_changed.emit(true)


func exit_dead_zone(_zone: Node) -> void:
	_dead_zone_count = maxi(_dead_zone_count - 1, 0)
	if _dead_zone_count == 0:
		dead_zone_changed.emit(false)
		broadcast_suppression_changed.emit(false)


## Clears Resonance/Form/Ignition (used on capture) and restarts the Release clock.
func reset_resonance() -> void:
	_set_form(FORM_BASE)
	_ignition_hold_left = 0.0
	resonance = 0.0
	_release_left = release_interval
	resonance_changed.emit(resonance, max_resonance)
	_update_ignition(0.0)


## Re-emits the full state so late listeners (e.g. HUD) can initialise.
func emit_full_state() -> void:
	resonance_changed.emit(resonance, max_resonance)
	form_changed.emit(form)
	dead_zone_changed.emit(is_in_dead_zone())
	release_countdown.emit(_release_left, release_interval)


# --- Internals ---------------------------------------------------------------

func _decay_multiplier() -> float:
	return (dead_zone_decay_multiplier if is_in_dead_zone() else 1.0) * decay_scale


func _change_resonance(amount: float) -> void:
	var previous: float = resonance
	resonance = clampf(resonance + amount, 0.0, max_resonance)
	if not is_equal_approx(previous, resonance):
		resonance_changed.emit(resonance, max_resonance)


func _set_form(new_form: StringName) -> void:
	if form == new_form:
		return
	form = new_form
	form_changed.emit(form)


func _update_ignition(delta: float) -> void:
	if not is_ignited and resonance >= max_resonance - 0.001:
		_ignite()
	elif is_ignited and resonance < ignition_release_threshold:
		is_ignited = false
		_ignition_hold_left = 0.0
		codex_ignition_ended.emit()
		feedback.emit("Ignition faded. Signal lost.")

	if not is_ignited or is_broadcast_suppressed() or _host == null:
		return

	_broadcast_timer -= delta
	if _broadcast_timer <= 0.0:
		_broadcast_timer = broadcast_interval
		ignition_broadcast.emit(_host.global_position)

	_echo_timer -= delta
	if _echo_timer <= 0.0:
		_echo_timer = echo_interval
		_drop_echo(_host.global_position)


func _ignite() -> void:
	is_ignited = true
	_ignition_hold_left = ignition_hold_time
	_broadcast_timer = 0.0
	_echo_timer = 0.0
	codex_ignited.emit(not is_broadcast_suppressed())


func _update_release(delta: float) -> void:
	if _host == null:
		return
	_release_left -= delta
	_countdown_tick -= delta
	if _countdown_tick <= 0.0:
		_countdown_tick = 0.1
		release_countdown.emit(maxf(_release_left, 0.0), release_interval * daylight_interval_scale)
	if _release_left > 0.0:
		return
	_release_left = release_interval * daylight_interval_scale
	var radius: float = get_release_radius()

	var decoy: Node3D = _strongest_decoy()
	if decoy != null:
		decoy.call(DECOY_CONSUME_METHOD, decoy_release_cost)
		decoy.call(DECOY_PULSE_METHOD)
		codex_released.emit(decoy.global_position, radius * 1.15, true)
		feedback.emit("Codex Release redirected through your decoy.")
		return
	if is_in_dead_zone():
		release_masked.emit("Dead Zone")
		feedback.emit("Codex Release absorbed by the Dead Zone.")
		return
	codex_released.emit(_host.global_position, radius, false)
	_drop_echo(_host.global_position)


func _strongest_decoy() -> Node3D:
	var best: Node3D = null
	var best_charge: float = decoy_release_cost - 0.001
	for item: Variant in _decoys:
		if not is_instance_valid(item):
			continue
		var decoy: Node3D = item as Node3D
		var charge: float = float(decoy.call(DECOY_CHARGE_METHOD))
		if charge > best_charge:
			best_charge = charge
			best = decoy
	return best


## While Ignited, armed decoys echo the broadcast as fake Codex beacons (draining charge).
func _update_decoy_echo(delta: float) -> void:
	var live: Array[Node3D] = []
	for item: Variant in _decoys:
		if is_instance_valid(item):
			live.append(item as Node3D)
	_decoys = live
	var echoing: Array[Node3D] = []
	for item: Variant in _echoing:
		if is_instance_valid(item):
			echoing.append(item as Node3D)
	_echoing = echoing
	for decoy: Node3D in _decoys:
		var charge: float = float(decoy.call(DECOY_CHARGE_METHOD))
		var should_echo: bool = is_ignited and charge > 0.0
		if should_echo:
			decoy.call(DECOY_CONSUME_METHOD, decoy_echo_drain * delta)
		if should_echo and not _echoing.has(decoy):
			_echoing.append(decoy)
			decoy_beacon_activated.emit(decoy, ABILITY_DECOY)
		elif not should_echo and _echoing.has(decoy):
			_echoing.erase(decoy)
			decoy_beacon_deactivated.emit(decoy, ABILITY_DECOY)


func _drop_echo(at: Vector3) -> void:
	var container: Node = echo_container
	if container == null or not is_instance_valid(container):
		container = get_tree().current_scene
	if container == null:
		return
	var echo := ResidualEcho.new()
	echo.name = "ResidualEcho"
	container.add_child(echo)
	echo.global_position = at
	echo_dropped.emit(echo)
