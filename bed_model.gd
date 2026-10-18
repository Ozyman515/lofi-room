extends RefCounted
# Procedural mid-century platform bed: tapered splayed legs, thin rails, slanted-gusset headboard
# with a wide wooden panel, quilted cream mattress cover and two charcoal pillows.
# Local frame: origin on the floor at the middle of the bed, head toward -Z, foot toward +Z.
# Footprint (outer frame) is W x L; default matches the old bed (1.68 x 2.12).

const W := 1.68
const L := 2.12

const WOOD := Color(0.66, 0.43, 0.24)
const COVER := Color(0.74, 0.71, 0.65)
const PILLOW := Color(0.30, 0.31, 0.34)
const SHEET := Color(0.36, 0.37, 0.40)


static func build(parent: Node3D, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	root.name = "Bed"
	root.position = pos
	parent.add_child(root)

	var wood := _wood_mat()
	var cover := _quilt_mat()
	var pillow := _fabric_mat(PILLOW, 0.95)
	var sheet := _fabric_mat(SHEET, 0.95)

	var hw := W * 0.5
	var hl := L * 0.5
	var rail_top := 0.31
	var rail_h := 0.10
	var rail_t := 0.035

	# --- frame: two side rails, foot rail, head rail (the headboard stands on it)
	for sx in [-1.0, 1.0]:
		_rbox(root, Vector3(sx * (hw - rail_t * 0.5), rail_top - rail_h * 0.5, 0.0), Vector3(rail_t, rail_h, L), wood, 0.004)
	_rbox(root, Vector3(0, rail_top - rail_h * 0.5, hl - rail_t * 0.5), Vector3(W - rail_t * 2.0, rail_h, rail_t), wood, 0.004)
	_rbox(root, Vector3(0, rail_top - rail_h * 0.5, -hl + 0.03), Vector3(W - rail_t * 2.0, rail_h, 0.04), wood, 0.004)
	# slat deck under the mattress (hidden, but fills the frame so there is no see-through)
	_rbox(root, Vector3(0, rail_top - 0.045, 0.0), Vector3(W - rail_t * 2.0, 0.02, L - 0.1), wood, 0.002)
	# stiffening ledge along the inside of the side rails
	for sx in [-1.0, 1.0]:
		_rbox(root, Vector3(sx * (hw - rail_t - 0.02), rail_top - rail_h + 0.015, 0.0), Vector3(0.04, 0.03, L - 0.08), wood, 0.002)

	# --- tapered, splayed legs
	var leg_top_y := rail_top - rail_h
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var top := Vector3(sx * (hw - 0.07), leg_top_y, sz * (hl - 0.08))
			var bot := Vector3(sx * (hw - 0.07 + 0.05), 0.0, sz * (hl - 0.08 + 0.045))
			if sz < 0.0:
				# the head legs sit under the headboard posts
				top.z = -hl + 0.10
				bot.z = -hl + 0.10 - 0.04
			_leg(root, top, 0.062, bot, 0.034, wood)

	# --- headboard: two slanted side boards and a wide panel between them
	var back_z := -hl + 0.01
	for sx in [-1.0, 1.0]:
		var x0: float = sx * (hw - 0.035) if sx > 0.0 else sx * hw
		var x1: float = sx * hw if sx > 0.0 else sx * (hw - 0.035)
		var poly := PackedVector2Array([
			Vector2(back_z, 0.20),
			Vector2(back_z + 0.05, 0.20),
			Vector2(back_z + 0.20, 0.34),
			Vector2(back_z + 0.034, 1.06),
			Vector2(back_z, 1.06)])
		_extrude_x(root, poly, minf(x0, x1), maxf(x0, x1), wood)
	var panel := _rbox(root, Vector3(0, 0.66, back_z + 0.035), Vector3(W - 0.07, 0.80, 0.03), wood, 0.004)
	panel.rotation.x = -0.05
	# top cap that overhangs a touch
	_rbox(root, Vector3(0, 1.065, back_z + 0.025), Vector3(W, 0.025, 0.05), wood, 0.005)

	# --- mattress, cover with a quilted pattern
	var m_len := L - 0.16
	var m_wid := W - 0.06
	var m_h := 0.27
	var m_y := rail_top + m_h * 0.5 - 0.005
	var m_z := 0.03
	_rbox(root, Vector3(0, m_y, m_z), Vector3(m_wid, m_h, m_len), cover, 0.035, 10)

	# the grey sheet showing at the head end, under the pillows
	var s_len := 0.42
	_rbox(root, Vector3(0, m_y + 0.002, m_z - m_len * 0.5 + s_len * 0.5 - 0.005), Vector3(m_wid + 0.012, m_h - 0.012, s_len), sheet, 0.03, 8)
	# the cover is laid over it again past the pillow line so the sheet reads as a folded edge
	_rbox(root, Vector3(0, m_y + m_h * 0.5 - 0.012, m_z - m_len * 0.5 + s_len + 0.012), Vector3(m_wid + 0.004, 0.028, 0.05), cover, 0.012, 6)

	# --- pillows, leaning on the headboard
	var top_y := m_y + m_h * 0.5
	var pz := m_z - m_len * 0.5 + 0.30
	for sx in [-1.0, 1.0]:
		_rbox(root, Vector3(sx * 0.415, top_y + 0.055, pz), Vector3(0.70, 0.15, 0.48), pillow, 0.06, 12)
	return root


# ---------------------------------------------------------------- materials

static func _wood_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.02
	var n2 := FastNoiseLite.new()
	n2.seed = 19
	n2.frequency = 0.07
	for y in 256:
		for x in 256:
			# grain runs along u (x): vary mostly with y, with a slow wobble along x
			var g: float = n.get_noise_2d(x * 0.18, y * 3.2)
			var fine: float = n2.get_noise_2d(x * 0.25, y * 9.0)
			var v: float = 0.5 + g * 0.55 + fine * 0.18
			var c := WOOD.lerp(Color(0.52, 0.30, 0.15), clampf(v, 0.0, 1.0) * 0.8).lerp(Color(0.74, 0.50, 0.29), clampf(1.0 - v, 0.0, 1.0) * 0.35)
			img.set_pixel(x, y, c)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.uv1_scale = Vector3(1, 1, 1)
	m.roughness = 0.62
	return m


static func _quilt_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	img.fill(COVER)
	for i in s:
		for k in [0, 1]:
			# thin stitched lines on a grid, a little darker with a soft shadow beside them
			for w in range(-1, 3):
				var a: float = 0.0 if w == 0 or w == 1 else 0.5
				var col := COVER.darkened(0.20 if a == 0.0 else 0.08)
				var px := clampi(k * (s / 2) + w + 1, 0, s - 1)
				img.set_pixel(px, i, col)
				img.set_pixel(i, px, col)
	img.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.uv1_scale = Vector3(7, 7, 1)
	m.roughness = 0.97
	return m


static func _fabric_mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


# ---------------------------------------------------------------- geometry

# Rounded box. UVs are in metres/scale on the dominant axis plane, with u along the longer side.
static func _rbox(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, radius: float = 0.0, seg: int = 4) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _rbox_mesh(size, radius, seg)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _rbox_mesh(size: Vector3, radius: float, seg: int) -> ArrayMesh:
	var h := size * 0.5
	var r := minf(radius, minf(h.x, minf(h.y, h.z)) * 0.99)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(seg, 1) if r > 0.0 else 1
	var uv_scale := 0.5
	for axis in 3:
		for dirs in [-1.0, 1.0]:
			var a1 := (axis + 1) % 3
			var a2 := (axis + 2) % 3
			for i in n:
				for j in n:
					var quad: Array[Vector3] = []
					var norms: Array[Vector3] = []
					var uvs: Array[Vector2] = []
					for c in [[0, 0], [1, 0], [1, 1], [0, 1]]:
						var u: float = -1.0 + 2.0 * float(i + c[0]) / n
						var v: float = -1.0 + 2.0 * float(j + c[1]) / n
						var p := Vector3.ZERO
						p[axis] = dirs
						p[a1] = u
						p[a2] = v
						var full := Vector3(p.x * h.x, p.y * h.y, p.z * h.z)
						var inner := Vector3(clampf(full.x, -(h.x - r), h.x - r), clampf(full.y, -(h.y - r), h.y - r), clampf(full.z, -(h.z - r), h.z - r))
						var nn := full - inner
						var nrm: Vector3
						if r > 0.0 and nn.length() > 0.00001:
							nrm = nn.normalized()
							full = inner + nrm * r
						else:
							nrm = Vector3.ZERO
							nrm[axis] = dirs
						quad.append(full)
						norms.append(nrm)
						# planar uv on the two remaining axes, u along the longer one
						var la := full[a1]
						var lb := full[a2]
						var ua := la
						var ub := lb
						if h[a2] > h[a1]:
							ua = lb
							ub = la
						uvs.append(Vector2(ua, ub) * uv_scale + Vector2(0.37 * axis, 0.21 * axis))
					var order := [0, 1, 2, 0, 2, 3] if (dirs * (1.0 if axis != 1 else -1.0)) > 0.0 else [0, 2, 1, 0, 3, 2]
					# winding depends on the handedness of (axis, a1, a2) which is always right-handed here
					if dirs < 0.0:
						order = [0, 1, 2, 0, 2, 3]
					else:
						order = [0, 2, 1, 0, 3, 2]
					for k in order:
						st.set_normal(norms[k])
						st.set_uv(uvs[k])
						st.add_vertex(quad[k])
	return st.commit()


# Tapered leg between two centres with square cross-sections (flat shaded).
static func _leg(parent: Node3D, top: Vector3, top_w: float, bot: Vector3, bot_w: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tw := top_w * 0.5
	var bw := bot_w * 0.5
	var t: Array[Vector3] = [top + Vector3(-tw, 0, -tw), top + Vector3(tw, 0, -tw), top + Vector3(tw, 0, tw), top + Vector3(-tw, 0, tw)]
	var b: Array[Vector3] = [bot + Vector3(-bw, 0, -bw), bot + Vector3(bw, 0, -bw), bot + Vector3(bw, 0, bw), bot + Vector3(-bw, 0, bw)]
	for i in 4:
		var j := (i + 1) % 4
		_tri(st, t[i], b[i], b[j], Vector2(0, 0), Vector2(0, 1), Vector2(1, 1))
		_tri(st, t[i], b[j], t[j], Vector2(0, 0), Vector2(1, 1), Vector2(1, 0))
	_tri(st, b[0], b[2], b[1], Vector2(0, 0), Vector2(1, 1), Vector2(1, 0))
	_tri(st, b[0], b[3], b[2], Vector2(0, 0), Vector2(0, 1), Vector2(1, 1))
	_tri(st, t[0], t[1], t[2], Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	_tri(st, t[0], t[2], t[3], Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_uv(uc)
	st.add_vertex(c)


# Extrude a (z, y) outline along X between x0 and x1.
static func _extrude_x(parent: Node3D, poly: PackedVector2Array, x0: float, x1: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var p0 := poly[idx[i]]
		var p1 := poly[idx[i + 1]]
		var p2 := poly[idx[i + 2]]
		# +X face (triangle winding as seen from +X: z to the left... flip as needed via normals below)
		_tri(st, Vector3(x1, p0.y, p0.x), Vector3(x1, p1.y, p1.x), Vector3(x1, p2.y, p2.x), p0 * 0.5, p1 * 0.5, p2 * 0.5)
		_tri(st, Vector3(x0, p0.y, p0.x), Vector3(x0, p2.y, p2.x), Vector3(x0, p1.y, p1.x), p0 * 0.5, p2 * 0.5, p1 * 0.5)
	for i in poly.size():
		var j := (i + 1) % poly.size()
		var a := poly[i]
		var b := poly[j]
		_tri(st, Vector3(x0, a.y, a.x), Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector2(0, 0), Vector2(0.06, 0), Vector2(0.06, 0.5))
		_tri(st, Vector3(x0, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x0, b.y, b.x), Vector2(0, 0), Vector2(0.06, 0.5), Vector2(0, 0.5))
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	# faces may come out inside-out depending on polygon winding; render both sides to be safe
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	parent.add_child(mi)
	return mi
