extends Node
## Shared listening: what plays on the host's speakers plays on everybody's. The host captures the song
## from its (muted) clock bus, downsamples to 24 kHz, codes it as ADPCM and sends ~40 ms packets to each
## guest; a guest feeds them into a generator stream that the room's speakers play, so it comes out of the
## same places in the room. Guests keep a small buffer (~150 ms) to ride out jitter.
## The same path will carry voices later (a second channel id).

const Net := preload("res://net_session.gd")
const Adpcm := preload("res://adpcm.gd")

const RATE := 24000.0
const CHUNK := 960                      # frames per packet at 24 kHz = 40 ms
const CH_MUSIC := 1
const CH_TV := 2

var net: Node
var main: Node3D
var _capture: AudioEffectCapture
var _tv_capture: AudioEffectCapture
var _tv_acc := PackedVector2Array()
var _tv_phase := 0.0
var _tv_last := Vector2.ZERO
var _tv_silent_t := 0.0
var _tv_gen: AudioStreamGenerator
var _tv_player: AudioStreamPlayer3D
var _tv_pending: Array = []
var _tv_primed := false                 # a little sound is queued up before playing starts (or restarts after a gap)
var _tv_skips := 0
const TV_PRIME := 5                     # packets (200 ms) to have in hand before starting
var _mix_rate := 48000.0
var _acc := PackedVector2Array()
var _ratio := 2.0
var _phase := 0.0
var _last := Vector2.ZERO
var _silent_t := 0.0

# guest side
var _gen: AudioStreamGenerator
var _pending: Array = []            # decoded packets waiting for buffer room
var _target_buf := 0.15
var _remote_playing := false
var _remote_title := ""


func setup(session: Node, m: Node3D) -> void:
	net = session
	main = m
	net.packet.connect(_on_packet)
	net.state_changed.connect(_on_state)
	_mix_rate = AudioServer.get_mix_rate()
	_ratio = _mix_rate / RATE


func _on_state() -> void:
	if net.is_host():
		_ensure_capture()
	elif net.state == net.State.JOINED:
		_start_remote()
	else:
		_stop_remote()


# ---- host: capture + send

func _ensure_capture() -> void:
	if _capture == null:
		var bi := AudioServer.get_bus_index("SpeakerClock")
		if bi >= 0:
			_capture = AudioEffectCapture.new()
			_capture.buffer_length = 0.5
			AudioServer.add_bus_effect(bi, _capture)
	_ensure_tv_capture()


func _ensure_tv_capture() -> void:
	if _tv_capture == null:
		var ti := AudioServer.get_bus_index("TV")
		if ti >= 0:
			_tv_capture = AudioEffectCapture.new()
			_tv_capture.buffer_length = 0.5
			AudioServer.add_bus_effect(ti, _tv_capture)


func _process(_delta: float) -> void:
	if net == null or not net.is_online():
		return
	if net.is_host():
		_host_tick()
	else:
		_guest_tick()
		if _tv_capture == null:
			_ensure_tv_capture()
		_tv_tick([1])                       # sends only while my tape is the one on the TV
	_play_tv()


func _host_tick() -> void:
	if _capture == null:
		_ensure_capture()
		return
	var guests: Array = net.peer_ids()
	_tv_tick(guests)
	var avail := _capture.get_frames_available()
	if avail <= 0:
		return
	var frames := _capture.get_buffer(avail)
	if guests.is_empty():
		return
	# resample to 24 kHz (linear) into the accumulator
	for f in frames:
		_phase += 1.0
		while _phase >= _ratio:
			_phase -= _ratio
			_acc.append(_last.lerp(f, 1.0 - _phase / _ratio))
		_last = f
	var vol: float = main.bank.master if main.bank != null else 1.0
	while _acc.size() >= CHUNK:
		var chunk := _acc.slice(0, CHUNK)
		_acc = _acc.slice(CHUNK)
		# the clock bus is muted and unscaled: apply the room's music volume so guests hear what the host hears
		var loud := false
		for i in chunk.size():
			chunk[i] *= vol
			if absf(chunk[i].x) > 0.002 or absf(chunk[i].y) > 0.002:
				loud = true
		if not loud:
			_silent_t += CHUNK / RATE
			if _silent_t > 0.5:
				continue                       # nothing playing: send nothing (guests coast to silence)
		else:
			_silent_t = 0.0
		var packet := PackedByteArray([CH_MUSIC])
		packet.append_array(Adpcm.encode(chunk))
		for id in guests:
			net.send_to(id, Net.K_SOUND, packet, false)


# the TV's sound: already at the volume the host hears (its bus is live, not muted)
# The TV's sound goes out from whoever's tape is on (a guest sends theirs to the host, who passes it on).
func _tv_tick(guests: Array) -> void:
	if _tv_capture == null:
		return
	var avail := _tv_capture.get_frames_available()
	if avail <= 0:
		return
	var frames := _tv_capture.get_buffer(avail)
	var ng = main.net_game
	if guests.is_empty() or ng == null or ng.tv_source != net.my_id:
		_tv_acc.clear()
		return                               # (the TV bus is also playing someone else's tape: don't echo it)
	for f in frames:
		_tv_phase += 1.0
		while _tv_phase >= _ratio:
			_tv_phase -= _ratio
			_tv_acc.append(_tv_last.lerp(f, 1.0 - _tv_phase / _ratio))
		_tv_last = f
	while _tv_acc.size() >= CHUNK:
		var chunk := _tv_acc.slice(0, CHUNK)
		_tv_acc = _tv_acc.slice(CHUNK)
		var loud := false
		for i in chunk.size():
			if absf(chunk[i].x) > 0.002 or absf(chunk[i].y) > 0.002:
				loud = true
				break
		if not loud:
			_tv_silent_t += CHUNK / RATE
			if _tv_silent_t > 0.5:
				continue
		else:
			_tv_silent_t = 0.0
		var packet := PackedByteArray([CH_TV])
		packet.append_array(Adpcm.encode(chunk))
		for id in guests:
			net.send_to(id, Net.K_SOUND, packet, false)


# ---- guest: receive + play through the room's speakers

func _start_remote() -> void:
	if _gen != null:
		return
	_gen = AudioStreamGenerator.new()        # only a marker that the live feed is on
	main.bank.live_start(RATE)
	_remote_playing = true
	_pending.clear()


func _stop_remote() -> void:
	if _tv_player != null:
		_tv_player.stop()
		_tv_player.queue_free()
		_tv_player = null
		_tv_gen = null
		_tv_pending.clear()
	if _gen == null:
		return
	main.bank.live_stop()
	_gen = null
	_pending.clear()
	_remote_playing = false


func _ensure_tv_player() -> void:
	if _tv_player != null:
		return
	_tv_primed = false
	_tv_skips = 0
	_tv_gen = AudioStreamGenerator.new()
	_tv_gen.mix_rate = RATE
	_tv_gen.buffer_length = 0.6
	_tv_player = AudioStreamPlayer3D.new()
	_tv_player.stream = _tv_gen
	_tv_player.unit_size = 4.0
	_tv_player.max_distance = 40.0
	_tv_player.bus = "TV"
	main.tv_root.add_child(_tv_player)
	_tv_player.position = Vector3(0, 0.6, 0.3)
	_tv_player.play()


func _play_tv() -> void:
	if _tv_player != null:
		var pb := _tv_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if pb == null:
			return
		# ran dry (a late packet): wait for a small cushion again instead of playing scraps with gaps between
		var skips := pb.get_skips()
		if skips != _tv_skips:
			_tv_skips = skips
			if _tv_pending.size() < 2:
				_tv_primed = false
		if not _tv_primed:
			if _tv_pending.size() < TV_PRIME:
				return
			_tv_primed = true
		while not _tv_pending.is_empty():
			var fr: PackedVector2Array = _tv_pending[0]
			if pb.get_frames_available() < fr.size():
				break
			_tv_pending.pop_front()
			pb.push_buffer(fr)


func _guest_tick() -> void:
	if _gen == null:
		return
	while not _pending.is_empty():
		if not main.bank.live_push(_pending[0]):
			break
		_pending.pop_front()


func _on_packet(from: int, kind: int, payload: PackedByteArray) -> void:
	if kind != Net.K_SOUND or payload.size() < 2:
		return
	if main.net_room_tvs != null and main.net_room_tvs.on_sound(from, payload):
		return                                  # the Big TV's or the Theater Screen's sound
	var ng = main.net_game
	if net.is_host():
		# only a guest whose tape is on the TV sends TV sound: play it here and pass it on
		if payload[0] != CH_TV or ng == null or from != ng.tv_source:
			return
		for id in net.peer_ids():
			if id != from:
				net.send_to(id, Net.K_SOUND, payload, false)
	elif from != 1 or (payload[0] == CH_TV and ng != null and ng.tv_source == net.my_id):
		return
	var frames: PackedVector2Array = Adpcm.decode(payload.slice(1))
	if frames.is_empty():
		return
	if payload[0] == CH_TV:
		_ensure_tv_player()
		while _tv_pending.size() > 16:
			_tv_pending.pop_front()
		_tv_pending.append(frames)
		return
	if payload[0] != CH_MUSIC:
		return
	if _gen == null:
		_start_remote()
	# keep latency bounded: if we fall far behind, drop the oldest
	while _pending.size() > 12:
		_pending.pop_front()
	_pending.append(frames)
