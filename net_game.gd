extends Node
## Game sharing. The host runs the console / arcade as usual and streams the picture (JPEG) and the
## sound (16-bit) to the guests. A guest holding a pad sends its buttons back; the host feeds them to
## the emulator as player 2 (or player 1 when the host plays the right-hand arcade stick).
## Guests mirror what the host did to the console: cart in, console power, TV power.

const Net := preload("res://net_session.gd")

const VIDEO_FPS := 30.0
const TV_FPS := 12.0
const TV_WIDTH := 640
var _last_tv := 0
const JPEG_QUALITY := 0.6
const MAX_VIDEO_BYTES := 48000          # stay under the data channel's message size

var net: Node
var main: Node3D
var emu: Node

var guest_pad := {}                     # host side: guest id -> pad held
var pads_seen := {}                     # everyone: id -> true for players holding a pad (from the host's state)
var guest_arcade := {}                  # host side: guest id -> true while they play at the arcade sticks (not a pad)
var guest_pad_idx := {}                 # host side: guest id -> which rug pad they hold
var pad_of_seen := {}                   # everyone: id -> which rug pad that player holds
# The TV shows one person's tape: whoever last put one in (the host, or a guest the host lets use the TV).
# That person streams the picture and sound; the host passes a guest's stream on to everyone else.
var tv_source := 1
var tv_live := false                    # the source has a tape going (so the VCR buttons act on theirs)
var _tv_was_active := false
var _tv_claim_ms := 0
var _poster_sent := {}                  # host side: guest id -> poster revision sent (-1 = told them it's private)
var _poster_parts := {}                 # guest side: rev -> {"n": parts, "got": {i: bytes}}
var _poster_t := 0.0
const POSTER_PART := 32000
var sticks_seen := {}                   # everyone: id -> true for players at the arcade sticks
var slap_minutes_seen := 30             # the host's slap cooldown, as last announced
var _last_slap := {}                    # host side: slapper id -> ms of their last slap
var my_last_slap := 0                   # ms of my own last (accepted) slap, for the countdown on the label
var guest_mask := {}                    # host side: guest id -> buttons
var p2_id := 0                          # the guest currently driving the second port
var _last_video := 0
var _state_known := {}                  # host side: guest id -> last state dict sent
var _state_t := 0.0
var _resend_t := 0.0
var _last_state := {}
var _my_pad_sent := false
var _my_arcade_sent := false
var _my_idx_sent := -2
var _my_mask_sent := -1
var _running_seen := false
var _rate := 44100.0


func setup(session: Node, m: Node3D, emulator: Node) -> void:
	net = session
	main = m
	emu = emulator
	net.packet.connect(_on_packet)
	net.state_changed.connect(_on_net_state)
	net.roster_changed.connect(_on_roster)
	emu.frame_out.connect(_on_frame)
	emu.audio_out.connect(_on_audio)
	emu.buttons_out.connect(_on_buttons_out)


func guests_playing() -> bool:
	for id in guest_pad:
		if guest_pad[id]:
			return true
	return false


func _on_net_state() -> void:
	var guest: bool = net.state == net.State.JOINED
	emu.set_remote_mode(guest)
	emu.streaming = net.state == net.State.HOSTING
	if not net.is_online():
		guest_pad.clear()
		if main.cats != null:
			main.cats.end_remote()
		if main.noir != null:
			main.noir.end_remote()
		_poster_sent.clear()
		_poster_parts.clear()
		if main.poster != null:
			main.poster.clear_remote()
		tv_source = 1
		tv_live = false
		_tv_was_active = false
		guest_arcade.clear()
		guest_pad_idx.clear()
		pad_of_seen.clear()
		sticks_seen.clear()
		guest_mask.clear()
		_state_known.clear()
		p2_id = 0
		emu.set_remote_buttons(0)
		_my_pad_sent = false


func _on_roster() -> void:
	if not net.is_host():
		return
	for id in guest_pad.keys():
		if not net.roster.has(id):
			guest_pad.erase(id)
			guest_arcade.erase(id)
			guest_pad_idx.erase(id)
			guest_mask.erase(id)
			_poster_sent.erase(id)
			if id == tv_source:
				tv_source = 1
				tv_live = my_tv_active()
			_state_known.erase(id)
			if id == p2_id:
				p2_id = 0
				emu.set_remote_buttons(0)


func _process(delta: float) -> void:
	if net == null or not net.is_online():
		return
	_tv_video_tick()
	main.vcr.remote_video_tick()
	_tv_ownership()
	if net.is_host():
		_poster_t += delta
		if _poster_t > 0.5:
			_poster_t = 0.0
			_share_poster()
	_state_t += delta
	if _state_t >= 0.2:
		_state_t = 0.0
		if net.is_host():
			_resend_t += 0.2
			if _resend_t >= 2.0:
				_resend_t = 0.0
				_state_known.clear()       # a guest may have missed a change (e.g. a cart still flying)
			_publish_state()
		else:
			_send_pad_state()


# ---- host -> guests

func _current_state() -> Dictionary:
	var pads := {}
	if main.game_mode:
		pads[1] = true
	for id in guest_pad:
		if guest_pad[id]:
			pads[id] = true
	var sticks := {}
	if main.game_mode and main.held_pad_idx < 0:
		sticks[1] = true
	for id in guest_arcade:
		if guest_arcade[id] and guest_pad.get(id, false):
			sticks[id] = true
	var pad_of := {}
	if main.game_mode and main.held_pad_idx >= 0:
		pad_of[1] = main.held_pad_idx
	for id in guest_pad_idx:
		if guest_pad.get(id, false) and not guest_arcade.get(id, false):
			pad_of[id] = guest_pad_idx[id]
	return {"ufo": main.ufo.state() if main.ufo != null else 0, "kaiju": main.kaiju.state() if main.kaiju != null else 0, "noir": main.noir.state() if main.noir != null else false, "cats": main.cats.state() if main.cats != null else {}, "tv_src": tv_source, "tv_live": tv_live, "sticks": sticks, "pad_of": pad_of, "k": "game", "cart": main.slot_cart, "console": main.console_on, "tv": main.vcr.tv_on,
		"run": emu.state == emu.State.RUNNING, "pads": pads, "slap": main.slap_minutes, "arcade": main.arcade_on, "guests": main.guest_allow, "song": main.pc._title.text if main.pc != null and main.bank.playing and not main.bank.stream_paused else ""}


func _publish_state() -> void:
	var st := _current_state()
	for id in net.peer_ids():
		if _state_known.get(id, {}) != st:
			_state_known[id] = st
			net.send_var(id, Net.K_EVENT, st)


func _on_frame(img: Image) -> void:
	if not net.is_host() or net.peer_ids().is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _last_video < int(1000.0 / VIDEO_FPS):
		return
	_last_video = now
	var q := JPEG_QUALITY
	var buf := img.save_jpg_to_buffer(q)
	if buf.size() > MAX_VIDEO_BYTES:
		buf = img.save_jpg_to_buffer(0.3)
		if buf.size() > MAX_VIDEO_BYTES:
			return
	var pk := PackedByteArray([0])
	pk.append_array(buf)
	for id in net.peer_ids():
		net.send_to(id, Net.K_VIDEO, pk, false)


# the host's tape: the TV picture goes out at a lower rate and size than a game
func _tv_video_tick() -> void:
	if tv_source != net.my_id or net.peer_ids().is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _last_tv < int(1000.0 / TV_FPS):
		return
	var tex: Texture2D = main.vcr.current_frame_texture()
	if tex == null:
		return
	_last_tv = now
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
	var pk := PackedByteArray([1])
	pk.append_array(buf)
	if net.is_host():
		for id in net.peer_ids():
			net.send_to(id, Net.K_VIDEO, pk, false)
	else:
		net.send_to(1, Net.K_VIDEO, pk, false)      # the host passes it on


# ---- who owns the TV

const TV_BUTTONS := 4                   # rewind, fast forward, play/pause, stop: these act on whoever's tape is on


func my_tv_active() -> bool:
	var v = main.vcr
	return v.has_tape and (v.state == v.State.PLAYING or v.state == v.State.PAUSED or v.state == v.State.LOADING)


func tv_source_name() -> String:
	return str(net.roster.get(tv_source, {}).get("name", "Someone"))


func _tv_ownership() -> void:
	var active := my_tv_active()
	if active and not _tv_was_active:
		_tv_claim_ms = Time.get_ticks_msec()
		if net.is_host():
			_set_tv_source(1)
		else:
			net.send_var(1, Net.K_EVENT, {"k": "tv_take"})
	elif not active and _tv_was_active and tv_source == net.my_id:
		if net.is_host():
			tv_live = false
		else:
			net.send_var(1, Net.K_EVENT, {"k": "tv_drop"})
	_tv_was_active = active
	if net.is_host():
		if tv_source == 1:
			tv_live = active
		elif not bool(main.guest_allow.get("tv", false)):
			_set_tv_source(1)                       # the host took the TV back from guests
	# somebody else's tape is on now: stop mine (after a moment, so my own claim has time to land)
	if active and tv_source != net.my_id and Time.get_ticks_msec() - _tv_claim_ms > 4000:
		main.vcr.stop_for_other()
		main.updater.show_toast("%s put a tape in." % tv_source_name(), 3.0)


func _set_tv_source(id: int) -> void:
	tv_source = id
	tv_live = true if id != 1 else my_tv_active()
	if id != net.my_id and my_tv_active():
		main.vcr.stop_for_other()


# pressing a VCR transport button while someone else's tape is on: it goes to them. Returns true if sent.
func vcr_button_remote(i: int) -> bool:
	if net == null or not net.is_online() or tv_source == net.my_id or not tv_live or i >= TV_BUTTONS:
		return false
	if net.is_host():
		net.send_var(tv_source, Net.K_EVENT, {"k": "vcr", "b": i})
	else:
		net.send_var(1, Net.K_EVENT, {"k": "vcr", "b": i})
	return true


func _apply_vcr_button(i: int) -> void:
	var v = main.vcr
	match i:
		0: v.seek_rel(-10.0)
		1: v.seek_rel(30.0)
		2: v.play_pause()
		3: v.stop()


# a guest pressed the TV's power button
func request_tv_power() -> void:
	net.send_var(1, Net.K_EVENT, {"k": "tv_power"})


func _on_audio(pcm: PackedByteArray, count: int) -> void:
	if not net.is_host() or net.peer_ids().is_empty():
		return
	var out := PackedByteArray()
	out.resize(8 + count * 4)
	out.encode_u32(0, int(emu._rate))
	out.encode_u32(4, count)
	for i in count * 2:
		out.encode_s16(8 + i * 2, int(clampf(pcm.decode_float(i * 4), -1.0, 1.0) * 32767.0))
	for id in net.peer_ids():
		net.send_to(id, Net.K_AUDIO, out, false)


# ---- guest -> host

func _on_buttons_out(mask: int) -> void:
	if not net.is_online() or net.is_host() or mask == _my_mask_sent:
		return
	_my_mask_sent = mask
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, mask & 0xFFFF)
	net.send_to(1, Net.K_INPUT, b, true)


func _send_pad_state() -> void:
	if net.is_host():
		return
	var held: bool = main.game_mode
	var arc: bool = held and main.held_pad_idx < 0
	var idx: int = main.held_pad_idx if held else -1
	if held != _my_pad_sent or arc != _my_arcade_sent or idx != _my_idx_sent:
		_my_pad_sent = held
		_my_arcade_sent = arc
		_my_idx_sent = idx
		net.send_var(1, Net.K_EVENT, {"k": "pad", "held": held, "arcade": arc, "idx": idx})
		if not held:
			_my_mask_sent = -1


func _on_packet(from: int, kind: int, payload: PackedByteArray) -> void:
	if net.is_host():
		match kind:
			Net.K_EVENT:
				var d = Net.read_var(payload)
				if d is Dictionary and d.get("k", "") == "pad":
					_guest_pad(from, bool(d.get("held", false)))
					guest_arcade[from] = bool(d.get("arcade", false))
					guest_pad_idx[from] = clampi(int(d.get("idx", -1)), -1, 7)
				elif d is Dictionary and d.get("k", "") == "slap":
					_host_slap(from, int(d.get("target", 0)))
				elif d is Dictionary:
					_host_tv_event(from, d)
			Net.K_VIDEO:
				# a guest's tape: show it here and pass it on to the others
				if from == tv_source and payload.size() >= 2 and payload.size() <= 2 * 1024 * 1024 and payload[0] == 1:
					var img := Image.new()
					if img.load_jpg_from_buffer(payload.slice(1)) == OK and img.get_width() <= 2048 and img.get_height() <= 2048:
						main.vcr.remote_video_frame(img, tv_source_name())
						for id in net.peer_ids():
							if id != from:
								net.send_to(id, Net.K_VIDEO, payload, false)
			Net.K_INPUT:
				if payload.size() >= 2 and from == p2_id:
					emu.set_remote_buttons(payload.decode_u16(0))
		return
	if from != 1:
		return
	match kind:
		Net.K_EVENT:
			var d = Net.read_var(payload)
			if d is Dictionary:
				match str(d.get("k", "")):
					"game":
						_apply_state(d)
					"slapped":
						main.get_slapped(str(d.get("by", "Someone")))
					"slap_news":
						main.updater.show_toast("%s slapped the controller out of %s's hands!" % [str(d.get("by", "?")), str(d.get("to", "?"))], 5.0)
					"slap_wait":
						my_last_slap = Time.get_ticks_msec() - (main.slap_minutes_of(slap_minutes_seen) - int(d.get("secs", 0))) * 1000
						main.updater.show_toast("You can slap again in %s." % main.fmt_wait(int(d.get("secs", 0))), 4.0)
					"slap_ok":
						my_last_slap = Time.get_ticks_msec()
					"cat_pet":
						if main.cats != null:
							main.cats.pet(str(d.get("w", "t")) == "t", true)
					"poster":
						_guest_poster_part(d)
					"poster_off":
						_poster_parts.clear()
						if main.poster != null:
							main.poster.clear_remote()
					"vcr":
						if tv_source == net.my_id:
							_apply_vcr_button(int(d.get("b", -1)))
		Net.K_VIDEO:
			if payload.size() > 2 * 1024 * 1024 or payload.size() < 2:
				return                                  # no honest frame is that big
			var img := Image.new()
			if img.load_jpg_from_buffer(payload.slice(1)) == OK and img.get_width() <= 2048 and img.get_height() <= 2048:
				if payload[0] == 1:
					if tv_source != net.my_id:
						main.vcr.remote_video_frame(img, tv_source_name())
				else:
					emu.remote_frame(img)
		Net.K_AUDIO:
			if payload.size() >= 8:
				var count := payload.decode_u32(4)
				if count <= 4000 and payload.size() >= 8 + count * 4:
					emu.remote_audio(payload.slice(8), float(clampi(payload.decode_u32(0), 8000, 192000)), count)


# a guest picks up / puts down a pad: the first one to pick up drives player 2
func _guest_pad(id: int, held: bool) -> void:
	guest_pad[id] = held
	if held and p2_id == 0:
		p2_id = id
	elif not held and id == p2_id:
		p2_id = 0
		emu.set_remote_buttons(0)
		for other in guest_pad:
			if guest_pad[other]:
				p2_id = other
				break


# ---- the host's poster, for guests (only if the host allows it)

func _share_poster() -> void:
	var p = main.poster
	if p == null:
		return
	var rev: int = p.revision if main.share_poster else -1
	var jpeg := PackedByteArray()
	for id in net.peer_ids():
		if net._connecting_since.has(id) or int(_poster_sent.get(id, -1)) == rev:
			continue
		_poster_sent[id] = rev
		if rev < 0:
			net.send_var(id, Net.K_EVENT, {"k": "poster_off"})
			continue
		if jpeg.is_empty():
			jpeg = p.shared_jpeg()
			if jpeg.is_empty():
				return
		var n := int(ceil(jpeg.size() / float(POSTER_PART)))
		for i in n:
			net.send_var(id, Net.K_EVENT, {"k": "poster", "rev": rev, "i": i, "n": n,
				"d": jpeg.slice(i * POSTER_PART, mini((i + 1) * POSTER_PART, jpeg.size()))})


func _guest_poster_part(d: Dictionary) -> void:
	var rev := int(d.get("rev", 0))
	var n := int(d.get("n", 0))
	var i := int(d.get("i", -1))
	var bytes = d.get("d", null)
	if n <= 0 or n > 160 or i < 0 or i >= n or not (bytes is PackedByteArray):
		return
	for k in _poster_parts.keys():
		if k != rev:
			_poster_parts.erase(k)                  # an older picture still arriving: drop it
	if not _poster_parts.has(rev):
		_poster_parts[rev] = {"n": n, "got": {}}
	var entry: Dictionary = _poster_parts[rev]
	entry["got"][i] = bytes
	if entry["got"].size() < n:
		return
	var all := PackedByteArray()
	for k in n:
		all.append_array(entry["got"][k])
	_poster_parts.erase(rev)
	var img := Image.new()
	if img.load_jpg_from_buffer(all) == OK and img.get_width() <= 4096 and img.get_height() <= 4096 and main.poster != null:
		main.poster.show_remote(img, str(net.roster.get(1, {}).get("name", "The host")))


func _host_tv_event(from: int, d: Dictionary) -> void:
	var allowed := bool(main.guest_allow.get("tv", false))
	match str(d.get("k", "")):
		"tv_take":
			if allowed:
				_set_tv_source(from)
		"tv_drop":
			if from == tv_source:
				tv_source = 1
				tv_live = my_tv_active()
		"tv_power":
			if allowed and not main.egg_active and not main._net_play_lock():
				main.vcr.toggle_tv()
		"ufo_on":
			if main.ufo != null:
				main.ufo.request_visit()
		"kaiju_on":
			if main.kaiju != null:
				main.kaiju.request_walk()
		"noir_on":
			if main.noir != null:
				main.noir.on_guest_event(d)
		"cat_pet", "cat_treats", "cat_bed":
			if main.cats != null:
				main.cats.on_guest_event(d)
				if str(d.get("k", "")) == "cat_pet":
					for id in net.peer_ids():
						if id != from:
							net.send_var(id, Net.K_EVENT, d)
		"vcr":
			if not allowed:
				return
			var b := int(d.get("b", -1))
			if tv_source == 1:
				_apply_vcr_button(b)
			elif tv_source != from:
				net.send_var(tv_source, Net.K_EVENT, {"k": "vcr", "b": b})


func _apply_state(d: Dictionary) -> void:
	var p = d.get("pads", {})
	pads_seen = p if p is Dictionary else {}
	var st = d.get("sticks", {})
	sticks_seen = st if st is Dictionary else {}
	var po = d.get("pad_of", {})
	pad_of_seen = po if po is Dictionary else {}
	slap_minutes_seen = int(d.get("slap", 30))
	tv_source = int(d.get("tv_src", 1))
	tv_live = bool(d.get("tv_live", false))
	main.net_apply_game(d)
	if not bool(d.get("run", false)):
		emu.remote_stopped()


# ---- slapping the controller out of somebody's hands

func holds_pad(id: int) -> bool:
	if net.is_host():
		return main.game_mode if id == net.my_id else bool(guest_pad.get(id, false))
	return bool(pads_seen.get(id, false))


# holding one of the console pads (not standing at the arcade sticks): their avatar shows it in their hands
func holds_controller(id: int) -> bool:
	if not holds_pad(id):
		return false
	if net.is_host():
		return main.held_pad_idx >= 0 if id == net.my_id else not bool(guest_arcade.get(id, false))
	return not bool(sticks_seen.get(id, false))


# rug pads somebody else is holding (so they aren't drawn lying on the rug too)
func pads_taken_by_others() -> Dictionary:
	var out := {}
	if net.is_host():
		for id in guest_pad_idx:
			if guest_pad.get(id, false) and not guest_arcade.get(id, false) and int(guest_pad_idx[id]) >= 0:
				out[int(guest_pad_idx[id])] = id
	else:
		for id in pad_of_seen:
			if int(id) != net.my_id and int(pad_of_seen[id]) >= 0:
				out[int(pad_of_seen[id])] = int(id)
	return out


func slap_minutes() -> int:
	return main.slap_minutes if net.is_host() else slap_minutes_seen


# seconds until I may slap again (0 = now)
func slap_wait() -> int:
	var cd: int = main.slap_minutes_of(slap_minutes())
	if cd <= 0:
		return 0
	var left: int = cd - (Time.get_ticks_msec() - my_last_slap) / 1000
	return maxi(0, left) if my_last_slap > 0 else 0


func slap(target: int) -> void:
	if not net.is_online() or target == net.my_id:
		return
	if net.is_host():
		_host_slap(net.my_id, target)
	else:
		net.send_var(1, Net.K_EVENT, {"k": "slap", "target": target})


# the host decides: the slapper's cooldown, and whether the target really holds a pad
func _host_slap(from: int, target: int) -> void:
	var cd: int = main.slap_minutes_of(main.slap_minutes)
	if main.slap_minutes < 0:
		return
	var now := Time.get_ticks_msec()
	var left: int = cd - (now - int(_last_slap.get(from, -1000000000))) / 1000
	if _last_slap.has(from) and left > 0:
		_tell(from, {"k": "slap_wait", "secs": left})
		return
	if not holds_pad(target) or target == from:
		return
	_last_slap[from] = now
	var by := str(net.roster.get(from, {}).get("name", "Someone"))
	var to := str(net.roster.get(target, {}).get("name", "someone"))
	_tell(from, {"k": "slap_ok"})
	if target == net.my_id:
		main.get_slapped(by)
	else:
		net.send_var(target, Net.K_EVENT, {"k": "slapped", "by": by})
	for id in net.roster:
		if id != target:
			_tell(id, {"k": "slap_news", "by": by, "to": to})


func _tell(id: int, d: Dictionary) -> void:
	if id == net.my_id:
		match str(d["k"]):
			"slap_wait":
				my_last_slap = _last_slap.get(id, Time.get_ticks_msec())
				main.updater.show_toast("You can slap again in %s." % main.fmt_wait(int(d.get("secs", 0))), 4.0)
			"slap_news":
				main.updater.show_toast("%s slapped the controller out of %s's hands!" % [str(d.get("by", "?")), str(d.get("to", "?"))], 5.0)
			"slap_ok":
				my_last_slap = Time.get_ticks_msec()
	else:
		net.send_var(id, Net.K_EVENT, d)
