extends Node3D
## A comic you can carry around: two facing pages that float in front of whoever holds it, or lie
## where it was put down for somebody else to pick up. Remembers the page you were on.
## Local +z faces the reader, pages are in the x/y plane.

const ComicBook := preload("res://comic_book.gd")
const ScreenUI := preload("res://screen_ui.gd")

const PAGE_H := 0.40          # metres, the height of a page
const PAGE_W := 0.27          # default width (pages keep their own aspect)
const BOOKMARKS := "user://reader.cfg"

signal turned                 # the reader changed the spread (page turn or contents jump)

var comic: ComicBook
var spread := 0               # 0 = the cover alone, then pairs
var title := ""
var lying := false            # put down somewhere (true) or held (false)
var held_by_me := false
var net_id := ""              # shared with the room: "<owner peer>:<n>" ("" = only on this machine)
var owner_id := 0             # the player whose shelf it came from (they have the file)
var holder_id := 0            # the player holding it (0 = nobody)

var _left: MeshInstance3D
var _right: MeshInstance3D
var _left_m: StandardMaterial3D
var _right_m: StandardMaterial3D
var _left_back: MeshInstance3D
var _right_back: MeshInstance3D
var _label: Label3D
var _shown := [-2, -2]         # page index on each side (-1 = blank)
var _want := [-1, -1]
var toc: ScreenUI              # table of contents on the inside cover of a series (null for a single issue)
var _toc_quad: MeshInstance3D


func _init() -> void:
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.93, 0.90, 0.84)
	paper.roughness = 0.9
	paper.disable_fog = true
	var spine := StandardMaterial3D.new()
	spine.albedo_color = Color(0.15, 0.08, 0.18)
	spine.roughness = 0.7
	spine.disable_fog = true
	_left_back = _box(Vector3(-PAGE_W / 2.0 - 0.005, 0.0, -0.004), Vector3(PAGE_W + 0.01, PAGE_H + 0.012, 0.006), paper)
	_right_back = _box(Vector3(PAGE_W / 2.0 + 0.005, 0.0, -0.004), Vector3(PAGE_W + 0.01, PAGE_H + 0.012, 0.006), paper)
	_box(Vector3(0.0, 0.0, -0.006), Vector3(0.012, PAGE_H + 0.02, 0.014), spine)
	_left_m = _page_mat()
	_right_m = _page_mat()
	_left = _quad(_left_m, Vector3(-PAGE_W / 2.0 - 0.005, 0.0, 0.0))
	_right = _quad(_right_m, Vector3(PAGE_W / 2.0 + 0.005, 0.0, 0.0))
	_label = Label3D.new()
	_label.font_size = 36
	_label.pixel_size = 0.0005
	_label.position = Vector3(0.0, -PAGE_H / 2.0 - 0.035, 0.0)
	_label.modulate = Color(1.0, 0.9, 1.0)
	_label.outline_modulate = Color(0.2, 0.05, 0.3)
	_label.no_depth_test = true
	add_child(_label)


func _page_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED     # pages read like lit paper in the dark room
	m.albedo_color = Color(0.93, 0.90, 0.84)
	m.disable_fog = true
	return m


func _quad(m: Material, pos: Vector3) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(PAGE_W, PAGE_H)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi


func _box(pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi


# ---- contents

func open_file(path: String) -> String:
	comic = ComicBook.new()
	if not comic.open(path):
		var e: String = comic.error
		comic = null
		return e
	title = comic.title
	spread = comic.spread_of(_load_bookmark(path))
	_build_toc()
	_refresh()
	return ""


# a book somebody else opened; `rc` is a RemoteComic that fetches pages over the network
func open_remote(rc: RefCounted) -> void:
	comic = rc
	title = rc.title
	spread = comic.spread_of(_load_bookmark(rc.path))
	_build_toc()
	_refresh()


# ---- table of contents: the inside cover of a series lists its issues; point at one to jump there

func _build_toc() -> void:
	if comic == null or comic.chapters.size() < 2 or toc != null:
		return
	var w := PAGE_W
	toc = ScreenUI.new()
	toc.position = Vector3(-w / 2.0 - 0.005, 0.0, 0.001)
	add_child(toc)
	var q := QuadMesh.new()
	q.size = Vector2(w, PAGE_H)
	_toc_quad = MeshInstance3D.new()
	_toc_quad.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/screen.gdshader")
	_toc_quad.material_override = sm
	toc.add_child(_toc_quad)
	toc.setup(sm, Vector2(w, PAGE_H), Vector2i(540, 800), 0.0)
	toc.set_cursor_allowed(true)
	var bg := ColorRect.new()
	bg.color = Color(0.96, 0.93, 0.87)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toc.root.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24
	scroll.offset_right = -24
	scroll.offset_top = 20
	scroll.offset_bottom = -20
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toc.root.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	scroll.add_child(col)
	var ink := Color(0.16, 0.10, 0.12)
	var t := Label.new()
	t.text = title
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", ink)
	col.add_child(t)
	var sub := Label.new()
	sub.text = "CONTENTS"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.45, 0.35, 0.4))
	col.add_child(sub)
	var last_section := ""
	for i in comic.chapters.size():
		var ch: Dictionary = comic.chapters[i]
		var sec := str(ch.get("section", "Issues"))
		if sec != last_section:
			last_section = sec
			var h := Label.new()
			h.text = sec.to_upper()
			h.add_theme_font_size_override("font_size", 26)
			h.add_theme_color_override("font_color", Color(0.55, 0.25, 0.4))
			col.add_child(h)
		var b := Button.new()
		b.text = "%s    %d p." % [str(ch["title"]), int(ch["count"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 28)
		b.add_theme_color_override("font_color", ink)
		b.add_theme_color_override("font_hover_color", Color(0.75, 0.2, 0.45))
		b.add_theme_color_override("font_pressed_color", Color(0.75, 0.2, 0.45))
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		b.pressed.connect(func() -> void: jump_to_chapter(i))
		col.add_child(b)


func jump_to_chapter(i: int) -> void:
	if comic == null or i < 0 or i >= comic.chapters.size():
		return
	spread = comic.spread_of(int(comic.chapters[i]["first"]))
	_refresh()
	_save_bookmark()
	turned.emit()


func _update_toc() -> void:
	if toc == null:
		return
	var show := spread == 0
	toc.visible = show
	toc.enabled = show and not lying and held_by_me
	if show:
		_left_back.visible = true


func spread_count() -> int:
	if comic == null:
		return 0
	return comic.spreads.size()


# the page the bookmark points at: the right-hand one for a cover, else the left-hand one
func first_page() -> int:
	if comic == null:
		return 0
	var sp: Array = comic.spreads[spread]
	return int(sp[0]) if int(sp[0]) >= 0 else int(sp[1])


func next_spread() -> void:
	if comic != null and spread < spread_count() - 1:
		spread += 1
		_refresh()
		_save_bookmark()
		turned.emit()


func prev_spread() -> void:
	if comic != null and spread > 0:
		spread -= 1
		_refresh()
		_save_bookmark()
		turned.emit()


# somebody else turned the page of this book (seen from across the room)
func show_spread(s: int) -> void:
	if comic == null:
		return
	spread = clampi(s, 0, spread_count() - 1)
	_refresh()


func _refresh() -> void:
	if comic == null:
		return
	var sp: Array = comic.spreads[spread]
	_want = [int(sp[0]), int(sp[1])]
	comic.prefetch(maxi(_want[0], _want[1]))
	_update_toc()
	var p := first_page()
	if comic.chapters.size() > 1:
		var c: int = comic.chapter_of(p)
		var ch: Dictionary = comic.chapters[c]
		_label.text = "%s     %d / %d     %s   (%d / %d)" % [title, c + 1, comic.chapters.size(), str(ch["title"]), p - int(ch["first"]) + 1, int(ch["count"])]
	else:
		_label.text = "%s     %d / %d" % [title, p + 1, comic.page_count()]
	_apply()


func _apply() -> void:
	for side in 2:
		var p: int = _want[side]
		if p == _shown[side]:
			continue
		var mi := _left if side == 0 else _right
		var m := _left_m if side == 0 else _right_m
		var back := _left_back if side == 0 else _right_back
		if p < 0:
			m.albedo_texture = null
			mi.visible = false
			back.visible = side == 1 or (toc != null and spread == 0)     # a blank right page still shows paper; a lone cover has nothing on its left (unless it's the contents page)
			_shown[side] = p
			continue
		var tex := comic.get_page(p)
		if tex == null:
			continue                    # still decoding, try again next frame
		m.albedo_texture = tex
		mi.visible = true
		back.visible = true
		var aspect := float(tex.get_width()) / float(maxi(tex.get_height(), 1))
		var w := minf(PAGE_H * aspect, PAGE_W * 1.35)
		(mi.mesh as QuadMesh).size = Vector2(w, PAGE_H)
		var sign := -1.0 if side == 0 else 1.0
		mi.position.x = sign * (w / 2.0 + 0.005)
		(back.mesh as BoxMesh).size = Vector3(w + 0.01, PAGE_H + 0.012, 0.006)
		back.position.x = mi.position.x
		_shown[side] = p


func _process(_delta: float) -> void:
	if comic != null and (_shown[0] != _want[0] or _shown[1] != _want[1]):
		_apply()


# ---- bookmarks

static func _key(path: String) -> String:
	return path.md5_text()


func _load_bookmark(path: String) -> int:
	var cf := ConfigFile.new()
	if cf.load(BOOKMARKS) == OK:
		return int(cf.get_value("bookmarks", _key(path), 0))
	return 0


func _save_bookmark() -> void:
	if comic == null:
		return
	var cf := ConfigFile.new()
	cf.load(BOOKMARKS)
	cf.set_value("bookmarks", _key(comic.path), first_page())
	cf.set_value("titles", _key(comic.path), comic.path)
	cf.save(BOOKMARKS)


func _exit_tree() -> void:
	if comic != null:
		comic.close()
