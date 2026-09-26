extends Control
## In-world overlay: viewfinder, partner name tags + chat bubbles, off-screen
## partner arrow, pings, toasts, the polaroid pop-up, chat and control hints.

signal chat_submitted(text: String)
signal chat_closed

const Cozy := preload("res://ui/Cozy.gd")

var world
var info_label: Label
var room_label: Label
var toasts: VBoxContainer
var chat_log: VBoxContainer
var chat_edit: LineEdit
var hint_label: Label
var polaroid: PanelContainer
var polaroid_tex: TextureRect
var polaroid_caption: Label
var count_label: Label
var hud_visible := true
var pings: Array = []           # [Vector3, name, Color, time_left]
var _flash := 0.0
var _polaroid_t := -1.0
var _hint_t := 25.0
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Cozy.theme()
	_font = ThemeDB.fallback_font

	var info_panel := PanelContainer.new()
	info_panel.position = Vector2(16, 14)
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var small := Cozy.box(Color(1.0, 0.97, 0.92, 0.88), 10, 0, Color.TRANSPARENT)
	small.content_margin_left = 12
	small.content_margin_right = 12
	small.content_margin_top = 6
	small.content_margin_bottom = 6
	info_panel.add_theme_stylebox_override("panel", small)
	add_child(info_panel)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 0)
	info_panel.add_child(iv)
	info_label = Cozy.label("", 15)
	iv.add_child(info_label)
	room_label = Cozy.label("", 14, Cozy.INK_SOFT)
	iv.add_child(room_label)

	var count_panel := PanelContainer.new()
	count_panel.add_theme_stylebox_override("panel", small.duplicate())
	count_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	count_panel.position = Vector2(get_viewport_rect().size.x - 150, 14)
	count_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_panel.name = "Count"
	add_child(count_panel)
	count_label = Cozy.label("", 15)
	count_panel.add_child(count_label)

	toasts = VBoxContainer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.position.y = 18
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)

	chat_log = VBoxContainer.new()
	chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_log.add_theme_constant_override("separation", 2)
	add_child(chat_log)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "say something nice…  (Enter to send, Esc to cancel)"
	chat_edit.custom_minimum_size = Vector2(420, 0)
	chat_edit.max_length = 120
	chat_edit.visible = false
	chat_edit.text_submitted.connect(_on_chat_submit)
	chat_edit.gui_input.connect(_on_chat_key)
	add_child(chat_edit)

	hint_label = Cozy.label("", 14, Color(1, 1, 1, 0.92))
	hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	hint_label.add_theme_constant_override("shadow_offset_x", 1)
	hint_label.add_theme_constant_override("shadow_offset_y", 1)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)

	polaroid = PanelContainer.new()
	var pbox := Cozy.box(Color("fffdf7"), 4, 0, Color.TRANSPARENT)
	pbox.content_margin_left = 10
	pbox.content_margin_right = 10
	pbox.content_margin_top = 10
	pbox.content_margin_bottom = 8
	pbox.shadow_color = Cozy.SHADOW
	pbox.shadow_size = 10
	polaroid.add_theme_stylebox_override("panel", pbox)
	polaroid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	polaroid.visible = false
	add_child(polaroid)
	var pv := VBoxContainer.new()
	polaroid.add_child(pv)
	polaroid_tex = TextureRect.new()
	polaroid_tex.custom_minimum_size = Vector2(256, 144)
	polaroid_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	polaroid_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	polaroid_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pv.add_child(polaroid_tex)
	polaroid_caption = Cozy.label("", 14, Cozy.INK_SOFT)
	polaroid_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(polaroid_caption)

	get_viewport().size_changed.connect(_layout)
	_layout()
	PhotoStore.photo_added.connect(_on_photo_added)


func _layout() -> void:
	var s := get_viewport_rect().size
	get_node("Count").position = Vector2(s.x - 170, 14)
	chat_edit.position = Vector2(16, s.y - 84)
	chat_log.position = Vector2(18, s.y - 250)
	chat_log.size = Vector2(460, 160)
	hint_label.position = Vector2(0, s.y - 36)
	hint_label.size = Vector2(s.x, 24)
	toasts.position = Vector2(s.x * 0.5 - 200, 18)
	toasts.size = Vector2(400, 0)


func _player():
	return world.player if world else null


# ------------------------------------------------------------------ API

func toast(text: String, col := Cozy.PAPER) -> void:
	var p := PanelContainer.new()
	var sb := Cozy.box(Color(col, 0.94), 12, 0, Color.TRANSPARENT)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Cozy.label(text, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toasts.add_child(p)
	var tw := create_tween()
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func add_chat(who: String, text: String, col: Color) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.custom_minimum_size.x = 460
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("default_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.text = "[color=#%s][b]%s[/b][/color]  %s" % [col.lightened(0.3).to_html(false), who.xml_escape(), text.xml_escape()]
	chat_log.add_child(l)
	while chat_log.get_child_count() > 7:
		chat_log.get_child(0).free()
	var tw := create_tween()
	tw.tween_interval(12.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


func open_chat() -> void:
	chat_edit.visible = true
	chat_edit.text = ""
	chat_edit.grab_focus()


func close_chat() -> void:
	chat_edit.visible = false
	chat_edit.release_focus()
	chat_closed.emit()


func chat_open() -> bool:
	return chat_edit.visible


func _on_chat_submit(text: String) -> void:
	text = text.strip_edges()
	close_chat()
	if text != "":
		chat_submitted.emit(text)


func flash() -> void:
	_flash = 1.0


func add_ping(pos: Vector3, who: String, col: Color) -> void:
	pings.append([pos, who, col, 8.0])


func _on_photo_added(meta: Dictionary) -> void:
	polaroid_tex.texture = PhotoStore.get_texture(meta["id"])
	var mine: bool = meta.get("by", "") == GameState.player_name
	polaroid_caption.text = "%s  ·  %s" % ["you" if mine else str(meta.get("by", "")), meta.get("clock", "")]
	polaroid.visible = true
	_polaroid_t = 0.0


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 3.5)
	_hint_t -= delta
	var s := get_viewport_rect().size
	# polaroid slides up from the bottom-right, lingers, slides away
	if _polaroid_t >= 0.0:
		_polaroid_t += delta
		var ps := polaroid.get_combined_minimum_size()
		var shown := Vector2(s.x - ps.x - 26, s.y - ps.y - 60)
		var hidden := Vector2(s.x - ps.x - 26, s.y + 20)
		var t := _polaroid_t
		var k := 0.0
		if t < 0.45:
			k = ease(t / 0.45, 0.3)
		elif t < 3.6:
			k = 1.0
		elif t < 4.2:
			k = 1.0 - ease((t - 3.6) / 0.6, 2.5)
		else:
			polaroid.visible = false
			_polaroid_t = -1.0
		polaroid.position = hidden.lerp(shown, k)
		polaroid.rotation = deg_to_rad(-3.0 + k * 1.5)
	# info text
	var world_name := GameState.world_name()
	info_label.text = "%s   ·   %s   ·   %s" % [world_name, GameState.clock_string(), GameState.WEATHER_NAMES.get(GameState.weather, "")]
	var room := ""
	if Net.room_code != "" and Net.is_host():
		room = "Room code  %s" % Net.room_code
		if GameState.partners.is_empty():
			room += "   ·   waiting for your partner…"
	if not GameState.partners.is_empty():
		var names := []
		for id in GameState.partners:
			names.append(GameState.partners[id].get("name", "?"))
		room = ("%s   ·   " % room if room != "" else "") + "with " + ", ".join(names)
	room_label.text = room
	room_label.visible = room != ""
	count_label.text = "Album  %d   (Tab)" % PhotoStore.photos.size()
	var p = _player()
	if p and p.raised:
		hint_label.text = "Click  shoot   ·   Scroll  lens   ·   Q/E  aperture   ·   Z/X  exposure   ·   F  film   ·   Right-click  lower"
	else:
		hint_label.text = "WASD  walk   ·   Shift  run   ·   Right-click  camera   ·   Tab  album   ·   T  chat   ·   1-4  emotes   ·   G  ping   ·   Esc  menu"
	hint_label.modulate.a = 1.0 if (_hint_t > 0.0 or (p and p.raised)) else 0.0
	for pg in pings.duplicate():
		pg[3] -= delta
		if pg[3] <= 0.0:
			pings.erase(pg)
	queue_redraw()


func _draw() -> void:
	if not hud_visible or world == null or not world.playing:
		return
	var s := get_viewport_rect().size
	var p = _player()
	if p == null:
		return
	if p.raised:
		_draw_viewfinder(s, p)
	else:
		draw_circle(s * 0.5, 2.0, Color(1, 1, 1, 0.75))
	for id in world.avatars:
		var av = world.avatars[id]
		var info: Dictionary = GameState.partners.get(id, {})
		var col: Color = info.get("color", Color.WHITE)
		var nm: String = info.get("name", "Partner")
		var sp = world.screen_point(av.head_pos())
		var dist: float = p.global_position.distance_to(av.global_position)
		if sp != null and Rect2(Vector2.ZERO, s).grow(-10).has_point(sp):
			_draw_tag(sp, nm, col, dist)
			if av.chat_timer > 0.0:
				_draw_bubble(sp - Vector2(0, 30), av.chat_text)
		else:
			_draw_edge_arrow(av.global_position, "%s  %dm" % [nm, int(dist)], col, s, p)
	for pg in pings:
		var a := clampf(pg[3], 0.0, 1.0)
		var sp = world.screen_point(pg[0] + Vector3(0, 1.5, 0))
		if sp != null and Rect2(Vector2.ZERO, s).has_point(sp):
			var pulse := 6.0 + sin(Time.get_ticks_msec() * 0.008) * 3.0
			var pts := PackedVector2Array([sp + Vector2(0, -12 - pulse), sp + Vector2(10, -pulse * 0.3), sp + Vector2(0, 12), sp + Vector2(-10, -pulse * 0.3)])
			draw_colored_polygon(pts, Color(pg[2], 0.85 * a))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, a), 2.0)
			_text(sp + Vector2(0, 30), "%s is here!" % pg[1], 14, Color(1, 1, 1, a), true)
		else:
			_draw_edge_arrow(pg[0], "%s's ping" % pg[1], pg[2], s, p)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, _flash * 0.85))


func _draw_viewfinder(s: Vector2, p) -> void:
	var m := Vector2(s.x * 0.05, s.y * 0.07)
	var r := Rect2(m, s - m * 2.0)
	var c := Color(1, 1, 1, 0.85)
	var L := 34.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var dx := L if corner.x < s.x * 0.5 else -L
		var dy := L if corner.y < s.y * 0.5 else -L
		draw_line(corner, corner + Vector2(dx, 0), c, 3.0)
		draw_line(corner, corner + Vector2(0, dy), c, 3.0)
	var g := Color(1, 1, 1, 0.18)
	for i in [1, 2]:
		draw_line(Vector2(r.position.x + r.size.x * i / 3.0, r.position.y), Vector2(r.position.x + r.size.x * i / 3.0, r.end.y), g, 1.0)
		draw_line(Vector2(r.position.x, r.position.y + r.size.y * i / 3.0), Vector2(r.end.x, r.position.y + r.size.y * i / 3.0), g, 1.0)
	var fc := Color(0.6, 1.0, 0.6, 0.9)
	var fr := Rect2(s * 0.5 - Vector2(22, 16), Vector2(44, 32))
	for corner in [fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)]:
		var dx := 8.0 if corner.x < s.x * 0.5 else -8.0
		var dy := 8.0 if corner.y < s.y * 0.5 else -8.0
		draw_line(corner, corner + Vector2(dx, 0), fc, 2.0)
		draw_line(corner, corner + Vector2(0, dy), fc, 2.0)
	var ev := "%+.1f" % p.exposure
	var focus := "%.1fm" % p.focus_dist if p.focus_dist < 100.0 else "inf"
	var txt := "%dmm     f/%s     %s EV     %s     focus %s" % [p.focal(), str(p.aperture()).trim_suffix(".0"), ev, p.film()["name"], focus]
	_text(Vector2(s.x * 0.5, r.end.y - 14), txt, 16, Color(1, 1, 1, 0.95), true)
	draw_circle(Vector2(r.position.x + 22, r.position.y + 22), 6.0, Color(1, 0.35, 0.35, 0.9 if int(Time.get_ticks_msec() / 600) % 2 == 0 else 0.4))
	_text(Vector2(r.position.x + 36, r.position.y + 28), "%d" % PhotoStore.photos.size(), 16, c, false)
	if p.busy:
		_text(s * 0.5 + Vector2(0, 50), "developing…", 16, c, true)


func _draw_tag(sp: Vector2, nm: String, col: Color, dist: float) -> void:
	var fs := 15
	var w := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18
	var rect := Rect2(sp - Vector2(w * 0.5, 22), Vector2(w, 22))
	draw_style_box(Cozy.box(Color(col, 0.9), 11, 2, Color(1, 1, 1, 0.9)), rect)
	_text(sp + Vector2(0, -6), nm, fs, Cozy.INK, true)


func _draw_bubble(sp: Vector2, text: String) -> void:
	var fs := 15
	var w := minf(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20, 320)
	var rect := Rect2(sp - Vector2(w * 0.5, 28), Vector2(w, 28))
	draw_style_box(Cozy.box(Color(1, 1, 1, 0.95), 12, 0, Color.TRANSPARENT), rect)
	draw_colored_polygon(PackedVector2Array([sp + Vector2(-6, 0), sp + Vector2(6, 0), sp + Vector2(0, 8)]), Color(1, 1, 1, 0.95))
	draw_string(_font, Vector2(rect.position.x + 10, sp.y - 9), text, HORIZONTAL_ALIGNMENT_LEFT, w - 20, fs, Cozy.INK)


func _draw_edge_arrow(target: Vector3, label: String, col: Color, s: Vector2, p) -> void:
	var cam: Camera3D = p.camera
	var local := cam.global_transform.affine_inverse() * target
	var d := Vector2(local.x, -local.y)
	if local.z > 0.0:
		d = -d if d.length() > 0.01 else Vector2(0, 1)
		d.y = absf(d.y) + 0.5
	if d.length() < 0.001:
		return
	d = d.normalized()
	var c := s * 0.5
	var ext := s * 0.5 - Vector2(60, 60)
	var t := minf(ext.x / maxf(absf(d.x), 0.001), ext.y / maxf(absf(d.y), 0.001))
	var pos := c + d * t
	var perp := Vector2(-d.y, d.x)
	var tri := PackedVector2Array([pos + d * 16, pos - d * 8 + perp * 11, pos - d * 8 - perp * 11])
	draw_colored_polygon(tri, Color(col, 0.95))
	draw_polyline(tri + PackedVector2Array([tri[0]]), Color(1, 1, 1, 0.9), 2.0)
	_text(pos - d * 28 + Vector2(0, 5), label, 14, Color.WHITE, true)


func _text(pos: Vector2, text: String, size: int, col: Color, centered: bool) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := pos - Vector2(w * 0.5, 0) if centered else pos
	draw_string(_font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, col.a * 0.55))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _on_chat_key(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		close_chat()
		chat_edit.accept_event()
