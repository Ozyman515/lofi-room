extends Node
## Books in a shared room. Whoever takes a comic off their shelf owns it (they have the file); everyone
## else sees the same book and, when they pick it up, gets its pages streamed from the owner as JPEGs.
## All messages go through the host, who keeps the list and forwards between guests.

const Net := preload("res://net_session.gd")
const Book := preload("res://book.gd")
const RemoteComic := preload("res://remote_comic.gd")

var net: Node
var main: Node3D
var _counter := 0
var _known := {}           # net_id -> Book (mine and others')


func setup(session: Node, m: Node3D) -> void:
	net = session
	main = m
	net.packet.connect(_on_packet)
	net.state_changed.connect(_on_state)
	net.roster_changed.connect(_on_roster)


func _process(_delta: float) -> void:
	# pages the owner's worker threads finished encoding go out now
	for bk in main.books:
		if bk.net_id == "" or bk.owner_id != net.my_id or bk.comic == null or not bk.comic.has_method("take_jpegs"):
			continue
		var ready: Dictionary = bk.comic.take_jpegs()
		for page in ready:
			var waiting: Array = bk.get_meta("waiting_%d" % page, [])
			bk.remove_meta("waiting_%d" % page)
			for to in waiting:
				_send_page(int(to), bk.net_id, page, ready[page])


# ---- my own books

func _my_book_opened(bk: Node3D) -> void:
	if not net.is_online():
		return
	_counter += 1
	bk.net_id = "%d:%d" % [net.my_id, _counter]
	bk.owner_id = net.my_id
	bk.holder_id = net.my_id
	_known[bk.net_id] = bk
	_say({"k": "book_open", "id": bk.net_id, "owner": net.my_id, "holder": net.my_id, "meta": bk.comic.meta()})


func _my_book_taken(bk: Node3D) -> void:
	if bk.net_id == "":
		_my_book_opened(bk)
		return
	bk.holder_id = net.my_id
	_say({"k": "book_take", "id": bk.net_id, "holder": net.my_id, "spread": bk.spread})


func _my_book_turned(bk: Node3D) -> void:
	if bk.net_id != "" and bk.held_by_me:
		_say({"k": "book_spread", "id": bk.net_id, "spread": bk.spread})


func _my_book_put(bk: Node3D) -> void:
	if bk.net_id == "":
		return
	bk.holder_id = 0
	_say({"k": "book_put", "id": bk.net_id, "xf": bk.global_transform})


# to the host (who passes it on), or from the host to everybody
func _say(d: Dictionary) -> void:
	if not net.is_online():
		return
	if net.is_host():
		_fanout(d, 0)
	else:
		net.send_var(1, Net.K_EVENT, d)


func _fanout(d: Dictionary, except_id: int) -> void:
	for id in net.peer_ids():
		if id != except_id:
			net.send_var(id, Net.K_EVENT, d)


# ---- messages

func _on_packet(from: int, kind: int, payload: PackedByteArray) -> void:
	if kind == Net.K_BOOK:
		_on_page_packet(from, payload)
		return
	if kind != Net.K_EVENT:
		return
	var d = Net.read_var(payload)
	if not (d is Dictionary) or not str(d.get("k", "")).begins_with("book"):
		return
	if OS.get_environment("LOFI_NET_DEBUG") == "1":
		print("[books] from ", from, ": ", d.get("k"), " ", d.get("id", ""))
	if net.is_host():
		# guests only talk to the host; the host applies and passes on
		match str(d["k"]):
			"book_open", "book_take", "book_put", "book_spread":
				_apply(d, from)
				_fanout(d, from)
			"book_page_req":
				_handle_page_req(d, from)
			"book_list_req":
				_send_list(from)
	else:
		if from != 1:
			return
		match str(d["k"]):
			"book_open", "book_take", "book_put", "book_spread":
				_apply(d, from)
			"book_list":
				for e in d.get("books", []):
					if e is Dictionary:
						_apply(e, from)
			"book_page_req":
				_handle_page_req(d, from)


func _apply(d: Dictionary, from: int) -> void:
	var id := str(d.get("id", ""))
	if id == "":
		return
	match str(d["k"]):
		"book_open", "book_list_entry":
			if _known.has(id):
				return
			var owner := from if from != 1 or net.is_host() else int(d.get("owner", from))     # a guest can only announce its own books; the host relays on behalf of others
			if owner == net.my_id or owner < 1 or owner > 4:
				return
			var rc := RemoteComic.new()
			rc.open_remote(d.get("meta", {}), func(page: int) -> void: _ask_page(id, owner, page))
			if rc.page_count() == 0:
				return
			var bk: Node3D = Book.new()
			bk.open_remote(rc)
			bk.net_id = id
			bk.owner_id = owner
			bk.holder_id = int(d.get("holder", owner))
			bk.lying = bk.holder_id == 0
			bk.held_by_me = false
			if d.has("xf") and d["xf"] is Transform3D:
				bk.transform = d["xf"]
			else:
				bk.position = Vector3(0, -5, 0)       # placed by the holder's avatar next frame
			main.add_child(bk)
			main._add_book(bk)
			_known[id] = bk
		"book_take":
			var bk: Node3D = _known.get(id)
			if bk == null:
				return
			var holder := int(d.get("holder", 0))
			if holder != net.my_id:
				if main.held_book == bk:
					main.held_book = null       # somebody grabbed it out of my hands (shouldn't happen, but stay consistent)
				bk.held_by_me = false
			bk.holder_id = holder
			bk.lying = false
			if holder != net.my_id and d.has("spread"):
				bk.show_spread(int(d["spread"]))
			bk._update_toc()
		"book_spread":
			var bk: Node3D = _known.get(id)
			if bk != null and not bk.held_by_me:
				bk.show_spread(int(d.get("spread", 0)))
		"book_put":
			var bk: Node3D = _known.get(id)
			if bk == null:
				return
			bk.holder_id = 0
			bk.lying = true
			bk.held_by_me = false
			if main.held_book == bk:
				main.held_book = null
			if d.has("xf") and d["xf"] is Transform3D:
				bk.global_transform = d["xf"]
			bk._update_toc()


func _send_list(to: int) -> void:
	var out: Array = []
	for bk in main.books:
		if bk.net_id == "" or bk.comic == null:
			continue
		var meta: Dictionary = bk.comic.meta() if bk.comic.has_method("meta") else {}
		if bk.owner_id != net.my_id:
			meta = {"title": bk.comic.title, "pages": bk.comic.page_count(), "spreads": bk.comic.spreads, "chapters": bk.comic.chapters}
		var e := {"k": "book_open", "id": bk.net_id, "owner": bk.owner_id, "holder": bk.holder_id, "meta": meta}
		if bk.lying:
			e["xf"] = bk.global_transform
		out.append(e)
	net.send_var(to, Net.K_EVENT, {"k": "book_list", "books": out})


# ---- pages

func _ask_page(id: String, owner: int, page: int) -> void:
	var d := {"k": "book_page_req", "id": id, "page": page, "from": net.my_id}
	if net.is_host():
		net.send_var(owner, Net.K_EVENT, d)
	else:
		net.send_var(1, Net.K_EVENT, d)


func _handle_page_req(d: Dictionary, _from: int) -> void:
	var id := str(d.get("id", ""))
	var page := int(d.get("page", -1))
	var asker := int(d.get("from", 0))
	var bk: Node3D = _known.get(id)
	if bk == null:
		return
	if bk.owner_id == net.my_id:
		if bk.comic == null or not bk.comic.has_method("request_jpeg"):
			return
		var key := "waiting_%d" % page
		var waiting: Array = bk.get_meta(key, [])
		waiting.append(asker)
		bk.set_meta(key, waiting)
		bk.comic.request_jpeg(page)
	elif net.is_host():
		net.send_var(bk.owner_id, Net.K_EVENT, d)      # a guest asked for another guest's book


func _send_page(to: int, id: String, page: int, jpeg: PackedByteArray) -> void:
	var head := var_to_bytes({"id": id, "page": page, "to": to})
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, head.size())
	out.append_array(head)
	out.append_array(jpeg)
	if net.is_host() or to == 1:
		net.send_to(to, Net.K_BOOK, out, true)
	else:
		net.send_to(1, Net.K_BOOK, out, true)          # via the host


func _on_page_packet(from: int, payload: PackedByteArray) -> void:
	if payload.size() < 4 or payload.size() > 4 * 1024 * 1024:
		return
	var hl := payload.decode_u32(0)
	if hl > 512 or payload.size() < 4 + hl:
		return
	var head = bytes_to_var(payload.slice(4, 4 + hl))
	if not (head is Dictionary):
		return
	var to := int(head.get("to", 0))
	if to != net.my_id:
		if net.is_host() and net.roster.has(to):
			net.send_to(to, Net.K_BOOK, payload, true)
		return
	var bk: Node3D = _known.get(str(head.get("id", "")))
	if bk == null or bk.comic == null or not bk.comic.has_method("receive"):
		return
	bk.comic.receive(int(head.get("page", -1)), payload.slice(4 + hl))


# ---- room changes

func _on_state() -> void:
	if net.state == net.State.JOINED:
		net.send_var(1, Net.K_EVENT, {"k": "book_list_req"})
	elif net.state == net.State.HOSTING:
		for bk in main.books:
			if bk.net_id == "":
				_my_book_opened(bk)
	elif not net.is_online():
		# alone again: other people's books vanish, mine stay
		for id in _known.keys():
			var bk: Node3D = _known[id]
			if bk.owner_id != net.my_id:
				_drop(bk)
			else:
				bk.net_id = ""
				bk.owner_id = 0
				bk.holder_id = 0
		_known.clear()


func _on_roster() -> void:
	if not net.is_online():
		return
	for id in _known.keys():
		var bk: Node3D = _known[id]
		if bk.owner_id != net.my_id and not net.roster.has(bk.owner_id):
			_drop(bk)                                  # the owner left: the book goes with them
		elif bk.holder_id != 0 and not net.roster.has(bk.holder_id):
			bk.holder_id = 0                           # the holder left: the book drops where they stood
			bk.lying = true
			bk.held_by_me = false
			var t := bk.global_transform
			t.origin.y = 0.012
			bk.global_transform = Transform3D(Basis(Vector3.UP, t.basis.get_euler().y) * Basis(Vector3.RIGHT, -PI / 2.0), t.origin)
			bk._update_toc()


func _drop(bk: Node3D) -> void:
	_known.erase(bk.net_id)
	main._remove_book(bk)
