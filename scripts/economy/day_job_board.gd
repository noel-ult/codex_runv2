class_name DayJobBoard
extends Node3D
## Daytime courier work: collect a parcel at the depot and hand it in across the city.
## Main supplies the daylight rule and connects payouts to the wallet.

signal payout_requested(amount: int)
signal marker_changed(id: StringName, world_position: Vector3, label: String, color: Color, shown: bool)
signal feedback(message: String)
signal status_changed(text: String)

const MINT: Color = Color(0.42, 1.0, 0.86)
const AMBER: Color = Color(1.0, 0.73, 0.35)
const DESTINATIONS: PackedVector3Array = [Vector3(-8.1, 0.1, -33.0), Vector3(29.0, 0.1, 8.2), Vector3(8.2, 0.1, 39.0)]
const ROUTE_NAMES: PackedStringArray = ["NORTH RESIDENTIAL", "MARKET ARCADE", "SOUTH OFFICES"]
const PAYMENTS: PackedInt32Array = [55, 65, 45]

var has_job: bool = false
var active_route: int = -1
var board: Interactable
var deliveries: Array[Interactable] = []

var _player: PlayerController
var _can_work: Callable
var _day_open: bool = false
var _last_open: bool = false
var _next_route: int = 0
var _hours_tick: float = 0.0
var _board_screen: Label3D
var _drop_labels: Array[Label3D] = []
var _indicators: Array[MeshInstance3D] = []


func _ready() -> void:
	_build_depot()
	_build_deliveries()
	_refresh()


func setup(player: PlayerController, can_work: Callable) -> void:
	_player = player
	_can_work = can_work
	_day_open = _work_available()
	_last_open = _day_open
	_refresh()


func get_board_marker_position() -> Vector3:
	return global_position + Vector3(0.0, 2.3, 0.0)


func on_runner_captured(_total: int) -> void:
	if not has_job:
		return
	_clear_job()
	_refresh()
	feedback.emit("Courier contract lost on capture. Pick up a new parcel at the depot during daylight.")


func _process(delta: float) -> void:
	_hours_tick -= delta
	if _hours_tick > 0.0:
		return
	_hours_tick = 0.25
	_sync_work_hours()


func _work_available() -> bool:
	return _can_work.is_valid() and bool(_can_work.call())


func _sync_work_hours() -> void:
	_day_open = _work_available()
	if _day_open == _last_open:
		return
	_last_open = _day_open
	if not _day_open and has_job:
		_clear_job()
		feedback.emit("Courier dispatch closed for the night. Unfinished parcel returned; work resumes at dawn.")
	elif _day_open:
		feedback.emit("Day courier dispatch is open. Pick up a parcel to earn credits for supplies.")
	_refresh()


func _on_parcel_collected(interaction: Interactable, actor: Node3D) -> void:
	_sync_work_hours()
	if has_job or not _day_open or not _valid_actor(interaction, actor):
		return
	has_job = true
	active_route = _next_route
	_next_route = (_next_route + 1) % DESTINATIONS.size()
	_refresh()
	feedback.emit("Parcel collected. Deliver to %s before dusk for %d credits. A vehicle can get you there faster." % [ROUTE_NAMES[active_route], PAYMENTS[active_route]])


func _on_delivered(interaction: Interactable, actor: Node3D, route: int) -> void:
	_sync_work_hours()
	if not has_job or route != active_route or not _day_open or not _valid_actor(interaction, actor):
		return
	var payment: int = PAYMENTS[active_route]
	var destination: String = ROUTE_NAMES[active_route]
	# Clear the active contract before signals so repeated completion cannot pay twice.
	_clear_job()
	_refresh()
	payout_requested.emit(payment)
	feedback.emit("Delivered to %s. Earned %d credits. Return to the courier depot for another parcel." % [destination, payment])


func _clear_job() -> void:
	has_job = false
	active_route = -1


func _valid_actor(interaction: Interactable, actor: Node3D) -> bool:
	if actor != _player or _player == null or not _player.input_enabled or _player.is_driving():
		return false
	if not interaction.is_available_for(actor):
		return false
	# Consoles face the street (+X); reach them from the front, not through a wall.
	if actor.global_position.x < interaction.global_position.x - 0.5:
		return false
	var exclude: Array[RID] = [_player.get_rid()]
	var from: Vector3 = _player.get_head_position()
	var to: Vector3 = interaction.global_position + Vector3(0.0, 0.75, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER, exclude)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _refresh() -> void:
	if board == null:
		return
	board.enabled = _player != null
	board.prompt = "Collect a courier parcel (+%d credits)" % PAYMENTS[_next_route]
	board.requirement_hint = "Deliver your current parcel first" if has_job else "Courier work opens at dawn; return during daylight"
	_board_screen.text = "PARCEL IN TRANSIT" if has_job else ("DAY COURIER\n%d CREDITS / JOB" % PAYMENTS[_next_route] if _day_open else "DAY COURIER\nCLOSED UNTIL DAWN")
	_board_screen.modulate = MINT if _day_open else AMBER
	for index: int in deliveries.size():
		var active: bool = has_job and active_route == index and _day_open
		deliveries[index].enabled = active
		_drop_labels[index].text = ROUTE_NAMES[index] + ("\nHOLD E TO DELIVER" if active else "\nCOURIER LOCKER")
		_drop_labels[index].modulate = MINT if active else Color(0.45, 0.61, 0.59)
		_indicators[index].visible = active
		marker_changed.emit(StringName("courier_drop_%d" % index), deliveries[index].global_position + Vector3(0.0, 1.8, 0.0), "DELIVER / " + ROUTE_NAMES[index], MINT, active)
	marker_changed.emit(&"courier_depot", get_board_marker_position(), "COURIER / " + ("DAY WORK" if _day_open else "DAWN WORK"), AMBER, not has_job)
	if has_job:
		status_changed.emit("COURIER  ·  %s  ·  +%d CR" % [ROUTE_NAMES[active_route], PAYMENTS[active_route]])
	else:
		status_changed.emit("COURIER  ·  DAY WORK AVAILABLE" if _day_open else "COURIER  ·  OPENS AT DAWN")


func _build_depot() -> void:
	var steel: StandardMaterial3D = MaterialLibrary.coated(Color(0.10, 0.17, 0.18), 0.68, 0.38)
	var orange: StandardMaterial3D = MaterialLibrary.coated(Color(0.73, 0.36, 0.12), 0.38, 0.46)
	GeometryKit.solid_box(self, Vector3(0.0, 0.62, 0.0), Vector3(0.56, 1.24, 0.65), steel)
	GeometryKit.mesh_box(self, Vector3(0.29, 1.0, 0.0), Vector3(0.035, 0.42, 0.55), orange)
	GeometryKit.mesh_box(self, Vector3(0.315, 1.03, 0.0), Vector3(0.015, 0.22, 0.45), MaterialLibrary.emissive(MINT, 0.7))
	GeometryKit.mesh_box(self, Vector3(0.29, 0.45, 0.0), Vector3(0.04, 0.20, 0.48), orange)
	_board_screen = _sign(self, Vector3(0.34, 1.6, 0.0), "DAY COURIER", 24, 0.004)
	var parcel: StandardMaterial3D = MaterialLibrary.coated(Color(0.51, 0.36, 0.20), 0.0, 0.85)
	GeometryKit.mesh_box(self, Vector3(0.0, 1.34, 0.0), Vector3(0.43, 0.20, 0.38), parcel)
	GeometryKit.mesh_box(self, Vector3(0.0, 1.447, 0.0), Vector3(0.12, 0.014, 0.39), MaterialLibrary.coated(AMBER, 0.05, 0.6))
	board = Interactable.new()
	board.name = "CollectParcel"
	board.position = Vector3(0.85, 0.65, 0.0)
	board.radius = 1.55
	board.height_tolerance = 0.85
	board.hold_time = 1.5
	board.requirement = func(actor: Node3D) -> bool: return not has_job and _work_available() and _valid_actor(board, actor)
	add_child(board)
	board.completed.connect(_on_parcel_collected)


func _build_deliveries() -> void:
	for index: int in DESTINATIONS.size():
		var locker := Node3D.new()
		locker.name = "CourierLocker%d" % index
		add_child(locker)
		locker.global_position = DESTINATIONS[index]
		var shell: StandardMaterial3D = MaterialLibrary.coated(Color(0.12, 0.23, 0.25), 0.52, 0.42)
		GeometryKit.solid_box(locker, Vector3(0.0, 0.65, 0.0), Vector3(0.55, 1.3, 0.68), shell)
		var edge: StandardMaterial3D = MaterialLibrary.coated(Color(0.25, 0.37, 0.36), 0.65, 0.4)
		for height: float in [0.25, 0.65, 1.05]:
			GeometryKit.mesh_box(locker, Vector3(0.28, height, 0.0), Vector3(0.025, 0.29, 0.56), edge)
		var indicator: MeshInstance3D = GeometryKit.mesh_box(locker, Vector3(0.30, 1.23, 0.0), Vector3(0.02, 0.05, 0.40), MaterialLibrary.emissive(MINT, 2.0))
		_indicators.append(indicator)
		_drop_labels.append(_sign(locker, Vector3(0.31, 1.7, 0.0), ROUTE_NAMES[index], 23, 0.0035))
		var interaction := Interactable.new()
		interaction.name = "DeliverParcel"
		interaction.position = Vector3(0.9, 0.65, 0.0)
		interaction.radius = 1.5
		interaction.height_tolerance = 0.85
		interaction.hold_time = 1.6
		interaction.prompt = "Deliver the courier parcel (+%d credits)" % PAYMENTS[index]
		interaction.enabled = false
		locker.add_child(interaction)
		interaction.requirement = _valid_delivery.bind(interaction, index)
		interaction.completed.connect(_on_delivered.bind(index))
		deliveries.append(interaction)


func _valid_delivery(actor: Node3D, interaction: Interactable, route: int) -> bool:
	return has_job and active_route == route and _work_available() and _valid_actor(interaction, actor)


func _sign(parent: Node3D, position_value: Vector3, text_value: String, font_size: int, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.position = position_value
	label.rotation_degrees.y = 90.0
	label.text = text_value
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = MINT
	label.outline_size = 4
	label.double_sided = false
	parent.add_child(label)
	return label
