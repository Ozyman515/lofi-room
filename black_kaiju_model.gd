extends RefCounted
## The black kaiju: the room's first monster (it walked past the window before the white T-Rex took over), kept
## for the fight (fight.gd), where it turns up when the other two fight to a draw.
## An original giant monster: a hunched, two-legged reptile with a big,
## deep tyrannosaur-style head (heavy brows, rows of teeth) crowned with swept-back horns and a fanned frill,
## long clawed arms, thick legs and a heavy tail. Rounded knobs run down its back. Neon stripes glow along its flanks and throat, the same
## colours as the city's signs. The body is one smooth tube from the tail tip to the snout; the limbs are
## tubes too, on pivots that move: LegL/LegR (thigh) > Knee (shin and foot), ArmL/ArmR, Head > Jaw.
## Faces +x, about 1 unit tall (the caller scales it up to building size).

const SKIN := Color(0.10, 0.12, 0.14)
const BELLY := Color(0.22, 0.20, 0.19)
const HORN := Color(0.32, 0.29, 0.26)
const GLOW := Color(1.0, 0.25, 0.75)
const GLOW2 := Color(0.25, 0.85, 1.0)


static func build() -> Node3D:
	var root := Node3D.new()
	var skin := _m(SKIN, 0.7)
	var belly := _m(BELLY, 0.8)
	var horn := _m(HORN, 0.5)
	var glow := _glow(GLOW, 4.0)
	var glow2 := _glow(GLOW2, 3.0)

	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	# the spine, tail tip to snout tip: [x, y, half width, half height]
	var spine := [
		[-1.00, 0.04, 0.012, 0.012], [-0.80, 0.10, 0.04, 0.035], [-0.55, 0.22, 0.08, 0.07], [-0.28, 0.38, 0.12, 0.115],
		[0.0, 0.48, 0.15, 0.16], [0.18, 0.58, 0.155, 0.17], [0.32, 0.69, 0.13, 0.135], [0.42, 0.79, 0.095, 0.10],
		[0.50, 0.84, 0.085, 0.105], [0.58, 0.845, 0.07, 0.095], [0.66, 0.835, 0.058, 0.08], [0.73, 0.82, 0.048, 0.062],
		[0.775, 0.81, 0.034, 0.042],
	]
	var pts: Array[Vector3] = []
	var rw: Array[float] = []
	var rh: Array[float] = []
	for i in spine.size() - 1:
		for k in 8:
			var t := k / 8.0
			var p0: Array = spine[maxi(i - 1, 0)]
			var p1: Array = spine[i]
			var p2: Array = spine[i + 1]
			var p3: Array = spine[mini(i + 2, spine.size() - 1)]
			var v := []
			for c in 4:
				v.append(_catmull(float(p0[c]), float(p1[c]), float(p2[c]), float(p3[c]), t))
			pts.append(Vector3(v[0], v[1], 0))
			rw.append(v[2])
			rh.append(v[3])
	var last: Array = spine[spine.size() - 1]
	pts.append(Vector3(last[0], last[1], 0))
	rw.append(0.004)
	rh.append(0.004)
	rw[0] = 0.003
	rh[0] = 0.003
	body.add_child(_tube(pts, rw, rh, skin))
	# paler belly and throat: a slimmer tube under the chest
	body.add_child(_tube([Vector3(-0.1, 0.42, 0), Vector3(0.1, 0.5, 0), Vector3(0.28, 0.62, 0), Vector3(0.4, 0.72, 0)] as Array[Vector3],
		[0.11, 0.13, 0.11, 0.06] as Array[float], [0.10, 0.12, 0.10, 0.05] as Array[float], belly, Vector3(0.012, -0.03, 0)))
	# knobs down the back and tail, biggest over the shoulders
	for k in 14:
		var u := k / 13.0
		var idx := int(lerpf(12.0, pts.size() * 0.66, u))
		var p := pts[idx]
		var r := 0.012 + 0.03 * sin(u * PI) * (0.6 + 0.4 * u)
		_ell(body, p + Vector3(0, rh[idx] * 0.92, 0), Vector3(r, r * 0.85, r * 0.9), horn)
	# neon stripes along each flank
	for sz in [-1.0, 1.0]:
		for k in 6:
			var p := Vector3(-0.12 + k * 0.08, 0.44 + k * 0.045, 0)
			var st := _ell(body, p + Vector3(0, 0, sz * (0.145 - abs(k - 2.5) * 0.008)), Vector3(0.035, 0.008, 0.005), glow)
			st.rotation.z = 0.55

	# the head: a big tyrannosaur-style skull (the body tube above makes its shape) with heavy brows, a deep
	# lower jaw on a pivot, rows of teeth, glowing eyes and throat
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.5, 0.84, 0)
	body.add_child(head)
	var tooth := _m(Color(0.85, 0.82, 0.74), 0.4)
	var jaw := Node3D.new()
	jaw.name = "Jaw"
	jaw.position = Vector3(0.02, -0.07, 0)
	head.add_child(jaw)
	jaw.add_child(_tube([Vector3(-0.02, 0.0, 0), Vector3(0.08, -0.006, 0), Vector3(0.17, -0.004, 0), Vector3(0.25, 0.006, 0)] as Array[Vector3],
		[0.075, 0.062, 0.05, 0.03] as Array[float], [0.045, 0.04, 0.032, 0.02] as Array[float], belly))
	for sz in [-1.0, 1.0]:
		for t in 7:                                                                                # teeth along both jaws
			var tx := 0.06 + t * 0.03
			var up := _cone(head, Vector3(tx, -0.072 + t * 0.002, sz * (0.052 - t * 0.003)), 0.006, 0.028, tooth)
			up.rotation.z = PI                                                                    # upper teeth point down
			_cone(jaw, Vector3(tx - 0.02, 0.02, sz * (0.05 - t * 0.003)), 0.005, 0.022, tooth)  # lower teeth point up
		# heavy brow ridge over each eye, the eye set deep under it
		var brow := _ell(head, Vector3(0.05, 0.075, sz * 0.055), Vector3(0.045, 0.02, 0.024), skin)
		brow.rotation.z = -0.25
		_ell(head, Vector3(0.065, 0.05, sz * 0.074), Vector3(0.02, 0.012, 0.008), glow)            # eyes
		_ell(head, Vector3(0.26, 0.02, sz * 0.032), Vector3(0.01, 0.006, 0.004), _m(Color(0.02, 0.02, 0.03), 0.9))   # nostrils
		_ell(head, Vector3(-0.04, -0.01, sz * 0.085), Vector3(0.05, 0.05, 0.01), skin)              # jaw muscles at the back of the skull
	_ell(head, Vector3(-0.06, -0.08, 0), Vector3(0.07, 0.04, 0.06), glow2)                         # glowing throat
	# the fanned frill behind the jaw, with its glowing rim
	for sz in [-1.0, 1.0]:
		var fr := _ell(head, Vector3(-0.1, 0.0, sz * 0.085), Vector3(0.055, 0.09, 0.006), skin)
		fr.rotation.y = sz * 0.6
		for t in 5:
			var a := -1.1 + t * 0.55
			_ell(head, Vector3(-0.12 + cos(a) * 0.05, sin(a) * 0.085, sz * 0.105), Vector3(0.008, 0.008, 0.004), glow2)
	# the crown of horns, swept back off the top of the skull
	for h in [[Vector3(-0.04, 0.09, 0.04), 0.12, 0.014], [Vector3(-0.04, 0.09, -0.04), 0.12, 0.014],
			[Vector3(-0.07, 0.07, 0.065), 0.08, 0.01], [Vector3(-0.07, 0.07, -0.065), 0.08, 0.01], [Vector3(0.03, 0.095, 0.0), 0.05, 0.009]]:
		var c := _cone(head, h[0], h[2], h[1], horn)
		c.rotation = Vector3(sign(h[0].z) * -0.25, 0.0, 1.2)
	# knobbly ridge from the brows back over the skull
	for k in 4:
		_ell(head, Vector3(0.0 - k * 0.04, 0.1 - k * 0.006, 0), Vector3(0.016, 0.012, 0.014), horn)

	# legs: a thigh on the hip pivot, a shin and three-toed foot on the knee pivot
	for sz in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegL" if sz < 0.0 else "LegR"
		leg.position = Vector3(0.02, 0.44, sz * 0.12)
		body.add_child(leg)
		leg.add_child(_tube([Vector3(0, 0.02, 0), Vector3(0.06, -0.08, 0), Vector3(0.09, -0.2, 0)] as Array[Vector3],
			[0.1, 0.09, 0.06] as Array[float], [0.11, 0.09, 0.06] as Array[float], skin))
		var knee := Node3D.new()
		knee.name = "Knee"
		knee.position = Vector3(0.09, -0.2, 0)
		leg.add_child(knee)
		knee.add_child(_tube([Vector3(0, 0, 0), Vector3(-0.06, -0.1, 0), Vector3(-0.08, -0.2, 0), Vector3(-0.02, -0.24, 0), Vector3(0.12, -0.24, 0)] as Array[Vector3],
			[0.058, 0.048, 0.042, 0.05, 0.03] as Array[float], [0.058, 0.048, 0.04, 0.025, 0.018] as Array[float], skin))
		for t in 3:
			var toe := _cone(knee, Vector3(0.14, -0.245, (t - 1) * 0.03), 0.012, 0.05, horn)
			toe.rotation.z = -PI / 2.0

	# arms: long, hanging forward, three big claws
	for sz in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "ArmL" if sz < 0.0 else "ArmR"
		arm.position = Vector3(0.3, 0.66, sz * 0.12)
		body.add_child(arm)
		arm.add_child(_tube([Vector3(0, 0, 0), Vector3(0.04, -0.1, 0), Vector3(0.1, -0.16, 0), Vector3(0.16, -0.2, 0)] as Array[Vector3],
			[0.04, 0.03, 0.026, 0.02] as Array[float], [0.04, 0.03, 0.026, 0.018] as Array[float], skin))
		for c in 3:
			var cl := _cone(arm, Vector3(0.18, -0.22, (c - 1) * 0.016), 0.008, 0.055, horn)
			cl.rotation.z = PI * 0.78
	return root


static func _catmull(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# a smooth tube through `pts` (in the x/y plane), elliptical: rw across, rh up and down
static func _tube(pts: Array[Vector3], rw: Array[float], rh: Array[float], mat: Material, shift := Vector3.ZERO) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := 18
	var cnt := pts.size()
	for i in cnt:
		var t := (pts[mini(i + 1, cnt - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var up := Vector3(-t.y, t.x, 0).normalized()             # perpendicular in the side plane
		var side := Vector3(0, 0, 1)
		for j in ring + 1:
			var ph := TAU * j / ring
			st.add_vertex(pts[i] + shift + up * sin(ph) * rh[i] + side * cos(ph) * rw[i])
	for i in cnt - 1:
		for j in ring:
			var a := i * (ring + 1) + j
			var b := a + ring + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	# caps at both ends (the tube may end fat, like a jaw root)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func _m(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.4
	m.rim_tint = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED      # open tube ends never show a hole
	m.disable_fog = true                            # it reads as a dark shape in the city haze, not a faded one
	return m


static func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	return m


static func _ell(parent: Node3D, pos: Vector3, radii: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = radii
	parent.add_child(mi)
	return mi


static func _cone(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
