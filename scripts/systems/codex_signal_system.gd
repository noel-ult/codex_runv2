class_name CodexSignalSystem
extends Node
## Single source of truth for the Runner's Codex: Resonance, Form, ability locks,
## Codex Ignition, Residual Echo drops, Dead Zone suppression and Codex Fracturing.
##
## Decoupling rules:
## - Talks to the outside world ONLY through the signals declared below.
## - Never references Hunter AI. Hunters learn about the Runner exclusively by
##   listening to `ignition_broadcast`, `echo_dropped` and `decoy_beacon_*`.
## - Decoys are treated as generic Node3D "fracture beacons" that implement the
##   contract described by the BEACON_* constants, so this system does not depend
##   on any concrete world class.

signal resonance_changed(value: float, max_value: float)
signal form_changed(form: StringName)
signal micro_fusion_triggered(ability: StringName, spike: float)
signal codex_ignited(broadcasting: bool)
signal codex_ignition_ended()
## Live 3D coordinates of the Runner, emitted continuously while Ignited and not masked.
signal ignition_broadcast(world_position: Vector3)
signal broadcast_suppression_changed(suppressed: bool)
signal dead_zone_changed(inside: bool)
signal echo_dropped(echo: ResidualEcho)
signal ability_lock_changed(ability: StringName, locked: bool, holder_name: String)
signal decoy_beacon_activated(beacon: Node3D, ability: StringName)
signal decoy_beacon_deactivated(beacon: Node3D, ability: StringName)
signal feedback(message: String)

const FORM_BASE: StringName = &"base"
const FORM_FULL: StringName = &"full"
const ABILITY_MICRO_DASH: StringName = &"micro_dash"
const ABILITY_SUPER_JUMP: StringName = &"super_jump"
const ABILITY_FULL_FORM: StringName = &"full_form"

## Fracture beacon contract (implemented by DecoyVehicle).
const BEACON_ATTACH_METHOD: StringName = &"attach_fractured_ability"
const BEACON_RELEASE_METHOD: StringName = &"release_fractured_ability"
const BEACON_IS_ACTIVE_METHOD: StringName = &"is_beacon_active"
const BEACON_NAME_METHOD: StringName = &"get_display_name"
const BEACON_CONTACT_SIGNAL: StringName = &"runner_contact"

@export_group("Resonance")
@export var max_resonance: float = 100.0
@export var base_decay_rate: float = 8.0
@export var dead_zone_decay_multiplier: float = 3.0
@export var full_form_build_rate: float = 27.0
@export var micro_dash_spike: float = 20.0
@export var super_jump_spike: float = 26.0
@export var fracture_resonance_cost: float = 45.0

@export_group("Ignition")
## Seconds Resonance is pinned at max after Ignition before it may decay again.
@export var ignition_hold_time: float = 2.5
## Ignition ends once Resonance falls below this value.
@export var ignition_release_threshold: float = 60.0
@export var broadcast_interval: float = 0.05
@export var echo_interval: float = 2.5

var resonance: float = 0.0
var form: StringName = FORM_BASE
var is_ignited: bool = false
## Node that receives spawned Residual Echoes. Falls back to the current scene.
var echo_container: Node

var _host: Node3D
var _dead_zone_count: int = 0
var _ignition_hold_left: float = 0.0
var _broadcast_timer: float = 0.0
var _echo_timer: float = 0.0
## ability (StringName) -> beacon (Node3D) currently holding it.
var _fractured: Dictionary = {}
var _ability_order: Array[StringName] = [ABILITY_MICRO_DASH, ABILITY_SUPER_JUMP, ABILITY_FULL_FORM]


func _ready() -> void:
	_host = get_parent() as Node3D
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


# --- Queries -----------------------------------------------------------------

func is_in_dead_zone() -> bool:
	return _dead_zone_count > 0


func is_broadcast_suppressed() -> bool:
	return is_in_dead_zone()


func is_full_form() -> bool:
	return form == FORM_FULL


func is_ability_locked(ability: StringName) -> bool:
	return _fractured.has(ability)


func get_ability_holder_name(ability: StringName) -> String:
	if not _fractured.has(ability):
		return ""
	var beacon: Node3D = _fractured[ability]
	return _beacon_name(beacon)


func get_abilities() -> Array[StringName]:
	return _ability_order.duplicate()


static func get_ability_display_name(ability: StringName) -> String:
	match ability:
		ABILITY_MICRO_DASH:
			return "MICRO DASH"
		ABILITY_SUPER_JUMP:
			return "SUPER JUMP"
		ABILITY_FULL_FORM:
			return "FULL FORM"
	return String(ability).to_upper()


static func get_ability_color(ability: StringName) -> Color:
	match ability:
		ABILITY_MICRO_DASH:
			return Color(0.2, 0.9, 1.0)
		ABILITY_SUPER_JUMP:
			return Color(0.55, 1.0, 0.25)
		ABILITY_FULL_FORM:
			return Color(1.0, 0.25, 0.85)
	return Color.WHITE


# --- Commands (called by the owning PlayerController) ------------------------

## Attempts a Micro-Fusion burst. Returns false if the ability is fractured.
func try_micro_fusion(ability: StringName) -> bool:
	if is_ability_locked(ability):
		feedback.emit("%s is fractured onto %s - touch it to re-absorb." % [get_ability_display_name(ability), get_ability_holder_name(ability)])
		return false
	var spike: float = micro_dash_spike if ability == ABILITY_MICRO_DASH else super_jump_spike
	_change_resonance(spike)
	micro_fusion_triggered.emit(ability, spike)
	return true


func toggle_full_form() -> bool:
	return set_full_form(form != FORM_FULL)


func set_full_form(active: bool) -> bool:
	if active and is_ability_locked(ABILITY_FULL_FORM):
		feedback.emit("FULL FORM is fractured onto %s - touch it to re-absorb." % get_ability_holder_name(ABILITY_FULL_FORM))
		return false
	_set_form(FORM_FULL if active else FORM_BASE)
	return true


## Detaches an active ability onto `beacon`, turning it into a fake Codex signal.
## `preferred` is the ability the Runner used most recently.
func fracture_onto(beacon: Node3D, preferred: StringName) -> bool:
	if beacon == null or not _is_valid_beacon(beacon):
		feedback.emit("No fracture target.")
		return false
	if bool(beacon.call(BEACON_IS_ACTIVE_METHOD)):
		feedback.emit("%s already carries a fractured ability." % _beacon_name(beacon))
		return false
	var ability: StringName = _pick_fracture_ability(preferred)
	if ability == &"":
		feedback.emit("Nothing left to fracture - every ability is detached.")
		return false

	_fractured[ability] = beacon
	if ability == ABILITY_FULL_FORM and form == FORM_FULL:
		_set_form(FORM_BASE)
	_change_resonance(-fracture_resonance_cost)
	beacon.call(BEACON_ATTACH_METHOD, ability, get_ability_color(ability))
	var on_contact: Callable = _on_beacon_contact
	if not beacon.is_connected(BEACON_CONTACT_SIGNAL, on_contact):
		beacon.connect(BEACON_CONTACT_SIGNAL, on_contact)

	ability_lock_changed.emit(ability, true, _beacon_name(beacon))
	decoy_beacon_activated.emit(beacon, ability)
	feedback.emit("Fractured %s onto %s. Resonance -%d." % [get_ability_display_name(ability), _beacon_name(beacon), int(fracture_resonance_cost)])
	_update_ignition(0.0)
	return true


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


## Clears Resonance/Form/Ignition (used on capture). Fractured abilities stay on their beacons.
func reset_resonance() -> void:
	_set_form(FORM_BASE)
	_ignition_hold_left = 0.0
	resonance = 0.0
	resonance_changed.emit(resonance, max_resonance)
	_update_ignition(0.0)


## Re-emits the full state so late listeners (e.g. HUD) can initialise.
func emit_full_state() -> void:
	resonance_changed.emit(resonance, max_resonance)
	form_changed.emit(form)
	dead_zone_changed.emit(is_in_dead_zone())
	for ability: StringName in _ability_order:
		ability_lock_changed.emit(ability, is_ability_locked(ability), get_ability_holder_name(ability))


# --- Internals ---------------------------------------------------------------

func _decay_multiplier() -> float:
	return dead_zone_decay_multiplier if is_in_dead_zone() else 1.0


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
		_drop_echo()


func _ignite() -> void:
	is_ignited = true
	_ignition_hold_left = ignition_hold_time
	_broadcast_timer = 0.0
	_echo_timer = 0.0
	codex_ignited.emit(not is_broadcast_suppressed())


func _drop_echo() -> void:
	var container: Node = echo_container
	if container == null or not is_instance_valid(container):
		container = get_tree().current_scene
	if container == null:
		return
	var echo := ResidualEcho.new()
	echo.name = "ResidualEcho"
	container.add_child(echo)
	echo.global_position = _host.global_position
	echo_dropped.emit(echo)


func _pick_fracture_ability(preferred: StringName) -> StringName:
	if form == FORM_FULL and not is_ability_locked(ABILITY_FULL_FORM):
		return ABILITY_FULL_FORM
	if preferred != &"" and _ability_order.has(preferred) and not is_ability_locked(preferred):
		return preferred
	for ability: StringName in _ability_order:
		if not is_ability_locked(ability):
			return ability
	return &""


func _on_beacon_contact(beacon: Node3D) -> void:
	var released: Array[StringName] = []
	for ability: StringName in _ability_order:
		if _fractured.has(ability) and _fractured[ability] == beacon:
			released.append(ability)
	if released.is_empty():
		return
	var on_contact: Callable = _on_beacon_contact
	if beacon.is_connected(BEACON_CONTACT_SIGNAL, on_contact):
		beacon.disconnect(BEACON_CONTACT_SIGNAL, on_contact)
	beacon.call(BEACON_RELEASE_METHOD)
	for ability: StringName in released:
		_fractured.erase(ability)
		ability_lock_changed.emit(ability, false, "")
		decoy_beacon_deactivated.emit(beacon, ability)
		feedback.emit("Re-absorbed %s from %s." % [get_ability_display_name(ability), _beacon_name(beacon)])


func _is_valid_beacon(beacon: Node3D) -> bool:
	return beacon.has_method(BEACON_ATTACH_METHOD) and beacon.has_method(BEACON_RELEASE_METHOD) \
		and beacon.has_method(BEACON_IS_ACTIVE_METHOD) and beacon.has_signal(BEACON_CONTACT_SIGNAL)


func _beacon_name(beacon: Node3D) -> String:
	if beacon == null or not is_instance_valid(beacon):
		return ""
	if beacon.has_method(BEACON_NAME_METHOD):
		return str(beacon.call(BEACON_NAME_METHOD))
	return String(beacon.name)
