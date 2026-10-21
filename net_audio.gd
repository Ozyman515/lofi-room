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

var net: Node
var main: Node3D
var _capture: AudioEffectCapture
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
	if _capture != null:
		return
	var bi := AudioServer.get_bus_index("SpeakerClock")
	if bi < 0:
		return
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(bi, _capture)


func _process(_delta: float) -> void:
	if net == null or not net.is_online():
		return
	if net.is_host():
		_host_tick()
	else:
		_guest_tick()


func _host_tick() -> void:
	if _capture == null:
		_ensure_capture()
		return
	var guests: Array = net.peer_ids()
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


# ---- guest: receive + play through the room's speakers

func _start_remote() -> void:
	if _gen != null:
		return
	_gen = AudioStreamGenerator.new()        # only a marker that the live feed is on
	main.bank.live_start(RATE)
	_remote_playing = true
	_pending.clear()


func _stop_remote() -> void:
	if _gen == null:
		return
	main.bank.live_stop()
	_gen = null
	_pending.clear()
	_remote_playing = false


func _guest_tick() -> void:
	if _gen == null:
		return
	while not _pending.is_empty():
		if not main.bank.live_push(_pending[0]):
			break
		_pending.pop_front()


func _on_packet(from: int, kind: int, payload: PackedByteArray) -> void:
	if kind != Net.K_SOUND or from != 1 or payload.size() < 2 or net.is_host():
		return
	if payload[0] != CH_MUSIC:
		return
	if _gen == null:
		_start_remote()
	var frames: PackedVector2Array = Adpcm.decode(payload.slice(1))
	if frames.is_empty():
		return
	# keep latency bounded: if we fall far behind, drop the oldest
	while _pending.size() > 12:
		_pending.pop_front()
	_pending.append(frames)
