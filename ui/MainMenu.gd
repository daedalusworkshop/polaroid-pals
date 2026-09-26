extends Control
## Title screen floating over a live, slowly orbiting preview of the chosen world.

signal host_pressed
signal join_pressed(code: String)
signal solo_pressed
signal world_selected(id: String)

const Cozy := preload("res://ui/Cozy.gd")

var name_edit: LineEdit
var code_edit: LineEdit
var status_label: Label
var world_buttons := {}
var swatches: Array = []
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Cozy.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.position = Vector2(40, 36)
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var title := Cozy.label("Polaroid Pals", 40, Cozy.INK)
	v.add_child(title)
	v.add_child(Cozy.label("a cozy photo walk for two", 16, Cozy.INK_SOFT))
	v.add_child(HSeparator.new())

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(Cozy.label("You are", 16, Cozy.INK_SOFT))
	name_edit = LineEdit.new()
	name_edit.text = GameState.player_name
	name_edit.max_length = 16
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t): GameState.player_name = t.strip_edges() if t.strip_edges() != "" else "Photographer")
	name_row.add_child(name_edit)
	v.add_child(name_row)

	var sw_row := HBoxContainer.new()
	sw_row.add_theme_constant_override("separation", 6)
	sw_row.add_child(Cozy.label("Scarf", 16, Cozy.INK_SOFT))
	for c in GameState.PLAYER_COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 30)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_on_swatch.bind(c))
		b.set_meta("color", c)
		sw_row.add_child(b)
		swatches.append(b)
	v.add_child(sw_row)
	_refresh_swatches()

	v.add_child(Cozy.label("Where to today?", 16, Cozy.INK_SOFT))
	for id in GameState.WORLD_ORDER:
		var info: Dictionary = GameState.WORLDS[id]
		var b := Cozy.tinted_button("%s\n%s" % [info["name"], info["place"]], func(): _pick_world(id), info["accent"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		v.add_child(b)
		world_buttons[id] = b
	_refresh_world_buttons()

	v.add_child(HSeparator.new())
	var host := Cozy.tinted_button("Host a walk  (get a room code)", _on_host, Cozy.ACCENT)
	v.add_child(host)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "partner's code, e.g. MOSS-42"
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.text_submitted.connect(func(_t): _join())
	join_row.add_child(code_edit)
	join_row.add_child(Cozy.tinted_button("Join", _join, Cozy.ACCENT_2))
	v.add_child(join_row)
	v.add_child(Cozy.button("Wander alone", _on_solo))
	status_label = Cozy.label("", 15, Cozy.INK_SOFT)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 380
	v.add_child(status_label)

	var tip := Cozy.label("Both of you open this same page. One hosts, the other types the code.", 14, Color(1, 1, 1, 0.9))
	tip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	tip.add_theme_constant_override("shadow_offset_x", 1)
	tip.add_theme_constant_override("shadow_offset_y", 1)
	tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	tip.position = Vector2(44, get_viewport_rect().size.y - 40)
	tip.name = "Tip"
	add_child(tip)
	get_viewport().size_changed.connect(func(): tip.position = Vector2(44, get_viewport_rect().size.y - 40))


func _join() -> void:
	if _busy:
		return
	join_pressed.emit(code_edit.text)


func _pick_world(id: String) -> void:
	if _busy:
		_refresh_world_buttons()
		return
	GameState.world_id = id
	GameState.time_of_day = GameState.WORLDS[id]["default_time"]
	_refresh_world_buttons()
	world_selected.emit(id)


func _refresh_world_buttons() -> void:
	for id in world_buttons:
		world_buttons[id].button_pressed = id == GameState.world_id


func _refresh_swatches() -> void:
	for b in swatches:
		var c: Color = b.get_meta("color")
		var sel: bool = c.is_equal_approx(GameState.player_color)
		var sb := Cozy.box(c, 8, 3 if sel else 1, Cozy.INK if sel else c.darkened(0.3))
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)


func set_status(text: String, busy := false) -> void:
	status_label.text = text
	_busy = busy


func _on_host() -> void:
	if not _busy:
		host_pressed.emit()


func _on_solo() -> void:
	if not _busy:
		solo_pressed.emit()


func _on_swatch(c: Color) -> void:
	GameState.player_color = c
	_refresh_swatches()
