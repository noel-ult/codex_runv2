class_name GadgetBelt
extends Node
## The Runner's equipment: selectable gadgets, ammo and Resonance Cells.
## Lives under the PlayerController and is driven by it each physics frame. Gadgets affect
## the world only through duck-typed group contracts (never typed references to Hunter AI).

signal inventory_changed(selected: StringName, darts: int, emps: int, cells: int, decoys_active: int)
signal feedback(message: String)
## Emitted whenever a gadget is used (disguise systems listen to this).
signal gadget_used(gadget: StringName)
signal parts_changed(parts: int)
## Jammer aim assist: a device/hunter is under (or near) the crosshair.
signal aim_target_changed(has_target: bool, label: String)

const GADGET_JAMMER: StringName = &"jammer"
const GADGET_EMP: StringName = &"emp"
const GADGET_DECOY: StringName = &"decoy"
const AIM_PREVIEW_INTERVAL: float = 0.05

@export var decoy_cell_cost: int = 2
@export var max_active_decoys: int = 2
@export var max_darts: int = 8
@export var max_emps: int = 3
@export var max_cells: int = 6
@export var dart_range: float = 45.0
## Half-angle of the Jammer Dart aim-assist cone.
@export var dart_assist_degrees: float = 7.0
@export var dart_disable_seconds: float = 20.0
@export var dart_blind_seconds: float = 4.0
@export var emp_resonance_spike: float = 15.0
@export var emp_throw_speed: float = 15.0

var darts: int = 4
var emps: int = 1
var cells: int = 0
## Salvage parts: currency for the hideout prep station.
var parts: int = 4
## Extra decoy charge capacity bought at the prep station.
var decoy_bonus: float = 0.0
var selected: StringName = GADGET_JAMMER

var _player: PlayerController
var _decoys: Array[DecoyEmitter] = []
var _order: Array[StringName] = [GADGET_JAMMER, GADGET_EMP, GADGET_DECOY]
var _aim_label: String = ""
var _aim_preview_left: float = 0.0


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
	var live: Array[DecoyEmitter] = []
	for item: Variant in _decoys:
		if is_instance_valid(item):
			live.append(item as DecoyEmitter)
	_decoys = live
	inventory_changed.emit(selected, darts, emps, cells, _decoys.size())


## Called by the PlayerController while input is enabled.
func handle_input(delta: float) -> void:
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
	# Throttle only the HUD preview. The dart still queries the exact shot frame.
	_aim_preview_left -= delta
	if _aim_preview_left <= 0.0:
		_aim_preview_left = AIM_PREVIEW_INTERVAL
		_update_aim()
	if Input.is_action_just_pressed(&"use_gadget") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		use_selected()


func _update_aim() -> void:
	var label: String = ""
	if selected == GADGET_JAMMER:
		var target: Dictionary = find_dart_target()
		var node := target.get("node") as Node
		if node != null:
			label = Electronics.describe(node)
	if label != _aim_label:
		_aim_label = label
		aim_target_changed.emit(label != "", label)


## Returns {"node": target, "point": aim point} for the dart, using the crosshair ray first
## and then an aim-assist cone over every jammable hitbox and hunter in range.
func find_dart_target() -> Dictionary:
	var camera: Camera3D = _player.get_view_camera()
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z
	var mask: int = GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER | Electronics.HITBOX_LAYER | 4
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * dart_range, mask, [_player.get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		var direct: Node = Electronics.resolve(collider, Electronics.ELECTRONICS_GROUP)
		if direct == null:
			direct = Electronics.resolve(collider, Electronics.EMP_GROUP)
		if direct != null:
			return {"node": direct, "point": hit.get("position")}
	var best: Node = null
	var best_point: Vector3 = Vector3.ZERO
	var best_alignment: float = cos(deg_to_rad(dart_assist_degrees))
	var range_squared: float = dart_range * dart_range
	var candidates: Array[Node3D] = []
	for node: Node in _player.get_tree().get_nodes_in_group(Electronics.HITBOX_GROUP):
		var box := node as Node3D
		if box != null:
			candidates.append(box)
	for node: Node in _player.get_tree().get_nodes_in_group(Electronics.EMP_GROUP):
		var body := node as Node3D
		if body != null:
			candidates.append(body)
	for candidate: Node3D in candidates:
		var point: Vector3 = candidate.global_position + (Vector3(0.0, 1.3, 0.0) if candidate.is_in_group(Electronics.EMP_GROUP) else Vector3.ZERO)
		var to: Vector3 = point - origin
		var distance_squared: float = to.length_squared()
		if distance_squared > range_squared or distance_squared < 0.25:
			continue
		var alignment: float = forward.dot(to) / sqrt(distance_squared)
		if alignment <= best_alignment:
			continue
		var los := PhysicsRayQueryParameters3D.create(origin, point, GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER, [_player.get_rid()])
		var blocked: Dictionary = space.intersect_ray(los)
		if not blocked.is_empty() and (blocked.get("position", point) as Vector3).distance_to(point) > 0.6:
			continue
		var owner_device: Node = Electronics.resolve(candidate, Electronics.ELECTRONICS_GROUP)
		if owner_device == null:
			owner_device = Electronics.resolve(candidate, Electronics.EMP_GROUP)
		if owner_device == null:
			continue
		best = owner_device
		best_point = point
		best_alignment = alignment
	if best == null:
		return {}
	return {"node": best, "point": best_point}


func use_selected() -> bool:
	var used: bool = false
	match selected:
		GADGET_JAMMER:
			used = _fire_dart()
		GADGET_EMP:
			used = _throw_emp()
		GADGET_DECOY:
			used = _deploy_decoy()
	if used:
		gadget_used.emit(selected)
	return used


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
		Pickup.KIND_PARTS:
			add_parts(amount)
			return true
		_:
			return false
	publish()
	return true


func add_parts(amount: int) -> void:
	parts += amount
	feedback.emit("Salvage +%d  (%d parts - spend them at the hideout prep station)" % [amount, parts])
	parts_changed.emit(parts)
	publish()


func spend_parts(cost: int) -> bool:
	if parts < cost:
		return false
	parts -= cost
	parts_changed.emit(parts)
	publish()
	return true


func _select(gadget: StringName) -> void:
	selected = gadget
	_aim_preview_left = 0.0
	publish()


func _cycle(direction: int) -> void:
	var index: int = _order.find(selected)
	_select(_order[wrapi(index + direction, 0, _order.size())])


## Silent hitscan dart from the crosshair: shuts down one electronic device or scrambles a
## Hunter's visor (it loses track of you and stops for a few seconds).
func _fire_dart() -> bool:
	if darts <= 0:
		feedback.emit("Out of Jammer darts - find a supply cache.")
		return false
	darts -= 1
	var camera: Camera3D = _player.get_view_camera()
	var muzzle: Vector3 = _player.global_position + Vector3(0.0, 1.35, 0.0) + _player.get_facing() * 0.4
	var target: Dictionary = find_dart_target()
	var node := target.get("node") as Node
	var end: Vector3 = target.get("point", camera.global_position - camera.global_basis.z * dart_range)
	HunterFX.beam(_player.get_parent(), muzzle, end, Color(0.3, 0.9, 1.0), 0.15)
	publish()
	if node == null:
		return true
	Electronics.sparks(_player.get_parent(), end, Color(0.4, 0.9, 1.0))
	if node.has_method(&"disable_for"):
		node.call(&"disable_for", dart_disable_seconds)
		feedback.emit("%s jammed - offline for %d s." % [Electronics.describe(node).capitalize(), int(dart_disable_seconds)])
	elif node.has_method(&"apply_emp"):
		node.call(&"apply_emp", dart_blind_seconds)
		feedback.emit("Hunter visor scrambled.")
	return true


## Thrown EMP: area shutdown of electronics + Hunter stun, but the discharge spikes Resonance.
func _throw_emp() -> bool:
	if emps <= 0:
		feedback.emit("No EMP charges left.")
		return false
	emps -= 1
	var camera: Camera3D = _player.get_view_camera()
	var charge := EmpCharge.new()
	charge.name = "EmpCharge"
	_player.get_parent().add_child(charge)
	charge.global_position = _player.global_position + Vector3(0.0, 1.5, 0.0) + _player.get_facing() * 0.5
	var aim: Vector3 = -camera.global_basis.z
	charge.linear_velocity = aim * emp_throw_speed + Vector3(0.0, 3.5, 0.0) + _player.velocity * 0.5
	charge.detonated.connect(func(_at: Vector3) -> void:
		_player.get_codex().add_resonance(emp_resonance_spike, "EMP discharge"))
	publish()
	return true


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
	decoy.max_charge += decoy_bonus
	decoy.imprint_amount += decoy_bonus * 0.5
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
