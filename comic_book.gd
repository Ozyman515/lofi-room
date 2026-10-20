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
	for f in files:
		var entries := _list_pages(f)
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


func _list_pages(file_path: String) -> Array:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		error = "Can't open this file."
		return []
	var head := f.get_buffer(4)
	f.close()
	if head.size() >= 4 and head[0] == 0x25 and head[1] == 0x50 and head[2] == 0x44 and head[3] == 0x46:     # %PDF
		return _list_pdf_pages(file_path)
	if file_path.get_extension().to_lower() == "epub":
		var ep := _list_epub_pages(file_path)
		if not ep.is_empty():
			return ep
		# not a picture book: fall through and treat it as a zip of images (fixed-layout comics often work that way)
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
		if img.load_jpg_from_buffer(data) != OK:
			return null
	else:
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
