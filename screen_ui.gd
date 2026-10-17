extends Node3D

const LofiTheme := preload("res://lofi_theme.gd")
## A flat in-world screen that shows a 2D UI (drawn in a SubViewport) and can be "clicked"
## by a pointer ray (VR controller or the desktop crosshair).
## Place this node at the centre of the screen quad: local +x is right, +y up, +z the screen normal.

var vp: SubViewport
var root: Control
var screen_size := Vector2(1.0, 1.0)     # metres
var px := Vector2i(1024, 576)            # UI resolution
var curve := 0.0                         # barrel distortion of the glass (CRT)
var last_pos := Vector2(-1000.0, -1000.0)
var enabled := true                      # false = screen is off, the pointer ignores it
var cursor_allowed := true               # false hides the little arrow (e.g. while a video plays)
var _cursor: Node2D


func setup(mat: ShaderMaterial, size_m: Vector2, pixels: Vector2i, glass_curve: float = 0.0) -> void:
	screen_size = size_m
	px = pixels
	curve = glass_curve
	vp = SubViewport.new()
	vp.size = pixels
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = LofiTheme.make()
	vp.add_child(root)

	# little arrow that follows the pointer
	_cursor = Node2D.new()
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 30), Vector2(8, 23), Vector2(14, 36), Vector2(20, 33), Vector2(14, 21), Vector2(24, 21)])
	arrow.color = Color(1, 1, 1)
	_cursor.add_child(arrow)
	var outline := Line2D.new()
	outline.points = arrow.polygon
	outline.closed = true
	outline.width = 3.0
	outline.default_color = Color(0.1, 0.0, 0.2)
	_cursor.add_child(outline)
	_cursor.visible = false
	vp.add_child(_cursor)

	mat.set_shader_parameter("ui_tex", vp.get_texture())
	mat.set_shader_parameter("use_ui", true)


# Returns {} or {"t": distance, "pos": pixel position in the UI} when the ray hits the front of the screen.
func hit(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	if not enabled:
		return {}
	var xf := global_transform
	var n := xf.basis.z.normalized()
	var denom := dir.dot(n)
	if denom > -0.0001:
		return {}
	var t := (xf.origin - origin).dot(n) / denom
	if t < 0.0 or t > max_dist:
		return {}
	var p := origin + dir * t
	var l := xf.affine_inverse() * p
	var x := l.x / screen_size.x + 0.5
	var y := 0.5 - l.y / screen_size.y
	if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
		return {}
	# the CRT shader bends the picture; undo that so the click lands where it looks like it does
	var c := Vector2(x * 2.0 - 1.0, y * 2.0 - 1.0)
	c *= 1.0 + curve * c.length_squared()
	var u := c * 0.5 + Vector2(0.5, 0.5)
	return {"t": t, "pos": Vector2(u.x * px.x, u.y * px.y)}


func send_motion(pos: Vector2, pressed: bool) -> void:
	if pos.is_equal_approx(last_pos):
		return
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = (pos - last_pos) if last_pos.x > -500.0 else Vector2.ZERO
	ev.button_mask = int(MOUSE_BUTTON_MASK_LEFT) if pressed else 0
	vp.push_input(ev, true)
	last_pos = pos
	_cursor.position = pos
	_cursor.visible = cursor_allowed


func send_button(pos: Vector2, pressed: bool) -> void:
	send_motion(pos, pressed)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = int(MOUSE_BUTTON_MASK_LEFT) if pressed else 0
	vp.push_input(ev, true)


func send_scroll(pos: Vector2, up: bool) -> void:
	for state in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = state
		ev.factor = 1.0
		ev.position = pos
		ev.global_position = pos
		vp.push_input(ev, true)


func clear_hover() -> void:
	send_motion(Vector2(-1000.0, -1000.0), false)
	_cursor.visible = false


func set_cursor_allowed(on: bool) -> void:
	cursor_allowed = on
	if not on:
		_cursor.visible = false
