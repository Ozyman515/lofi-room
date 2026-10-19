extends Node3D
## The Konami-code easter egg (entered while the console is on). For 30 seconds a tornado full of flailing sharks and
## debris crosses the window from right to left, the weather goes to a full storm, the TV and the PC monitor show an
## emergency alert and the whole street panics (honks, sirens, screams). Then everything goes back to how it was.

const VCR := preload("res://vcr.gd")
const GifPlayer := preload("res://gif_player.gd")

const DURATION := 30.0
const Z := -22.0                  # the tornado is in front of the city, behind the window
const BASE_Y := -30.0               # the tip touches the ground, far below the window
const FUNNEL_H := 42.0
const SWAY_K := 14.0               # how much the funnel wobbles and leans
const SHARK_K := 2.5              # sharks and debris are scaled up with the funnel
const DEBRIS_K := 2.2
const Y_LO := 27.0               # debris lives in the band of the funnel you can see from the window
const Y_HI := 38.0
const N_SHARKS := 13
const ANG_K := 0.45
const R_BOT := 0.9
const R_TOP := 23.3
const X_START := 31.0
const X_END := -31.0
const PASS_START := 6.0          # seconds: the tornado starts to come into view
const PASS_END := 19.0
# Where the funnel is (x, z): across the window from right to left and out of sight; then it is removed.
const PATH_T := [6.0, 21.0]
const PATH_P := [Vector2(35, -22), Vector2(-62, -22)]
const GONE_T := 21.5            # once it has left the window it is removed

var main: Node3D
var weather: Node
var active := false

var _t := 0.0                    # show time
var _clock := 0.0                # animation clock (seconds)
var _rng := RandomNumberGenerator.new()
var _funnel: Node3D
var _f_mats: Array[ShaderMaterial] = []
var _dust: GPUParticles3D
var _items: Array = []           # debris: {node, u0, rise, rk, a0, w, size, spin}
var _sharks: Array = []          # {root, tail, jaw, fin_l, fin_r, u0, rise, rk, a0, w, size, ph}
var _room0 := Vector3.ZERO
var _was_tv_on := true
var _was_monitor_on := true
var _weather_back := false

# overlays on the two screens
var _tv_alert: Control
var _pc_alert: Control
var _alerts: Array = []          # {root, bg, title, ticker, vol}

# audio
var _thread: Thread
var _bank := {}
var _audio_ready := false
var _jingle_pl: AudioStreamPlayer
var _tone_pl: AudioStreamPlayer3D
var _tone_loop: AudioStreamWAV
var _horn_pls: Array[AudioStreamPlayer] = []
var _horn_i := 0
var _scream_pls: Array[AudioStreamPlayer] = []
var _scream_i := 0
var _siren_pls: Array[AudioStreamPlayer] = []
var _siren_i := 0
var _rumble_pl: AudioStreamPlayer
var _horn_t := 0.0
var _scream_t := 0.0
var _siren_t := 0.0
var _arc_gif: Node                    # decodes media/sharknado.gif for the arcade monitor
var _arc_on := false
var _arc_t := 0.0
var _arc_i := 0


func setup(m: Node3D) -> void:
	main = m
	weather = m.weather
	_rng.randomize()
	visible = false
	_build_funnel()
	_build_items()
	_build_alerts()
	_build_players()
	_arc_gif = GifPlayer.new()
	add_child(_arc_gif)
	_arc_gif.setup(ShaderMaterial.new(), "res://media/sharknado", "console")      # a throw-away material: only the decoded frames are used
	_thread = Thread.new()
	_thread.start(_generate_audio)         # the sounds are made in the background so the game never hitches


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


# ---------------------------------------------------------------- tornado

func _build_funnel() -> void:
	_funnel = Node3D.new()
	_funnel.position = Vector3(PATH_P[0].x, BASE_Y, PATH_P[0].y)
	add_child(_funnel)
	var sh: Shader = load("res://shaders/funnel.gdshader")
	for k in 2:
		var cm := CylinderMesh.new()
		cm.top_radius = R_TOP * (1.0 if k == 0 else 0.72)
		cm.bottom_radius = R_BOT * (1.0 if k == 0 else 0.7)
		cm.height = FUNNEL_H
		cm.radial_segments = 48
		cm.rings = 30
		cm.cap_top = false
		cm.cap_bottom = false
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.render_priority = 20 + k
		mat.set_shader_parameter("height", FUNNEL_H)
		mat.set_shader_parameter("sway_k", SWAY_K)
		mat.set_shader_parameter("swirl_speed", 1.0 if k == 0 else -1.6)
		mat.set_shader_parameter("tint", Vector3(0.24, 0.21, 0.30) if k == 0 else Vector3(0.12, 0.10, 0.17))
		_f_mats.append(mat)
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = mat
		mi.position = Vector3(0.0, FUNNEL_H / 2.0, 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_funnel.add_child(mi)
	# dust and rubble thrown up at the bottom (kept high enough to be seen from the window)
	_dust = GPUParticles3D.new()
	_dust.amount = 150
	_dust.lifetime = 3.0
	_dust.local_coords = false
	_dust.visibility_aabb = AABB(Vector3(-60, -30, -50), Vector3(120, 80, 100))
	_dust.position = Vector3(0.0, Y_LO - 5.0, 0.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(11.0, 1.5, 6.0)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 70.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0.0, 0.1, 0.0)
	pm.damping_min = 0.3
	pm.damping_max = 0.8
	pm.scale_min = 3.0
	pm.scale_max = 9.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.42, 0.34, 0.34, 0.0))
	grad.add_point(0.18, Color(0.42, 0.34, 0.34, 0.55))
	grad.set_color(grad.get_point_count() - 1, Color(0.30, 0.26, 0.30, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_dust.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.billboard_keep_scale = true
	qm.albedo_texture = _soft_dot()
	qm.disable_fog = true
	q.material = qm
	_dust.draw_pass_1 = q
	_dust.emitting = false
	_funnel.add_child(_dust)


func _soft_dot() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) * clampf(1.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _sway(vh: float, tt: float) -> float:       # the same bend as in funnel.gdshader
	return (sin(tt * 1.1 + vh * 3.0) * 0.20 + sin(vh * 5.0 - tt * 1.7) * 0.09) * vh * SWAY_K


func _sway_z(vh: float, tt: float) -> float:
	return sin(tt * 0.9 + vh * 2.5) * 0.10 * vh * SWAY_K


# ---------------------------------------------------------------- sharks + debris

func _mat(c: Color, glow: float = 0.22, rough: float = 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = glow
	return m


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# a thin cylinder between two points (frames, branches, poles)
func _rod(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material) -> void:
	var d := b - a
	var dist := d.length()
	if dist < 0.001:
		return
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = dist
	cm.radial_segments = 6
	cm.rings = 1
	var mi := _mesh(parent, cm, mat, (a + b) / 2.0)
	var dn := d / dist
	if dn.dot(Vector3.UP) < -0.999:
		mi.rotation = Vector3(PI, 0.0, 0.0)
	else:
		mi.basis = Basis(Quaternion(Vector3.UP, dn))


func _make_shark(length: float) -> Dictionary:
	var root := Node3D.new()
	var slate := _mat(Color(0.34, 0.42, 0.54), 0.5, 0.55)
	var fin_m := _mat(Color(0.26, 0.32, 0.43), 0.4, 0.6)
	var belly := _mat(Color(0.82, 0.84, 0.90), 0.45, 0.6)
	var mouth_m := _mat(Color(0.55, 0.05, 0.10), 0.5, 0.6)
	var eye_m := _mat(Color(0.02, 0.02, 0.03), 0.0, 0.3)
	var teeth_m := _mat(Color(0.95, 0.95, 0.92), 0.5, 0.4)
	var L := length
	var body := SphereMesh.new()
	body.radius = 0.5
	body.height = 1.0
	body.radial_segments = 16
	body.rings = 8
	var bn := Node3D.new()
	bn.scale = Vector3(L, L * 0.30, L * 0.32)
	root.add_child(bn)
	_mesh(bn, body, slate)
	var bn2 := Node3D.new()
	bn2.scale = Vector3(L * 0.95, L * 0.20, L * 0.30)
	bn2.position = Vector3(0.02 * L, -0.07 * L, 0.0)
	root.add_child(bn2)
	_mesh(bn2, body, belly)
	# dorsal fin
	var fin := PrismMesh.new()
	fin.size = Vector3(0.24 * L, 0.22 * L, 0.03 * L)
	_mesh(root, fin, fin_m, Vector3(-0.02 * L, 0.20 * L, 0.0), Vector3(0.0, 0.0, 0.0))
	# tail: two lobes on a pivot at the back, swung left and right
	var tail := Node3D.new()
	tail.position = Vector3(-0.47 * L, 0.0, 0.0)
	root.add_child(tail)
	var tf1 := PrismMesh.new()
	tf1.size = Vector3(0.20 * L, 0.34 * L, 0.025 * L)
	_mesh(tail, tf1, fin_m, Vector3(-0.08 * L, 0.14 * L, 0.0), Vector3(0.0, 0.0, 0.5))
	_mesh(tail, tf1, fin_m, Vector3(-0.07 * L, -0.12 * L, 0.0), Vector3(PI, 0.0, -0.4))
	# pectoral fins, flapping
	var pf := PrismMesh.new()
	pf.size = Vector3(0.22 * L, 0.18 * L, 0.03 * L)
	var fin_l := Node3D.new()
	fin_l.position = Vector3(0.14 * L, -0.05 * L, 0.12 * L)
	root.add_child(fin_l)
	_mesh(fin_l, pf, fin_m, Vector3(0.0, -0.08 * L, 0.0), Vector3(0.0, 0.0, PI))
	var fin_r := Node3D.new()
	fin_r.position = Vector3(0.14 * L, -0.05 * L, -0.12 * L)
	root.add_child(fin_r)
	_mesh(fin_r, pf, fin_m, Vector3(0.0, -0.08 * L, 0.0), Vector3(0.0, 0.0, PI))
	# open mouth: rounded dark-red inside, a rounded lower jaw that snaps open and shut, cone teeth top and bottom
	var mouth := _mesh(root, body, mouth_m, Vector3(0.36 * L, -0.105 * L, 0.0))
	mouth.scale = Vector3(0.20 * L, 0.035 * L, 0.15 * L)
	var jaw := Node3D.new()
	jaw.position = Vector3(0.20 * L, -0.11 * L, 0.0)
	root.add_child(jaw)
	var jm := _mesh(jaw, body, belly, Vector3(0.14 * L, 0.0, 0.0))
	jm.scale = Vector3(0.30 * L, 0.06 * L, 0.20 * L)
	var tooth := CylinderMesh.new()
	tooth.top_radius = 0.0
	tooth.bottom_radius = 0.011 * L
	tooth.height = 0.045 * L
	tooth.radial_segments = 5
	tooth.rings = 1
	for k in 5:
		var tz: float = (float(k) - 2.0) * 0.036 * L
		var tx: float = 0.22 * L - absf(tz) * 0.5
		_mesh(jaw, tooth, teeth_m, Vector3(tx, 0.045 * L, tz))
		_mesh(root, tooth, teeth_m, Vector3(0.32 * L - absf(tz) * 0.4 + 0.07 * L, -0.065 * L, tz), Vector3(PI, 0.0, 0.0))
	for sgn in [-1.0, 1.0]:
		var ey := SphereMesh.new()
		ey.radius = 0.025 * L
		ey.height = 0.05 * L
		_mesh(root, ey, eye_m, Vector3(0.33 * L, 0.06 * L, sgn * 0.10 * L))
	return {"root": root, "tail": tail, "jaw": jaw, "fin_l": fin_l, "fin_r": fin_r}


func _boxm(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 8
	return t


func _cylm(r: float, h: float, segs: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	return c


func _make_bike() -> Node3D:
	var root := Node3D.new()
	var tire := _mat(Color(0.07, 0.07, 0.09), 0.3)
	var frame := _mat(Color(0.85, 0.18, 0.28), 0.6)
	var chrome := _mat(Color(0.65, 0.68, 0.75), 0.5)
	for wx in [-0.42, 0.42]:
		_mesh(root, _torus(0.18, 0.22), tire, Vector3(wx, 0.0, 0.0), Vector3(PI / 2.0, 0.0, 0.0))
		for ang in [0.0, 0.8, 1.6, 2.4]:                    # spokes
			var d := Vector3(cos(ang), sin(ang), 0.0) * 0.19
			_rod(root, Vector3(wx, 0.0, 0.0) - d, Vector3(wx, 0.0, 0.0) + d, 0.004, 0.004, chrome)
	_rod(root, Vector3(-0.42, 0.0, 0.0), Vector3(-0.05, 0.0, 0.0), 0.012, 0.012, frame)
	_rod(root, Vector3(-0.42, 0.0, 0.0), Vector3(-0.12, 0.32, 0.0), 0.012, 0.012, frame)
	_rod(root, Vector3(-0.05, 0.0, 0.0), Vector3(-0.12, 0.32, 0.0), 0.014, 0.014, frame)
	_rod(root, Vector3(-0.05, 0.0, 0.0), Vector3(0.30, 0.32, 0.0), 0.016, 0.016, frame)
	_rod(root, Vector3(-0.12, 0.32, 0.0), Vector3(0.30, 0.32, 0.0), 0.014, 0.014, frame)
	_rod(root, Vector3(0.42, 0.0, 0.0), Vector3(0.30, 0.32, 0.0), 0.012, 0.012, chrome)
	_rod(root, Vector3(0.30, 0.32, 0.0), Vector3(0.27, 0.45, 0.0), 0.012, 0.012, chrome)
	_rod(root, Vector3(0.27, 0.45, -0.17), Vector3(0.27, 0.45, 0.17), 0.011, 0.011, chrome)
	_mesh(root, _boxm(0.14, 0.035, 0.07), tire, Vector3(-0.14, 0.36, 0.0))
	return root


func _make_barrel() -> Node3D:
	var root := Node3D.new()
	var rust := _mat(Color(0.52, 0.24, 0.13), 0.3)
	var band := _mat(Color(0.20, 0.12, 0.10), 0.2)
	_mesh(root, _cylm(0.25, 0.62, 14), rust)
	for by in [-0.2, 0.2]:
		_mesh(root, _cylm(0.262, 0.035, 14), band, Vector3(0.0, by, 0.0))
	return root


func _make_plank() -> Node3D:
	var root := Node3D.new()
	var wood := _mat(Color(0.56, 0.38, 0.22), 0.3)
	var l := _rng.randf_range(0.9, 1.6)
	_mesh(root, _boxm(l, 0.05, 0.16), wood)
	_mesh(root, _boxm(0.05, 0.052, 0.12), _mat(Color(0.38, 0.24, 0.14), 0.2), Vector3(l * 0.3, 0.0, 0.0))
	return root


func _make_sign() -> Node3D:
	var root := Node3D.new()
	var metal := _mat(Color(0.55, 0.58, 0.64), 0.3)
	var red := _mat(Color(0.82, 0.10, 0.12), 0.5)
	var white := _mat(Color(0.95, 0.95, 0.95), 0.5)
	_rod(root, Vector3(0.0, -0.5, 0.0), Vector3(0.0, 0.5, 0.0), 0.018, 0.018, metal)
	_mesh(root, _cylm(0.27, 0.03, 8), red, Vector3(0.0, 0.5, 0.0), Vector3(PI / 2.0, 0.0, 0.0))
	_mesh(root, _boxm(0.34, 0.07, 0.035), white, Vector3(0.0, 0.5, 0.0))
	return root


func _make_tire() -> Node3D:
	var root := Node3D.new()
	_mesh(root, _torus(0.11, 0.3), _mat(Color(0.07, 0.07, 0.08), 0.2, 0.4), Vector3.ZERO, Vector3(0.9, 0.0, 0.0))
	return root


func _make_umbrella() -> Node3D:
	var root := Node3D.new()
	var cloth := _mat(Color(0.82, 0.16, 0.42), 0.45)
	var metal := _mat(Color(0.20, 0.20, 0.24), 0.3)
	var dome := SphereMesh.new()
	dome.radius = 0.46
	dome.height = 0.46
	dome.is_hemisphere = true
	dome.radial_segments = 10
	dome.rings = 4
	var mi := _mesh(root, dome, cloth, Vector3(0.0, 0.1, 0.0))
	mi.scale = Vector3(1.0, 0.8, 1.0)
	_rod(root, Vector3(0.0, -0.45, 0.0), Vector3(0.0, 0.3, 0.0), 0.012, 0.012, metal)
	_mesh(root, _torus(0.02, 0.07), metal, Vector3(0.05, -0.45, 0.0), Vector3(PI / 2.0, 0.0, 0.0))
	return root


# a tree branch with a few twigs (leaves on the bigger ones)
func _make_branch(length: float) -> Node3D:
	var root := Node3D.new()
	var bark := _mat(Color(0.34, 0.22, 0.13), 0.25)
	var leaf := _mat(Color(0.30, 0.55, 0.22), 0.35)
	var th := length * 0.035
	_rod(root, Vector3(-length / 2.0, 0.0, 0.0), Vector3(length / 2.0, 0.0, 0.0), th, th * 0.35, bark)
	var twigs := 2 if length < 0.9 else 3
	for i in twigs:
		var fx := _rng.randf_range(-0.3, 0.35) * length
		var side := 1.0 if i % 2 == 0 else -1.0
		var tl := length * _rng.randf_range(0.25, 0.4)
		var tip := Vector3(fx + tl * 0.7, side * tl * 0.5, _rng.randf_range(-0.2, 0.2) * tl)
		_rod(root, Vector3(fx, 0.0, 0.0), tip, th * 0.55, th * 0.2, bark)
		if length >= 0.9:
			for k in 3:
				var lf := SphereMesh.new()
				lf.radius = 0.07
				lf.height = 0.09
				lf.radial_segments = 6
				lf.rings = 3
				_mesh(root, lf, leaf, tip + Vector3(_rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.05, 0.08), _rng.randf_range(-0.08, 0.08)))
	if length >= 0.9:
		for k in 4:
			var lf2 := SphereMesh.new()
			lf2.radius = 0.08
			lf2.height = 0.1
			lf2.radial_segments = 6
			lf2.rings = 3
			_mesh(root, lf2, leaf, Vector3(length * 0.5 + _rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.07, 0.07)))
	return root


var _item_n := 0
const ITEM_COUNT := 22

func _add_item(node: Node3D, size: float) -> void:
	_funnel.add_child(node)
	var k := _item_n
	_item_n += 1
	# all debris moves at the same speed on a spiral, so nothing ever runs into anything else
	_items.append({"node": node, "u0": float(k) / float(ITEM_COUNT), "rise": 0.04, "rk": 0.50 + 0.12 * float(k % 2),
		"a0": float(k) * TAU * 0.382 + 1.1, "w": 3.0, "size": size,
		"spin": Vector3(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0))})


func _build_items() -> void:
	for i in N_SHARKS:
		var sd := _make_shark(_rng.randf_range(1.25, 1.9))
		var root: Node3D = sd["root"]
		_funnel.add_child(root)
		sd["u0"] = float(i) / float(N_SHARKS)
		sd["rise"] = 0.055
		sd["rk"] = 0.90
		sd["a0"] = float(i) * TAU * 0.382
		sd["w"] = 3.0
		sd["ph"] = _rng.randf() * TAU
		sd["spin"] = _rng.randf_range(1.5, 4.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_sharks.append(sd)
	_add_item(_make_bike(), 1.0)
	for i in 2:
		_add_item(_make_barrel(), 1.0)
	for i in 3:
		_add_item(_make_plank(), 1.0)
	for i in 2:
		_add_item(_make_sign(), 1.0)
	for i in 3:
		_add_item(_make_tire(), 1.0)
	for i in 3:
		_add_item(_make_umbrella(), 1.0)
	for i in 3:
		_add_item(_make_branch(_rng.randf_range(1.1, 1.8)), 1.0)       # medium branches
	for i in 5:
		_add_item(_make_branch(_rng.randf_range(0.45, 0.85)), 1.0)     # small ones
	_funnel.visible = false


func _orbit(u: float, rk: float, a0: float, w: float) -> Array:
	var yl: float = lerpf(Y_LO, Y_HI, u)
	var vh: float = yl / FUNNEL_H
	var r: float = lerpf(R_BOT, R_TOP, vh) * rk
	var fling := maxf(u - 0.86, 0.0) / 0.14
	r += fling * fling * 3.0                      # at the top of the band things get thrown out
	var a: float = a0 + _clock * w * ANG_K * (1.0 + 1.1 * (1.0 - u))
	var p := Vector3(cos(a) * r + _sway(vh, _clock), yl, sin(a) * r * 0.95 + _sway_z(vh, _clock))
	return [p, a]


func _update_things(delta: float) -> void:
	for sd in _sharks:
		var u: float = fmod(float(sd["u0"]) + _clock * float(sd["rise"]), 1.0)
		var o := _orbit(u, sd["rk"], sd["a0"], sd["w"])
		var root: Node3D = sd["root"]
		root.position = o[0]
		var a: float = o[1]
		var ph: float = sd["ph"]
		root.rotation = Vector3(_clock * float(sd["spin"]) + ph, -a - PI / 2.0, sin(_clock * 4.0 + ph) * 0.6)
		var sc := smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.93, 1.0, u))
		root.scale = Vector3.ONE * maxf(sc, 0.001) * SHARK_K
		(sd["tail"] as Node3D).rotation.y = sin(_clock * 13.0 + ph) * 0.75
		(sd["jaw"] as Node3D).rotation.z = -(0.1 + 0.5 * (0.5 + 0.5 * sin(_clock * 7.0 + ph * 2.0)))
		(sd["fin_l"] as Node3D).rotation.x = 0.9 + sin(_clock * 10.0 + ph) * 0.6
		(sd["fin_r"] as Node3D).rotation.x = -(0.9 + sin(_clock * 10.0 + ph + 1.3) * 0.6)
	for it in _items:
		var u2: float = fmod(float(it["u0"]) + _clock * float(it["rise"]), 1.0)
		var o2 := _orbit(u2, it["rk"], it["a0"], it["w"])
		var n: Node3D = it["node"]
		n.position = o2[0]
		var sp: Vector3 = it["spin"]
		n.rotation = sp * _clock
		var sc2 := smoothstep(0.0, 0.06, u2) * (1.0 - smoothstep(0.93, 1.0, u2))
		n.scale = Vector3.ONE * maxf(sc2, 0.001) * DEBRIS_K
	for mat in _f_mats:
		mat.set_shader_parameter("t", _clock)
		mat.set_shader_parameter("flash", maxf(weather.flash, weather.room_flash))


# ---------------------------------------------------------------- the alert on the screens

func _make_alert(sz: Vector2, with_volume: bool) -> Dictionary:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.55, 0.02, 0.04)
	root.add_child(bg)
	# hazard stripes along the top and bottom
	var bar_h := sz.y * 0.07
	for row in 2:
		var y := 0.0 if row == 0 else sz.y - bar_h
		var bar := ColorRect.new()
		bar.position = Vector2(0, y)
		bar.size = Vector2(sz.x, bar_h)
		bar.color = Color(0.98, 0.80, 0.08)
		root.add_child(bar)
		var step := bar_h * 1.6
		var x := -bar_h
		while x < sz.x:
			var st := Polygon2D.new()
			st.polygon = PackedVector2Array([Vector2(x, y + bar_h), Vector2(x + step * 0.5, y + bar_h), Vector2(x + step * 0.5 + bar_h * 0.8, y), Vector2(x + bar_h * 0.8, y)])
			st.color = Color(0.08, 0.05, 0.05)
			root.add_child(st)
			x += step
	# warning triangle with an exclamation mark
	var tri_cx := sz.x * 0.5
	var tri_top := bar_h * 1.4
	var tri_h := sz.y * 0.26
	var tri := Polygon2D.new()
	tri.polygon = PackedVector2Array([Vector2(tri_cx, tri_top), Vector2(tri_cx + tri_h * 0.62, tri_top + tri_h), Vector2(tri_cx - tri_h * 0.62, tri_top + tri_h)])
	tri.color = Color(0.98, 0.80, 0.08)
	root.add_child(tri)
	var tri_in := Polygon2D.new()
	tri_in.polygon = PackedVector2Array([Vector2(tri_cx, tri_top + tri_h * 0.16), Vector2(tri_cx + tri_h * 0.47, tri_top + tri_h * 0.93), Vector2(tri_cx - tri_h * 0.47, tri_top + tri_h * 0.93)])
	tri_in.color = Color(0.10, 0.04, 0.04)
	root.add_child(tri_in)
	var bang := Label.new()
	bang.text = "!"
	bang.add_theme_font_size_override("font_size", int(tri_h * 0.78))
	bang.add_theme_color_override("font_color", Color(0.98, 0.80, 0.08))
	bang.size = Vector2(tri_h, tri_h)
	bang.position = Vector2(tri_cx - tri_h * 0.5, tri_top + tri_h * 0.1)
	bang.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(bang)
	var title := Label.new()
	title.text = "TORNADO WARNING"
	title.add_theme_font_size_override("font_size", int(sz.x * 0.088))
	title.size = Vector2(sz.x, sz.y * 0.16)
	title.position = Vector2(0, tri_top + tri_h + sz.y * 0.02)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var sub := Label.new()
	sub.text = "TAKE SHELTER NOW"
	sub.add_theme_font_size_override("font_size", int(sz.x * 0.055))
	sub.add_theme_color_override("font_color", Color(0.98, 0.90, 0.35))
	sub.size = Vector2(sz.x, sz.y * 0.1)
	sub.position = Vector2(0, title.position.y + sz.y * 0.15)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	var sub2 := Label.new()
	sub2.text = "THIS IS NOT A TEST"
	sub2.add_theme_font_size_override("font_size", int(sz.x * 0.034))
	sub2.size = Vector2(sz.x, sz.y * 0.07)
	sub2.position = Vector2(0, sub.position.y + sz.y * 0.1)
	sub2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub2)
	# scrolling ticker
	var tick_h := sz.y * 0.075
	var tick_bg := ColorRect.new()
	tick_bg.position = Vector2(0, sz.y - bar_h - tick_h)
	tick_bg.size = Vector2(sz.x, tick_h)
	tick_bg.color = Color(0.06, 0.02, 0.03)
	tick_bg.clip_contents = true
	root.add_child(tick_bg)
	var ticker := Label.new()
	ticker.text = "EMERGENCY ALERT SYSTEM  ***  A TORNADO WARNING IS IN EFFECT FOR YOUR AREA  ***  SEEK SHELTER IN AN INTERIOR ROOM AWAY FROM WINDOWS  ***  DO NOT GO OUTSIDE  ***  DANGEROUS AIRBORNE DEBRIS AND SHARKS  ***  THIS IS NOT A TEST  ***  "
	ticker.add_theme_font_size_override("font_size", int(tick_h * 0.62))
	ticker.add_theme_color_override("font_color", Color(0.98, 0.9, 0.5))
	ticker.position = Vector2(0, tick_h * 0.06)
	tick_bg.add_child(ticker)
	var vol: Label = null
	if with_volume:
		vol = Label.new()
		vol.add_theme_font_size_override("font_size", int(sz.x * 0.026))
		vol.position = Vector2(sz.x * 0.03, sz.y - bar_h - tick_h - sz.y * 0.065)
		root.add_child(vol)
	return {"root": root, "bg": bg, "title": title, "ticker": ticker, "vol": vol, "width": sz.x}


func _build_alerts() -> void:
	var tv := _make_alert(Vector2(1024, 768), true)
	main.tv_screen_ui.root.add_child(tv["root"])
	_tv_alert = tv["root"]
	_alerts.append(tv)
	var pc := _make_alert(Vector2(1024, 576), false)
	main.monitor_ui.root.add_child(pc["root"])
	_pc_alert = pc["root"]
	_alerts.append(pc)


func _update_alerts(delta: float) -> void:
	var on := int(floor(_clock * 2.0)) % 2 == 0
	for a in _alerts:
		(a["bg"] as ColorRect).color = Color(0.62, 0.02, 0.04) if on else Color(0.36, 0.0, 0.02)
		(a["title"] as Label).add_theme_color_override("font_color", Color(1, 1, 1) if on else Color(1.0, 0.85, 0.2))
		var tk: Label = a["ticker"]
		tk.position.x -= delta * float(a["width"]) * 0.22
		if tk.position.x < -tk.size.x * 0.5:
			tk.position.x += tk.size.x * 0.5
		if a["vol"] != null:
			(a["vol"] as Label).text = "VOLUME  " + "|".repeat(main.vcr.tv_volume) + ".".repeat(10 - main.vcr.tv_volume)


# ---------------------------------------------------------------- audio

func _build_players() -> void:
	_jingle_pl = AudioStreamPlayer.new()
	_jingle_pl.bus = "Master"
	_jingle_pl.volume_db = -8.0
	add_child(_jingle_pl)
	_tone_pl = AudioStreamPlayer3D.new()
	_tone_pl.bus = "Master"
	_tone_pl.unit_size = 5.0
	_tone_pl.max_distance = 25.0
	_tone_pl.finished.connect(_on_tone_finished)
	add_child(_tone_pl)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Weather"
		add_child(p)
		_horn_pls.append(p)
	for i in 4:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "Weather"
		add_child(p2)
		_scream_pls.append(p2)
	for i in 3:
		var p3 := AudioStreamPlayer.new()
		p3.bus = "Weather"
		add_child(p3)
		_siren_pls.append(p3)
	_rumble_pl = AudioStreamPlayer.new()
	_rumble_pl.bus = "Weather"
	_rumble_pl.volume_db = -80.0
	_rumble_pl.stream = weather._noise_loop(8000, 6.0, 0.012, 1.0, 0.0, true)
	add_child(_rumble_pl)


func _generate_audio() -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	var bank := {}
	# the "power-up" jingle: a quick square-wave arpeggio and a final chord
	bank["jingle"] = _gen_jingle()
	# the emergency-alert attention tone (853 Hz + 960 Hz): a long first blast, then a repeating pattern
	bank["tone_long"] = _gen_tone(8.0, false)
	bank["tone_loop"] = _gen_tone(1.6, true)
	var horns: Array = []
	for i in 8:
		horns.append(weather._horn(r))
	bank["horns"] = horns
	var screams: Array = []
	for i in 6:
		screams.append(_gen_scream(r.randi()))
	bank["screams"] = screams
	_bank = bank
	_audio_ready = true


func _gen_jingle() -> AudioStreamWAV:
	var rate := 22050
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98]
	var n := int(rate * (0.07 * notes.size() + 0.55))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var idx := int(t / 0.07)
		var s := 0.0
		if idx < notes.size():
			var f: float = notes[idx]
			s = (1.0 if fmod(t * f, 1.0) < 0.25 else -1.0) * 0.5 * (1.0 - fmod(t, 0.07) / 0.07 * 0.3)
		else:
			var tt := t - 0.07 * notes.size()
			var env := exp(-tt * 4.0)
			for f2 in [1046.5, 1318.5, 1567.98]:
				s += (1.0 if fmod(tt * f2, 1.0) < 0.5 else -1.0) * 0.18 * env
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	return wav


func _gen_tone(secs: float, pulse: bool) -> AudioStreamWAV:
	var rate := 11025
	var n := int(rate * secs)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := 1.0
		if pulse:
			env = 1.0 if t < 1.0 else 0.0
		env *= minf(t * 60.0, 1.0) * minf((secs - t) * 60.0 + (0.0 if not pulse else 1.0), 1.0)
		var s := (sin(TAU * 853.0 * t) + sin(TAU * 960.0 * t)) * 0.32 * env
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	if pulse:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


# a stylised distant scream: a pitch that shoots up and falls, with vibrato and vowel-like emphasis, panned somewhere
func _gen_scream(seed_: int) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var rate := 16000
	var dur := r.randf_range(0.8, 1.4)
	var n := int(rate * dur)
	var f0 := r.randf_range(420.0, 740.0)
	var pk := f0 * r.randf_range(1.35, 1.75)
	var pan := r.randf_range(0.1, 0.9)
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	var phase := 0.0
	var lo := 0.0
	var f1 := r.randf_range(750.0, 1000.0)
	for i in n:
		var x := float(i) / n
		var contour := f0 + (pk - f0) * smoothstep(0.0, 0.22, x) * (1.0 - 0.45 * smoothstep(0.5, 1.0, x))
		var f := contour * (1.0 + 0.03 * sin(TAU * 6.5 * x * dur))
		phase += TAU * f / rate
		var s := 0.0
		for k in range(1, 9):
			var fk := f * k
			var form := exp(-pow((fk - f1) / 450.0, 2.0)) + 0.7 * exp(-pow((fk - 1900.0) / 700.0, 2.0)) + 0.25 * exp(-pow((fk - 3100.0) / 900.0, 2.0))
			s += sin(phase * k) * form / sqrt(float(k))
		var w := r.randf_range(-1.0, 1.0)
		lo += (w - lo) * 0.35
		var env := minf(x / 0.06, 1.0) * pow(1.0 - x, 0.8)
		var v := (s * 0.45 + lo * 0.22) * env
		bytes.encode_s16(i * 4, int(clampf(v * sqrt(1.0 - pan), -1.0, 1.0) * 26000.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(v * sqrt(pan), -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = true
	wav.data = bytes
	return wav


func _on_tone_finished() -> void:
	if active and _audio_ready:
		_tone_pl.stream = _tone_loop
		_tone_pl.play()


# how wild the street is right now, 0..1: builds up, peaks when the tornado is at the window, dies away
func _path(t: float) -> Vector2:
	var n := PATH_T.size()
	if t <= PATH_T[0]:
		return PATH_P[0]
	if t >= PATH_T[n - 1]:
		return PATH_P[n - 1]
	var i := 0
	while i < n - 2 and t >= PATH_T[i + 1]:
		i += 1
	var w: float = (t - PATH_T[i]) / (PATH_T[i + 1] - PATH_T[i])
	var p0: Vector2 = PATH_P[maxi(i - 1, 0)]
	var p3: Vector2 = PATH_P[mini(i + 2, n - 1)]
	var a: Vector2 = PATH_P[i]
	return a.cubic_interpolate(PATH_P[i + 1], p0, p3, w)


func _intensity() -> float:
	return smoothstep(0.0, 10.0, _t) * (1.0 - smoothstep(19.0, 29.0, _t))


func _update_audio(delta: float) -> void:
	var inten := _intensity()
	# the alert tone comes out of the TV, so the TV's volume buttons control it
	var tvv: int = main.vcr.tv_volume
	_tone_pl.volume_db = -80.0 if tvv == 0 else linear_to_db(float(tvv) / 10.0) - 3.0
	_tone_pl.global_position = main.tv_root.to_global(Vector3(0.0, 0.6, 0.4))     # just in front of the screen
	_rumble_pl.volume_db = linear_to_db(maxf(0.03 + 0.55 * inten, 0.0001))
	# honks
	_horn_t -= delta
	if _horn_t <= 0.0 and _t > 0.8 and _t < 29.0:
		_horn_t = lerpf(2.4, 0.45, inten) * _rng.randf_range(0.6, 1.4)
		var hp := _horn_pls[_horn_i]
		_horn_i = (_horn_i + 1) % _horn_pls.size()
		hp.stream = _bank["horns"][_rng.randi() % _bank["horns"].size()]
		hp.pitch_scale = _rng.randf_range(0.85, 1.2)
		hp.volume_db = linear_to_db(_rng.randf_range(0.5, 0.9) * (0.35 + 0.65 * inten))
		hp.play()
	# screams
	_scream_t -= delta
	if _scream_t <= 0.0 and _t > 5.0 and _t < 28.0:
		_scream_t = lerpf(3.0, 0.7, inten) * _rng.randf_range(0.6, 1.5)
		var sp := _scream_pls[_scream_i]
		_scream_i = (_scream_i + 1) % _scream_pls.size()
		sp.stream = _bank["screams"][_rng.randi() % _bank["screams"].size()]
		sp.pitch_scale = _rng.randf_range(0.9, 1.15)
		sp.volume_db = linear_to_db(_rng.randf_range(0.3, 0.6) * (0.3 + 0.7 * inten))
		sp.play()
	# sirens
	_siren_t -= delta
	if _siren_t <= 0.0 and _t > 2.0 and _t < 27.0:
		_siren_t = lerpf(5.0, 2.2, inten) * _rng.randf_range(0.7, 1.3)
		var pair: Array = weather._siren_streams[_rng.randi() % weather._siren_streams.size()]
		var sr := _siren_pls[_siren_i]
		_siren_i = (_siren_i + 1) % _siren_pls.size()
		sr.stream = pair[_rng.randi() % 2]
		sr.pitch_scale = _rng.randf_range(0.93, 1.07)
		sr.volume_db = linear_to_db(_rng.randf_range(0.35, 0.6) * (0.4 + 0.6 * inten))
		sr.play()


# ---------------------------------------------------------------- the show

func start() -> void:
	if active:
		return
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()                 # normally long finished
	if not _audio_ready:
		return
	_tone_loop = _bank["tone_loop"]
	active = true
	_t = 0.0
	_clock = 0.0
	_horn_t = 1.0
	_scream_t = 5.0
	_siren_t = 2.5
	_weather_back = false
	main.egg_active = true
	_was_tv_on = main.vcr.tv_on
	_was_monitor_on = main.monitor_on
	# the VCR and console are out of action: pause the tape, hide the console picture
	main.vcr.external_hold = true
	if not main.vcr.tv_on:
		main.vcr.toggle_tv()
	if main.vcr.state == VCR.State.PLAYING and not main.vcr._paused_flag:
		main.vcr._set_paused(true)
		main.vcr._tv_paused = true
	main.tv_mat.set_shader_parameter("use_console", false)
	main.tv_screen_ui.enabled = false
	main.tv_screen_ui.clear_hover()
	# the PC stays on (it is switched on if it was off), music pauses, nothing can be clicked
	if not main.monitor_on:
		main._set_monitor(true)
	main.monitor_ui.enabled = false
	main.monitor_ui.clear_hover()
	main.pc.set_alert_lock(true)
	_tv_alert.visible = true
	_pc_alert.visible = true
	main.tv_screen_ui.root.move_child(_tv_alert, -1)
	main.monitor_ui.root.move_child(_pc_alert, -1)
	# curtains go up and stay up
	main.curtain_target = 0.0
	main.curtain_last_down = false
	weather.begin_event()
	_room0 = main.room.position
	_funnel.position = Vector3(PATH_P[0].x, BASE_Y, PATH_P[0].y)
	_funnel.visible = true
	_funnel.scale = Vector3.ONE
	_dust.emitting = true
	_jingle_pl.stream = _bank["jingle"]
	_jingle_pl.play()
	_tone_pl.stream = _bank["tone_long"]
	_tone_pl.play()
	_rumble_pl.play()
	_arcade_show(true)
	visible = true


func _finish() -> void:
	active = false
	_funnel.visible = false
	_dust.emitting = false
	visible = false
	for p in _horn_pls + _scream_pls + _siren_pls:
		p.stop()
	_jingle_pl.stop()
	_tone_pl.stop()
	_rumble_pl.stop()
	main.room.position = _room0
	_tv_alert.visible = false
	_pc_alert.visible = false
	if not _weather_back:
		weather.end_event()
	main.egg_active = false
	_arcade_show(false)
	main.pc.set_alert_lock(false)
	if not _was_monitor_on:
		main._set_monitor(false)
	else:
		main.monitor_ui.enabled = true
	main.vcr.external_hold = main.console_on
	if not _was_tv_on:
		main.vcr.toggle_tv()
	main._apply_console()
	if not main.console_on and main.vcr._tv_paused and main.vcr.tv_on:
		main.vcr._set_paused(false)
		main.vcr._tv_paused = false


# The arcade monitor plays a looping sharknado picture while the event runs.
func _arcade_show(on: bool) -> void:
	_arc_on = false
	if not on:
		return                                # main._apply_console() puts the arcade screen back
	if main.arcade_mat == null or _arc_gif == null or _arc_gif.frames.is_empty():
		return
	_arc_on = true
	_arc_i = 0
	_arc_t = 0.0
	var m: ShaderMaterial = main.arcade_mat
	m.set_shader_parameter("console_tex", _arc_gif.frames[0])
	m.set_shader_parameter("console_aspect", 1.3333)
	m.set_shader_parameter("console_contain", false)
	m.set_shader_parameter("console_file", true)
	m.set_shader_parameter("use_console", true)
	m.set_shader_parameter("tv_power", 1.0)
	main.arcade_light.light_energy = 0.7


func _arcade_step(delta: float) -> void:
	var fr: Array = _arc_gif.frames
	var dl: Array = _arc_gif.delays
	if fr.size() < 2:
		return
	_arc_t += delta
	var moved := false
	while _arc_t >= float(dl[_arc_i]):
		_arc_t -= float(dl[_arc_i])
		_arc_i = (_arc_i + 1) % fr.size()
		moved = true
	if moved:
		(main.arcade_mat as ShaderMaterial).set_shader_parameter("console_tex", fr[_arc_i])


func _process(delta: float) -> void:
	if not active:
		return
	if _arc_on:
		_arcade_step(delta)
	_t += delta
	_clock += delta
	# the tornado crosses the window from right to left
	var pp := _path(_t)
	_funnel.position = Vector3(pp.x, BASE_Y, pp.y + sin(_clock * 0.5) * 1.2)
	_funnel.rotation.z = sin(_clock * 0.7) * 0.03
	if _t >= GONE_T and _funnel.visible:
		_funnel.visible = false          # out of sight: take the tornado away
		_dust.emitting = false
	_update_things(delta)
	_update_alerts(delta)
	_update_audio(delta)
	# a soft rumble through the building, strongest while the tornado is passing; tiny and low frequency on purpose
	var inten := _intensity()
	var amp := 0.0032 * inten
	main.room.position = _room0 + Vector3(
		(sin(_clock * 6.1) + 0.6 * sin(_clock * 9.7 + 1.0)) * amp,
		0.5 * sin(_clock * 7.3 + 2.0) * amp,
		(sin(_clock * 5.3 + 0.5) + 0.5 * sin(_clock * 8.9)) * amp)
	# the storm eases off for the last few seconds
	if _t >= 26.0 and not _weather_back:
		_weather_back = true
		weather.end_event()
	if _t >= DURATION:
		_finish()
