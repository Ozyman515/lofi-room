extends Node
## Turns the text of an ebook into page pictures. One hidden page-sized viewport with a rich-text label:
## chapters are laid out once to find where each page starts, then pages are drawn on demand (two
## frames each) and handed back as textures, which the book shows exactly like comic pages.

const PAGE_PX := Vector2i(900, 1350)       # 2:3, like a comic page
const MARGIN := 64
const FONT_SIZE := 34
const INK := Color(0.13, 0.09, 0.10)
const PAPER := Color(0.96, 0.93, 0.87)

var _vp: SubViewport
var _clip: Control
var _label: RichTextLabel
var _queue: Array = []                     # [comic, page index]
var _busy := false
var _laid_out := ""                        # which chapter text is currently in the label


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = PAGE_PX
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.size = Vector2(PAGE_PX)
	_vp.add_child(bg)
	_clip = Control.new()
	_clip.position = Vector2(MARGIN, MARGIN)
	_clip.size = Vector2(PAGE_PX.x - 2 * MARGIN, PAGE_PX.y - 2 * MARGIN)
	_clip.clip_contents = true
	_vp.add_child(_clip)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.fit_content = true
	_label.size = Vector2(_clip.size.x, 10)
	_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_label.add_theme_font_size_override("bold_font_size", FONT_SIZE)
	_label.add_theme_font_size_override("italics_font_size", FONT_SIZE)
	_label.add_theme_font_size_override("bold_italics_font_size", FONT_SIZE)
	_label.add_theme_color_override("default_color", INK)
	_label.add_theme_constant_override("line_separation", 6)
	_clip.add_child(_label)


func page_height() -> float:
	return _clip.size.y


# Lays a chapter out and returns the first wrapped line of every page.
func paginate(bbcode: String) -> PackedInt32Array:
	_set_text(bbcode)
	var n := _label.get_line_count()
	var starts := PackedInt32Array()
	if n == 0:
		starts.append(0)
		return starts
	var h := page_height()
	var s := 0
	while s < n:
		starts.append(s)
		var top := _label.get_line_offset(s)
		var last := s
		while last + 1 < n and _label.get_line_offset(last + 1) + _label.get_line_height(last + 1) <= top + h:
			last += 1
		s = last + 1
	return starts


func _set_text(bbcode: String) -> void:
	if _laid_out == bbcode:
		return
	_laid_out = bbcode
	_label.text = bbcode
	_label.size = Vector2(_clip.size.x, 10)
	_label.get_line_count()      # forces the layout


# Ask for a page picture; the comic gets it back through receive_text_page(page, image).
func request(comic: RefCounted, page: int) -> void:
	for q in _queue:
		if q[0] == comic and q[1] == page:
			return
	_queue.append([comic, page])
	if not _busy:
		_pump()


func _pump() -> void:
	_busy = true
	while not _queue.is_empty():
		var job: Array = _queue.pop_front()
		var comic: RefCounted = job[0]
		var page: int = job[1]
		var where: Array = comic.text_page_location(page)      # [chapter bbcode, first line]
		if where.is_empty():
			comic.receive_text_page(page, null)
			continue
		_set_text(where[0])
		var line: int = where[1]
		_label.position.y = -_label.get_line_offset(line) if line < _label.get_line_count() else 0.0
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		if img != null:
			img.convert(Image.FORMAT_RGB8)
			img.generate_mipmaps()
		comic.receive_text_page(page, img)
	_busy = false
