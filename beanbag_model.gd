extends RefCounted
## A classic round beanbag: a squat ball with a bowl pressed into the top (deeper toward the front),
## six fabric panels with top-stitched seams that pucker into creases inside the bowl.
## Built as one mesh. Local -z is the front (where you sit), the bottom rests on y = 0.

const RINGS := 60
const SEGS := 108
const GORES := 6
const R := 0.46            # half width
const RY_TOP := 0.42
const RY_BOT := 0.30
const CENTRE_Y := 0.28     # the ball's centre; the bottom pokes 2 cm through the floor and is clamped flat


static func build(parent: Node, pos: Vector3, yaw: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh()
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.96
	m.disable_fog = true
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi


# how close (0..1) the angle ph is to a panel seam, at a ring of radius rr metres
static func _seam(ph: float, rr: float, w := 0.012) -> float:
	if rr < 0.03:
		return 0.0
	var step := TAU / GORES
	var a := fposmod(ph + PI / 2.0, step)          # one seam runs straight down the front
	var delta := minf(a, step - a) * rr            # distance along the surface, metres
	var f := exp(-(delta * delta) / (w * w))
	return f * smoothstep(0.03, 0.09, rr)          # the seams fade out before they all meet at the centre


const AXIS := Vector3(0.0, 1.0, -0.55)      # the bowl is pressed in along this (tilted toward the front)
const CAV_H := 0.50                          # cavity sphere centre, along AXIS from the ball's centre
const CAV_R := 0.42


# how far inside the bowl's footprint a sphere point is, in metres (negative outside)
static func _inside(p: Vector3) -> float:
	var c2 := Vector3(0.0, CENTRE_Y, 0.0) + AXIS.normalized() * CAV_H
	return CAV_R - (p - c2).length()


static func _crater(th: float, ph: float) -> float:
	var st := sin(th)
	var n := Vector3(st * cos(ph), cos(th), st * sin(ph))
	var ry := RY_TOP if n.y > 0.0 else RY_BOT
	return smoothstep(0.0, 0.15, _inside(Vector3(R * n.x, CENTRE_Y + ry * n.y, R * n.z)))


static func _p(th: float, ph: float) -> Vector3:
	var st := sin(th)
	var ct := cos(th)
	var n := Vector3(st * cos(ph), ct, st * sin(ph))
	var ry := RY_TOP if ct > 0.0 else RY_BOT
	var p := Vector3(R * n.x, CENTRE_Y + ry * n.y, R * n.z)
	# the bowl: a sphere scooped out of the top; the fabric inside it lies on the scoop, the rim is rounded off
	var a := AXIS.normalized()
	var c2 := Vector3(0.0, CENTRE_Y, 0.0) + a * CAV_H
	var inside := CAV_R - (p - c2).length()
	var s := smoothstep(0.0, 0.15, inside)
	if inside > 0.0:
		var q := p - c2
		var qa := q.dot(a)
		var t := qa + sqrt(maxf(qa * qa - (q.dot(q) - CAV_R * CAV_R), 0.0))
		p -= a * t * smoothstep(0.0, 0.10, inside)
	# the filling piles up around the rim: a rolled lip all the way round
	var lip := exp(-pow((inside - 0.01) / 0.09, 2.0))
	p += n * 0.045 * lip * (0.35 + 0.65 * clampf(0.5 + 0.5 * n.z, 0.0, 1.0))
	# the sides are not perfectly round: a gentle swell between the seams (the filling pushes the panels out)
	var seam := _seam(ph, R * st, 0.012 + 0.03 * s)
	var panel_swell := 0.008 * (0.5 - 0.5 * cos(GORES * (ph + PI / 2.0))) * st
	# top-stitched seams stand out a touch on the outside and sink into creases inside the bowl
	var ridge := 0.005 * seam * (1.0 - s)
	var groove := -0.035 * seam * s * s
	p += n * (ridge + groove + panel_swell)
	if p.y < 0.0:
		p.y = 0.0
	return p


static func _mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var e := 0.004
	for i in RINGS + 1:
		var th := PI * float(i) / RINGS
		var tn := clampf(th, e, PI - e)
		for j in SEGS + 1:
			var ph := TAU * float(j) / SEGS
			var p := _p(th, ph)
			var dth := _p(tn + e, ph) - _p(tn - e, ph)
			var dph := _p(tn, ph + e) - _p(tn, ph - e)
			var nrm := dph.cross(dth)
			if nrm.length_squared() < 1e-12:
				nrm = Vector3.UP if th < PI / 2.0 else Vector3.DOWN
			verts.append(p)
			norms.append(nrm.normalized())
			var st := sin(th)
			var seam := _seam(ph, R * st) * (1.0 - _crater(th, ph))
			var v := 0.84 + 0.16 * seam
			cols.append(Color(v, v, v))
	for i in RINGS:
		for j in SEGS:
			var a := i * (SEGS + 1) + j
			var b := a + SEGS + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
