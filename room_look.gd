extends Node
## The room's look, chosen on the PC (Settings > Room look):
##   "og"  - the room as it was built, everything made in code
##   "new" - models from Quaternius's packs (CC0, assets/quaternius), recoloured to the room's lofi palette:
##           Downtown buildings with rooftop clutter and street lights across the east street, model cars in the
##           traffic, plants, a floor lamp, a mug, a croissant and a soda can in the living room, a Shiba on the rug,
##           a radio and a matchbox on the Noir office desk.
## NEW is built the first time it's chosen; after that switching just shows one set and hides the other, so OG is
## always exactly the original. On a low-power headset (Plat.low_power) the heavy buildings stay as they were.

const Plat := preload("res://platform.gd")
const LofiTex := preload("res://shaders/lofi_tex.gdshader")
const Q := "res://assets/quaternius/"
const WASH := Color(0.86, 0.30, 0.58)            # the carts' pink wash, so everything leans the same way

var main: Node3D
var look := "og"
var _built := false
var _new_nodes: Array = []                       # shown in NEW
var _og_nodes: Array = []                        # hidden in NEW
var _blocks: Array = []                          # [room id, Rect2]: where the new furniture stands (no walking through it)
var _anims: Array = []                           # AnimationPlayers to pause in OG


func setup(m: Node3D) -> void:
	main = m


func set_look(v: String) -> void:
	look = "new" if v == "new" else "og"
	if look == "new" and not _built:
		_build()
	var on := look == "new"
	for n in _new_nodes:
		if is_instance_valid(n):
			(n as Node3D).visible = on
	for n in _og_nodes:
		if is_instance_valid(n):
			(n as Node3D).visible = not on
	var bl: Dictionary = main.apartment._blockers
	for b in _blocks:
		var arr: Array = bl.get(b[0], [])
		var has := arr.has(b[1])
		if on and not has:
			arr.append(b[1])
		elif not on and has:
			arr.erase(b[1])
	for ap in _anims:
		if is_instance_valid(ap):
			if on:
				(ap as AnimationPlayer).play()
			else:
				(ap as AnimationPlayer).pause()


func _build() -> void:
	_built = true
	if not Plat.low_power():
		_build_city()
	_build_cars()
	_build_living()
	_build_noir()


# ---------------------------------------------------------------- the street below the balcony

# rooftop clutter (worked out once from the buildings' roofs): model, scale, where (street frame), turn
const CLUTTER := [
		["cyber/AC.gltf", 1.60, Vector3(27.26, -5.19, -25.13), 324],
		["cyber/AC_Side.gltf", 1.60, Vector3(29.80, -5.19, -31.08), 71],
		["cyber/AC_Stacked.gltf", 1.70, Vector3(30.64, -5.19, -28.07), 15],
		["cyber/Antenna_1.gltf", 2.60, Vector3(26.77, -5.19, -27.56), 209],
		["cyber/Antenna_2.gltf", 1.80, Vector3(31.30, -5.19, -24.18), 9],
		["cyber/Pipe_1.gltf", 1.60, Vector3(28.70, -5.19, -23.18), 37],
		["city/Prop_ACUnit.gltf", 1.60, Vector3(24.56, -5.19, -31.37), 172],
		["cyber/AC_Side.gltf", 1.60, Vector3(27.27, -13.19, -10.19), 16],
		["cyber/AC_Stacked.gltf", 1.70, Vector3(26.92, -13.19, -13.86), 77],
		["cyber/Antenna_1.gltf", 2.60, Vector3(31.89, -13.19, -15.30), 360],
		["cyber/Antenna_2.gltf", 1.80, Vector3(32.06, -13.19, -10.99), 26],
		["cyber/Pipe_1.gltf", 1.60, Vector3(30.48, -13.19, -13.25), 136],
		["cyber/AC.gltf", 1.60, Vector3(24.56, -13.19, -10.81), 207],
		["cyber/AC_Stacked.gltf", 1.70, Vector3(28.51, -13.19, 2.28), 144],
		["cyber/Antenna_1.gltf", 2.60, Vector3(31.14, -13.19, -1.89), 26],
		["cyber/Antenna_2.gltf", 1.80, Vector3(25.01, -13.19, 0.65), 203],
		["cyber/Pipe_1.gltf", 1.60, Vector3(26.20, -13.19, 3.84), 141],
		["city/Prop_ACUnit.gltf", 1.60, Vector3(30.90, -13.19, 1.22), 232],
		["cyber/AC.gltf", 1.60, Vector3(26.05, -13.19, -1.98), 2],
		["cyber/AC.gltf", 1.60, Vector3(31.46, -13.19, 3.72), 311],
		["cyber/Antenna_1.gltf", 2.60, Vector3(29.30, -5.19, 20.25), 152],
		["cyber/Antenna_2.gltf", 1.80, Vector3(28.88, -5.19, 15.36), 207],
		["cyber/Pipe_1.gltf", 1.60, Vector3(30.08, -5.19, 12.22), 172],
		["city/Prop_ACUnit.gltf", 1.60, Vector3(23.91, -5.19, 14.15), 39],
		["cyber/AC.gltf", 1.60, Vector3(27.80, -5.19, 18.05), 36],
		["cyber/AC.gltf", 1.60, Vector3(25.09, -5.19, 17.06), 265],
		["cyber/Antenna_2.gltf", 1.80, Vector3(31.74, -13.19, 29.00), 69],
		["cyber/Pipe_1.gltf", 1.60, Vector3(29.60, -13.19, 31.69), 7],
		["city/Prop_ACUnit.gltf", 1.60, Vector3(25.96, -13.19, 27.65), 351],
		["cyber/AC.gltf", 1.60, Vector3(25.00, -13.19, 31.00), 40],
		["cyber/AC.gltf", 1.60, Vector3(27.64, -13.19, 30.05), 103],
		["cyber/AC_Side.gltf", 1.60, Vector3(28.36, -13.19, 33.85), 357],
		["cyber/AC_Stacked.gltf", 1.70, Vector3(32.38, -13.19, 34.00), 153],
		["cyber/Pipe_1.gltf", 1.60, Vector3(51.43, -2.20, -23.61), 175],
		["city/Prop_ACUnit.gltf", 1.60, Vector3(41.78, -2.20, -22.56), 201],
		["cyber/AC.gltf", 1.60, Vector3(49.20, -2.20, -19.12), 53],
		["cyber/AC.gltf", 1.60, Vector3(45.76, -2.20, -24.77), 354],
		["cyber/AC_Side.gltf", 1.60, Vector3(42.81, -2.20, -26.32), 162],
		["cyber/AC_Stacked.gltf", 1.70, Vector3(44.19, -2.20, -19.53), 227],
		["cyber/Antenna_1.gltf", 2.60, Vector3(47.05, -2.20, -28.27), 55],
		["city/Prop_ACUnit.gltf", 1.60, Vector3(45.36, -2.20, -6.83), 350],
		["cyber/AC.gltf", 1.60, Vector3(50.39, -2.20, -8.01), 72],
		["cyber/AC.gltf", 1.60, Vector3(50.74, -2.20, -4.18), 87],
		["cyber/AC_Side.gltf", 1.60, Vector3(42.09, -2.20, -6.45), 100],
		["cyber/AC_Stacked.gltf", 1.70, Vector3(42.53, -2.20, 0.75), 341],
		["cyber/Antenna_1.gltf", 2.60, Vector3(42.93, -2.20, -4.05), 234],
		["cyber/Antenna_2.gltf", 1.80, Vector3(46.02, -2.20, 0.02), 179],
		["cyber/AC.gltf", 1.60, Vector3(44.02, -5.19, 19.36), 224],
		["cyber/AC.gltf", 1.60, Vector3(44.96, -5.19, 10.55), 250],
		["cyber/AC_Side.gltf", 1.60, Vector3(42.08, -5.19, 14.92), 188],
		["cyber/AC_Stacked.gltf", 1.70, Vector3(46.58, -5.19, 19.00), 147],
		["cyber/Antenna_1.gltf", 2.60, Vector3(46.41, -5.19, 15.56), 194],
		["cyber/Pipe_1.gltf", 1.60, Vector3(46.46, -5.19, 12.54), 305],
		["cyber/AC.gltf", 1.60, Vector3(42.96, -2.20, 30.09), 234],
		["cyber/AC_Side.gltf", 1.60, Vector3(49.81, -2.20, 33.67), 272],
		["cyber/AC_Stacked.gltf", 1.70, Vector3(46.65, -2.20, 38.19), 69],
		["cyber/Antenna_1.gltf", 2.60, Vector3(44.78, -2.20, 33.46), 310],
		["cyber/Antenna_2.gltf", 1.80, Vector3(50.96, -2.20, 28.80), 149],
		["cyber/Pipe_1.gltf", 1.60, Vector3(43.99, -2.20, 27.87), 68],
		["city/Prop_ACUnit.gltf", 1.60, Vector3(42.33, -2.20, 33.64), 187]
]


func _build_city() -> void:
	var ap = main.apartment
	var street: Node3D = ap.street
	if street == null:
		return
	var g: float = ap.GROUND
	var car_nodes := []
	for c in ap._cars:
		car_nodes.append(c[0])
	for mi in street.find_children("*", "MeshInstance3D", true, false):
		var n := mi as MeshInstance3D
		var in_car := false
		for cn in car_nodes:
			if (cn as Node).is_ancestor_of(n):
				in_car = true
		if not in_car and n.global_position.x > 22.0:
			_og_nodes.append(n)                          # the low box buildings across the east street, and their roofs
	var city := Node3D.new()
	city.name = "NewLookCity"
	street.add_child(city)
	_new_nodes.append(city)
	# Downtown kit buildings, fronts to the street (west); the taller ones in the second row
	for r in [["Building_Medium_2_001", 27.8, -27.0], ["Building_Small_1", 28.6, -12.5], ["Building_Small_1", 28.6, 1.5],
			["Building_Medium_2_001", 27.8, 16.5], ["Building_Small_1", 28.6, 31.0],
			["Building_Large_2", 46.5, -24.0], ["Building_Large_2", 46.5, -3.0], ["Building_Medium_2_001", 44.5, 15.0], ["Building_Large_2", 46.5, 33.0]]:
		spawn("city/%s.gltf" % r[0], city, Vector3(r[1], g, r[2]), -90.0)
	for c in CLUTTER:
		spawn(c[0], city, c[2], c[3], {"scale": c[1]})
	for i in 8:                                      # street lights along the east sidewalk, facing the road
		spawn("cyber/Light_Street_1.gltf", city, Vector3(20.9, g + 0.16, -34.0 + i * 10.0), -90.0, {"scale": 1.8})


func _build_cars() -> void:
	var models := ["NormalCar1", "Taxi", "SUV", "SportsCar", "NormalCar2"]
	var i := 0
	for c in main.apartment._cars:
		var cn: Node3D = c[0]
		for ch in cn.get_children():
			if ch is MeshInstance3D:
				_og_nodes.append(ch)
		var nm: String = models[i % models.size()]
		var h := spawn("cars/%s.fbx" % nm, cn, Vector3.ZERO, 180.0, {"fit": 4.2 if nm != "NormalCar2" else 3.5})   # (fronts +z; the cars drive toward -z)
		_new_nodes.append(h)
		i += 1


# ---------------------------------------------------------------- the living room and the Noir office

func _build_living() -> void:
	var liv: Node3D = main.apartment.living
	if liv == null:
		return
	var inv := liv.global_transform.affine_inverse()
	var props := Node3D.new()
	props.name = "NewLookProps"
	liv.add_child(props)
	_new_nodes.append(props)
	for mi in liv.find_children("*", "MeshInstance3D", true, false):
		var n := mi as MeshInstance3D
		if n.mesh is CylinderMesh and n.global_position.distance_to(Vector3(5.2, 0.475, 0.4)) < 0.05:
			_og_nodes.append(n)                          # the box mug on the coffee table: the model one takes its place
	spawn("food/CupOfCoffee.obj", props, inv * Vector3(5.2, 0.425, 0.4), -60.0, {"fit": 0.12})
	spawn("food/Croissant.fbx", props, inv * Vector3(5.22, 0.425, 1.0), 30.0, {"fit": 0.15})
	spawn("food/SodaCan.fbx", props, inv * Vector3(4.97, 0.425, 0.55), 0.0, {"fit": 0.12})
	spawn("interior/Houseplant_7.fbx", props, inv * Vector3(3.2, 0.0, -1.45), 20.0, {"fit": 1.25})
	spawn("interior/Houseplant_1.fbx", props, inv * Vector3(3.15, 0.0, 2.9), 0.0, {"fit": 0.95})
	spawn("interior/Light_Floor1.fbx", props, inv * Vector3(9.05, 0.0, -1.5), 220.0, {"fit": 1.65})
	spawn("pets/ShibaInu.gltf", props, inv * Vector3(4.2, 0.012, 1.75), 75.0, {"fit": 0.75, "anim": "Idle"})
	for r in [Rect2(2.95, -1.75, 0.5, 0.6), Rect2(2.9, 2.65, 0.5, 0.5), Rect2(8.85, -1.7, 0.4, 0.4), Rect2(3.95, 1.5, 0.5, 0.5)]:
		_blocks.append(["living", r])


func _build_noir() -> void:
	if main.noir == null or main.noir._typewriter == null:
		return
	var tw: Node3D = main.noir._typewriter
	var desk := tw.get_parent() as Node3D
	var props := Node3D.new()
	props.name = "NewLookDesk"
	desk.add_child(props)
	_new_nodes.append(props)
	var radio := spawn("noir/Radio.fbx", props, tw.position + Vector3(-0.55, 0, -0.12), 0.0, {"fit": 0.32, "noir": true})
	var page := tw.get_node_or_null("Sheet/PageFocus") as Node3D
	if page != null:                                 # (facing the chair, like the typewriter)
		var at := page.global_position + page.global_transform.basis.z
		radio.look_at(Vector3(at.x, radio.global_position.y, at.z), Vector3.UP)
		radio.rotate_y(PI)
	spawn("noir/Matchbox.fbx", props, tw.position + Vector3(0.36, 0, 0.22), 25.0, {"fit": 0.055, "noir": true})


# ---------------------------------------------------------------- loading and recolouring a model

# opts: fit (largest size in metres) or scale, noir (greys only), anim (an animation to loop)
func spawn(path: String, parent: Node3D, pos: Vector3, yaw_deg := 0.0, opts := {}) -> Node3D:
	var res = load(Q + path)
	var model: Node3D
	if res is PackedScene:
		model = (res as PackedScene).instantiate()
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		model = mi
	else:
		push_warning("room look: can't load " + path)
		return Node3D.new()
	var fix := Node3D.new()                        # scale and centring
	fix.add_child(model)
	var holder := Node3D.new()                     # where it stands and which way it faces
	holder.name = path.get_file().get_basename()
	holder.add_child(fix)
	parent.add_child(holder)
	var box := _aabb(fix, holder)
	var k := float(opts.get("scale", 1.0))
	if opts.has("fit"):
		k = float(opts["fit"]) / maxf(maxf(box.size.x, box.size.y), box.size.z)
	fix.scale = Vector3.ONE * k
	box = _aabb(fix, holder)
	fix.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)   # centred, standing on y = 0
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	recolor(model, bool(opts.get("noir", false)))
	if opts.has("anim"):
		var aps := model.find_children("*", "AnimationPlayer", true, false)
		if aps.size() > 0:
			var p := aps[0] as AnimationPlayer
			var a := p.get_animation(String(opts["anim"]))
			if a != null:
				a.loop_mode = Animation.LOOP_LINEAR
				p.play(String(opts["anim"]))
				_anims.append(p)
	return holder


# any flat colour -> its lofi version: hue moved onto the room's palette, a little more saturated, a touch darker
static func lofi(c: Color) -> Color:
	var h := c.h
	var s := c.s
	var v := c.v
	var out: Color
	if s < 0.14:                                   # greys, whites, blacks: cool lavender greys
		out = Color.from_hsv(0.75, 0.16 + 0.24 * (1.0 - v), clampf(v * 0.88 + 0.03, 0.0, 1.0))
	else:
		var th: float
		if h < 0.05 or h >= 0.93: th = 0.935        # red -> pink
		elif h < 0.11: th = 0.06                    # orange / brown -> peach
		elif h < 0.2: th = 0.075                    # yellow -> peach
		elif h < 0.45: th = 0.47                    # green -> teal
		elif h < 0.56: th = 0.52                    # cyan
		elif h < 0.69: th = 0.69                    # blue -> indigo
		elif h < 0.8: th = 0.77                     # purple
		else: th = 0.86                             # magenta
		var smax := 0.55 if (th > 0.03 and th < 0.1) else 0.88      # (peach stays soft)
		out = Color.from_hsv(th, clampf(s * 1.1 + 0.12, 0.0, smax), v * 0.92)
	return out.lerp(WASH, 0.12)


static func _is_light(name: String) -> bool:
	var n := name.to_lower()
	if n.contains("headlight") or n.contains("taillight") or n.contains("texture_sign"):
		return true
	return n == "light" or n == "lights"           # (lamp shades, street lights; not "LightGrey" and the like)


# the Downtown kit's textured surfaces: a dark -> mid -> light gradient per kind
const TEX_LOOKS := {
	"redbrick": [Color(0.10, 0.04, 0.12), Color(0.40, 0.14, 0.34), Color(0.86, 0.48, 0.66)],
	"trim": [Color(0.06, 0.04, 0.12), Color(0.24, 0.16, 0.40), Color(0.66, 0.56, 0.86)],
	"metalconcrete": [Color(0.05, 0.04, 0.10), Color(0.20, 0.15, 0.36), Color(0.58, 0.52, 0.80)],
	"concrete": [Color(0.08, 0.06, 0.14), Color(0.30, 0.22, 0.44), Color(0.72, 0.62, 0.86)],
	"asphalt": [Color(0.10, 0.07, 0.16), Color(0.24, 0.17, 0.34), Color(0.50, 0.40, 0.62)],
	"ornaments": [Color(0.06, 0.04, 0.12), Color(0.26, 0.16, 0.42), Color(0.70, 0.56, 0.88)],
	"dirt": [Color(0.08, 0.05, 0.10), Color(0.20, 0.13, 0.22), Color(0.42, 0.30, 0.44)],
	"marble": [Color(0.12, 0.08, 0.20), Color(0.36, 0.26, 0.52), Color(0.80, 0.70, 0.92)],
	"interiorwall": [Color(0.10, 0.06, 0.14), Color(0.30, 0.18, 0.36), Color(0.62, 0.46, 0.66)],
}


static func recolor(root: Node, noir := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(root.name)
	for mi in root.find_children("*", "MeshInstance3D", true, false) + ([root] if root is MeshInstance3D else []):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if not (mat is StandardMaterial3D):
				continue
			var sm := mat as StandardMaterial3D
			var mname := sm.resource_name.to_lower()
			if sm.albedo_texture != null:
				m.set_surface_override_material(s, _tex_material(sm, mname, rng))
				continue
			var nm := sm.duplicate() as StandardMaterial3D
			var col := lofi(sm.albedo_color)
			if noir:
				var gr := sm.albedo_color.get_luminance() * 0.9
				col = Color(gr, gr, gr * 1.03)
			nm.albedo_color = Color(col.r, col.g, col.b, 1.0)
			nm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			nm.metallic = minf(sm.metallic, 0.3)
			nm.roughness = maxf(sm.roughness, 0.55)
			if mname.contains("glass"):
				nm.albedo_color = Color(0.20, 0.14, 0.34, 0.45)
				nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				nm.roughness = 0.15
				nm.metallic = 0.4
			if _is_light(sm.resource_name):
				nm.emission_enabled = true
				var e := col.lightened(0.25)
				if mname.contains("head"):
					e = Color(1.0, 0.85, 0.65)
				elif mname.contains("tail"):
					e = Color(1.0, 0.25, 0.45)
				nm.emission = e
				nm.emission_energy_multiplier = 1.6
			else:
				nm.emission_enabled = false          # (the Quaternius files switch glow on for every part)
			m.set_surface_override_material(s, nm)


static func _tex_material(sm: StandardMaterial3D, mname: String, rng: RandomNumberGenerator) -> Material:
	var sh := ShaderMaterial.new()
	sh.shader = LofiTex
	sh.set_shader_parameter("tex", sm.albedo_texture)
	if sm.normal_enabled and sm.normal_texture != null:
		sh.set_shader_parameter("nrm", sm.normal_texture)
		sh.set_shader_parameter("use_nrm", true)
	sh.set_shader_parameter("uv_scale", sm.uv1_scale)
	sh.set_shader_parameter("uv_offset", sm.uv1_offset)
	if mname.contains("fakeinterior"):
		# the window interiors: most rooms lit, warm or pink; a few dark
		var lit := rng.randf() < 0.75
		var warm := rng.randf() < 0.6
		sh.set_shader_parameter("dark", Color(0.05, 0.03, 0.08))
		sh.set_shader_parameter("mid", Color(0.30, 0.16, 0.30))
		sh.set_shader_parameter("light", Color(0.95, 0.72, 0.62))
		sh.set_shader_parameter("emit_col", Color(1.0, 0.70, 0.42) if warm else Color(0.95, 0.40, 0.75))
		sh.set_shader_parameter("emit_k", 1.4 if lit else 0.08)
		return sh
	var lk: Array = TEX_LOOKS["concrete"]
	for k in TEX_LOOKS:
		if mname.contains(k):
			lk = TEX_LOOKS[k]
	sh.set_shader_parameter("dark", lk[0])
	sh.set_shader_parameter("mid", lk[1])
	sh.set_shader_parameter("light", lk[2])
	return sh


static func _aabb(n: Node3D, rel: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var t := Transform3D()
		var cur: Node = m
		while cur != null and cur != rel:
			if cur is Node3D:
				t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		var b: AABB = t * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
