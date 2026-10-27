extends Node
## The disc console: a slim dark machine with a slot in its front, next to the cartridge console and on the same TV
## (emu.gd's "ps" system: the PlayStation core). Its "cart" is a tall long-box case lying with the other carts.
## Inserting: the case flies over in front of the console, lies down and opens, the disc lifts off the hub and slides
## into the slot; the empty case shuts and goes home. Ejecting is the same backwards. Our own designs: no logos.

const CASE_W := 0.152            # the long box: width, height (its long side), thickness
const CASE_H := 0.27
const CASE_T := 0.024
const DISC_R := 0.06
const CON_W := 0.3               # the disc console: width, depth, height
const CON_D := 0.24
const CON_H := 0.062
const SLOT_Y := 0.038            # the slot's height on its front
const CON_AT := Vector3(0.44, 0.0, 0.0)       # where it stands, in the cartridge console's frame (beside it, same way round)

var main: Node3D
var console: Node3D
var case_node: Node3D
var lid: Node3D
var disc: Node3D
var _hub := Vector3.ZERO          # where the disc sits in the case (case space)
var _led: StandardMaterial3D
var _slot_glow: StandardMaterial3D


func build(m: Node3D) -> void:
	main = m
	_build_console()
	_build_case()


func _mat(c: Color, rough := 0.6, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = rough
	mt.metallic = metal
	if emit > 0.0:
		mt.emission_enabled = true
		mt.emission = c
		mt.emission_energy_multiplier = emit
	return mt


func _box(parent: Node3D, pos: Vector3, size: Vector3, mt: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mt
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, pos: Vector3, r: float, h: float, mt: Material, segs := 32) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mt
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---- the console: local +z is its front (the same way round as the cartridge console)

func _build_console() -> void:
	console = Node3D.new()
	console.name = "DiscConsole"
	main.console_root.get_parent().add_child(console)
	console.transform = main.console_root.transform * Transform3D(Basis.IDENTITY, CON_AT)
	var body := _mat(Color(0.1, 0.1, 0.115), 0.45, 0.2)
	var top := _mat(Color(0.14, 0.14, 0.16), 0.4, 0.2)
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.5)
	var fz := CON_D / 2.0
	_box(console, Vector3(0, 0.004, 0), Vector3(CON_W - 0.02, 0.008, CON_D - 0.02), dark)           # feet plinth
	_box(console, Vector3(0, 0.008 + (CON_H - 0.008) / 2.0, 0), Vector3(CON_W, CON_H - 0.008, CON_D), body)
	_box(console, Vector3(0, CON_H + 0.002, -0.01), Vector3(CON_W - 0.03, 0.004, CON_D - 0.05), top)    # a raised top panel
	# the front: the disc slot across the middle with a soft glow along it, a power button and a reset button
	_box(console, Vector3(-0.02, SLOT_Y, fz + 0.0005), Vector3(0.15, 0.007, 0.002), dark)
	_slot_glow = _mat(Color(0.25, 0.55, 1.0), 0.3, 0.0, 0.6)
	_box(console, Vector3(-0.02, SLOT_Y + 0.009, fz + 0.0008), Vector3(0.15, 0.0015, 0.001), _slot_glow)
	var btn := _cyl(console, Vector3(0.105, SLOT_Y, fz + 0.002), 0.011, 0.006, _mat(Color(0.32, 0.32, 0.36), 0.35))
	btn.rotation.x = PI / 2.0
	var rst := _cyl(console, Vector3(0.105, SLOT_Y - 0.02, fz + 0.0015), 0.006, 0.004, _mat(Color(0.32, 0.32, 0.36), 0.35))
	rst.rotation.x = PI / 2.0
	_led = _mat(Color(0.2, 1.0, 0.45), 0.3, 0.0, 0.0)
	_box(console, Vector3(0.105, SLOT_Y + 0.019, fz + 0.0006), Vector3(0.008, 0.003, 0.001), _led)
	# two controller ports low on the front
	for sx in [-0.09, -0.045]:
		_box(console, Vector3(sx, 0.017, fz + 0.0006), Vector3(0.03, 0.01, 0.001), dark)
	main.interactables.append({"node": btn, "half": Vector3(0.02, 0.02, 0.02), "egg_lock": true, "group": "games",
		"label": func() -> String: return "DISC CONSOLE POWER  [%s]" % ("ON" if main.console_on else "OFF"),
		"cb": func() -> void: main.toggle_console()})


func set_power_light(on: bool) -> void:
	if _led != null:
		_led.emission_enabled = on
		_led.emission_energy_multiplier = 2.0 if on else 0.0
		_led.albedo_color = Color(0.2, 1.0, 0.45) if on else Color(0.08, 0.12, 0.09)


# ---- the long-box case: built standing up, its front (+z) facing out, hinged on its left long edge; the disc on
# a hub in the lower half of the tray

func _build_case() -> void:
	case_node = Node3D.new()
	case_node.name = "LongBox"
	var tray := _mat(Color(0.04, 0.04, 0.05), 0.4)
	var clear := StandardMaterial3D.new()
	clear.albedo_color = Color(0.85, 0.9, 1.0, 0.18)
	clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear.roughness = 0.08
	clear.metallic_specular = 0.9
	var hw := CASE_W / 2.0
	var hh := CASE_H / 2.0
	_box(case_node, Vector3(0, 0, -CASE_T / 2.0 + 0.002), Vector3(CASE_W, CASE_H, 0.004), tray)                # the back
	for sx in [-1.0, 1.0]:
		_box(case_node, Vector3(sx * (hw - 0.002), 0, -0.002), Vector3(0.004, CASE_H, CASE_T - 0.008), tray)    # the sides
	for sy in [-1.0, 1.0]:
		_box(case_node, Vector3(0, sy * (hh - 0.002), -0.002), Vector3(CASE_W, 0.004, CASE_T - 0.008), tray)
	_box(case_node, Vector3(0, 0, -CASE_T / 2.0 + 0.0045), Vector3(CASE_W - 0.01, CASE_H - 0.01, 0.001), _mat(Color(0.1, 0.1, 0.12), 0.6))   # the inner tray
	_hub = Vector3(0, -hh + 0.012 + DISC_R, -CASE_T / 2.0 + 0.006)
	var hub := _cyl(case_node, _hub, 0.012, 0.004, tray, 16)
	hub.rotation.x = PI / 2.0
	# the lid: hinged on the left edge, a clear front over the cover art
	lid = Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(-hw, 0, CASE_T / 2.0 - 0.002)
	case_node.add_child(lid)
	var art := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(CASE_W - 0.008, CASE_H - 0.008)
	art.mesh = q
	var am := StandardMaterial3D.new()
	am.albedo_texture = _cover_art()
	am.roughness = 0.6
	art.material_override = am
	art.position = Vector3(hw, 0, -0.0012)
	lid.add_child(art)
	_box(lid, Vector3(hw, 0, 0.0), Vector3(CASE_W, CASE_H, 0.0016), clear)
	# the disc: black underneath (the data side), a printed label on top
	disc = Node3D.new()
	disc.name = "Disc"
	disc.position = _hub + Vector3(0, 0, 0.004)
	disc.rotation.x = PI / 2.0                       # (flat against the tray: its axis along the case's z)
	case_node.add_child(disc)
	_cyl(disc, Vector3(0, -0.0003, 0), DISC_R, 0.0006, _mat(Color(0.03, 0.03, 0.035), 0.15, 0.6), 48)
	var label := _cyl(disc, Vector3(0, 0.0003, 0), DISC_R - 0.001, 0.0006, null, 48)
	var lm := StandardMaterial3D.new()
	lm.albedo_texture = _disc_art()
	lm.roughness = 0.4
	lm.uv1_triplanar = true
	lm.uv1_scale = Vector3(1.0 / (DISC_R * 2.0), 1.0 / (DISC_R * 2.0), 1.0 / (DISC_R * 2.0))
	lm.uv1_offset = Vector3(0.5, 0.5, 0.5)
	label.material_override = lm
	_cyl(disc, Vector3(0, 0.0, 0), 0.0075, 0.0016, _mat(Color(0.02, 0.02, 0.025), 0.5), 20)                 # the centre hole
	case_node.set_meta("half", Vector3(hw, hh, CASE_T / 2.0 + 0.005))


# a cover of our own: a black band down the left edge, a sunset over a grid, "DISC" in big letters
func _cover_art() -> Texture2D:
	var w := 152
	var h := 270
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / h
		var col := Color(0.95, 0.45, 0.35).lerp(Color(0.35, 0.12, 0.45), t)
		for x in w:
			img.set_pixel(x, y, col)
	var cx := w * 0.58
	var cy := h * 0.45
	for y in h:                                      # the sun
		for x in w:
			var d := Vector2(x - cx, y - cy).length()
			if d < 38.0 and (y < cy or int(y - cy) % 9 > 3):
				img.set_pixel(x, y, Color(1.0, 0.85, 0.35))
	for y in range(int(h * 0.62), h):                # the grid
		for x in w:
			if int(x - cx) % 16 == 0 or int(y - h * 0.62) % 12 == 0:
				img.set_pixel(x, y, Color(0.4, 0.9, 1.0))
	for y in h:                                      # the band down the left
		for x in 18:
			img.set_pixel(x, y, Color(0.05, 0.05, 0.06))
	return ImageTexture.create_from_image(img)


func _disc_art() -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length() / (s / 2.0)
			var col := Color(0.92, 0.92, 0.95)
			if d < 0.32:
				col = Color(0.75, 0.75, 0.8)
			elif d < 0.62:
				col = Color(0.35, 0.12, 0.45).lerp(Color(0.95, 0.45, 0.35), (float(y) / s))
			elif d > 0.97:
				col = Color(0.6, 0.6, 0.65)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# ---- putting the disc in and taking it out

func _console_xf(local: Transform3D) -> Transform3D:
	return console.global_transform * local


# where the case lies open in front of the console: face up, its long side across, the disc just in front of the slot
func _stage_xf() -> Transform3D:
	var lay := Basis(Vector3.RIGHT, -PI / 2.0)                       # front up
	var b := lay.rotated(Vector3.UP, 0.0) * Basis(Vector3.BACK, -PI / 2.0)     # long side across the console
	return _console_xf(Transform3D(Basis(Vector3.UP, 0.0) * b, Vector3(0.25, 0.003 + CASE_T / 2.0, CON_D / 2.0 + 0.2)))


# (for keeping the carts out of the way)
func stage_point() -> Vector3:
	return _stage_xf().origin


func _slot_point(depth: float) -> Vector3:
	return _console_xf(Transform3D(Basis.IDENTITY, Vector3(-0.02, SLOT_Y, CON_D / 2.0 + depth))).origin


func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


# fly a node (global) to a transform along a little arc
func _fly(tw: Tween, n: Node3D, to: Callable, secs: float, arc := 0.1) -> void:
	var st := {}
	tw.tween_callback(func() -> void: st["from"] = n.global_transform)
	tw.tween_method(func(k: float) -> void:
		var e := _ease(k)
		var f: Transform3D = st["from"]
		var t: Transform3D = to.call()
		var q := f.basis.get_rotation_quaternion().slerp(t.basis.get_rotation_quaternion(), e)
		n.global_transform = Transform3D(Basis(q), f.origin.lerp(t.origin, e) + Vector3(0, sin(e * PI) * arc, 0)), 0.0, 1.0, secs)


func _lid(tw: Tween, open: bool, secs := 0.45) -> void:
	tw.tween_property(lid, "rotation:y", -PI * 0.97 if open else 0.0, secs).set_trans(Tween.TRANS_SINE)


func insert(home_done: Callable) -> void:
	var c: Dictionary = main.carts["ps"]
	c["busy"] = true
	var tw := create_tween()
	_fly(tw, case_node, _stage_xf, 0.6, 0.14)
	_lid(tw, true)
	# the disc lifts off the hub, comes round to the slot and slides in
	tw.tween_callback(func() -> void: disc.reparent(console.get_parent(), true))
	var up := {}
	tw.tween_callback(func() -> void: up["p"] = disc.global_position + Vector3(0, 0.05, 0))
	tw.tween_method(func(k: float) -> void: disc.global_position = disc.global_position.lerp(up["p"], k), 0.0, 1.0, 0.3)
	_fly(tw, disc, func() -> Transform3D: return Transform3D(console.global_transform.basis, _slot_point(0.03)), 0.5, 0.03)
	tw.tween_method(func(k: float) -> void: disc.global_position = _slot_point(lerpf(0.03, -0.1, _ease(k))), 0.0, 1.0, 0.45)
	tw.tween_callback(func() -> void:
		disc.visible = false
		_slot_glow.emission_energy_multiplier = 1.6)
	_lid(tw, false)
	tw.tween_callback(func() -> void: c["busy"] = false)
	tw.tween_callback(home_done)


func eject(home: Callable) -> void:
	var c: Dictionary = main.carts["ps"]
	c["busy"] = true
	var tw := create_tween()
	_fly(tw, case_node, _stage_xf, 0.6, 0.14)
	_lid(tw, true)
	tw.tween_callback(func() -> void:
		disc.visible = true
		disc.global_transform = Transform3D(console.global_transform.basis, _slot_point(-0.1)))
	tw.tween_method(func(k: float) -> void: disc.global_position = _slot_point(lerpf(-0.1, 0.03, _ease(k))), 0.0, 1.0, 0.45)
	tw.tween_callback(func() -> void: _slot_glow.emission_energy_multiplier = 0.6)
	# back onto the hub in the open case
	_fly(tw, disc, func() -> Transform3D: return case_node.global_transform * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), _hub + Vector3(0, 0, 0.004)), 0.55, 0.06)
	tw.tween_callback(func() -> void: disc.reparent(case_node, true))
	_lid(tw, false)
	_fly(tw, case_node, home, 0.55, 0.14)
	tw.tween_callback(func() -> void: c["busy"] = false)
