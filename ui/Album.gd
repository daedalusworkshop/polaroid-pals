extends Control
## The shared album: every photo either of you takes lands here as a polaroid.
## Heart favourites together, download full-size pixel-perfect PNGs.

signal closed

const Cozy := preload("res://ui/Cozy.gd")

var grid: GridContainer
var title: Label
var filter := "all"
var filter_buttons := {}
var lightbox: Control
var lb_tex: TextureRect
var lb_caption: Label
var lb_heart: Button
var _current := ""
var _dirty := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Cozy.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.07, 0.16, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60
	panel.offset_right = -60
	panel.offset_top = 40
	panel.offset_bottom = -40
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	title = Cozy.label("Our Album", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	for f in [["all", "All"], ["mine", "Mine"], ["theirs", "Theirs"], ["hearts", "Hearted"]]:
		var b := Cozy.button(f[1], _set_filter.bind(f[0]))
		b.toggle_mode = true
		head.add_child(b)
		filter_buttons[f[0]] = b
	head.add_child(Cozy.tinted_button("Close  (Tab)", close, Cozy.ACCENT))
	v.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(grid)

	_build_lightbox()
	PhotoStore.photo_added.connect(func(_m): _dirty = true)
	PhotoStore.photo_changed.connect(func(_m): _dirty = true)
	PhotoStore.photo_removed.connect(func(_id): _dirty = true)
	visibility_changed.connect(func(): _dirty = true)
	get_viewport().size_changed.connect(func(): _dirty = true)
	_set_filter("all")


func close() -> void:
	lightbox.visible = false
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("album") or event.is_action_pressed("pause"):
		if lightbox.visible and event.is_action_pressed("pause"):
			lightbox.visible = false
		else:
			close()
		get_viewport().set_input_as_handled()
	elif lightbox.visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_LEFT:
			_step(-1)
		elif event.keycode == KEY_RIGHT:
			_step(1)


func _process(_d: float) -> void:
	if visible and _dirty:
		_refresh()


func _set_filter(f: String) -> void:
	filter = f
	for k in filter_buttons:
		filter_buttons[k].button_pressed = k == f
	_dirty = true


func _visible_photos() -> Array:
	var out := []
	for m in PhotoStore.photos:
		var mine: bool = m.get("by", "") == GameState.player_name
		match filter:
			"mine":
				if not mine: continue
			"theirs":
				if mine: continue
			"hearts":
				if m.get("hearts", []).is_empty(): continue
		out.append(m)
	out.reverse()
	return out


func _refresh() -> void:
	_dirty = false
	for c in grid.get_children():
		c.queue_free()
	var w := get_viewport_rect().size.x - 180
	grid.columns = maxi(1, int(w / 290))
	var list := _visible_photos()
	title.text = "Our Album   ·   %d photo%s" % [list.size(), "" if list.size() == 1 else "s"]
	if list.is_empty():
		grid.add_child(Cozy.label("No photos yet. Raise your camera with right-click and take one!", 17, Cozy.INK_SOFT))
		return
	for m in list:
		grid.add_child(_card(m))


func _card(m: Dictionary) -> Control:
	var b := Button.new()
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := Cozy.box(Color("fffdf7"), 4, 0, Color.TRANSPARENT)
	sb.shadow_color = Cozy.SHADOW
	sb.shadow_size = 5
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = Color("fff3de")
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.custom_minimum_size = Vector2(270, 205)
	b.pressed.connect(_open.bind(m["id"]))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_right = -8
	v.offset_top = 8
	v.offset_bottom = -6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var t := TextureRect.new()
	t.texture = PhotoStore.get_texture(m["id"])
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(254, 143)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var hearts: Array = m.get("hearts", [])
	var by: String = m.get("by", "?")
	var cap := Cozy.label("%s%s  ·  %s" % [by, "  <3" if not hearts.is_empty() else "", m.get("world_name", "")], 14, Color(m.get("color", "7a6d8c")).darkened(0.35))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cap)
	b.rotation_degrees = [-1.2, 0.8, -0.4, 1.3][abs(hash(m["id"])) % 4]
	b.pivot_offset = b.custom_minimum_size * 0.5
	return b


# ------------------------------------------------------------------ lightbox

func _build_lightbox() -> void:
	lightbox = Control.new()
	lightbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lightbox.visible = false
	lightbox.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(lightbox)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.05, 0.12, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lightbox.add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 50
	v.offset_right = -50
	v.offset_top = 30
	v.offset_bottom = -24
	v.add_theme_constant_override("separation", 10)
	lightbox.add_child(v)
	var frame := PanelContainer.new()
	var fb := Cozy.box(Color("fffdf7"), 4, 0, Color.TRANSPARENT)
	fb.content_margin_left = 16
	fb.content_margin_right = 16
	fb.content_margin_top = 16
	fb.content_margin_bottom = 12
	frame.add_theme_stylebox_override("panel", fb)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(frame)
	var fv := VBoxContainer.new()
	frame.add_child(fv)
	lb_tex = TextureRect.new()
	lb_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lb_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lb_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lb_tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fv.add_child(lb_tex)
	lb_caption = Cozy.label("", 16, Cozy.INK_SOFT)
	lb_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fv.add_child(lb_caption)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.add_child(Cozy.button("<", _step.bind(-1)))
	lb_heart = Cozy.tinted_button("Heart", _heart, Color("f29bc0"))
	row.add_child(lb_heart)
	row.add_child(Cozy.tinted_button("Download", _download, Cozy.ACCENT_2))
	row.add_child(Cozy.button("Delete (just for me)", _delete))
	row.add_child(Cozy.button("Back", func(): lightbox.visible = false))
	row.add_child(Cozy.button(">", _step.bind(1)))
	v.add_child(row)


func _open(id: String) -> void:
	_current = id
	var m := PhotoStore.get_meta_of(id)
	if m.is_empty():
		lightbox.visible = false
		return
	lb_tex.texture = PhotoStore.get_texture(id)
	lb_caption.text = "by %s   ·   %s   ·   %s   ·   %s   ·   %s   ·   %s" % [
		m.get("by", "?"), m.get("world_name", ""), m.get("clock", ""),
		GameState.WEATHER_NAMES.get(m.get("weather", ""), ""), m.get("lens", ""), m.get("film", "")]
	var hearts: Array = m.get("hearts", [])
	lb_heart.text = "<3  Hearted by %s" % ", ".join(hearts) if not hearts.is_empty() else "<3  Heart"
	lightbox.visible = true


func _step(d: int) -> void:
	var list := _visible_photos()
	for i in list.size():
		if list[i]["id"] == _current:
			_open(list[(i + d + list.size()) % list.size()]["id"])
			return


func _heart() -> void:
	if _current == "":
		return
	var hearts := PhotoStore.toggle_heart(_current, GameState.player_name)
	Net.send_event("hearts", {"id": _current, "hearts": hearts})
	_open(_current)


func _download() -> void:
	if _current != "":
		PhotoStore.download(_current)


func _delete() -> void:
	if _current == "":
		return
	var id := _current
	_step(1)
	PhotoStore.remove(id)
	if PhotoStore.photos.is_empty() or _current == id:
		lightbox.visible = false
