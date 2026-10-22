extends Node3D
## Three little photo frames on the dresser: the tuxedo, the calico, and the two of them curled up together.
## A frame stays empty (a faint paw print) until you've met that cat (or seen the pair together). Click a
## filled frame to name the cats, on a little keypad that floats over the dresser.
## The photos are in res://photos/ (made from the in-game models; loaded as plain pictures).

const ScreenUI := preload("res://screen_ui.gd")

const PHOTO_DIR := "res://photos/"
# [key, photo, empty photo, position on the dresser (x, z), picture size]
const FRAMES := [
	["tux", "cat_tux.png", "frame_empty.png", Vector2(-3.70, -1.30 + DZ), Vector2(0.104, 0.13)],
	["both", "cats_together.png", "frame_empty_wide.png", Vector2(-3.72, -1.13 + DZ), Vector2(0.152, 0.114)],
	["calico", "cat_calico.png", "frame_empty.png", Vector2(-3.70, -0.76 + DZ), Vector2(0.104, 0.13)],
]
const DZ := 1.35                            # the dresser moved this far toward the TV
const TOP_Y := 0.76                         # the dresser's top
const BORDER := 0.014
const MAX_NAME := 12

var main: Node3D
var cats: Node3D
var ui: ScreenUI
var _panel_mesh: MeshInstance3D
var _mats := {}                             # key -> the photo's material
var _tags := {}                             # key -> Label3D under the photo
var _editing := "tux"
var _draft := ""
var _name_label: Label
var _who_btns := {}
var _open := false
var _fresh := false                         # the name shown is the old one: the first letter typed replaces it


func setup(m: Node3D, c: Node3D) -> void:
	main = m
	cats = c
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.20, 0.09, 0.12)
	wood.roughness = 0.5
	for f in FRAMES:
		_build_frame(f, wood)
	_build_panel()
	refresh()


func _build_frame(f: Array, wood: Material) -> void:
	var key: String = f[0]
	var pic: Vector2 = f[4]
	var root := Node3D.new()
	root.position = Vector3(f[3].x, TOP_Y, f[3].y)
	root.rotation = Vector3(0.0, PI / 2.0 - 0.18 + 0.12 * FRAMES.find(f), 0.0)     # facing the room, fanned a little
	main.room.add_child(root)
	var tilt := Node3D.new()                 # leaning back on its stand
	tilt.rotation.x = -0.2
	root.add_child(tilt)
	var outer := pic + Vector2(BORDER * 2.0, BORDER * 2.0)
	var box := BoxMesh.new()
	box.size = Vector3(outer.x, outer.y, 0.012)
	var body := MeshInstance3D.new()
	body.mesh = box
	body.material_override = wood
	body.position = Vector3(0, outer.y * 0.5, 0)
	tilt.add_child(body)
	var q := QuadMesh.new()
	q.size = pic
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # a print keeps its own colours under the pink lamps
	pm.albedo_color = Color(0.78, 0.74, 0.76)
	pm.disable_fog = true
	pm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var photo := MeshInstance3D.new()
	photo.mesh = q
	photo.material_override = pm
	photo.position = Vector3(0, outer.y * 0.5, 0.0063)
	tilt.add_child(photo)
	_mats[key] = pm
	var stand := BoxMesh.new()               # the strut behind it, from the dresser up to the frame's back
	stand.size = Vector3(0.012, outer.y * 0.7, 0.005)
	var st := MeshInstance3D.new()
	st.mesh = stand
	st.material_override = wood
	st.position = Vector3(0, outer.y * 0.33, -0.012 - outer.y * 0.33 * sin(0.2) - 0.02)
	st.rotation.x = 0.35
	root.add_child(st)
	var tag := Label3D.new()                 # the name, small, on the bottom of the frame
	tag.font_size = 28
	tag.pixel_size = 0.0003
	tag.outline_size = 0
	tag.modulate = Color(1.0, 0.86, 0.6)
	tag.position = Vector3(0, BORDER * 0.5, 0.0065)
	tilt.add_child(tag)
	_tags[key] = tag
	var k := key
	main.interactables.append({"node": body, "half": Vector3(outer.x * 0.5 + 0.01, outer.y * 0.5 + 0.01, 0.03), "guest_ok": true,
		"label": func() -> String: return _frame_label(k), "cb": func() -> void: _frame_click(k)})


func _frame_label(key: String) -> String:
	if not cats.is_unlocked(key):
		return "AN EMPTY FRAME"
	var who: String = (cats.name_of("tux") + " & " + cats.name_of("calico")) if key == "both" else cats.name_of(key)
	return "%s   (click to name)" % who.to_upper()


func _frame_click(key: String) -> void:
	if not cats.is_unlocked(key):
		return
	if _open:
		close_panel()
		return
	open_panel("tux" if key == "both" else key)


# the photos and name tags, as the cats are met
func refresh() -> void:
	for f in FRAMES:
		var key: String = f[0]
		var on: bool = cats.is_unlocked(key)
		var img := Image.load_from_file(PHOTO_DIR + (f[1] if on else f[2]))
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			var tex := ImageTexture.create_from_image(img)
			_mats[key].albedo_texture = tex
		_tags[key].text = ((cats.name_of("tux") + " & " + cats.name_of("calico")) if key == "both" else cats.name_of(key)) if on else ""
	if _open:
		_render_panel()


# ---- the naming keypad

func _build_panel() -> void:
	var size := Vector2(0.56, 0.44)
	var quad := QuadMesh.new()
	quad.size = size
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/screen.gdshader")
	_panel_mesh = MeshInstance3D.new()
	_panel_mesh.mesh = quad
	_panel_mesh.material_override = sm
	_panel_mesh.position = Vector3(-3.18, 1.12, -1.08 + DZ)
	_panel_mesh.rotation.y = PI / 2.0                # faces +x, into the room
	main.room.add_child(_panel_mesh)
	ui = ScreenUI.new()
	ui.position = _panel_mesh.position + Vector3(0.0005, 0, 0)
	ui.rotation.y = PI / 2.0
	main.room.add_child(ui)
	ui.setup(sm, size, Vector2i(700, 550), 0.0)
	main.screens.append(ui)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.04, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.root.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 14
	col.offset_right = -14
	col.offset_top = 10
	col.offset_bottom = -10
	col.add_theme_constant_override("separation", 6)
	ui.root.add_child(col)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	col.add_child(who)
	for k in ["tux", "calico"]:
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		var kk: String = k
		b.pressed.connect(func() -> void: _pick(kk))
		who.add_child(b)
		_who_btns[k] = b
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 40)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	col.add_child(_name_label)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	col.add_child(grid)
	for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ-'":
		var b := Button.new()
		b.text = ch
		b.custom_minimum_size = Vector2(68, 50)
		b.add_theme_font_size_override("font_size", 24)
		var c: String = ch
		b.pressed.connect(func() -> void: _type(c))
		grid.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	for spec in [["SPACE", func() -> void: _type(" ")], ["DEL", _del], ["DEFAULT", _default], ["DONE", _done]]:
		var b := Button.new()
		b.text = spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 50)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(spec[1])
		row.add_child(b)
	close_panel()


func open_panel(which: String) -> void:
	if cats.showing_hosts_cats():
		main.updater.show_toast("These are the host's cats: the host names them.", 3.0)
		return
	_open = true
	_panel_mesh.visible = true
	ui.enabled = true
	_pick(which)


func close_panel() -> void:
	_open = false
	_panel_mesh.visible = false
	ui.enabled = false
	ui.clear_hover()


func _pick(which: String) -> void:
	if not cats.is_unlocked(which):
		return
	_editing = which
	_draft = cats.name_of(which)
	_fresh = true
	_render_panel()


func _render_panel() -> void:
	for k in _who_btns:
		var b: Button = _who_btns[k]
		var met: bool = cats.is_unlocked(k)
		var label := ("TUXEDO" if k == "tux" else "CALICO")
		b.text = ("[ %s ]" if k == _editing else "%s") % ((label + ":  " + cats.name_of(k)) if met else label + ":  ???")
		b.disabled = not met
	_name_label.text = (_draft if _draft != "" else " ") + ("" if _fresh else "_")


func _type(c: String) -> void:
	if _fresh:
		_draft = ""
		_fresh = false
	if _draft.length() >= MAX_NAME:
		return
	if c == " " and (_draft == "" or _draft.ends_with(" ")):
		return
	_draft += c
	_draft = _tidy(_draft, false)
	_render_panel()


func _del() -> void:
	_fresh = false
	_draft = _draft.left(_draft.length() - 1)
	_render_panel()


func _default() -> void:
	_draft = cats.default_name(_editing)
	_fresh = true
	_render_panel()


func _done() -> void:
	var n := _tidy(_draft, true)
	if n == "":
		n = cats.default_name(_editing)
	cats.set_name_of(_editing, n)
	close_panel()


# "MOCHI" -> "Mochi", "MR WHISKERS" -> "Mr Whiskers"
static func _tidy(s: String, trim: bool) -> String:
	var out := ""
	var start := true
	for ch in s:
		if ch == " " or ch == "-":
			out += ch
			start = true
		elif start:
			out += ch.to_upper()
			start = false
		else:
			out += ch.to_lower()
	return out.strip_edges() if trim else out
