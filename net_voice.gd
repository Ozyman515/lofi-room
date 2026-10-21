extends Node
## Voice chat. Your microphone is captured on a "Mic" bus (muted so you don't hear yourself), coded as
## ADPCM in 40 ms packets and sent to everyone; guests send to the host, who passes each packet on to the
## other guests. Each player's voice plays from their avatar's head. Push-to-talk or open mic, a mute,
## and a volume per player that you can set and that is shared, so pointing at somebody shows the volume
## they have you at.

const Net := preload("res://net_session.gd")
const Adpcm := preload("res://adpcm.gd")

const RATE := 24000.0
const CHUNK := 960
const SETTINGS_FILE := "user://lofi_room.cfg"

var net: Node
var main: Node3D
var avatars: Node3D
var mic_on := true                 # the master switch (false = muted)
var push_to_talk := false
var talking := false               # held key / button while push-to-talk
var gate := 0.012                  # open-mic noise gate (RMS)
var my_volumes := {}               # id -> 0..1, how loud I hear them (persisted by name)
var their_volumes := {}            # id -> 0..1, how loud they have me (shared)
var speaking := {}                 # id -> last ms a packet arrived (for the indicator)
var levels := {}                   # id -> recent loudness 0..1

var _mic: AudioStreamPlayer
var _capture: AudioEffectCapture
var _mix_rate := 48000.0
var _ratio := 2.0
var _phase := 0.0
var _last := Vector2.ZERO
var _acc := PackedVector2Array()
var _players := {}                 # id -> AudioStreamPlayer3D
var _pending := {}                 # id -> Array of frames
var _share_t := 0.0
var _shared := {}
var _my_level := 0.0


func setup(session: Node, m: Node3D, av: Node3D) -> void:
	net = session
	main = m
	avatars = av
	net.packet.connect(_on_packet)
	net.state_changed.connect(_on_state)
	net.roster_changed.connect(_on_roster)
	_mix_rate = AudioServer.get_mix_rate()
	_ratio = _mix_rate / RATE
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_FILE) == OK:
		mic_on = bool(cf.get_value("voice", "mic_on", true))
		push_to_talk = bool(cf.get_value("voice", "push_to_talk", false))


func is_available() -> bool:
	return ProjectSettings.get_setting("audio/driver/enable_input", false)


# ---- settings

func set_mic_on(on: bool) -> void:
	mic_on = on
	_save()


func set_push_to_talk(on: bool) -> void:
	push_to_talk = on
	_save()


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_FILE)
	cf.set_value("voice", "mic_on", mic_on)
	cf.set_value("voice", "push_to_talk", push_to_talk)
	cf.save(SETTINGS_FILE)


func volume_of(id: int) -> float:
	return float(my_volumes.get(id, _saved_volume(id)))


func set_volume_of(id: int, v: float) -> void:
	v = clampf(v, 0.0, 1.5)
	my_volumes[id] = v
	if _players.has(id):
		_players[id].volume_db = -80.0 if v <= 0.01 else linear_to_db(v)
	# remembered by the player's name, so it holds across visits
	var cf := ConfigFile.new()
	cf.load(SETTINGS_FILE)
	cf.set_value("voice_volumes", _name_key(id), v)
	cf.save(SETTINGS_FILE)
	_shared.erase(id)          # resend


func _saved_volume(id: int) -> float:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_FILE) == OK:
		return clampf(float(cf.get_value("voice_volumes", _name_key(id), 1.0)), 0.0, 1.5)
	return 1.0


func _name_key(id: int) -> String:
	return str(net.roster.get(id, {}).get("name", "id%d" % id)).md5_text()


# what they have me at, or -1 if they haven't said
func volume_they_have_me(id: int) -> float:
	return float(their_volumes.get(id, -1.0))


func is_speaking(id: int) -> bool:
	return Time.get_ticks_msec() - int(speaking.get(id, 0)) < 300


# ---- mic

func _on_state() -> void:
	if net.is_online():
		_ensure_mic()
	else:
		_stop_all()


func _ensure_mic() -> void:
	if _mic != null or not is_available():
		return
	if AudioServer.get_bus_index("Mic") < 0:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Mic")
		AudioServer.set_bus_mute(bi, true)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.3
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Mic"), _capture)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)
	_mic.play()


func _stop_all() -> void:
	for id in _players.keys():
		_players[id].queue_free()
	_players.clear()
	_pending.clear()
	their_volumes.clear()
	my_volumes.clear()
	_shared.clear()
	speaking.clear()


func _on_roster() -> void:
	for id in _players.keys():
		if not net.roster.has(id):
			_players[id].queue_free()
			_players.erase(id)
			_pending.erase(id)
			their_volumes.erase(id)
			_shared.erase(id)


func _process(delta: float) -> void:
	if net == null or not net.is_online():
		return
	_send_tick()
	_play_tick()
	_share_t += delta
	if _share_t > 1.0:
		_share_t = 0.0
		_share_volumes()


func _send_tick() -> void:
	if _capture == null:
		return
	var avail := _capture.get_frames_available()
	if avail <= 0:
		return
	var frames := _capture.get_buffer(avail)
	var live := mic_on and (talking or not push_to_talk)
	for f in frames:
		_phase += 1.0
		while _phase >= _ratio:
			_phase -= _ratio
			_acc.append(_last.lerp(f, 1.0 - _phase / _ratio))
		_last = f
	while _acc.size() >= CHUNK:
		var chunk := _acc.slice(0, CHUNK)
		_acc = _acc.slice(CHUNK)
		if not live:
			continue
		var sum := 0.0
		for i in chunk.size():
			var mono := (chunk[i].x + chunk[i].y) * 0.5
			sum += mono * mono
			chunk[i] = Vector2(mono, mono)
		var rms := sqrt(sum / chunk.size())
		_my_level = lerpf(_my_level, rms, 0.5)
		if not push_to_talk and rms < gate:
			continue
		speaking[net.my_id] = Time.get_ticks_msec()
		var packet := PackedByteArray([net.my_id])
		packet.append_array(Adpcm.encode(chunk))
		if net.is_host():
			for id in net.peer_ids():
				net.send_to(id, Net.K_VOICE, packet, false)
		else:
			net.send_to(1, Net.K_VOICE, packet, false)


func _play_tick() -> void:
	for id in _pending.keys():
		var p: AudioStreamPlayer3D = _players.get(id)
		if p == null:
			continue
		var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
		var q: Array = _pending[id]
		while pb != null and not q.is_empty():
			var fr: PackedVector2Array = q[0]
			if pb.get_frames_available() < fr.size():
				break
			q.pop_front()
			pb.push_buffer(fr)


func _player_for(id: int) -> AudioStreamPlayer3D:
	if _players.has(id):
		return _players[id]
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 0.4
	var p := AudioStreamPlayer3D.new()
	p.stream = g
	p.unit_size = 3.0
	p.max_distance = 30.0
	var v := volume_of(id)
	p.volume_db = -80.0 if v <= 0.01 else linear_to_db(v)
	var av: Node3D = avatars.avatars.get(id) if avatars != null else null
	if av != null:
		av.head.add_child(p)
	else:
		add_child(p)
	p.play()
	_players[id] = p
	_pending[id] = []
	return p


func _on_packet(from: int, kind: int, payload: PackedByteArray) -> void:
	if kind == Net.K_EVENT:
		var d = Net.read_var(payload)
		if d is Dictionary and d.get("k", "") == "voice_vol":
			# "I have <you> at v"; the host relays a guest's full table so everyone knows everyone's setting
			var who := int(d.get("who", from))
			var vols = d.get("vols", {})
			if vols is Dictionary and vols.has(net.my_id):
				their_volumes[who] = clampf(float(vols[net.my_id]), 0.0, 1.5)
			if net.is_host() and from != 1:
				for id in net.peer_ids():
					if id != from:
						net.send_var(id, Net.K_EVENT, {"k": "voice_vol", "who": from, "vols": vols})
		return
	if kind != Net.K_VOICE or payload.size() < 2:
		return
	var who := int(payload[0])
	if not net.is_host() and from != 1:
		return
	if net.is_host():
		who = from                                   # a guest can only speak as itself
		payload[0] = who
		for id in net.peer_ids():
			if id != from:
				net.send_to(id, Net.K_VOICE, payload, false)
	if who == net.my_id or not net.roster.has(who):
		return
	var frames: PackedVector2Array = Adpcm.decode(payload.slice(1))
	if frames.is_empty():
		return
	_player_for(who)
	var q: Array = _pending[who]
	while q.size() > 8:
		q.pop_front()
	q.append(frames)
	speaking[who] = Time.get_ticks_msec()
	var sum := 0.0
	for f in frames:
		sum += f.x * f.x
	levels[who] = sqrt(sum / frames.size())


func _share_volumes() -> void:
	var vols := {}
	for id in net.peer_ids():
		vols[id] = volume_of(id)
	if vols == _shared:
		return
	_shared = vols.duplicate()
	if net.is_host():
		for id in net.peer_ids():
			net.send_var(id, Net.K_EVENT, {"k": "voice_vol", "who": 1, "vols": vols})
	else:
		net.send_var(1, Net.K_EVENT, {"k": "voice_vol", "who": net.my_id, "vols": vols})
