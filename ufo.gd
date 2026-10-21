extends Node3D
## UFO (an easter egg): a flying saucer swoops in from the left, close outside the window, and stops. Its
## spin slows until a little port faces the room, the hatch slides up, and a grey alien with big black eyes
## looks in at you for a few seconds. The hatch drops, and it zooms off to the right.
## Started from the Debug window for now; in a shared room the host's saucer flies past everyone's window.

const Model := preload("res://ufo_model.gd")

const SCALE := 4.5
const Y := 1.12                     # puts the port at standing eye height
const Z := -4.9                      # just outside the glass
const FROM_X := -14.0
const STOP_X := -1.95                # the middle of a pane (not behind the centre post)
const TO_X := 22.0
const ARRIVE := 2.6
const SETTLE := 1.4                  # spin slowing down until the port faces in
const OPEN := 0.5
const LOOK := 3.5
const LEAVE := 1.3

var main: Node3D
var active := false
var count := 0
var _u: Node3D
var _hatch: Node3D
var _alien: Node3D
var _t := 0.0
var _spin := 0.0
var _hum: AudioStreamPlayer
var _whoosh: AudioStreamPlayer


func setup(m: Node3D) -> void:
	main = m
	_u = Model.build()
	_u.scale = Vector3.ONE * SCALE
	_u.visible = false
	_u.get_node("Beam").visible = false
	main.room.add_child(_u)
	_hatch = _u.get_node("Port/Hatch")
	_alien = _u.get_node("Port/Alien")
	_hum = AudioStreamPlayer.new()
	_hum.stream = _make_hum()
	_hum.volume_db = -14.0
	add_child(_hum)
	_whoosh = AudioStreamPlayer.new()
	_whoosh.stream = _make_whoosh()
	_whoosh.volume_db = -6.0
	add_child(_whoosh)
	set_process(false)


func request_visit() -> void:
	if active or main.egg_active or main.sleeping:
		return
	var ng = main.net_game
	if ng != null and ng.net.is_online() and not ng.net.is_host():
		ng.net.send_var(1, ng.Net.K_EVENT, {"k": "ufo_on"})
		return
	count += 1
	start()


func start() -> void:
	if active:
		return
	active = true
	_t = 0.0
	_spin = 0.0
	_hatch.position.y = 0.0
	_alien.visible = false
	_u.visible = true
	_hum.play()
	_whoosh.play()
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	var t := _t
	var x := STOP_X
	var spin_speed := 4.0
	var bob := sin(t * 2.2) * 0.04
	var tilt := 0.0
	var t1 := ARRIVE
	var t2 := t1 + SETTLE
	var t3 := t2 + OPEN
	var t4 := t3 + LOOK
	var t5 := t4 + OPEN
	if t < t1:
		var k := t / ARRIVE
		x = lerpf(FROM_X, STOP_X, 1.0 - pow(1.0 - k, 3.0))         # swoops in and brakes
		tilt = -0.25 * (1.0 - k)                                  # leaning into the move
	elif t < t2:
		spin_speed = 0.0                                           # the spin winds down to the port, below
	elif t < t5:
		spin_speed = 0.0
	else:
		var k := (t - t5) / LEAVE
		x = STOP_X + (TO_X - STOP_X) * k * k * k                   # and off, faster and faster
		tilt = 0.3 * minf(k * 3.0, 1.0)
		if t - delta < t5:
			_whoosh.play()
		spin_speed = 6.0
	# the spin: free while moving; between t1 and t2 it eases to a stop with the port toward the room
	if t < t1 or t >= t5:
		_spin += spin_speed * delta
	elif t < t2:
		var target := ceilf(_spin / TAU) * TAU                     # the next time the port faces +z
		_spin = lerpf(_spin, target, clampf(delta * 3.5, 0.0, 1.0))
	_u.position = Vector3(x, Y + bob, Z)
	_u.rotation = Vector3(0.0, _spin, tilt)
	Model.animate_lights(_u, t)
	# the hatch: up, the alien looks, down
	var open := 0.0
	if t >= t2 and t < t3:
		open = (t - t2) / OPEN
	elif t >= t3 and t < t4:
		open = 1.0
	elif t >= t4 and t < t5:
		open = 1.0 - (t - t4) / OPEN
	_hatch.position.y = 0.13 * smoothstep(0.0, 1.0, open)
	_alien.visible = open > 0.02
	if _alien.visible:
		# it leans in a little, tilts its head, looks at you
		_alien.rotation = Vector3(0.0, 0.2 * sin(t * 0.9), 0.18 * sin(t * 1.3))
		_alien.position.z = -0.01 + 0.008 * open
	_hum.volume_db = linear_to_db(clampf(1.0 - absf(x - STOP_X) / 18.0, 0.02, 1.0)) - 10.0
	if x > TO_X - 0.5:
		active = false
		_u.visible = false
		_hum.stop()
		set_process(false)


# ---- shared rooms

func state() -> int:
	return count


func apply_remote(n: int) -> void:
	if n > count:
		count = n
		start()


# ---- sounds, made here

static func _make_hum() -> AudioStreamWAV:
	var rate := 22050
	var n := int(2.0 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s := sin(t * TAU * 110.0) * 0.5 + sin(t * TAU * 165.0) * 0.25 + sin(t * TAU * 220.0 + sin(t * TAU * 6.0) * 2.0) * 0.2
		data.encode_s16(i * 2, int(s * 0.6 * 32767.0))
	var w := _wav(data, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


static func _make_whoosh() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.2 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 300.0 + 1400.0 * t                              # a rising sci-fi zip
		ph += f / rate
		var env := smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.7, 1.2, t))
		var s := sin(ph * TAU) * 0.5 + sin(ph * TAU * 1.5) * 0.25
		data.encode_s16(i * 2, int(s * env * 0.6 * 32767.0))
	return _wav(data, rate)


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
