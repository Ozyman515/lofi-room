extends Node
## Multiplayer session: talks to the code server (WebSocket), then links players with WebRTC.
## Star layout: the host is peer 1, every guest connects only to the host.
## Game packets are [kind byte] + payload; use send_to()/broadcast() and the `packet` signal.

const Cfg := preload("res://net_config.gd")

enum State { OFFLINE, CONNECTING, HOSTING, JOINING, JOINED }

# packet kinds
const K_ROSTER := 1      # host -> all: {id: {name, color}}
const K_POSE := 2        # unreliable: head + hands
const K_EVENT := 3       # reliable game events (var)
const K_INPUT := 4       # guest -> host: pad / stick state
const K_VIDEO := 5       # host -> guest: emulator frames
const K_AUDIO := 6       # host -> guest: emulator sound
const K_BOOK := 7        # comic pages (JPEG) from a book's owner to whoever is reading it
const K_SOUND := 8       # host -> guests: the room's music and TV, ADPCM
const K_VOICE := 9       # voices: [speaker id] + ADPCM, relayed by the host

signal state_changed
signal roster_changed
signal packet(from_id: int, kind: int, payload: PackedByteArray)
signal failed(message: String)
signal kicked
signal knock(id: int, player_name: String)   # hosting: someone is asking to come in

var state := State.OFFLINE
var code := ""
var host_token := ""                    # proves to the server that we are the host when taking a dropped room back
var my_id := 0
var my_name := ""
var status := ""                         # short text for the phone screen
var roster := {}                         # id -> {name, color}
var host_away := false
var knocks := {}                         # hosting: id -> name of players waiting at the door
var _waiting := false                    # joining: waiting for the host to let us in

var _ws: WebSocketPeer
var _mp: WebRTCMultiplayerPeer
var _conns := {}                         # id -> WebRTCPeerConnection
var _relayed := {}                       # id -> true: no direct link, packets go through the room server instead
const DIRECT_WAIT_MS := 7000             # how long a direct link gets before falling back to the server
const RELAY_BACKLOG := 512 * 1024        # skip unreliable packets (video, poses) while this much is still unsent
var _pending_sig := {}                   # id -> queued signals that arrived before the connection existed
var _connecting_since := {}              # id -> ms
var _ping_t := 0.0
var _want := ""                          # "host" or "join" request to send once the socket opens
var _want_code := ""
var _ws_open := false
var _closing := false

const COLORS := [Color(1.0, 0.45, 0.75), Color(0.45, 0.85, 1.0), Color(1.0, 0.85, 0.4), Color(0.6, 1.0, 0.6)]


func is_host() -> bool:
	return state == State.HOSTING


func is_online() -> bool:
	return state == State.HOSTING or state == State.JOINED


func peer_ids() -> Array:
	var out: Array = []
	for id in roster:
		if id != my_id:
			out.append(id)
	return out


func player_count() -> int:
	return roster.size()


# ---- public: start / stop ----

func host_room(reclaim_code := "") -> void:
	if state != State.OFFLINE:
		return
	_start("host", reclaim_code)


func join_room(c: String) -> void:
	if state != State.OFFLINE:
		return
	_start("join", c.strip_edges().to_upper())


func leave() -> void:
	if _ws != null and _ws_open:
		_send_ws({"t": "leave"})
	_teardown()


func kick(id: int) -> void:
	if is_host() and id != 1:
		_send_ws({"t": "kick", "id": id})
		knocks.erase(id)
		_drop_peer(id)
		roster_changed.emit()


# hosting: let a waiting player in, or turn them away
func admit(id: int) -> void:
	if is_host() and knocks.has(id):
		knocks.erase(id)
		_send_ws({"t": "admit", "id": id})
		roster_changed.emit()


func turn_away(id: int) -> void:
	kick(id)


# ---- public: packets ----

func send_to(id: int, kind: int, payload: PackedByteArray, reliable := true) -> void:
	if _mp == null:
		return
	if id == 0:
		for pid in peer_ids():
			send_to(pid, kind, payload, reliable)
		return
	if _relayed.has(id):
		if not reliable and _ws.get_current_outbound_buffered_amount() > RELAY_BACKLOG:
			return                      # a slow link drops a frame rather than falling behind
		var r := PackedByteArray([id, kind])
		r.append_array(payload)
		_ws.send(r, WebSocketPeer.WRITE_MODE_BINARY)
		return
	if _connecting_since.has(id) or not _conns.has(id):
		return                          # not linked up yet (or gone)
	_mp.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	_mp.set_target_peer(id)
	var b := PackedByteArray([kind])
	b.append_array(payload)
	_mp.put_packet(b)


# bytes still waiting to go out to a player (their data channels, or the server link when relayed). Pictures
# check this and wait their turn when the line is busy, so sound never gets crowded out.
func backlog(id: int) -> int:
	if _relayed.has(id):
		return _ws.get_current_outbound_buffered_amount() if _ws != null else 0
	if _mp == null or not _mp.has_peer(id):
		return 0
	var total := 0
	var info: Dictionary = _mp.get_peer(id)
	for ch in info.get("channels", []):
		if ch is WebRTCDataChannel:
			total += (ch as WebRTCDataChannel).get_buffered_amount()
	return total


func broadcast(kind: int, payload: PackedByteArray, reliable := true) -> void:
	if _mp == null:
		return
	send_to(0, kind, payload, reliable)


func send_var(id: int, kind: int, v: Variant, reliable := true) -> void:
	send_to(id, kind, var_to_bytes(v), reliable)


static func read_var(payload: PackedByteArray) -> Variant:
	return bytes_to_var(payload)      # never bytes_to_var_with_objects: packets come from other players


# ---- internals ----

func _start(what: String, c: String) -> void:
	_want = what
	_want_code = c
	my_name = Cfg.player_name()
	_closing = false
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 4 * 1024 * 1024      # relayed game packets are bigger than handshake messages
	_ws.outbound_buffer_size = 4 * 1024 * 1024
	_ws.max_queued_packets = 8192
	var err := _ws.connect_to_url(Cfg.server_url())
	if err != OK:
		_fail("Can't reach the room server.")
		return
	_set_state(State.CONNECTING, "Connecting...")


func _set_state(s: State, text := "") -> void:
	state = s
	status = text
	state_changed.emit()


func _fail(msg: String) -> void:
	_teardown()
	status = msg
	failed.emit(msg)
	state_changed.emit()


func _teardown() -> void:
	_closing = true
	for id in _conns:
		_conns[id].close()
	_conns.clear()
	_relayed.clear()
	_pending_sig.clear()
	_connecting_since.clear()
	if _mp != null:
		_mp.close()
		_mp = null
	if _ws != null:
		_ws.close()
		_ws = null
	_ws_open = false
	code = ""
	my_id = 0
	roster = {}
	knocks = {}
	_waiting = false
	host_away = false
	_set_state(State.OFFLINE, "")
	roster_changed.emit()


func _send_ws(obj: Dictionary) -> void:
	if _ws != null and _ws_open:
		_ws.send_text(JSON.stringify(obj))


func _process(delta: float) -> void:
	if _ws != null:
		_ws.poll()
		var st := _ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN or (st == WebSocketPeer.STATE_CLOSING and _ws_open):
			if not _ws_open:
				_ws_open = true
				_on_ws_open()
			while _ws.get_available_packet_count() > 0:
				var raw := _ws.get_packet()
				if not _ws.was_string_packet():
					_on_relayed(raw)
					continue
				var m = JSON.parse_string(raw.get_string_from_utf8())
				if m is Dictionary:
					_on_server_msg(m)
				if _ws == null:
					return
			_ping_t += delta
			if _ping_t > 20.0:
				_ping_t = 0.0
				_send_ws({"t": "ping"})
		elif st == WebSocketPeer.STATE_CLOSED and not _closing:
			# the server's last words (e.g. "kicked") can arrive together with the close: read them first
			while _ws != null and _ws.get_available_packet_count() > 0:
				var last := _ws.get_packet()
				if _ws.was_string_packet():
					var lm = JSON.parse_string(last.get_string_from_utf8())
					if lm is Dictionary:
						_on_server_msg(lm)
			if _ws == null or _closing:
				return
			var was_online := is_online()
			if _waiting:
				_fail("The host didn't let you in this time.")
			elif state == State.CONNECTING or state == State.JOINING:
				_fail("Can't reach the room server.")
			else:
				_fail("Lost connection to the room server." if not was_online else "The room closed.")
			return
	if _mp != null:
		_mp.poll()
		_check_timeouts()
		while _mp != null and _mp.get_available_packet_count() > 0:
			var from := _mp.get_packet_peer()
			var data := _mp.get_packet()
			if data.size() > 0:
				_on_packet(from, int(data[0]), data.slice(1))


func _on_ws_open() -> void:
	if _want == "host":
		_send_ws({"t": "host", "ver": Cfg.build_version(), "name": my_name, "code": _want_code, "token": host_token if _want_code != "" else "",
			"approve": Cfg.ask_to_join()})
	else:
		_set_state(State.JOINING, "Joining...")
		_send_ws({"t": "join", "code": _want_code, "ver": Cfg.build_version(), "name": my_name})


func _on_server_msg(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"hosted":
			_relay = m.get("ice", []) if m.get("ice", []) is Array else []
			code = str(m.get("code", ""))
			host_token = str(m.get("token", ""))
			my_id = 1
			_mp = WebRTCMultiplayerPeer.new()
			_mp.create_server()
			_mp.peer_disconnected.connect(_on_peer_gone)
			roster = {1: {"name": my_name, "color": COLORS[0]}}
			_set_state(State.HOSTING, "Room open")
			roster_changed.emit()
		"waiting":
			_waiting = true
			code = str(m.get("code", _want_code))
			_set_state(State.JOINING, "Knocking...\nWaiting for %s to let you in." % str(m.get("host_name", "the host")).left(20))
		"knock":
			if is_host():
				var kid := int(m.get("id", 0))
				var kname := str(m.get("name", "Guest")).left(20)
				knocks[kid] = kname
				knock.emit(kid, kname)
				roster_changed.emit()
		"knock_gone":
			if knocks.erase(int(m.get("id", 0))):
				roster_changed.emit()
		"joined":
			_waiting = false
			_relay = m.get("ice", []) if m.get("ice", []) is Array else []
			code = str(m.get("code", _want_code))
			my_id = int(m.get("id", 0))
			_mp = WebRTCMultiplayerPeer.new()
			_mp.create_client(my_id)
			_mp.peer_disconnected.connect(_on_peer_gone)
			_make_conn(1, false)
			roster = {1: {"name": str(m.get("host_name", "Host")), "color": COLORS[0]}, my_id: {"name": my_name, "color": COLORS[(my_id - 1) % 4]}}
			_set_state(State.JOINING, "Connecting to %s..." % roster[1]["name"])
			roster_changed.emit()
		"peer_join":
			if is_host():
				var id := int(m.get("id", 0))
				knocks.erase(id)
				roster[id] = {"name": str(m.get("name", "Guest")).left(20), "color": COLORS[(id - 1) % 4]}
				_make_conn(id, true)
		"peer_leave":
			_drop_peer(int(m.get("id", 0)))
		"sig":
			_on_sig(int(m.get("from", 0)), m.get("data", {}))
		"host_away":
			host_away = true
			status = "Host is away..."
			state_changed.emit()
		"host_back":
			host_away = false
			status = ""
			state_changed.emit()
		"kicked":
			var was_waiting := _waiting
			_teardown()
			status = "The host didn't let you in this time." if was_waiting else "You were removed from the room."
			kicked.emit()
			state_changed.emit()
		"closed":
			_fail("The host closed the room.")
		"error":
			_fail(_error_text(str(m.get("code", "")), m))
		_:
			pass


func _error_text(c: String, m: Dictionary) -> String:
	match c:
		"no_room": return "No room with that code."
		"full": return "That room is full."
		"version": return "The host is on a different version of the room."
		"host_away": return "The host stepped away. Try again in a moment."
		"rate": return "Too many tries. Wait a minute."
		"busy": return "Server is busy. Try again."
	return "Something went wrong."


# ---- WebRTC links ----

func _make_conn(id: int, offerer: bool) -> void:
	if _conns.has(id):
		return
	var c := WebRTCPeerConnection.new()
	var ice: Array = Cfg.ice_servers()
	for r in _relay:
		if r is Dictionary and r.has("urls"):
			ice.append(r)
	c.initialize({"iceServers": ice})
	_log("link %d: %d ice servers (relay %s)" % [id, ice.size(), "yes" if _relay.size() > 0 else "no"])
	c.session_description_created.connect(func(type: String, sdp: String) -> void:
		c.set_local_description(type, sdp)
		_send_ws({"t": "sig", "to": id, "data": {"k": "sdp", "type": type, "sdp": sdp}}))
	c.ice_candidate_created.connect(func(media: String, index: int, cname: String) -> void:
		_log("link %d: my candidate %s" % [id, _cand_kind(cname)])
		if OS.get_environment("LOFI_NO_DIRECT") == "1":
			return                      # testing: pretend the networks block a direct link
		_send_ws({"t": "sig", "to": id, "data": {"k": "ice", "m": media, "i": index, "n": cname}}))
	_conns[id] = c
	_connecting_since[id] = Time.get_ticks_msec()
	_mp.add_peer(c, id)
	if offerer:
		c.create_offer()
	if _pending_sig.has(id):
		for d in _pending_sig[id]:
			_apply_sig(id, d)
		_pending_sig.erase(id)


func _on_sig(from: int, d: Variant) -> void:
	if not (d is Dictionary):
		return
	if not _conns.has(from):
		if not _pending_sig.has(from):
			_pending_sig[from] = []
		if _pending_sig[from].size() < 64:
			_pending_sig[from].append(d)
		return
	_apply_sig(from, d)


func _apply_sig(from: int, d: Dictionary) -> void:
	var c: WebRTCPeerConnection = _conns.get(from)
	if c == null:
		return
	if d.get("k", "") == "sdp":
		c.set_remote_description(str(d.get("type", "")), str(d.get("sdp", "")))
	elif d.get("k", "") == "ice":
		_log("link %d: their candidate %s" % [from, _cand_kind(str(d.get("n", "")))])
		c.add_ice_candidate(str(d.get("m", "")), int(d.get("i", 0)), str(d.get("n", "")))


var _relay: Array = []


# connection notes for user://net.log, so a failed link can be diagnosed (host / srflx = direct, relay = via TURN)
func _cand_kind(c: String) -> String:
	var i := c.find(" typ ")
	return c.substr(i + 5).get_slice(" ", 0) if i >= 0 else "?"


func _log(line: String) -> void:
	var path := "user://net.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	if f.get_length() > 200000:
		f.close()
		f = FileAccess.open(path, FileAccess.WRITE)
	f.seek_end()
	f.store_line("%s  %s" % [Time.get_datetime_string_from_system(), line])


func _check_timeouts() -> void:
	var now := Time.get_ticks_msec()
	for id in _connecting_since.keys():
		if not _conns.has(id):
			_connecting_since.erase(id)
			continue
		if _mp.has_peer(id) and _mp.get_peer(id).get("connected", false):
			_connecting_since.erase(id)
			_log("link %d: direct" % id)
			_on_peer_up(id)
		elif now - int(_connecting_since[id]) > DIRECT_WAIT_MS:
			_log("link %d: no direct link after %d s (state %d), going through the server" % [id, DIRECT_WAIT_MS / 1000, _conns[id].get_connection_state()])
			_use_relay(id)
			_send_relay_hello(id)


# the direct link didn't come up: talk to this player through the room server from now on
func _use_relay(id: int) -> void:
	if _relayed.has(id):
		return
	_relayed[id] = true
	_connecting_since.erase(id)
	if _conns.has(id):
		_conns[id].close()
	if _mp != null and _mp.has_peer(id):
		_mp.remove_peer(id)
	_on_peer_up(id)


func _send_relay_hello(id: int) -> void:
	_ws.send(PackedByteArray([id, 0]), WebSocketPeer.WRITE_MODE_BINARY)


# [from id] [kind] payload, from the server (it fills in the real sender)
func _on_relayed(raw: PackedByteArray) -> void:
	if raw.size() < 2:
		return
	var from := int(raw[0])
	if is_host():
		if not roster.has(from) or from == 1:
			return
	elif from != 1 or state == State.CONNECTING:
		return
	if not _relayed.has(from):
		_log("link %d: the other side went through the server, following" % from)
		_use_relay(from)
		if int(raw[1]) == 0:
			_send_relay_hello(from)
	if int(raw[1]) != 0:
		_on_packet(from, int(raw[1]), raw.slice(2))


func _on_peer_up(id: int) -> void:
	if is_host():
		_send_roster()
	elif id == 1:
		_set_state(State.JOINED, "Connected")


func _drop_peer(id: int) -> void:
	_relayed.erase(id)
	if _conns.has(id):
		_conns[id].close()
		_conns.erase(id)
	if _mp != null and _mp.has_peer(id):
		_mp.remove_peer(id)
	_connecting_since.erase(id)
	if is_host():
		if roster.erase(id):
			_send_roster()
			roster_changed.emit()
	elif id == 1:
		_fail("Lost connection to the host.")


func _on_peer_gone(id: int) -> void:
	if _relayed.has(id):
		return                          # we closed the direct attempt ourselves
	_drop_peer(id)


func _send_roster() -> void:
	if _mp == null:
		return
	for id in peer_ids():
		if _conns.has(id) and not _connecting_since.has(id):
			send_var(id, K_ROSTER, roster)
	roster_changed.emit()


func _on_packet(from: int, kind: int, payload: PackedByteArray) -> void:
	if kind == K_ROSTER:
		if from != 1:
			return
		var r = read_var(payload)
		if r is Dictionary:
			var clean := {}
			for k in r:
				if k is int and r[k] is Dictionary:
					clean[k] = {"name": str(r[k].get("name", "?")).left(20), "color": r[k].get("color", Color.WHITE) if r[k].get("color", null) is Color else Color.WHITE}
			roster = clean
			roster_changed.emit()
		return
	packet.emit(from, kind, payload)
