extends Node3D
## A cat curled up asleep: a round croissant with the head resting on its front paws, the tail wrapped
## round to the nose, eyes shut. Two coats: "tux" (black with a white bib, paws and muzzle) and "calico"
## (white with orange and black patches). It breathes, purrs in spells (a purr made here from pulses of soft
## noise, quiet unless you're close), and when petted it lifts its head a little and purrs loud for a while.
## Set `coat` before adding it to the tree. Local frame: origin on the surface it lies on. About 0.36 x 0.30 m.

@export var coat := "tux"

const BLACK := Color(0.040, 0.040, 0.048)
const WHITE := Color(0.93, 0.92, 0.90)
const PINK := Color(0.78, 0.45, 0.48)
const ORANGE := Color(0.86, 0.47, 0.16)
const PET_TIME := 7.0               # seconds of loud purring after a pet

static var _purr_stream: AudioStreamWAV

const BREATH := 2.6                 # seconds per breath (in, out)
const PURR_ON := Vector2(18.0, 45.0)     # a purring spell lasts this long (random in range)
const PURR_OFF := Vector2(25.0, 70.0)    # and the quiet between spells

var _body: Node3D                   # the parts that rise and fall with breathing
var _head: Node3D
var _purr: AudioStreamPlayer3D
var _t := 0.0
var _purring := false
var _next := 0.0
var _fade := 0.0
var _rng := RandomNumberGenerator.new()
var _pet_t := 0.0
var _lift := 0.0
var _head_rest := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	_build()
	_purr = AudioStreamPlayer3D.new()
	if _purr_stream == null:
		_purr_stream = _make_purr()
	_purr.stream = _purr_stream
	_purr.unit_size = 0.6               # a purr is close-up: clear within a metre, gone across the room
	_purr.max_distance = 4.0
	_purr.volume_db = -80.0
	_purr.position = Vector3(0.05, 0.08, 0)
	add_child(_purr)
	_next = _rng.randf_range(3.0, 10.0)


func _process(delta: float) -> void:
	_t += delta
	# breathing: the body swells a touch on the in-breath, the head nods with it
	var b := sin(_t * TAU / BREATH)
	_body.scale = Vector3(1.0 + b * 0.012, 1.0 + b * 0.03, 1.0 + b * 0.012)
	# a pet: the head comes up a little, then settles back down
	_pet_t = maxf(0.0, _pet_t - delta)
	_lift = move_toward(_lift, 1.0 if _pet_t > PET_TIME - 3.0 else 0.0, delta * 1.5)
	_head.rotation = _head_rest + Vector3(-0.32 * smoothstep(0.0, 1.0, _lift), 0.0, 0.03 * b)
	_head.position = _head_hp + Vector3(0, 0.012 * smoothstep(0.0, 1.0, _lift), 0)
	# purr in spells, fading in and out so it never clicks on (a pet starts one straight away)
	_next -= delta
	if _pet_t > 0.0 and not _purring:
		_next = 0.0
	if _next <= 0.0:
		_purring = not _purring
		_next = _rng.randf_range(PURR_ON.x, PURR_ON.y) if _purring else _rng.randf_range(PURR_OFF.x, PURR_OFF.y)
		if _purring:
			# start in step with the breathing, so the purr's in/out matches the body
			_purr.play(fmod(_t, BREATH))
	_fade = move_toward(_fade, 1.0 if _purring else 0.0, delta / 2.5)
	if _purr.playing:
		_purr.volume_db = linear_to_db(maxf(_fade, 0.0001)) - (0.0 if _pet_t > 0.0 else 6.0)
		if _fade <= 0.0 and not _purring:
			_purr.stop()


func is_purring() -> bool:
	return _purring


func pet() -> void:
	_pet_t = PET_TIME
	if _purring:
		_next = maxf(_next, PET_TIME)


func is_petted() -> bool:
	return _pet_t > 0.0


# ---- the model

var _head_hp := Vector3.ZERO


# the coat's colour at a point on the body or tail (calico patches; the tux is black all over its back)
func _coat_at(p: Vector3, tail: bool) -> Color:
	if coat != "calico":
		return BLACK
	if tail:
		return ORANGE if p.x < 0.06 else BLACK                  # orange tail, dark tip
	if p.y < 0.05:
		return WHITE                                             # white underneath and low on the sides
	# big patches over the back (the body's top is ~0.12 m up): orange rump, a black saddle, orange shoulders
	var patches := [[Vector3(-0.075, 0.13, -0.02), 0.085, ORANGE], [Vector3(0.0, 0.14, -0.085), 0.07, BLACK],
		[Vector3(0.065, 0.13, -0.03), 0.06, ORANGE], [Vector3(-0.095, 0.12, 0.07), 0.05, BLACK]]
	for pt in patches:
		var c: Vector3 = pt[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(pt[1]) and p.y > 0.05:
			return pt[2]
	return WHITE


func _build() -> void:
	var calico := coat == "calico"
	var blk := _fur(BLACK)
	var wht := _fur(WHITE)
	var pnk := _fur(PINK)
	var org := _fur(ORANGE)
	var coat_m := _fur(Color.WHITE)
	coat_m.vertex_color_use_as_albedo = true
	_body = Node3D.new()
	add_child(_body)
	# the body: one smooth tube along a spine that curls 250 degrees round the middle, rump to shoulders.
	# Thick enough that the curl closes up into a round cushion.
	var R := 0.068
	var spine: Array[Vector3] = []
	var rh: Array[float] = []
	var rv: Array[float] = []
	var n := 40
	for i in n + 1:
		var s := float(i) / n
		var a := deg_to_rad(lerpf(205.0, 445.0, s))
		var w := lerpf(0.080, 0.062, s) + 0.010 * sin(s * PI)        # hips widest, a little fuller mid-back
		var h := lerpf(0.070, 0.058, s)
		var k := _cap(s, 0.10) * _cap(1.0 - s, 0.06)                 # rounded rump; the shoulder end hides under the head
		spine.append(Vector3(cos(a) * R, h * 0.86, sin(a) * R))
		rh.append(w * k)
		rv.append(h * k)
	_body.add_child(_tube(spine, rh, rv, coat_m, _coat_at.bind(false)))
	# the tail: from the rump, round the outside of the curl and across the front, tip under the nose
	var tp: Array[Vector3] = []
	var tr: Array[float] = []
	var m := 30
	for i in m + 1:
		var s := float(i) / m
		var a := deg_to_rad(lerpf(200.0, 70.0, s))
		var rad := lerpf(0.13, 0.135, s) + 0.012 * sin(s * PI)
		tp.append(Vector3(cos(a) * rad, lerpf(0.035, 0.021, s), sin(a) * rad))
		var r := lerpf(0.023, 0.013, s) * _cap(1.0 - s, 0.08)
		tr.append(r)
	var trv: Array[float] = []
	for r in tr:
		trv.append(r * 0.9)
	_body.add_child(_tube(tp, tr, trv, coat_m, _coat_at.bind(true)))
	# a hind paw peeking out by the tail, white
	_ell(_body, Vector3(-0.115, 0.018, 0.095), Vector3(0.030, 0.017, 0.022), wht).rotation.y = 0.6
	# the head rests on the shoulder end, turned half out of the curl, chin on two tucked white paws
	var face := Vector3(-0.6, 0.0, 0.8).normalized()
	var hp := Vector3(-0.022, 0.082, 0.092)
	var sidev := face.cross(Vector3.UP)
	_ell(_body, hp + face * 0.018 + Vector3(0, -0.042, 0), Vector3(0.036, 0.028, 0.03), wht)     # white chest under the chin
	for sx in [-1.0, 1.0]:
		var pp: Vector3 = hp + face * 0.058 + sidev * sx * 0.024 + Vector3(0, -0.062, 0)
		var paw := _ell(_body, pp, Vector3(0.019, 0.016, 0.034), wht)
		paw.rotation.y = atan2(face.x, face.z)
	_head = Node3D.new()
	_head.position = hp
	_head_hp = hp
	_head.rotation = Vector3(deg_to_rad(18.0), atan2(face.x, face.z), deg_to_rad(-8.0))
	_head_rest = _head.rotation
	add_child(_head)
	if calico:
		_sleepy_head(_head, org, blk, wht, pnk, true)
	else:
		_sleepy_head(_head, blk, blk, wht, pnk, false)


# 0 at the very end of a tube, rising to 1 over the first `len` of it (a round end cap)
static func _cap(s: float, len: float) -> float:
	if s >= len:
		return 1.0
	var u := 1.0 - s / len
	return sqrt(maxf(0.0, 1.0 - u * u))           # closes to a point, so the end is a round cap with no hole


# a smooth tube through `pts`, with an elliptical section (width rh, height rv) that never dips below y = 0
static func _tube(pts: Array[Vector3], rh: Array[float], rv: Array[float], mat: Material, color_at: Callable) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := 24
	var cnt := pts.size()
	for i in cnt:
		var t := (pts[mini(i + 1, cnt - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := t.cross(Vector3.UP).normalized()
		var up := side.cross(t).normalized()
		for j in ring + 1:
			var ph := TAU * j / ring
			var p := pts[i] + side * cos(ph) * rh[i] + up * sin(ph) * rv[i]
			p.y = maxf(p.y, 0.002)                   # lies flat on whatever it's on
			st.set_uv(Vector2(float(j) / ring, float(i) / cnt))
			st.set_color(color_at.call(p))
			st.add_vertex(p)
	for i in cnt - 1:
		for j in ring:
			var a := i * (ring + 1) + j
			var b := a + ring + 1
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


# the head with the eyes shut and the ears relaxed. `a` is the left side's fur, `b` the right's (the calico's
# face is split orange / black, with a broad white blaze; the tux is black both sides with a thin one)
func _sleepy_head(h: Node3D, a: StandardMaterial3D, b: StandardMaterial3D, wht: StandardMaterial3D, pnk: StandardMaterial3D, calico: bool) -> void:
	_ell(h, Vector3(0, 0.000, 0.020), Vector3(0.072, 0.058, 0.064), a)
	if calico:
		_ell(h, Vector3(0.03, 0.006, 0.02), Vector3(0.046, 0.053, 0.058), b)       # the black half of the face
	for sx in [-1.0, 1.0]:
		_ell(h, Vector3(sx * 0.044, -0.014, 0.036), Vector3(0.037, 0.034, 0.038), b if sx > 0.0 else a)
	if calico:
		_ell(h, Vector3(0, 0.014, 0.066), Vector3(0.013, 0.03, 0.012), wht)       # broad white blaze
	else:
		_ell(h, Vector3(0, 0.016, 0.0775), Vector3(0.0055, 0.024, 0.006), wht)    # the blaze, a thin stripe
	var bridge := _ell(h, Vector3(0, 0.002, 0.077), Vector3(0.016, 0.032, 0.012), wht if calico else a)
	bridge.rotation_degrees = Vector3(-26, 0, 0)
	for sx in [-1.0, 1.0]:
		_ell(h, Vector3(sx * 0.025, -0.030, 0.076), Vector3(0.028, 0.023, 0.027), wht)
	_ell(h, Vector3(0, -0.048, 0.068), Vector3(0.023, 0.015, 0.023), wht)
	_ell(h, Vector3(0, -0.020, 0.099), Vector3(0.010, 0.008, 0.006), pnk)
	# shut eyes: a soft curved crease, a shade lighter than the fur so it shows
	var lid := StandardMaterial3D.new()
	lid.albedo_color = Color(0.20, 0.13, 0.10) if calico else Color(0.42, 0.40, 0.46)
	lid.roughness = 0.9
	for sx in [-1.0, 1.0]:
		var crease := _ell(h, Vector3(sx * 0.031, 0.008, 0.0765), Vector3(0.015, 0.0028, 0.005), lid)
		crease.rotation_degrees = Vector3(0, 0, sx * -12.0)
	# ears: laid back a little, the way a sleeping cat's go
	for sx in [-1.0, 1.0]:
		var ear := _cone(h, Vector3(sx * 0.047, 0.026, -0.010), 0.030, 0.060, b if sx > 0.0 else a)
		ear.rotation_degrees = Vector3(-22, 0, -sx * 24)
		var inner := _cone(h, Vector3(sx * 0.046, 0.029, -0.002), 0.020, 0.045, pnk)
		inner.rotation_degrees = Vector3(-22, 0, -sx * 24)


# ---- the purr: ~25 pulses a second of soft filtered noise, a little faster and stronger on the in-breath,
# with a breath's pause between. Three breaths, made to loop seamlessly.

static func _make_purr() -> AudioStreamWAV:
	var rate := 22050
	var breaths := 3
	var n := int(BREATH * breaths * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	var lp2 := 0.0
	var pulse_t := 0.0
	var amp := 0.0
	for i in n:
		var t := float(i) / rate
		var ph := fmod(t, BREATH) / BREATH            # 0..1 through a breath: in for 45 %, out for the rest
		var inhale := ph < 0.45
		var f := 23.0 if inhale else 26.0
		var env := 0.0
		if inhale:
			env = smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.38, 0.45, ph))
		else:
			env = 0.75 * smoothstep(0.47, 0.55, ph) * (1.0 - smoothstep(0.90, 1.0, ph))
		pulse_t += 1.0 / rate
		if pulse_t >= 1.0 / f:
			pulse_t -= 1.0 / f
			amp = 1.0                                 # each vocal-fold flutter is a little thud of noise
		amp *= 0.9975
		var noise := rng.randf_range(-1.0, 1.0) * amp
		lp += (noise - lp) * 0.08                     # soft, low and breathy
		lp2 += (lp - lp2) * 0.15
		var s := clampf(lp2 * 5.5 * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


# ---- shapes (the same little helpers the cat was first modelled with)

static func _fur(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.5
	return m


static func _ell(parent: Node3D, pos: Vector3, radii: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 28
	sm.rings = 14
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = radii
	parent.add_child(mi)
	return mi


static func _capsule(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 20
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cone(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos + Vector3(0, height * 0.5, 0)
	parent.add_child(mi)
	return mi
