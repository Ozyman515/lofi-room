extends RefCounted
## King Gaboon: the owner's own monster, a giant mandrill (a big monkey). He walks on his knuckles with a huge
## hunched chest and shaggy olive fur, a red ridge down his long snout, blue ridged cheeks, a gold beard and
## cheek fur, long canines and a big curled tail. The fur is smooth with a few large swept-back locks
## (no bumpy or clustered textures anywhere).
## Pivots that move: Body (at the hips) > Head > Muzzle > Jaw, Body > ArmL/ArmR > Elbow, Body > Tail,
## and LegL/LegR > Knee on the rig itself so the feet stay planted when he rears up.
## Faces +x and is about 1 unit tall like kaiju_model.gd (the caller scales him).
## Everything is authored in metres facing +z (4.3 m tall) inside "Rig", which turns and shrinks it.

const HEIGHT := 4.3

const FUR := Color(0.37, 0.34, 0.26)
const FUR_DARK := Color(0.26, 0.24, 0.18)
const FUR_LIGHT := Color(0.49, 0.45, 0.33)
const GOLD := Color(0.82, 0.68, 0.23)
const SKIN := Color(0.23, 0.20, 0.20)
const RED := Color(0.78, 0.12, 0.16)
const BLUE := Color(0.16, 0.52, 0.84)
const BLUE_HI := Color(0.35, 0.71, 0.95)
const LIP := Color(0.66, 0.20, 0.27)
const EYE := Color(0.88, 0.64, 0.23)
const BLACK := Color(0.05, 0.04, 0.04)
const CLAW := Color(0.15, 0.13, 0.12)
const FANG := Color(0.90, 0.86, 0.76)

var _origin := {}          # pivot node -> its position in model space, so parts can be placed in model space
var M := {}


static func build() -> Node3D:
	return new()._build()


func _build() -> Node3D:
	M = {
		"fur": _m(FUR, 0.9), "dark": _m(FUR_DARK, 0.9), "light": _m(FUR_LIGHT, 0.9), "gold": _m(GOLD, 0.85),
		"skin": _m(SKIN, 0.7), "red": _m(RED, 0.4), "blue": _m(BLUE, 0.4), "blue_hi": _m(BLUE_HI, 0.35),
		"lip": _m(LIP, 0.5), "eye": _m(EYE, 0.25), "black": _m(BLACK, 0.3), "claw": _m(CLAW, 0.45),
		"fang": _m(FANG, 0.35),
	}
	for k in ["red", "blue", "blue_hi", "gold", "eye"]:      # his face colours glow a touch so they read at night
		var mm: StandardMaterial3D = M[k]
		mm.emission_enabled = true
		mm.emission = mm.albedo_color
		mm.emission_energy_multiplier = 0.35
	var root := Node3D.new()
	root.name = "KingGaboon"
	var rig := Node3D.new()
	rig.name = "Rig"
	rig.rotation.y = PI / 2.0                  # authored facing +z; the room expects +x
	rig.scale = Vector3.ONE / HEIGHT
	root.add_child(rig)
	_origin[rig] = Vector3.ZERO

	var body := _pivot(rig, "Body", Vector3(0, 2.0, -1.0))
	_ell(body, "fur", Vector3(0, 2.55, -0.15), Vector3(1.15, 1.15, 1.35), Vector3(-0.4, 0, 0))
	_ell(body, "fur", Vector3(0, 2.95, 0.55), Vector3(1.25, 0.95, 0.85)).name = "Chest"
	_ell(body, "light", Vector3(0, 2.05, 0.2), Vector3(0.85, 0.75, 0.85))
	_ell(body, "fur", Vector3(0, 2.0, -1.05), Vector3(0.85, 0.85, 0.8))
	_ell(body, "fur", Vector3(0, 3.3, 1.0), Vector3(0.58, 0.55, 0.55))
	for s: float in [1.0, -1.0]:
		_ell(body, "fur", Vector3(1.12 * s, 3.1, 0.5), Vector3(0.58, 0.62, 0.58))

	# ---- arms: shoulder pivot (upper arm), elbow pivot (forearm, fist, fingers, claws)
	for s: float in [1.0, -1.0]:
		var x := 1.35 * s
		var arm := _pivot(body, "ArmL" if s > 0 else "ArmR", Vector3(1.15 * s, 3.1, 0.55))
		_tube(arm, "fur", [Vector3(1.15 * s, 3.1, 0.55), Vector3(1.38 * s, 2.45, 0.8), Vector3(1.45 * s, 1.85, 0.95)], 0.48, 0.38)
		var elbow := _pivot(arm, "Elbow", Vector3(1.45 * s, 1.85, 0.95))
		_tube(elbow, "fur", [Vector3(1.45 * s, 1.85, 0.95), Vector3(1.42 * s, 1.2, 1.18), Vector3(x, 0.55, 1.35)], 0.41, 0.28, 0.04)
		_cone(elbow, "dark", Vector3(0.03 * s, 0.1, -0.1) + Vector3(1.45 * s, 1.85, 0.95), Vector3(0.3 * s, -0.6, -1.0), 0.2, 0.55)
		# the open hand he walks on ("Fingers"), and the same hand balled into a fist ("Fist") for fighting
		var open_hand := _pivot(elbow, "Fingers", Vector3(1.45 * s, 1.85, 0.95))
		_ell(open_hand, "skin", Vector3(x, 0.3, 1.47), Vector3(0.32, 0.28, 0.36))
		for k in 4:
			var o := (k - 1.5) * 0.15 * s
			_tube(open_hand, "skin", [Vector3(x + o, 0.42, 1.68), Vector3(x + o, 0.24, 1.86), Vector3(x + o, 0.07, 1.88)], 0.085, 0.065, 0.0, 10, 12)
			_cone(open_hand, "claw", Vector3(x + o, 0.06, 1.9), Vector3(0, -0.3, 1), 0.05, 0.16)
		_tube(open_hand, "skin", [Vector3(x - 0.26 * s, 0.35, 1.5), Vector3(x - 0.34 * s, 0.18, 1.66), Vector3(x - 0.32 * s, 0.07, 1.74)], 0.08, 0.06, 0.0, 8, 12)
		var fist := _pivot(elbow, "Fist", Vector3(1.45 * s, 1.85, 0.95))
		fist.visible = false
		_ell(fist, "skin", Vector3(x, 0.32, 1.45), Vector3(0.36, 0.34, 0.36))                          # the ball of the fist
		_tube(fist, "skin", [Vector3(x + 0.27 * s, 0.42, 1.62), Vector3(x, 0.45, 1.7), Vector3(x - 0.27 * s, 0.42, 1.62)], 0.14, 0.14, 0.0, 10, 12)   # the curled fingers, knuckles forward
		_tube(fist, "skin", [Vector3(x + 0.25 * s, 0.24, 1.6), Vector3(x, 0.2, 1.7), Vector3(x - 0.25 * s, 0.24, 1.6)], 0.12, 0.12, 0.0, 10, 12)
		_tube(fist, "skin", [Vector3(x - 0.3 * s, 0.38, 1.4), Vector3(x - 0.3 * s, 0.28, 1.6), Vector3(x - 0.12 * s, 0.22, 1.76)], 0.08, 0.065, 0.0, 8, 12)   # the thumb across the front

	# ---- legs: hip pivot (thigh), knee pivot (shin, foot, toes); on the rig so the feet stay put
	for s: float in [1.0, -1.0]:
		var leg := _pivot(rig, "LegL" if s > 0 else "LegR", Vector3(0.6 * s, 1.95, -1.0))
		_tube(leg, "fur", [Vector3(0.6 * s, 1.95, -1.0), Vector3(0.8 * s, 1.55, -0.65), Vector3(0.86 * s, 1.12, -0.45)], 0.47, 0.33)
		var knee := _pivot(leg, "Knee", Vector3(0.86 * s, 1.12, -0.45))
		_tube(knee, "fur", [Vector3(0.86 * s, 1.12, -0.45), Vector3(0.85 * s, 0.7, -0.68), Vector3(0.8 * s, 0.3, -0.85)], 0.33, 0.22)
		_ell(knee, "skin", Vector3(0.8 * s, 0.14, -0.6), Vector3(0.3, 0.14, 0.5))
		for k in 4:
			var o := (k - 1.5) * 0.14 * s
			_tube(knee, "skin", [Vector3(0.8 * s + o, 0.12, -0.25), Vector3(0.8 * s + o, 0.09, -0.08)], 0.07, 0.06, 0.0, 6, 12)
			_cone(knee, "claw", Vector3(0.8 * s + o, 0.07, -0.04), Vector3(0, -0.4, 1), 0.045, 0.13)
		_cone(body, "dark", Vector3(0.75 * s, 2.15, -1.2), Vector3(0.4 * s, -0.5, -1), 0.2, 0.5)

	# ---- the big curled tail
	var tail := _pivot(body, "Tail", Vector3(0, 2.2, -1.6))
	var tp := [Vector3(0, 2.2, -1.6), Vector3(0, 2.45, -2.1), Vector3(-0.3, 2.65, -2.8), Vector3(-1.0, 2.35, -3.3),
		Vector3(-1.7, 1.55, -3.2), Vector3(-2.0, 0.8, -2.6), Vector3(-2.0, 0.4, -1.9)]
	_tube_fn(tail, "fur", tp, func(u: float) -> float: return (0.2 + 0.25 * sin(PI * u)) * (1.0 - pow(u, 6.0)) + 0.03, 60, 20)

	# ---- mane: a few big swept-back locks over the shoulders and back
	var c := Vector3(0, 2.95, 0.4)
	var sc := Vector3(1.3, 1.02, 0.95)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 0
	for i in 160:
		if n >= 34:
			break
		var y := 1.0 - (i / 159.0) * 2.0
		var rr := sqrt(1.0 - y * y)
		var th := i * 2.39996
		var d := Vector3(cos(th) * rr, y, sin(th) * rr)
		if d.y < 0.15 or d.z > 0.55:
			continue
		var p := c + sc * d * 0.92
		var nrm := (d / sc).normalized()
		var dir := (nrm + Vector3(0, -0.35, -0.9)).normalized()
		_cone(body, "fur" if n % 3 else "dark", p, dir, 0.17 + rng.randf() * 0.08, 0.6 + rng.randf() * 0.35)
		n += 1

	# ---- head
	var head := _pivot(body, "Head", Vector3(0, 3.3, 1.0))
	_ell(head, "fur", Vector3(0, 3.55, 1.35), Vector3(0.58, 0.56, 0.55))
	_ell(head, "dark", Vector3(0, 3.78, 1.18), Vector3(0.62, 0.48, 0.62))
	_cone(head, "dark", Vector3(0, 3.95, 1.1), Vector3(0, 0.5, -1), 0.28, 0.6)
	_ell(head, "skin", Vector3(0, 3.55, 1.72), Vector3(0.4, 0.3, 0.24))
	_tube(head, "light", [Vector3(-0.32, 3.68, 1.8), Vector3(0, 3.74, 1.9), Vector3(0.32, 3.68, 1.8)], 0.075, 0.075, 0.0, 12, 12)
	for s: float in [1.0, -1.0]:
		_ell(head, "skin", Vector3(0.55 * s, 3.62, 1.25), Vector3(0.08, 0.12, 0.1))
		_ell(head, "eye", Vector3(0.17 * s, 3.6, 1.9), Vector3(0.065, 0.06, 0.06))
		_ell(head, "black", Vector3(0.17 * s, 3.6, 1.955), Vector3(0.033, 0.033, 0.02))
		_ell(head, "gold", Vector3(0.38 * s, 3.36, 1.5), Vector3(0.21, 0.29, 0.23))
	_ell(head, "gold", Vector3(0, 3.15, 1.72), Vector3(0.36, 0.22, 0.28))
	_tube(head, "gold", [Vector3(0, 3.18, 1.75), Vector3(0, 2.85, 1.95), Vector3(0, 2.5, 2.08)], 0.33, 0.03, 0.0, 16, 18)

	# the snout: its own frame tipped nose-down, local +z runs to the nose
	var mz := Node3D.new()
	mz.name = "Muzzle"
	head.add_child(mz)
	mz.position = Vector3(0, 3.33, 2.2) - _origin[head]
	mz.rotation.x = 0.45
	_origin[mz] = null                                   # parts inside the snout use its local frame
	var mx := 0.26
	var my := 0.23
	var mzr := 0.5
	_ell(mz, "blue", Vector3.ZERO, Vector3(mx, my, mzr))
	_ell(mz, "red", Vector3(0, 0.13, 0.02), Vector3(0.11, 0.13, 0.5))
	for s: float in [1.0, -1.0]:
		for y: float in [0.09, 0.02, -0.05, -0.12]:
			var pts: Array = []
			var t := -0.36
			while t <= 0.361:
				var inside := 1.0 - pow(y / my, 2.0) - pow(t / mzr, 2.0)
				pts.append(Vector3((mx * sqrt(maxf(inside, 0.02)) + 0.005) * s, y, t))
				t += 0.09
			_tube_fn(mz, "blue_hi", pts, func(u: float) -> float: return 0.022 * sin(PI * (0.08 + 0.84 * u)) + 0.004, 16, 8, false)
		_cone(mz, "fang", Vector3(0.1 * s, -0.12, 0.28), Vector3(0, -1, 0.15), 0.035, 0.2)
	_ell(mz, "red", Vector3(0, 0.03, 0.48), Vector3(0.14, 0.12, 0.09))
	_ell(mz, "black", Vector3(0.05, -0.01, 0.555), Vector3(0.03, 0.02, 0.015))
	_ell(mz, "black", Vector3(-0.05, -0.01, 0.555), Vector3(0.03, 0.02, 0.015))
	_ell(mz, "lip", Vector3(0, -0.13, 0.12), Vector3(0.2, 0.06, 0.38))
	var jaw := Node3D.new()                              # opens downward from the back of the snout
	jaw.name = "Jaw"
	jaw.position = Vector3(0, -0.15, -0.3)
	mz.add_child(jaw)
	_ell(jaw, "skin", Vector3(0, -0.06, 0.28), Vector3(0.21, 0.09, 0.36))
	_ell(jaw, "black", Vector3(0, 0.0, 0.3), Vector3(0.15, 0.03, 0.3))   # the inside of the mouth shows when it opens
	return root


# ---- helpers; positions are in model space unless the parent is the snout (or its jaw)

func _pivot(parent: Node3D, n: String, at: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = at - _local_origin(parent)
	parent.add_child(p)
	_origin[p] = at
	return p


func _local_origin(parent: Node3D) -> Vector3:
	var o = _origin.get(parent, null)
	return o if o != null else Vector3.ZERO


func _ell(parent: Node3D, mat: String, pos: Vector3, radii: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	mi.material_override = M[mat]
	mi.position = pos - _local_origin(parent)
	mi.rotation = rot
	mi.scale = radii
	parent.add_child(mi)
	return mi


func _cone(parent: Node3D, mat: String, base: Vector3, dir: Vector3, radius: float, length: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = M[mat]
	var d := dir.normalized()
	var q := Quaternion(Vector3.UP, d) if d.dot(Vector3.UP) > -0.999 else Quaternion(Vector3.RIGHT, PI)
	var b := Basis(q)
	mi.transform = Transform3D(b, base - _local_origin(parent) + b.y * (length / 2.0))
	parent.add_child(mi)
	return mi


# radius goes from r0 to r1 along the tube, with an optional bulge in the middle
func _tube(parent: Node3D, mat: String, pts: Array, r0: float, r1: float, bulge := 0.0, seg := 20, ring := 18) -> void:
	_tube_fn(parent, mat, pts, func(u: float) -> float: return lerpf(r0, r1, u) + bulge * sin(PI * u), seg, ring)


# a smooth tube along a Catmull-Rom curve through `pts`; parallel-transported rings, so it never twists
func _tube_fn(parent: Node3D, mat: String, pts: Array, radius: Callable, seg := 20, ring := 18, caps := true) -> void:
	var o := _local_origin(parent)
	var path: Array[Vector3] = []
	var cnt := pts.size()
	for i in cnt - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, cnt - 1)]
		var steps := maxi(2, int(ceil(float(seg) / (cnt - 1))))
		for k in steps:
			path.append(_catmull(p0, p1, p2, p3, float(k) / steps) - o)
	path.append((pts[cnt - 1] as Vector3) - o)
	# radius by distance along the path
	var lens: Array[float] = [0.0]
	for i in range(1, path.size()):
		lens.append(lens[i - 1] + path[i].distance_to(path[i - 1]))
	var total := maxf(lens[lens.size() - 1], 0.0001)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := path.size()
	var tan0 := (path[1] - path[0]).normalized()
	var nrm := tan0.cross(Vector3.UP)
	if nrm.length() < 0.01:
		nrm = tan0.cross(Vector3.RIGHT)
	nrm = nrm.normalized()
	var prev_t := tan0
	for i in n:
		var t := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var ax := prev_t.cross(t)
		if ax.length() > 0.00001:
			nrm = nrm.rotated(ax.normalized(), prev_t.angle_to(t))
		prev_t = t
		var bin := t.cross(nrm).normalized()
		var r: float = radius.call(lens[i] / total)
		for j in ring + 1:
			var a := TAU * j / ring
			var dir := (nrm * cos(a) + bin * sin(a)).normalized()
			st.set_normal(dir)
			st.add_vertex(path[i] + dir * r)
	for i in n - 1:
		for j in ring:
			var a := i * (ring + 1) + j
			var b := a + ring + 1
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(b + 1)
			st.add_index(b)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = M[mat]
	parent.add_child(mi)
	if caps:
		var ra: float = radius.call(0.0)
		var rb: float = radius.call(1.0)
		if ra > 0.015:
			_ell(parent, mat, path[0] + o, Vector3.ONE * ra * 1.04)
		if rb > 0.015:
			_ell(parent, mat, path[n - 1] + o, Vector3.ONE * rb * 1.04)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _m(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true             # reads as a solid shape in the city haze, like the kaiju
	return m
