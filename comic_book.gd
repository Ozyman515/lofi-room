extends RefCounted
## A comic: one .cbz (zip of images), or a folder of them read as one book whose issues are chapters.
## Pages are the image files inside each zip, in natural name order ("page 2" before "page 10"); the
## first page of the first issue is the cover. Pages are decoded on worker threads and kept as textures
## for the current spread and its neighbours only, since comic pages are big.

const Plat := preload("res://platform.gd")
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]
const BOOK_EXTS := ["cbz", "zip", "pdf", "epub"]

var path := ""
var title := ""
var error := ""
var chapters: Array = []        # [{"title": String, "path": String, "first": int (global page index), "count": int, "section": String}]
const EXTRA_WORDS := ["annual", "special", "one-shot", "oneshot", "one shot", "preview", "extra", "giant", "ashcan", "sketchbook", "companion", "prelude", "epilogue", "directors cut", "director's cut", "variant", "fcbd", "free comic book day", "halloween", "holiday"]
var pages: Array = []           # global page index -> [zip path, entry name]
var spreads: Array = []         # spread index -> [left page, right page] (-1 = blank); every chapter opens with its cover alone

static var renderer: Node     # the page_renderer that draws ebook text (set by main)
var text_mode := false        # an ebook: pages are drawn from text, not read from files
var _text_chapters: Array = []    # [{"bbcode": String, "starts": PackedInt32Array}]
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
	# the regular run first, then the annuals, specials and one-shots as their own section
	if files.size() > 1:
		var main: Array = []
		var extras: Array = []
		for f in files:
			(extras if is_extra(f.get_file()) else main).append(f)
		files = main + extras
	files_count = files.size()
	if files.size() == 1 and files[0].get_extension().to_lower() == "epub" and _open_text_epub(files[0]):
		return true
	for f in files:
		var entries := _list_pages(f)
		if text_mode:
			return true
		if entries.is_empty():
			if files.size() == 1:
				return false            # `error` is set
			continue                    # a bad issue in a series is skipped
		var first := pages.size()
		for e in entries:
			pages.append([f, e])
		var ct := nice_title(f)
		if files.size() > 1 and ct.length() > title.length() + 1 and ct.to_lower().begins_with(title.to_lower()):
			ct = ct.substr(title.length()).strip_edges(true, false).trim_prefix("-").strip_edges()     # "#002" instead of "Series #002"
		chapters.append({"title": ct, "path": f, "first": first, "count": entries.size(),
			"section": "Extras" if (files.size() > 1 and is_extra(f.get_file())) else "Issues"})
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


static func is_extra(file_name: String) -> bool:
	var n := file_name.to_lower()
	for w in EXTRA_WORDS:
		if n.contains(w):
			return true
	return false


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


var files_count := 1


func _list_pages(file_path: String) -> Array:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		error = "Can't open this file."
		return []
	var head := f.get_buffer(4)
	f.close()
	if head.size() >= 4 and head[0] == 0x25 and head[1] == 0x50 and head[2] == 0x44 and head[3] == 0x46:     # %PDF
		var pp := _list_pdf_pages(file_path)
		if pp.is_empty() and files_count == 1 and _open_text_pdf(file_path):
			return ["text"]          # a marker: the book was built from text already
		return pp
	if file_path.get_extension().to_lower() == "epub":
		var ep := _list_epub_pages(file_path)
		if not ep.is_empty():
			return ep
		# not a picture book: fall through and treat it as a zip of images (fixed-layout comics often work that way)
		if error != "":
			return []
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
	if text_mode:
		if renderer != null:
			renderer.request(self, i)
		return null
	_collect()
	if _tex.has(i):
		return _tex[i]
	if not _tasks.has(i):
		_start(i)
	return null


# Start decoding pages that will be needed soon; drop the ones far away.
func prefetch(center: int, span := 3) -> void:
	if text_mode:
		for i in range(center - 1, center + 3):
			if i >= 0 and i < pages.size() and not _tex.has(i) and renderer != null:
				renderer.request(self, i)
		for k in _tex.keys():
			if absi(k - center) > 6:
				_tex.erase(k)
		return
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
				_tex[i] = ImageTexture.create_from_image(img)       # mipmaps were generated on the worker
			else:
				_tex[i] = null


static func _decode(zip_path: String, name: String, max_dim: int) -> Image:
	if name.begins_with("pdf:"):
		return _decode_pdf_image(zip_path, name, max_dim)
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
	img.generate_mipmaps()
	return img


func close() -> void:
	for i in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(_tasks[i])
	_tasks.clear()
	_tex.clear()
	_results.clear()


# ---------------------------------------------------------------- the owner's side of sharing: pages as JPEG for the network

var _jpeg_tasks := {}       # page -> task id
var _jpeg_results := {}     # page -> PackedByteArray


func request_jpeg(i: int) -> void:
	if i < 0 or i >= pages.size() or _jpeg_tasks.has(i):
		return
	if text_mode:
		_jpeg_tasks[i] = -1              # a marker: taken from the rendered page when it is ready
		get_page(i)
		return
	var zp: String = pages[i][0]
	var name: String = pages[i][1]
	_jpeg_tasks[i] = WorkerThreadPool.add_task(func() -> void:
		var img := _decode(zp, name, 1400)
		var bytes := PackedByteArray()
		if img != null:
			if img.get_format() == Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGB8)
			bytes = img.save_jpg_to_buffer(0.78)
		_mutex.lock()
		_jpeg_results[i] = bytes
		_mutex.unlock())


# {page: bytes} for the pages whose JPEG is ready (empty bytes = could not be read)
func take_jpegs() -> Dictionary:
	var out := {}
	for i in _jpeg_tasks.keys():
		if int(_jpeg_tasks[i]) == -1:
			var t: ImageTexture = _tex.get(i)
			if t != null:
				_jpeg_tasks.erase(i)
				out[i] = t.get_image().save_jpg_to_buffer(0.85)
			elif _tex.has(i):
				_jpeg_tasks.erase(i)
				out[i] = PackedByteArray()
			continue
		if WorkerThreadPool.is_task_completed(_jpeg_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_jpeg_tasks[i])
			_jpeg_tasks.erase(i)
			_mutex.lock()
			out[i] = _jpeg_results.get(i, PackedByteArray())
			_jpeg_results.erase(i)
			_mutex.unlock()
	return out


func meta() -> Dictionary:
	var ch: Array = []
	for c in chapters:
		ch.append({"title": c["title"], "first": c["first"], "count": c["count"], "section": c.get("section", "Issues")})
	return {"title": title, "pages": pages.size(), "spreads": spreads, "chapters": ch}


# ---------------------------------------------------------------- PDF: the pictures inside, in file order
# Godot has no PDF renderer, but scanned comics and manga PDFs are just a JPEG per page wrapped in PDF.
# We pull those out (DCTDecode), plus plain zlib-packed RGB/grey images (FlateDecode). Text PDFs give nothing.

const PDF_CHUNK := 8 * 1024 * 1024
const PDF_OVERLAP := 64 * 1024


func _list_pdf_pages(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		error = "Can't open this file."
		return []
	var size := f.get_length()
	var out: Array = []
	var seen := {}
	var pos := 0
	while pos < size:
		f.seek(pos)
		var chunk := f.get_buffer(mini(PDF_CHUNK, size - pos))
		# binary data has NUL bytes that cut a String short, so the search runs on the hex form (two chars per byte)
		var hx := chunk.hex_encode()
		var at := 0
		while true:
			var i := hx.find(HEX_SUBTYPE, at)
			if i < 0 or i % 2 == 1:
				if i < 0:
					break
				at = i + 1
				continue
			at = i + HEX_SUBTYPE.length()
			# the dictionary this belongs to: back to "obj", forward to "stream"
			var dstart := _hex_rfind(hx, HEX_OBJ, i)
			var dend := _hex_find(hx, HEX_STREAM, i)
			if dstart < 0 or dend < 0 or dend - dstart > 8000:
				continue
			var d := hx.substr(dstart, dend - dstart).hex_decode().get_string_from_ascii()
			dstart /= 2
			dend /= 2
			if not d.contains("/Image") or d.contains("/SMask ") and d.find("/Type") < 0:
				continue
			var filt := ""
			if d.contains("/DCTDecode"):
				filt = "dct"
			elif d.contains("/FlateDecode"):
				filt = "flate"
			else:
				continue
			var w := _pdf_int(d, "/Width")
			var h := _pdf_int(d, "/Height")
			if w <= 0 or h <= 0 or w * h < 120000:
				continue              # icons and thumbnails
			var cs := "rgb"
			if d.contains("/DeviceGray") or d.contains("/CalGray"):
				cs = "gray"
			elif d.contains("/DeviceCMYK"):
				cs = "cmyk"
			if filt == "flate" and (cs == "cmyk" or _pdf_int(d, "/BitsPerComponent") != 8 or d.contains("/Predictor")):
				continue
			var data_start := dend + 6
			if data_start < chunk.size() and chunk[data_start] == 0x0D:
				data_start += 1
			if data_start < chunk.size() and chunk[data_start] == 0x0A:
				data_start += 1
			var length := _pdf_int(d, "/Length")
			var abs_start := pos + data_start
			if length <= 0 or d.contains("/Length " + str(length) + " 0 R"):
				length = -1        # indirect: measure to "endstream" when decoding
			if seen.has(abs_start):
				continue
			seen[abs_start] = true
			out.append("pdf:%d:%d:%s:%d:%d:%s" % [abs_start, length, filt, w, h, cs])
		pos += PDF_CHUNK - PDF_OVERLAP
	f.close()
	if out.is_empty():
		error = "No picture pages in this PDF.\nText PDFs aren't supported yet."
		return []
	out.sort_custom(func(a: String, b: String) -> bool: return int(a.split(":")[1]) < int(b.split(":")[1]))
	return out


const HEX_SUBTYPE := "2f53756274797065"     # "/Subtype"
const HEX_OBJ := "6f626a"                   # "obj"
const HEX_STREAM := "73747265616d"          # "stream"
const HEX_ENDSTREAM := "656e6473747265616d" # "endstream"


# find/rfind on hex text, only at even positions (byte boundaries)
static func _hex_find(hx: String, pat: String, from: int) -> int:
	var i := hx.find(pat, from)
	while i >= 0 and i % 2 == 1:
		i = hx.find(pat, i + 1)
	return i


static func _hex_rfind(hx: String, pat: String, from: int) -> int:
	var i := hx.rfind(pat, from)
	while i >= 0 and i % 2 == 1:
		i = hx.rfind(pat, i - 1)
	return i


static func _pdf_int(d: String, key: String) -> int:
	var i := d.find(key)
	if i < 0:
		return -1
	var j := i + key.length()
	while j < d.length() and d[j] == " ":
		j += 1
	var k := j
	while k < d.length() and d[k].is_valid_int():
		k += 1
	return int(d.substr(j, k - j)) if k > j else -1


static func _decode_pdf_image(path: String, desc: String, max_dim: int) -> Image:
	var parts := desc.split(":")
	if parts.size() < 7:
		return null
	var start := int(parts[1])
	var length := int(parts[2])
	var filt := parts[3]
	var w := int(parts[4])
	var h := int(parts[5])
	var cs := parts[6]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	f.seek(start)
	var data: PackedByteArray
	if length > 0:
		data = f.get_buffer(length)
	else:
		# length unknown: read generously and cut at "endstream"
		var buf := f.get_buffer(mini(64 * 1024 * 1024, f.get_length() - start))
		var e := _hex_find(buf.hex_encode(), HEX_ENDSTREAM, 0)
		data = buf.slice(0, e / 2 if e > 0 else buf.size())
	f.close()
	var img := Image.new()
	if filt == "dct":
		img = preload("res://safe_image.gd").jpeg(data, 12000)
		if img == null:
			return null
	else:
		if w <= 0 or h <= 0 or w > 12000 or h > 12000:
			return null                        # a page claiming to be enormous: not unpacked
		var raw := data.decompress_dynamic(w * h * 4 + 1024, FileAccess.COMPRESSION_DEFLATE)
		var chans := 1 if cs == "gray" else 3
		if raw.size() < w * h * chans:
			return null
		img = Image.create_from_data(w, h, false, Image.FORMAT_L8 if chans == 1 else Image.FORMAT_RGB8, raw.slice(0, w * h * chans))
	if img.get_width() == 0:
		return null
	var big := maxi(img.get_width(), img.get_height())
	if big > max_dim:
		var k := float(max_dim) / float(big)
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return img


# ---------------------------------------------------------------- EPUB: picture books (fixed-layout comics) in reading order
# The OPF file lists the chapters in order; each chapter page is a bit of HTML with one image in it.

func _list_epub_pages(path: String) -> Array:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return []
	var files := z.get_files()
	var opf_path := ""
	if files.has("META-INF/container.xml"):
		var c := z.read_file("META-INF/container.xml").get_string_from_utf8()
		var m := RegEx.new()
		m.compile("full-path=\"([^\"]+)\"")
		var r := m.search(c)
		if r != null:
			opf_path = r.get_string(1)
	if opf_path == "" or not files.has(opf_path):
		for n in files:
			if n.get_extension().to_lower() == "opf":
				opf_path = n
				break
	if opf_path == "":
		z.close()
		return []
	var opf := z.read_file(opf_path).get_string_from_utf8()
	var base := opf_path.get_base_dir()
	var items := {}
	var re_item := RegEx.new()
	re_item.compile("<item\\s[^>]*?>")
	var re_attr := RegEx.new()
	re_attr.compile("(id|href|media-type)=\"([^\"]*)\"")
	for m in re_item.search_all(opf):
		var a := {}
		for am in re_attr.search_all(m.get_string()):
			a[am.get_string(1)] = am.get_string(2)
		if a.has("id") and a.has("href"):
			items[a["id"]] = a
	var re_ref := RegEx.new()
	re_ref.compile("<itemref\\s[^>]*?idref=\"([^\"]+)\"")
	var out: Array = []
	var re_img := RegEx.new()
	re_img.compile("<(?:img|image)\\s[^>]*?(?:src|href|xlink:href)=\"([^\"]+)\"")
	for m in re_ref.search_all(opf):
		var it: Dictionary = items.get(m.get_string(1), {})
		if it.is_empty():
			continue
		var href := _epub_join(base, str(it["href"]))
		if not files.has(href):
			continue
		var mt := str(it.get("media-type", ""))
		if mt.begins_with("image/"):
			out.append(href)
			continue
		var html := z.read_file(href).get_string_from_utf8()
		var im := re_img.search(html)
		if im != null:
			var ip := _epub_join(href.get_base_dir(), im.get_string(1).uri_decode())
			if files.has(ip) and IMAGE_EXTS.has(ip.get_extension().to_lower()):
				out.append(ip)
	z.close()
	return out


static func _epub_join(base: String, rel: String) -> String:
	if rel.begins_with("/"):
		return rel.substr(1)
	var parts := (base.path_join(rel) if base != "" else rel).split("/")
	var stack: Array = []
	for p in parts:
		if p == "..":
			if not stack.is_empty():
				stack.pop_back()
		elif p != "." and p != "":
			stack.append(p)
	return "/".join(stack)


# ---------------------------------------------------------------- EPUB: novels (text), drawn into pages by page_renderer

func _open_text_epub(file_path: String) -> bool:
	if renderer == null:
		return false
	var z := ZIPReader.new()
	if z.open(file_path) != OK:
		return false
	var files := z.get_files()
	var opf_path := _epub_opf(z, files)
	if opf_path == "":
		z.close()
		return false
	var opf := z.read_file(opf_path).get_string_from_utf8()
	var base := opf_path.get_base_dir()
	var items := _epub_items(opf)
	var re_ref := RegEx.new()
	re_ref.compile("<itemref\\s[^>]*?idref=\"([^\"]+)\"")
	var book_title := ""
	var mt := RegEx.new()
	mt.compile("<dc:title[^>]*>([^<]+)</dc:title>")
	var tm := mt.search(opf)
	if tm != null:
		book_title = _entities(tm.get_string(1)).strip_edges()
	var chapters_bb: Array = []
	var total_text := 0
	for m in re_ref.search_all(opf):
		var it: Dictionary = items.get(m.get_string(1), {})
		if it.is_empty():
			continue
		var href := _epub_join(base, str(it["href"]))
		if not files.has(href) or not str(it.get("media-type", "")).contains("html"):
			continue
		var html := z.read_file(href).get_string_from_utf8()
		var conv := html_to_bbcode(html)
		var plain: String = conv["plain"]
		if plain.strip_edges().length() < 40:
			continue                                   # cover pages, blank separators
		total_text += plain.length()
		chapters_bb.append({"title": conv["title"], "bbcode": conv["bbcode"]})
	z.close()
	if chapters_bb.is_empty() or total_text < 2000:
		return false                                   # not a novel: let the picture-book route have it
	text_mode = true
	if book_title != "":
		title = book_title
	pages = []
	chapters = []
	spreads = []
	for ci in chapters_bb.size():
		var ch: Dictionary = chapters_bb[ci]
		var starts: PackedInt32Array = renderer.paginate(ch["bbcode"])
		var first := pages.size()
		for k in starts.size():
			pages.append(["text", "%d:%d" % [ci, k]])
		_text_chapters.append({"bbcode": ch["bbcode"], "starts": starts})
		var ctitle: String = str(ch["title"]) if str(ch["title"]) != "" else "Chapter %d" % (ci + 1)
		chapters.append({"title": ctitle, "path": "", "first": first, "count": starts.size(), "section": "Chapters"})
	# spreads run straight through: a novel's pages pair up left/right from the first page
	var p := 0
	while p < pages.size():
		spreads.append([p, p + 1 if p + 1 < pages.size() else -1])
		p += 2
	error = ""
	return true


# the renderer asks where a page lives: [chapter bbcode, first wrapped line]
func text_page_location(page: int) -> Array:
	if page < 0 or page >= pages.size() or pages[page][0] != "text":
		return []
	var parts := str(pages[page][1]).split(":")
	var ch: Dictionary = _text_chapters[int(parts[0])]
	return [ch["bbcode"], int(ch["starts"][int(parts[1])])]


func receive_text_page(page: int, img: Image) -> void:
	if img == null:
		_tex[page] = null
	else:
		_tex[page] = ImageTexture.create_from_image(img)


static func _epub_opf(z: ZIPReader, files: PackedStringArray) -> String:
	var opf_path := ""
	if files.has("META-INF/container.xml"):
		var c := z.read_file("META-INF/container.xml").get_string_from_utf8()
		var m := RegEx.new()
		m.compile("full-path=\"([^\"]+)\"")
		var r := m.search(c)
		if r != null:
			opf_path = r.get_string(1)
	if opf_path == "" or not files.has(opf_path):
		for n in files:
			if n.get_extension().to_lower() == "opf":
				return n
		return ""
	return opf_path


static func _epub_items(opf: String) -> Dictionary:
	var items := {}
	var re_item := RegEx.new()
	re_item.compile("<item\\s[^>]*?>")
	var re_attr := RegEx.new()
	re_attr.compile("(id|href|media-type)=\"([^\"]*)\"")
	for m in re_item.search_all(opf):
		var a := {}
		for am in re_attr.search_all(m.get_string()):
			a[am.get_string(1)] = am.get_string(2)
		if a.has("id") and a.has("href"):
			items[a["id"]] = a
	return items


const ENTITIES := {"amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "mdash": "—", "ndash": "–",
	"hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "copy": "©", "eacute": "é", "egrave": "è",
	"agrave": "à", "ouml": "ö", "uuml": "ü", "auml": "ä", "ccedil": "ç", "ntilde": "ñ", "shy": "", "thinsp": " ", "emsp": " ", "ensp": " "}


static func _entities(t: String) -> String:
	var re := RegEx.new()
	re.compile("&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
	var out := ""
	var last := 0
	for m in re.search_all(t):
		out += t.substr(last, m.get_start() - last)
		var e := m.get_string(1)
		if e.begins_with("#x"):
			out += char(("0x" + e.substr(2)).hex_to_int())
		elif e.begins_with("#"):
			out += char(int(e.substr(1)))
		else:
			out += str(ENTITIES.get(e, "&" + e + ";"))
		last = m.get_end()
	return out + t.substr(last)


# A small HTML-to-BBCode pass for the tags novels use. Returns {"bbcode", "plain", "title"}.
static func html_to_bbcode(html: String) -> Dictionary:
	var body := html
	var bm := RegEx.new()
	bm.compile("(?is)<body[^>]*>(.*)</body>")
	var r := bm.search(html)
	if r != null:
		body = r.get_string(1)
	var strip := RegEx.new()
	strip.compile("(?is)<(script|style|head)[^>]*>.*?</\\1>|<!--.*?-->")
	body = strip.sub(body, "", true)
	var out := ""
	var plain := ""
	var title := ""
	var tag := RegEx.new()
	tag.compile("(?s)<(/?)([a-zA-Z0-9]+)([^>]*)>")
	var pos := 0
	var heading := 0
	var got_title := false
	for m in tag.search_all(body):
		var text := _entities(body.substr(pos, m.get_start() - pos))
		pos = m.get_end()
		text = text.replace("\r", " ").replace("\n", " ").replace("\t", " ")
		while text.contains("  "):
			text = text.replace("  ", " ")
		if text.strip_edges() != "" or (text != "" and out != "" and not out.ends_with("\n")):
			var safe := text.replace("[", "[lb]")
			out += safe
			plain += text
			if heading > 0 and not got_title:
				title += text
		var closing := m.get_string(1) == "/"
		var name := m.get_string(2).to_lower()
		var attrs := m.get_string(3)
		match name:
			"p", "div", "section", "article", "blockquote", "li", "tr", "dd", "dt", "figure", "figcaption", "pre":
				if closing:
					out = out.strip_edges(false, true) + "\n\n"
					plain += "\n"
				elif name == "li":
					out += "• "
			"br":
				out += "\n"
				if heading > 0 and not got_title:
					title += " "
			"h1", "h2", "h3", "h4", "h5", "h6":
				if closing:
					out = out.strip_edges(false, true) + "[/b][/font_size]\n\n"
					heading = 0
					if title.strip_edges() != "":
						got_title = true
				else:
					out = out.strip_edges(false, true) + ("\n\n" if out != "" else "") + "[font_size=%d][b]" % (48 if name <= "h2" else 40)
					heading = int(name.substr(1))
			"i", "em", "cite", "q":
				out += "[/i]" if closing else "[i]"
			"b", "strong":
				out += "[/b]" if closing else "[b]"
			"u":
				out += "[/u]" if closing else "[u]"
			"s", "del", "strike":
				out += "[/s]" if closing else "[s]"
			"sup", "sub":
				pass
			"hr":
				out = out.strip_edges(false, true) + "\n\n[center]* * *[/center]\n\n"
			"img", "image", "svg":
				pass
			_:
				pass
	var tail := _entities(body.substr(pos)).strip_edges()
	if tail != "":
		out += tail.replace("[", "[lb]")
		plain += tail
	while out.contains("\n\n\n"):
		out = out.replace("\n\n\n", "\n\n")
	title = title.strip_edges()
	if title.length() > 60:
		title = title.left(57) + "…"
	return {"bbcode": out.strip_edges(), "plain": plain, "title": title}


# ---------------------------------------------------------------- PDF: text, pulled out of the page content streams
# Godot has no PDF renderer. For a text PDF (a novel) the words are taken from the content streams and laid out
# as pages by page_renderer, so you read the book, not a picture of the original page. Works for PDFs that use
# plain (unencoded, non-subset-remapped) fonts, which is most ebook PDFs; scanned books have no text to find.

func _open_text_pdf(path: String) -> bool:
	if renderer == null:
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var size := f.get_length()
	if size > 200 * 1024 * 1024:
		return false
	var data := f.get_buffer(size)
	f.close()
	var hx := data.hex_encode()
	var H_STREAM := "73747265616d"          # "stream"
	var H_END := "656e6473747265616d"       # "endstream"
	var H_FLATE := "2f466c6174654465636f6465"   # "/FlateDecode"
	var texts: Array = []
	var at := 0
	var total := 0
	while true:
		var i := _hex_find(hx, H_STREAM, at)
		if i < 0:
			break
		var e := _hex_find(hx, H_END, i)
		if e < 0:
			break
		at = e + H_END.length()
		var dstart := _hex_rfind(hx, HEX_OBJ, i)
		if dstart < 0 or i - dstart > 6000:
			continue
		var dict := hx.substr(dstart, i - dstart)
		if dict.contains("2f496d616765") or dict.contains("2f466f6e7446696c65") or dict.contains("2f584d4c") or dict.contains("2f4f626a53746d") and false:
			continue        # /Image, /FontFile, /XML
		var b0 := i / 2 + 6
		if b0 < data.size() and data[b0] == 0x0D:
			b0 += 1
		if b0 < data.size() and data[b0] == 0x0A:
			b0 += 1
		var raw := data.slice(b0, e / 2)
		if raw.size() > 0 and (raw[raw.size() - 1] == 0x0A or raw[raw.size() - 1] == 0x0D):
			raw = raw.slice(0, raw.size() - 1)
		var body := raw
		if dict.contains(H_FLATE):
			body = raw.decompress_dynamic(32 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
			if body.is_empty():
				continue
		var t := _pdf_stream_text(body)
		if t.strip_edges().length() > 20:
			texts.append(t)
			total += t.length()
	if total < 1500:
		return false
	# chapters: a long PDF is split into even chunks so the contents page is useful; headings are not reliable here
	text_mode = true
	var all := "\n\n".join(texts)
	var chunk := 60000
	var parts: Array = []
	var p := 0
	while p < all.length():
		var cut := mini(all.length(), p + chunk)
		if cut < all.length():
			var nl := all.rfind("\n\n", cut)
			if nl > p + chunk / 2:
				cut = nl
		parts.append(all.substr(p, cut - p))
		p = cut
	pages = []
	chapters = []
	spreads = []
	for ci in parts.size():
		var bb: String = str(parts[ci]).replace("[", "[lb]").strip_edges()
		var starts: PackedInt32Array = renderer.paginate(bb)
		var first := pages.size()
		for k in starts.size():
			pages.append(["text", "%d:%d" % [ci, k]])
		_text_chapters.append({"bbcode": bb, "starts": starts})
		chapters.append({"title": "Part %d" % (ci + 1), "path": "", "first": first, "count": starts.size(), "section": "Parts"})
	var q := 0
	while q < pages.size():
		spreads.append([q, q + 1 if q + 1 < pages.size() else -1])
		q += 2
	error = ""
	return true


# The text-showing operators of a content stream: (..) Tj, [..] TJ, ' and ". Hex strings <..> too.
# Text runs are joined with spaces; T* / Td / TD / ET start new lines; big vertical moves become paragraphs.
static func _pdf_stream_text(body: PackedByteArray) -> String:
	var out := ""
	var i := 0
	var n := body.size()
	var depth := 0
	var in_text := false
	var last_op := ""
	var tok := ""
	var had_text := false
	while i < n:
		var c := body[i]
		if c == 0x28:                     # ( string
			var s := ""
			depth = 1
			i += 1
			while i < n and depth > 0:
				var ch := body[i]
				if ch == 0x5C and i + 1 < n:       # backslash escape
					i += 1
					var e := body[i]
					match e:
						0x6E: s += "\n"
						0x72: pass
						0x74: s += "\t"
						0x28: s += "("
						0x29: s += ")"
						0x5C: s += "\\"
						_:
							if e >= 0x30 and e <= 0x37:         # octal
								var o := 0
								var k := 0
								while k < 3 and i < n and body[i] >= 0x30 and body[i] <= 0x37:
									o = o * 8 + (body[i] - 0x30)
									i += 1
									k += 1
								i -= 1
								s += char(_pdf_std_char(o))
							else:
								s += char(e)
				elif ch == 0x28:
					depth += 1
					s += "("
				elif ch == 0x29:
					depth -= 1
					if depth > 0:
						s += ")"
				else:
					s += char(_pdf_std_char(ch))
				i += 1
			tok = s
			continue
		elif c == 0x3C and i + 1 < n and body[i + 1] != 0x3C:       # <hex string>
			var j := i + 1
			var hexs := ""
			while j < n and body[j] != 0x3E:
				hexs += char(body[j])
				j += 1
			i = j + 1
			hexs = hexs.replace(" ", "").replace("\n", "").replace("\r", "")
			var s := ""
			var k := 0
			while k + 1 < hexs.length():
				var v := ("0x" + hexs.substr(k, 2)).hex_to_int()
				if v >= 32 and v < 127:
					s += char(v)
				elif v > 160 and v < 256:
					s += char(v)
				k += 2
			tok = s
			continue
		elif c == 0x5B:                   # [ array: strings inside, with kerning numbers between
			var j := i + 1
			var parts := ""
			var d := 1
			var buf := PackedByteArray()
			while j < n and d > 0:
				if body[j] == 0x5B: d += 1
				elif body[j] == 0x5D: d -= 1
				if d > 0: buf.append(body[j])
				j += 1
			# recursive: strings inside the array; a large negative kerning number is a space
			var inner := _pdf_array_strings(buf)
			tok = inner
			i = j
			continue
		# operators and numbers
		var j := i
		while j < n and body[j] > 0x20 and body[j] != 0x28 and body[j] != 0x5B and body[j] != 0x3C:
			j += 1
		if j == i:
			i += 1
			continue
		var word := body.slice(i, j).get_string_from_ascii()
		i = j
		match word:
			"BT":
				in_text = true
			"ET":
				in_text = false
				if had_text and not out.ends_with("\n"):
					out += "\n"
			"Tj", "'", "\"":
				if in_text and tok != "":
					if word != "Tj" and had_text:
						out += "\n"
					out += tok
					had_text = true
				tok = ""
			"TJ":
				if in_text and tok != "":
					out += tok
					had_text = true
				tok = ""
			"T*", "Td", "TD", "Tm":
				if had_text and not out.ends_with("\n") and not out.ends_with(" "):
					out += " " if word != "T*" else "\n"
			_:
				pass
		last_op = word
	# tidy: hyphenation at line ends, runs of spaces, paragraph breaks from blank lines;
	# single line breaks inside a sentence are just the PDF's own wrapping and are joined back into flowing text
	out = out.replace("-\n", "").replace(" \n", "\n")
	var re := RegEx.new()
	re.compile("([^.!?:\"”’'\\n])\\n(?!\\n)")
	out = re.sub(out, "$1 ", true)
	while out.contains("  "):
		out = out.replace("  ", " ")
	while out.contains("\n\n\n"):
		out = out.replace("\n\n\n", "\n\n")
	return out


static func _pdf_array_strings(buf: PackedByteArray) -> String:
	var s := ""
	var i := 0
	var n := buf.size()
	while i < n:
		var c := buf[i]
		if c == 0x28:
			var d := 1
			i += 1
			while i < n and d > 0:
				var ch := buf[i]
				if ch == 0x5C and i + 1 < n:
					i += 1
					var e := buf[i]
					if e == 0x6E: s += "\n"
					elif e == 0x28 or e == 0x29 or e == 0x5C: s += char(e)
					elif e >= 0x30 and e <= 0x37:
						var o := 0
						var k := 0
						while k < 3 and i < n and buf[i] >= 0x30 and buf[i] <= 0x37:
							o = o * 8 + (buf[i] - 0x30)
							i += 1
							k += 1
						i -= 1
						s += char(_pdf_std_char(o))
				elif ch == 0x28:
					d += 1
					s += "("
				elif ch == 0x29:
					d -= 1
					if d > 0: s += ")"
				else:
					s += char(_pdf_std_char(ch))
				i += 1
			continue
		elif c == 0x3C:
			var j := i + 1
			var hexs := ""
			while j < n and buf[j] != 0x3E:
				hexs += char(buf[j]); j += 1
			i = j + 1
			var k := 0
			while k + 1 < hexs.length():
				var v := ("0x" + hexs.substr(k, 2)).hex_to_int()
				if v >= 32 and v < 256: s += char(v)
				k += 2
			continue
		elif (c >= 0x30 and c <= 0x39) or c == 0x2D or c == 0x2E:
			var j := i
			while j < n and ((buf[j] >= 0x30 and buf[j] <= 0x39) or buf[j] == 0x2D or buf[j] == 0x2E):
				j += 1
			var v := buf.slice(i, j).get_string_from_ascii().to_float()
			if v < -180.0:
				s += " "          # a big backwards kern is a word gap
			i = j
			continue
		i += 1
	return s


# WinAnsi / Standard encodings mostly agree with Latin-1 in the printable range; a few common swaps
static func _pdf_std_char(c: int) -> int:
	match c:
		0x91, 0xD4: return 0x2018
		0x92, 0xD5: return 0x2019
		0x93, 0xD2: return 0x201C
		0x94, 0xD3: return 0x201D
		0x96, 0xD0: return 0x2013
		0x97, 0xD1: return 0x2014
		0x85, 0xC9: return 0x2026
		0xAD: return 0x2D
	if c < 32 and c != 10 and c != 9:
		return 32
	return c
