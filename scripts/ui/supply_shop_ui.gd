class_name SupplyShopUI
extends CanvasLayer
## Supply counter interface. Main owns the player input lock and other modal coordination.

signal opened_changed(is_open: bool)

const INK: Color = Color("0a151a")
const PANEL: Color = Color("10262d")
const PAPER: Color = Color("e7f5f2")
const MUTED: Color = Color("a3bcb9")
const MINT: Color = Color("6affdb")
const AMBER: Color = Color("ffc47c")
const PANEL_SIZE: Vector2 = Vector2(860.0, 550.0)

var is_open: bool = false

var _player: PlayerController
var _belt: GadgetBelt
var _economy: RunnerEconomy
var _items: Array[Dictionary] = []
var _index: int = 0
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _root: Control
var _panel: PanelContainer
var _balance: Label
var _inventory: Label
var _title: Label
var _description: Label
var _availability: Label
var _message: Label
var _buy: Button
var _rows: Array[Button] = []
var _normal_row: StyleBoxFlat
var _selected_row: StyleBoxFlat
var _font: SystemFont


func _ready() -> void:
	layer = 22
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Inter", "Noto Sans", "DejaVu Sans", "sans-serif"])
	_build()
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()


func setup(player: PlayerController, economy: RunnerEconomy) -> void:
	_player = player
	_belt = player.get_gadgets()
	_economy = economy
	_items = economy.catalog()
	_build_rows()
	economy.credits_changed.connect(_on_balance_changed)
	_belt.inventory_changed.connect(_on_inventory_changed)


func open() -> void:
	if is_open or not is_instance_valid(_player) or not is_instance_valid(_economy):
		return
	_previous_mouse_mode = Input.mouse_mode
	is_open = true
	_index = 0
	_root.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_message.text = ""
	_refresh()
	_rows[0].grab_focus()
	opened_changed.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.hide()
	Input.mouse_mode = _previous_mouse_mode
	opened_changed.emit(false)


func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_W, KEY_UP:
			_select(wrapi(_index - 1, 0, _items.size()))
		KEY_S, KEY_DOWN:
			_select(wrapi(_index + 1, 0, _items.size()))
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_purchase()
		KEY_ESCAPE, KEY_TAB:
			close()


func _select(index: int) -> void:
	_index = index
	_message.text = ""
	_refresh()
	_rows[index].grab_focus()


func _purchase() -> void:
	if not is_open:
		return
	var id: StringName = _items[_index]["id"]
	var blocked: String = _economy.purchase_block_reason(id, _belt)
	if not blocked.is_empty():
		_message.text = blocked
		return
	if _economy.purchase(id, _belt):
		_message.text = "%s added to your inventory." % String(_items[_index]["title"])
	_refresh()


func _on_balance_changed(_credits: int) -> void:
	if is_open:
		_refresh.call_deferred()


func _on_inventory_changed(_selected: StringName, _darts: int, _emps: int, _cells: int, _decoys: int) -> void:
	if is_open:
		_refresh.call_deferred()


func _refresh() -> void:
	if _items.is_empty():
		return
	_balance.text = "%d CREDITS" % _economy.credits
	_inventory.text = "DARTS %d/%d     EMP %d/%d     CELLS %d/%d     SALVAGE %d" % [_belt.darts, _belt.max_darts, _belt.emps, _belt.max_emps, _belt.cells, _belt.max_cells, _belt.parts]
	for index: int in _items.size():
		var row: Button = _rows[index]
		row.add_theme_stylebox_override(&"normal", _selected_row if index == _index else _normal_row)
		row.add_theme_color_override(&"font_color", MINT if index == _index else PAPER)
	var item: Dictionary = _items[_index]
	_title.text = String(item["title"])
	_description.text = String(item["description"])
	var blocked: String = _economy.purchase_block_reason(item["id"], _belt)
	_availability.text = blocked if not blocked.is_empty() else "Whole pack · %d credits" % int(item["price"])
	_availability.add_theme_color_override(&"font_color", AMBER if not blocked.is_empty() else MINT)
	_buy.text = "Buy for %d credits" % int(item["price"])
	_buy.disabled = not blocked.is_empty()


func _build() -> void:
	_root = Control.new()
	_root.name = "SupplyShop"
	_root.hide()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.036, 0.045, 0.84)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.size = PANEL_SIZE
	_root.add_child(_panel)
	var frame: StyleBoxFlat = _box(INK, Color("3d635f"), 24)
	frame.border_width_top = 3
	frame.shadow_color = Color(0, 0, 0, 0.6)
	frame.shadow_size = 16
	frame.shadow_offset = Vector2(0, 12)
	_panel.add_theme_stylebox_override(&"panel", frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	_panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var heading: Label = _label("CITY SUPPLY COUNTER", 13, MINT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	_balance = _label("", 15, AMBER)
	top.add_child(_balance)
	column.add_child(_label("Ammunition & supplies", 30, PAPER))
	column.add_child(_label("Earn credits from daytime work, then stock up for the next heist.", 14, MUTED))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 16)
	column.add_child(body)
	var list := VBoxContainer.new()
	list.name = "ShopItems"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_stretch_ratio = 1.1
	list.add_theme_constant_override(&"separation", 8)
	body.add_child(list)
	var details := PanelContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_stylebox_override(&"panel", _box(PANEL, Color("294b4c"), 18))
	body.add_child(details)
	var detail_column := VBoxContainer.new()
	detail_column.add_theme_constant_override(&"separation", 14)
	details.add_child(detail_column)
	_title = _label("", 24, PAPER)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_column.add_child(_title)
	_description = _label("", 15, MUTED)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(_description)
	_availability = _label("", 13, MINT)
	_availability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_column.add_child(_availability)
	_buy = _button("")
	_buy.pressed.connect(_purchase)
	detail_column.add_child(_buy)
	_inventory = _label("", 12, MUTED)
	column.add_child(_inventory)
	_message = _label("", 14, AMBER)
	_message.custom_minimum_size.y = 22
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 20)
	column.add_child(footer)
	var help: Label = _label("[W/S or ↑/↓] Select   [E/Enter] Buy", 12, MUTED)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(help)
	var leave: Button = _button("Leave  [Esc]")
	leave.pressed.connect(close)
	footer.add_child(leave)
	_normal_row = _box(PANEL, Color("294b4c"), 16)
	_selected_row = _box(Color("193b3e"), MINT, 16)


func _build_rows() -> void:
	var list: VBoxContainer = _root.find_child("ShopItems", true, false) as VBoxContainer
	for row: Button in _rows:
		list.remove_child(row)
		row.queue_free()
	_rows.clear()
	for index: int in _items.size():
		var item: Dictionary = _items[index]
		var row: Button = _button("%s   ·   %d cr" % [String(item["title"]), int(item["price"])])
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size.y = 55
		row.pressed.connect(_select.bind(index))
		list.add_child(row)
		_rows.append(row)


func _fit_panel() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var available: Vector2 = (view - Vector2(24, 24)).max(Vector2.ONE)
	var factor: float = minf(1.0, minf(available.x / PANEL_SIZE.x, available.y / PANEL_SIZE.y))
	_panel.scale = Vector2.ONE * factor
	_panel.position = ((view - PANEL_SIZE * factor) * 0.5).floor()


func _label(text_value: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", size_px)
	label.add_theme_color_override(&"font_color", color)
	return label


func _button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 38
	button.add_theme_font_override(&"font", _font)
	button.add_theme_font_size_override(&"font_size", 14)
	button.add_theme_color_override(&"font_color", PAPER)
	button.add_theme_color_override(&"font_hover_color", MINT)
	button.add_theme_stylebox_override(&"normal", _box(PANEL, Color("3d635f"), 10))
	button.add_theme_stylebox_override(&"hover", _box(Color("193b3e"), MINT, 10))
	button.add_theme_stylebox_override(&"pressed", _box(Color("22504c"), MINT, 10))
	var focus: StyleBoxFlat = _box(Color.TRANSPARENT, AMBER, 2)
	focus.draw_center = false
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override(&"focus", focus)
	return button


func _box(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style
