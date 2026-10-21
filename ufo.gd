extends Node3D
## UFO (an easter egg): a flying saucer swoops in from the left, close outside the window, and stops. Its
## spin slows until a little port faces the room, the hatch slides up, and a grey alien with big black eyes
## looks in at you for a few seconds. The hatch drops, and it zooms off to the right.
## Tap the little alien bobblehead on the desk ten times (or use the Debug window); in a shared room the host's saucer flies past everyone's window.

const Model := preload("res://ufo_model.gd")

const SCALE := 4.5
const Y := 1.12                     # puts the port at standing eye height
const Z := -4.9                      # just outside the glass
const FROM_X := -14.0
const STOP_X := -1.95                # the middle of a pane (not behind the centre post)
const TO_X := 22.0
const ARRIVE := 2.6
const SETTLE := 1.4                  # spin slowing down until the port faces in
const OPEN := 0.5
const LOOK := 3.5
const LEAVE := 1.3

var main: Node3D
var active := false
var count := 0
var _u: Node3D
var _hatch: Node3D
var _alien: Node3D
var _t := 0.0
var _spin := 0.0
var _hum: AudioStreamPlayer
var _whoosh: AudioStreamPlayer


func setup(m: Node3D) -> void:
	main = m
	_u = Model.build()
	_u.scale = Vector3.ONE * SCALE
	_u.visible = false
	_u.get_node("Beam").visible = false
	main.room.add_child(_u)
	_hatch = _u.get_node("Port/Hatch")
	_alien = _u.get_node("Port/Alien")
	_hum = AudioStreamPlayer.new()
	_hum.stream = _make_hum()
	_hum.volume_db = -14.0
	add_child(_hum)
	_whoosh = AudioStreamPlayer.new()
	_whoosh.stream = _make_whoosh()
	_whoosh.volume_db = -6.0
	add_child(_whoosh)
	set_process(false)
	_build_figure()


# ---- the little alien figure on the desk: a bobblehead. Tap its head ten times and the real one visits.

const FIG_POS := Vector3(0.62, 0.785, -1.42)
const FIG_TAPS := 10
var _fig_head: Node3D
var _fig_taps := 0
var _fig_t := 0.0


func _build_figure() -> void:
	var fig := Node3D.new()
	fig.position = FIG_POS
	fig.rotation.y = 0.5                          # turned toward the chair
	main.room.add_child(fig)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.60, 0.63, 0.65)
	grey.roughness = 0.35
	grey.emission_enabled = true                  # a little of its own grey, so the pink lamps don't wash it out
	grey.emission = Color(0.36, 0.39, 0.40)
	grey.emission_energy_multiplier = 0.5
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0, 0, 0)
	black.roughness = 0.03
	black.metallic_specular = 1.0
	var base_m := StandardMaterial3D.new()
	base_m.albedo_color = Color(0.1, 0.35, 0.3)
	base_m.emission_enabled = true
	base_m.emission = Color(0.2, 0.9, 0.7)
	base_m.emission_energy_multiplier = 0.9       # a glow-in-the-dark stand
	var base := CylinderMesh.new()
	base.top_radius = 0.03
	base.bottom_radius = 0.034
	base.height = 0.01
	base.radial_segments = 32
	var bm := MeshInstance3D.new()
	bm.mesh = base
	bm.material_override = base_m
	bm.position = Vector3(0, 0.005, 0)
	fig.add_child(bm)
	# a slim body, one smooth piece from the hips to a thin neck
	var body := _lathe([[0.0, 0.0], [0.002, 0.009], [0.012, 0.013], [0.026, 0.0135], [0.038, 0.012], [0.047, 0.009],
		[0.053, 0.0055], [0.058, 0.0038], [0.064, 0.0036], [0.066, 0.0]], 0.8, grey)
	body.position.y = 0.01
	fig.add_child(body)
	# long thin arms hanging at its sides
	for sx in [-1.0, 1.0]:
		var arm := _lathe([[0.0, 0.0], [0.003, 0.0026], [0.02, 0.0024], [0.034, 0.002], [0.037, 0.0]], 1.0, grey)
		arm.position = Vector3(sx * 0.0125, 0.06, 0.0)
		arm.rotation = Vector3(0.0, 0.0, PI + sx * 0.14)            # hanging down from the shoulder
		fig.add_child(arm)
	# the head on a spring (it bobbles): a smooth inverted teardrop, a big rounded cranium tapering to a narrow chin
	_fig_head = Node3D.new()
	_fig_head.position = Vector3(0, 0.07, 0)
	fig.add_child(_fig_head)
	var head := _lathe([[0.0, 0.0], [0.002, 0.0045], [0.008, 0.0085], [0.016, 0.013], [0.026, 0.018], [0.036, 0.022],
		[0.046, 0.0245], [0.054, 0.025], [0.061, 0.0235], [0.067, 0.0195], [0.072, 0.013], [0.075, 0.006], [0.076, 0.0]], 0.84, grey)
	_fig_head.add_child(head)
	# big black almond eyes wrapping round the front of the face
	for sx in [-1.0, 1.0]:
		var em := SphereMesh.new()
		em.radius = 1.0
		em.height = 2.0
		em.radial_segments = 24
		em.rings = 12
		var e := MeshInstance3D.new()
		e.mesh = em
		e.material_override = black
		e.position = Vector3(sx * 0.0105, 0.031, 0.0142)
		e.scale = Vector3(0.0118, 0.0062, 0.0042)
		e.rotation = Vector3(0.0, sx * 0.5, sx * 0.48)              # tilted up at the outer corners, following the curve
		_fig_head.add_child(e)
	var hit := Node3D.new()
	hit.position = FIG_POS + Vector3(0, 0.07, 0)
	main.room.add_child(hit)
	main.interactables.append({"node": hit, "half": Vector3(0.045, 0.075, 0.045), "guest_ok": true,
		"label": func() -> String: return "A LITTLE ALIEN" if not active else "A LITTLE ALIEN  (it's waving)", "cb": tap_figure})


# a smooth surface turned around the y axis from a profile of [height, radius] points (depth scales z)
static func _lathe(profile: Array, depth: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 32
	# smooth the profile: Catmull-Rom, 6 steps per span
	var pts: Array[Vector2] = []
	for i in profile.size() - 1:
		var p0: Array = profile[maxi(i - 1, 0)]
		var p1: Array = profile[i]
		var p2: Array = profile[i + 1]
		var p3: Array = profile[mini(i + 2, profile.size() - 1)]
		for k in 6:
			var t := k / 6.0
			pts.append(Vector2(_cr(p0[0], p1[0], p2[0], p3[0], t), maxf(0.0, _cr(p0[1], p1[1], p2[1], p3[1], t))))
	var last: Array = profile[profile.size() - 1]
	pts.append(Vector2(last[0], last[1]))
	for i in pts.size():
		for j in seg + 1:
			var a := TAU * j / seg
			st.add_vertex(Vector3(cos(a) * pts[i].y, pts[i].x, sin(a) * pts[i].y * depth))
	for i in pts.size() - 1:
		for j in seg:
			var a := i * (seg + 1) + j
			var b := a + seg + 1
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(b + 1)
			st.add_index(b)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func _cr(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t2 * t)


func tap_figure() -> void:
	_fig_t = 1.2                                    # bobble
	set_process(true)
	if active:
		return
	_fig_taps += 1
	if _fig_taps >= FIG_TAPS:
		_fig_taps = 0
		await get_tree().create_timer(1.2).timeout
		request_visit()


func _bobble(delta: float) -> void:
	if _fig_t <= 0.0 and not active:
		return
	_fig_t = maxf(0.0, _fig_t - delta)
	var k := _fig_t / 1.2
	var w := Time.get_ticks_msec() / 1000.0
	var amp := 0.35 * k + (0.08 if active else 0.0)  # it keeps nodding while its friend is outside
	_fig_head.rotation = Vector3(amp * sin(w * 14.0), 0.0, amp * 0.7 * sin(w * 11.0))


func request_visit() -> void:
	if active or main.egg_active or main.sleeping:
		return
	var ng = main.net_game
	if ng != null and ng.net.is_online() and not ng.net.is_host():
		ng.net.send_var(1, ng.Net.K_EVENT, {"k": "ufo_on"})
		return
	count += 1
	start()


func start() -> void:
	if active:
		return
	active = true
	_t = 0.0
	_spin = 0.0
	_hatch.position.y = 0.0
	_alien.visible = false
	_u.visible = true
	_hum.play()
	_whoosh.play()
	set_process(true)


func _process(delta: float) -> void:
	_bobble(delta)
	if not active:
		if _fig_t <= 0.0:
			_fig_head.rotation = Vector3.ZERO
			set_process(false)
		return
	_t += delta
	var t := _t
	var x := STOP_X
	var spin_speed := 4.0
	var bob := sin(t * 2.2) * 0.04
	var tilt := 0.0
	var t1 := ARRIVE
	var t2 := t1 + SETTLE
	var t3 := t2 + OPEN
	var t4 := t3 + LOOK
	var t5 := t4 + OPEN
	if t < t1:
		var k := t / ARRIVE
		x = lerpf(FROM_X, STOP_X, 1.0 - pow(1.0 - k, 3.0))         # swoops in and brakes
		tilt = -0.25 * (1.0 - k)                                  # leaning into the move
	elif t < t2:
		spin_speed = 0.0                                           # the spin winds down to the port, below
	elif t < t5:
		spin_speed = 0.0
	else:
		var k := (t - t5) / LEAVE
		x = STOP_X + (TO_X - STOP_X) * k * k * k                   # and off, faster and faster
		tilt = 0.3 * minf(k * 3.0, 1.0)
		if t - delta < t5:
			_whoosh.play()
		spin_speed = 6.0
	# the spin: free while moving; between t1 and t2 it eases to a stop with the port toward the room
	if t < t1 or t >= t5:
		_spin += spin_speed * delta
	elif t < t2:
		var target := ceilf(_spin / TAU) * TAU                     # the next time the port faces +z
		_spin = lerpf(_spin, target, clampf(delta * 3.5, 0.0, 1.0))
	_u.position = Vector3(x, Y + bob, Z)
	_u.rotation = Vector3(0.0, _spin, tilt)
	Model.animate_lights(_u, t)
	# the hatch: up, the alien looks, down
	var open := 0.0
	if t >= t2 and t < t3:
		open = (t - t2) / OPEN
	elif t >= t3 and t < t4:
		open = 1.0
	elif t >= t4 and t < t5:
		open = 1.0 - (t - t4) / OPEN
	_hatch.position.y = 0.13 * smoothstep(0.0, 1.0, open)
	_alien.visible = open > 0.02
	if _alien.visible:
		# it leans in a little, tilts its head, looks at you
		_alien.rotation = Vector3(0.0, 0.2 * sin(t * 0.9), 0.18 * sin(t * 1.3))
		_alien.position.z = -0.01 + 0.008 * open
	_hum.volume_db = linear_to_db(clampf(1.0 - absf(x - STOP_X) / 18.0, 0.02, 1.0)) - 10.0
	if x > TO_X - 0.5:
		active = false
		_u.visible = false
		_hum.stop()


# ---- shared rooms

func state() -> int:
	return count


func apply_remote(n: int) -> void:
	if n > count:
		count = n
		start()


# ---- sounds, made here

static func _make_hum() -> AudioStreamWAV:
	var rate := 22050
	var n := int(2.0 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s := sin(t * TAU * 110.0) * 0.5 + sin(t * TAU * 165.0) * 0.25 + sin(t * TAU * 220.0 + sin(t * TAU * 6.0) * 2.0) * 0.2
		data.encode_s16(i * 2, int(s * 0.6 * 32767.0))
	var w := _wav(data, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


static func _make_whoosh() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.2 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 300.0 + 1400.0 * t                              # a rising sci-fi zip
		ph += f / rate
		var env := smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.7, 1.2, t))
		var s := sin(ph * TAU) * 0.5 + sin(ph * TAU * 1.5) * 0.25
		data.encode_s16(i * 2, int(s * env * 0.6 * 32767.0))
	return _wav(data, rate)


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
