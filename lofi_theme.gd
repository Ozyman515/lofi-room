extends RefCounted
## One purple/pink UI theme shared by the on-screen UIs (PC monitor, TV).


static func _box(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 8, bw: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(bw)
	sb.border_color = border
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


static func _dot(size: int, col: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			if Vector2(x - c, y - c).length() <= size / 2.0 - 1.0:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	var text := Color(0.98, 0.92, 0.98)
	var pink := Color(1.0, 0.45, 0.75)

	t.set_color("font_color", "Label", text)

	t.set_stylebox("normal", "Button", _box(Color(0.30, 0.12, 0.42), pink, 8, 2))
	t.set_stylebox("hover", "Button", _box(Color(0.52, 0.20, 0.58), Color(1.0, 0.75, 0.9), 8, 2))
	t.set_stylebox("pressed", "Button", _box(Color(0.90, 0.35, 0.65), Color(1, 1, 1), 8, 2))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", text)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))

	t.set_stylebox("panel", "PanelContainer", _box(Color(0.10, 0.04, 0.17, 0.96), pink, 12, 3))
	t.set_stylebox("panel", "Panel", _box(Color(0.10, 0.04, 0.17, 0.96), pink, 12, 3))

	t.set_stylebox("panel", "ItemList", _box(Color(0.06, 0.02, 0.11, 0.92), Color(0.5, 0.2, 0.6), 8, 2))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", _box(Color(0.55, 0.20, 0.60), Color(0, 0, 0, 0), 6, 0))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(0.55, 0.20, 0.60), Color(0, 0, 0, 0), 6, 0))
	t.set_stylebox("hovered", "ItemList", _box(Color(0.35, 0.14, 0.45), Color(0, 0, 0, 0), 6, 0))
	t.set_color("font_color", "ItemList", text)
	t.set_color("font_selected_color", "ItemList", Color(1, 1, 1))
	t.set_color("font_hovered_color", "ItemList", Color(1, 1, 1))
	t.set_constant("v_separation", "ItemList", 10)

	var rail := _box(Color(0.25, 0.10, 0.35), Color(0, 0, 0, 0), 5, 0)
	rail.content_margin_top = 5.0
	rail.content_margin_bottom = 5.0
	var fill := _box(pink, Color(0, 0, 0, 0), 5, 0)
	fill.content_margin_top = 5.0
	fill.content_margin_bottom = 5.0
	t.set_stylebox("slider", "HSlider", rail)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _dot(30, Color(1.0, 0.85, 0.95)))
	t.set_icon("grabber_highlight", "HSlider", _dot(30, Color(1, 1, 1)))
	return t
