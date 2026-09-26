extends Control
## Esc menu: invite code, time of day, weather, world switching, settings.
## Changes to time / weather / world are shared with your partner.

signal resume
signal leave
signal settings_changed          # time / weather / flow (broadcast by Main)
signal world_change(id: String, seed: int)
signal invite
signal pixel_changed

const Cozy := preload("res://ui/Cozy.gd")

var tod_slider: HSlider
var tod_label: Label
var flow_check: CheckBox
var weather_buttons := {}
var world_buttons := {}
var room_box: VBoxContainer
var room_label: Label
var pixel_buttons := {}
var _syncing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Cozy.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.07, 0.16, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	panel.add_child(v)

	var head := HBoxContainer.new()
	var t := Cozy.label("Taking a breather", 26)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(Cozy.tinted_button("Resume", func(): resume.emit(), Cozy.GOOD))
	v.add_child(head)

	room_box = VBoxContainer.new()
	v.add_child(room_box)
	room_label = Cozy.label("", 17)
	room_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_box.add_child(room_label)
	var room_row := HBoxContainer.new()
	room_row.add_theme_constant_override("separation", 8)
	room_row.add_child(Cozy.button("Copy invite link", _copy_code))
	room_row.add_child(Cozy.tinted_button("Invite someone (open a room)", func(): invite.emit(), Cozy.ACCENT))
	room_box.add_child(room_row)
	v.add_child(HSeparator.new())

	v.add_child(Cozy.label("Time of day", 16, Cozy.INK_SOFT))
	var tod_row := HBoxContainer.new()
	tod_row.add_theme_constant_override("separation", 10)
	tod_slider = HSlider.new()
	tod_slider.min_value = 0.0
	tod_slider.max_value = 24.0
	tod_slider.step = 0.05
	tod_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tod_slider.custom_minimum_size.y = 24
	tod_slider.value_changed.connect(_on_tod)
	tod_row.add_child(tod_slider)
	tod_label = Cozy.label("00:00", 17)
	tod_label.custom_minimum_size.x = 60
	tod_row.add_child(tod_label)
	v.add_child(tod_row)
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	for p in [["Sunrise", 5.9], ["Morning", 9.0], ["Noon", 12.5], ["Golden hour", 17.4], ["Dusk", 19.3], ["Night", 22.5]]:
		presets.add_child(Cozy.button(p[0], _set_tod.bind(p[1])))
	v.add_child(presets)
	flow_check = CheckBox.new()
	flow_check.text = "Let time pass (a day lasts 48 minutes)"
	flow_check.toggled.connect(_on_flow)
	v.add_child(flow_check)

	v.add_child(Cozy.label("Weather", 16, Cozy.INK_SOFT))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 6)
	for w in GameState.WEATHERS:
		var b := Cozy.button(GameState.WEATHER_NAMES[w], _set_weather.bind(w))
		b.toggle_mode = true
		wrow.add_child(b)
		weather_buttons[w] = b
	v.add_child(wrow)

	v.add_child(Cozy.label("Travel to", 16, Cozy.INK_SOFT))
	var world_row := HBoxContainer.new()
	world_row.add_theme_constant_override("separation", 6)
	for id in GameState.WORLD_ORDER:
		var b := Cozy.tinted_button(GameState.WORLDS[id]["name"], _travel.bind(id, false), GameState.WORLDS[id]["accent"])
		world_row.add_child(b)
		world_buttons[id] = b
	world_row.add_child(Cozy.button("New spot here", func(): _travel(GameState.world_id, true)))
	v.add_child(world_row)
	v.add_child(HSeparator.new())

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	srow.add_child(Cozy.label("Pixels", 16, Cozy.INK_SOFT))
	for p in [["Chunky", 216], ["Cozy", 270], ["Crisp", 360]]:
		var b := Cozy.button(p[0], _set_pixels.bind(p[1]))
		b.toggle_mode = true
		srow.add_child(b)
		pixel_buttons[p[1]] = b
	srow.add_child(Cozy.label("   Mouse", 16, Cozy.INK_SOFT))
	var ms := HSlider.new()
	ms.min_value = 0.3
	ms.max_value = 2.5
	ms.step = 0.05
	ms.value = GameState.mouse_sensitivity
	ms.custom_minimum_size = Vector2(140, 24)
	ms.value_changed.connect(_on_mouse)
	srow.add_child(ms)
	v.add_child(srow)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(Cozy.button("Leave to title", func(): leave.emit()))
	v.add_child(bottom)
	visibility_changed.connect(sync)


func sync() -> void:
	if not is_inside_tree():
		return
	_syncing = true
	tod_slider.value = GameState.time_of_day
	tod_label.text = GameState.clock_string()
	flow_check.button_pressed = GameState.time_flowing
	for w in weather_buttons:
		weather_buttons[w].button_pressed = w == GameState.weather
	for p in pixel_buttons:
		pixel_buttons[p].button_pressed = p == GameState.pixel_height
	var txt := ""
	if Net.room_code != "" and Net.is_host():
		txt = "Your room code is  %s  — send your partner the invite link, or they can type the code on the title screen." % Net.room_code
	elif Net.has_partner():
		txt = "Walking together in room %s." % Net.room_code
	else:
		txt = "Wandering alone. Open a room and share the code to invite someone in."
	if not GameState.partners.is_empty():
		var names := []
		for id in GameState.partners:
			names.append(GameState.partners[id].get("name", "?"))
		txt += "\nWith you: " + ", ".join(names)
	room_label.text = txt
	_syncing = false


func _process(_d: float) -> void:
	if visible and not tod_slider.has_focus():
		if absf(tod_slider.value - GameState.time_of_day) > 0.06:
			_syncing = true
			tod_slider.value = GameState.time_of_day
			_syncing = false
		tod_label.text = GameState.clock_string()


func _on_flow(on: bool) -> void:
	if _syncing:
		return
	GameState.time_flowing = on
	settings_changed.emit()


func _on_mouse(val: float) -> void:
	GameState.mouse_sensitivity = val
	GameState.save_settings()


func _copy_code() -> void:
	if Net.room_code != "":
		DisplayServer.clipboard_set(Net.invite_link())


func _on_tod(v: float) -> void:
	if _syncing:
		return
	GameState.time_of_day = v
	tod_label.text = GameState.clock_string()
	settings_changed.emit()


func _set_tod(t: float) -> void:
	GameState.time_of_day = t
	sync()
	settings_changed.emit()


func _set_weather(w: String) -> void:
	GameState.weather = w
	sync()
	settings_changed.emit()


func _travel(id: String, new_seed: bool) -> void:
	var s := GameState.world_seed
	if new_seed or id != GameState.world_id:
		s = randi() % 99999 + 1
	world_change.emit(id, s)


func _set_pixels(h: int) -> void:
	GameState.pixel_height = h
	GameState.save_settings()
	sync()
	pixel_changed.emit()
