class_name HackTerminal
extends CanvasLayer
## Full-screen retro CRT terminal that runs a sequence of RetroMinigame stages.
## Owns the session TRACE meter: mistakes and failed stages raise it; at 100% the HunterNet
## traces the intrusion and the session is aborted (`session_aborted(..., traced = true)`).
## While open it consumes keyboard/mouse input so the Runner stands still.

signal session_completed(session_id: StringName)
signal session_aborted(session_id: StringName, traced: bool)
signal trace_changed(value: float)
signal opened_changed(is_open: bool)

const STAGE_SIGNAL: StringName = &"signal_lock"
const STAGE_FIREWALL: StringName = &"firewall"
const STAGE_CIPHER: StringName = &"cipher"
const FAIL_TRACE: float = 30.0
const PANEL_SIZE: Vector2 = Vector2(944.0, 642.0)
const GAME_SIZE: Vector2 = Vector2(880.0, 480.0)

var is_open: bool = false
var trace: float = 0.0

var _session: StringName = &""
var _stages: Array[StringName] = []
var _stage_index: int = 0
var _difficulty: float = 1.0
var _game: RetroMinigame
var _font: SystemFont
var _root: Control
var _panel: PanelContainer
var _header: Label
var _stage_label: Label
var _trace_bar: ProgressBar
var _trace_fill: StyleBoxFlat
var _game_host: Control
var _footer: Label
var _banner: Label
var _banner_time: float = 0.0
var _advance_time: float = -1.0


func _ready() -> void:
	layer = 20
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "Courier New", "monospace"])
	_build_ui()
	get_viewport().size_changed.connect(_fit_panel)
	_root.visible = false


## Starts a hacking session. `stages` is a list of STAGE_* ids played in order.
func open(session_id: StringName, title_text: String, stages: Array[StringName], difficulty: float) -> void:
	_session = session_id
	_stages = stages
	_stage_index = 0
	_difficulty = difficulty
	trace = 0.0
	_trace_bar.value = trace
	_trace_fill.bg_color = RetroMinigame.PHOSPHOR
	trace_changed.emit(trace)
	is_open = true
	_root.visible = true
	_header.text = "HUNTERNET  //  %s" % title_text
	_start_stage()
	opened_changed.emit(true)


func close() -> void:
	var was_open: bool = is_open
	_advance_time = -1.0
	_discard_game()
	is_open = false
	_root.visible = false
	if was_open:
		opened_changed.emit(false)


func get_current_game() -> RetroMinigame:
	return _game


## Capture discards the session without an abort callback from an obsolete mission step.
func reset_session() -> void:
	close()
	_session = &""
	_stages.clear()
	_stage_index = 0
	trace = 0.0
	_trace_bar.value = 0.0
	_trace_fill.bg_color = RetroMinigame.PHOSPHOR
	_banner_time = 0.0
	trace_changed.emit(trace)


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		var id: StringName = _session
		close()
		session_aborted.emit(id, false)
		return
	if _game != null:
		_game.key_pressed(key.physical_keycode)


func _process(delta: float) -> void:
	if not is_open:
		return
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time * 2.0, 0.0, 1.0)
	if _advance_time >= 0.0:
		_advance_time -= delta
		if _advance_time < 0.0:
			_stage_index += 1
			if _stage_index >= _stages.size():
				var id: StringName = _session
				close()
				session_completed.emit(id)
			else:
				_start_stage()


func _start_stage() -> void:
	_discard_game()
	var stage: StringName = _stages[_stage_index]
	match stage:
		STAGE_FIREWALL:
			_game = FirewallOverrideGame.new()
		STAGE_CIPHER:
			_game = CipherGame.new()
		_:
			_game = SignalLockGame.new()
	_game.difficulty = _difficulty
	_game.font = _font
	# Give the physics-based minigames their playfield before their _ready runs.
	_game.size = GAME_SIZE
	_game_host.add_child(_game)
	_game_host.move_child(_banner, -1)
	_game.succeeded.connect(_on_stage_succeeded)
	_game.failed.connect(_on_stage_failed)
	_game.trace_spike.connect(_add_trace)
	_stage_label.text = "STAGE %d/%d  ·  %s" % [_stage_index + 1, _stages.size(), _game.title()]
	_footer.text = _game.help_text() + "      ESC  disconnect"
	_flash("CONNECTING...", RetroMinigame.PHOSPHOR)


func _discard_game() -> void:
	if _game == null:
		return
	_game.finished = true
	_game.succeeded.disconnect(_on_stage_succeeded)
	_game.failed.disconnect(_on_stage_failed)
	_game.trace_spike.disconnect(_add_trace)
	_game.queue_free()
	_game = null


func _on_stage_succeeded() -> void:
	_flash("ACCESS GRANTED", RetroMinigame.PHOSPHOR)
	_advance_time = 1.1


func _on_stage_failed(reason: String) -> void:
	_add_trace(FAIL_TRACE)
	if not is_open:
		return
	_start_stage()
	_flash("%s  ·  TRACE +%d%%  ·  RETRYING" % [reason, int(FAIL_TRACE)], RetroMinigame.RED)


func _add_trace(amount: float) -> void:
	trace = minf(trace + amount, 100.0)
	_trace_bar.value = trace
	_trace_fill.bg_color = RetroMinigame.PHOSPHOR.lerp(RetroMinigame.RED, trace / 100.0)
	trace_changed.emit(trace)
	if trace >= 100.0 and is_open:
		var id: StringName = _session
		close()
		session_aborted.emit(id, true)


func _flash(message: String, color: Color) -> void:
	_banner.text = message
	_banner.add_theme_color_override(&"font_color", color)
	_banner_time = 1.2


func _label(size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", size_px)
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.036, 0.045, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0a151a")
	style.border_color = Color("3d635d")
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.66)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0.0, 12.0)
	style.content_margin_left = 32.0
	style.content_margin_right = 32.0
	style.content_margin_top = 22.0
	style.content_margin_bottom = 22.0
	_panel.add_theme_stylebox_override(&"panel", style)
	_root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	_panel.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_header = _label(18, RetroMinigame.PHOSPHOR)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	var trace_label := _label(14, RetroMinigame.AMBER)
	trace_label.text = "TRACE"
	top.add_child(trace_label)
	_trace_bar = ProgressBar.new()
	_trace_bar.custom_minimum_size = Vector2(200.0, 14.0)
	_trace_bar.show_percentage = false
	_trace_bar.max_value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.08, 0.04)
	_trace_fill = StyleBoxFlat.new()
	_trace_fill.bg_color = RetroMinigame.PHOSPHOR
	_trace_bar.add_theme_stylebox_override(&"background", bg)
	_trace_bar.add_theme_stylebox_override(&"fill", _trace_fill)
	_trace_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_trace_bar)
	_stage_label = _label(15, RetroMinigame.DIM.lightened(0.5))
	box.add_child(_stage_label)

	_game_host = Control.new()
	_game_host.custom_minimum_size = GAME_SIZE
	_game_host.clip_contents = true
	box.add_child(_game_host)
	var screen := ColorRect.new()
	screen.color = Color("020c08")
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_host.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner = _label(26, RetroMinigame.PHOSPHOR)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -400.0
	_banner.offset_right = 400.0
	_banner.offset_top = 200.0
	_game_host.add_child(_banner)
	_footer = _label(13, RetroMinigame.DIM.lightened(0.6))
	box.add_child(_footer)

	var crt := ColorRect.new()
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var crt_material := ShaderMaterial.new()
	crt_material.shader = load("res://shaders/crt.gdshader") as Shader
	crt_material.set_shader_parameter(&"intensity", 0.34)
	crt.material = crt_material
	_game_host.add_child(crt)
	crt.z_index = 2
	_fit_panel()


func _fit_panel() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var available: Vector2 = (view - Vector2(24.0, 24.0)).max(Vector2.ONE)
	var factor: float = minf(1.0, minf(available.x / PANEL_SIZE.x, available.y / PANEL_SIZE.y))
	_panel.scale = Vector2.ONE * factor
	_panel.position = ((view - PANEL_SIZE * factor) * 0.5).floor()
