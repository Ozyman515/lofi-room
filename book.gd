extends Node3D
## A comic you can carry around: two facing pages that float in front of whoever holds it, or lie
## where it was put down for somebody else to pick up. Remembers the page you were on.
## Local +z faces the reader, pages are in the x/y plane.

const ComicBook := preload("res://comic_book.gd")

const PAGE_H := 0.40          # metres, the height of a page
const PAGE_W := 0.27          # default width (pages keep their own aspect)
const BOOKMARKS := "user://reader.cfg"

var comic: ComicBook
var spread := 0               # 0 = the cover alone, then pairs
var title := ""
var lying := false            # put down somewhere (true) or held (false)
var held_by_me := false

var _left: MeshInstance3D
var _right: MeshInstance3D
var _left_m: StandardMaterial3D
var _right_m: StandardMaterial3D
var _left_back: MeshInstance3D
var _right_back: MeshInstance3D
var _label: Label3D
var _shown := [-2, -2]         # page index on each side (-1 = blank)
var _want := [-1, -1]


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
	_refresh()
	return ""


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


func prev_spread() -> void:
	if comic != null and spread > 0:
		spread -= 1
		_refresh()
		_save_bookmark()


func _refresh() -> void:
	if comic == null:
		return
	var sp: Array = comic.spreads[spread]
	_want = [int(sp[0]), int(sp[1])]
	comic.prefetch(maxi(_want[0], _want[1]))
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
			back.visible = side == 1       # a blank right page still shows paper; a cover sits alone on the right, nothing on its left
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
