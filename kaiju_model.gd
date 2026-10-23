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
	_part(body, dir + "body.res", skin)
	_part(body, dir + "spikes.res", ice)

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
