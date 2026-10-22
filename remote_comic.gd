extends "res://comic_book.gd"
## A comic somebody else in the room opened: same shape as ComicBook, but the pages arrive over the
## network as JPEGs from whoever has the file. `ask` is called with a page number to request one.

var ask: Callable
var _asked := {}          # page -> time asked (ms)


func open_remote(m: Dictionary, asker: Callable) -> void:
	ask = asker
	title = str(m.get("title", "Comic")).left(60)
	path = "remote:" + title
	chapters = []
	var cl = m.get("chapters", [])
	for c in (cl if cl is Array else []).slice(0, 500):
		if c is Dictionary:
			chapters.append({"title": str(c.get("title", "")).left(80), "path": "", "first": clampi(int(c.get("first", 0)), 0, 5000), "count": clampi(int(c.get("count", 0)), 0, 5000), "section": "Extras" if str(c.get("section", "")) == "Extras" else "Issues"})
	var n := clampi(int(m.get("pages", 0)), 0, 5000)
	pages = []
	for i in n:
		pages.append(["", ""])
	spreads = []
	var sl = m.get("spreads", [])
	for sp in (sl if sl is Array else []).slice(0, 5001):
		if sp is Array and sp.size() == 2 and int(sp[0]) < n and int(sp[1]) < n:
			spreads.append([int(sp[0]), int(sp[1])])
	if spreads.is_empty() and n > 0:
		spreads.append([-1, 0])
		var p := 1
		while p < n:
			spreads.append([p, p + 1 if p + 1 < n else -1])
			p += 2


func get_page(i: int) -> ImageTexture:
	if i < 0 or i >= pages.size():
		return null
	if _tex.has(i):
		return _tex[i]
	_request(i)
	return null


func prefetch(center: int, span := 2) -> void:
	for i in range(center - 1, center + span + 1):
		if i >= 0 and i < pages.size() and not _tex.has(i):
			_request(i)
	for k in _tex.keys():
		if absi(k - center) > span + 2:
			_tex.erase(k)


func _request(i: int) -> void:
	var now := Time.get_ticks_msec()
	if _asked.has(i) and now - int(_asked[i]) < 8000:
		return                       # already on its way (asked again after 8 s in case it got lost)
	_asked[i] = now
	if ask.is_valid():
		ask.call(i)


# a page arrived
func receive(i: int, jpeg: PackedByteArray) -> void:
	_asked.erase(i)
	if i < 0 or i >= pages.size():
		return
	if jpeg.is_empty():
		_tex[i] = null
		return
	var img := preload("res://safe_image.gd").jpeg(jpeg, 2048)
	if img == null:
		_tex[i] = null
		return
	img.generate_mipmaps()
	_tex[i] = ImageTexture.create_from_image(img)


func close() -> void:
	_tex.clear()
