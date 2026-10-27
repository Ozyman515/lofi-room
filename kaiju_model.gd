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
	_part(head, dir + "head.res", skin)
	_part(head, dir + "teeth_up.res", tooth)
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
	for mi: MeshInstance3D in parts:
		var key := mi.mesh.resource_path
		if not _skinned.has(key):
			_skinned[key] = _skin_mesh(mi.mesh)
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


static func _skin_mesh(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var v := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(v.size() * 4)
		weights.resize(v.size() * 4)
		for n in v.size():
			# joint k bends what's past it: a vertex at s gets bone floor(s)+1, blended into the one before
			# over the first 40% of the segment, so the bends are soft
			var s := _along(v[n].x, v[n].y)
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
