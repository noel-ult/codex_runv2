class_name FieldContracts
extends Node3D
## Optional city contracts. The composition root connects rewards, markers and capture.

signal reward_requested(amount: int, reason: String)
signal marker_changed(id: StringName, pos: Vector3, label: String, color: Color, shown: bool)
signal status_changed(text: String)
signal feedback(message: String)

const CASE_REWARD: int = 75
const SURVEY_REWARD: int = 90
const SURVEY_WINDOW: float = 55.0
const CASE_COLOR: Color = Color(1.0, 0.70, 0.36)
const SURVEY_COLOR: Color = Color(0.53, 0.78, 1.0)
const DISPATCH_COLOR: Color = Color(0.86, 0.70, 1.0)
const CASE_SITES: Array[Vector3] = [
	Vector3(-29.0, 0.1, -49.8),
	Vector3(48.8, 0.1, 48.65),
	Vector3(-20.3, 0.1, 48.6),
]
const SURVEY_SITES: Array[Vector3] = [
	Vector3(-49.9, 0.1, 30.7),
	Vector3(49.85, 0.1, 31.0),
]

enum State { AVAILABLE, FIND_CASE, RETURN_CASE, SCAN_FIRST, SCAN_SECOND }

var _state: State = State.AVAILABLE
var _player: PlayerController
var _case_dispatch: Interactable
var _survey_dispatch: Interactable
var _case_sign: Label3D
var _survey_sign: Label3D
var _case_ports: Array[Interactable] = []
var _survey_ports: Array[Interactable] = []
var _case_models: Array[MeshInstance3D] = []
var _survey_lights: Array[MeshInstance3D] = []
var _case_slot: int = 0
var _survey_start: int = 0
var _scan_left: float = 0.0
var _status_seconds: int = -1
var _dispatch_needs_release: bool = false


func _ready() -> void:
	_build_dispatch()
	_build_case_sites()
	_build_survey_sites()
	_refresh()


func setup(player: PlayerController) -> void:
	_player = player
	_refresh()


func on_runner_captured(_total: int) -> void:
	if _state != State.AVAILABLE:
		_end_contract()
		feedback.emit("Field contract lost on capture. Pick up another at dispatch.")


func _physics_process(delta: float) -> void:
	if _dispatch_needs_release and not Input.is_action_pressed(&"interact"):
		_dispatch_needs_release = false
		_update_processing()
	if _state != State.SCAN_SECOND:
		return
	_scan_left -= delta
	if _scan_left <= 0.0:
		_end_contract()
		feedback.emit("Survey window expired. Return to dispatch for another attempt.")
		return
	var seconds: int = ceili(_scan_left)
	if seconds != _status_seconds:
		_status_seconds = seconds
		_publish_status()


func _can_use(actor: Node3D, port: Interactable) -> bool:
	if _player == null or actor != _player or not _player.input_enabled or _player.is_driving():
		return false
	if not port.is_available_for(actor):
		return false
	var target: Vector3 = port.global_position + Vector3.UP * 0.45
	var mask: int = GeometryKit.WORLD_LAYER | GeometryKit.DOOR_LAYER
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(_player.get_head_position(), target, mask, [_player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _can_use_dispatch(actor: Node3D, port: Interactable) -> bool:
	return not _dispatch_needs_release and _can_use(actor, port)


func _on_dispatch_used(port: Interactable, actor: Node3D) -> void:
	if not _can_use_dispatch(actor, port):
		return
	_dispatch_needs_release = Input.is_action_pressed(&"interact")
	match _state:
		State.AVAILABLE:
			if port == _case_dispatch:
				_state = State.FIND_CASE
				feedback.emit("Recover the data case at the marked cache. Bring it back to this kiosk for %d credits." % CASE_REWARD)
			else:
				_state = State.SCAN_FIRST
				feedback.emit("Scan the first receiver, then reach the second within %d seconds. The clock starts at the first scan." % int(SURVEY_WINDOW))
			_refresh()
		State.RETURN_CASE:
			_case_slot = (_case_slot + 1) % _case_ports.size()
			_end_contract()
			reward_requested.emit(CASE_REWARD, "Case recovery")
			feedback.emit("Case delivered. Earned %d credits." % CASE_REWARD)
		_:
			_end_contract()
			feedback.emit("Field contract abandoned. Both jobs are available again.")


func _on_case_collected(port: Interactable, actor: Node3D, slot: int) -> void:
	if _state != State.FIND_CASE or slot != _case_slot or not _can_use(actor, port):
		return
	_state = State.RETURN_CASE
	_refresh()
	feedback.emit("Case recovered. Bring it back to the recovery kiosk at dispatch.")


func _on_receiver_scanned(port: Interactable, actor: Node3D, slot: int) -> void:
	if not _can_use(actor, port):
		return
	if _state == State.SCAN_FIRST and slot == _survey_start:
		_state = State.SCAN_SECOND
		_scan_left = SURVEY_WINDOW
		_status_seconds = ceili(SURVEY_WINDOW)
		_refresh()
		feedback.emit("First signal logged. Reach the second receiver before the timer runs out.")
	elif _state == State.SCAN_SECOND and slot != _survey_start and _scan_left > 0.0:
		_survey_start = slot
		_end_contract()
		reward_requested.emit(SURVEY_REWARD, "Signal survey")
		feedback.emit("Survey complete. Earned %d credits." % SURVEY_REWARD)


func _end_contract() -> void:
	_state = State.AVAILABLE
	_scan_left = 0.0
	_status_seconds = -1
	_refresh()


func _update_processing() -> void:
	set_physics_process(_dispatch_needs_release or _state == State.SCAN_SECOND)


func _refresh() -> void:
	var available: bool = _state == State.AVAILABLE and _player != null
	var recovering: bool = _state == State.FIND_CASE or _state == State.RETURN_CASE
	var surveying: bool = _state == State.SCAN_FIRST or _state == State.SCAN_SECOND
	_case_dispatch.enabled = available or recovering
	_survey_dispatch.enabled = available or surveying
	_case_dispatch.prompt = "Accept case recovery (+%d credits)" % CASE_REWARD
	_survey_dispatch.prompt = "Accept signal survey (+%d credits)" % SURVEY_REWARD
	_case_sign.text = "CASE RECOVERY\n%d CR" % CASE_REWARD
	_survey_sign.text = "SIGNAL SURVEY\n%d CR" % SURVEY_REWARD
	if recovering:
		_case_dispatch.prompt = "Return the recovered case" if _state == State.RETURN_CASE else "Abandon case recovery"
		_case_sign.text = "CASE RECOVERY\nJOB ACTIVE"
	if surveying:
		_survey_dispatch.prompt = "Abandon signal survey"
		_survey_sign.text = "SIGNAL SURVEY\nJOB ACTIVE"

	for slot: int in _case_ports.size():
		var active: bool = _state == State.FIND_CASE and slot == _case_slot
		_case_ports[slot].enabled = active
		_case_models[slot].visible = active
	for slot: int in _survey_ports.size():
		var active: bool = (_state == State.SCAN_FIRST and slot == _survey_start) or (_state == State.SCAN_SECOND and slot != _survey_start)
		_survey_ports[slot].enabled = active
		_survey_lights[slot].visible = active

	var target: Interactable = _case_ports[_case_slot]
	var target_label: String = "RECOVER CASE"
	var target_color: Color = CASE_COLOR
	match _state:
		State.RETURN_CASE:
			target = _case_dispatch
			target_label = "RETURN CASE"
		State.SCAN_FIRST, State.SCAN_SECOND:
			var first: bool = _state == State.SCAN_FIRST
			target = _survey_ports[_survey_start if first else 1 - _survey_start]
			target_label = "SCAN SIGNAL %d/2" % (1 if first else 2)
			target_color = SURVEY_COLOR
	var dispatch_position: Vector3 = (_case_dispatch.global_position + _survey_dispatch.global_position) * 0.5
	marker_changed.emit(&"field_dispatch", dispatch_position + Vector3.UP * 1.8, "FIELD CONTRACTS", DISPATCH_COLOR, available)
	marker_changed.emit(&"field_target", target.global_position + Vector3.UP * 1.35, target_label, target_color, _state != State.AVAILABLE)
	_publish_status()
	_update_processing()


func _publish_status() -> void:
	var text: String = ""
	match _state:
		State.FIND_CASE:
			text = "CASE RECOVERY  ·  FIND THE DATA CASE"
		State.RETURN_CASE:
			text = "CASE RECOVERY  ·  RETURN TO DISPATCH"
		State.SCAN_FIRST:
			text = "SIGNAL SURVEY  ·  SCAN POINT 1 OF 2"
		State.SCAN_SECOND:
			text = "SIGNAL SURVEY  ·  POINT 2 OF 2  ·  %ds" % _status_seconds
	status_changed.emit(text)


func _build_dispatch() -> void:
	var case_kiosk: Node3D = _place_site("RecoveryKiosk", Vector3(8.25, 0.1, 27.25), -90.0)
	var survey_kiosk: Node3D = _place_site("SurveyKiosk", Vector3(8.25, 0.1, 30.75), -90.0)
	_case_sign = _build_kiosk(case_kiosk, CASE_COLOR)
	_survey_sign = _build_kiosk(survey_kiosk, SURVEY_COLOR)
	_case_dispatch = _add_port(case_kiosk, "", Vector3(0.0, 0.64, 0.79), 0.85)
	_survey_dispatch = _add_port(survey_kiosk, "", Vector3(0.0, 0.64, 0.79), 0.85)
	for port: Interactable in [_case_dispatch, _survey_dispatch]:
		port.requirement = _can_use_dispatch.bind(port)
		port.requirement_hint = "Approach the kiosk and press E again"
		port.completed.connect(_on_dispatch_used)


func _build_kiosk(kiosk: Node3D, color: Color) -> Label3D:
	var steel: StandardMaterial3D = MaterialLibrary.coated(Color(0.10, 0.14, 0.18), 0.4, 0.48)
	var brace: StandardMaterial3D = MaterialLibrary.coated(Color(0.27, 0.30, 0.35), 0.56, 0.41)
	var light: StandardMaterial3D = MaterialLibrary.emissive(color, 1.7)
	GeometryKit.solid_box(kiosk, Vector3(0.0, 0.63, 0.0), Vector3(0.82, 1.26, 0.52), steel)
	GeometryKit.mesh_box(kiosk, Vector3(0.0, 1.31, 0.04), Vector3(0.94, 0.11, 0.67), brace)
	GeometryKit.mesh_box(kiosk, Vector3(0.0, 0.92, 0.274), Vector3(0.60, 0.30, 0.035), brace)
	GeometryKit.mesh_box(kiosk, Vector3(0.0, 1.18, 0.271), Vector3(0.64, 0.034, 0.024), light)
	for index: int in 3:
		GeometryKit.mesh_box(kiosk, Vector3(-0.17 + index * 0.17, 0.89, 0.298), Vector3(0.07, 0.027, 0.01), light)
	return _add_sign(kiosk, Vector3(0.0, 1.6, 0.28), color)


func _build_case_sites() -> void:
	var cache_material: StandardMaterial3D = MaterialLibrary.coated(Color(0.27, 0.29, 0.25), 0.28, 0.82)
	var case_material: StandardMaterial3D = MaterialLibrary.coated(Color(0.40, 0.23, 0.09), 0.34, 0.55)
	for slot: int in CASE_SITES.size():
		var cache: Node3D = _place_site("CaseCache%d" % slot, CASE_SITES[slot], 0.0)
		GeometryKit.solid_box(cache, Vector3(0.0, 0.235, 0.0), Vector3(0.77, 0.47, 0.56), cache_material)
		GeometryKit.mesh_box(cache, Vector3(0.0, 0.46, 0.0), Vector3(0.83, 0.08, 0.61), cache_material)
		var data_case: MeshInstance3D = GeometryKit.mesh_box(cache, Vector3(0.0, 0.585, 0.03), Vector3(0.47, 0.17, 0.31), case_material)
		GeometryKit.mesh_box(data_case, Vector3(0.0, 0.09, 0.0), Vector3(0.30, 0.027, 0.10), MaterialLibrary.emissive(CASE_COLOR, 2.0))
		var port: Interactable = _add_port(cache, "Recover the data case", Vector3(0.0, 0.49, 0.0), 1.15)
		port.completed.connect(_on_case_collected.bind(slot))
		_case_models.append(data_case)
		_case_ports.append(port)


func _build_survey_sites() -> void:
	var housing: StandardMaterial3D = MaterialLibrary.coated(Color(0.10, 0.17, 0.24), 0.43, 0.47)
	var lit: StandardMaterial3D = MaterialLibrary.emissive(SURVEY_COLOR, 2.2)
	for slot: int in SURVEY_SITES.size():
		var receiver: Node3D = _place_site("SignalReceiver%d" % slot, SURVEY_SITES[slot], 0.0)
		GeometryKit.cylinder(receiver, Vector3(0.0, 0.07, 0.0), 0.24, 0.27, 0.14, housing, 12)
		GeometryKit.cylinder(receiver, Vector3(0.0, 0.53, 0.0), 0.09, 0.12, 0.92, housing, 12)
		GeometryKit.mesh_box(receiver, Vector3(0.0, 1.06, 0.0), Vector3(0.43, 0.29, 0.26), housing)
		GeometryKit.cylinder(receiver, Vector3(0.14, 1.33, 0.0), 0.016, 0.025, 0.28, housing, 8)
		_survey_lights.append(GeometryKit.sphere(receiver, Vector3(0.14, 1.5, 0.0), 0.04, lit))
		var port: Interactable = _add_port(receiver, "Log receiver signal", Vector3(0.0, 0.85, 0.0), 1.35)
		port.completed.connect(_on_receiver_scanned.bind(slot))
		_survey_ports.append(port)


func _place_site(site_name: String, at: Vector3, yaw: float) -> Node3D:
	var site: Node3D = Node3D.new()
	site.name = site_name
	add_child(site)
	site.global_position = at
	site.rotation_degrees.y = yaw
	return site


func _add_port(site: Node3D, text: String, offset: Vector3, duration: float) -> Interactable:
	var port: Interactable = Interactable.new()
	port.name = "Interaction"
	port.prompt = text
	port.position = offset
	port.radius = 1.4
	port.height_tolerance = 1.05
	port.hold_time = duration
	port.enabled = false
	port.requirement = _can_use.bind(port)
	port.requirement_hint = "Move closer on foot"
	site.add_child(port)
	return port


func _add_sign(site: Node3D, at: Vector3, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.position = at
	label.font_size = 29
	label.pixel_size = 0.0047
	label.outline_size = 4
	label.outline_modulate = Color(0.029, 0.04, 0.06)
	label.modulate = color
	label.double_sided = false
	site.add_child(label)
	return label
