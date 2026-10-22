extends Node3D
## A big, soft recliner on the rug that swivels. Point at either arm's end to turn it (45 degrees a click),
## pull the lever on the right side to lean back (the back drops, the footrest comes up and your view tips
## up a little), sit with E / the grip like any seat. It starts facing the window, for the view.
## Local -z is the way it faces; the origin is on the floor under the seat.

signal turned(delta_yaw: float)

const SEAT_H := 0.46
const TURN_STEP := PI / 4.0
const LEATHER := Color(0.36, 0.17, 0.30)
const LEATHER_DK := Color(0.24, 0.10, 0.20)

var reclined := false
var _back: Node3D
var _foot: Node3D
var _lever: Node3D
var _turning := false
var _recline_k := 0.0


func build() -> void:
	var lth := _m(LEATHER, 0.55)
	var dk := _m(LEATHER_DK, 0.6)
	var metal := _m(Color(0.12, 0.11, 0.13), 0.35, 0.7)
	# swivel base: a low dark disc
	_cyl(Vector3(0, 0.03, 0), 0.34, 0.06, metal)
	# the body: a soft box under the seat, the seat cushion on top
	_rbox(Vector3(0, 0.22, 0.02), Vector3(0.74, 0.34, 0.74), dk)
	_rbox(Vector3(0, 0.43, -0.02), Vector3(0.6, 0.14, 0.66), lth)
	# fat rolled arms
	for sx in [-1.0, 1.0]:
		_rbox(Vector3(sx * 0.35, 0.42, 0.0), Vector3(0.18, 0.4, 0.78), lth)
		_cyl(Vector3(sx * 0.35, 0.62, 0.0), 0.095, 0.78, lth).rotation.x = PI / 2.0
	# the back, on a hinge at the back of the seat
	_back = Node3D.new()
	_back.position = Vector3(0, 0.44, 0.32)
	add_child(_back)
	_rbox(Vector3(0, 0.32, 0.03), Vector3(0.62, 0.7, 0.2), lth, _back)
	_rbox(Vector3(0, 0.62, -0.03), Vector3(0.5, 0.16, 0.14), dk, _back)          # head pillow
	for k in 2:                                                                 # tufted cushion lines
		_rbox(Vector3(0, 0.18 + k * 0.2, -0.075), Vector3(0.52, 0.012, 0.01), dk, _back)
	# the footrest, folded under the front until you lean back
	_foot = Node3D.new()
	_foot.position = Vector3(0, 0.34, -0.36)
	add_child(_foot)
	_rbox(Vector3(0, -0.13, -0.04), Vector3(0.56, 0.26, 0.1), lth, _foot)
	# the lever on the right side
	_lever = Node3D.new()
	_lever.position = Vector3(0.45, 0.36, -0.12)
	add_child(_lever)
	_rbox(Vector3(0, 0.0, 0), Vector3(0.025, 0.14, 0.03), metal, _lever)
	_cyl(Vector3(0, 0.08, 0), 0.022, 0.05, _m(Color(0.75, 0.6, 0.4), 0.3, 0.6), _lever).rotation.z = PI / 2.0
	_apply_recline(0.0)


func lever_node() -> Node3D:
	return _lever


func arm_node(side: int) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(side * 0.35, 0.66, -0.36)
	add_child(n)
	return n


func toggle_recline() -> void:
	reclined = not reclined


func turn(dir: int) -> void:
	if _turning:
		return
	_turning = true
	var from := rotation.y
	var to := from - dir * TURN_STEP
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", to, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(func() -> void: _turning = false)
	turned.emit(to - from)


func recline_amount() -> float:
	return smoothstep(0.0, 1.0, _recline_k)


func _process(delta: float) -> void:
	var target := 1.0 if reclined else 0.0
	if not is_equal_approx(_recline_k, target):
		_recline_k = move_toward(_recline_k, target, delta / 0.8)
		_apply_recline(recline_amount())


func _apply_recline(k: float) -> void:
	_back.rotation.x = 0.12 + 0.55 * k             # +x rotation tips the top back (+z)
	_foot.rotation.x = 1.35 * k                     # swings the footrest up and out in front
	_lever.rotation.x = 0.5 * k


static func _m(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.disable_fog = true
	return m


func _rbox(pos: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _cyl(pos: Vector3, r: float, h: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 24
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi
