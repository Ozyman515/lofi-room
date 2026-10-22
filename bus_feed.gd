extends Node
## Plays whatever is on one audio bus again from places in the room. A capture on the bus collects the sound;
## every frame it is pushed into a generator stream on each target speaker (3D, so it comes from where that
## speaker hangs). While there are targets, the bus's own (flat, placeless) output is sent to a muted bus so you
## only hear it from the speakers; with no targets it plays straight out as before.
## Used for the TV (and the console games on it) going out of the speakers set to TV, and for the arcade's grill.

const SINK := "FeedSink"

var bus_name := ""
var targets: Array[AudioStreamPlayer3D] = []
var _cap: AudioEffectCapture


static func ensure_bus(n: String, muted := false) -> int:
	var bi := AudioServer.get_bus_index(n)
	if bi < 0:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, n)
		AudioServer.set_bus_mute(bi, muted)
	return bi


func setup(bus: String) -> void:
	bus_name = bus
	ensure_bus(SINK, true)
	ensure_bus(bus)
	var bi := AudioServer.get_bus_index(bus)
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 0.3
	AudioServer.add_bus_effect(bi, _cap, 0)        # first on the bus, so nothing after it can change what we hear
	_apply_route()


# a speaker-shaped generator player for this feed (the caller places it)
static func make_player(unit := 6.0) -> AudioStreamPlayer3D:
	var g := AudioStreamGenerator.new()
	g.mix_rate = AudioServer.get_mix_rate()
	g.buffer_length = 0.25
	var p := AudioStreamPlayer3D.new()
	p.stream = g
	p.unit_size = unit
	p.max_distance = 60.0
	return p


func set_targets(list: Array[AudioStreamPlayer3D]) -> void:
	for p in targets:
		if not list.has(p) and is_instance_valid(p):
			p.stop()
	targets = list
	_apply_route()


func _apply_route() -> void:
	var bi := AudioServer.get_bus_index(bus_name)
	if bi >= 0:
		AudioServer.set_bus_send(bi, SINK if not targets.is_empty() else "Master")


func _process(_delta: float) -> void:
	if _cap == null:
		return
	var n := _cap.get_frames_available()
	if n <= 0:
		return
	var fr := _cap.get_buffer(n)
	for p in targets:
		if not is_instance_valid(p) or not p.is_inside_tree():
			continue
		if not p.playing:
			p.play()
		var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
		if pb == null:
			continue
		var room := pb.get_frames_available()
		if room >= fr.size():
			pb.push_buffer(fr)
		elif room > 0:
			pb.push_buffer(fr.slice(fr.size() - room))   # (full: keep only the newest, so it never lags far behind)
