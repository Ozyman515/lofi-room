extends RefCounted
## The kaiju: a snarling, upright tyrannosaur in white, with a jagged crest of blue ice crystals running from
## its neck down its back and round the U of its tail, more ice spikes along its forearms, curled talons, and
## jaws held open on rows of teeth, head tipped up toward the sky. The meshes are baked from the
## owner's 3D-print design (pack/trex: gamemesh.py makes the data, bake.gd writes res://kaiju/*/*.res).
## Pivots that move, as kaiju.gd expects: LegL/LegR (thigh) > Knee (shin and foot), ArmL/ArmR, Head > Jaw.
## Faces +x, about 1 unit tall (the caller scales it up to building size). build(true) gives the lighter
## version used for the little toy on the nightstand.

const WHITE := Color(0.93, 0.94, 0.96)
const TOOTH := Color(0.97, 0.96, 0.90)
const TONGUE := Color(0.14, 0.19, 0.38)
const ICE_GLOW := Color(0.35, 0.75, 1.0)
const EYE := Color(0.13, 0.40, 0.95)            # the eyes: the deep blue of the crest's crystals, no pupils (reads from afar)
const EYE_AT := Vector3(0.214, 0.152, 0.043)   # the eye sockets (head space; z mirrored for the other side)
const BOXY := 0.75                              # how far the skull's rounded top is squared off (0 = as baked)
const BACK_FLAT := 0.35                         # ...and its rounded back (side on), very slightly
const BACK_X := 0.06                            # (the back of the skull: behind this, above BACK_Y, out to XMIN / YMAX)
const BACK_Y := 0.06
const XMIN := -0.11
const YMAX := 0.2

# pivots (body space), from the bake
const HEAD := Vector3(0.356, 0.784, 0.0)
const JAW := Vector3(0.379476, 0.78899, 0.0)
const LEG := {"L": Vector3(0.156, 0.448, -0.12), "R": Vector3(0.076, 0.448, 0.12)}
const KNEE := {"L": Vector3(0.284, 0.256, -0.144), "R": Vector3(0.204, 0.256, 0.144)}
const ARM := {"L": Vector3(0.316, 0.608, -0.104), "R": Vector3(0.316, 0.608, 0.104)}


static func build(toy := false) -> Node3D:
	var dir := "res://kaiju/toy/" if toy else "res://kaiju/full/"
	var skin := _m(WHITE, 0.45)
	var tooth := _m(TOOTH, 0.3)
	var tongue := _m(TONGUE, 0.6)
	var ice := _ice()
	var root := Node3D.new()

	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var bmi := _part(body, dir + "body.res", skin)
	var smi := _part(body, dir + "spikes.res", ice)
	if not toy:
		_rig_tail(body, [bmi, smi])

	var head := Node3D.new()
	head.name = "Head"
	head.position = HEAD
	body.add_child(head)
	var hm := _part(head, dir + "head.res", skin)
	hm.mesh = _boxy_head(hm.mesh)
	_part(head, dir + "teeth_up.res", tooth)
	_head_detail(head, ice)
	var jaw := Node3D.new()
	jaw.name = "Jaw"
	jaw.position = JAW - HEAD
	head.add_child(jaw)
	_part(jaw, dir + "jaw.res", skin)
	_part(jaw, dir + "tongue.res", tongue)
	_part(jaw, dir + "teeth_lo.res", tooth)

	for s in ["L", "R"]:
		var leg := Node3D.new()
		leg.name = "Leg" + s
		leg.position = LEG[s]
		body.add_child(leg)
		_part(leg, dir + "thigh%s.res" % s, skin)
		var knee := Node3D.new()
		knee.name = "Knee"
		knee.position = KNEE[s] - LEG[s]
		leg.add_child(knee)
		_part(knee, dir + "shin%s.res" % s, skin)
		var arm := Node3D.new()
		arm.name = "Arm" + s
		arm.position = ARM[s]
		body.add_child(arm)
		_part(arm, dir + "arm%s.res" % s, skin)
		_part(arm, dir + "armspikes%s.res" % s, ice)
	return root


# ---- the tail: a skeleton of five joints down its middle (from the hips, along the ground, up into the curl at the
# end), the body and its ice crest skinned to it with smooth weights, so it can swing without cracking

const TAIL_PTS := [Vector2(-0.06, 0.40), Vector2(-0.24, 0.25), Vector2(-0.41, 0.12), Vector2(-0.57, 0.07),
	Vector2(-0.69, 0.13), Vector2(-0.72, 0.48)]       # the joints (x, y), the last one the tip
static var _skinned := {}                          # mesh path -> the skinned copy (built once)


static func _rig_tail(body: Node3D, parts: Array) -> void:
	var sk := Skeleton3D.new()
	sk.name = "Tail"
	body.add_child(sk)
	sk.add_bone("root")
	var prev := Vector3.ZERO
	for i in 5:
		var p: Vector2 = TAIL_PTS[i]
		var at := Vector3(p.x, p.y, 0.0)
		var b := sk.add_bone("tail%d" % (i + 1))
		sk.set_bone_parent(b, b - 1)
		sk.set_bone_rest(b, Transform3D(Basis.IDENTITY, at - prev))
		prev = at
	sk.reset_bone_poses()
	var skin := Skin.new()
	for b in sk.get_bone_count():
		skin.add_named_bind(sk.get_bone_name(b), sk.get_bone_global_rest(b).affine_inverse())
	for k in parts.size():
		var mi: MeshInstance3D = parts[k]
		var key := mi.mesh.resource_path
		if not _skinned.has(key):
			_skinned[key] = _skin_mesh(mi.mesh, k > 0)      # (the crest: each spike moves whole)
		mi.mesh = _skinned[key]
		mi.skin = skin
		mi.skeleton = mi.get_path_to(sk)


# where a point sits along the tail: 0 at the hips' joint .. 5 at the tip (or < 0, in the body)
static func _along(x: float, y: float) -> float:
	var q := Vector2(x, y)
	var best := 1e9
	var s := -1.0
	for i in 5:
		var a: Vector2 = TAIL_PTS[i]
		var b: Vector2 = TAIL_PTS[i + 1]
		var ab := b - a
		var u := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var dd := q.distance_squared_to(a + ab * u)
		if dd < best:
			best = dd
			s = float(i) + u
	# in front of the first joint (the body and hips) it isn't the tail
	var d0: Vector2 = TAIL_PTS[1] - TAIL_PTS[0]
	var ahead := (q - (TAIL_PTS[0] as Vector2)).dot(d0.normalized())
	return minf(s, ahead / d0.length()) if ahead < 0.0 else s


# the separate pieces of a mesh (triangles that share corners): for each vertex, the index of its piece's base,
# the corner nearest the tail's middle line (where a spike grows out of the body)
static func _piece_bases(v: PackedVector3Array, idx: PackedInt32Array) -> PackedInt32Array:
	var parent: Array[int] = []
	parent.resize(v.size())
	for n in v.size():
		parent[n] = n
	var at := {}
	for n in v.size():                                   # corners at the same spot are one corner
		var key := v[n].snapped(Vector3.ONE * 0.0001)
		if at.has(key):
			parent[_root(parent, n)] = _root(parent, int(at[key]))
		else:
			at[key] = n
	for t in range(0, idx.size(), 3):                    # and a triangle's corners are one piece
		var r0 := _root(parent, idx[t])
		for c in [1, 2]:
			var rc := _root(parent, idx[t + c])
			if rc != r0:
				parent[rc] = r0
	var best := {}
	var bd := {}
	for n in v.size():
		var r := _root(parent, n)
		var d := _off_line(v[n].x, v[n].y)
		if not bd.has(r) or d < float(bd[r]):
			bd[r] = d
			best[r] = n
	var out := PackedInt32Array()
	out.resize(v.size())
	for n in v.size():
		out[n] = int(best[_root(parent, n)])
	return out


static func _root(parent: Array[int], a: int) -> int:
	while parent[a] != a:
		parent[a] = parent[parent[a]]
		a = parent[a]
	return a


# how far a point is from the tail's middle line (x, y)
static func _off_line(x: float, y: float) -> float:
	var q := Vector2(x, y)
	var best := 1e9
	for i in 5:
		var a: Vector2 = TAIL_PTS[i]
		var b: Vector2 = TAIL_PTS[i + 1]
		var ab := b - a
		var u := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * u))
	return best


static func _skin_mesh(src: Mesh, rigid := false) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var v := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(v.size() * 4)
		weights.resize(v.size() * 4)
		var base := PackedInt32Array()
		if rigid:
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx == null:
				idx = PackedInt32Array(range(v.size()))
			base = _piece_bases(v, idx)
		for n in v.size():
			# joint k bends what's past it: a vertex at s gets bone floor(s)+1, blended into the one before
			# over the first 40% of the segment, so the bends are soft; a spike takes its base's weights whole
			var p := v[base[n]] if rigid else v[n]
			var s := _along(p.x, p.y)
			var b0 := 0
			var b1 := 0
			var w1 := 0.0
			if s > -0.4:
				var seg := clampi(int(floor(s)), -1, 4)
				var u := s - float(seg)
				if seg < 0:                                  # the hips: half-way onto the first joint at most
					b1 = 1
					w1 = 0.5 * smoothstep(-0.4, 0.0, s)
				elif seg == 0:
					b1 = 1
					w1 = lerpf(0.5, 1.0, smoothstep(0.0, 0.4, u))
				else:
					b1 = seg + 1                             # 2 .. 5
					b0 = seg
					w1 = smoothstep(0.0, 0.4, u)
			bones[n * 4] = b1
			bones[n * 4 + 1] = b0
			weights[n * 4] = w1
			weights[n * 4 + 1] = 1.0 - w1
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


# ---- the head: a boxier skull (the top squared off, brow ridges over the eyes), eyes that glow, little horns

static var _boxed := {}


static func _boxy_head(src: Mesh) -> Mesh:
	var key := src.resource_path
	if _boxed.has(key):
		return _boxed[key]
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var v := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		# per slice along the head (x): the middle height, the half height above it and the half width
		var lo := {}
		var hi := {}
		var wd := {}
		for p in v:
			var b := int(floor(p.x / 0.02))
			lo[b] = minf(lo.get(b, 9.0), p.y)
			hi[b] = maxf(hi.get(b, -9.0), p.y)
			wd[b] = maxf(wd.get(b, 0.0), absf(p.z))
		for n in v.size():
			var p := v[n]
			var b := int(floor(p.x / 0.02))
			var cy: float = (float(lo[b]) + float(hi[b])) * 0.5
			var hy: float = maxf(float(hi[b]) - cy, 0.01)
			var hz: float = maxf(float(wd[b]), 0.01)
			var uy := (p.y - cy) / hy
			var uz := p.z / hz
			if uy <= 0.0:
				continue                                   # the mouth line and below stay as they are (teeth, jaw)
			var r := Vector2(uz, uy).length()
			if r < 0.001:
				continue
			var c := absf(uz) / r
			var sn := uy / r
			var k := 1.0 / pow(pow(c, 4.0) + pow(sn, 4.0), 0.25)           # circle -> rounded square
			var g := smoothstep(0.0, 0.5, uy) * smoothstep(-0.12, 0.0, p.x) * (1.0 - smoothstep(0.24, 0.31, p.x))
			var kk := lerpf(1.0, k, BOXY * g)
			var q := Vector3(p.x, cy + uy * kk * hy, uz * kk * hz)
			# the back of the skull: its rounded top-back corner squared off a touch (side on)
			if p.x < BACK_X and q.y > BACK_Y:
				var bu := (p.x - BACK_X) / (BACK_X - XMIN)
				var bw := (q.y - BACK_Y) / (YMAX - BACK_Y)
				var br := Vector2(bu, bw).length()
				if br > 0.001:
					var bc := absf(bu) / br
					var bs := bw / br
					var bk := lerpf(1.0, 1.0 / pow(pow(bc, 4.0) + pow(bs, 4.0), 0.25), BACK_FLAT * smoothstep(0.2, 0.7, br))
					q.x = BACK_X + bu * bk * (BACK_X - XMIN)
					q.y = BACK_Y + bw * bk * (YMAX - BACK_Y)
			v[n] = q
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = null
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.generate_normals()
		st.commit(out)
	_boxed[key] = out
	return out


static func _head_detail(head: Node3D, horn_mat: Material) -> void:
	var em := StandardMaterial3D.new()
	em.albedo_color = EYE
	em.emission_enabled = true
	em.emission = EYE
	em.emission_energy_multiplier = 1.3
	em.roughness = 0.2
	em.disable_fog = true
	for sd in [1.0, -1.0]:
		var at := Vector3(EYE_AT.x, EYE_AT.y, EYE_AT.z * sd)
		var eye := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.044
		sm.radial_segments = 14
		sm.rings = 7
		eye.mesh = sm
		eye.material_override = em
		eye.position = at + Vector3(0.0, -0.004, 0.0)
		head.add_child(eye)
		# a little horn on the brow over each eye, swept back and a little out (the base sits on the skull)
		var pivot := Node3D.new()
		pivot.position = Vector3(0.178, 0.186, 0.056 * sd)
		pivot.rotation = Vector3(0.3 * sd, 0.0, 0.62)
		head.add_child(pivot)
		var horn := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.019
		cm.height = 0.075
		cm.radial_segments = 10
		horn.mesh = cm
		horn.material_override = horn_mat
		horn.position = Vector3(0.0, 0.0375, 0.0)
		pivot.add_child(horn)


static func _part(parent: Node3D, path: String, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = load(path)
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _m(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.5
	m.disable_fog = true                            # stays a crisp shape in the city haze
	return m


# blue ice: deep blue at the root to pale cyan at the tips (vertex colours), glossy, with a soft glow so the
# crest still reads against the night sky
static func _ice() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.roughness = 0.12
	m.metallic = 0.15
	m.metallic_specular = 0.8
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	m.emission_enabled = true
	m.emission = ICE_GLOW
	m.emission_energy_multiplier = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED      # thin blades: both sides show
	m.disable_fog = true
	return m
