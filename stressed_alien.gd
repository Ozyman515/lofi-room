extends Node3D
## A grey alien having a rough night, for Noir Night: sitting back in the recliner in a worn trench coat and
## fedora, one arm along the armrest, the other elbow propped up with a cigarette held by its face, smoke curling up.
## Built from smooth turned shapes and tubes (the same ones as the alien bobblehead in ufo.gd).
## Local frame: it faces +z, the origin is on the floor under the middle of the seat. About 1.1 m tall sitting.

const U := preload("res://ufo.gd")

var _smoke: Array[Sprite3D] = []
var _ember: StandardMaterial3D
var _tip := Vector3.ZERO
var _t := 0.0
var _head: Node3D
var _glass: Node3D


func build(seat_y := 0.6) -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.58, 0.61, 0.63)
	skin.roughness = 0.55
	skin.rim_enabled = true
	skin.rim = 0.3
	skin.emission_enabled = true                     # a faint pale glow, so it reads in the dark of Noir Night
	skin.emission = Color(0.3, 0.32, 0.33)
	skin.emission_energy_multiplier = 0.5
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0, 0, 0)
	black.roughness = 0.05
	black.metallic_specular = 1.0
	var coat := StandardMaterial3D.new()               # a tired old trench coat and dark slacks
	coat.albedo_color = Color(0.46, 0.39, 0.29)
	coat.roughness = 0.9
	coat.emission_enabled = true
	coat.emission = Color(0.12, 0.1, 0.08)
	coat.emission_energy_multiplier = 0.5
	var slacks := StandardMaterial3D.new()
	slacks.albedo_color = Color(0.13, 0.13, 0.15)
	slacks.roughness = 0.85
	var sy := seat_y
	# sitting back in the chair, upright, leaning a little onto the right arm (+x)
	add_child(U._tube([Vector3(0, sy + 0.03, -0.2), Vector3(0.01, sy + 0.16, -0.21), Vector3(0.025, sy + 0.3, -0.21),
		Vector3(0.035, sy + 0.42, -0.19)] as Array[Vector3], [0.12, 0.105, 0.11, 0.085] as Array[float], coat))
	_blob(Vector3(0, sy + 0.05, -0.17), Vector3(0.14, 0.07, 0.12), coat)                     # hips, coat tails
	_blob(Vector3(0.035, sy + 0.4, -0.19), Vector3(0.14, 0.06, 0.09), coat)                   # shoulders
	for sx in [-1.0, 1.0]:                                                                     # the collar, turned up
		var col := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.07, 0.09, 0.012)
		col.mesh = cb
		col.material_override = coat
		col.position = Vector3(0.035 + sx * 0.05, sy + 0.46, -0.15)
		col.rotation = Vector3(-0.25, sx * 0.55, sx * 0.15)
		add_child(col)
	# legs: thighs along the cushion, knees at its front edge, shins down to long bare feet on the rug
	for sx in [-1.0, 1.0]:
		add_child(U._tube([Vector3(sx * 0.07, sy + 0.04, -0.14), Vector3(sx * 0.09, sy + 0.06, 0.06),
			Vector3(sx * 0.1, sy + 0.07, 0.24), Vector3(sx * 0.1, sy - 0.05, 0.3), Vector3(sx * 0.105, 0.2, 0.33),
			Vector3(sx * 0.105, 0.07, 0.33)] as Array[Vector3],
			[0.06, 0.055, 0.048, 0.042, 0.036, 0.032] as Array[float], slacks))
		add_child(U._tube([Vector3(sx * 0.105, 0.09, 0.32), Vector3(sx * 0.105, 0.04, 0.34), Vector3(sx * 0.11, 0.025, 0.43)] as Array[Vector3],
			[0.03, 0.028, 0.022] as Array[float], skin))
	# the right arm lies along the armrest, the hand round a glass of whiskey standing at its end
	add_child(U._tube([Vector3(0.13, sy + 0.4, -0.19), Vector3(0.24, sy + 0.3, -0.16), Vector3(0.31, sy + 0.235, -0.08),
		Vector3(0.33, sy + 0.235, 0.08), Vector3(0.34, sy + 0.24, 0.19)] as Array[Vector3],
		[0.042, 0.036, 0.034, 0.03, 0.026] as Array[float], coat))
	var gc := Vector3(0.335, sy + 0.215, 0.265)                    # the glass, on the end of the armrest
	_glass = load("res://noir_props.gd")._tumbler(gc)
	add_child(_glass)
	var palm := Vector3(0.345, sy + 0.27, 0.205)
	add_child(U._tube([Vector3(0.34, sy + 0.24, 0.19), palm] as Array[Vector3], [0.02, 0.018] as Array[float], skin))
	for f in 3:                                                    # long fingers wrapped round the far side of it
		var fy: float = sy + 0.285 - f * 0.018
		var pts: Array[Vector3] = [palm + Vector3(0.0, fy - palm.y, 0.0)]
		for ang in [0.55, 1.2, 1.85 - f * 0.12]:
			pts.append(gc + Vector3(sin(ang) * 0.052, fy - gc.y, -cos(ang) * 0.052))
		add_child(U._tube(pts, [0.012, 0.011, 0.009, 0.007] as Array[float], skin))
	add_child(U._tube([palm, gc + Vector3(-0.045, 0.07, -0.03), gc + Vector3(-0.052, 0.06, 0.01)] as Array[Vector3],
		[0.011, 0.009, 0.007] as Array[float], skin))             # the thumb, on the near side
	# the head, upright on a thin neck, chin down a touch, eyes slid off to one side
	add_child(U._tube([Vector3(0.03, sy + 0.4, -0.19), Vector3(0.025, sy + 0.5, -0.17)] as Array[Vector3],
		[0.03, 0.026] as Array[float], skin))
	_head = Node3D.new()
	_head.position = Vector3(0.02, sy + 0.48, -0.16)
	_head.rotation = Vector3(0.16, -0.25, 0.05)
	_head.scale = Vector3.ONE * 1.3
	add_child(_head)
	var head := U._lathe([[0.0, 0.0], [0.008, 0.018], [0.03, 0.034], [0.064, 0.052], [0.104, 0.07], [0.144, 0.088],
		[0.184, 0.098], [0.216, 0.1], [0.244, 0.094], [0.268, 0.078], [0.288, 0.052], [0.3, 0.024], [0.304, 0.0]], 0.84, skin)
	_head.add_child(head)
	for sx in [-1.0, 1.0]:                                    # tired eyes: big, but half shut
		var em := SphereMesh.new()
		em.radius = 1.0
		em.height = 2.0
		var e := MeshInstance3D.new()
		e.mesh = em
		e.material_override = black
		e.position = Vector3(sx * 0.042, 0.122, 0.057)
		e.scale = Vector3(0.046, 0.017, 0.016)
		e.rotation = Vector3(0.0, sx * 0.5, sx * 0.4)
		_head.add_child(e)
		var lid := MeshInstance3D.new()                      # heavy lids over the top half
		lid.mesh = em
		lid.material_override = skin
		lid.position = Vector3(sx * 0.042, 0.136, 0.058)
		lid.scale = Vector3(0.05, 0.014, 0.018)
		lid.rotation = Vector3(0.0, sx * 0.5, sx * 0.4)
		_head.add_child(lid)
	# a fedora, tipped down over one eye
	var hat: Node3D = load("res://noir_props.gd").fedora()
	hat.position = Vector3(0.0, 0.222, -0.005)
	hat.rotation = Vector3(0.12, 0.0, -0.14)
	hat.scale = Vector3(1.15, 1.1, 1.2)
	for mi in hat.get_children():
		if mi is MeshInstance3D and mi.material_override is StandardMaterial3D:
			var hm := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			hm.albedo_color = hm.albedo_color.lightened(0.18)
			mi.material_override = hm
	_head.add_child(hat)
	# the cigarette at his lips, held level between two fingers, the lit end out to the side, away from his face
	var mouth: Vector3 = _head.transform * Vector3(0.0, 0.045, 0.034)
	var cdir := Vector3(-0.62, -0.1, 0.78).normalized()
	var cmid := mouth + cdir * 0.042
	var cig := Node3D.new()
	cig.position = cmid
	cig.basis = Basis(Quaternion(Vector3.UP, cdir))
	add_child(cig)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.95, 0.94, 0.9)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0045
	cm.bottom_radius = 0.0045
	cm.height = 0.062
	var c := MeshInstance3D.new()
	c.mesh = cm
	c.material_override = paper
	c.position = Vector3(0, 0.009, 0.0)
	cig.add_child(c)
	var filt := StandardMaterial3D.new()
	filt.albedo_color = Color(0.8, 0.62, 0.38)
	var fm := CylinderMesh.new()
	fm.top_radius = 0.0046
	fm.bottom_radius = 0.0046
	fm.height = 0.02
	var fl := MeshInstance3D.new()
	fl.mesh = fm
	fl.material_override = filt
	fl.position = Vector3(0, -0.032, 0.0)
	cig.add_child(fl)
	# the left elbow propped on the other armrest, the forearm up, two fingers round the cigarette
	var hand := cmid + Vector3(-0.045, -0.035, -0.012)
	var wrist := hand + Vector3(-0.05, -0.055, 0.0)
	add_child(U._tube([Vector3(-0.07, sy + 0.4, -0.19), Vector3(-0.2, sy + 0.32, -0.15), Vector3(-0.29, sy + 0.24, -0.05),
		(Vector3(-0.29, sy + 0.24, -0.05) + wrist) / 2.0 + Vector3(0.0, 0.02, 0.0), wrist] as Array[Vector3],
		[0.042, 0.036, 0.034, 0.03, 0.026] as Array[float], coat))
	add_child(U._tube([wrist, hand] as Array[Vector3], [0.02, 0.018] as Array[float], skin))
	for f in 2:                                                     # one finger over the cigarette, one under it
		var side := Vector3(0.0, 0.006 if f == 0 else -0.006, 0.0)
		add_child(U._tube([hand, hand + Vector3(0.025, 0.02, 0.006) + side, cmid + side * 1.4 + Vector3(0.004, 0.0, 0.004)] as Array[Vector3],
			[0.012, 0.009, 0.006] as Array[float], skin))
	add_child(U._tube([hand, hand + Vector3(0.0, -0.01, 0.03), hand + Vector3(0.02, 0.0, 0.045)] as Array[Vector3],
		[0.011, 0.009, 0.006] as Array[float], skin))            # the thumb, curled under
	_ember = StandardMaterial3D.new()
	_ember.albedo_color = Color(1.0, 0.35, 0.05)
	_ember.emission_enabled = true
	_ember.emission = Color(1.0, 0.3, 0.04)
	_ember.emission_energy_multiplier = 5.0
	var em2 := CylinderMesh.new()
	em2.top_radius = 0.0047
	em2.bottom_radius = 0.0047
	em2.height = 0.006
	var tip := MeshInstance3D.new()
	tip.mesh = em2
	tip.material_override = _ember
	tip.position = Vector3(0, 0.043, 0)
	cig.add_child(tip)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.light_energy = 0.3
	glow.omni_range = 0.25
	tip.add_child(glow)
	_tip_node = tip
	var tex := _puff()
	for i in 22:
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.transparent = true
		sp.shaded = false
		sp.modulate = Color(0.85, 0.85, 0.9, 0.0)
		add_child(sp)
		_smoke.append(sp)


var _tip_node: Node3D


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var puff := 0.5 + 0.5 * sin(_t * 0.8)                    # a slow drag now and then
	_ember.emission_energy_multiplier = 3.0 + 4.0 * pow(puff, 4.0)
	_head.rotation.z = 0.04 * sin(_t * 0.35)                 # a slow, weary sway
	var tip := to_local(_tip_node.global_position)
	var away := Vector3(tip.x - _head.position.x, 0.0, tip.z - _head.position.z)
	away = away.normalized() if away.length() > 0.001 else Vector3(-1, 0, 0)
	for i in _smoke.size():
		var u := fposmod(_t * 0.07 + float(i) / _smoke.size(), 1.0)
		var s := _smoke[i]
		# it drifts off sideways first, out from under the brim, then rises (it never goes through his head or hat)
		s.position = tip + away * (0.26 * smoothstep(0.0, 0.32, u) + 0.06 * u) \
			+ Vector3(sin(u * 8.0 + i) * 0.02 * (0.3 + u), u * 0.7 * smoothstep(0.0, 0.12, u) + 0.02 * u, cos(u * 6.0) * 0.015 * u)
		s.pixel_size = (0.012 + 0.09 * u) / 64.0
		s.modulate.a = 0.22 * smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.45, 1.0, u))


func _blob(pos: Vector3, radii: Vector3, mat: Material) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = radii
	add_child(mi)


static func _puff() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0, y - n / 2.0).length() / (n / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
