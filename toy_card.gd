extends RefCounted
## A little folded name card in front of a display figure, like in a shop window.

static var _mat: StandardMaterial3D


# pos: the top of the shelf the figure stands on; yaw: which way the figure faces (+x); ahead: how far in front
static func place(parent: Node3D, pos: Vector3, yaw: float, text: String, ahead: float) -> Node3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.95, 0.93, 0.88)
		_mat.roughness = 0.8
	var c := Node3D.new()
	c.name = "NameCard"
	var fwd := Vector3(cos(yaw), 0.0, -sin(yaw))         # the figure's +x
	c.position = pos + fwd * ahead
	c.rotation.y = yaw + PI / 2.0                         # the card's front (+z) faces the same way as the figure
	parent.add_child(c)
	var card := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.014 + text.length() * 0.009, 0.026, 0.002)
	card.mesh = bm
	card.material_override = _mat
	card.position = Vector3(0, 0.013, 0)
	card.rotation.x = -0.35                               # leaning back
	c.add_child(card)
	var l := Label3D.new()
	l.text = text
	l.font_size = 32
	l.pixel_size = 0.00035
	l.outline_size = 0
	l.modulate = Color(0.12, 0.08, 0.14)
	l.position = Vector3(0, 0, 0.0015)
	card.add_child(l)
	return c
