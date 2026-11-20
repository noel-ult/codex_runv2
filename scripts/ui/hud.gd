class_name HUD
extends CanvasLayer
## Minimal, diegetic-style heads-up display built in code. Purely reactive: it only listens to
## signals from the CodexSignalSystem, PlayerController (+ GadgetBelt), HunterAIDirector,
## MissionDirector and HackTerminal (wired by main.gd). The player camera is used only to
## orient the compass and project markers.
##
## Layout: compass strip (top-centre) - threat state (top-right) - current objective (top-left,
## TAB for the full log) - Codex cluster with Release countdown (bottom-left) - gadget readout
## (bottom-right) - interaction prompt (centre) - radio subtitles (bottom-centre).

const WHITE: Color = Color(0.93, 0.95, 0.97)
const DIM: Color = Color(0.62, 0.66, 0.72)
const FAINT: Color = Color(0.4, 0.43, 0.48)
const CYAN: Color = Color(0.4, 0.88, 1.0)
const AMBER: Color = Color(1.0, 0.72, 0.28)
const RED: Color = Color(1.0, 0.3, 0.24)
const GREEN: Color = Color(0.45, 0.95, 0.6)
const VIOLET: Color = Color(0.72, 0.58, 1.0)

var _font: SystemFont
var _root: Control
var _compass: Control
var _threat_label: Label
var _threat_sub: Label
var _objective_label: Label
var _objective_log: VBoxContainer
var _objective_lines: Array[Label] = []
var _resonance_bar: ProgressBar
var _resonance_fill: StyleBoxFlat
var _resonance_value: Label
var _release_label: Label
var _release_bar: ProgressBar
var _release_fill: StyleBoxFlat
var _form_label: Label
var _chips: HBoxContainer
var _chip_labels: Dictionary = {}
var _ability_labels: Dictionary = {}
var _gadget_name: Label
var _gadget_slots: Array[Label] = []
var _gadget_meta: Label
var _prompt_box: VBoxContainer
var _prompt_label: Label
var _prompt_bar: ProgressBar
var _subtitle: Label
var _toast: Label
var _meter_box: VBoxContainer
var _meter_label: Label
var _meter_bar: ProgressBar
var _meter_fill: StyleBoxFlat
var _vignette: ColorRect
var _vignette_material: ShaderMaterial
var _flash: ColorRect
var _caught_overlay: ColorRect
var _caught_label: Label
var _win_overlay: ColorRect
var _win_stats: Label

var _camera: Camera3D
var _player: Node3D
var _markers: Dictionary = {}
var _full_form: bool = false
var _ignited: bool = false
var _suppressed: bool = false
var _dead_zone: bool = false
var _disguise_role: String = ""
var _disguise_left: float = 0.0
var _lockdown: bool = false
var _threat: int = 0
var _toast_time: float = 0.0
var _subtitle_time: float = 0.0
var _caught_time: float = 0.0
var _flash_time: float = 0.0
var _captures: int = 0
var _time: float = 0.0
var _won: bool = false
var _vignette_strength: float = 0.0
var _release_left: float = 30.0
var _release_interval: float = 30.0


func _ready() -> void:
	layer = 10
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "Liberation Sans", "sans-serif"])
	_font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_vignette()
	_build_compass()
	_build_threat()
	_build_objective()
	_build_codex_cluster()
	_build_gadgets()
	_build_center()
	_build_overlays()


func _process(delta: float) -> void:
	_time += delta
	_compass.queue_redraw()
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _subtitle_time > 0.0:
		_subtitle_time -= delta
		_subtitle.modulate.a = clampf(_subtitle_time, 0.0, 1.0)
	if _flash_time > 0.0:
		_flash_time -= delta
		_flash.color.a = 0.18 * clampf(_flash_time / 0.5, 0.0, 1.0)
	if _caught_time > 0.0:
		_caught_time -= delta
		var a: float = clampf(_caught_time / 2.5, 0.0, 1.0)
		_caught_overlay.color.a = 0.5 * a
		_caught_label.modulate.a = a
		_caught_overlay.visible = _caught_time > 0.0
	if _disguise_left > 0.0:
		_disguise_left = maxf(_disguise_left - delta, 0.0)
	_update_release_visual()
	_update_chips()
	_update_vignette()


# --- Binding ------------------------------------------------------------------------------

func bind_codex(codex: CodexSignalSystem) -> void:
	codex.resonance_changed.connect(_on_resonance_changed)
	codex.form_changed.connect(_on_form_changed)
	codex.codex_ignited.connect(func(broadcasting: bool) -> void:
		_ignited = true
		_suppressed = not broadcasting)
	codex.codex_ignition_ended.connect(func() -> void: _ignited = false)
	codex.broadcast_suppression_changed.connect(func(s: bool) -> void: _suppressed = s)
	codex.dead_zone_changed.connect(func(inside: bool) -> void: _dead_zone = inside)
	codex.micro_fusion_triggered.connect(_on_micro_fusion)
	codex.feedback.connect(show_toast)
	codex.release_countdown.connect(func(left: float, interval: float) -> void:
		_release_left = left
		_release_interval = interval)
	codex.codex_released.connect(func(_p: Vector3, _r: float, from_decoy: bool) -> void:
		_flash_time = 0.5
		_flash.color = Color(AMBER if from_decoy else RED, 0.0))
	codex.emit_full_state()


func bind_player(player: PlayerController) -> void:
	_player = player
	_camera = player.get_view_camera()
	player.interaction_prompt_changed.connect(_on_interaction_prompt)
	player.captured.connect(_on_captured)
	player.feedback.connect(show_toast)
	player.disguise_changed.connect(func(active: bool, role: String, left: float) -> void:
		_disguise_role = role if active else ""
		_disguise_left = left if active else 0.0)
	var gadgets: GadgetBelt = player.get_gadgets()
	gadgets.inventory_changed.connect(_on_inventory_changed)
	gadgets.publish()


func bind_director(director: HunterAIDirector) -> void:
	director.hunter_census_changed.connect(_on_census_changed)


func bind_mission(mission: MissionDirector) -> void:
	mission.objectives_changed.connect(_on_objectives_changed)
	mission.marker_changed.connect(_on_marker_changed)
	mission.transmission_progress.connect(_on_transmission_progress)
	mission.radio_message.connect(show_radio)
	mission.mission_completed.connect(_on_mission_completed)
	mission.lockdown_started.connect(func() -> void: _lockdown = true)


func bind_terminal(terminal: HackTerminal) -> void:
	terminal.opened_changed.connect(func(open: bool) -> void: _root.visible = not open)


func show_toast(message: String) -> void:
	_toast.text = message
	_toast_time = 3.2
	_toast.modulate.a = 1.0


func show_radio(message: String) -> void:
	_subtitle.text = message
	_subtitle_time = 7.0
	_subtitle.modulate.a = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_objectives"):
		_objective_log.visible = not _objective_log.visible


# --- Handlers --------------------------------------------------------------------------------

func _on_resonance_changed(value: float, max_value: float) -> void:
	_resonance_bar.max_value = max_value
	_resonance_bar.value = value
	_resonance_value.text = "%d" % int(value)
	var t: float = value / max_value
	_resonance_fill.bg_color = CYAN.lerp(AMBER, clampf(t * 1.4, 0.0, 1.0)).lerp(RED, clampf((t - 0.75) * 4.0, 0.0, 1.0))


func _on_form_changed(form: StringName) -> void:
	_full_form = form == CodexSignalSystem.FORM_FULL
	_form_label.text = "FULL FORM" if _full_form else "BASE FORM"
	_form_label.add_theme_color_override(&"font_color", CodexSignalSystem.get_ability_color(CodexSignalSystem.ABILITY_FULL_FORM) if _full_form else DIM)


func _on_micro_fusion(ability: StringName, _spike: float) -> void:
	var label: Label = _ability_labels.get(ability)
	if label != null:
		label.modulate = Color(2.2, 2.2, 2.2)
		create_tween().tween_property(label, "modulate", Color.WHITE, 0.45)


func _on_interaction_prompt(text: String, progress: float) -> void:
	_prompt_box.visible = text != ""
	_prompt_label.text = text.replace("[Hold E] ", "")
	_prompt_label.text = ("E  ·  " + _prompt_label.text) if text.begins_with("[Hold E]") else text
	_prompt_bar.visible = progress >= 0.0
	_prompt_bar.value = maxf(progress, 0.0)


func _on_captured(total: int) -> void:
	_captures = total
	_caught_time = 2.5
	_caught_overlay.visible = true


func _on_census_changed(_patrolling: int, investigating: int, pursuing: int, decoyed: int) -> void:
	_threat = 2 if pursuing > 0 else (1 if investigating > 0 else 0)
	var texts: PackedStringArray = ["UNDETECTED", "SEARCHING", "HUNTED"]
	var colors: Array[Color] = [GREEN, AMBER, RED]
	_threat_label.text = texts[_threat]
	_threat_label.add_theme_color_override(&"font_color", colors[_threat])
	var sub: PackedStringArray = []
	if pursuing > 0:
		sub.append("%d in pursuit" % pursuing)
	if investigating > 0:
		sub.append("%d searching" % investigating)
	if decoyed > 0:
		sub.append("%d on decoy" % decoyed)
	_threat_sub.text = "  ·  ".join(sub)


func _on_inventory_changed(selected: StringName, darts: int, emps: int, cells: int, decoys_active: int) -> void:
	_gadget_name.text = GadgetBelt.display_name(selected)
	var counts: Array[String] = ["%d" % darts, "%d" % emps, "%d" % floori(cells / 2.0)]
	var ids: Array[StringName] = [GadgetBelt.GADGET_JAMMER, GadgetBelt.GADGET_EMP, GadgetBelt.GADGET_DECOY]
	var names: PackedStringArray = ["JAM", "EMP", "DCY"]
	for i: int in 3:
		var active: bool = ids[i] == selected
		_gadget_slots[i].text = "%d %s %s" % [i + 1, names[i], counts[i]]
		_gadget_slots[i].add_theme_color_override(&"font_color", WHITE if active else FAINT)
	_gadget_meta.text = "CELLS %d   ·   DECOYS %d/2" % [cells, decoys_active]


func _on_objectives_changed(lines: PackedStringArray, active_index: int) -> void:
	var current: String = lines[mini(active_index, lines.size() - 1)].substr(4) if not lines.is_empty() else ""
	_objective_label.text = current.to_upper() if active_index < lines.size() else "CODEX SAFE"
	for i: int in _objective_lines.size():
		var label: Label = _objective_lines[i]
		label.visible = i < lines.size()
		if i >= lines.size():
			continue
		var done: bool = lines[i].begins_with("[x]")
		label.text = ("✓  " if done else ("›  " if i == active_index else "·  ")) + lines[i].substr(4)
		label.add_theme_color_override(&"font_color", GREEN if done else (WHITE if i == active_index else FAINT))


func _on_marker_changed(marker_id: StringName, world_position: Vector3, label_text: String, color: Color, shown: bool) -> void:
	_markers[marker_id] = {"pos": world_position, "label": label_text, "color": color, "shown": shown}


func _on_transmission_progress(progress: float, in_range: bool) -> void:
	_meter_box.visible = progress >= 0.0
	_meter_label.text = "UPLINK  %d%%" % int(progress * 100.0) + ("" if in_range else "   ·   OUT OF RANGE")
	_meter_bar.value = maxf(progress, 0.0)
	_meter_fill.bg_color = GREEN if in_range else RED


func _on_mission_completed(elapsed_seconds: float, captures: int) -> void:
	_won = true
	_win_overlay.visible = true
	_win_stats.text = "%s   ·   %d captures\n\nR  ·  run it again" % [_format_time(elapsed_seconds), captures]
	_win_overlay.modulate.a = 0.0
	create_tween().tween_property(_win_overlay, "modulate:a", 1.0, 1.4)


# --- Per-frame visuals --------------------------------------------------------------------------

func _update_release_visual() -> void:
	var ratio: float = clampf(_release_left / maxf(_release_interval, 0.01), 0.0, 1.0)
	_release_bar.value = 1.0 - ratio
	var warning: bool = _release_left < 5.0
	var masked: bool = _dead_zone
	_release_label.text = "RELEASE  %s%s" % ["%.1f" % _release_left if warning else "%d s" % int(ceilf(_release_left)), "   ·   MASKED" if masked else ""]
	var color: Color = VIOLET if masked else (AMBER.lerp(RED, 0.5 + 0.5 * sin(_time * 12.0)) if warning else DIM)
	_release_label.add_theme_color_override(&"font_color", color)
	_release_fill.bg_color = VIOLET if masked else (RED if warning else AMBER.darkened(0.2))


func _update_chips() -> void:
	_set_chip(&"ignited", _ignited, "BROADCAST MASKED" if _suppressed else "IGNITED · BROADCASTING", VIOLET if _suppressed else RED)
	_set_chip(&"deadzone", _dead_zone, "DEAD ZONE", VIOLET)
	_set_chip(&"disguise", _disguise_role != "", "%s  %d:%02d" % [_disguise_role.to_upper(), floori(_disguise_left / 60.0), int(_disguise_left) % 60], CYAN)
	_set_chip(&"lockdown", _lockdown, "LOCKDOWN", RED)
	if _ignited and not _suppressed:
		(_chip_labels[&"ignited"] as Label).modulate.a = 0.6 + 0.4 * absf(sin(_time * 6.0))


func _set_chip(id: StringName, shown: bool, text: String, color: Color) -> void:
	var chip: Label = _chip_labels.get(id)
	if chip == null:
		chip = _label(12, color)
		_chips.add_child(chip)
		_chip_labels[id] = chip
	chip.visible = shown
	chip.text = text
	chip.add_theme_color_override(&"font_color", color)


func _update_vignette() -> void:
	var target: float = 0.0
	var color: Color = RED
	if _threat == 2:
		target = 0.55 + 0.15 * sin(_time * 4.0)
	elif _threat == 1:
		target = 0.25
		color = AMBER
	if _ignited and not _suppressed:
		target = maxf(target, 0.45)
	_vignette_strength = lerpf(_vignette_strength, target, 0.06)
	_vignette_material.set_shader_parameter(&"strength", _vignette_strength)
	_vignette_material.set_shader_parameter(&"tint", color)


func _draw_compass() -> void:
	var w: float = _compass.size.x
	var h: float = _compass.size.y
	var center: float = w * 0.5
	_compass.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.0, 0.0, 0.0, 0.18))
	if _camera == null or not is_instance_valid(_camera):
		return
	var forward: Vector3 = -_camera.global_basis.z
	var heading: float = rad_to_deg(atan2(forward.x, -forward.z))
	var span: float = 120.0
	var px_per_deg: float = w / span
	var names: Dictionary = {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	for d: int in range(0, 360, 15):
		var delta_deg: float = wrapf(float(d) - heading, -180.0, 180.0)
		if absf(delta_deg) > span * 0.5:
			continue
		var x: float = center + delta_deg * px_per_deg
		var fade: float = 1.0 - absf(delta_deg) / (span * 0.5)
		if names.has(d):
			var label: String = names[d]
			var color: Color = (WHITE if label.length() == 1 else DIM) * Color(1, 1, 1, fade)
			_compass.draw_string(_font, Vector2(x - 20.0, h - 7.0), label, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 13, color)
		else:
			_compass.draw_line(Vector2(x, h - 9.0), Vector2(x, h - 4.0), FAINT * Color(1, 1, 1, fade), 1.0)
	_compass.draw_line(Vector2(center, 0.0), Vector2(center, 5.0), WHITE, 2.0)
	if _player == null:
		return
	for marker_id: Variant in _markers.keys():
		var marker: Dictionary = _markers[marker_id]
		if not bool(marker.get("shown", false)):
			continue
		var pos: Vector3 = marker.get("pos", Vector3.ZERO)
		var to: Vector3 = pos - _player.global_position
		var bearing: float = rad_to_deg(atan2(to.x, -to.z))
		var delta_deg: float = clampf(wrapf(bearing - heading, -180.0, 180.0), -span * 0.5, span * 0.5)
		var x: float = center + delta_deg * px_per_deg
		var color: Color = marker.get("color", WHITE)
		var diamond := PackedVector2Array([Vector2(x, -2.0), Vector2(x + 5.0, 4.0), Vector2(x, 10.0), Vector2(x - 5.0, 4.0)])
		_compass.draw_colored_polygon(diamond, color)
		_compass.draw_string(_font, Vector2(x - 60.0, h + 15.0), "%s  %dm" % [str(marker.get("label", "")), int(to.length())], HORIZONTAL_ALIGNMENT_CENTER, 120.0, 11, color)


func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


# --- Construction ----------------------------------------------------------------------------

func _label(size_px: int, color: Color = WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", size_px)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _bar(width: float, height: float, color: Color) -> Array:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.show_percentage = false
	bar.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override(&"background", bg)
	bar.add_theme_stylebox_override(&"fill", fill)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return [bar, fill]


func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float strength = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.3, 0.24, 1.0);
void fragment() {
	vec2 c = UV - 0.5;
	float v = smoothstep(0.35, 0.75, length(c * vec2(1.0, 1.3)));
	COLOR = vec4(tint.rgb, v * strength * 0.55);
}"""
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = shader
	_vignette.material = _vignette_material
	_root.add_child(_vignette)
	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 0.3, 0.2, 0.0)
	_root.add_child(_flash)


func _build_compass() -> void:
	_compass = Control.new()
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_compass.offset_left = -190.0
	_compass.offset_right = 190.0
	_compass.offset_top = 16.0
	_compass.offset_bottom = 40.0
	_compass.draw.connect(_draw_compass)
	_root.add_child(_compass)


func _build_threat() -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -220.0
	box.offset_right = -24.0
	box.offset_top = 16.0
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_root.add_child(box)
	_threat_label = _label(17, GREEN)
	_threat_label.text = "UNDETECTED"
	_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_threat_label)
	_threat_sub = _label(12, DIM)
	_threat_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_threat_sub)


func _build_objective() -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(24.0, 16.0)
	box.add_theme_constant_override(&"separation", 3)
	_root.add_child(box)
	var tag := _label(11, AMBER)
	tag.text = "OBJECTIVE   ·   TAB  log"
	box.add_child(tag)
	_objective_label = _label(15, WHITE)
	_objective_label.custom_minimum_size = Vector2(250.0, 0.0)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_objective_label)
	_objective_log = VBoxContainer.new()
	_objective_log.visible = false
	_objective_log.add_theme_constant_override(&"separation", 2)
	box.add_child(_objective_log)
	for i: int in 4:
		var line := _label(13, FAINT)
		line.custom_minimum_size = Vector2(300.0, 0.0)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_objective_log.add_child(line)
		_objective_lines.append(line)


func _build_codex_cluster() -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 24.0
	box.offset_top = -132.0
	box.offset_right = 340.0
	box.offset_bottom = -20.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override(&"separation", 4)
	_root.add_child(box)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override(&"separation", 14)
	box.add_child(_chips)
	var head := HBoxContainer.new()
	box.add_child(head)
	_form_label = _label(12, DIM)
	_form_label.text = "BASE FORM"
	_form_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_form_label)
	_resonance_value = _label(12, WHITE)
	_resonance_value.text = "0"
	head.add_child(_resonance_value)
	var res_parts: Array = _bar(300.0, 4.0, CYAN)
	_resonance_bar = res_parts[0]
	_resonance_fill = res_parts[1]
	_resonance_bar.max_value = 100.0
	box.add_child(_resonance_bar)
	_release_label = _label(11, DIM)
	box.add_child(_release_label)
	var rel_parts: Array = _bar(300.0, 2.0, AMBER)
	_release_bar = rel_parts[0]
	_release_fill = rel_parts[1]
	box.add_child(_release_bar)
	var abilities := HBoxContainer.new()
	abilities.add_theme_constant_override(&"separation", 16)
	box.add_child(abilities)
	var defs: Array[Array] = [[CodexSignalSystem.ABILITY_MICRO_DASH, "SHIFT"], [CodexSignalSystem.ABILITY_SUPER_JUMP, "Q"], [CodexSignalSystem.ABILITY_FULL_FORM, "F"]]
	for def: Array in defs:
		var ability: StringName = def[0]
		var label := _label(11, CodexSignalSystem.get_ability_color(ability).lerp(DIM, 0.35))
		label.text = "%s  %s" % [str(def[1]), CodexSignalSystem.get_ability_display_name(ability)]
		abilities.add_child(label)
		_ability_labels[ability] = label


func _build_gadgets() -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -300.0
	box.offset_right = -24.0
	box.offset_top = -90.0
	box.offset_bottom = -20.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override(&"separation", 3)
	_root.add_child(box)
	_gadget_name = _label(15, WHITE)
	_gadget_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_gadget_name)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 14)
	box.add_child(row)
	for i: int in 3:
		var slot := _label(12, FAINT)
		row.add_child(slot)
		_gadget_slots.append(slot)
	_gadget_meta = _label(11, FAINT)
	_gadget_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_gadget_meta)
	var hint := _label(10, FAINT)
	hint.text = "LMB use  ·  1 2 3 / wheel select"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hint)


func _build_center() -> void:
	var dot := ColorRect.new()
	dot.color = Color(1.0, 1.0, 1.0, 0.8)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dot.offset_left = -1.5
	dot.offset_right = 1.5
	dot.offset_top = -1.5
	dot.offset_bottom = 1.5
	_root.add_child(dot)

	_prompt_box = VBoxContainer.new()
	_prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt_box.offset_left = -240.0
	_prompt_box.offset_right = 240.0
	_prompt_box.offset_top = 46.0
	_prompt_box.offset_bottom = 90.0
	_prompt_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_prompt_box.visible = false
	_root.add_child(_prompt_box)
	_prompt_label = _label(14, WHITE)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_box.add_child(_prompt_label)
	var prompt_parts: Array = _bar(180.0, 3.0, WHITE)
	_prompt_bar = prompt_parts[0]
	_prompt_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prompt_box.add_child(_prompt_bar)

	_meter_box = VBoxContainer.new()
	_meter_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_meter_box.offset_left = -200.0
	_meter_box.offset_right = 200.0
	_meter_box.offset_top = 70.0
	_meter_box.offset_bottom = 100.0
	_meter_box.visible = false
	_root.add_child(_meter_box)
	_meter_label = _label(12, WHITE)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter_box.add_child(_meter_label)
	var meter_parts: Array = _bar(400.0, 3.0, GREEN)
	_meter_bar = meter_parts[0]
	_meter_fill = meter_parts[1]
	_meter_box.add_child(_meter_bar)

	_subtitle = _label(15, Color(0.92, 0.94, 0.9))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle.offset_left = -380.0
	_subtitle.offset_right = 380.0
	_subtitle.offset_top = -190.0
	_subtitle.offset_bottom = -140.0
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_subtitle.modulate.a = 0.0
	_root.add_child(_subtitle)
	_toast = _label(12, DIM)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -380.0
	_toast.offset_right = 380.0
	_toast.offset_top = -136.0
	_toast.offset_bottom = -116.0
	_toast.modulate.a = 0.0
	_root.add_child(_toast)


func _build_overlays() -> void:
	_caught_overlay = ColorRect.new()
	_caught_overlay.color = Color(0.4, 0.0, 0.0, 0.0)
	_caught_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caught_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caught_overlay.visible = false
	add_child(_caught_overlay)
	_caught_label = _label(34, Color(1.0, 0.9, 0.88))
	_caught_label.text = "CAPTURED"
	_caught_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caught_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caught_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caught_overlay.add_child(_caught_label)

	_win_overlay = ColorRect.new()
	_win_overlay.color = Color(0.0, 0.01, 0.02, 0.85)
	_win_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_win_overlay.visible = false
	add_child(_win_overlay)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -400.0
	box.offset_right = 400.0
	box.offset_top = -100.0
	box.offset_bottom = 100.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_win_overlay.add_child(box)
	var title := _label(38, GREEN)
	title.text = "CODEX TRANSMITTED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _label(15, DIM)
	subtitle.text = "The Codex is beyond the Hunters' reach."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	_win_stats = _label(14, DIM)
	_win_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_win_stats)
