extends RefCounted
## Shared cozy UI palette + helpers (cream paper, plum ink, soft rounded corners).

const PAPER := Color("fff7ea")
const PAPER_DARK := Color("f1e4cf")
const INK := Color("3b3050")
const INK_SOFT := Color("7a6d8c")
const ACCENT := Color("f08a78")
const ACCENT_2 := Color("7fb6e8")
const GOOD := Color("7cc47a")
const SHADOW := Color(0.12, 0.08, 0.2, 0.35)


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	var panel := box(PAPER, 14, 2, INK.lerp(PAPER, 0.6))
	panel.shadow_color = SHADOW
	panel.shadow_size = 8
	panel.shadow_offset = Vector2(0, 4)
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var bn := box(Color("ffe9d6"), 10, 2, INK.lerp(PAPER, 0.45))
	var bh := box(Color("ffdcc2"), 10, 2, INK.lerp(PAPER, 0.3))
	var bp := box(Color("f7c9a8"), 10, 2, INK)
	var bd := box(Color("eee6dc"), 10, 2, INK.lerp(PAPER, 0.75))
	for b in [bn, bh, bp, bd]:
		b.content_margin_left = 14
		b.content_margin_right = 14
		b.content_margin_top = 7
		b.content_margin_bottom = 7
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("hover_pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", INK_SOFT)
	t.set_color("font_focus_color", "Button", INK)

	var le := box(Color("fffdf8"), 8, 2, INK.lerp(PAPER, 0.5))
	le.content_margin_left = 10
	le.content_margin_right = 10
	le.content_margin_top = 6
	le.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", box(Color("fffdf8"), 8, 2, ACCENT))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK_SOFT)
	t.set_color("caret_color", "LineEdit", INK)

	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_hover_pressed_color", "CheckBox", INK)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())

	var track := box(PAPER_DARK, 6, 0, Color.TRANSPARENT)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var fill := box(ACCENT, 6, 0, Color.TRANSPARENT)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var sb := box(Color(0, 0, 0, 0), 4, 0, Color.TRANSPARENT)
	t.set_stylebox("scroll", "VScrollBar", box(PAPER_DARK, 6, 0, Color.TRANSPARENT))
	t.set_stylebox("grabber", "VScrollBar", box(INK_SOFT, 6, 0, Color.TRANSPARENT))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(INK, 6, 0, Color.TRANSPARENT))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(INK, 6, 0, Color.TRANSPARENT))
	t.set_stylebox("panel", "ScrollContainer", sb)
	return t


static func box(bg: Color, radius: int, border: int, border_col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.anti_aliasing = true
	return s


static func label(text: String, size := 17, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	b.custom_minimum_size.x = min_w
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func tinted_button(text: String, cb: Callable, col: Color) -> Button:
	var b := button(text, cb)
	var n := box(col.lightened(0.55), 10, 2, col.darkened(0.25))
	var h := box(col.lightened(0.4), 10, 2, col.darkened(0.35))
	var p := box(col.lightened(0.2), 10, 3, INK)
	for s in [n, h, p]:
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 8
		s.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	return b
