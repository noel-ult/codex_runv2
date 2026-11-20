class_name HUD
extends CanvasLayer
## Runner field display. Gameplay systems publish state through the bindings below.
## The navigation tape and scene beacons share the active player camera and mission markers.

const INK: Color = Color("#0a151a")
const WHITE: Color = Color("#eafff9")
const DIM: Color = Color("#b0c7cc")
const FAINT: Color = Color("#819ca3")
const CYAN: Color = Color("#6affdb")
const AMBER: Color = Color(1.0, 0.72, 0.28)
const RED: Color = Color(1.0, 0.3, 0.24)
const GREEN: Color = Color(0.45, 0.95, 0.6)
const VIOLET: Color = Color(0.72, 0.58, 1.0)

class InstrumentCard extends MarginContainer:
	var accent: Color = CYAN
	var right_cut: bool = false
	var selected: bool = false

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var cut: float = minf(h * 0.25, 15.0)
		if w < cut * 2.0 or h <= 0.0:
			return
		var outline: PackedVector2Array = PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(w - cut, 0.0), Vector2(w, cut),
			Vector2(w, h), Vector2(cut, h), Vector2(0.0, h - cut)
		])
		if right_cut:
			for i: int in outline.size():
				outline[i].x = w - outline[i].x
		var back: PackedVector2Array = outline.duplicate()
		for i: int in back.size():
			back[i] += Vector2(1.0, 4.0)
		draw_colored_polygon(back, Color(0.0, 0.025, 0.035, 0.53))
		var base: Color = INK.lerp(accent, 0.12) if selected else INK
		draw_polygon(outline, PackedColorArray([
			Color(base.lightened(0.04), 0.94), Color(base, 0.92), Color(base, 0.89),
			Color(base.darkened(0.25), 0.96), Color(base.darkened(0.18), 0.94), Color(base, 0.9)
		]))
		outline.append(outline[0])
		draw_polyline(outline, Color(accent, 0.9 if selected else 0.34), 1.0, true)
		var begin: float = w - 36.0 if right_cut else 0.0
		draw_line(Vector2(begin, 0.5), Vector2(begin + 36.0, 0.5), accent, 1.3, true)


var _font: SystemFont
var _mono: SystemFont
var _layout_scale: float = 1.0
var _root: Control
var _compass: Control
var _spatial: Control
var _threat_card: InstrumentCard
var _status_pips: HBoxContainer
var _gadget_cards: Array[InstrumentCard] = []
var _gadget_glyphs: Array[Control] = []
var _gadget_selected: int = 0
var _prompt_card: InstrumentCard
var _aim_target: bool = false
var _aim_lock_display: Label
var _threat_label: Label
var _threat_sub: Label
var _clock_label: Label
var _credits_label: Label
var _objective_label: Label
var _job_label: Label
var _contract_label: Label
var _objective_log: VBoxContainer
var _objective_lines: Array[Label] = []
var _resonance_bar: ProgressBar
var _resonance_fill: StyleBoxFlat
var _resonance_value: Label
var _release_label: Label
var _release_bar: ProgressBar
var _release_fill: StyleBoxFlat
var _form_label: Label
var _chips: HFlowContainer
var _chip_labels: Dictionary = {}
var _ability_labels: Dictionary = {}
var _gadget_name: Label
var _gadget_slots: Array[Label] = []
var _gadget_meta: Label
var _gadget_panel: InstrumentCard
var _vehicle_panel: InstrumentCard
var _vehicle_name: Label
var _vehicle_speed: Label
var _prompt_label: Label
var _prompt_bar: ProgressBar
var _subtitle: Label
var _toast: Label
var _meter_card: InstrumentCard
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
var _time: float = 0.0
var _vignette_strength: float = 0.0
var _release_left: float = 30.0
var _release_interval: float = 30.0
var _status_left: float = 0.0


func _ready() -> void:
	layer = 10
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "Liberation Sans", "sans-serif"])
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["IBM Plex Mono", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_vignette()
	_build_spatial_layer()
	_build_compass()
	_build_threat()
	_build_objective()
	_build_codex_cluster()
	_build_gadgets()
	_build_center()
	_build_overlays()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var pixels: Vector2 = get_viewport().get_visible_rect().size
	_layout_scale = minf(pixels.x / 1100.0, pixels.y / 720.0)
	_root.scale = Vector2.ONE * _layout_scale
	_root.size = pixels / maxf(_layout_scale, 0.01)
	var caption_half: float = clampf((_root.size.x - 680.0) * 0.5, 210.0, 352.0)
	_subtitle.offset_left = -caption_half
	_subtitle.offset_right = caption_half
	_toast.offset_left = -caption_half
	_toast.offset_right = caption_half


func _process(delta: float) -> void:
	_time += delta
	if _root.visible and visible:
		_compass.queue_redraw()
		_spatial.queue_redraw()
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
		_toast.visible = _toast_time > 0.0
	if _subtitle_time > 0.0:
		_subtitle_time -= delta
		_subtitle.modulate.a = clampf(_subtitle_time, 0.0, 1.0)
		_subtitle.visible = _subtitle_time > 0.0
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
	_status_left -= delta
	if _status_left <= 0.0:
		_status_left = 0.1
		_update_chips()
	if _ignited and not _suppressed:
		var chip: Label = _chip_labels.get(&"ignited")
		if chip != null:
			chip.modulate.a = 0.6 + 0.4 * absf(sin(_time * 6.0))
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
	player.stance_changed.connect(_on_stance_changed)
	_on_stance_changed(player.stance)
	player.feedback.connect(show_toast)
	player.vehicle_changed.connect(_on_vehicle_changed)
	player.disguise_changed.connect(func(active: bool, role: String, left: float) -> void:
		_disguise_role = role if active else ""
		_disguise_left = left if active else 0.0)
	var gadgets: GadgetBelt = player.get_gadgets()
	gadgets.inventory_changed.connect(_on_inventory_changed)
	gadgets.aim_target_changed.connect(_on_aim_target_changed)
	gadgets.publish()
	_on_vehicle_changed(player.is_driving())


func bind_economy(economy: RunnerEconomy) -> void:
	economy.credits_changed.connect(_on_credits_changed)
	_on_credits_changed(economy.credits)


func set_job_status(status: String) -> void:
	_job_label.text = status
	_job_label.visible = not status.is_empty()


func set_contract_status(status: String) -> void:
	_contract_label.text = status
	_contract_label.visible = not status.is_empty()


func set_vehicle_telemetry(speed_kmh: float, vehicle_name: String) -> void:
	_vehicle_name.text = vehicle_name.to_upper()
	_vehicle_speed.text = "%03d KM/H" % roundi(absf(speed_kmh))


func bind_director(director: HunterAIDirector) -> void:
	director.hunter_census_changed.connect(_on_census_changed)


func bind_mission(mission: MissionDirector) -> void:
	mission.objectives_changed.connect(_on_objectives_changed)
	mission.marker_changed.connect(_on_marker_changed)
	mission.transmission_progress.connect(_on_transmission_progress)
	mission.radio_message.connect(show_radio)
	mission.mission_completed.connect(_on_mission_completed)
	mission.lockdown_started.connect(func() -> void: _lockdown = true)
	mission.mission_reset.connect(func() -> void:
		_lockdown = false
		_win_overlay.visible = false)


func bind_environment(time: TimeOfDay, weather: WeatherSystem) -> void:
	var update_clock: Callable = func(hour: float) -> void:
		var phase_text: String = {TimeOfDay.PHASE_NIGHT: "NIGHT", TimeOfDay.PHASE_DAWN: "DAWN", TimeOfDay.PHASE_DAY: "DAYLIGHT", TimeOfDay.PHASE_DUSK: "DUSK"}.get(time.phase, "")
		_clock_label.text = "%s  ·  %s  ·  %s" % [TimeOfDay.format_clock(hour), phase_text, weather.get_weather_name()]
		_clock_label.add_theme_color_override(&"font_color", AMBER if time.is_daytime() else DIM)
	time.clock_tick.connect(update_clock)
	update_clock.call(time.hour)


## Shows / updates a compass marker (used by systems other than the mission, e.g. the hideout).
func set_marker(marker_id: StringName, world_position: Vector3, label_text: String, color: Color, shown: bool) -> void:
	_on_marker_changed(marker_id, world_position, label_text, color, shown)


func bind_terminal(terminal: HackTerminal) -> void:
	terminal.opened_changed.connect(func(open: bool) -> void: _root.visible = not open)


func show_toast(message: String) -> void:
	_toast.text = message
	_toast.visible = true
	_toast_time = 3.2
	_toast.modulate.a = 1.0


func show_radio(message: String) -> void:
	_subtitle.text = message
	_subtitle.visible = true
	_subtitle_time = 7.0
	_subtitle.modulate.a = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if visible and _root.visible and event.is_action_pressed(&"toggle_objectives") and not event.is_echo():
		_objective_log.visible = not _objective_log.visible
		get_viewport().set_input_as_handled()


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
	_prompt_card.visible = text != ""
	_prompt_label.text = ("Hold [E]   " + text.trim_prefix("[Hold E] ")) if text.begins_with("[Hold E]") else text
	_prompt_bar.visible = progress >= 0.0
	_prompt_bar.value = maxf(progress, 0.0)


func _on_captured(_total: int) -> void:
	_caught_time = 2.5
	_caught_overlay.visible = true


func _on_credits_changed(balance: int) -> void:
	_credits_label.text = "%d CREDITS" % balance


func _on_vehicle_changed(driving: bool) -> void:
	if is_instance_valid(_player):
		_camera = (_player as PlayerController).get_view_camera()
	_gadget_panel.visible = not driving
	_vehicle_panel.visible = driving
	_aim_lock_display.visible = _aim_target and not driving


func _on_census_changed(patrolling: int, investigating: int, pursuing: int, decoyed: int) -> void:
	_threat = 2 if pursuing > 0 else (1 if investigating > 0 else 0)
	var texts: PackedStringArray = ["UNDETECTED", "SEARCHING", "HUNTED"]
	var colors: Array[Color] = [GREEN, AMBER, RED]
	_threat_label.text = texts[_threat]
	_threat_label.add_theme_color_override(&"font_color", colors[_threat])
	_threat_card.accent = colors[_threat]
	_threat_card.queue_redraw()
	for i: int in _status_pips.get_child_count():
		var pip: ColorRect = _status_pips.get_child(i) as ColorRect
		pip.color = Color(colors[_threat], 0.95 if i <= _threat else 0.17)
	var sub: PackedStringArray = []
	if pursuing > 0:
		sub.append("%d in pursuit" % pursuing)
	if investigating > 0:
		sub.append("%d searching" % investigating)
	if decoyed > 0:
		sub.append("%d on decoy" % decoyed)
	_threat_sub.text = "  ·  ".join(sub) if not sub.is_empty() else "%d on patrol" % patrolling


func _on_inventory_changed(selected: StringName, darts: int, emps: int, cells: int, decoys_active: int) -> void:
	_gadget_name.text = GadgetBelt.display_name(selected)
	var counts: Array[int] = [darts, emps, floori(cells / 2.0)]
	var ids: Array[StringName] = [GadgetBelt.GADGET_JAMMER, GadgetBelt.GADGET_EMP, GadgetBelt.GADGET_DECOY]
	for i: int in 3:
		var active: bool = ids[i] == selected
		if active:
			_gadget_selected = i
		_gadget_slots[i].text = str(counts[i])
		_gadget_slots[i].add_theme_color_override(&"font_color", WHITE if active else DIM)
		_gadget_cards[i].selected = active
		_gadget_cards[i].queue_redraw()
		_gadget_glyphs[i].queue_redraw()
	_gadget_meta.text = "%d cells   ·   %d/2 decoys active" % [cells, decoys_active]


func _on_stance_changed(stance: int) -> void:
	match stance:
		PlayerController.Stance.CROUCHED:
			_set_chip(&"stance", true, "CROUCHED", CYAN)
		PlayerController.Stance.PRONE:
			_set_chip(&"stance", true, "PRONE", CYAN)
		_:
			_set_chip(&"stance", false, "", DIM)


func _on_aim_target_changed(has_target: bool, label_text: String) -> void:
	_aim_target = has_target
	_aim_lock_display.text = "JAMMER LOCK   /   " + label_text if not label_text.is_empty() else "JAMMER LOCK"
	_aim_lock_display.visible = has_target and (not is_instance_valid(_player) or not (_player as PlayerController).is_driving())


func _on_objectives_changed(lines: PackedStringArray, active_index: int) -> void:
	var current: String = lines[mini(active_index, lines.size() - 1)].substr(4) if not lines.is_empty() else ""
	_objective_label.text = current if active_index < lines.size() else "Codex safe"
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
	_meter_card.visible = progress >= 0.0
	_meter_label.text = "UPLINK  %d%%" % int(progress * 100.0) + ("" if in_range else "   ·   OUT OF RANGE")
	_meter_bar.value = maxf(progress, 0.0)
	_meter_fill.bg_color = GREEN if in_range else RED


func show_ending_restart_prompt() -> void:
	_win_stats.text = "R  ·  run it again"


func _on_mission_completed(elapsed_seconds: float, captures: int) -> void:
	_win_overlay.visible = true
	_win_stats.text = "%s   ·   %d captures\n\nCtrl+S  ·  save completion\nR  ·  run it again" % [_format_time(elapsed_seconds), captures]
	_win_overlay.modulate.a = 0.0
	create_tween().tween_property(_win_overlay, "modulate:a", 1.0, 1.4)


# --- Per-frame visuals --------------------------------------------------------------------------

func _update_release_visual() -> void:
	var ratio: float = clampf(_release_left / maxf(_release_interval, 0.01), 0.0, 1.0)
	_release_bar.value = 1.0 - ratio
	var warning: bool = _release_left < 5.0
	var masked: bool = _dead_zone
	var countdown: String = ("%.1f s" % _release_left if warning else "%d s" % ceili(_release_left)) + ("  MASKED" if masked else "")
	if _release_label.text != countdown:
		_release_label.text = countdown
	var color: Color = VIOLET if masked else (AMBER.lerp(RED, 0.5 + 0.5 * sin(_time * 12.0)) if warning else DIM)
	if _release_label.get_theme_color(&"font_color") != color:
		_release_label.add_theme_color_override(&"font_color", color)
	var fill_color: Color = VIOLET if masked else (RED if warning else AMBER.darkened(0.2))
	if _release_fill.bg_color != fill_color:
		_release_fill.bg_color = fill_color


func _update_chips() -> void:
	_set_chip(&"ignited", _ignited, "BROADCAST MASKED" if _suppressed else "IGNITED · BROADCASTING", VIOLET if _suppressed else RED)
	_set_chip(&"deadzone", _dead_zone, "DEAD ZONE", VIOLET)
	_set_chip(&"disguise", _disguise_role != "", "%s  %d:%02d" % [_disguise_role.to_upper(), floori(_disguise_left / 60.0), int(_disguise_left) % 60], CYAN)
	_set_chip(&"lockdown", _lockdown, "LOCKDOWN", RED)


func _set_chip(id: StringName, shown: bool, text: String, color: Color) -> void:
	var chip: Label = _chip_labels.get(id)
	if chip == null:
		chip = _label(11, color, true)
		_chips.add_child(chip)
		_chip_labels[id] = chip
	chip.visible = shown
	if chip.text != text:
		chip.text = text
	if chip.get_theme_color(&"font_color") != color:
		chip.add_theme_color_override(&"font_color", color)
	chip.modulate.a = 1.0


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
	var center: float = w * 0.5
	var face: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(w, 0.0), Vector2(w - 14.0, 42.0), Vector2(14.0, 42.0)])
	_compass.draw_polygon(face, PackedColorArray([Color(INK, 0.46), Color(INK, 0.46), Color(INK, 0.94), Color(INK, 0.94)]))
	_compass.draw_line(Vector2(14.0, 42.0), Vector2(w - 14.0, 42.0), Color(CYAN, 0.37), 1.0, true)
	_compass.draw_colored_polygon(PackedVector2Array([Vector2(center - 4.0, 40.0), Vector2(center + 4.0, 40.0), Vector2(center, 45.0)]), CYAN)
	if not is_instance_valid(_camera):
		return
	var forward: Vector3 = -_camera.global_basis.z
	var heading: float = rad_to_deg(atan2(forward.x, -forward.z))
	const SPAN: float = 120.0
	var density: float = (w - 34.0) / SPAN
	var heading_text: String = "%03d°" % (roundi(wrapf(heading, 0.0, 360.0)) % 360)
	_compass.draw_string(_mono, Vector2(center - 32.0, 13.0), heading_text, HORIZONTAL_ALIGNMENT_CENTER, 64.0, 12, CYAN)
	for degrees: int in range(0, 360, 5):
		var shift: float = wrapf(float(degrees) - heading, -180.0, 180.0)
		if absf(shift) > SPAN * 0.5:
			continue
		var x: float = center + shift * density
		var fade: float = 1.0 - 0.6 * pow(absf(shift) / (SPAN * 0.5), 2.0)
		if degrees % 45 == 0:
			var name_text: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][floori(float(degrees) / 45.0)]
			_compass.draw_string(_mono, Vector2(x - 20.0, 29.0), name_text, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 13, Color(WHITE, fade))
		else:
			var length: float = 6.0 if degrees % 15 == 0 else 3.0
			_compass.draw_line(Vector2(x, 38.0 - length), Vector2(x, 38.0), Color(DIM, fade * 0.75), 1.0)
	if not is_instance_valid(_player):
		return
	var ranges: Array[Rect2] = []
	for id: StringName in _markers:
		var marker: Dictionary = _markers[id]
		if not bool(marker.get("shown", false)):
			continue
		var position: Vector3 = marker.get("pos", Vector3.ZERO)
		var offset: Vector3 = position - _player.global_position
		var angle: float = wrapf(rad_to_deg(atan2(offset.x, -offset.z)) - heading, -180.0, 180.0)
		var x: float = center + clampf(angle, -SPAN * 0.5, SPAN * 0.5) * density
		var color: Color = marker.get("color", WHITE)
		var diamond_center: Vector2 = Vector2(x, 42.0)
		if absf(angle) >= SPAN * 0.5:
			var outward: float = signf(angle)
			_compass.draw_polyline(PackedVector2Array([diamond_center + Vector2(-4.0 * outward, -4.0), diamond_center, diamond_center + Vector2(-4.0 * outward, 4.0)]), color, 1.7, true)
		else:
			_compass.draw_colored_polygon(_diamond(diamond_center, 4.0), color)
		var caption: String = "%s  %d m" % [marker.get("label", ""), roundi(offset.length())]
		var width: float = _mono.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x + 12.0
		var chip: Rect2 = Rect2(clampf(x - width * 0.5, 0.0, w - width), 49.0, width, 17.0)
		for prior: Rect2 in ranges:
			if prior.grow(3.0).intersects(chip):
				chip.position.y = prior.end.y + 3.0
		ranges.append(chip)
		_compass.draw_rect(chip, Color(INK, 0.94))
		_compass.draw_string(_mono, chip.position + Vector2(6.0, 12.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, color)


func _draw_spatial() -> void:
	var center: Vector2 = _spatial.size * 0.5
	if is_instance_valid(_camera) and is_instance_valid(_player):
		var bounds: Rect2 = Rect2(Vector2(40.0, 106.0), _spatial.size - Vector2(80.0, 255.0))
		for id: StringName in _markers:
			var marker: Dictionary = _markers[id]
			if not bool(marker.get("shown", false)):
				continue
			var position: Vector3 = marker.get("pos", Vector3.ZERO)
			if _camera.is_position_behind(position):
				continue
			var point: Vector2 = _camera.unproject_position(position) / _layout_scale
			if not bounds.has_point(point) or point.distance_squared_to(center) < 42.0 * 42.0:
				continue
			var range_m: float = position.distance_to(_player.global_position)
			var radius: float = lerpf(10.0, 5.5, clampf(range_m / 130.0, 0.0, 1.0))
			var color: Color = marker.get("color", WHITE)
			var landing: Vector2 = point + Vector2(0.0, -31.0)
			_spatial.draw_line(point, landing, Color(color, 0.65), 1.0, true)
			_spatial.draw_colored_polygon(_diamond(point, radius), Color(INK, 0.85))
			_spatial.draw_polyline(_diamond(point, radius, true), Color(color, 0.88), 1.4, true)
			_spatial.draw_colored_polygon(_diamond(point, 2.5), color)
			_spatial.draw_circle(landing, 2.0, color, true, -1.0, true)
			var caption: String = "%s  /  %d m" % [marker.get("label", ""), roundi(range_m)]
			var width: float = _mono.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x + 14.0
			var top_left: Vector2 = Vector2(clampf(landing.x - width * 0.5, 12.0, _spatial.size.x - width - 12.0), landing.y - 21.0)
			var tag: Rect2 = Rect2(top_left, Vector2(width, 18.0))
			_spatial.draw_rect(tag, Color(INK, 0.9))
			_spatial.draw_string(_mono, top_left + Vector2(7.0, 13.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, color)
	var color: Color = CYAN if _aim_target else Color(WHITE, 0.82)
	var reticle_radius: float = 9.0 if _aim_target else 5.0
	var outline: Color = Color(INK, 0.94)
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var start: Vector2 = center + direction * reticle_radius
		var end: Vector2 = center + direction * (reticle_radius + 3.5)
		_spatial.draw_line(start, end, outline, 3.0, true)
		_spatial.draw_line(start, end, color, 1.2, true)
	_spatial.draw_circle(center, 2.3, outline, true, -1.0, true)
	_spatial.draw_circle(center, 1.2, color, true, -1.0, true)


func _diamond(center: Vector2, radius: float, closed: bool = false) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius), center + Vector2(-radius, 0.0),
	])
	if closed:
		points.append(points[0])
	return points


func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


# --- Construction ----------------------------------------------------------------------------

func _label(size_px: int, color: Color = WHITE, technical: bool = false) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_override(&"font", _mono if technical else _font)
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
	bg.bg_color = Color(0.58, 0.8, 0.84, 0.18)
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


func _build_spatial_layer() -> void:
	_spatial = Control.new()
	_spatial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_spatial)
	_spatial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_spatial.draw.connect(_draw_spatial)


func _build_compass() -> void:
	_compass = Control.new()
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_compass)
	_place(_compass, Vector2(0.5, 0.0), Rect2(-191.0, 12.0, 382.0, 78.0))
	_compass.draw.connect(_draw_compass)


func _place(control: Control, anchor: Vector2, box: Rect2) -> void:
	control.set_anchor(SIDE_LEFT, anchor.x)
	control.set_anchor(SIDE_RIGHT, anchor.x)
	control.set_anchor(SIDE_TOP, anchor.y)
	control.set_anchor(SIDE_BOTTOM, anchor.y)
	control.offset_left = box.position.x
	control.offset_right = box.end.x
	control.offset_top = box.position.y
	control.offset_bottom = box.end.y
	if box.size.y == 0.0:
		var fit: Callable = _fit_height.bind(control, box.position.y)
		control.minimum_size_changed.connect(fit)
		fit.call_deferred()


func _fit_height(control: Control, edge: float) -> void:
	var height: float = control.get_combined_minimum_size().y
	if control.grow_vertical == Control.GROW_DIRECTION_BEGIN:
		control.offset_top = edge - height
		control.offset_bottom = edge
	else:
		control.offset_bottom = edge + height
		control.offset_top = edge


func _card(parent: Control, accent: Color = CYAN, right_cut: bool = false, padding: Vector2i = Vector2i(14, 9)) -> InstrumentCard:
	var panel: InstrumentCard = InstrumentCard.new()
	panel.accent = accent
	panel.right_cut = right_cut
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_constant_override(&"margin_left", padding.x)
	panel.add_theme_constant_override(&"margin_right", padding.x)
	panel.add_theme_constant_override(&"margin_top", padding.y)
	panel.add_theme_constant_override(&"margin_bottom", padding.y)
	parent.add_child(panel)
	panel.resized.connect(panel.queue_redraw)
	return panel


func _column(parent: Control, separation: int) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", separation)
	parent.add_child(column)
	return column


func _rule(parent: Control) -> void:
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(CYAN, 0.18)
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


func _build_threat() -> void:
	_threat_card = _card(_root, GREEN, true)
	_place(_threat_card, Vector2(1.0, 0.0), Rect2(-250.0, 20.0, 230.0, 0.0))
	var box: VBoxContainer = _column(_threat_card, 4)
	var head: HBoxContainer = HBoxContainer.new()
	box.add_child(head)
	var cap: Label = _label(11, DIM, true)
	cap.text = "HUNTER ACTIVITY"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(cap)
	_status_pips = HBoxContainer.new()
	_status_pips.add_theme_constant_override(&"separation", 3)
	head.add_child(_status_pips)
	for i: int in 3:
		var pip: ColorRect = ColorRect.new()
		pip.color = Color(GREEN, 0.95 if i == 0 else 0.17)
		pip.custom_minimum_size = Vector2(8.0, 3.0)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_pips.add_child(pip)
	_threat_label = _label(21, GREEN)
	_threat_label.text = "UNDETECTED"
	box.add_child(_threat_label)
	_threat_sub = _label(12, DIM)
	_threat_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_threat_sub)
	_rule(box)
	_clock_label = _label(11, DIM, true)
	_clock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_clock_label)
	_credits_label = _label(14, AMBER, true)
	_credits_label.text = "0 CREDITS"
	box.add_child(_credits_label)
	var pause_hint: Label = _label(12, CYAN)
	pause_hint.text = "[ESC]  Pause / Controls"
	box.add_child(pause_hint)


func _build_objective() -> void:
	var panel: InstrumentCard = _card(_root)
	_place(panel, Vector2.ZERO, Rect2(20.0, 20.0, 302.0, 0.0))
	var box: VBoxContainer = _column(panel, 5)
	var header: HBoxContainer = HBoxContainer.new()
	box.add_child(header)
	var tag: Label = _label(11, CYAN, true)
	tag.text = "OBJECTIVE"
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tag)
	var hint: Label = _label(11, DIM, true)
	hint.text = "[TAB] LOG"
	header.add_child(hint)
	_objective_label = _label(19)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_objective_label)
	_rule(box)
	_job_label = _label(12, AMBER, true)
	_job_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job_label.visible = false
	box.add_child(_job_label)
	_contract_label = _label(12, VIOLET, true)
	_contract_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_contract_label.visible = false
	box.add_child(_contract_label)
	_objective_log = _column(box, 3)
	_objective_log.visible = false
	_rule(_objective_log)
	for i: int in 4:
		var line: Label = _label(13, FAINT)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_objective_log.add_child(line)
		_objective_lines.append(line)


func _build_codex_cluster() -> void:
	var panel: InstrumentCard = _card(_root)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_place(panel, Vector2(0.0, 1.0), Rect2(20.0, -22.0, 322.0, 0.0))
	var box: VBoxContainer = _column(panel, 5)
	var head: HBoxContainer = HBoxContainer.new()
	box.add_child(head)
	var group: Label = _label(11, CYAN, true)
	group.text = "CODEX"
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(group)
	_form_label = _label(11, WHITE, true)
	_form_label.text = "BASE FORM"
	head.add_child(_form_label)
	_chips = HFlowContainer.new()
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.add_theme_constant_override(&"h_separation", 12)
	_chips.add_theme_constant_override(&"v_separation", 2)
	box.add_child(_chips)
	var resonance_row: HBoxContainer = HBoxContainer.new()
	box.add_child(resonance_row)
	var resonance_tag: Label = _label(12, DIM)
	resonance_tag.text = "Resonance"
	resonance_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resonance_row.add_child(resonance_tag)
	_resonance_value = _label(16, WHITE, true)
	_resonance_value.text = "0"
	resonance_row.add_child(_resonance_value)
	var res_parts: Array = _bar(0.0, 5.0, CYAN)
	_resonance_bar = res_parts[0]
	_resonance_fill = res_parts[1]
	_resonance_bar.max_value = 100.0
	box.add_child(_resonance_bar)

	var release_row: HBoxContainer = HBoxContainer.new()
	box.add_child(release_row)
	var release_tag: Label = _label(12, DIM)
	release_tag.text = "Next release"
	release_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	release_row.add_child(release_tag)
	_release_label = _label(12, WHITE, true)
	release_row.add_child(_release_label)
	var rel_parts: Array = _bar(0.0, 3.0, AMBER)
	_release_bar = rel_parts[0]
	_release_fill = rel_parts[1]
	box.add_child(_release_bar)

	_rule(box)
	var abilities: HBoxContainer = HBoxContainer.new()
	abilities.add_theme_constant_override(&"separation", 13)
	box.add_child(abilities)
	var defs: Array[Array] = [[CodexSignalSystem.ABILITY_MICRO_DASH, "SHIFT"], [CodexSignalSystem.ABILITY_SUPER_JUMP, "Q"], [CodexSignalSystem.ABILITY_FULL_FORM, "F"]]
	for def: Array in defs:
		var ability: StringName = def[0]
		var label: Label = _label(10, CodexSignalSystem.get_ability_color(ability).lerp(WHITE, 0.32), true)
		label.text = "[%s] %s" % [str(def[1]), CodexSignalSystem.get_ability_display_name(ability)]
		abilities.add_child(label)
		_ability_labels[ability] = label


func _build_gadgets() -> void:
	var panel: InstrumentCard = _card(_root, CYAN, true)
	_gadget_panel = panel
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_place(panel, Vector2.ONE, Rect2(-338.0, -22.0, 318.0, 0.0))
	var box: VBoxContainer = _column(panel, 5)
	var heading: HBoxContainer = HBoxContainer.new()
	box.add_child(heading)
	var title: Label = _label(11, CYAN, true)
	title.text = "GADGET BELT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var hint: Label = _label(11, DIM, true)
	hint.text = "LMB USE  /  SCROLL SELECT"
	heading.add_child(hint)
	_gadget_name = _label(19)
	box.add_child(_gadget_name)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	box.add_child(row)
	var names: PackedStringArray = ["JAM", "EMP", "DCY"]
	for i: int in 3:
		var card: InstrumentCard = _card(row, CYAN, false, Vector2i(8, 6))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_gadget_cards.append(card)
		var body: VBoxContainer = _column(card, 3)
		var drawables: HBoxContainer = HBoxContainer.new()
		body.add_child(drawables)
		var icon: Control = Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(22.0, 19.0)
		icon.draw.connect(_draw_gadget_icon.bind(icon, i))
		drawables.add_child(icon)
		_gadget_glyphs.append(icon)
		var count: Label = _label(16, WHITE, true)
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		drawables.add_child(count)
		_gadget_slots.append(count)
		var key: Label = _label(10, DIM, true)
		key.text = "[%d] %s" % [i + 1, names[i]]
		body.add_child(key)
	_gadget_meta = _label(11, DIM, true)
	box.add_child(_gadget_meta)
	_vehicle_panel = _card(_root, AMBER, true)
	_vehicle_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_place(_vehicle_panel, Vector2.ONE, Rect2(-338.0, -22.0, 318.0, 0.0))
	_vehicle_panel.visible = false
	var drive_box: VBoxContainer = _column(_vehicle_panel, 5)
	var drive_tag: Label = _label(11, AMBER, true)
	drive_tag.text = "DRIVING"
	drive_box.add_child(drive_tag)
	_vehicle_name = _label(19)
	_vehicle_name.text = "CITY VEHICLE"
	drive_box.add_child(_vehicle_name)
	_vehicle_speed = _label(27, WHITE, true)
	_vehicle_speed.text = "000 KM/H"
	drive_box.add_child(_vehicle_speed)
	var drive_hint: Label = _label(11, DIM, true)
	drive_hint.text = "W/S MOVE · A/D STEER · SPACE BRAKE · E EXIT"
	drive_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drive_box.add_child(drive_hint)


func _draw_gadget_icon(icon: Control, index: int) -> void:
	var color: Color = CYAN if index == _gadget_selected else FAINT
	var center: Vector2 = Vector2(9.0, 10.0)
	match index:
		0:
			icon.draw_line(Vector2(3.0, 16.0), Vector2(16.0, 3.0), color, 1.7, true)
			icon.draw_polyline(PackedVector2Array([Vector2(10.0, 4.5), Vector2(17.0, 2.0), Vector2(14.5, 9.0)]), color, 1.4, true)
			icon.draw_line(Vector2(1.0, 12.0), Vector2(5.0, 16.0), color, 1.2, true)
		1:
			icon.draw_arc(center, 7.5, 0.0, TAU, 18, color, 1.2, true)
			icon.draw_polyline(PackedVector2Array([Vector2(10.0, 5.0), Vector2(7.0, 10.0), Vector2(11.0, 10.0), Vector2(8.0, 15.0)]), color, 1.35, true)
		2:
			icon.draw_polyline(_diamond(center, 8.0, true), color, 1.35, true)
			icon.draw_colored_polygon(_diamond(center, 3.0), color)


func _build_center() -> void:
	_aim_lock_display = _label(11, CYAN, true)
	_aim_lock_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_lock_display.visible = false
	_root.add_child(_aim_lock_display)
	_place(_aim_lock_display, Vector2(0.5, 0.5), Rect2(-180.0, 20.0, 360.0, 0.0))

	_prompt_card = _card(_root, CYAN, false, Vector2i(11, 7))
	_place(_prompt_card, Vector2(0.5, 0.5), Rect2(-192.0, 48.0, 384.0, 0.0))
	_prompt_card.visible = false
	var prompt: VBoxContainer = _column(_prompt_card, 5)
	_prompt_label = _label(14)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_child(_prompt_label)
	var prompt_parts: Array = _bar(0.0, 4.0, CYAN)
	_prompt_bar = prompt_parts[0]
	prompt.add_child(_prompt_bar)

	_meter_card = _card(_root)
	_place(_meter_card, Vector2(0.5, 0.0), Rect2(-180.0, 111.0, 360.0, 0.0))
	_meter_card.visible = false
	var uplink: VBoxContainer = _column(_meter_card, 5)
	_meter_label = _label(12, WHITE, true)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	uplink.add_child(_meter_label)
	var meter_parts: Array = _bar(0.0, 4.0, GREEN)
	_meter_bar = meter_parts[0]
	_meter_fill = meter_parts[1]
	uplink.add_child(_meter_bar)

	_subtitle = _label(16)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_subtitle.visible = false
	_root.add_child(_subtitle)
	_place(_subtitle, Vector2(0.5, 1.0), Rect2(-300.0, -63.0, 600.0, 0.0))
	_caption_backdrop(_subtitle, 0.93)
	_toast = _label(13, DIM)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.visible = false
	_root.add_child(_toast)
	_place(_toast, Vector2(0.5, 1.0), Rect2(-300.0, -31.0, 600.0, 0.0))
	_caption_backdrop(_toast, 0.88)


func _caption_backdrop(label: Label, opacity: float) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(INK, opacity)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	style.set_corner_radius_all(3)
	label.add_theme_stylebox_override(&"normal", style)


func _build_overlays() -> void:
	_caught_overlay = ColorRect.new()
	_caught_overlay.color = Color(0.4, 0.0, 0.0, 0.0)
	_caught_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caught_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caught_overlay.visible = false
	_root.add_child(_caught_overlay)
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
	_root.add_child(_win_overlay)
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
