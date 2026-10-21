extends RefCounted
## A classic flying saucer: a wide brushed-metal disc with a raised rim, a glass dome on top with a soft glow
## inside, a ring of lights round the edge (they can chase), and a pale tractor-beam cone underneath.
## A cabin under the dome has a round port at the front (+z) with a sliding hatch and an alien inside.
## About 1 unit across; the caller scales it. Named parts: Dome, Port (Hatch, Alien), Lights (Light0..), Beam.

const RING_LIGHTS := 16


static func build() -> Node3D:
	var root := Node3D.new()
	var hull := _m(Color(0.62, 0.64, 0.68), 0.25, 0.9)
	var hull_dk := _m(Color(0.30, 0.31, 0.34), 0.35, 0.85)
	# the disc: two shallow cones back to back, with a band round the middle
	var top := CylinderMesh.new()
	top.top_radius = 0.2
	top.bottom_radius = 0.5
	top.height = 0.09
	top.radial_segments = 48
	_part(root, top, hull, Vector3(0, 0.045, 0))
	var bot := CylinderMesh.new()
	bot.top_radius = 0.5
	bot.bottom_radius = 0.22
	bot.height = 0.07
	bot.radial_segments = 48
	_part(root, bot, hull_dk, Vector3(0, -0.035, 0))
	var band := CylinderMesh.new()
	band.top_radius = 0.51
	band.bottom_radius = 0.51
	band.height = 0.018
	band.radial_segments = 48
	_part(root, band, _m(Color(0.2, 0.2, 0.23), 0.3, 0.9), Vector3.ZERO)
	# panel seams on the top
	for k in 12:
		var a := TAU * k / 12.0
		var seam := BoxMesh.new()
		seam.size = Vector3(0.3, 0.003, 0.004)
		var s := _part(root, seam, hull_dk, Vector3(cos(a) * 0.35, 0.06, sin(a) * 0.35))
		s.rotation = Vector3(0, -a, -0.32)
	# the underside: a glowing ring and a hub
	var hub := CylinderMesh.new()
	hub.top_radius = 0.18
	hub.bottom_radius = 0.12
	hub.height = 0.04
	_part(root, hub, hull_dk, Vector3(0, -0.085, 0))
	var under_ring := TorusMesh.new()
	under_ring.inner_radius = 0.1
	under_ring.outer_radius = 0.125
	_part(root, under_ring, _glow(Color(0.4, 1.0, 0.7), 4.0), Vector3(0, -0.1, 0))
	# the dome: tinted glass with a warm light inside
	var dome := Node3D.new()
	dome.name = "Dome"
	dome.position = Vector3(0, 0.09, 0)
	root.add_child(dome)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.95, 0.85, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	glass.rim_enabled = true
	glass.rim = 0.8
	glass.emission_enabled = true
	glass.emission = Color(0.3, 0.9, 0.7)
	glass.emission_energy_multiplier = 0.6
	var dm := SphereMesh.new()
	dm.radius = 0.17
	dm.height = 0.34
	dm.is_hemisphere = true
	dm.radial_segments = 32
	_part(dome, dm, glass, Vector3.ZERO)
	var inner := SphereMesh.new()
	inner.radius = 0.06
	inner.height = 0.12
	_part(dome, inner, _glow(Color(0.6, 1.0, 0.8), 3.0), Vector3(0, 0.04, 0))
	# the cabin under the dome, with a round port at the front (+z) behind a sliding hatch; inside, a grey
	# alien with big black eyes
	var cabin := CylinderMesh.new()
	cabin.top_radius = 0.19
	cabin.bottom_radius = 0.21
	cabin.height = 0.13
	cabin.radial_segments = 40
	_part(root, cabin, hull, Vector3(0, 0.12, 0))
	dome.position.y = 0.185
	var port := Node3D.new()
	port.name = "Port"
	port.position = Vector3(0, 0.125, 0.2)
	root.add_child(port)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.048
	rim.outer_radius = 0.058
	var r := _part(port, rim, _m(Color(0.25, 0.26, 0.3), 0.3, 0.9), Vector3.ZERO)
	r.rotation.x = PI / 2.0
	var hole := CylinderMesh.new()
	hole.top_radius = 0.049
	hole.bottom_radius = 0.049
	hole.height = 0.01
	var back := _part(port, hole, _glow(Color(0.12, 0.3, 0.26), 1.0), Vector3(0, 0, -0.03))   # the dim lit cabin behind
	back.rotation.x = PI / 2.0
	var alien := Node3D.new()
	alien.name = "Alien"
	alien.position = Vector3(0, -0.004, -0.01)
	port.add_child(alien)
	var skin := _m(Color(0.62, 0.64, 0.66), 0.6, 0.0)
	skin.emission_enabled = true                       # lit by the cabin's own light, so it stays grey under the pink lamps
	skin.emission = Color(0.42, 0.45, 0.46)
	skin.emission_energy_multiplier = 0.8
	var head := SphereMesh.new()
	head.radius = 0.03
	head.height = 0.06
	var h := _part(alien, head, skin, Vector3(0, 0.006, 0))
	h.scale = Vector3(1.0, 1.15, 0.9)
	var chin := SphereMesh.new()
	chin.radius = 0.016
	chin.height = 0.032
	_part(alien, chin, skin, Vector3(0, -0.02, 0.006)).scale = Vector3(1.0, 1.2, 0.9)
	var eye_m := StandardMaterial3D.new()
	eye_m.albedo_color = Color(0.0, 0.0, 0.0)
	eye_m.roughness = 0.05
	eye_m.metallic_specular = 1.0
	for sx in [-1.0, 1.0]:
		var em := SphereMesh.new()
		em.radius = 1.0
		em.height = 2.0
		var e := _part(alien, em, eye_m, Vector3(sx * 0.0135, 0.004, 0.022))
		e.scale = Vector3(0.0145, 0.0078, 0.006)
		e.rotation.z = sx * 0.5                        # big almond eyes, tilted up at the outer corners
	_part(alien, SphereMesh.new(), skin, Vector3(0, -0.05, -0.005)).scale = Vector3(0.03, 0.02, 0.02)   # thin neck / shoulders
	# the hatch: a curved plate that slides up over the cabin to uncover the port
	var hatch := Node3D.new()
	hatch.name = "Hatch"
	port.add_child(hatch)
	var plate := CylinderMesh.new()
	plate.top_radius = 0.062
	plate.bottom_radius = 0.062
	plate.height = 0.008
	var hp := _part(hatch, plate, hull, Vector3(0, 0, 0.006))
	hp.rotation.x = PI / 2.0
	alien.visible = false

	# the ring of lights round the edge
	var lights := Node3D.new()
	lights.name = "Lights"
	root.add_child(lights)
	for i in RING_LIGHTS:
		var a := TAU * i / RING_LIGHTS
		var lm := SphereMesh.new()
		lm.radius = 0.018
		lm.height = 0.036
		var col := Color(1.0, 0.85, 0.3) if i % 2 == 0 else Color(0.3, 1.0, 0.8)
		var l := _part(lights, lm, _glow(col, 5.0), Vector3(cos(a) * 0.5, 0.0, sin(a) * 0.5))
		l.name = "Light%d" % i
	# the tractor beam: a pale, see-through cone fading toward the ground
	var beam_m := StandardMaterial3D.new()
	beam_m.albedo_color = Color(0.6, 1.0, 0.8, 0.18)
	beam_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_m.disable_fog = true
	var bm := CylinderMesh.new()
	bm.top_radius = 0.12
	bm.bottom_radius = 0.45
	bm.height = 1.4
	bm.cap_top = false
	bm.cap_bottom = false
	bm.radial_segments = 32
	var beam := _part(root, bm, beam_m, Vector3(0, -0.8, 0))
	beam.name = "Beam"
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 1.0, 0.75)
	glow.light_energy = 1.5
	glow.omni_range = 1.5
	glow.position = Vector3(0, -0.2, 0)
	root.add_child(glow)
	return root


# lights chase round the rim; call every frame with the time
static func animate_lights(ufo: Node3D, t: float) -> void:
	var lights := ufo.get_node("Lights")
	for i in RING_LIGHTS:
		var l := lights.get_child(i) as MeshInstance3D
		var on := 0.5 + 0.5 * sin(t * 6.0 - i * TAU / RING_LIGHTS * 2.0)
		(l.material_override as StandardMaterial3D).emission_energy_multiplier = 1.0 + 6.0 * on



static func _m(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.disable_fog = true
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


static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
