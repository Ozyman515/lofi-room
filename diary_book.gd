extends Node3D
## A small diary lying on the nightstand. Pick it up and it opens in front of you like a book, listing
## what you've read and played; point at a comic entry to open that book where you left off.
## Built on ScreenUI so the entries are clickable.

const ScreenUI := preload("res://screen_ui.gd")
const Diary := preload("res://diary.gd")

const W := 0.17
const H := 0.23
const PX := Vector2i(560, 768)

var ui: ScreenUI
var cover: MeshInstance3D
var open_book := false
var _list: VBoxContainer
var _main: Node3D


func build(main: Node3D) -> void:
	_main = main
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.36, 0.14, 0.22)
	leather.roughness = 0.55
	leather.disable_fog = true
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.93, 0.90, 0.84)
	paper.roughness = 0.9
	paper.disable_fog = true
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.85, 0.65, 0.25)
	band.roughness = 0.5
	band.disable_fog = true
	# closed: a little book lying flat, cover up
	cover = _box(Vector3(0, 0.011, 0), Vector3(W, 0.022, H), leather)
	_box(Vector3(0, 0.010, 0), Vector3(W - 0.012, 0.018, H - 0.012), paper)
	_box(Vector3(W / 2.0 - 0.025, 0.0225, 0), Vector3(0.012, 0.002, H), band)
	# open: the right-hand page is a screen with the entries (shown only while held)
	var quad := QuadMesh.new()
	quad.size = Vector2(W, H)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/screen.gdshader")
	ui = ScreenUI.new()
	ui.position = Vector3(0, 0, 0)
	add_child(ui)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = sm
	ui.add_child(mi)
	ui.setup(sm, Vector2(W, H), PX, 0.0)
	ui.visible = false
	ui.enabled = false
	_build_ui()


func _box(pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.95, 0.92, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.root.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 26
	scroll.offset_right = -22
	scroll.offset_top = 22
	scroll.offset_bottom = -20
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var ink := Color(0.16, 0.10, 0.12)
	var faint := Color(0.45, 0.35, 0.4)
	var t := Label.new()
	t.text = "Diary"
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", ink)
	_list.add_child(t)
	var entries := Diary.entries()
	if entries.is_empty():
		var l := Label.new()
		l.text = "\nNothing yet.\n\nRead a comic or play a game and it will be noted here."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", faint)
		_list.add_child(l)
		return
	var last_day := ""
	for e in entries:
		var day := Diary.fmt_when(int(e["when"]))
		if day != last_day:
			last_day = day
			var h := Label.new()
			h.text = day
			h.add_theme_font_size_override("font_size", 20)
			h.add_theme_color_override("font_color", Color(0.6, 0.25, 0.45))
			_list.add_child(h)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		_list.add_child(row)
		var is_book: bool = e["kind"] == "book"
		var title: Control = Button.new() if is_book else Label.new()
		title.set("text", ({"book": "[comic]  ", "cat": "[cat]  "} as Dictionary).get(str(e["kind"]), "[game]  ") + str(e["title"]))
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", ink)
		if is_book:
			var b := title as Button
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = false
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.add_theme_color_override("font_hover_color", Color(0.75, 0.2, 0.45))
			b.add_theme_color_override("font_pressed_color", Color(0.75, 0.2, 0.45))
			for st in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			var path := str(e["path"])
			b.pressed.connect(func() -> void: _open(path))
		else:
			(title as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(title)
		var d := Label.new()
		d.text = "     " + str(e["detail"])
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 18)
		d.add_theme_color_override("font_color", faint)
		row.add_child(d)


func _open(path: String) -> void:
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		_main.updater.show_toast("That book isn't in the books folder any more.", 4.0)
		return
	_main.put_diary()
	_main._open_book(path)


func set_open(on: bool) -> void:
	open_book = on
	ui.visible = on
	ui.enabled = on
	cover.visible = not on
	for c in get_children():
		if c != ui and c is MeshInstance3D:
			c.visible = not on
	if on:
		refresh()
