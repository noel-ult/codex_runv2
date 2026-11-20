class_name PrepStationUI
extends CanvasLayer
## Hideout workbench menu. Spend salvage parts to fabricate gear and buy permanent upgrades,
## or rest until dusk. W/S (or arrows) select, E/Enter confirm, Esc/Tab leave.
## Talks to the Runner's systems through the references main hands it in `setup()`.

signal opened_changed(is_open: bool)
signal rest_requested()

const INK: Color = Color("#0a151a")
const WHITE: Color = Color("#eafff9")
const DIM: Color = Color("#b0c7cc")
const FAINT: Color = Color("#819ca3")
const ACCENT: Color = Color("#ffc578")
const MINT: Color = Color("#6affdb")
const PANEL_SIZE: Vector2 = Vector2(804.0, 552.0)

class WorkRow extends PanelContainer:
	var marker: Label
	var title: Label
	var price: Label


var is_open: bool = false

var _player: PlayerController
var _belt: GadgetBelt
var _codex: CodexSignalSystem
var _time: TimeOfDay
var _weather: WeatherSystem
var _items: Array[Dictionary] = []
var _purchased: Dictionary = {}
var _index: int = 0
var _font: SystemFont
var _mono: SystemFont
var _root: Control
var _panel: PanelContainer
var _list: VBoxContainer
var _rows: Array[WorkRow] = []
var _row_normal: StyleBoxFlat
var _row_selected: StyleBoxFlat
var _status: Label
var _salvage: Label
var _detail_title: Label
var _detail: Label
var _detail_price: Label
var _stock: Label
var _toast: Label
var _toast_tween: Tween
var _fade: ColorRect

func _ready() -> void:
	layer = 18
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "sans-serif"])
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["IBM Plex Mono", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	_build()
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	_root.visible = false


func setup(player: PlayerController, time: TimeOfDay, weather: WeatherSystem) -> void:
	_player = player
	_belt = player.get_gadgets()
	_codex = player.get_codex()
	_time = time
	_weather = weather
	_items = [
		{"id": &"darts", "title": "Fabricate jammer darts  x3", "cost": 2, "kind": "craft", "desc": "Silent darts that knock one device offline for 20 s."},
		{"id": &"emp", "title": "Fabricate EMP charge", "cost": 3, "kind": "craft", "desc": "Area shutdown of electronics + Hunter stun. Loud."},
		{"id": &"cell", "title": "Synthesize resonance cell", "cost": 2, "kind": "craft", "desc": "Two cells build one Decoy Codex."},
		{"id": &"rack", "title": "Dart rack  (+3 capacity)", "cost": 5, "kind": "upgrade", "desc": "Carry 3 more jammer darts."},
		{"id": &"capacitor", "title": "EMP capacitor  (+1 capacity)", "cost": 5, "kind": "upgrade", "desc": "Carry one more EMP charge."},
		{"id": &"amplifier", "title": "Decoy amplifier  (+20 charge)", "cost": 6, "kind": "upgrade", "desc": "Decoys store and accept more of your signature."},
		{"id": &"forger", "title": "ID forger  (+60 s disguise)", "cost": 4, "kind": "upgrade", "desc": "Cloned IDs hold up for longer."},
		{"id": &"dampener", "title": "Signature dampener  (-15% Release)", "cost": 6, "kind": "upgrade", "desc": "Codex Releases ping a smaller radius."},
		{"id": &"rest", "title": "Rest until dusk", "cost": 0, "kind": "action", "desc": "Sleep through the daylight. Wake at 19:00."},
		{"id": &"leave", "title": "Leave the station", "cost": 0, "kind": "action", "desc": ""},
	]
	_build_rows()
	_time.clock_tick.connect(func(_hour: float) -> void:
		if is_open:
			_refresh_stock())
	_time.phase_changed.connect(func(_phase: StringName) -> void:
		if is_open:
			_refresh())
	_weather.weather_changed.connect(func(_name_text: String) -> void:
		if is_open:
			_refresh_stock())


func open() -> void:
	is_open = true
	_index = 0
	_root.visible = true
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_refresh()
	opened_changed.emit(true)


func close() -> void:
	is_open = false
	_root.visible = false
	opened_changed.emit(false)


## Fade to black, run `midpoint`, fade back (used for resting).
func play_rest_fade(midpoint: Callable, finished: Callable = Callable()) -> void:
	_fade.visible = true
	_fade.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.7)
	tween.tween_callback(midpoint)
	tween.tween_interval(0.6)
	tween.tween_property(_fade, "color:a", 0.0, 0.9)
	tween.tween_callback(func() -> void:
		_fade.visible = false
		if finished.is_valid():
			finished.call())


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_W, KEY_UP:
			_index = wrapi(_index - 1, 0, _items.size())
		KEY_S, KEY_DOWN:
			_index = wrapi(_index + 1, 0, _items.size())
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate(_items[_index])
		KEY_ESCAPE, KEY_TAB:
			close()
			return
	_refresh()


func _available(item: Dictionary) -> bool:
	var id: StringName = item.get("id", &"")
	if id == &"rest":
		return _time != null and _time.is_daytime()
	if str(item.get("kind", "")) == "upgrade" and _purchased.has(id):
		return false
	return _belt.parts >= int(item.get("cost", 0))


func _activate(item: Dictionary) -> void:
	var id: StringName = item.get("id", &"")
	if id == &"leave":
		close()
		return
	if id == &"rest":
		if not _available(item):
			_flash("Resting is only safe during the day.")
			return
		close()
		rest_requested.emit()
		return
	if not _available(item):
		_flash("Already installed." if _purchased.has(id) else "Not enough salvage parts.")
		return
	var cost: int = int(item.get("cost", 0))
	match id:
		&"darts":
			if _belt.darts >= _belt.max_darts:
				_flash("Dart rack is full.")
				return
			_belt.darts = mini(_belt.darts + 3, _belt.max_darts)
		&"emp":
			if _belt.emps >= _belt.max_emps:
				_flash("No room for another charge.")
				return
			_belt.emps += 1
		&"cell":
			if _belt.cells >= _belt.max_cells:
				_flash("Cell pouch is full.")
				return
			_belt.cells += 1
		&"rack":
			_belt.max_darts += 3
		&"capacitor":
			_belt.max_emps += 1
		&"amplifier":
			_belt.decoy_bonus += 20.0
		&"forger":
			_player.disguise_duration += 60.0
		&"dampener":
			_codex.upgrade_radius_scale *= 0.85
	_belt.spend_parts(cost)
	if str(item.get("kind", "")) == "upgrade":
		_purchased[id] = true
	_flash("%s - done." % str(item.get("title", "")).split("  ")[0])


func _refresh() -> void:
	if _player == null:
		return
	_refresh_stock()
	for i: int in _items.size():
		var item: Dictionary = _items[i]
		var row: WorkRow = _rows[i]
		var id: StringName = item.get("id", &"")
		var cost: int = int(item.get("cost", 0))
		var installed: bool = _purchased.has(id)
		var available: bool = _available(item)
		var selected: bool = i == _index
		row.add_theme_stylebox_override(&"panel", _row_selected if selected else _row_normal)
		row.marker.text = "›" if selected else ""
		row.title.add_theme_color_override(&"font_color", WHITE if available or selected else DIM)
		row.price.text = "INSTALLED" if installed else ("%d parts" % cost if cost > 0 else "")
		row.price.add_theme_color_override(&"font_color", MINT if installed else (ACCENT if available else FAINT))

	var current: Dictionary = _items[_index]
	var current_id: StringName = current.get("id", &"")
	var current_cost: int = int(current.get("cost", 0))
	_detail_title.text = str(current.get("title", "")).replace("  ", " ")
	_detail.text = str(current.get("desc", ""))
	_detail_price.visible = current_id != &"leave"
	if _purchased.has(current_id):
		_detail_price.text = "UPGRADE INSTALLED"
		_detail_price.add_theme_color_override(&"font_color", MINT)
	elif current_id == &"rest":
		_detail_price.text = "AVAILABLE NOW" if _time.is_daytime() else "AVAILABLE DURING THE DAY"
		_detail_price.add_theme_color_override(&"font_color", MINT if _time.is_daytime() else DIM)
	elif _available(current):
		_detail_price.text = "%d SALVAGE PARTS" % current_cost
		_detail_price.add_theme_color_override(&"font_color", ACCENT)
	else:
		_detail_price.text = "NEED %d MORE SALVAGE" % (current_cost - _belt.parts)
		_detail_price.add_theme_color_override(&"font_color", DIM)


func _refresh_stock() -> void:
	_status.text = "%s  /  %s" % [TimeOfDay.format_clock(_time.hour), _weather.get_weather_name()]
	_salvage.text = "%d SALVAGE PARTS" % _belt.parts
	_stock.text = "DARTS %d/%d  ·  EMP %d/%d  ·  CELLS %d/%d" % [
		_belt.darts, _belt.max_darts, _belt.emps, _belt.max_emps, _belt.cells, _belt.max_cells]


func _flash(message: String) -> void:
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.text = message
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 2.0).set_delay(1.1)


func _label(text_value: String, size_px: int, color: Color = WHITE, mono: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_override(&"font", _mono if mono else _font)
	label.add_theme_font_size_override(&"font_size", size_px)
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _frame(fill: Color, line: Color, padding: Vector2i) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = padding.x
	style.content_margin_right = padding.x
	style.content_margin_top = padding.y
	style.content_margin_bottom = padding.y
	return style


func _fit_panel() -> void:
	var area: Vector2 = get_viewport().get_visible_rect().size
	var scale_factor: float = minf(minf((area.x - 30.0) / PANEL_SIZE.x, (area.y - 30.0) / PANEL_SIZE.y), 1.25)
	scale_factor = maxf(scale_factor, 0.1)
	_panel.size = PANEL_SIZE
	_panel.scale = Vector2.ONE * scale_factor
	_panel.position = (area - _panel.size * scale_factor) * 0.5


func _build_rows() -> void:
	var section: String = ""
	for item: Dictionary in _items:
		var kind: String = item.get("kind", "")
		var heading: String = {"craft": "FABRICATE", "upgrade": "UPGRADES", "action": "HIDEOUT"}.get(kind, "")
		if heading != section:
			section = heading
			var bar: Label = _label(section, 11, ACCENT, true)
			_list.add_child(bar)
		var row: WorkRow = WorkRow.new()
		row.custom_minimum_size.y = 27.0
		row.add_theme_stylebox_override(&"panel", _row_normal)
		_list.add_child(row)
		var layout: HBoxContainer = HBoxContainer.new()
		layout.add_theme_constant_override(&"separation", 7)
		row.add_child(layout)
		row.marker = _label("", 17, MINT)
		row.marker.custom_minimum_size.x = 10.0
		layout.add_child(row.marker)
		row.title = _label(str(item.get("title", "")).replace("  ", " "), 15)
		row.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		layout.add_child(row.title)
		row.price = _label("", 11, ACCENT, true)
		row.price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.price.custom_minimum_size.x = 82.0
		layout.add_child(row.price)
		_rows.append(row)


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color("#03090cbb")
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	var frame: StyleBoxFlat = _frame(INK, Color(MINT, 0.3), Vector2i(22, 18))
	frame.border_width_top = 2
	frame.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	frame.shadow_size = 12
	frame.shadow_offset = Vector2(0.0, 5.0)
	_panel.add_theme_stylebox_override(&"panel", frame)
	_root.add_child(_panel)

	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 11)
	_panel.add_child(body)
	var heading: HBoxContainer = HBoxContainer.new()
	body.add_child(heading)
	var heading_title: VBoxContainer = VBoxContainer.new()
	heading_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_title.add_theme_constant_override(&"separation", 0)
	heading.add_child(heading_title)
	heading_title.add_child(_label("STORAGE 07", 11, MINT, true))
	heading_title.add_child(_label("Prep station", 28))
	var heading_status: VBoxContainer = VBoxContainer.new()
	heading_status.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_child(heading_status)
	_status = _label("", 12, DIM, true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading_status.add_child(_status)
	_salvage = _label("", 14, ACCENT, true)
	_salvage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading_status.add_child(_salvage)

	var rule: ColorRect = ColorRect.new()
	rule.color = Color(MINT, 0.17)
	rule.custom_minimum_size.y = 1.0
	body.add_child(rule)
	var content: HBoxContainer = HBoxContainer.new()
	content.add_theme_constant_override(&"separation", 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_list)
	_row_normal = _frame(Color(MINT, 0.025), Color(MINT, 0.09), Vector2i(9, 0))
	_row_selected = _frame(Color("#183838"), Color(MINT, 0.55), Vector2i(9, 0))
	_row_selected.border_width_left = 3

	var detail_frame: PanelContainer = PanelContainer.new()
	detail_frame.custom_minimum_size.x = 266.0
	detail_frame.add_theme_stylebox_override(&"panel", _frame(Color("#0e2127"), Color(MINT, 0.2), Vector2i(14, 12)))
	content.add_child(detail_frame)
	var details: VBoxContainer = VBoxContainer.new()
	details.add_theme_constant_override(&"separation", 9)
	detail_frame.add_child(details)
	_detail_price = _label("", 11, ACCENT, true)
	details.add_child(_detail_price)
	_detail_title = _label("", 22)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_detail_title)
	_detail = _label("", 15, DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(_detail)
	_toast = _label("", 13, ACCENT)
	_toast.custom_minimum_size.y = 39.0
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.modulate.a = 0.0
	details.add_child(_toast)

	var footer: HBoxContainer = HBoxContainer.new()
	body.add_child(footer)
	_stock = _label("", 11, DIM, true)
	_stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_stock)
	footer.add_child(_label("[W/S or ↑/↓] Select    [E / Enter] Apply    [Esc] Leave", 12, DIM))
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
