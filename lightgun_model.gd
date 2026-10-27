extends RefCounted
## The light gun: Dead Rail's pistol (slide, frame, sights, trigger guard, angled grip), built from boxes, in a colour
## scheme per console. Muzzle points -z, the grip hangs down; about 21 cm long like a real one. build(style) where
## style is "deadrail" (as in Dead Rail), "nes", "snes", "gen" or "ps".

const STYLES := {
	"deadrail": {"slide": Color(0.22, 0.23, 0.26), "frame": Color(0.09, 0.09, 0.1), "grip": Color(0.18, 0.12, 0.08), "tip": Color(0.09, 0.09, 0.1), "trim": Color(0.09, 0.09, 0.1)},
	"nes": {"slide": Color(0.62, 0.62, 0.64), "frame": Color(0.3, 0.3, 0.32), "grip": Color(0.3, 0.3, 0.32), "tip": Color(1.0, 0.45, 0.08), "trim": Color(0.75, 0.12, 0.12)},
	"snes": {"slide": Color(0.78, 0.78, 0.8), "frame": Color(0.45, 0.42, 0.62), "grip": Color(0.45, 0.42, 0.62), "tip": Color(1.0, 0.45, 0.08), "trim": Color(0.55, 0.4, 0.85)},
	"gen": {"slide": Color(0.12, 0.12, 0.13), "frame": Color(0.06, 0.06, 0.07), "grip": Color(0.06, 0.06, 0.07), "tip": Color(1.0, 0.45, 0.08), "trim": Color(0.8, 0.1, 0.1)},
	"ps": {"slide": Color(0.55, 0.56, 0.6), "frame": Color(0.2, 0.21, 0.24), "grip": Color(0.2, 0.21, 0.24), "tip": Color(1.0, 0.45, 0.08), "trim": Color(0.2, 0.45, 0.95)},
}


static func build(style := "deadrail") -> Node3D:
	var c: Dictionary = STYLES.get(style, STYLES["deadrail"])
	var g := Node3D.new()
	g.name = "LightGun"
	var shiny := style != "deadrail"
	_part(g, Vector3(0.036, 0.042, 0.18), c["slide"], Vector3(0, 0.022, -0.07), shiny)          # slide
	_part(g, Vector3(0.032, 0.026, 0.13), c["frame"], Vector3(0, -0.008, -0.045), shiny)        # frame
	_part(g, Vector3(0.017, 0.017, 0.02), c["tip"], Vector3(0, 0.022, -0.165), false)            # muzzle
	_part(g, Vector3(0.008, 0.012, 0.012), c["frame"], Vector3(0, 0.048, -0.15), false)         # front sight
	_part(g, Vector3(0.024, 0.01, 0.012), c["frame"], Vector3(0, 0.048, 0.01), false)           # rear sight
	_part(g, Vector3(0.008, 0.026, 0.045), c["frame"], Vector3(0, -0.033, -0.035), false)       # trigger guard
	_part(g, Vector3(0.006, 0.018, 0.008), c["trim"], Vector3(0, -0.026, -0.03), false)         # trigger
	var grip := _part(g, Vector3(0.03, 0.11, 0.046), c["grip"], Vector3(0, -0.065, 0.015), false)
	grip.rotation.x = -0.28
	if style != "deadrail":
		# a stripe down each side of the slide, and the cable out of the bottom of the grip
		for sx in [-1.0, 1.0]:
			_part(g, Vector3(0.002, 0.006, 0.15), c["trim"], Vector3(sx * 0.0185, 0.022, -0.075), false)
		var cable := _part(g, Vector3(0.008, 0.06, 0.008), Color(0.08, 0.08, 0.09), Vector3(0, -0.14, 0.04), false)
		cable.rotation.x = -0.28
	return g


static func _part(parent: Node3D, size: Vector3, col: Color, pos: Vector3, shiny: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.35 if shiny else 0.6
	m.metallic = 0.2 if shiny else 0.1
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi
