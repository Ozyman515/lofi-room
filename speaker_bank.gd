extends Node3D
## All the room's speakers (2 on the desk, several on the walls). Each one is set to PC, TV or OFF:
## on PC it plays the PC's music (all of them in sync, from their own positions), on TV it plays the TV's
## sound (tapes and the console games on it), and OFF is silent. Click a speaker to go PC -> TV -> OFF.

signal finished
signal changed

const BusFeed := preload("res://bus_feed.gd")
const MODES := ["pc", "tv", "off"]

var speakers: Array = []         # [{"name", "player", "enabled", "mode", "tv", "con", "led"}]  (enabled = mode is "pc")
var _tv_feed: BusFeed            # the TV's tapes
var _con_feed: BusFeed           # the console games shown on the TV
var master := 0.7

# A silent "clock" player runs the song all the time (on a muted bus) so a speaker that was switched
# off, and so fully stopped, can jump back in at the right point when it is switched on again.
var _ref: AudioStreamPlayer
var _paused := false

var stream: AudioStream:
	set(v):
		_ensure_ref()
		_ref.stream = v
		if _live:
			return                           # a guest's own songs wait until the host's feed stops
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
	_ensure_feeds()
	p.stream = _ref.stream
	var tvp := BusFeed.make_player()
	tvp.position = pos
	add_child(tvp)
	var conp := BusFeed.make_player()
	conp.position = pos
	add_child(conp)
	speakers.append({"name": spk_name, "player": p, "enabled": true, "mode": "pc", "tv": tvp, "con": conp, "led": led_material})
	if _ref.playing:
		p.play(_ref.get_playback_position())
		p.stream_paused = _paused
	_apply()
	return speakers.size() - 1


func play() -> void:
	_ensure_ref()
	_ref.play()
	if _live:
		return
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
	elif _live:
		p.play()                              # the live feed: it fills up from the next packet
		_live_pbs[i] = p.get_stream_playback()
	elif _ref != null and _ref.playing:
		p.play(_ref.get_playback_position())   # join in at the right point
		p.stream_paused = _paused


func set_enabled(i: int, on: bool) -> void:
	set_mode(i, "pc" if on else "off")


func set_all_enabled(on: bool) -> void:
	set_all_mode("pc" if on else "off")


func toggle(i: int) -> void:
	cycle(i)


func get_mode(i: int) -> String:
	return str(speakers[i]["mode"]) if i >= 0 and i < speakers.size() else "off"


# PC -> TV -> OFF -> PC
func cycle(i: int) -> void:
	set_mode(i, MODES[(MODES.find(get_mode(i)) + 1) % MODES.size()])


func set_mode(i: int, m: String) -> void:
	if i < 0 or i >= speakers.size() or not MODES.has(m):
		return
	speakers[i]["mode"] = m
	_set_one(i, m == "pc")
	_refresh_feeds()
	_apply()
	changed.emit()


func set_all_mode(m: String) -> void:
	if not MODES.has(m):
		return
	for i in speakers.size():
		speakers[i]["mode"] = m
		_set_one(i, m == "pc")
	_refresh_feeds()
	_apply()
	changed.emit()


func _ensure_feeds() -> void:
	if _tv_feed != null:
		return
	_tv_feed = BusFeed.new()
	add_child(_tv_feed)
	_tv_feed.setup("TV")
	_con_feed = BusFeed.new()
	add_child(_con_feed)
	_con_feed.setup("Console")


# the speakers set to TV take the TV's sound (and the TV's own placeless sound goes quiet while any do)
func _refresh_feeds() -> void:
	_ensure_feeds()
	var tvs: Array[AudioStreamPlayer3D] = []
	var cons: Array[AudioStreamPlayer3D] = []
	for s in speakers:
		if s["mode"] == "tv":
			tvs.append(s["tv"])
			cons.append(s["con"])
	_tv_feed.set_targets(tvs)
	_con_feed.set_targets(cons)


func _apply() -> void:
	var n := 0
	var ntv := 0
	for s in speakers:
		if s["enabled"]:
			n += 1
		if s["mode"] == "tv":
			ntv += 1
	var tv_share := -3.0 * log(float(maxi(ntv, 1))) / log(2.0)
	# more speakers on = each one a bit quieter so the total level stays about the same
	var share_db := -3.0 * log(float(maxi(n, 1))) / log(2.0)
	for s in speakers:
		var p: AudioStreamPlayer3D = s["player"]
		p.volume_db = (linear_to_db(maxf(master, 0.0001)) + share_db) if s["enabled"] else -80.0
		for k in ["tv", "con"]:
			(s[k] as AudioStreamPlayer3D).volume_db = tv_share if s["mode"] == "tv" else -80.0
		var led: StandardMaterial3D = s["led"]
		if led != null:
			var c: Color = {"pc": Color(0.2, 1.0, 0.4), "tv": Color(0.25, 0.6, 1.0)}.get(s["mode"], Color(0.6, 0.05, 0.05))
			var lit: bool = s["mode"] != "off"
			led.albedo_color = c if lit else Color(0.35, 0.05, 0.05)
			led.emission_enabled = true
			led.emission = c
			led.emission_energy_multiplier = 3.0 if lit else 0.6


# ---- live feed (music streamed from the host): every enabled speaker gets its own generator and the
# same frames are pushed into each, so the sound still comes from the speakers' places in the room.
var _live := false
var _live_pbs: Array = []


func live_start(rate: float) -> void:
	_ensure_ref()
	_ref.stop()
	_live = true
	_live_pbs.clear()
	for s in speakers:
		var p: AudioStreamPlayer3D = s["player"]
		p.stop()
		var g := AudioStreamGenerator.new()
		g.mix_rate = rate
		g.buffer_length = 0.6
		p.stream = g
		p.stream_paused = false
		if s["enabled"]:
			p.play()
		_live_pbs.append(p.get_stream_playback())
	_apply()
	changed.emit()


func live_push(frames: PackedVector2Array) -> bool:
	if not _live:
		return false
	var room := 1 << 30
	for pb in _live_pbs:
		if pb != null:
			room = mini(room, (pb as AudioStreamGeneratorPlayback).get_frames_available())
	if room < frames.size():
		return false
	for pb in _live_pbs:
		if pb != null:
			(pb as AudioStreamGeneratorPlayback).push_buffer(frames)
	return true


func live_stop() -> void:
	if not _live:
		return
	_live = false
	_live_pbs.clear()
	for s in speakers:
		var p: AudioStreamPlayer3D = s["player"]
		p.stop()
		p.stream = _ref.stream
	changed.emit()


func is_live() -> bool:
	return _live
