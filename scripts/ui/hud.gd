class_name HUD
extends CanvasLayer
## Procedurally built heads-up display. Purely reactive: it only listens to signals from
## the CodexSignalSystem, PlayerController and HunterAIDirector (wired by main.gd).

const PANEL_COLOR: Color = Color(0.03, 0.04, 0.07, 0.72)
const TEXT_COLOR: Color = Color(0.88, 0.93, 1.0)
const IGNITION_COLOR: Color = Color(1.0, 0.18, 0.12)
const DEAD_ZONE_COLOR: Color = Color(0.62, 0.45, 1.0)

var _resonance_bar: ProgressBar
var _resonance_fill: StyleBoxFlat
var _resonance_value: Label
var _form_label: Label
var _ability_labels: Dictionary = {}
var _ignition_label: Label
var _dead_zone_badge: PanelContainer
var _census_label: Label
var _stats_label: Label
var _crosshair: Label
var _fracture_prompt: Label
var _toast: Label
var _caught_overlay: ColorRect
var _caught_label: Label

var _ignited: bool = false
var _suppressed: bool = false
var _toast_time: float = 0.0
var _caught_time: float = 0.0
var _survival_time: float = 0.0
var _best_survival: float = 0.0
var _captures: int = 0
var _time: float = 0.0


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_codex_panel(root)
	_build_alerts(root)
	_build_status_panel(root)
	_build_center(root)
	_build_help(root)
	_build_caught_overlay(root)


func _process(delta: float) -> void:
	_time += delta
	_survival_time += delta
	_best_survival = maxf(_best_survival, _survival_time)
	_stats_label.text = "SURVIVED %s   BEST %s   CAPTURES %d" % [_format_time(_survival_time), _format_time(_best_survival), _captures]

	if _ignited:
		var blink: float = 0.55 + 0.45 * absf(sin(_time * 6.0))
		_ignition_label.modulate.a = blink
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _caught_time > 0.0:
		_caught_time -= delta
		var a: float = clampf(_caught_time / 2.5, 0.0, 1.0)
		_caught_overlay.color.a = 0.45 * a
		_caught_label.modulate.a = a
		_caught_overlay.visible = _caught_time > 0.0


# --- Binding -------------------------------------------------------------------------------

func bind_codex(codex: CodexSignalSystem) -> void:
	codex.resonance_changed.connect(_on_resonance_changed)
	codex.form_changed.connect(_on_form_changed)
	codex.codex_ignited.connect(_on_codex_ignited)
	codex.codex_ignition_ended.connect(_on_codex_ignition_ended)
	codex.broadcast_suppression_changed.connect(_on_suppression_changed)
	codex.dead_zone_changed.connect(_on_dead_zone_changed)
	codex.ability_lock_changed.connect(_on_ability_lock_changed)
	codex.micro_fusion_triggered.connect(_on_micro_fusion)
	codex.feedback.connect(show_toast)
	codex.emit_full_state()


func bind_player(player: PlayerController) -> void:
	player.fracture_target_changed.connect(_on_fracture_target_changed)
	player.captured.connect(_on_captured)
	player.feedback.connect(show_toast)


func bind_director(director: HunterAIDirector) -> void:
	director.hunter_census_changed.connect(_on_census_changed)


func show_toast(message: String) -> void:
	_toast.text = message
	_toast_time = 3.0
	_toast.modulate.a = 1.0


# --- Signal handlers ---------------------------------------------------------------------------

func _on_resonance_changed(value: float, max_value: float) -> void:
	_resonance_bar.max_value = max_value
	_resonance_bar.value = value
	_resonance_value.text = "%5.1f / %d" % [value, int(max_value)]
	var t: float = value / max_value
	_resonance_fill.bg_color = Color(0.1, 0.85, 0.9).lerp(Color(1.0, 0.55, 0.1), clampf(t * 1.4, 0.0, 1.0)).lerp(IGNITION_COLOR, clampf((t - 0.75) * 4.0, 0.0, 1.0))


func _on_form_changed(form: StringName) -> void:
	var full: bool = form == CodexSignalSystem.FORM_FULL
	_form_label.text = "FORM: %s" % ("FULL FORM" if full else "BASE (stealth)")
	_form_label.add_theme_color_override(&"font_color", CodexSignalSystem.get_ability_color(CodexSignalSystem.ABILITY_FULL_FORM) if full else Color(0.4, 0.95, 1.0))
	_refresh_ability(CodexSignalSystem.ABILITY_FULL_FORM)


func _on_codex_ignited(broadcasting: bool) -> void:
	_ignited = true
	_suppressed = not broadcasting
	_update_ignition_label()
	show_toast("CODEX IGNITION! Your location is being broadcast.")


func _on_codex_ignition_ended() -> void:
	_ignited = false
	_update_ignition_label()


func _on_suppression_changed(suppressed: bool) -> void:
	_suppressed = suppressed
	_update_ignition_label()


func _on_dead_zone_changed(inside: bool) -> void:
	_dead_zone_badge.visible = inside


func _on_ability_lock_changed(ability: StringName, locked: bool, holder_name: String) -> void:
	var label: Label = _ability_labels.get(ability)
	if label == null:
		return
	label.set_meta(&"locked", locked)
	label.set_meta(&"holder", holder_name)
	_refresh_ability(ability)


func _on_micro_fusion(ability: StringName, spike: float) -> void:
	var label: Label = _ability_labels.get(ability)
	if label != null:
		label.modulate = Color(2.0, 2.0, 2.0)
		create_tween().tween_property(label, "modulate", Color.WHITE, 0.4)
	show_toast("%s  +%d Resonance" % [CodexSignalSystem.get_ability_display_name(ability), int(spike)])


func _on_fracture_target_changed(has_target: bool, target_name: String) -> void:
	_fracture_prompt.visible = has_target
	_fracture_prompt.text = "[E] FRACTURE CODEX ONTO %s" % target_name.to_upper()
	_crosshair.add_theme_color_override(&"font_color", Color(1.0, 0.4, 0.95) if has_target else TEXT_COLOR)


func _on_captured(total_captures: int) -> void:
	_captures = total_captures
	_survival_time = 0.0
	_caught_time = 2.5
	_caught_overlay.visible = true


func _on_census_changed(patrolling: int, investigating: int, pursuing: int, decoyed: int) -> void:
	_census_label.text = "HUNTERS\n[PATROL] %d   [INVESTIGATE] %d\n[APEX PURSUIT] %d   [CHASE DECOY] %d" % [patrolling, investigating, pursuing, decoyed]
	_census_label.add_theme_color_override(&"font_color", IGNITION_COLOR if pursuing > 0 else TEXT_COLOR)


# --- Helpers -----------------------------------------------------------------------------------

func _update_ignition_label() -> void:
	_ignition_label.visible = _ignited
	if _suppressed:
		_ignition_label.text = "CODEX IGNITED - BROADCAST MASKED"
		_ignition_label.add_theme_color_override(&"font_color", DEAD_ZONE_COLOR)
	else:
		_ignition_label.text = "!! CODEX IGNITED - LOCATION BROADCASTING !!"
		_ignition_label.add_theme_color_override(&"font_color", IGNITION_COLOR)


func _refresh_ability(ability: StringName) -> void:
	var label: Label = _ability_labels.get(ability)
	if label == null:
		return
	var locked: bool = bool(label.get_meta(&"locked", false))
	var holder: String = str(label.get_meta(&"holder", ""))
	var status: String = "READY"
	var color: Color = CodexSignalSystem.get_ability_color(ability)
	if locked:
		status = "FRACTURED -> %s (LOCKED)" % holder.to_upper()
		color = Color(0.55, 0.55, 0.6)
	elif ability == CodexSignalSystem.ABILITY_FULL_FORM and _form_label.text.contains("FULL FORM"):
		status = "ACTIVE"
	label.text = "%-11s %s" % [CodexSignalSystem.get_ability_display_name(ability), status]
	label.add_theme_color_override(&"font_color", color)


func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


func _make_panel(color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
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
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_codex_panel(root: Control) -> void:
	var panel := _make_panel(PANEL_COLOR)
	panel.position = Vector2(20.0, 20.0)
	panel.custom_minimum_size = Vector2(430.0, 0.0)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := _make_label("CODEX RESONANCE", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_resonance_value = _make_label("0.0 / 100", 18)
	header.add_child(_resonance_value)

	_resonance_bar = ProgressBar.new()
	_resonance_bar.custom_minimum_size = Vector2(400.0, 22.0)
	_resonance_bar.show_percentage = false
	_resonance_bar.max_value = 100.0
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.12, 0.13, 0.18)
	background.set_corner_radius_all(4)
	_resonance_fill = StyleBoxFlat.new()
	_resonance_fill.bg_color = Color(0.1, 0.85, 0.9)
	_resonance_fill.set_corner_radius_all(4)
	_resonance_bar.add_theme_stylebox_override(&"background", background)
	_resonance_bar.add_theme_stylebox_override(&"fill", _resonance_fill)
	box.add_child(_resonance_bar)

	_form_label = _make_label("FORM: BASE (stealth)", 20, Color(0.4, 0.95, 1.0))
	box.add_child(_form_label)
	box.add_child(_make_label("ABILITIES", 14, Color(0.6, 0.65, 0.75)))
	for ability: StringName in [CodexSignalSystem.ABILITY_MICRO_DASH, CodexSignalSystem.ABILITY_SUPER_JUMP, CodexSignalSystem.ABILITY_FULL_FORM]:
		var label := _make_label("", 17)
		_ability_labels[ability] = label
		box.add_child(label)
		_refresh_ability(ability)


func _build_alerts(root: Control) -> void:
	_ignition_label = _make_label("", 34, IGNITION_COLOR)
	_ignition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ignition_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_ignition_label.offset_left = -500.0
	_ignition_label.offset_right = 500.0
	_ignition_label.offset_top = 24.0
	_ignition_label.offset_bottom = 70.0
	_ignition_label.visible = false
	root.add_child(_ignition_label)

	_dead_zone_badge = _make_panel(Color(0.25, 0.12, 0.5, 0.85))
	_dead_zone_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_dead_zone_badge.offset_left = -170.0
	_dead_zone_badge.offset_right = 170.0
	_dead_zone_badge.offset_top = 80.0
	_dead_zone_badge.offset_bottom = 130.0
	var badge_label := _make_label("DEAD ZONE - SIGNAL MASKED  (decay x3)", 18, Color(0.9, 0.85, 1.0))
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead_zone_badge.add_child(badge_label)
	_dead_zone_badge.visible = false
	root.add_child(_dead_zone_badge)


func _build_status_panel(root: Control) -> void:
	var panel := _make_panel(PANEL_COLOR)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -440.0
	panel.offset_right = -20.0
	panel.offset_top = 20.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_census_label = _make_label("HUNTERS\n...", 17)
	box.add_child(_census_label)
	_stats_label = _make_label("", 15, Color(0.7, 0.75, 0.85))
	box.add_child(_stats_label)


func _build_center(root: Control) -> void:
	_crosshair = _make_label("+", 30)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -20.0
	_crosshair.offset_right = 20.0
	_crosshair.offset_top = -22.0
	_crosshair.offset_bottom = 18.0
	root.add_child(_crosshair)

	_fracture_prompt = _make_label("", 20, Color(1.0, 0.45, 0.95))
	_fracture_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fracture_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_fracture_prompt.offset_left = -300.0
	_fracture_prompt.offset_right = 300.0
	_fracture_prompt.offset_top = 26.0
	_fracture_prompt.offset_bottom = 56.0
	_fracture_prompt.visible = false
	root.add_child(_fracture_prompt)

	_toast = _make_label("", 20)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -500.0
	_toast.offset_right = 500.0
	_toast.offset_top = -110.0
	_toast.offset_bottom = -76.0
	_toast.modulate.a = 0.0
	root.add_child(_toast)


func _build_help(root: Control) -> void:
	var help := _make_label(
		"WASD move | Mouse look | SPACE jump (air: Super Jump) | Q Super Jump | SHIFT Micro Dash\n" +
		"F toggle Full Form | E Fracture Codex onto aimed vehicle | R restart | ESC free mouse",
		14, Color(0.7, 0.75, 0.85))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 20.0
	help.offset_right = 900.0
	help.offset_top = -60.0
	help.offset_bottom = -14.0
	root.add_child(help)


func _build_caught_overlay(root: Control) -> void:
	_caught_overlay = ColorRect.new()
	_caught_overlay.color = Color(0.8, 0.0, 0.0, 0.0)
	_caught_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caught_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caught_overlay.visible = false
	root.add_child(_caught_overlay)
	_caught_label = _make_label("CAUGHT BY HUNTERS", 56, Color(1.0, 0.85, 0.85))
	_caught_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caught_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caught_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caught_overlay.add_child(_caught_label)
