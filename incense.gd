extends Node3D
## A stick of incense in a little wooden boat on the dresser. Light it and a curl of smoke rises,
## the glow of the ember warms the corner and the whole room slowly turns hazy; put it out and it clears.

const HAZE_SECS := 4.0
const WISP_N := 64

var main: Node3D
var lit := false
var haze := 0.0                       # 0 = clear air, 1 = fully hazy

var _ember_m: StandardMaterial3D
var _ember_light: OmniLight3D
var _tip := Vector3.ZERO              # where the ember sits (room space)
var _wisp: Array[Sprite3D] = []
var _sheets: Array[Sprite3D] = []
var _sheet_base: Array[Vector3] = []
var _veil: MeshInstance3D
var _veil_m: StandardMaterial3D
var _t := 0.0
var _glow_base := 0.9
var _glow_bloom := 0.15
var _sat_base := 1.25
var _amb_base := Color(0.55, 0.25, 0.60)
var _base_read := false


func setup(m: Node3D, pos: Vector3) -> void:
	main = m
	position = pos
	main.room.add_child(self)
	_build_holder()
	_build_smoke()
	set_process(false)
	var hit: MeshInstance3D = main._box(Vector3(0, 0.1, 0), Vector3(0.12, 0.26, 0.3), main._mat(Color.WHITE), self)
	hit.visible = false
	main.interactables.append({"node": hit, "half": Vector3(0.06, 0.13, 0.15), "egg_lock": true,
		"label": func() -> String: return "PUT OUT THE INCENSE" if lit else "LIGHT THE INCENSE",
		"cb": toggle})


func _build_holder() -> void:
	var wood: StandardMaterial3D = main._mat(Color(0.42, 0.22, 0.14), 0.55)
	var dark: StandardMaterial3D = main._mat(Color(0.30, 0.14, 0.10), 0.6)
	var ash: StandardMaterial3D = main._mat(Color(0.62, 0.60, 0.62), 0.9)
	var stick: StandardMaterial3D = main._mat(Color(0.66, 0.46, 0.28), 0.8)
	# a narrow wooden boat: a long tray with raised, rounded ends, standing on two little feet
	main._box(Vector3(0, 0.012, 0), Vector3(0.05, 0.014, 0.26), wood, self)
	main._box(Vector3(0, 0.024, -0.125), Vector3(0.05, 0.012, 0.04), wood, self)
	main._box(Vector3(0, 0.024, 0.125), Vector3(0.05, 0.012, 0.04), wood, self)
	main._box(Vector3(0, 0.032, -0.14), Vector3(0.05, 0.012, 0.018), dark, self)
	main._box(Vector3(0, 0.032, 0.14), Vector3(0.05, 0.012, 0.018), dark, self)
	main._box(Vector3(0, 0.003, -0.09), Vector3(0.04, 0.008, 0.02), dark, self)
	main._box(Vector3(0, 0.003, 0.09), Vector3(0.04, 0.008, 0.02), dark, self)
	# the stick leans out of the hole at the left end; ash has fallen along the tray
	var ang := deg_to_rad(28.0)
	var base := Vector3(0, 0.03, -0.12)
	var dirv := Vector3(0, cos(ang), sin(ang))
	var length := 0.21
	var st: MeshInstance3D = main._cyl(base + dirv * (length * 0.5), 0.0021, length, stick, self)
	st.basis = Basis(Vector3(1, 0, 0), ang)
	st.position = base + dirv * (length * 0.5)
	# burnt grey section at the top, the ember on the very tip
	var burnt: MeshInstance3D = main._cyl(base + dirv * (length - 0.018), 0.0024, 0.036, ash, self)
	burnt.basis = Basis(Vector3(1, 0, 0), ang)
	burnt.position = base + dirv * (length - 0.018)
	_ember_m = StandardMaterial3D.new()
	_ember_m.albedo_color = Color(0.25, 0.08, 0.04)
	_ember_m.emission_enabled = true
	_ember_m.emission = Color(1.0, 0.35, 0.08)
	_ember_m.emission_energy_multiplier = 0.0
	_ember_m.disable_fog = true
	var tip_local := base + dirv * (length + 0.002)
	var ember := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0034
	sm.height = 0.0068
	sm.radial_segments = 8
	sm.rings = 4
	ember.mesh = sm
	ember.material_override = _ember_m
	ember.position = tip_local
	add_child(ember)
	for i in 6:
		main._sphere(Vector3(0, 0.02, -0.06 + i * 0.012 + (i % 2) * 0.004), 0.003 + (i % 3) * 0.0008, ash, Vector3(1.3, 0.5, 1.0), self, 6)
	_tip = to_global(tip_local)
	_ember_light = OmniLight3D.new()
	_ember_light.position = tip_local + Vector3(0, 0.03, 0)
	_ember_light.light_color = Color(1.0, 0.5, 0.2)
	_ember_light.light_energy = 0.0
	_ember_light.omni_range = 0.7
	_ember_light.shadow_enabled = false
	add_child(_ember_light)


func _soft_tex(size: int, hard: float) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, hard)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _sprite(tex: Texture2D, size: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.double_sided = true
	s.transparent = true
	s.no_depth_test = false
	s.pixel_size = size / float(tex.get_width())
	s.modulate = Color(0.86, 0.80, 0.92, 0.0)
	s.render_priority = 5
	s.visible = false
	main.room.add_child(s)
	return s


func _build_smoke() -> void:
	var puff := _soft_tex(64, 1.6)
	for i in WISP_N:
		_wisp.append(_sprite(puff, 0.05))
	# big soft sheets of haze floating through the room, thicker around the dresser
	var big := _soft_tex(128, 1.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 16:
		var s := _sprite(big, rng.randf_range(1.6, 2.8))
		var p := Vector3(rng.randf_range(-3.7, 2.3), rng.randf_range(0.9, 2.5), rng.randf_range(-1.8, 1.4))
		if i < 6:
			p = Vector3(rng.randf_range(-3.7, -2.0), rng.randf_range(1.0, 2.4), rng.randf_range(-1.8, 0.2))
		s.position = p
		_sheets.append(s)
		_sheet_base.append(p)


func _ensure_veil() -> void:
	if _veil != null and is_instance_valid(_veil):
		return
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	_veil_m = StandardMaterial3D.new()
	_veil_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_veil_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_veil_m.cull_mode = BaseMaterial3D.CULL_FRONT
	_veil_m.no_depth_test = true
	_veil_m.render_priority = 10
	_veil_m.albedo_color = Color(0.78, 0.66, 0.86, 0.0)
	_veil = MeshInstance3D.new()
	_veil.mesh = sm
	_veil.material_override = _veil_m
	_veil.extra_cull_margin = 16.0
	main.head.add_child(_veil)


func toggle() -> void:
	lit = not lit
	if lit:
		if not _base_read:
			_base_read = true
			var e: Environment = main.world_env
			_glow_base = e.glow_intensity
			_glow_bloom = e.glow_bloom
			_sat_base = e.adjustment_saturation
			_amb_base = e.ambient_light_color
		_ensure_veil()
		for s in _wisp:
			s.visible = true
		for s in _sheets:
			s.visible = true
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	haze = move_toward(haze, 1.0 if lit else 0.0, delta / HAZE_SECS)
	var flick := 0.8 + 0.2 * sin(_t * 7.0) * sin(_t * 3.1 + 1.0)
	_ember_m.emission_energy_multiplier = (2.4 * flick) if lit else move_toward(_ember_m.emission_energy_multiplier, 0.0, delta * 3.0)
	_ember_m.albedo_color = Color(0.25, 0.08, 0.04).lerp(Color(0.9, 0.25, 0.08), clampf(_ember_m.emission_energy_multiplier / 2.4, 0.0, 1.0))
	_ember_light.light_energy = 0.35 * flick * clampf(_ember_m.emission_energy_multiplier / 2.4, 0.0, 1.0)
	_tip = to_global(Vector3(0, 0.03 + 0.21 * cos(deg_to_rad(28.0)), -0.12 + 0.21 * sin(deg_to_rad(28.0))))
	# the smoke column: a ribbon of soft puffs rising, curling and widening
	var strength := 1.0 if lit else haze
	for i in _wisp.size():
		var u := fposmod(_t * 0.085 + float(i) / _wisp.size(), 1.0)
		var h := u * 1.15
		var curl := sin(u * 9.0 - _t * 1.7 + i * 0.3) * (0.012 + 0.07 * u)
		var curl2 := cos(u * 7.0 - _t * 1.3 + i * 0.5) * (0.010 + 0.06 * u)
		var s := _wisp[i]
		s.global_position = _tip + Vector3(curl + 0.05 * u * u, h, curl2)
		s.pixel_size = (0.026 + 0.2 * u) / 64.0
		var fade := smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.45, 1.0, u))
		s.modulate.a = 0.22 * fade * strength * (1.0 if lit else haze)
	# haze: sheets drifting through the room, a veil over the view, softer bloom, flatter colour
	for i in _sheets.size():
		var b := _sheet_base[i]
		_sheets[i].position = b + Vector3(sin(_t * 0.07 + i) * 0.35, sin(_t * 0.05 + i * 2.0) * 0.12, cos(_t * 0.06 + i * 1.3) * 0.3)
		_sheets[i].modulate.a = 0.05 * haze
	if _veil_m != null:
		_veil_m.albedo_color.a = 0.11 * haze
	var e: Environment = main.world_env
	if _base_read and e != null:
		e.glow_intensity = lerpf(_glow_base, _glow_base * 1.3, haze)
		e.glow_bloom = lerpf(_glow_bloom, 0.34, haze)
		e.adjustment_saturation = lerpf(_sat_base, _sat_base * 0.86, haze)
		e.ambient_light_color = _amb_base.lerp(Color(0.66, 0.48, 0.70), haze * 0.7)
	if not lit and haze <= 0.0 and _ember_m.emission_energy_multiplier <= 0.01:
		for s in _wisp:
			s.visible = false
		for s in _sheets:
			s.visible = false
		set_process(false)
