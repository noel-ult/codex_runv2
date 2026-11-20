class_name GadgetBelt
extends Node
## The Runner's equipment: selectable gadgets, ammo and Resonance Cells.
## Lives under the PlayerController and is driven by it each physics frame. Gadgets affect
## the world only through duck-typed group contracts (never typed references to Hunter AI).

signal inventory_changed(selected: StringName, darts: int, emps: int, cells: int, decoys_active: int)
signal feedback(message: String)

const GADGET_JAMMER: StringName = &"jammer"
const GADGET_EMP: StringName = &"emp"
const GADGET_DECOY: StringName = &"decoy"

@export var decoy_cell_cost: int = 2
@export var max_active_decoys: int = 2
@export var max_darts: int = 8
@export var max_emps: int = 3
@export var max_cells: int = 6

var darts: int = 4
var emps: int = 1
var cells: int = 0
var selected: StringName = GADGET_JAMMER

var _player: PlayerController
var _decoys: Array[DecoyEmitter] = []
var _order: Array[StringName] = [GADGET_JAMMER, GADGET_EMP, GADGET_DECOY]


func _ready() -> void:
	_player = get_parent() as PlayerController


static func display_name(gadget: StringName) -> String:
	match gadget:
		GADGET_JAMMER:
			return "JAMMER DART"
		GADGET_EMP:
			return "EMP CHARGE"
		GADGET_DECOY:
			return "DECOY CODEX"
	return String(gadget).to_upper()


func publish() -> void:
	_decoys = _decoys.filter(func(d: DecoyEmitter) -> bool: return is_instance_valid(d))
	inventory_changed.emit(selected, darts, emps, cells, _decoys.size())


## Called by the PlayerController while input is enabled.
func handle_input() -> void:
	if Input.is_action_just_pressed(&"gadget_1"):
		_select(GADGET_JAMMER)
	elif Input.is_action_just_pressed(&"gadget_2"):
		_select(GADGET_EMP)
	elif Input.is_action_just_pressed(&"gadget_3"):
		_select(GADGET_DECOY)
	elif Input.is_action_just_pressed(&"gadget_next"):
		_cycle(1)
	elif Input.is_action_just_pressed(&"gadget_prev"):
		_cycle(-1)
	if Input.is_action_just_pressed(&"use_gadget") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		use_selected()


func use_selected() -> bool:
	match selected:
		GADGET_DECOY:
			return _deploy_decoy()
	return false


func collect(kind: StringName, amount: int) -> bool:
	match kind:
		Pickup.KIND_CELL:
			if cells >= max_cells:
				return false
			cells = mini(cells + amount, max_cells)
			feedback.emit("Resonance Cell collected (%d/%d). %d cells build a decoy." % [cells, max_cells, decoy_cell_cost])
		Pickup.KIND_DARTS:
			if darts >= max_darts:
				return false
			darts = mini(darts + amount, max_darts)
			feedback.emit("Jammer darts +%d" % amount)
		Pickup.KIND_EMP:
			if emps >= max_emps:
				return false
			emps = mini(emps + amount, max_emps)
			feedback.emit("EMP charge +%d" % amount)
		_:
			return false
	publish()
	return true


func _select(gadget: StringName) -> void:
	selected = gadget
	publish()


func _cycle(direction: int) -> void:
	var index: int = _order.find(selected)
	_select(_order[wrapi(index + direction, 0, _order.size())])


func _deploy_decoy() -> bool:
	publish()
	if cells < decoy_cell_cost:
		feedback.emit("Decoy needs %d Resonance Cells (you have %d)." % [decoy_cell_cost, cells])
		return false
	if _decoys.size() >= max_active_decoys:
		feedback.emit("Maximum %d decoys deployed." % max_active_decoys)
		return false
	var forward: Vector3 = _player.get_facing()
	var origin: Vector3 = _player.global_position + forward * 1.6 + Vector3(0.0, 2.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(0.0, -5.0, 0.0), GeometryKit.WORLD_LAYER, [_player.get_rid()])
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		feedback.emit("No solid ground to place the decoy.")
		return false
	var decoy := DecoyEmitter.new()
	decoy.name = "DecoyEmitter"
	_player.get_parent().add_child(decoy)
	decoy.global_position = hit.get("position", origin)
	cells -= decoy_cell_cost
	_decoys.append(decoy)
	var codex: CodexSignalSystem = _player.get_codex()
	codex.register_decoy(decoy)
	decoy.destroyed.connect(func(d: DecoyEmitter) -> void:
		codex.unregister_decoy(d)
		feedback.emit("A Hunter destroyed your decoy.")
		publish.call_deferred())
	feedback.emit("Decoy deployed - hold E on it to imprint your Codex signature.")
	publish()
	return true
