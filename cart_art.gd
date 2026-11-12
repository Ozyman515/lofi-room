extends RefCounted
## Painted cart labels. Each one is a small canvas drawn in code and shown with nearest filtering,
## so it keeps a chunky pixel look. Every picture is an original drawing (no real games' characters).

const SUN := Color(1.0, 0.72, 0.55)
const MAG := Color(0.88, 0.25, 0.55)
const CYAN := Color(0.20, 0.80, 0.85)
const DUSK := Color(0.20, 0.12, 0.36)


static func _img(w: int, h: int) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 1))
	return im


static func tex(im: Image) -> ImageTexture:
	return ImageTexture.create_from_image(im)


static func _px(im: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		im.set_pixel(x, y, c)


static func _rect(im: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(im, xx, yy, c)


static func _ellipse(im: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for yy in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for xx in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := (xx + 0.5 - cx) / rx
			var dy := (yy + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(im, xx, yy, c)


static func _poly(im: Image, pts: Array, c: Color) -> void:
	var miny := 99999
	var maxy := -99999
	for p in pts:
		miny = mini(miny, int(floor(p.y)))
		maxy = maxi(maxy, int(ceil(p.y)))
	for yy in range(miny, maxy + 1):
		var yc := yy + 0.5
		var xs := []
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			if (a.y <= yc and b.y > yc) or (b.y <= yc and a.y > yc):
				xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			for xx in range(int(round(xs[k])), int(round(xs[k + 1]))):
				_px(im, xx, yy, c)


static func _line(im: Image, a: Vector2, b: Vector2, t: float, c: Color) -> void:
	var n := int(a.distance_to(b) * 2.0) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		_ellipse(im, p.x, p.y, t * 0.5, t * 0.5, c)


static func _grad(im: Image, y0: int, y1: int, c0: Color, c1: Color) -> void:
	for yy in range(y0, y1):
		var k := float(yy - y0) / maxf(1.0, float(y1 - y0 - 1))
		_rect(im, 0, yy, im.get_width(), 1, c0.lerp(c1, k))


# rows of characters, one pixel each (scaled by s); '.' is empty
static func _sprite(im: Image, ox: int, oy: int, rows: Array, pal: Dictionary, s: int = 1) -> void:
	for ry in rows.size():
		var row: String = rows[ry]
		for rx in row.length():
			var ch := row[rx]
			if ch != "." and pal.has(ch):
				_rect(im, ox + rx * s, oy + ry * s, s, s, pal[ch])


# ---------------------------------------------------------------- 8-BIT: a cat in headphones on a rooftop, watching the moon

# a thin ring (ripples, moon halos)
static func _ring(im: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	var n := int((rx + ry) * 4.0) + 8
	for i in n:
		var a := TAU * i / n
		_px(im, int(round(cx + cos(a) * rx)), int(round(cy + sin(a) * ry)), c)


static func nes_label() -> ImageTexture:
	var im := _img(56, 92)
	_grad(im, 0, 44, Color(0.10, 0.07, 0.30), Color(0.55, 0.20, 0.55))
	_grad(im, 44, 66, Color(0.55, 0.20, 0.55), Color(0.98, 0.58, 0.50))
	_ellipse(im, 38, 17, 8, 8, Color(1.0, 0.93, 0.80))                          # the moon
	_ring(im, 38, 17, 11, 11, Color(0.62, 0.40, 0.72))                          # its halo
	for st in [Vector2(6, 6), Vector2(18, 13), Vector2(50, 33), Vector2(9, 27), Vector2(27, 4)]:
		_px(im, int(st.x), int(st.y), Color(1, 0.95, 1))                          # a few stars
	var far := Color(0.30, 0.13, 0.42)                                           # the city behind
	for bl in [[0, 48, 8], [8, 42, 6], [14, 50, 9], [23, 45, 7], [30, 52, 8], [38, 40, 7], [45, 47, 11]]:
		_rect(im, bl[0], bl[1], bl[2], 66 - bl[1], far)
	for w in [Vector2(10, 45), Vector2(40, 44), Vector2(48, 51), Vector2(17, 54)]:  # four lit windows
		_rect(im, int(w.x), int(w.y), 2, 2, Color(1.0, 0.80, 0.45))
	_rect(im, 0, 64, 56, 10, Color(0.16, 0.08, 0.24))                           # the rooftop ledge
	_rect(im, 0, 64, 56, 1, Color(0.62, 0.32, 0.55))
	var fur := Color(0.07, 0.05, 0.12)                                           # the cat, from behind
	_line(im, Vector2(28, 62), Vector2(36, 63), 3.0, fur)                       # tail along the ledge
	_line(im, Vector2(36, 63), Vector2(40, 58), 3.0, fur)
	_ellipse(im, 22, 56, 8, 8.5, fur)                                            # body
	_ellipse(im, 22, 44, 6, 5.5, fur)                                            # head
	_poly(im, [Vector2(16, 43), Vector2(16, 35), Vector2(21, 40)], fur)         # ears
	_poly(im, [Vector2(28, 43), Vector2(28, 35), Vector2(23, 40)], fur)
	var band := Color(0.20, 0.80, 0.85)                                          # headphones
	_line(im, Vector2(15.5, 44), Vector2(17, 39), 1.2, band)
	_line(im, Vector2(17, 39), Vector2(22, 37.5), 1.2, band)
	_line(im, Vector2(22, 37.5), Vector2(27, 39), 1.2, band)
	_line(im, Vector2(27, 39), Vector2(28.5, 44), 1.2, band)
	_ellipse(im, 15.5, 45, 2.0, 2.8, MAG)
	_ellipse(im, 28.5, 45, 2.0, 2.8, MAG)
	_rect(im, 0, 74, 56, 18, Color(0.12, 0.07, 0.22))                           # title band
	_rect(im, 0, 74, 56, 1, CYAN)
	return tex(im)


# ---------------------------------------------------------------- 16-BIT: two koi circling under the moon's reflection (left part), dark panel on the right

static func _koi(im: Image, c: Vector2, dir: float, body: Color, patch: Color) -> void:
	var fin := body.lerp(Color(1, 1, 1), 0.35)
	_poly(im, [c + Vector2(-dir * 9, 0), c + Vector2(-dir * 16, -5), c + Vector2(-dir * 14, 0), c + Vector2(-dir * 16, 5)], fin)   # tail
	_ellipse(im, c.x, c.y, 10, 4, body)
	_ellipse(im, c.x - dir * 2, c.y - 1, 3.5, 2.2, patch)                       # one patch on its back
	_ellipse(im, c.x + dir * 6, c.y, 3.5, 3, patch)                             # and its head
	_poly(im, [c + Vector2(dir * 2, 3), c + Vector2(-dir * 2, 7), c + Vector2(-dir * 1, 3)], fin)                                    # side fin
	_px(im, int(c.x + dir * 8), int(c.y - 1), Color(0.08, 0.06, 0.1))           # eye


static func snes_label() -> ImageTexture:
	var im := _img(120, 56)
	_grad(im, 0, 56, Color(0.08, 0.30, 0.42), Color(0.04, 0.10, 0.24))
	var shine := Color(0.98, 0.86, 0.80)                                         # the moon on the water, broken by ripples
	for i in 6:
		var w := 14 - absi(i - 2) * 3
		_rect(im, 38 - w / 2 + (i % 2) * 2, 8 + i * 3, w, 1, shine)
	_ring(im, 38, 15, 15, 7, Color(0.20, 0.52, 0.62))
	_ring(im, 38, 15, 24, 11, Color(0.14, 0.42, 0.54))
	var pad := Color(0.16, 0.54, 0.42)                                           # two lily pads
	_ellipse(im, 9, 9, 7, 4, pad)
	_poly(im, [Vector2(9, 9), Vector2(16, 6), Vector2(16, 10)], Color(0.08, 0.30, 0.42))
	_ellipse(im, 66, 47, 8, 4.5, pad)
	_poly(im, [Vector2(66, 47), Vector2(58, 44), Vector2(58, 49)], Color(0.05, 0.14, 0.27))
	_ellipse(im, 63, 45, 2, 1.5, Color(0.98, 0.55, 0.70))                       # a flower on it
	_koi(im, Vector2(30, 32), 1.0, Color(0.98, 0.95, 0.92), Color(0.98, 0.42, 0.18))
	_koi(im, Vector2(46, 42), -1.0, Color(0.98, 0.48, 0.20), Color(0.99, 0.95, 0.90))
	# the right-hand panel
	_rect(im, 76, 0, 44, 56, Color(0.13, 0.08, 0.24))
	_rect(im, 76, 0, 2, 56, MAG)
	_rect(im, 78, 0, 1, 56, CYAN)
	_rect(im, 80, 41, 40, 6, MAG)
	_rect(im, 80, 48, 40, 2, CYAN)
	return tex(im)


# ---------------------------------------------------------------- BLAST 16: a coupe heading down the highway into a striped sunset

static func _palm(im: Image, base: Vector2, lean: float, c: Color) -> void:
	var top := base + Vector2(lean, -26)
	_line(im, base, base.lerp(top, 0.5) + Vector2(lean * 0.3, 0), 2.0, c)
	_line(im, base.lerp(top, 0.5) + Vector2(lean * 0.3, 0), top, 1.6, c)
	for f in [Vector2(-11, 3), Vector2(-8, -4), Vector2(0, -6), Vector2(8, -4), Vector2(11, 4)]:
		_line(im, top, top + f, 1.6, c)


static func gen_label() -> ImageTexture:
	var im := _img(112, 60)
	_grad(im, 0, 38, Color(0.16, 0.08, 0.38), Color(0.92, 0.32, 0.55))
	_ellipse(im, 56, 37, 18, 18, Color(1.0, 0.82, 0.50))                        # the sun, sinking
	for sy in [28, 32, 35]:
		_rect(im, 38, sy, 36, 1 + (sy - 28) / 4, Color(0.92, 0.32, 0.55))       # its stripes
	_grad(im, 38, 60, Color(0.18, 0.08, 0.30), Color(0.08, 0.04, 0.16))        # the ground
	_rect(im, 0, 38, 112, 1, CYAN)                                               # horizon
	for gx in [-60, -30, 0, 30, 60]:                                              # a few lines running to the horizon
		_line(im, Vector2(56 + gx * 0.18, 39), Vector2(56 + gx * 1.4, 60), 1.0, Color(0.55, 0.20, 0.55))
	_poly(im, [Vector2(52, 38), Vector2(60, 38), Vector2(88, 60), Vector2(24, 60)], Color(0.10, 0.08, 0.14))   # the road
	for i in 3:                                                                    # centre dashes
		var y := 41 + i * 6
		_rect(im, 55, y, 2, 2 + i, Color(1.0, 0.85, 0.45))
	_palm(im, Vector2(14, 44), 4.0, Color(0.10, 0.04, 0.16))
	_palm(im, Vector2(99, 46), -5.0, Color(0.10, 0.04, 0.16))
	var car := Color(0.20, 0.10, 0.34)                                            # the car, from behind
	_poly(im, [Vector2(47, 45), Vector2(65, 45), Vector2(68, 49), Vector2(44, 49)], car)                        # roof and back window
	_poly(im, [Vector2(48, 46), Vector2(64, 46), Vector2(66, 48.5), Vector2(46, 48.5)], Color(0.45, 0.60, 0.85))   # rear glass
	_rect(im, 40, 49, 32, 6, Color(0.30, 0.12, 0.42))                            # body
	_rect(im, 40, 49, 32, 1, Color(0.70, 0.40, 0.80))
	_rect(im, 42, 51, 7, 2, Color(1.0, 0.25, 0.35))                              # tail lights
	_rect(im, 63, 51, 7, 2, Color(1.0, 0.25, 0.35))
	_rect(im, 50, 52, 12, 1, CYAN)
	_rect(im, 42, 55, 6, 3, Color(0.03, 0.02, 0.05))                             # tyres
	_rect(im, 64, 55, 6, 3, Color(0.03, 0.02, 0.05))
	return tex(im)


# the small grid below the Genesis label
static func gen_grid() -> ImageTexture:
	var im := _img(112, 40)
	im.fill(Color(0.05, 0.05, 0.065))
	for x in range(0, 112, 5):
		_rect(im, x, 0, 1, 40, Color(0.22, 0.22, 0.28))
	for y in range(0, 40, 5):
		_rect(im, 0, y, 112, 1, Color(0.22, 0.22, 0.28))
	return tex(im)


# ---------------------------------------------------------------- GameCube: an indigo cube floating over a dusk city

static func gc_label() -> ImageTexture:
	var im := _img(112, 64)
	_grad(im, 0, 40, Color(0.10, 0.07, 0.30), Color(0.62, 0.24, 0.62))
	_grad(im, 40, 64, Color(0.62, 0.24, 0.62), Color(0.98, 0.62, 0.52))
	_ellipse(im, 92, 13, 7, 7, Color(1.0, 0.92, 0.80))                          # moon
	_ellipse(im, 95, 11, 6, 6, Color(0.22, 0.12, 0.40))                         # (a crescent)
	var city := Color(0.14, 0.08, 0.26)                                          # skyline along the bottom
	for b in [[0, 50, 9], [9, 44, 7], [16, 53, 10], [26, 47, 8], [72, 46, 9], [81, 52, 8], [89, 42, 7], [96, 49, 16]]:
		_rect(im, b[0], b[1], b[2], 64 - b[1], city)
	_rect(im, 0, 63, 112, 1, MAG)
	# the cube, seen from above a corner: a light top face and two shaded sides
	var c := Vector2(49, 34)
	var s := 17.0
	var top := [c + Vector2(0, -s), c + Vector2(s * 0.87, -s * 0.5), c, c + Vector2(-s * 0.87, -s * 0.5)]
	var left := [c + Vector2(-s * 0.87, -s * 0.5), c, c + Vector2(0, s), c + Vector2(-s * 0.87, s * 0.5)]
	var right := [c, c + Vector2(s * 0.87, -s * 0.5), c + Vector2(s * 0.87, s * 0.5), c + Vector2(0, s)]
	_poly(im, top, Color(0.66, 0.58, 0.98))
	_poly(im, left, Color(0.36, 0.28, 0.72))
	_poly(im, right, Color(0.24, 0.17, 0.52))
	_line(im, top[0], top[1], 1.0, Color(0.86, 0.82, 1.0))                      # bright edges
	_line(im, top[0], top[3], 1.0, Color(0.86, 0.82, 1.0))
	_line(im, c, c + Vector2(0, s), 1.0, Color(0.50, 0.42, 0.90))
	_ellipse(im, c.x, c.y + s + 6, 14, 2.2, Color(0.30, 0.12, 0.38))            # its soft shadow on the haze
	_rect(im, 80, 30, 26, 2, CYAN)                                               # two speed lines on the right
	_rect(im, 86, 35, 20, 1, MAG)
	return tex(im)


# ---------------------------------------------------------------- Neo Geo: lofi stripes

static func neo_label() -> ImageTexture:
	var im := _img(116, 56)
	_grad(im, 0, 56, Color(0.22, 0.12, 0.42), Color(0.12, 0.07, 0.24))
	_rect(im, 0, 0, 116, 3, MAG)
	_rect(im, 0, 3, 116, 1, SUN)
	_rect(im, 0, 52, 116, 4, MAG)
	_ellipse(im, 24, 28, 14, 14, Color(1.0, 0.8, 0.6))                           # sun on the left
	for i in 5:
		_rect(im, 8, 28 + i * 3 + 1, 34, 1, Color(0.17, 0.09, 0.32))
	for i in 3:                                                                    # speed lines, bottom right
		_rect(im, 66 + i * 4, 45 + i * 2, 46 - i * 4, 1, CYAN if i % 2 == 0 else MAG)
	return tex(im)


# ---------------------------------------------------------------- the secret cart: gold label with a blue and green egg

static func egg_label() -> ImageTexture:
	var im := _img(56, 92)
	for yy in 92:
		for xx in 56:
			var d := Vector2(xx - 28, yy - 46).length() / 48.0
			im.set_pixel(xx, yy, Color(1.0, 0.86, 0.38).lerp(Color(0.80, 0.55, 0.12), clampf(d, 0.0, 1.0)))
	for sp in [Vector2(8, 12), Vector2(46, 18), Vector2(10, 72), Vector2(47, 76), Vector2(28, 8), Vector2(9, 44), Vector2(47, 46)]:
		_rect(im, int(sp.x) - 2, int(sp.y), 5, 1, Color(1, 0.97, 0.8))
		_rect(im, int(sp.x), int(sp.y) - 2, 1, 5, Color(1, 0.97, 0.8))
	var blue := Color(0.2, 0.45, 0.95)
	var green := Color(0.18, 0.78, 0.46)
	var outline := Color(0.30, 0.16, 0.08)
	var cy := 46.0
	_ellipse(im, 28, cy, 20, 28, outline)
	_ellipse(im, 28, cy, 18.5, 26.5, blue)
	for yy in range(int(cy - 28), int(cy + 28)):                                   # green zigzag bands, clipped to the egg
		for xx in range(8, 49):
			var dx := (xx + 0.5 - 28) / 18.5
			var dy := (yy + 0.5 - cy) / 26.5
			if dx * dx + dy * dy > 1.0:
				continue
			var z := absi((xx % 8) - 4)
			var band := int(floor((yy + z - (cy - 26.0)) / 10.0))
			if band % 2 == 1 and yy > cy - 21 and yy < cy + 21:
				im.set_pixel(xx, yy, green)
	for dp in [Vector2(28, cy - 17), Vector2(17, cy - 8), Vector2(39, cy - 8), Vector2(28, cy + 8), Vector2(17, cy + 17), Vector2(39, cy + 17)]:
		_rect(im, int(dp.x) - 1, int(dp.y) - 1, 3, 3, Color(1.0, 0.95, 0.8))
	_ellipse(im, 19, cy - 18, 3, 5, Color(1, 1, 1, 1).lerp(blue, 0.35))             # shine
	return tex(im)
