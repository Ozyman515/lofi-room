extends Node3D
## All the room's speakers (2 on the desk, several on the walls). They play the same sound from
## their own positions. Switching one off silences it (it keeps running muted so they stay in sync).

signal finished
signal changed

var speakers: Array = []         # [{"name", "player", "enabled", "led"}]
var master := 0.7

# A silent "clock" player runs the song all the time (on a muted bus) so a speaker that was switched
# off, and so fully stopped, can jump back in at the right point when it is switched on again.
var _ref: AudioStreamPlayer
var _paused := false

var stream: AudioStream:
	set(v):
		_ensure_ref()
		_ref.stream = v
		for s in speakers:
			(s["player"] as AudioStreamPlayer3D).stream = v
	get:
		return null if _ref == null else _ref.stream

var stream_paused: bool:
	set(v):
		_ensure_ref()
		_paused = v
		_ref.stream_paused = v
		for s in speakers:
			(s["player"] as AudioStreamPlayer3D).stream_paused = v
	get:
		return _paused

var playing: bool:
	get:
		return _ref != null and _ref.playing


func _ensure_ref() -> void:
	if _ref != null:
		return
	if AudioServer.get_bus_index("SpeakerClock") < 0:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "SpeakerClock")
		AudioServer.set_bus_mute(bi, true)
	_ref = AudioStreamPlayer.new()
	_ref.bus = "SpeakerClock"
	_ref.finished.connect(func() -> void: finished.emit())
	add_child(_ref)


func add_speaker(spk_name: String, pos: Vector3, led_material: StandardMaterial3D) -> int:
	var p := AudioStreamPlayer3D.new()
	p.unit_size = 6.0
	p.max_distance = 60.0
	p.position = pos
	add_child(p)
	_ensure_ref()
	p.stream = _ref.stream
	speakers.append({"name": spk_name, "player": p, "enabled": true, "led": led_material})
	if _ref.playing:
		p.play(_ref.get_playback_position())
		p.stream_paused = _paused
	_apply()
	return speakers.size() - 1


func play() -> void:
	_ensure_ref()
	_ref.play()
	for s in speakers:
		if s["enabled"]:
			(s["player"] as AudioStreamPlayer3D).play()


func stop() -> void:
	_ensure_ref()
	_ref.stop()
	for s in speakers:
		(s["player"] as AudioStreamPlayer3D).stop()


func seek(t: float) -> void:
	_ensure_ref()
	_ref.seek(t)
	for s in speakers:
		var p: AudioStreamPlayer3D = s["player"]
		if p.playing:
			p.seek(t)


func get_playback_position() -> float:
	return 0.0 if _ref == null else _ref.get_playback_position()


func set_master(v: float) -> void:
	master = clampf(v, 0.0, 1.0)
	_apply()


func is_enabled(i: int) -> bool:
	return i >= 0 and i < speakers.size() and bool(speakers[i]["enabled"])


func _set_one(i: int, on: bool) -> void:
	if bool(speakers[i]["enabled"]) == on:
		return
	speakers[i]["enabled"] = on
	var p: AudioStreamPlayer3D = speakers[i]["player"]
	if not on:
		p.stop()                              # fully silent, not just turned down
	elif _ref != null and _ref.playing:
		p.play(_ref.get_playback_position())   # join in at the right point
		p.stream_paused = _paused


func set_enabled(i: int, on: bool) -> void:
	if i < 0 or i >= speakers.size():
		return
	_set_one(i, on)
	_apply()
	changed.emit()


func set_all_enabled(on: bool) -> void:
	for i in speakers.size():
		_set_one(i, on)
	_apply()
	changed.emit()


func toggle(i: int) -> void:
	set_enabled(i, not is_enabled(i))


func _apply() -> void:
	var n := 0
	for s in speakers:
		if s["enabled"]:
			n += 1
	# more speakers on = each one a bit quieter so the total level stays about the same
	var share_db := -3.0 * log(float(maxi(n, 1))) / log(2.0)
	for s in speakers:
		var p: AudioStreamPlayer3D = s["player"]
		p.volume_db = (linear_to_db(maxf(master, 0.0001)) + share_db) if s["enabled"] else -80.0
		var led: StandardMaterial3D = s["led"]
		if led != null:
			var on: bool = s["enabled"]
			led.albedo_color = Color(0.2, 1.0, 0.4) if on else Color(0.35, 0.05, 0.05)
			led.emission_enabled = true
			led.emission = Color(0.2, 1.0, 0.4) if on else Color(0.6, 0.05, 0.05)
			led.emission_energy_multiplier = 3.0 if on else 0.6
