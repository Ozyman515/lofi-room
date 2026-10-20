extends RefCounted
## A comic: one .cbz (zip of images), or a folder of them read as one book whose issues are chapters.
## Pages are the image files inside each zip, in natural name order ("page 2" before "page 10"); the
## first page of the first issue is the cover. Pages are decoded on worker threads and kept as textures
## for the current spread and its neighbours only, since comic pages are big.

const Plat := preload("res://platform.gd")
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]
const BOOK_EXTS := ["cbz", "zip"]

var path := ""
var title := ""
var error := ""
var chapters: Array = []        # [{"title": String, "path": String, "first": int (global page index), "count": int}]
var pages: Array = []           # global page index -> [zip path, entry name]
var spreads: Array = []         # spread index -> [left page, right page] (-1 = blank); every chapter opens with its cover alone

var _tex := {}             # page index -> ImageTexture
var _tasks := {}           # page index -> WorkerThreadPool task id
var _results := {}         # page index -> Image (filled by the worker)
var _mutex := Mutex.new()
var _max_dim := 2048


# `file_path` is a .cbz or a folder of them
func open(file_path: String) -> bool:
	path = file_path
	title = nice_title(file_path)
	_max_dim = 1600 if Plat.low_power() else 2048
	var files: Array = []
	if DirAccess.dir_exists_absolute(file_path):
		files = issues_in(file_path)
		if files.is_empty():
			error = "No .cbz comics in this folder."
			return false
	else:
		files = [file_path]
	for f in files:
		var entries := _list_pages(f)
		if entries.is_empty():
			if files.size() == 1:
				return false            # `error` is set
			continue                    # a bad issue in a series is skipped
		var first := pages.size()
		for e in entries:
			pages.append([f, e])
		chapters.append({"title": nice_title(f), "path": f, "first": first, "count": entries.size()})
		spreads.append([-1, first])
		var p := first + 1
		while p < first + entries.size():
			spreads.append([p, p + 1 if p + 1 < first + entries.size() else -1])
			p += 2
	if pages.is_empty():
		if error == "":
			error = "No pictures inside this comic."
		return false
	error = ""
	return true


# the .cbz files directly inside a folder, in reading order
static func issues_in(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and BOOK_EXTS.has(n.get_extension().to_lower()) and not n.begins_with("."):
			out.append(dir_path.path_join(n))
		n = d.get_next()
	d.list_dir_end()
	out.sort_custom(func(a: String, b: String) -> bool: return _nat_key(a.get_file()) < _nat_key(b.get_file()))
	return out


func _list_pages(file_path: String) -> Array:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		error = "Can't open this file."
		return []
	var head := f.get_buffer(4)
	f.close()
	if head.size() >= 4 and head[0] == 0x52 and head[1] == 0x61 and head[2] == 0x72 and head[3] == 0x21:
		error = "This one is a RAR comic (.cbr).\nConvert it to .cbz on the PC first."
		return []
	var z := ZIPReader.new()
	if z.open(file_path) != OK:
		error = "This file isn't a zip comic (.cbz)."
		return []
	var names: Array = []
	for n in z.get_files():
		var ext := n.get_extension().to_lower()
		if IMAGE_EXTS.has(ext) and not n.get_file().begins_with(".") and not n.contains("__MACOSX"):
			names.append(n)
	z.close()
	if names.is_empty():
		error = "No pictures inside this comic."
		return []
	names.sort_custom(func(a: String, b: String) -> bool: return _nat_key(a) < _nat_key(b))
	return names


func page_count() -> int:
	return pages.size()


func chapter_of(page: int) -> int:
	var c := 0
	for i in chapters.size():
		if page >= int(chapters[i]["first"]):
			c = i
	return c


func spread_of(page: int) -> int:
	for i in spreads.size():
		if spreads[i][0] == page or spreads[i][1] == page:
			return i
	return 0


# "Saga v01 (2012) (digital) (Zone-Empire).cbz" -> "Saga v01"
static func nice_title(file_path: String) -> String:
	var t := file_path.get_file()
	if not DirAccess.dir_exists_absolute(file_path):
		t = t.get_basename()
	var re := RegEx.new()
	re.compile("\\s*[\\(\\[][^\\)\\]]*[\\)\\]]")
	t = re.sub(t, "", true)
	t = t.replace("_", " ").strip_edges()
	return t if t != "" else file_path.get_file()


static func _nat_key(s: String) -> String:
	var re := RegEx.new()
	re.compile("\\d+")
	var out := ""
	var last := 0
	for m in re.search_all(s.to_lower()):
		out += s.substr(last, m.get_start() - last).to_lower()
		out += m.get_string().lpad(10, "0")
		last = m.get_end()
	return out + s.substr(last).to_lower()


# The texture for a page, or null while it is still being decoded (call again next frame).
func get_page(i: int) -> ImageTexture:
	if i < 0 or i >= pages.size():
		return null
	if _tex.has(i):
		return _tex[i]
	_collect()
	if _tex.has(i):
		return _tex[i]
	if not _tasks.has(i):
		_start(i)
	return null


# Start decoding pages that will be needed soon; drop the ones far away.
func prefetch(center: int, span := 3) -> void:
	for i in range(center - span, center + span + 1):
		if i >= 0 and i < pages.size() and not _tex.has(i) and not _tasks.has(i):
			_start(i)
	for k in _tex.keys():
		if absi(k - center) > span + 1:
			_tex.erase(k)


func _start(i: int) -> void:
	var zp: String = pages[i][0]
	var name: String = pages[i][1]
	var md := _max_dim
	_tasks[i] = WorkerThreadPool.add_task(func() -> void:
		var img := _decode(zp, name, md)
		_mutex.lock()
		_results[i] = img
		_mutex.unlock())


func _collect() -> void:
	for i in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.erase(i)
			_mutex.lock()
			var img: Image = _results.get(i)
			_results.erase(i)
			_mutex.unlock()
			if img != null:
				_tex[i] = ImageTexture.create_from_image(img)
			else:
				_tex[i] = null


static func _decode(zip_path: String, name: String, max_dim: int) -> Image:
	var z := ZIPReader.new()
	if z.open(zip_path) != OK:
		return null
	var data := z.read_file(name)
	z.close()
	if data.is_empty():
		return null
	var img := Image.new()
	var ext := name.get_extension().to_lower()
	var err := ERR_INVALID_DATA
	match ext:
		"png": err = img.load_png_from_buffer(data)
		"jpg", "jpeg": err = img.load_jpg_from_buffer(data)
		"webp": err = img.load_webp_from_buffer(data)
		"bmp": err = img.load_bmp_from_buffer(data)
		"tga": err = img.load_tga_from_buffer(data)
	if err != OK:
		# wrong extension: sniff the common ones
		if img.load_png_from_buffer(data) != OK and img.load_jpg_from_buffer(data) != OK and img.load_webp_from_buffer(data) != OK:
			return null
	if img.get_width() == 0:
		return null
	var w := img.get_width()
	var h := img.get_height()
	var big := maxi(w, h)
	if big > max_dim:
		var k := float(max_dim) / float(big)
		img.resize(int(w * k), int(h * k), Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func close() -> void:
	for i in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(_tasks[i])
	_tasks.clear()
	_tex.clear()
	_results.clear()
