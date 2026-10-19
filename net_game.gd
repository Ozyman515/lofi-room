extends Node
## Game sharing. The host runs the console / arcade as usual and streams the picture (JPEG) and the
## sound (16-bit) to the guests. A guest holding a pad sends its buttons back; the host feeds them to
## the emulator as player 2 (or player 1 when the host plays the right-hand arcade stick).
## Guests mirror what the host did to the console: cart in, console power, TV power.

const Net := preload("res://net_session.gd")

const VIDEO_FPS := 30.0
const JPEG_QUALITY := 0.6
const MAX_VIDEO_BYTES := 48000          # stay under the data channel's message size

var net: Node
var main: Node3D
var emu: Node

var guest_pad := {}                     # host side: guest id -> pad held
var guest_mask := {}                    # host side: guest id -> buttons
var p2_id := 0                          # the guest currently driving the second port
var _last_video := 0
var _state_known := {}                  # host side: guest id -> last state dict sent
var _state_t := 0.0
var _resend_t := 0.0
var _last_state := {}
var _my_pad_sent := false
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
			guest_mask.erase(id)
			_state_known.erase(id)
			if id == p2_id:
				p2_id = 0
				emu.set_remote_buttons(0)


func _process(delta: float) -> void:
	if net == null or not net.is_online():
		return
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
	return {"k": "game", "cart": main.slot_cart, "console": main.console_on, "tv": main.vcr.tv_on,
		"run": emu.state == emu.State.RUNNING}


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
	for id in net.peer_ids():
		net.send_to(id, Net.K_VIDEO, buf, false)


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
	if held != _my_pad_sent:
		_my_pad_sent = held
		net.send_var(1, Net.K_EVENT, {"k": "pad", "held": held})
		if not held:
			_my_mask_sent = -1


func _on_packet(from: int, kind: int, payload: PackedByteArray) -> void:
	if net.is_host():
		match kind:
			Net.K_EVENT:
				var d = Net.read_var(payload)
				if d is Dictionary and d.get("k", "") == "pad":
					_guest_pad(from, bool(d.get("held", false)))
			Net.K_INPUT:
				if payload.size() >= 2 and from == p2_id:
					emu.set_remote_buttons(payload.decode_u16(0))
		return
	if from != 1:
		return
	match kind:
		Net.K_EVENT:
			var d = Net.read_var(payload)
			if d is Dictionary and d.get("k", "") == "game":
				_apply_state(d)
		Net.K_VIDEO:
			var img := Image.new()
			if img.load_jpg_from_buffer(payload) == OK:
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


func _apply_state(d: Dictionary) -> void:
	main.net_apply_game(d)
	if not bool(d.get("run", false)):
		emu.remote_stopped()
