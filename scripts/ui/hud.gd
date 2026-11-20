class_name HUD
extends CanvasLayer
## Procedurally built heads-up display. Purely reactive: it only listens to signals from
## the CodexSignalSystem, PlayerController, HunterAIDirector and MissionDirector (wired by
## main.gd). The player camera is used only to project world markers onto the screen.

const PANEL_COLOR: Color = Color(0.02, 0.03, 0.05, 0.62)
const TEXT_COLOR: Color = Color(0.88, 0.92, 0.98)
const DIM_TEXT: Color = Color(0.6, 0.65, 0.74)
const IGNITION_COLOR: Color = Color(1.0, 0.22, 0.15)
const DEAD_ZONE_COLOR: Color = Color(0.7, 0.55, 1.0)
const ACCENT: Color = Color(0.35, 0.9, 1.0)

var _resonance_bar: ProgressBar
var _resonance_fill: StyleBoxFlat
var _resonance_value: Label
var _form_label: Label
var _ability_labels: Dictionary = {}
var _objective_labels: Array[Label] = []
var _ignition_label: Label
var _dead_zone_badge: PanelContainer
var _radio_label: Label
var _census_label: Label
var _stats_label: Label
var _crosshair: Label
var _toast: Label
var _interact_box: VBoxContainer
var _interact_label: Label
var _interact_bar: ProgressBar
var _meter_box: VBoxContainer
var _meter_label: Label
var _meter_bar: ProgressBar
var _meter_fill: StyleBoxFlat
var _caught_overlay: ColorRect
var _caught_label: Label
var _win_overlay: ColorRect
var _win_stats: Label
var _marker_root: Control
var _markers: Dictionary = {}

var _camera: Camera3D
var _player: Node3D
var _full_form: bool = false
var _ignited: bool = false
var _suppressed: bool = false
var _toast_time: float = 0.0
var _radio_time: float = 0.0
var _caught_time: float = 0.0
var _survival_time: float = 0.0
var _captures: int = 0
var _time: float = 0.0
var _won: bool = false


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_marker_root = Control.new()
	_marker_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_marker_root)
	_build_codex_panel(root)
	_build_alerts(root)
	_build_status_panel(root)
	_build_center(root)
	_build_help(root)
	_build_overlays(root)


func _process(delta: float) -> void:
	_time += delta
	if not _won:
		_survival_time += delta
	_stats_label.text = "TIME %s    CAPTURES %d" % [_format_time(_survival_time), _captures]
	if _ignited:
		_ignition_label.modulate.a = 0.55 + 0.45 * absf(sin(_time * 6.0))
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _radio_time > 0.0:
		_radio_time -= delta
		_radio_label.modulate.a = clampf(_radio_time, 0.0, 1.0)
	if _caught_time > 0.0:
		_caught_time -= delta
		var a: float = clampf(_caught_time / 2.5, 0.0, 1.0)
		_caught_overlay.color.a = 0.45 * a
		_caught_label.modulate.a = a
		_caught_overlay.visible = _caught_time > 0.0
	_update_markers()


# --- Binding -------------------------------------------------------------------------------

func bind_codex(codex: CodexSignalSystem) -> void:
	codex.resonance_changed.connect(_on_resonance_changed)
	codex.form_changed.connect(_on_form_changed)
	codex.codex_ignited.connect(_on_codex_ignited)
	codex.codex_ignition_ended.connect(_on_codex_ignition_ended)
	codex.broadcast_suppression_changed.connect(_on_suppression_changed)
	codex.dead_zone_changed.connect(_on_dead_zone_changed)
	codex.micro_fusion_triggered.connect(_on_micro_fusion)
	codex.feedback.connect(show_toast)
	codex.emit_full_state()


func bind_player(player: PlayerController) -> void:
	_player = player
	_camera = player.get_view_camera()
	player.interaction_prompt_changed.connect(_on_interaction_prompt)
	player.captured.connect(_on_captured)
	player.feedback.connect(show_toast)


func bind_director(director: HunterAIDirector) -> void:
	director.hunter_census_changed.connect(_on_census_changed)


func bind_mission(mission: MissionDirector) -> void:
	mission.objectives_changed.connect(_on_objectives_changed)
	mission.marker_changed.connect(_on_marker_changed)
	mission.transmission_progress.connect(_on_transmission_progress)
	mission.radio_message.connect(show_radio)
	mission.mission_completed.connect(_on_mission_completed)


func bind_terminal(_terminal: HackTerminal) -> void:
	pass


func show_toast(message: String) -> void:
	_toast.text = message
	_toast_time = 3.0
	_toast.modulate.a = 1.0


func show_radio(message: String) -> void:
	_radio_label.text = message
	_radio_time = 6.0
	_radio_label.modulate.a = 1.0


# --- Codex / player / director handlers --------------------------------------------------------

func _on_resonance_changed(value: float, max_value: float) -> void:
	_resonance_bar.max_value = max_value
	_resonance_bar.value = value
	_resonance_value.text = "%d" % int(value)
	var t: float = value / max_value
	_resonance_fill.bg_color = ACCENT.lerp(Color(1.0, 0.6, 0.15), clampf(t * 1.4, 0.0, 1.0)).lerp(IGNITION_COLOR, clampf((t - 0.75) * 4.0, 0.0, 1.0))


func _on_form_changed(form: StringName) -> void:
	_full_form = form == CodexSignalSystem.FORM_FULL
	_form_label.text = "FULL FORM" if _full_form else "BASE FORM  ·  stealth"
	_form_label.add_theme_color_override(&"font_color", CodexSignalSystem.get_ability_color(CodexSignalSystem.ABILITY_FULL_FORM) if _full_form else ACCENT)
	_refresh_ability(CodexSignalSystem.ABILITY_FULL_FORM)


func _on_codex_ignited(broadcasting: bool) -> void:
	_ignited = true
	_suppressed = not broadcasting
	_update_ignition_label()


func _on_codex_ignition_ended() -> void:
	_ignited = false
	_update_ignition_label()


func _on_suppression_changed(suppressed: bool) -> void:
	_suppressed = suppressed
	_update_ignition_label()


func _on_dead_zone_changed(inside: bool) -> void:
	_dead_zone_badge.visible = inside


func _on_micro_fusion(ability: StringName, _spike: float) -> void:
	var label: Label = _ability_labels.get(ability)
	if label != null:
		label.modulate = Color(2.0, 2.0, 2.0)
		create_tween().tween_property(label, "modulate", Color.WHITE, 0.4)


func _on_interaction_prompt(text: String, progress: float) -> void:
	_interact_box.visible = text != ""
	_interact_label.text = text
	_interact_bar.visible = progress >= 0.0
	_interact_bar.value = maxf(progress, 0.0)


func _on_captured(total_captures: int) -> void:
	_captures = total_captures
	_caught_time = 2.5
	_caught_overlay.visible = true


func _on_census_changed(patrolling: int, investigating: int, pursuing: int, decoyed: int) -> void:
	_census_label.text = "HUNTERS\npatrol %d  ·  searching %d  ·  pursuing %d  ·  decoyed %d" % [patrolling, investigating, pursuing, decoyed]
	_census_label.add_theme_color_override(&"font_color", IGNITION_COLOR if pursuing > 0 else TEXT_COLOR)


# --- Mission handlers --------------------------------------------------------------------------

func _on_objectives_changed(lines: PackedStringArray, active_index: int) -> void:
	for i: int in _objective_labels.size():
		var label: Label = _objective_labels[i]
		label.visible = i < lines.size()
		if i >= lines.size():
			continue
		label.text = lines[i]
		var done: bool = lines[i].begins_with("[x]")
		var color: Color = Color(0.45, 0.95, 0.55) if done else (TEXT_COLOR if i == active_index else DIM_TEXT)
		label.add_theme_color_override(&"font_color", color)


func _on_marker_changed(marker_id: StringName, world_position: Vector3, label_text: String, color: Color, shown: bool) -> void:
	var marker: Label = _markers.get(marker_id)
	if marker == null:
		marker = _make_label("", 15, color)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.size = Vector2(240.0, 40.0)
		_marker_root.add_child(marker)
		_markers[marker_id] = marker
	marker.set_meta(&"world", world_position)
	marker.set_meta(&"title", label_text)
	marker.add_theme_color_override(&"font_color", color)
	marker.visible = shown


func _on_observation_progress(progress: float) -> void:
	_show_meter(progress, "DECODING HUNTER HANDSHAKE - keep the scanning Hunter in sight", Color(0.4, 0.65, 1.0))


func _on_transmission_progress(progress: float, in_range: bool) -> void:
	var text: String = "UPLINK TRANSMISSION %d%%" % int(progress * 100.0)
	if not in_range:
		text += "  -  OUT OF RANGE, return to the relay!"
	_show_meter(progress, text, Color(0.35, 1.0, 0.55) if in_range else IGNITION_COLOR)


func _show_meter(progress: float, text: String, color: Color) -> void:
	_meter_box.visible = progress >= 0.0
	_meter_label.text = text
	_meter_bar.value = maxf(progress, 0.0)
	_meter_fill.bg_color = color


func _on_mission_completed(elapsed_seconds: float, captures: int) -> void:
	_won = true
	_win_overlay.visible = true
	_win_stats.text = "Time  %s\nCaptures  %d\n\nPress R to run it again" % [_format_time(elapsed_seconds), captures]
	_win_overlay.modulate.a = 0.0
	create_tween().tween_property(_win_overlay, "modulate:a", 1.0, 1.2)


# --- Helpers -----------------------------------------------------------------------------------

func _update_markers() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	for marker_id: Variant in _markers.keys():
		var marker: Label = _markers[marker_id]
		if not marker.visible:
			continue
		var world: Vector3 = marker.get_meta(&"world", Vector3.ZERO)
		var distance: float = _player.global_position.distance_to(world) if _player != null else 0.0
		marker.text = "◆\n%s  %d m" % [str(marker.get_meta(&"title", "")), int(distance)]
		var screen: Vector2 = _camera.unproject_position(world)
		if _camera.is_position_behind(world):
			screen = viewport_size - screen
			screen.y = viewport_size.y - 60.0
		screen.x = clampf(screen.x, 130.0, viewport_size.x - 130.0)
		screen.y = clampf(screen.y, 70.0, viewport_size.y - 90.0)
		marker.position = screen - Vector2(120.0, 12.0)


func _update_ignition_label() -> void:
	_ignition_label.visible = _ignited
	if _suppressed:
		_ignition_label.text = "CODEX IGNITED  ·  BROADCAST MASKED"
		_ignition_label.add_theme_color_override(&"font_color", DEAD_ZONE_COLOR)
	else:
		_ignition_label.text = "CODEX IGNITED  ·  LOCATION BROADCASTING"
		_ignition_label.add_theme_color_override(&"font_color", IGNITION_COLOR)


func _refresh_ability(ability: StringName) -> void:
	var label: Label = _ability_labels.get(ability)
	if label == null:
		return
	var status: String = "ready"
	var color: Color = CodexSignalSystem.get_ability_color(ability)
	if ability == CodexSignalSystem.ABILITY_FULL_FORM and _full_form:
		status = "ACTIVE"
	var key: String = {CodexSignalSystem.ABILITY_MICRO_DASH: "Shift", CodexSignalSystem.ABILITY_SUPER_JUMP: "Q", CodexSignalSystem.ABILITY_FULL_FORM: "F"}.get(ability, "")
	label.text = "%s  [%s]  ·  %s" % [CodexSignalSystem.get_ability_display_name(ability), key, status]
	label.add_theme_color_override(&"font_color", color)


func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


func _make_panel(color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.border_width_left = 2
	style.border_color = Color(ACCENT, 0.5)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override(&"panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _make_label(text: String, size: int, color: Color = TEXT_COLOR) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override(&"outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_bar(width: float, height: float, fill_color: Color) -> Array:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.show_percentage = false
	bar.max_value = 1.0
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.09, 0.12, 0.85)
	background.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override(&"background", background)
	bar.add_theme_stylebox_override(&"fill", fill)
	return [bar, fill]


func _build_codex_panel(root: Control) -> void:
	var panel := _make_panel(PANEL_COLOR)
	panel.position = Vector2(20.0, 20.0)
	panel.custom_minimum_size = Vector2(420.0, 0.0)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 5)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := _make_label("CODEX RESONANCE", 14, DIM_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_resonance_value = _make_label("0", 16)
	header.add_child(_resonance_value)

	var bar_parts: Array = _make_bar(390.0, 10.0, ACCENT)
	_resonance_bar = bar_parts[0]
	_resonance_fill = bar_parts[1]
	_resonance_bar.max_value = 100.0
	box.add_child(_resonance_bar)

	_form_label = _make_label("BASE FORM  ·  stealth", 19, ACCENT)
	box.add_child(_form_label)
	for ability: StringName in [CodexSignalSystem.ABILITY_MICRO_DASH, CodexSignalSystem.ABILITY_SUPER_JUMP, CodexSignalSystem.ABILITY_FULL_FORM]:
		var label := _make_label("", 15)
		_ability_labels[ability] = label
		box.add_child(label)
		_refresh_ability(ability)

	var objectives := _make_panel(PANEL_COLOR)
	objectives.position = Vector2(20.0, 196.0)
	objectives.custom_minimum_size = Vector2(420.0, 0.0)
	root.add_child(objectives)
	var obox := VBoxContainer.new()
	obox.add_theme_constant_override(&"separation", 4)
	objectives.add_child(obox)
	obox.add_child(_make_label("OBJECTIVES", 14, DIM_TEXT))
	for i: int in 3:
		var label := _make_label("", 15, DIM_TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(390.0, 0.0)
		obox.add_child(label)
		_objective_labels.append(label)


func _build_alerts(root: Control) -> void:
	_ignition_label = _make_label("", 28, IGNITION_COLOR)
	_ignition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ignition_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_ignition_label.offset_left = -500.0
	_ignition_label.offset_right = 500.0
	_ignition_label.offset_top = 22.0
	_ignition_label.offset_bottom = 60.0
	_ignition_label.visible = false
	root.add_child(_ignition_label)

	_dead_zone_badge = _make_panel(Color(0.2, 0.1, 0.4, 0.8))
	_dead_zone_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_dead_zone_badge.offset_left = -190.0
	_dead_zone_badge.offset_right = 190.0
	_dead_zone_badge.offset_top = 64.0
	_dead_zone_badge.offset_bottom = 104.0
	var badge_label := _make_label("DEAD ZONE  ·  signal masked  ·  decay ×3", 16, Color(0.92, 0.88, 1.0))
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead_zone_badge.add_child(badge_label)
	_dead_zone_badge.visible = false
	root.add_child(_dead_zone_badge)

	_radio_label = _make_label("", 17, Color(0.75, 0.95, 0.85))
	_radio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_radio_label.offset_left = -420.0
	_radio_label.offset_right = 420.0
	_radio_label.offset_top = -250.0
	_radio_label.offset_bottom = -180.0
	_radio_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_radio_label.modulate.a = 0.0
	root.add_child(_radio_label)


func _build_status_panel(root: Control) -> void:
	var panel := _make_panel(PANEL_COLOR)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -430.0
	panel.offset_right = -20.0
	panel.offset_top = 20.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_census_label = _make_label("HUNTERS", 15)
	box.add_child(_census_label)
	_stats_label = _make_label("", 14, DIM_TEXT)
	box.add_child(_stats_label)


func _build_center(root: Control) -> void:
	_crosshair = _make_label("·", 34)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -20.0
	_crosshair.offset_right = 20.0
	_crosshair.offset_top = -24.0
	_crosshair.offset_bottom = 16.0
	root.add_child(_crosshair)


	_interact_box = VBoxContainer.new()
	_interact_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_interact_box.offset_left = -260.0
	_interact_box.offset_right = 260.0
	_interact_box.offset_top = 70.0
	_interact_box.offset_bottom = 120.0
	_interact_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_interact_box.visible = false
	root.add_child(_interact_box)
	_interact_label = _make_label("", 19)
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_box.add_child(_interact_label)
	var interact_parts: Array = _make_bar(320.0, 6.0, ACCENT)
	_interact_bar = interact_parts[0]
	_interact_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_interact_box.add_child(_interact_bar)

	_meter_box = VBoxContainer.new()
	_meter_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_meter_box.offset_left = -330.0
	_meter_box.offset_right = 330.0
	_meter_box.offset_top = -170.0
	_meter_box.offset_bottom = -120.0
	_meter_box.visible = false
	root.add_child(_meter_box)
	_meter_label = _make_label("", 16)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter_box.add_child(_meter_label)
	var meter_parts: Array = _make_bar(660.0, 10.0, ACCENT)
	_meter_bar = meter_parts[0]
	_meter_fill = meter_parts[1]
	_meter_box.add_child(_meter_bar)

	_toast = _make_label("", 17)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -500.0
	_toast.offset_right = 500.0
	_toast.offset_top = -110.0
	_toast.offset_bottom = -80.0
	_toast.modulate.a = 0.0
	root.add_child(_toast)


func _build_help(root: Control) -> void:
	var help := _make_label(
		"WASD move · Mouse look · Space jump (again mid-air: Super Jump) · Q Super Jump · Shift Micro Dash · F Full Form\nE hold to interact · R restart · Esc release mouse",
		12, DIM_TEXT)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 20.0
	help.offset_right = 1400.0
	help.offset_top = -48.0
	help.offset_bottom = -12.0
	root.add_child(help)


func _build_overlays(root: Control) -> void:
	_caught_overlay = ColorRect.new()
	_caught_overlay.color = Color(0.6, 0.0, 0.0, 0.0)
	_caught_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caught_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caught_overlay.visible = false
	root.add_child(_caught_overlay)
	_caught_label = _make_label("CAUGHT BY THE HUNTERS", 48, Color(1.0, 0.88, 0.88))
	_caught_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caught_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caught_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caught_overlay.add_child(_caught_label)

	_win_overlay = ColorRect.new()
	_win_overlay.color = Color(0.0, 0.02, 0.03, 0.82)
	_win_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_win_overlay.visible = false
	root.add_child(_win_overlay)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -400.0
	box.offset_right = 400.0
	box.offset_top = -140.0
	box.offset_bottom = 140.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_win_overlay.add_child(box)
	var title := _make_label("CODEX TRANSMITTED", 54, Color(0.45, 1.0, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _make_label("The Codex is safe beyond the Hunters' reach.", 20)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	_win_stats = _make_label("", 18, DIM_TEXT)
	_win_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_win_stats)
