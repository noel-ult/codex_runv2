class_name PauseMenu
extends CanvasLayer
## Field reference and operator viewer. The simulation stays paused while either is open.

signal restart_requested()
signal graphics_preset_changed(preset: int)

enum GraphicsPreset { DETAIL, PERFORMANCE }

const INK: Color = Color("0a151a")
const PANEL: Color = Color("0e2026")
const MINT: Color = Color("6affdb")
const PAPER: Color = Color("e7f5f2")
const MUTED: Color = Color("a3bcb9")
const AMBER: Color = Color("ffc47c")
const COMPACT_WIDTH: float = 880.0
const ROLES: PackedStringArray = ["Runner", "Hunter", "Civilian", "Technician"]
const DOSSIERS: PackedStringArray = [
	"Codex carrier. A hood and luminous suit seams identify the Runner outside a disguise.",
	"HunterNet patrol. The visor changes color when a Hunter investigates, pursues, or follows a decoy.",
	"City pedestrian. Hold Interact near an eligible pedestrian to clone their identity and outfit.",
	"Meridian lab staff. A cloned technician ID opens the staff gate and loading bay.",
]

var can_pause: Callable
var is_open: bool = false
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _root: Control
var _margin: MarginContainer
var _control_panel: PanelContainer
var _operator_panel: PanelContainer
var _sections: VBoxContainer
var _scroll: ScrollContainer
var _resume: Button
var _restart: Button
var _controls_tab: Button
var _operators_tab: Button
var _graphics_preset: OptionButton
var _preview: OperatorPreview
var _dossier: Label
var _show_operators: bool = false
var _restart_pending: bool = false
var _mono: SystemFont


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_viewport().size_changed.connect(_layout)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if not is_open and (get_tree().paused or (can_pause.is_valid() and not bool(can_pause.call()))):
		return
	get_viewport().set_input_as_handled()
	if is_open:
		_close()
	else:
		_open()


func _open() -> void:
	_previous_mouse_mode = Input.mouse_mode
	is_open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_controls()
	_set_page(false)
	_root.show()
	_resume.grab_focus()


func _close() -> void:
	is_open = false
	_restart_pending = false
	_restart.text = "Restart run"
	_root.hide()
	Input.mouse_mode = _previous_mouse_mode
	get_tree().paused = false


func _request_restart() -> void:
	if not _restart_pending:
		_restart_pending = true
		_restart.text = "Confirm restart"
		return
	_close()
	restart_requested.emit()


func select_graphics_preset(preset: int) -> void:
	_graphics_preset.select(preset)


func _build() -> void:
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	_root = Control.new()
	_root.name = "PauseInterface"
	_root.hide()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.036, 0.045, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_margin = MarginContainer.new()
	_root.add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var surface := PanelContainer.new()
	var frame: StyleBoxFlat = _box(INK, Color("355858"), 20)
	frame.border_width_top = 2
	frame.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	frame.shadow_size = 14
	frame.shadow_offset = Vector2(0.0, 12.0)
	surface.add_theme_stylebox_override(&"panel", frame)
	_margin.add_child(surface)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	surface.add_child(column)
	var identity: Label = _label("CODEX RUN", 13, MINT, true)
	column.add_child(identity)
	column.add_child(_label("Run paused", 34, PAPER))

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override(&"separation", 8)
	column.add_child(nav)
	var tab_group := ButtonGroup.new()
	_controls_tab = _button("Controls")
	_controls_tab.toggle_mode = true
	_controls_tab.button_group = tab_group
	_controls_tab.pressed.connect(_set_page.bind(false))
	nav.add_child(_controls_tab)
	_operators_tab = _button("Operators")
	_operators_tab.toggle_mode = true
	_operators_tab.button_group = tab_group
	_operators_tab.pressed.connect(_set_page.bind(true))
	nav.add_child(_operators_tab)
	var nav_spacer := Control.new()
	nav_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nav_spacer)
	_graphics_preset = OptionButton.new()
	_graphics_preset.name = "GraphicsPreset"
	_graphics_preset.accessibility_name = "Graphics preset"
	_graphics_preset.add_item("Graphics · Detail", GraphicsPreset.DETAIL)
	_graphics_preset.add_item("Graphics · Performance", GraphicsPreset.PERFORMANCE)
	_style_button(_graphics_preset, false)
	_graphics_preset.item_selected.connect(graphics_preset_changed.emit)
	nav.add_child(_graphics_preset)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 15)
	column.add_child(body)
	_build_controls(body)
	_build_stage(body)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 9)
	column.add_child(footer)
	_restart = _button("Restart run")
	_restart.pressed.connect(_request_restart)
	footer.add_child(_restart)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_resume = _button("Resume  [Esc]", true)
	_resume.pressed.connect(_close)
	footer.add_child(_resume)
	_layout()


func _build_controls(body: HBoxContainer) -> void:
	_control_panel = PanelContainer.new()
	_control_panel.name = "ControlsPanel"
	_control_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_control_panel.size_flags_stretch_ratio = 1.32
	_control_panel.add_theme_stylebox_override(&"panel", _box(PANEL, Color("294346"), 14))
	body.add_child(_control_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	_control_panel.add_child(column)
	column.add_child(_label("KEYBOARD & MOUSE", 13, MINT, true))
	_scroll = ScrollContainer.new()
	_scroll.name = "Bindings"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_ALL
	_scroll.accessibility_name = "Control bindings"
	_scroll.gui_input.connect(_on_bindings_input)
	var focus_border: StyleBoxFlat = _box(Color.TRANSPARENT, AMBER, 0)
	focus_border.draw_center = false
	_scroll.add_theme_stylebox_override(&"focus", focus_border)
	var scrollbar: VScrollBar = _scroll.get_v_scroll_bar()
	scrollbar.add_theme_stylebox_override(&"scroll", _box(Color("0a171d"), Color.TRANSPARENT, 3))
	scrollbar.add_theme_stylebox_override(&"grabber", _box(Color("446d70"), Color.TRANSPARENT, 3))
	scrollbar.add_theme_stylebox_override(&"grabber_highlight", _box(Color("72a09e"), Color.TRANSPARENT, 3))
	scrollbar.add_theme_stylebox_override(&"grabber_pressed", _box(MINT, Color.TRANSPARENT, 3))
	column.add_child(_scroll)
	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override(&"separation", 4)
	_scroll.add_child(_sections)


func _build_stage(body: HBoxContainer) -> void:
	_operator_panel = PanelContainer.new()
	_operator_panel.name = "OperatorsPanel"
	_operator_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_operator_panel.add_theme_stylebox_override(&"panel", _box(Color("0c1c23"), Color("365a5d"), 12))
	body.add_child(_operator_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	_operator_panel.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title: Label = _label("OPERATOR VIEW", 13, MINT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var roles := OptionButton.new()
	roles.name = "OperatorRole"
	roles.accessibility_name = "Operator role"
	_style_button(roles, false)
	var popup: PopupMenu = roles.get_popup()
	popup.add_theme_stylebox_override(&"panel", _box(INK, Color("416368"), 6))
	popup.add_theme_stylebox_override(&"hover", _box(Color("19383e"), Color.TRANSPARENT, 4))
	popup.add_theme_color_override(&"font_color", PAPER)
	popup.add_theme_color_override(&"font_hover_color", MINT)
	for role: String in ROLES:
		roles.add_item(role)
	roles.select(0)
	roles.item_selected.connect(_select_role)
	head.add_child(roles)
	_preview = OperatorPreview.new()
	_preview.name = "OperatorPreview"
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(0.0, 100.0)
	column.add_child(_preview)
	_dossier = _label(DOSSIERS[0], 14, PAPER)
	_dossier.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_dossier)
	column.add_child(_label("Drag to rotate · ← / → when focused", 12, MUTED))


func _select_role(index: int) -> void:
	_preview.show_operator(index as HumanoidRig.Style)
	_dossier.text = DOSSIERS[index]


func _set_page(operators: bool) -> void:
	_show_operators = operators
	_controls_tab.set_pressed_no_signal(not operators)
	_operators_tab.set_pressed_no_signal(operators)
	_layout()


func _layout() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var side: int = maxi(12, roundi((view.x - 1180.0) * 0.5))
	var top: int = maxi(12, roundi((view.y - 730.0) * 0.5))
	_margin.add_theme_constant_override(&"margin_left", side)
	_margin.add_theme_constant_override(&"margin_right", side)
	_margin.add_theme_constant_override(&"margin_top", top)
	_margin.add_theme_constant_override(&"margin_bottom", top)
	_control_panel.visible = not _show_operators
	_operator_panel.visible = view.x >= COMPACT_WIDTH or _show_operators
	_dossier.visible = _show_operators or view.y >= 610.0


func _refresh_controls() -> void:
	for child: Node in _sections.get_children():
		_sections.remove_child(child)
		child.queue_free()
	_add_section("MOVEMENT & STEALTH")
	_add_row("Move", _keys([&"move_forward", &"move_left", &"move_back", &"move_right"]))
	_add_row("Look / aim", "Mouse")
	_add_row("Jump / leap in the air", _keys([&"jump"]) + " / again")
	_add_action("Leap from the ground", &"super_jump")
	_add_action("Dash", &"micro_dash")
	_add_action("Toggle crouch", &"crouch")
	_add_action("Toggle prone", &"prone")
	_add_section("CODEX & EQUIPMENT")
	_add_action("Toggle Full Form", &"toggle_full_form")
	_add_row("Interact", _keys([&"interact"]) + " (hold)")
	_add_action("Use selected gadget", &"use_gadget")
	_add_row("Jammer Dart / EMP / Decoy", _keys([&"gadget_1", &"gadget_2", &"gadget_3"]))
	_add_row("Cycle gadgets", _keys([&"gadget_prev", &"gadget_next"]))
	_add_section("CITY VEHICLES")
	_add_row("Enter parked vehicle", _keys([&"interact"]) + " (hold at driver door)")
	_add_row("Drive / reverse", _keys([&"move_forward", &"move_back"]))
	_add_row("Steer", _keys([&"move_left", &"move_right"]))
	_add_row("Brake / exit", _keys([&"jump"]) + " / " + _keys([&"interact"]) + " (stopped)")
	_add_section("MISSION & MENUS")
	_add_action("Open objective log", &"toggle_objectives")
	_add_action("Pause / resume", &"ui_cancel")
	_add_action("Restart from gameplay", &"restart_slice")
	_add_section("HUNTERNET TERMINAL")
	var horizontal: String = "%s %s or ← →" % [_physical_key_name(KEY_A), _physical_key_name(KEY_D)]
	var vertical: String = "%s %s or ↑ ↓" % [_physical_key_name(KEY_W), _physical_key_name(KEY_S)]
	_add_row("Signal Lock · frequency / phase", horizontal + " / " + vertical)
	_add_row("Firewall Override · match prompt", "1 / 2 / 3")
	_add_row("Cipher · slot / glyph / submit", horizontal + " / " + vertical + " / Enter or Space")
	_add_row("Disconnect", "Esc")
	_add_section("HIDEOUT WORKBENCH")
	_add_row("Select item", vertical)
	_add_row("Confirm", "%s / Enter / Space" % _physical_key_name(KEY_E))
	_add_row("Leave station", "Esc / Tab")
	_add_section("MORNING WORK & SUPPLIES")
	_add_row("Courier depot / drop", _keys([&"interact"]) + " (hold on foot, dawn to 18:00)")
	_add_row("Supply counter", _keys([&"interact"]) + " (hold on foot)")
	_add_row("Select / buy / leave shop", vertical + " / E or Enter / Esc")
	_scroll.set_deferred(&"scroll_vertical", 0)


func _add_section(title: String) -> void:
	var heading: Label = _label(title, 12, MUTED, true)
	heading.custom_minimum_size.y = 25
	heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_sections.add_child(heading)


func _on_bindings_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_down", true):
		_scroll.scroll_vertical += 36
	elif event.is_action_pressed(&"ui_up", true):
		_scroll.scroll_vertical -= 36
	elif event.is_action_pressed(&"ui_page_down", true):
		_scroll.scroll_vertical += roundi(_scroll.size.y * 0.85)
	elif event.is_action_pressed(&"ui_page_up", true):
		_scroll.scroll_vertical -= roundi(_scroll.size.y * 0.85)
	else:
		return
	_scroll.accept_event()


func _add_action(description: String, action: StringName) -> void:
	if InputMap.has_action(action):
		_add_row(description, _keys([action]))


func _add_row(description: String, binding: String) -> void:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override(&"panel", _box(Color("12292f"), Color("243c40"), 6))
	_sections.add_child(row)
	var cells := HBoxContainer.new()
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.add_theme_constant_override(&"separation", 8)
	row.add_child(cells)
	var action: Label = _label(description, 14, PAPER)
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action.size_flags_stretch_ratio = 1.3
	action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cells.add_child(action)
	var key: Label = _label(binding, 12, MINT, true)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cells.add_child(key)


func _keys(actions: Array[StringName]) -> String:
	var primary: PackedStringArray = []
	var alternate: PackedStringArray = []
	for action: StringName in actions:
		if not InputMap.has_action(action):
			continue
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		for index: int in events.size():
			var key: String = _binding_text(events[index])
			if key.is_empty():
				continue
			if index == 0:
				primary.append(key)
			elif not primary.has(key) and not alternate.has(key):
				alternate.append(key)
	return " ".join(primary) + (" / " + " ".join(alternate) if not alternate.is_empty() else "")


func _binding_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		return _key_name(key_event.keycode) if key_event.keycode != KEY_NONE else _physical_key_name(key_event.physical_keycode)
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT: return "Left click"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel ↑"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel ↓"
		return mouse_event.as_text()
	return ""


func _physical_key_name(key: Key) -> String:
	if key != KEY_NONE and DisplayServer.get_name() != "headless":
		var localized: Key = DisplayServer.keyboard_get_keycode_from_physical(key)
		if localized != KEY_NONE:
			return _key_name(localized)
	return _key_name(key)


func _key_name(key: Key) -> String:
	match key:
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
		KEY_ESCAPE: return "Esc"
		KEY_CTRL: return "Ctrl"
	return OS.get_keycode_string(key)


func _label(value: String, size: int, color: Color, mono: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	if mono:
		label.add_theme_font_override(&"font", _mono)
	return label


func _button(value: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	_style_button(button, primary)
	return button


func _style_button(button: Button, primary: bool) -> void:
	button.custom_minimum_size.y = 40.0
	button.add_theme_font_size_override(&"font_size", 14)
	button.add_theme_color_override(&"font_color", INK if primary else PAPER)
	button.add_theme_color_override(&"font_hover_color", INK if primary else MINT)
	button.add_theme_color_override(&"font_focus_color", INK if primary else PAPER)
	button.add_theme_color_override(&"font_pressed_color", INK)
	button.add_theme_stylebox_override(&"normal", _box(MINT if primary else PANEL, Color("416368"), 7, 13))
	button.add_theme_stylebox_override(&"hover", _box(Color("bcffec") if primary else Color("19383e"), MINT, 7, 13))
	button.add_theme_stylebox_override(&"pressed", _box(Color("8ef5d9"), MINT, 7, 13))
	var focus: StyleBoxFlat = _box(Color.TRANSPARENT, AMBER, 7)
	focus.draw_center = false
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override(&"focus", focus)


func _box(fill: Color, border: Color, padding: int, horizontal: int = -1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = padding if horizontal < 0 else horizontal
	style.content_margin_right = style.content_margin_left
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style
