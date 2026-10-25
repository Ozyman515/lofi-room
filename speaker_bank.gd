extends Node3D
## All the apartment's speakers. Each one plays one of the sources in its own room, or nothing:
##   PC            the PC's music (all of them in sync, from their own positions)
##   TV            the TV in the same room: the CRT TV (game room, with the console games), the Big TV (living
##                 room) or the Theater Screen; rooms without a TV don't offer it
##   Record player its own music, separate from the PC (living room, hallway and balcony speakers)
##   OFF           silent
## Click a speaker to step through what its room offers. TV sound drops to 15% (gradually) once you're out of
## that TV's room, so one TV turned right up doesn't drown out another.

signal finished
signal changed

const BusFeed := preload("res://bus_feed.gd")
const MODES := ["pc", "tv", "lp", "off"]
const TV_OF := {"game": "TV", "living": "TV_living", "theater": "TV_theater"}       # room -> its TV's bus
const TV_NAME := {"game": "CRT TV", "living": "Big TV", "theater": "Theater Screen"}
const LP_ROOMS := ["living", "hallway", "balcony"]                                 # the record player reaches these
const BUS_ROOM := {"TV": "game", "Console": "game", "TV_living": "living", "TV_theater": "theater"}
const AWAY := 0.15                       # a TV heard from outside its room
const FADE := 1.5                        # seconds to fade between the two

signal lp_finished

var speakers: Array = []         # [{"name", "player", "enabled", "mode", "tv", "con", "lp", "led", "room", "gain"}]  (enabled = mode is "pc")
var _tv_feed: BusFeed            # the game room TV's tapes
var _tv_feeds := {}              # bus -> BusFeed: the game room TV ("TV") and each room's own TV
var _con_feed: BusFeed           # the console games shown on the TV
var master := 0.7
var duck := 0.0                     # 0..1: the music fades down (in the noir office, which has its own)
var listener_room := ""             # the room you're in (the apartment sets it)
var _rooms_set := false
var _bus_gain := {}                 # TV bus -> 0.15..1 (its flat sound, when no speakers play it)
var _lp_ref: AudioStreamPlayer      # the record player's clock, like _ref is the PC's

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
	var lpp := AudioStreamPlayer3D.new()
	lpp.unit_size = 6.0
	lpp.max_distance = 60.0
	lpp.position = pos
	add_child(lpp)
	speakers.append({"name": spk_name, "player": p, "enabled": true, "mode": "pc", "tv": tvp, "con": conp, "lp": lpp,
		"led": led_material, "tv_bus": "TV", "room": "", "gain": 1.0})
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


func set_duck(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if absf(v - duck) < 0.02 and not (v == 0.0 and duck != 0.0) and not (v == 1.0 and duck != 1.0):
		return
	duck = v
	_apply()


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


# what a speaker can play: the PC, its room's TV and the record player where they reach, or nothing
func sources(i: int) -> Array:
	if i < 0 or i >= speakers.size():
		return []
	var room: String = speakers[i]["room"]
	if not _rooms_set:
		return MODES
	var out := ["pc"]
	if TV_OF.has(room):
		out.append("tv")
	if LP_ROOMS.has(room):
		out.append("lp")
	out.append("off")
	return out


# a source's name, as a speaker in this room calls it
func source_name(i: int, m: String) -> String:
	match m:
		"pc":
			return "PC"
		"tv":
			var room: String = speakers[i]["room"] if i >= 0 and i < speakers.size() else ""
			return TV_NAME.get(room, "TV")
		"lp":
			return "Record player"
	return "Off"


func room_of(i: int) -> String:
	return str(speakers[i]["room"]) if i >= 0 and i < speakers.size() else ""


# once the apartment is built: which room each speaker hangs in (so which TV it plays), and any mode its room
# doesn't offer goes back to the PC
func assign_rooms(room_at: Callable) -> void:
	for s in speakers:
		var pos: Vector3 = (s["player"] as Node3D).global_position
		s["room"] = str(room_at.call(pos))
		s["tv_bus"] = TV_OF.get(s["room"], "TV")
		(s["tv"] as AudioStreamPlayer3D).stop()
	_rooms_set = true
	for i in speakers.size():
		if not sources(i).has(get_mode(i)):
			_switch(i, "pc")
	_refresh_feeds()
	_apply()
	changed.emit()


# PC -> (TV) -> (Record player) -> OFF -> PC, through what this speaker's room offers
func cycle(i: int) -> void:
	var src := sources(i)
	set_mode(i, src[(src.find(get_mode(i)) + 1) % src.size()])


# which TV a speaker set to TV plays: "TV" (the game room's) or a room TV's own bus
func set_tv_bus(i: int, b: String) -> void:
	if i < 0 or i >= speakers.size() or str(speakers[i]["tv_bus"]) == b:
		return
	(speakers[i]["tv"] as AudioStreamPlayer3D).stop()
	speakers[i]["tv_bus"] = b
	_refresh_feeds()


func set_mode(i: int, m: String) -> void:
	if i < 0 or i >= speakers.size() or not sources(i).has(m):
		return
	_switch(i, m)
	_refresh_feeds()
	_apply()
	changed.emit()


# every speaker that can play it (the TV: each its own room's)
func set_all_mode(m: String) -> void:
	if not MODES.has(m):
		return
	for i in speakers.size():
		if sources(i).has(m):
			_switch(i, m)
	_refresh_feeds()
	_apply()
	changed.emit()


func _switch(i: int, m: String) -> void:
	speakers[i]["mode"] = m
	_set_one(i, m == "pc")
	var lpp: AudioStreamPlayer3D = speakers[i]["lp"]
	if m == "lp":
		if _lp_ref != null and _lp_ref.playing and not lpp.playing:
			lpp.stream = _lp_ref.stream
			lpp.play(_lp_ref.get_playback_position())
	else:
		lpp.stop()


func _ensure_feeds() -> void:
	if _tv_feed != null:
		return
	_tv_feed = BusFeed.new()
	add_child(_tv_feed)
	_tv_feed.setup("TV")
	_tv_feeds["TV"] = _tv_feed
	_con_feed = BusFeed.new()
	add_child(_con_feed)
	_con_feed.setup("Console")


# the speakers set to TV take the TV's sound (and the TV's own placeless sound goes quiet while any do)
func _refresh_feeds() -> void:
	_ensure_feeds()
	var tvs := {}
	for b in _tv_feeds:
		tvs[b] = [] as Array[AudioStreamPlayer3D]
	var cons: Array[AudioStreamPlayer3D] = []
	for s in speakers:
		if s["mode"] == "tv":
			var b: String = s["tv_bus"]
			if not tvs.has(b):
				tvs[b] = [] as Array[AudioStreamPlayer3D]
			(tvs[b] as Array[AudioStreamPlayer3D]).append(s["tv"])
			if b == "TV":
				cons.append(s["con"])           # (console games are on the game room TV)
	for b in tvs:
		if not _tv_feeds.has(b):
			var f := BusFeed.new()
			add_child(f)
			f.setup(b)
			_tv_feeds[b] = f
		(_tv_feeds[b] as BusFeed).set_targets(tvs[b])
	_con_feed.set_targets(cons)


func _apply() -> void:
	var n := 0
	var nlp := 0
	var ntv := {}
	for s in speakers:
		if s["enabled"]:
			n += 1
		if s["mode"] == "lp":
			nlp += 1
		if s["mode"] == "tv":
			ntv[s["tv_bus"]] = int(ntv.get(s["tv_bus"], 0)) + 1
	var lp_db := linear_to_db(maxf(master * (1.0 - 0.85 * duck), 0.0001)) - 3.0 * log(float(maxi(nlp, 1))) / log(2.0)
	# more speakers on = each one a bit quieter so the total level stays about the same
	var share_db := -3.0 * log(float(maxi(n, 1))) / log(2.0)
	for s in speakers:
		var p: AudioStreamPlayer3D = s["player"]
		p.volume_db = (linear_to_db(maxf(master * (1.0 - 0.85 * duck), 0.0001)) + share_db) if s["enabled"] else -80.0
		var tv_share := -3.0 * log(float(maxi(int(ntv.get(s["tv_bus"], 1)), 1))) / log(2.0)
		for k in ["tv", "con"]:
			(s[k] as AudioStreamPlayer3D).volume_db = (tv_share + linear_to_db(float(s["gain"]))) if s["mode"] == "tv" else -80.0
		(s["lp"] as AudioStreamPlayer3D).volume_db = lp_db if s["mode"] == "lp" else -80.0
		var led: StandardMaterial3D = s["led"]
		if led != null:
			var c: Color = {"pc": Color(0.2, 1.0, 0.4), "tv": Color(0.25, 0.6, 1.0), "lp": Color(1.0, 0.6, 0.15)}.get(s["mode"], Color(0.6, 0.05, 0.05))
			var lit: bool = s["mode"] != "off"
			led.albedo_color = c if lit else Color(0.35, 0.05, 0.05)
			led.emission_enabled = true
			led.emission = c
			led.emission_energy_multiplier = 3.0 if lit else 0.6


# ---- the room drop: a TV's sound fades to 15% once you're out of its room (its speakers, and its own flat sound
# when no speakers play it), and back up when you come in

func _process(delta: float) -> void:
	if not _rooms_set:
		return
	var step := delta * (1.0 - AWAY) / FADE
	var moved := false
	for s in speakers:
		var want := 1.0 if listener_room == "" or s["room"] == listener_room else AWAY
		var g: float = s["gain"]
		if g != want:
			s["gain"] = move_toward(g, want, step)
			moved = moved or s["mode"] == "tv"
	if moved:
		_apply()
	for b in BUS_ROOM:
		var bi := AudioServer.get_bus_index(b)
		if bi < 0:
			continue
		var want := 1.0 if listener_room == "" or BUS_ROOM[b] == listener_room else AWAY
		var g: float = _bus_gain.get(b, 1.0)
		if g != want or not _bus_gain.has(b):
			g = move_toward(g, want, step)
			_bus_gain[b] = g
			AudioServer.set_bus_volume_db(bi, linear_to_db(g))


# ---- the record player: its own music, out of the speakers set to it (its clock runs on the muted bus too)

func _ensure_lp() -> void:
	if _lp_ref != null:
		return
	_ensure_ref()
	_lp_ref = AudioStreamPlayer.new()
	_lp_ref.bus = "SpeakerClock"
	_lp_ref.finished.connect(func() -> void:
		for s in speakers:
			(s["lp"] as AudioStreamPlayer3D).stop()
		lp_finished.emit())
	add_child(_lp_ref)


func lp_play(st: AudioStream) -> void:
	_ensure_lp()
	_lp_ref.stream = st
	_lp_ref.play()
	for s in speakers:
		var lpp: AudioStreamPlayer3D = s["lp"]
		lpp.stop()
		lpp.stream = st
		if s["mode"] == "lp":
			lpp.play()
	_apply()
	changed.emit()


func lp_stop() -> void:
	if _lp_ref == null:
		return
	_lp_ref.stop()
	for s in speakers:
		(s["lp"] as AudioStreamPlayer3D).stop()
	changed.emit()


func lp_playing() -> bool:
	return _lp_ref != null and _lp_ref.playing


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
