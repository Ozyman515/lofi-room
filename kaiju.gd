extends Node3D
## Kaiju (an easter egg): an original giant reptile (kaiju_model.gd) lumbers down the street outside the
## window. Every footfall is a deep thump: the view jolts (on a screen; in a headset the controllers rumble
## instead, since shaking someone's view in VR makes them sick), the window rattles and the lamps flicker.
## Halfway across it stops, turns its head and looks in at you with a low rumble, then walks on.
## It comes now and then on its own (more often at night), or from the Debug window. In a shared room the
## host's kaiju walks past everybody's window.

const Model := preload("res://kaiju_model.gd")

const SCALE := 7.5                   # in the city's units: just taller than the nearest rooftops
const STREET := Vector3(0.0, -2.2, -9.5)
const FROM_X := -16.0
const TO_X := 12.0
const STEP_TIME := 1.25              # seconds per footfall
const STRIDE := 1.6                  # how far it moves each step (city units)
const PEEK_X := -1.5                 # where it stops to look in the window
const PEEK_TIME := 4.5
const CHANCE_PER_CHECK := 0.04       # checked every 10 minutes; doubled at night
const CHECK_EVERY := 600.0

var main: Node3D
var active := false
var count := 0                       # how many walks (shared rooms follow the host's count)
var _k: Node3D
var _body: Node3D
var _head: Node3D
var _jaw: Node3D
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _x := FROM_X
var _phase := 0.0                    # walk cycle, one footfall per half
var _peeked := false
var _peek_t := 0.0
var _check_t := 0.0
var _shake := 0.0
var _thump: AudioStreamPlayer
var _rattle: AudioStreamPlayer
var _rumble: AudioStreamPlayer
var _flicker_t := 0.0
var _light_base := {}
var _rng := RandomNumberGenerator.new()


func setup(m: Node3D) -> void:
	main = m
	_rng.randomize()
	_k = Model.build()
	_k.scale = Vector3.ONE * SCALE
	_k.visible = false
	main.room.add_child(_k)
	_body = _k.get_node("Body")
	_head = _body.get_node("Head")
	_jaw = _head.get_node("Jaw")
	for n in ["LegL", "LegR"]:
		var leg: Node3D = _body.get_node(n)
		_legs.append(leg)
		_knees.append(leg.get_node("Knee"))
	for n in ["ArmL", "ArmR"]:
		_arms.append(_body.get_node(n))
	_thump = _player(_make_thump(), 0.0)
	_rattle = _player(_make_rattle(), -10.0)
	_rumble = _player(_make_rumble(), -4.0)
	_check_t = _rng.randf_range(60.0, CHECK_EVERY)


func _player(s: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = db
	p.max_polyphony = 3
	add_child(p)
	return p


# ---- starting a walk

func request_walk() -> void:
	if active or main.egg_active or main.sleeping:
		return
	var ng = main.net_game
	if ng != null and ng.net.is_online() and not ng.net.is_host():
		return                       # guests see the host's kaiju only
	count += 1
	start()


func start() -> void:
	if active:
		return
	active = true
	_x = FROM_X
	_phase = 0.0
	_peeked = false
	_peek_t = 0.0
	_k.visible = true
	_pose(0.0)


func _process(delta: float) -> void:
	_camera_shake(delta)
	_flicker(delta)
	if not active:
		_check_t -= delta
		if _check_t <= 0.0:
			_check_t = CHECK_EVERY
			var h := int(Time.get_datetime_dict_from_system()["hour"])
			var night := h >= 21 or h < 5
			if _rng.randf() < CHANCE_PER_CHECK * (2.0 if night else 1.0):
				request_walk()
		return
	# the pause at the window: stand still, turn the head toward the room, rumble
	if not _peeked and _x >= PEEK_X:
		_peek_t += delta
		var k := clampf(_peek_t / 1.2, 0.0, 1.0) * (1.0 - clampf((_peek_t - (PEEK_TIME - 1.0)) / 1.0, 0.0, 1.0))
		_head.rotation = Vector3(0.0, 0.9 * k, -0.15 * k)
		_jaw.rotation.z = -0.12 * k * (0.5 + 0.5 * sin(_peek_t * 5.0))
		if _peek_t > 0.6 and not _rumble.playing and _peek_t < 1.0:
			_rumble.play()
		if _peek_t >= PEEK_TIME:
			_peeked = true
		_pose(_phase)
		return
	var before := int(_phase / PI)
	_phase += delta * PI / STEP_TIME
	_x += delta * STRIDE / STEP_TIME
	if int(_phase / PI) != before:
		_footfall()
	_pose(_phase)
	if _x > TO_X:
		active = false
		_k.visible = false


# legs swing, knees bend on the lifted leg, the body dips at each footfall, arms and tail sway
func _pose(ph: float) -> void:
	var s := sin(ph)
	_k.position = STREET + Vector3(_x, -absf(cos(ph)) * 0.04 * SCALE + 0.04 * SCALE, 0.0)
	_body.rotation.z = 0.04 * sin(ph * 2.0)
	_body.rotation.x = 0.05 * s
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var sw := s * side
		_legs[i].rotation.z = -0.38 * sw
		_knees[i].rotation.z = 0.45 * maxf(0.0, sw)                # the leg coming forward bends
		_arms[i].rotation.z = 0.2 * sw
	if _peeked or _x < PEEK_X:
		_head.rotation = Vector3(0.0, 0.08 * sin(ph * 0.5), 0.05 * sin(ph * 2.0))


func _footfall() -> void:
	var dist := Vector3(_x, 0, STREET.z).distance_to(Vector3(-1.4, 0, 0))
	var near := clampf(1.0 - (dist - 9.5) / 16.0, 0.25, 1.0)        # loudest right outside the window
	_thump.volume_db = linear_to_db(near)
	_thump.pitch_scale = _rng.randf_range(0.9, 1.05)
	_thump.play()
	_rattle.volume_db = linear_to_db(near * 0.35)
	_rattle.play()
	_shake = 0.06 * near
	_flicker_t = 0.25 * near
	if main.xr_active:
		for hand in [main.left_hand, main.right_hand]:
			if hand != null:
				hand.trigger_haptic_pulse("haptic", 40.0, 0.9 * near, 0.25, 0.0)


# a screen gets a quick jolt that settles; a headset never has its view moved
func _camera_shake(delta: float) -> void:
	var cam: Camera3D = main.desktop_cam
	if cam == null:
		return
	if _shake > 0.0 and not main.xr_active:
		_shake = move_toward(_shake, 0.0, delta * 0.18)
		cam.h_offset = _rng.randf_range(-1.0, 1.0) * _shake * 0.4
		cam.v_offset = _rng.randf_range(-1.0, 1.0) * _shake
	elif cam.h_offset != 0.0 or cam.v_offset != 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
		_shake = 0.0


func _flicker(delta: float) -> void:
	if _flicker_t <= 0.0:
		if not _light_base.is_empty():
			for l in _light_base:
				if is_instance_valid(l):
					(l as OmniLight3D).light_energy = _light_base[l]
			_light_base.clear()
		return
	_flicker_t -= delta
	if _light_base.is_empty():
		for g in main.light_groups:
			for l in g["omnis"]:
				_light_base[l] = (l as OmniLight3D).light_energy
	for l in _light_base:
		(l as OmniLight3D).light_energy = _light_base[l] * (0.35 if _rng.randf() < 0.5 else 1.0)


# ---- shared rooms

func state() -> int:
	return count


func apply_remote(n: int) -> void:
	if n > count:
		count = n
		start()


# ---- sounds, made here

static func _make_thump() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.6 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 34.0 + 60.0 * exp(-t * 9.0)                   # a deep boom that drops in pitch
		ph += f / rate
		var boom := sin(ph * TAU) * exp(-t * 3.2)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.05          # the crunch of the street under it
		var crunch := lp * 3.0 * exp(-t * 14.0)
		var s := boom * 0.9 + crunch * 0.5
		s = s / (1.0 + absf(s) * 0.4)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


static func _make_rattle() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.5 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var hp := 0.0
	var last := 0.0
	for i in n:
		var t := float(i) / rate
		var x := rng.randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + x - last)
		last = x
		var buzz := 1.0 if fmod(t * 38.0, 1.0) < 0.3 else 0.2        # the window buzzing in its frame
		data.encode_s16(i * 2, int(clampf(hp * buzz * exp(-t * 7.0) * 0.6, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


static func _make_rumble() -> AudioStreamWAV:
	var rate := 22050
	var n := int(2.6 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 52.0 + 6.0 * sin(t * 2.3)
		ph += f / rate
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		var growl := (sin(ph * TAU) + 0.5 * sin(ph * TAU * 2.0)) * (0.6 + 0.4 * sin(t * 31.0)) + lp * 1.5
		var env := smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(1.8, 2.6, t))
		var s := growl * env * 0.5
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
