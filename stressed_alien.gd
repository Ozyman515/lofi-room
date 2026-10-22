extends Node3D
## A grey alien having a rough night, for Noir Night: sitting slumped on the edge of the bed, elbows on its
## knees, both hands clutching its big head, a cigarette hanging from its mouth with a thin curl of smoke.
## Built from smooth turned shapes and tubes (the same ones as the alien bobblehead in ufo.gd).
## Local frame: it faces +z, the origin is on the floor under the front of the seat. About 1.1 m tall sitting.

const U := preload("res://ufo.gd")

var _smoke: Array[Sprite3D] = []
var _ember: StandardMaterial3D
var _tip := Vector3.ZERO
var _t := 0.0
var _head: Node3D


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
	# hips and a thin, hunched body leaning forward over the knees
	add_child(U._tube([Vector3(0, seat_y + 0.02, -0.12), Vector3(0, seat_y + 0.16, -0.08), Vector3(0, seat_y + 0.3, 0.0),
		Vector3(0, seat_y + 0.4, 0.09)] as Array[Vector3], [0.1, 0.09, 0.095, 0.07] as Array[float], skin))
	_blob(Vector3(0, seat_y + 0.02, -0.1), Vector3(0.12, 0.07, 0.1), skin)                     # hips on the bed
	_blob(Vector3(0, seat_y + 0.34, 0.03), Vector3(0.12, 0.06, 0.08), skin)                    # shoulders, rounded
	# legs: thin thighs along the bed edge, knees up, shins down to long feet flat on the floor
	for sx in [-1.0, 1.0]:
		add_child(U._tube([Vector3(sx * 0.07, seat_y + 0.0, -0.08), Vector3(sx * 0.085, seat_y + 0.04, 0.12),
			Vector3(sx * 0.1, seat_y + 0.07, 0.28), Vector3(sx * 0.1, seat_y - 0.1, 0.32), Vector3(sx * 0.1, 0.3, 0.33),
			Vector3(sx * 0.1, 0.06, 0.32), Vector3(sx * 0.1, 0.03, 0.4)] as Array[Vector3],
			[0.055, 0.05, 0.046, 0.04, 0.034, 0.03, 0.026] as Array[float], skin))
	# arms: from the shoulders down to the elbows on the knees, forearms up to the head
	for sx in [-1.0, 1.0]:
		add_child(U._tube([Vector3(sx * 0.09, seat_y + 0.36, 0.03), Vector3(sx * 0.13, seat_y + 0.25, 0.12),
			Vector3(sx * 0.13, seat_y + 0.11, 0.25), Vector3(sx * 0.12, seat_y + 0.2, 0.31), Vector3(sx * 0.11, seat_y + 0.36, 0.3),
			Vector3(sx * 0.075, seat_y + 0.48, 0.25)] as Array[Vector3],
			[0.036, 0.031, 0.028, 0.026, 0.024, 0.021] as Array[float], skin))
	# the head, bowed: the big cranium tipped forward, held in both hands
	_head = Node3D.new()
	_head.position = Vector3(0, seat_y + 0.38, 0.17)
	_head.rotation.x = 0.62
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
		# long fingers spread over the sides of the head
		for f in 3:
			add_child(U._tube([Vector3(sx * 0.075, seat_y + 0.48, 0.25), Vector3(sx * (0.12 - f * 0.012), seat_y + 0.58 + f * 0.025, 0.22 + f * 0.03),
				Vector3(sx * (0.1 - f * 0.025), seat_y + 0.66 + f * 0.02, 0.18 + f * 0.045)] as Array[Vector3],
				[0.015, 0.011, 0.008] as Array[float], skin))
	# the cigarette hanging from the mouth, and its smoke
	var cig := Node3D.new()
	cig.position = Vector3(0, 0.03, 0.026)             # between the lips, hanging out and down
	cig.rotation.x = -1.3
	_head.add_child(cig)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.95, 0.94, 0.9)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.004
	cm.bottom_radius = 0.004
	cm.height = 0.07
	var c := MeshInstance3D.new()
	c.mesh = cm
	c.material_override = paper
	c.position = Vector3(0, -0.035, 0.0)
	cig.add_child(c)
	_ember = StandardMaterial3D.new()
	_ember.albedo_color = Color(1.0, 0.35, 0.05)
	_ember.emission_enabled = true
	_ember.emission = Color(1.0, 0.3, 0.04)
	_ember.emission_energy_multiplier = 5.0
	var em2 := CylinderMesh.new()
	em2.top_radius = 0.0042
	em2.bottom_radius = 0.0042
	em2.height = 0.006
	var tip := MeshInstance3D.new()
	tip.mesh = em2
	tip.material_override = _ember
	tip.position = Vector3(0, -0.072, 0)
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
	for i in _smoke.size():
		var u := fposmod(_t * 0.07 + float(i) / _smoke.size(), 1.0)
		var s := _smoke[i]
		s.position = tip + Vector3(sin(u * 8.0 + i) * 0.02 * (0.3 + u), u * 0.7, cos(u * 6.0) * 0.015 * u)
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
