class_name PrepStationUI
extends CanvasLayer
## Hideout workbench menu. Spend salvage parts to fabricate gear and buy permanent upgrades,
## or rest until dusk. W/S (or arrows) select, E/Enter confirm, Esc/Tab leave.
## Talks to the Runner's systems through the references main hands it in `setup()`.

signal opened_changed(is_open: bool)
signal rest_requested()

const WHITE: Color = Color(0.93, 0.95, 0.97)
const DIM: Color = Color(0.6, 0.64, 0.7)
const FAINT: Color = Color(0.38, 0.41, 0.46)
const ACCENT: Color = Color(1.0, 0.72, 0.3)
const GREEN: Color = Color(0.45, 0.95, 0.6)

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
var _root: Control
var _list: VBoxContainer
var _header: Label
var _status: Label
var _detail: Label
var _toast: Label
var _fade: ColorRect


func _ready() -> void:
	layer = 18
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "sans-serif"])
	_build()
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


func open() -> void:
	is_open = true
	_index = 0
	_root.visible = true
	_refresh()
	opened_changed.emit(true)


func close() -> void:
	is_open = false
	_root.visible = false
	opened_changed.emit(false)


## Fade to black, run `midpoint`, fade back (used for resting).
func play_rest_fade(midpoint: Callable) -> void:
	_fade.visible = true
	_fade.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.7)
	tween.tween_callback(midpoint)
	tween.tween_interval(0.6)
	tween.tween_property(_fade, "color:a", 0.0, 0.9)
	tween.tween_callback(func() -> void: _fade.visible = false)


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
	_header.text = "STORAGE 07  ·  PREP STATION"
	_status.text = "%s   ·   %s   ·   SALVAGE %d   ·   DARTS %d/%d   EMP %d/%d   CELLS %d/%d" % [
		TimeOfDay.format_clock(_time.hour), _weather.get_weather_name(), _belt.parts,
		_belt.darts, _belt.max_darts, _belt.emps, _belt.max_emps, _belt.cells, _belt.max_cells]
	for child: Node in _list.get_children():
		child.queue_free()
	var section: String = ""
	for i: int in _items.size():
		var item: Dictionary = _items[i]
		var kind: String = str(item.get("kind", ""))
		var title_text: String = {"craft": "FABRICATE", "upgrade": "UPGRADES", "action": "HIDEOUT"}.get(kind, "")
		if title_text != section:
			section = title_text
			var heading := _label(11, ACCENT)
			heading.text = section
			_list.add_child(heading)
		var row := _label(15, WHITE)
		var cost: int = int(item.get("cost", 0))
		var installed: bool = _purchased.has(item.get("id", &""))
		var price: String = "INSTALLED" if installed else ("%d parts" % cost if cost > 0 else "")
		row.text = "%s %-40s %s" % ["›" if i == _index else " ", str(item.get("title", "")), price]
		var color: Color = WHITE if _available(item) or item.get("id", &"") == &"leave" else FAINT
		if installed:
			color = GREEN
		if i == _index:
			color = ACCENT if _available(item) or item.get("id", &"") == &"leave" else DIM
		row.add_theme_color_override(&"font_color", color)
		_list.add_child(row)
	_detail.text = str(_items[_index].get("desc", ""))


func _flash(message: String) -> void:
	_toast.text = message
	_toast.modulate.a = 1.0
	create_tween().tween_property(_toast, "modulate:a", 0.0, 2.5).set_delay(0.8)


func _label(size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", size_px)
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -360.0
	panel.offset_right = 360.0
	panel.offset_top = -270.0
	panel.offset_bottom = 270.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.045, 0.055, 0.96)
	style.border_color = Color(1.0, 0.72, 0.3, 0.5)
	style.border_width_top = 2
	style.set_corner_radius_all(6)
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override(&"panel", style)
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	panel.add_child(box)
	_header = _label(18, WHITE)
	box.add_child(_header)
	_status = _label(12, DIM)
	box.add_child(_status)
	var rule := ColorRect.new()
	rule.color = Color(1.0, 1.0, 1.0, 0.08)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	box.add_child(rule)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 3)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_list)
	_detail = _label(13, DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail)
	_toast = _label(13, ACCENT)
	_toast.modulate.a = 0.0
	box.add_child(_toast)
	var hint := _label(11, FAINT)
	hint.text = "W/S  select   ·   E  confirm   ·   ESC  leave"
	box.add_child(hint)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.visible = false
	add_child(_fade)
