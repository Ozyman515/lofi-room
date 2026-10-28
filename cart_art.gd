extends RefCounted
## Painted cart labels. Each one is a small canvas drawn in code and shown with nearest filtering,
## so it keeps a chunky pixel look. The characters are original drawings.

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


# ---------------------------------------------------------------- NES: a jumping little guy over a dusk hill

static func nes_label() -> ImageTexture:
	var im := _img(56, 92)
	_grad(im, 0, 40, Color(0.26, 0.14, 0.48), Color(0.90, 0.30, 0.55))
	_grad(im, 40, 62, Color(0.90, 0.30, 0.55), Color(1.0, 0.72, 0.5))
	_ellipse(im, 40, 47, 9, 9, Color(1.0, 0.86, 0.6))                         # low sun
	for sx in [6, 17, 33, 47, 11, 26]:
		_px(im, sx, 3 + (sx * 7) % 14, Color(1, 0.95, 1))                      # stars
	_poly(im, [Vector2(0, 62), Vector2(10, 52), Vector2(22, 58), Vector2(34, 50), Vector2(56, 60), Vector2(56, 70), Vector2(0, 70)], Color(0.35, 0.17, 0.5))
	_rect(im, 0, 66, 56, 8, Color(0.52, 0.27, 0.38))                          # ground
	for gx in range(0, 56, 8):
		_rect(im, gx, 66, 4, 2, Color(0.66, 0.36, 0.40))
	_rect(im, 0, 74, 56, 18, Color(0.12, 0.07, 0.22))                          # title band
	_rect(im, 0, 74, 56, 1, Color(0.2, 0.8, 0.85))
	var skin := Color(1.0, 0.78, 0.6)
	var red := Color(0.88, 0.14, 0.16)
	var blue := Color(0.16, 0.30, 0.86)
	var yel := Color(1.0, 0.82, 0.25)
	var ink := Color(0.1, 0.08, 0.12)
	# a round-headed kid mid-jump: red cap, yellow top, blue overalls, white sneakers
	_line(im, Vector2(23, 46), Vector2(16, 34), 4.0, yel)                       # arms up
	_line(im, Vector2(33, 46), Vector2(40, 33), 4.0, yel)
	_ellipse(im, 15, 32, 2.8, 2.8, skin)
	_ellipse(im, 41, 31, 2.8, 2.8, skin)
	_line(im, Vector2(25, 54), Vector2(19, 60), 4.5, blue)                      # tucked legs
	_line(im, Vector2(31, 54), Vector2(37, 59), 4.5, blue)
	_ellipse(im, 17, 61, 4.5, 2.8, Color(0.97, 0.97, 1.0))
	_ellipse(im, 39, 60, 4.5, 2.8, Color(0.97, 0.97, 1.0))
	_rect(im, 13, 62, 9, 1, red)
	_rect(im, 35, 61, 9, 1, red)
	_ellipse(im, 28, 49, 7.5, 7.5, blue)                                         # overalls
	_rect(im, 21, 43, 14, 3, yel)                                                # shirt at the shoulders
	_rect(im, 23, 42, 2, 7, blue)
	_rect(im, 31, 42, 2, 7, blue)
	_rect(im, 23, 47, 2, 2, yel)                                                 # buttons
	_rect(im, 31, 47, 2, 2, yel)
	_rect(im, 26, 51, 4, 3, Color(0.88, 0.25, 0.55))                             # a pink patch
	_ellipse(im, 28, 36, 8, 7.5, skin)                                           # head
	_rect(im, 20, 35, 2, 4, Color(0.42, 0.22, 0.12))                             # side hair
	_rect(im, 34, 35, 2, 4, Color(0.42, 0.22, 0.12))
	_ellipse(im, 28, 31, 9, 5.5, red)                                            # cap
	_rect(im, 19, 32, 18, 3, red)
	_poly(im, [Vector2(21, 34), Vector2(40, 34), Vector2(42, 36), Vector2(21, 36)], Color(0.62, 0.08, 0.14))   # brim
	_rect(im, 26, 27, 4, 2, Color(0.97, 0.95, 0.9))                              # cap stripe
	_rect(im, 24, 37, 2, 3, ink)                                                 # eyes
	_rect(im, 31, 37, 2, 3, ink)
	_rect(im, 22, 40, 2, 1, Color(1.0, 0.55, 0.6))                               # cheeks
	_rect(im, 33, 40, 2, 1, Color(1.0, 0.55, 0.6))
	_rect(im, 26, 41, 4, 1, Color(0.6, 0.2, 0.25))                               # smile
	for cl in [Vector2(8, 16), Vector2(40, 8)]:                                  # clouds
		_ellipse(im, cl.x, cl.y, 6, 2.6, Color(1, 0.9, 0.95))
		_ellipse(im, cl.x + 4, cl.y - 2, 4, 3, Color(1, 0.9, 0.95))
	return tex(im)


# ---------------------------------------------------------------- SNES: a monkey with bananas in the jungle (left part), dark panel on the right

static func _banana(im: Image, a: Vector2, b: Vector2, bend: float) -> void:
	var yel := Color(1.0, 0.86, 0.22)
	var mid := (a + b) * 0.5
	var nrm := (b - a).orthogonal().normalized() * bend
	var c := mid + nrm
	var prev := a
	for i in range(1, 9):
		var t := i / 8.0
		var p := a.lerp(c, t).lerp(c.lerp(b, t), t)
		_line(im, prev, p, 3.0 if i < 8 else 2.0, yel)
		prev = p
	_px(im, int(b.x), int(b.y), Color(0.35, 0.22, 0.1))
	_px(im, int(a.x), int(a.y), Color(0.35, 0.22, 0.1))


static func snes_label() -> ImageTexture:
	var im := _img(120, 56)
	_grad(im, 0, 56, Color(0.10, 0.34, 0.42), Color(0.05, 0.14, 0.26))
	_ellipse(im, 20, 14, 8, 8, Color(0.95, 0.45, 0.62))                       # moon
	var leaf := Color(0.12, 0.52, 0.40)
	var leaf2 := Color(0.08, 0.38, 0.34)
	_poly(im, [Vector2(0, 0), Vector2(26, 0), Vector2(14, 10), Vector2(0, 22)], leaf2)
	_poly(im, [Vector2(0, 0), Vector2(14, 0), Vector2(6, 12), Vector2(0, 14)], leaf)
	_poly(im, [Vector2(76, 0), Vector2(52, 0), Vector2(64, 10), Vector2(76, 20)], leaf2)
	_poly(im, [Vector2(76, 0), Vector2(62, 0), Vector2(70, 12), Vector2(76, 14)], leaf)
	_poly(im, [Vector2(0, 56), Vector2(0, 42), Vector2(14, 48), Vector2(28, 56)], leaf)
	_poly(im, [Vector2(76, 56), Vector2(76, 44), Vector2(62, 50), Vector2(50, 56)], leaf)
	_rect(im, 0, 50, 76, 6, Color(0.30, 0.20, 0.22))                          # branch
	# the monkey
	var fur := Color(0.58, 0.34, 0.20)
	var fur2 := Color(0.42, 0.24, 0.15)
	var face := Color(0.98, 0.80, 0.62)
	_line(im, Vector2(46, 46), Vector2(34, 40), 3.0, fur)                    # tail curl
	_line(im, Vector2(34, 40), Vector2(30, 32), 3.0, fur)
	_ellipse(im, 40, 41, 11, 11, fur)                                          # body
	_ellipse(im, 40, 43, 6, 7, face)                                           # belly
	_line(im, Vector2(31, 36), Vector2(24, 44), 4.0, fur)                    # left arm down
	_line(im, Vector2(49, 34), Vector2(56, 22), 4.0, fur)                    # right arm up
	_ellipse(im, 56, 21, 3, 3, fur2)
	_ellipse(im, 42, 20, 10, 9, fur)                                           # head
	_ellipse(im, 33, 18, 4.5, 4.5, fur)                                        # ears
	_ellipse(im, 51, 18, 4.5, 4.5, fur)
	_ellipse(im, 33, 18, 2.5, 2.5, face)
	_ellipse(im, 51, 18, 2.5, 2.5, face)
	_ellipse(im, 42, 23, 7, 5, face)                                           # muzzle
	_ellipse(im, 42, 17, 6, 3, face)                                           # brow patch
	_rect(im, 37, 16, 2, 3, Color(0.1, 0.08, 0.1))                             # eyes
	_rect(im, 46, 16, 2, 3, Color(0.1, 0.08, 0.1))
	_rect(im, 40, 22, 1, 1, fur2)
	_rect(im, 43, 22, 1, 1, fur2)
	_rect(im, 38, 25, 8, 1, Color(0.6, 0.25, 0.3))                             # grin
	_banana(im, Vector2(56, 24), Vector2(62, 8), 4.0)                         # banana held up
	_banana(im, Vector2(66, 40), Vector2(70, 26), -4.0)                       # a bunch on the branch
	_banana(im, Vector2(62, 42), Vector2(66, 28), -3.0)
	_banana(im, Vector2(22, 46), Vector2(14, 36), 3.0)
	# the right-hand panel
	_rect(im, 76, 0, 44, 56, Color(0.13, 0.08, 0.24))
	_rect(im, 76, 0, 2, 56, MAG)
	_rect(im, 78, 0, 1, 56, CYAN)
	_rect(im, 80, 41, 40, 6, MAG)
	_rect(im, 80, 48, 40, 2, CYAN)
	return tex(im)


# ---------------------------------------------------------------- Genesis style: a blue hedgehog on a sunset

static func gen_label() -> ImageTexture:
	var im := _img(112, 60)
	_grad(im, 0, 36, Color(0.20, 0.10, 0.42), Color(0.88, 0.28, 0.56))
	_grad(im, 36, 60, Color(0.88, 0.28, 0.56), Color(1.0, 0.74, 0.5))
	_ellipse(im, 24, 40, 14, 14, Color(1.0, 0.88, 0.62))                      # sun
	for sy in [36, 40, 44]:
		_rect(im, 8, sy, 34, 1, Color(0.88, 0.28, 0.56))                      # sun stripes
	_rect(im, 0, 50, 112, 10, Color(0.14, 0.62, 0.72))                        # grass band
	for gx in range(0, 112, 12):
		_rect(im, gx, 50, 6, 10, Color(0.10, 0.52, 0.64))
	_rect(im, 0, 50, 112, 1, Color(0.8, 0.95, 0.9))
	var blue := Color(0.20, 0.38, 0.95)
	var dk := Color(0.12, 0.22, 0.72)
	var cream := Color(0.99, 0.88, 0.74)
	var ink := Color(0.1, 0.08, 0.12)
	# a chubby blue hedgehog hopping with a trailing yellow scarf
	_poly(im, [Vector2(40, 22), Vector2(34, 8), Vector2(47, 16)], dk)           # a crown of spines
	_poly(im, [Vector2(46, 17), Vector2(46, 3), Vector2(57, 13)], blue)
	_poly(im, [Vector2(55, 13), Vector2(60, 1), Vector2(68, 13)], dk)
	_poly(im, [Vector2(65, 14), Vector2(74, 3), Vector2(77, 16)], blue)
	_poly(im, [Vector2(36, 30), Vector2(26, 22), Vector2(40, 20)], blue)
	_ellipse(im, 56, 31, 16, 15, blue)                                           # round body
	_ellipse(im, 58, 40, 9, 8, cream)                                            # tummy
	_ellipse(im, 70, 26, 4, 4, blue)                                             # ears
	_ellipse(im, 46, 24, 4, 4, blue)
	_ellipse(im, 62, 28, 11, 9, cream)                                           # face
	_ellipse(im, 56, 25, 4.2, 5, Color(1, 1, 1))                                 # big eyes
	_ellipse(im, 66, 25, 4.2, 5, Color(1, 1, 1))
	_ellipse(im, 57, 26, 2.2, 3, ink)
	_ellipse(im, 67, 26, 2.2, 3, ink)
	_rect(im, 56, 24, 1, 1, Color(1, 1, 1))
	_rect(im, 66, 24, 1, 1, Color(1, 1, 1))
	_ellipse(im, 61, 31, 2, 1.6, ink)                                            # nose
	_ellipse(im, 52, 32, 2.5, 1.6, Color(1.0, 0.55, 0.6))                        # cheeks
	_ellipse(im, 71, 32, 2.5, 1.6, Color(1.0, 0.55, 0.6))
	_rect(im, 59, 34, 5, 1, Color(0.6, 0.2, 0.25))                               # smile
	_line(im, Vector2(46, 41), Vector2(38, 33), 4.0, blue)                      # arms up
	_line(im, Vector2(68, 40), Vector2(76, 31), 4.0, blue)
	_ellipse(im, 37, 32, 2.5, 2.5, cream)
	_ellipse(im, 77, 30, 2.5, 2.5, cream)
	_line(im, Vector2(50, 44), Vector2(46, 51), 4.5, blue)                      # tucked feet
	_line(im, Vector2(64, 44), Vector2(68, 51), 4.5, blue)
	_ellipse(im, 44, 52, 5, 2.8, Color(1.0, 0.62, 0.2))
	_ellipse(im, 70, 52, 5, 2.8, Color(1.0, 0.62, 0.2))
	var scarf := Color(1.0, 0.86, 0.25)                                          # scarf flying off to the left
	_line(im, Vector2(50, 36), Vector2(64, 36), 3.0, scarf)
	_poly(im, [Vector2(50, 35), Vector2(36, 38), Vector2(40, 44), Vector2(52, 39)], scarf)
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
