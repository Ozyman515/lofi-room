extends Node
## The room TVs in a shared room: the Big TV (living room) and the Theater Screen, kept in step for everyone the
## same way as the CRT (net_game.gd): whoever puts a tape in a TV (the host, or a guest the host lets use the TVs)
## sends its picture (JPEG) and sound (ADPCM) to the others, the host passing a guest's stream on; the transport
## buttons act on that person's tape; the host's power switch counts for everyone.
## Wire format: K_VIDEO payload[0] = 2 + slot, K_SOUND channel = 3 + slot, events {"k": "rtv", "a": ..., "s": slot}.

const SafeImage := preload("res://safe_image.gd")
const Net := preload("res://net_session.gd")
const Adpcm := preload("res://adpcm.gd")

const SLOTS := 2                        # 0 = Big TV, 1 = Theater Screen
const TV_WIDTH := 512
const MAX_VIDEO_BYTES := 48000
const VIDEO_BACKLOG := 64 * 1024
const RATE := 24000.0
const CHUNK := 960
const PRIME := 5
const TV_BUTTONS := 4                   # rewind, fast forward, play/pause, stop

var net: Node
var main: Node3D
var src := [1, 1]                       # whose tape is on each TV
var live := [false, false]
var _was := [false, false]
var _claim := [0, 0]
var _last_frame := [0, 0]
var _cap: Array = [null, null]
var _acc: Array = [PackedVector2Array(), PackedVector2Array()]
var _phase := [0.0, 0.0]
var _last := [Vector2.ZERO, Vector2.ZERO]
var _silent := [0.0, 0.0]
var _player: Array = [null, null]       # a guest's player for a remote tape's sound (on that TV's own bus)
var _pending: Array = [[], []]
var _primed := [false, false]
var _skips := [0, 0]
var _ratio := 2.0
var _power_sent := [true, true]


func setup(session: Node, m: Node3D) -> void:
	net = session
	main = m
	_ratio = AudioServer.get_mix_rate() / RATE
	net.state_changed.connect(_on_state)
	# the tape buttons act on whoever's tape is on that TV
	for s in SLOTS:
		var v = _vcr(s)
		if v == null:
			continue
		for bi in v.buttons.size():
			var b: Dictionary = v.buttons[bi]
			var local_cb: Callable = b["cb"]
			var slot: int = s
			var idx: int = bi
			b["cb"] = func() -> void:
				if button_remote(slot, idx):
					return
				local_cb.call()


func _rtv(s: int):
	if main.apartment == null:
		return null
	return main.apartment.liv_tv if s == 0 else main.apartment.th_tv


func _vcr(s: int):
	var t = _rtv(s)
	return t.vcr if t != null else null


func _bus(s: int) -> String:
	return "TV_living" if s == 0 else "TV_theater"


func _on_state() -> void:
	if net.is_online():
		return
	for s in SLOTS:
		src[s] = 1
		live[s] = false
		_was[s] = false
		if _player[s] != null:
			(_player[s] as AudioStreamPlayer).queue_free()
			_player[s] = null
		_pending[s] = []


func _name(id: int) -> String:
	return str(net.roster.get(id, {}).get("name", "Someone"))


func active(s: int) -> bool:
	var v = _vcr(s)
	return v != null and v.has_tape and (v.state == v.State.PLAYING or v.state == v.State.PAUSED or v.state == v.State.LOADING)


func _process(delta: float) -> void:
	if net == null or not net.is_online() or main.apartment == null:
		return
	var mine := 0
	for s in SLOTS:
		if src[s] == net.my_id and live[s]:
			mine += 1
	for s in SLOTS:
		var v = _vcr(s)
		if v == null:
			continue
		_ownership(s)
		_video_tick(s, mine)
		v.remote_video_tick()
		_sound_tick(s)
		_play_sound(s)
	if net.is_host():
		_power_tick()


# ---- who owns each TV

func _ownership(s: int) -> void:
	var a := active(s)
	if a and not _was[s]:
		_claim[s] = Time.get_ticks_msec()
		if net.is_host():
			_set_src(s, 1)
		else:
			net.send_var(1, Net.K_EVENT, {"k": "rtv", "a": "take", "s": s})
	elif not a and _was[s] and src[s] == net.my_id:
		if net.is_host():
			live[s] = false
		else:
			net.send_var(1, Net.K_EVENT, {"k": "rtv", "a": "drop", "s": s})
	_was[s] = a
	if net.is_host():
		if src[s] == 1:
			live[s] = a
		elif not bool(main.guest_allow.get("tv", false)):
			_set_src(s, 1)
	if a and src[s] != net.my_id and Time.get_ticks_msec() - _claim[s] > 4000:
		_vcr(s).stop_for_other()
		main.updater.show_toast("%s put a tape in the %s." % [_name(src[s]), "Big TV" if s == 0 else "Theater Screen"], 3.0)


func _set_src(s: int, id: int) -> void:
	src[s] = id
	live[s] = true if id != 1 else active(s)
	if id != net.my_id and active(s):
		_vcr(s).stop_for_other()


func button_remote(s: int, i: int) -> bool:
	if net == null or not net.is_online() or src[s] == net.my_id or not live[s] or i >= TV_BUTTONS:
		return false
	net.send_var(src[s] if net.is_host() else 1, Net.K_EVENT, {"k": "rtv", "a": "btn", "s": s, "b": i})
	return true


func _apply_button(s: int, i: int) -> void:
	var v = _vcr(s)
	match i:
		0: v.seek_rel(-10.0)
		1: v.seek_rel(30.0)
		2: v.play_pause()
		3: v.stop()


# a guest pressed a room TV's power switch: the host's counts
func request_power(s: int) -> void:
	net.send_var(1, Net.K_EVENT, {"k": "rtv", "a": "power", "s": s})


func _power_tick() -> void:
	for s in SLOTS:
		var on: bool = _rtv(s).is_on()
		if on != _power_sent[s]:
			_power_sent[s] = on
			main.net_game.push_state_soon()


# ---- what goes into the host's room state, and a guest applying it

func state() -> Array:
	var out := []
	for s in SLOTS:
		out.append([src[s], live[s], _rtv(s).is_on() if _rtv(s) != null else true])
	return out


func apply_state(a) -> void:
	if not (a is Array):
		return
	for s in mini(SLOTS, a.size()):
		var e = a[s]
		if not (e is Array) or e.size() < 3:
			continue
		src[s] = int(e[0])
		live[s] = bool(e[1])
		var t = _rtv(s)
		if t != null and bool(e[2]) != t.is_on():
			if s == 0:
				main.apartment.set_liv_tv(bool(e[2]))
			else:
				t.set_power(bool(e[2]))


# ---- events

func on_event(from: int, d: Dictionary) -> void:
	var s := clampi(int(d.get("s", 0)), 0, SLOTS - 1)
	var allowed := bool(main.guest_allow.get("tv", false))
	match str(d.get("a", "")):
		"take":
			if net.is_host() and allowed:
				_set_src(s, from)
		"drop":
			if net.is_host() and from == src[s]:
				src[s] = 1
				live[s] = active(s)
		"power":
			if net.is_host() and allowed and not main.egg_active:
				if s == 0:
					main.apartment.set_liv_tv(not _rtv(s).is_on())
				else:
					_rtv(s).set_power(not _rtv(s).is_on())
		"btn":
			var b := int(d.get("b", -1))
			if src[s] == net.my_id:
				_apply_button(s, b)
			elif net.is_host() and allowed and src[s] != from:
				net.send_var(src[s], Net.K_EVENT, d)      # pass it on to whoever's tape it is


func on_roster_left(id: int) -> void:
	for s in SLOTS:
		if src[s] == id:
			src[s] = 1
			live[s] = active(s)


# ---- picture

func _video_tick(s: int, mine: int) -> void:
	if src[s] != net.my_id or not live[s] or net.peer_ids().is_empty():
		return
	var now := Time.get_ticks_msec()
	var fps := 12.0 if net.peer_ids().size() <= 3 else (9.0 if net.peer_ids().size() <= 5 else 7.0)
	fps /= float(maxi(mine, 1))                           # two TVs of mine going at once: half the rate each
	if now - int(_last_frame[s]) < int(1000.0 / fps):
		return
	var tex: Texture2D = _vcr(s).current_frame_texture()
	if tex == null:
		return
	_last_frame[s] = now
	var img := tex.get_image()
	if img == null or img.get_width() == 0:
		return
	if img.get_width() > TV_WIDTH:
		img.resize(TV_WIDTH, int(img.get_height() * float(TV_WIDTH) / img.get_width()), Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	var buf := img.save_jpg_to_buffer(0.55)
	if buf.size() > MAX_VIDEO_BYTES:
		return
	var pk := PackedByteArray([2 + s])
	pk.append_array(buf)
	if net.is_host():
		for id in net.peer_ids():
			if net.backlog(id) < VIDEO_BACKLOG:
				net.send_to(id, Net.K_VIDEO, pk, false)
	elif net.backlog(1) < VIDEO_BACKLOG:
		net.send_to(1, Net.K_VIDEO, pk, false)


# a picture for a room TV (payload[0] is 2 + slot). Returns true if it was one.
func on_video(from: int, payload: PackedByteArray) -> bool:
	if payload.size() < 2 or payload[0] < 2 or payload[0] > 1 + SLOTS:
		return false
	var s: int = payload[0] - 2
	if net.is_host():
		if from != src[s]:
			return true
		for id in net.peer_ids():
			if id != from and net.backlog(id) < VIDEO_BACKLOG:
				net.send_to(id, Net.K_VIDEO, payload, false)
	elif from != 1 or src[s] == net.my_id:
		return true
	if payload.size() > 2 * 1024 * 1024:
		return true
	var img := SafeImage.jpeg(payload.slice(1), 2048)
	if img != null and _vcr(s) != null:
		_vcr(s).remote_video_frame(img, _name(src[s]))
	return true


# ---- sound

func _sound_tick(s: int) -> void:
	if _cap[s] == null:
		var bi := AudioServer.get_bus_index(_bus(s))
		if bi < 0:
			return
		var c := AudioEffectCapture.new()
		c.buffer_length = 0.5
		AudioServer.add_bus_effect(bi, c)
		_cap[s] = c
	var cap: AudioEffectCapture = _cap[s]
	var avail := cap.get_frames_available()
	if avail <= 0:
		return
	var frames := cap.get_buffer(avail)
	if src[s] != net.my_id or not live[s] or net.peer_ids().is_empty():
		_acc[s] = PackedVector2Array()
		return                                            # (playing someone else's tape: don't echo it)
	var acc: PackedVector2Array = _acc[s]
	var ph: float = _phase[s]
	var last: Vector2 = _last[s]
	for f in frames:
		ph += 1.0
		while ph >= _ratio:
			ph -= _ratio
			acc.append(last.lerp(f, 1.0 - ph / _ratio))
		last = f
	_phase[s] = ph
	_last[s] = last
	while acc.size() >= CHUNK:
		var chunk := acc.slice(0, CHUNK)
		acc = acc.slice(CHUNK)
		var loud := false
		for i in chunk.size():
			if absf(chunk[i].x) > 0.002 or absf(chunk[i].y) > 0.002:
				loud = true
				break
		if not loud:
			_silent[s] = float(_silent[s]) + CHUNK / RATE
			if float(_silent[s]) > 0.5:
				continue
		else:
			_silent[s] = 0.0
		var packet := PackedByteArray([3 + s])
		packet.append_array(Adpcm.encode(chunk))
		if net.is_host():
			for id in net.peer_ids():
				net.send_to(id, Net.K_SOUND, packet, false)
		else:
			net.send_to(1, Net.K_SOUND, packet, false)
	_acc[s] = acc


# a sound packet for a room TV (channel 3 + slot). Returns true if it was one.
func on_sound(from: int, payload: PackedByteArray) -> bool:
	if payload.size() < 2 or payload[0] < 3 or payload[0] > 2 + SLOTS:
		return false
	var s: int = payload[0] - 3
	if net.is_host():
		if from != src[s]:
			return true
		for id in net.peer_ids():
			if id != from:
				net.send_to(id, Net.K_SOUND, payload, false)
	elif from != 1 or src[s] == net.my_id:
		return true
	var frames: PackedVector2Array = Adpcm.decode(payload.slice(1))
	if frames.is_empty():
		return true
	if _player[s] == null:
		var g := AudioStreamGenerator.new()
		g.mix_rate = RATE
		g.buffer_length = 0.6
		var p := AudioStreamPlayer.new()                  # on that TV's own bus: its speakers and the 15% rule apply
		p.stream = g
		p.bus = _bus(s)
		add_child(p)
		p.play()
		_player[s] = p
		_primed[s] = false
		_skips[s] = 0
	var q: Array = _pending[s]
	while q.size() > 16:
		q.pop_front()
	q.append(frames)
	return true


func _play_sound(s: int) -> void:
	var p: AudioStreamPlayer = _player[s]
	if p == null:
		return
	var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var q: Array = _pending[s]
	var sk := pb.get_skips()
	if sk != int(_skips[s]):
		_skips[s] = sk
		if q.size() < 2:
			_primed[s] = false
	if not bool(_primed[s]):
		if q.size() < PRIME:
			return
		_primed[s] = true
	while not q.is_empty():
		var fr: PackedVector2Array = q[0]
		if pb.get_frames_available() < fr.size():
			break
		q.pop_front()
		pb.push_buffer(fr)
