extends RefCounted
## Props for Noir Night (noir.gd), built from primitives:
##  - the still life: a revolver lying on its side, one cartridge standing beside it, a tumbler of whiskey
##    half drunk (one ice cube) and a lit cigarette in a glass ashtray with a thin curl of smoke (about 40 x 30 cm)
##  - a detective's things: a fedora, an open case file with a photo clipped to it, a badge
##  - a typewriter with a sheet of paper in it (its text is a Label3D the caller fills in)
## Everything sits on y = 0 in its own frame.

static func build(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	var gun := _revolver()
	root.add_child(gun)
	gun.position = Vector3(-0.06, 0.0115, 0.05)
	gun.rotation = Vector3(-PI / 2.0, 0.42, 0.0)     # on its left side, muzzle angled away
	root.add_child(_cartridge(Vector3(0.075, 0.0, 0.125)))
	var glass := _tumbler(Vector3(0.12, 0.0, -0.06))
	glass.name = "Tumbler"
	root.add_child(glass)
	var tray := _ashtray(Vector3(-0.15, 0.0, -0.09))
	root.add_child(tray)
	return root


# ---- materials

static func _m(col: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.disable_fog = true
	return m


static func _glass(tint: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic_specular = 0.9
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	return m


static func _part(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if parent != null:
		parent.add_child(mi)
	return mi


static func _cyl(r_top: float, r_bot: float, h: float, segs := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


# ---- the revolver (modelled upright: barrel along +x, top along +y, then laid down by the caller)

static func _revolver() -> Node3D:
	var g := Node3D.new()
	var steel := _m(Color(0.10, 0.11, 0.13), 0.32, 0.9)
	var steel_hi := _m(Color(0.20, 0.21, 0.24), 0.25, 0.95)
	var hole := _m(Color(0.01, 0.01, 0.012), 0.9)
	var wood := _m(Color(0.17, 0.075, 0.035), 0.45)
	var wood_dk := _m(Color(0.07, 0.03, 0.015), 0.7)
	var side := Vector3(0, 0, PI / 2.0)                # cylinders lie along x
	# barrel, with the ejector housing underneath and a front sight
	_part(_cyl(0.0085, 0.0095, 0.105), steel, Vector3(0.085, 0.034, 0), side, g)
	_part(_cyl(0.0105, 0.0105, 0.006), steel_hi, Vector3(0.1385, 0.034, 0), side, g)    # muzzle crown
	_part(_cyl(0.0045, 0.0045, 0.008), hole, Vector3(0.139, 0.034, 0), side, g)        # bore
	_part(_box(Vector3(0.07, 0.009, 0.010)), steel, Vector3(0.07, 0.022, 0), Vector3.ZERO, g)
	_part(_box(Vector3(0.010, 0.008, 0.004)), steel, Vector3(0.13, 0.045, 0), Vector3.ZERO, g)
	_part(_box(Vector3(0.10, 0.003, 0.006)), steel_hi, Vector3(0.085, 0.0435, 0), Vector3.ZERO, g)   # top rib
	# the frame around the cylinder, the top strap, the rear sight notch
	_part(_box(Vector3(0.066, 0.016, 0.020)), steel, Vector3(0.0, 0.006, 0), Vector3.ZERO, g)
	_part(_box(Vector3(0.062, 0.008, 0.016)), steel, Vector3(0.0, 0.053, 0), Vector3.ZERO, g)
	_part(_box(Vector3(0.012, 0.050, 0.020)), steel, Vector3(0.028, 0.03, 0), Vector3.ZERO, g)
	_part(_box(Vector3(0.016, 0.054, 0.022)), steel, Vector3(-0.032, 0.026, 0), Vector3.ZERO, g)
	# the cylinder: six chambers, flutes between them
	var cyl := Node3D.new()
	cyl.position = Vector3(0.0, 0.03, 0)
	g.add_child(cyl)
	_part(_cyl(0.0205, 0.0205, 0.040, 30), steel_hi, Vector3.ZERO, side, cyl)
	for i in 6:
		var a := TAU * i / 6.0
		var off := Vector3(0, cos(a), sin(a)) * 0.0125
		_part(_cyl(0.0042, 0.0042, 0.002, 12), hole, off + Vector3(0.0201, 0, 0), side, cyl)
		var fa := a + TAU / 12.0
		var fl := _part(_box(Vector3(0.026, 0.0045, 0.0028)), steel, Vector3(0, cos(fa), sin(fa)) * 0.0196, Vector3(fa, 0, 0), cyl)
		fl.rotation = Vector3(-fa, 0, 0)
	# hammer
	_part(_box(Vector3(0.012, 0.022, 0.008)), steel, Vector3(-0.045, 0.052, 0), Vector3(0, 0, 0.5), g)
	_part(_box(Vector3(0.014, 0.004, 0.009)), steel_hi, Vector3(-0.054, 0.062, 0), Vector3(0, 0, 0.2), g)
	# trigger guard + trigger
	var guard := TorusMesh.new()
	guard.inner_radius = 0.0125
	guard.outer_radius = 0.0155
	guard.rings = 24
	guard.ring_segments = 8
	_part(guard, steel, Vector3(-0.006, -0.010, 0), Vector3(PI / 2.0, 0, 0), g)
	_part(_box(Vector3(0.004, 0.017, 0.005)), steel_hi, Vector3(-0.004, -0.006, 0), Vector3(0, 0, -0.25), g)
	# grip: wooden panels on a steel frame, raked back
	var grip := Node3D.new()
	grip.position = Vector3(-0.034, 0.004, 0)
	grip.rotation = Vector3(0, 0, -0.38)          # raked back under the hammer
	g.add_child(grip)
	_part(_box(Vector3(0.026, 0.068, 0.016)), steel, Vector3(0, -0.03, 0), Vector3.ZERO, grip)
	for sz in [-1.0, 1.0]:
		_part(_box(Vector3(0.027, 0.062, 0.004)), wood, Vector3(-0.001, -0.031, sz * 0.0095), Vector3.ZERO, grip)
		# chequering: a few dark grooves
		for k in 6:
			_part(_box(Vector3(0.023, 0.0012, 0.0005)), wood_dk, Vector3(-0.001, -0.053 + k * 0.0075, sz * 0.0118), Vector3.ZERO, grip)
		_part(_cyl(0.0035, 0.0035, 0.001, 12), steel_hi, Vector3(0, -0.03, sz * 0.0119), Vector3(PI / 2.0, 0, 0), grip)   # grip screw
	_part(_box(Vector3(0.028, 0.006, 0.018)), steel, Vector3(0, -0.064, 0), Vector3.ZERO, grip)
	return g


# ---- one cartridge, standing on its base

static func _cartridge(pos: Vector3) -> Node3D:
	var c := Node3D.new()
	c.position = pos
	var brass := _m(Color(0.95, 0.74, 0.30), 0.2, 1.0)
	var lead := _m(Color(0.62, 0.42, 0.30), 0.3, 0.9)
	_part(_cyl(0.0058, 0.0062, 0.0012), brass, Vector3(0, 0.0006, 0), Vector3.ZERO, c)       # rim
	_part(_cyl(0.0057, 0.0057, 0.030), brass, Vector3(0, 0.0162, 0), Vector3.ZERO, c)
	_part(_cyl(0.0042, 0.0055, 0.008), lead, Vector3(0, 0.0352, 0), Vector3.ZERO, c)
	var tip := SphereMesh.new()
	tip.radius = 0.0042
	tip.height = 0.0075
	_part(tip, lead, Vector3(0, 0.0393, 0), Vector3.ZERO, c)
	return c


# ---- a heavy tumbler, half full, one ice cube

static func _tumbler(pos: Vector3) -> Node3D:
	var t := Node3D.new()
	t.position = pos
	var glass := _glass(Color(0.85, 0.9, 0.95), 0.09)
	var base := _glass(Color(0.85, 0.9, 0.95), 0.35)
	_part(_cyl(0.043, 0.038, 0.098, 40), glass, Vector3(0, 0.049, 0), Vector3.ZERO, t)
	_part(_cyl(0.0378, 0.0378, 0.014, 40), base, Vector3(0, 0.007, 0), Vector3.ZERO, t)
	var whisky := StandardMaterial3D.new()
	whisky.albedo_color = Color(0.55, 0.22, 0.03, 0.82)
	whisky.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	whisky.roughness = 0.05
	whisky.emission_enabled = true
	whisky.emission = Color(0.6, 0.22, 0.02)
	whisky.emission_energy_multiplier = 0.12
	whisky.disable_fog = true
	_part(_cyl(0.0392, 0.0372, 0.034, 40), whisky, Vector3(0, 0.031, 0), Vector3.ZERO, t).name = "Whisky"
	var surface := _glass(Color(0.95, 0.62, 0.25), 0.55)
	_part(_cyl(0.0392, 0.0392, 0.0004, 40), surface, Vector3(0, 0.0482, 0), Vector3.ZERO, t).name = "Surface"
	var ice := _glass(Color(0.92, 0.96, 1.0), 0.45)
	_part(_box(Vector3(0.026, 0.024, 0.026)), ice, Vector3(0.006, 0.047, -0.004), Vector3(0.25, 0.6, 0.15), t).name = "Ice"
	return t


# ---- glass ashtray with a cigarette burning on its rest

static func _ashtray(pos: Vector3) -> Node3D:
	var a := Node3D.new()
	a.position = pos
	var tray := _glass(Color(0.55, 0.62, 0.7), 0.42)
	_part(_cyl(0.055, 0.052, 0.022, 40), tray, Vector3(0, 0.011, 0), Vector3.ZERO, a)
	_part(_cyl(0.040, 0.036, 0.004, 40), _m(Color(0.25, 0.24, 0.24), 0.95), Vector3(0, 0.012, 0), Vector3.ZERO, a)   # ash in the bowl
	_part(_box(Vector3(0.012, 0.006, 0.02)), _m(Color(0.04, 0.04, 0.05), 0.4), Vector3(0.05, 0.021, 0), Vector3.ZERO, a)  # the rest notch
	# the cigarette rests in the notch, burning end out over the table
	var cig := Node3D.new()
	cig.position = Vector3(0.05, 0.024, 0.0)
	cig.rotation = Vector3(0, 0.0, -0.10)
	a.add_child(cig)
	var side := Vector3(0, 0, PI / 2.0)
	var paper := _m(Color(0.95, 0.94, 0.9), 0.8)
	var filt := _m(Color(0.86, 0.56, 0.28), 0.75)
	var ash := _m(Color(0.45, 0.44, 0.42), 1.0)
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color(1.0, 0.35, 0.05)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.3, 0.04)
	ember.emission_energy_multiplier = 6.0
	_part(_cyl(0.0039, 0.0039, 0.024), filt, Vector3(-0.022, 0, 0), side, cig)
	_part(_cyl(0.0039, 0.0039, 0.046), paper, Vector3(0.013, 0, 0), side, cig)
	_part(_cyl(0.0040, 0.0040, 0.005), ember, Vector3(0.0385, 0, 0), side, cig)
	_part(_cyl(0.0034, 0.0039, 0.010), ash, Vector3(0.046, 0, 0), side, cig)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.light_energy = 0.25
	glow.omni_range = 0.12
	glow.position = Vector3(0.04, 0.008, 0)
	cig.add_child(glow)
	# smoke: a thin rising curl of soft puffs
	var puff_tex := _puff_texture()
	var tip := Vector3(0.09, 0.03, 0.0)
	for i in 34:
		var f := i / 33.0
		var q := QuadMesh.new()
		var sz := 0.008 + f * 0.05
		q.size = Vector2(sz, sz * 1.6)
		var pm := StandardMaterial3D.new()
		pm.albedo_texture = puff_tex
		pm.albedo_color = Color(0.85, 0.85, 0.9, 0.22 * (1.0 - f * 0.85))
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		pm.disable_fog = true
		var p := tip + Vector3(sin(f * 7.0) * 0.012 * (0.4 + f) + f * 0.02, f * 0.30, cos(f * 5.0) * 0.010 * f)
		_part(q, pm, p, Vector3.ZERO, a)
	return a


static func _puff_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0, y - n / 2.0).length() / (n / 2.0)
			var al := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, al * al))
	return ImageTexture.create_from_image(img)


# ---- the detective's things

static func fedora() -> Node3D:
	var f := Node3D.new()
	var felt := _m(Color(0.16, 0.14, 0.12), 0.85)
	var band := _m(Color(0.05, 0.04, 0.04), 0.6)
	var brim := _cyl(0.17, 0.17, 0.006, 40)
	var b := _part(brim, felt, Vector3(0, 0.003, 0), Vector3.ZERO, f)
	b.scale = Vector3(1.0, 1.0, 0.88)
	var crown := _cyl(0.072, 0.088, 0.11, 32)
	var c := _part(crown, felt, Vector3(0, 0.06, 0), Vector3.ZERO, f)
	c.scale = Vector3(1.0, 1.0, 0.82)
	var dent := SphereMesh.new()                 # the pinch along the top
	dent.radius = 0.06
	dent.height = 0.03
	var d := _part(dent, _m(Color(0.10, 0.09, 0.08), 0.9), Vector3(0, 0.113, 0), Vector3.ZERO, f)
	d.scale = Vector3(0.5, 0.35, 1.0)
	var bd := _part(_cyl(0.089, 0.089, 0.022, 32), band, Vector3(0, 0.017, 0), Vector3.ZERO, f)
	bd.scale = Vector3(1.0, 1.0, 0.82)
	return f


static func case_file() -> Node3D:
	var f := Node3D.new()
	var manila := _m(Color(0.80, 0.66, 0.40), 0.9)
	var paper := _m(Color(0.93, 0.91, 0.84), 0.9)
	var ink := _m(Color(0.15, 0.14, 0.16), 0.9)
	_part(_box(Vector3(0.23, 0.003, 0.30)), manila, Vector3(-0.118, 0.0015, 0), Vector3(0, 0, 0.02), f)   # open: left cover
	_part(_box(Vector3(0.23, 0.003, 0.30)), manila, Vector3(0.118, 0.0015, 0), Vector3.ZERO, f)          # right cover
	_part(_box(Vector3(0.05, 0.003, 0.02)), manila, Vector3(0.21, 0.0015, -0.16), Vector3.ZERO, f)       # the tab
	_part(_box(Vector3(0.20, 0.0012, 0.27)), paper, Vector3(0.12, 0.0035, 0.005), Vector3(0, 0.03, 0), f)
	for k in 9:                                  # typed lines
		_part(_box(Vector3(0.15 - (k % 3) * 0.02, 0.0004, 0.004)), ink, Vector3(0.11, 0.0043, -0.07 + k * 0.018), Vector3.ZERO, f)
	var photo := _m(Color(0.30, 0.30, 0.32), 0.6)       # a grainy black-and-white photo, clipped on
	_part(_box(Vector3(0.09, 0.0015, 0.07)), _m(Color(0.95, 0.95, 0.93), 0.8), Vector3(-0.11, 0.0045, -0.06), Vector3(0, -0.12, 0), f)
	_part(_box(Vector3(0.078, 0.0016, 0.058)), photo, Vector3(-0.11, 0.0052, -0.06), Vector3(0, -0.12, 0), f)
	_part(_box(Vector3(0.012, 0.004, 0.03)), _m(Color(0.7, 0.7, 0.72), 0.3, 0.9), Vector3(-0.07, 0.006, -0.088), Vector3(0, -0.12, 0), f)  # paper clip
	var stamp := Label3D.new()
	stamp.text = "CONFIDENTIAL"
	stamp.font_size = 40
	stamp.pixel_size = 0.0006
	stamp.outline_size = 0
	stamp.modulate = Color(0.7, 0.12, 0.1, 0.85)
	stamp.rotation = Vector3(-PI / 2.0, 0.0, 0.25)
	stamp.position = Vector3(-0.11, 0.0045, 0.06)
	f.add_child(stamp)
	return f


static func badge() -> Node3D:
	var b := Node3D.new()
	var leather := _m(Color(0.10, 0.06, 0.04), 0.7)
	var gold := _m(Color(0.85, 0.66, 0.25), 0.25, 1.0)
	_part(_box(Vector3(0.075, 0.008, 0.10)), leather, Vector3(0, 0.004, 0), Vector3.ZERO, b)
	var shield := _cyl(0.026, 0.026, 0.004, 7)
	_part(shield, gold, Vector3(0, 0.010, -0.012), Vector3.ZERO, b)
	_part(_cyl(0.012, 0.012, 0.002, 5), _m(Color(0.65, 0.48, 0.18), 0.3, 1.0), Vector3(0, 0.013, -0.012), Vector3.ZERO, b)
	return b


# a black typewriter; the paper's text is the Label3D named "Text" (on the sheet, facing the typist)
static func typewriter() -> Node3D:
	var w := Node3D.new()
	var body := _m(Color(0.07, 0.07, 0.08), 0.35, 0.4)
	var chrome := _m(Color(0.75, 0.75, 0.78), 0.2, 1.0)
	var keycap := _m(Color(0.88, 0.86, 0.80), 0.5)
	var rubber := _m(Color(0.03, 0.03, 0.03), 0.8)
	_part(_box(Vector3(0.34, 0.07, 0.26)), body, Vector3(0, 0.035, 0), Vector3.ZERO, w)
	_part(_box(Vector3(0.34, 0.06, 0.12)), body, Vector3(0, 0.085, -0.07), Vector3.ZERO, w)            # the raised back
	var platen := _part(_cyl(0.022, 0.022, 0.36, 20), rubber, Vector3(0, 0.125, -0.09), Vector3(0, 0, PI / 2.0), w)
	platen.name = "Platen"
	for sx in [-1.0, 1.0]:
		_part(_cyl(0.012, 0.012, 0.012, 16), chrome, Vector3(sx * 0.19, 0.125, -0.09), Vector3(0, 0, PI / 2.0), w)
	_part(_box(Vector3(0.05, 0.006, 0.012)), chrome, Vector3(-0.21, 0.135, -0.07), Vector3(0, 0, 0.3), w)  # carriage return lever
	# four rows of round keys stepping up toward the back
	for r in 4:
		for k in 10 - (1 if r == 3 else 0):
			var x := -0.135 + k * 0.03 + r * 0.007
			var key := _part(_cyl(0.011, 0.011, 0.006, 14), keycap, Vector3(x, 0.074 + r * 0.008, 0.10 - r * 0.026), Vector3.ZERO, w)
			key.name = "Key"
			_part(_cyl(0.0125, 0.0125, 0.004, 14), chrome, Vector3(x, 0.071 + r * 0.008, 0.10 - r * 0.026), Vector3.ZERO, w)
	_part(_box(Vector3(0.16, 0.008, 0.02)), keycap, Vector3(0, 0.072, 0.125), Vector3.ZERO, w)            # space bar
	# the sheet of paper rolling out of the platen, leaning back
	var sheet := Node3D.new()
	sheet.name = "Sheet"
	sheet.position = Vector3(0, 0.13, -0.1)
	sheet.rotation.x = -0.28
	w.add_child(sheet)
	var p := QuadMesh.new()
	p.size = Vector2(0.21, 0.24)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.94, 0.92, 0.86)
	pm.roughness = 0.95
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pq := MeshInstance3D.new()
	pq.mesh = p
	pq.material_override = pm
	pq.position = Vector3(0, 0.12, 0)
	sheet.add_child(pq)
	var text := Label3D.new()
	text.name = "Text"
	text.font_size = 22
	text.pixel_size = 0.00042
	text.outline_size = 0
	text.modulate = Color(0.08, 0.07, 0.08)
	text.width = 440.0
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.position = Vector3(0, 0.225, 0.001)
	sheet.add_child(text)
	return w


# a bottle of whiskey; its liquid is the MeshInstance3D named "Liquid" (scale its height to show how much is left)
static func bottle() -> Node3D:
	var b := Node3D.new()
	var glass := _glass(Color(0.35, 0.22, 0.12), 0.35)
	var whisky := StandardMaterial3D.new()
	whisky.albedo_color = Color(0.55, 0.22, 0.03, 0.85)
	whisky.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	whisky.roughness = 0.05
	whisky.disable_fog = true
	var liquid := _part(_cyl(0.034, 0.034, 0.15, 24), whisky, Vector3(0, 0.083, 0), Vector3.ZERO, b)
	liquid.name = "Liquid"
	_part(_cyl(0.037, 0.037, 0.17, 24), glass, Vector3(0, 0.085, 0), Vector3.ZERO, b)        # the body
	_part(_cyl(0.014, 0.037, 0.04, 24), glass, Vector3(0, 0.19, 0), Vector3.ZERO, b)         # shoulders
	_part(_cyl(0.013, 0.013, 0.07, 16), glass, Vector3(0, 0.245, 0), Vector3.ZERO, b)        # neck
	_part(_cyl(0.015, 0.015, 0.022, 16), _m(Color(0.12, 0.08, 0.06), 0.6), Vector3(0, 0.29, 0), Vector3.ZERO, b)   # cork cap
	var label := _part(_cyl(0.0375, 0.0375, 0.07, 24), _m(Color(0.88, 0.82, 0.66), 0.9), Vector3(0, 0.09, 0), Vector3.ZERO, b)
	label.scale = Vector3(1.0, 1.0, 1.0)
	var t := Label3D.new()
	t.text = "OLD\nGUMSHOE"
	t.font_size = 26
	t.pixel_size = 0.0005
	t.outline_size = 0
	t.modulate = Color(0.25, 0.1, 0.05)
	t.position = Vector3(0, 0.09, 0.0385)
	b.add_child(t)
	return b
