extends Node3D
## Kaiju vs King Gaboon (an easter egg): the white T-Rex and King Gaboon meet far out in the city and fight
## behind the rooftops for two and a half to five minutes, while little news and police helicopters circle
## them with searchlights. They size each other up, roar, then trade blows: grapples, bites, punches, tail
## swipes, tackles and throws (the one knocked down sinks behind the buildings in a cloud of dust and climbs
## back up). Every fight is different. It ends one of three ways: the T-Rex freezes King Gaboon with an ice
## beam, King Gaboon hurls a fireball, or (now and then) they knock each other back and both limp off.
## It starts when you play with both figures on the bookshelf, one after the other, within PAIR_WINDOW
## seconds (or from the Debug window). Best seen from the window: they are out past the last row of towers.
## Effects are shader-made meshes, not particles: a glowing card for flashes, a few soft puffs for dust, a
## streaked cylinder for the beam and a swirling sphere for the fireball. The headset skips the searchlights
## and the impact lights (Plat.low_power).
## In a shared room the host's fight plays for everyone: the fight's number and its random seed travel in
## the room state, so every copy plays the same fight.

const KModel := preload("res://kaiju_model.gd")
const GModel := preload("res://gaboon_model.gd")
const KaijuScript := preload("res://kaiju.gd")
const GaboonScript := preload("res://gaboon.gd")
const Plat := preload("res://platform.gd")

const S := 60.0                      # both stand about 60 units tall: heads and shoulders over the far rooftops,
                                     # below the blinds at the top of the window
const GROUND := -2.0                 # their feet, hidden behind the towers
const Z := -64.0                     # just behind the last row of towers
const CX := -3.0                     # where they meet, across from the window
const FACE := 0.75                   # how far apart (in S) they square up
const CONTACT := 0.42                # how close (in S) their middles get when they grapple
const PAIR_WINDOW := 20.0            # seconds between playing with the two figures
const HELIS := 5

var main: Node3D
var active := false
var count := 0
var fight_seed := 0
var winner := ""                     # "k" (the T-Rex), "g" (King Gaboon) or "draw"
var _built := false
var _rng := RandomNumberGenerator.new()
var _beats: Array = []
var _bi := 0
var _bt := 0.0
var _T := 0.0
var _last_toy := {}

# the two of them: holder (place and facing) > tilt (falls) > model
var _kh: Node3D
var _kt: Node3D
var _kp := {}
var _gh: Node3D
var _gt: Node3D
var _gp := {}
var _k_over: ShaderMaterial          # scorch / frost overlays
var _g_over: ShaderMaterial
var _ice_mat: StandardMaterial3D     # the T-Rex's crest glows brighter as the beam charges
var _ice_glow_base := 0.6
var kx := 0.0
var gx := 0.0
var _k0 := 0.0
var _g0 := 0.0
var _kph := 0.0
var _gph := 0.0
var K := {}                          # this frame's pose for the T-Rex
var G := {}                          # ... and for King Gaboon

# effects
var _fx_shader: Shader
var _flashes: Array = []             # [mesh, light, t, life, size]
var _puffs: Array = []               # [mesh, t, life, vel, grow]
var _beam: Node3D
var _beam_core: MeshInstance3D
var _beam_mat: ShaderMaterial
var _crystals: Array[MeshInstance3D] = []
var _fireball: MeshInstance3D
var _fire_mat: ShaderMaterial
var _boom: MeshInstance3D
var _boom_mat: ShaderMaterial
var _boom_t := -1.0
var _charge: MeshInstance3D          # the glow gathering in King Gaboon's hands / the T-Rex's jaws
var _helis: Array = []
var _key: OmniLight3D
var _fill: OmniLight3D

# sounds
var _thump: AudioStreamPlayer
var _kroar: AudioStreamPlayer
var _groar: AudioStreamPlayer
var _gbeat: AudioStreamPlayer
var _zap: AudioStreamPlayer
var _whoosh: AudioStreamPlayer
var _later: Array = []               # [time, player, pitch]: sound arrives a beat after the light


func setup(m: Node3D) -> void:
	main = m
	set_process(false)


# ---- starting

# called by each figure on the bookshelf when you play with it; both within PAIR_WINDOW starts a fight
func toy_played(which: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	_last_toy[which] = now
	var other := "gaboon" if which == "kaiju" else "kaiju"
	if active or not _last_toy.has(other) or now - float(_last_toy[other]) > PAIR_WINDOW:
		return false
	_last_toy.clear()
	return request_fight()


func request_fight() -> bool:
	if active or main.egg_active or main.sleeping:
		return false
	if (main.kaiju != null and main.kaiju.active) or (main.gaboon != null and main.gaboon.active):
		return false
	var ng = main.net_game
	if ng != null and ng.net.is_online() and not ng.net.is_host():
		ng.net.send_var(1, ng.Net.K_EVENT, {"k": "fight_on"})        # the host's city: ask the host
		return true
	count += 1
	fight_seed = randi() % 100000
	start()
	return true


func start() -> void:
	if active:
		return
	if not _built:
		_build()
	active = true
	_rng.seed = hash(fight_seed * 7919 + 13)
	_plan()
	_bi = 0
	_bt = 0.0
	_T = 0.0
	kx = CX - 2.3 * S
	gx = CX + 2.3 * S
	_k0 = kx
	_g0 = gx
	_kh.visible = true
	_gh.visible = true
	_key.visible = true
	_fill.visible = true
	_kh.rotation.y = 0.0
	_gh.rotation.y = PI
	_kt.rotation = Vector3.ZERO
	_gt.rotation = Vector3.ZERO
	_over_k(0.0)
	_over_g(0.0)
	for i in _helis.size():
		_helis[i]["t"] = -6.0 * i - 4.0                    # they arrive one after another
		(_helis[i]["node"] as Node3D).visible = false
	set_process(true)
	if main.updater != null:
		main.updater.show_toast("The whole city is shaking... look out the window.", 6.0)
	_kroar.volume_db = -14.0
	_kroar.play()


func _end() -> void:
	active = false
	_kh.visible = false
	_gh.visible = false
	_key.visible = false
	_fill.visible = false
	_beam.visible = false
	_fireball.visible = false
	_boom.visible = false
	_charge.visible = false
	for c in _crystals:
		c.visible = false
	for h in _helis:
		(h["node"] as Node3D).visible = false
		(h["sound"] as AudioStreamPlayer3D).stop()
	for f in _flashes:
		(f[0] as Node3D).visible = false
		if f[1] != null:
			(f[1] as Light3D).visible = false
	for p in _puffs:
		(p[0] as Node3D).visible = false
	_ice_mat.emission_energy_multiplier = _ice_glow_base
	set_process(false)


# ---- the fight, planned from its seed

func _plan() -> void:
	_beats = [{"n": "enter", "d": 26.0}, {"n": "faceoff", "d": 9.0}]
	var moves := ["grapple", "bite", "punch", "tail", "tackle", "slam", "circle", "roars", "grapple", "bite", "punch"]
	# rounds until the fight fills its time: two and a half to four and a half minutes in all (the opening and
	# the finish take about 70 s of that)
	var target := _rng.randf_range(110.0, 270.0) - 70.0
	var used := 35.0
	var last := ""
	while used < target:
		var mv: String = moves[_rng.randi() % moves.size()]
		while mv == last:
			mv = moves[_rng.randi() % moves.size()]
		last = mv
		if mv in ["grapple", "bite", "punch", "tail", "tackle", "slam"]:
			_beats.append({"n": "close", "d": 3.0})
			used += 3.0
		var mt := _move_time(mv)
		_beats.append({"n": mv, "d": mt})
		used += mt
	var r := _rng.randf()
	winner = "k" if r < 0.43 else ("g" if r < 0.86 else "draw")
	_beats.append({"n": "circle", "d": 6.0})
	match winner:
		"k":
			_beats.append_array([{"n": "ice_beam", "d": 9.0}, {"n": "g_retreat", "d": 24.0}, {"n": "k_victory", "d": 7.0}, {"n": "k_exit", "d": 30.0}])
		"g":
			_beats.append_array([{"n": "fireball", "d": 9.0}, {"n": "k_retreat", "d": 24.0}, {"n": "g_victory", "d": 8.0}, {"n": "g_exit", "d": 30.0}])
		_:
			_beats.append_array([{"n": "close", "d": 3.0}, {"n": "clash", "d": 7.0}, {"n": "both_exit", "d": 30.0}])


func _move_time(mv: String) -> float:
	match mv:
		"grapple": return _rng.randf_range(7.0, 10.0)
		"bite": return 5.0
		"punch": return 5.5
		"tail": return 6.0
		"tackle": return 9.0
		"slam": return 9.0
		"circle": return _rng.randf_range(5.0, 8.0)
		"roars": return 7.0
	return 5.0


func _process(delta: float) -> void:
	if not active:
		return
	if main.sleeping:
		_end()
		return
	_T += delta
	var was := _bt
	_bt += delta
	_reset_pose()
	var b: Dictionary = _beats[_bi]
	_beat(str(b["n"]), _bt, was, float(b["d"]), delta)
	_apply_k()
	_apply_g()
	_helis_tick(delta)
	_fx_tick(delta)
	_sounds_tick()
	if _bt >= float(b["d"]):
		_bi += 1
		_bt = 0.0
		_k0 = kx
		_g0 = gx
		if _bi >= _beats.size():
			_end()


static func _at(t: float, was: float, mark: float) -> bool:
	return was < mark and t >= mark


static func _rise(t: float, a: float, b: float) -> float:
	return smoothstep(a, b, t)


static func _pulse(t: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, t) * (1.0 - smoothstep(c, d, t))


# one beat of the fight at time t (was = t a frame ago, d = its length)
func _beat(n: String, t: float, was: float, d: float, delta: float) -> void:
	var face_k := CX - FACE * S
	var face_g := CX + FACE * S
	var touch_k := CX - CONTACT * S
	var touch_g := CX + CONTACT * S
	match n:
		"enter":
			var u := clampf(t / d, 0.0, 1.0)
			kx = lerpf(_k0, face_k, u)
			gx = lerpf(_g0, face_g, u)
			_walk(delta, 1.0, 1.0, 1.75, 1.3)
			G["rear"] = 0.0
			if _at(t, was, 12.0):
				_play(_groar, -12.0, 1.0)
		"faceoff":
			K["roar"] = _pulse(t, 0.2, 0.8, 3.0, 3.8)
			if _at(t, was, 0.4):
				_play(_kroar, -3.0, 0.85)
			G["rear"] = _rise(t, 3.6, 4.4)
			G["beat"] = _pulse(t, 4.4, 4.6, 5.8, 6.0)
			G["roar"] = _pulse(t, 6.0, 6.4, 8.2, 8.8)
			if _at(t, was, 4.45):
				_play(_gbeat, -2.0, 0.9)
			if _at(t, was, 6.0):
				_play(_groar, 0.0, 0.9)
		"close":
			var u := smoothstep(0.0, 1.0, t / d)
			kx = lerpf(_k0, touch_k - 0.05 * S, u)
			gx = lerpf(_g0, touch_g + 0.05 * S, u)
			_walk(delta, 1.0, 1.0, 1.0, 1.0)
		"grapple":
			var push := sin(t * 1.25) * 0.07 * S
			kx = touch_k + push
			gx = touch_g + push
			K["arms"] = 1.0
			K["lunge"] = 0.35 + 0.25 * sin(t * 1.25)
			G["grab"] = 1.0
			K["bite"] = 0.4 * _pulse(fmod(t, 3.0), 0.3, 0.8, 1.5, 2.2)
			G["roar"] = 0.5 * _pulse(fmod(t + 1.5, 3.0), 0.3, 0.8, 1.5, 2.2)
			if int(was / 1.6) != int(t / 1.6):
				_impact(Vector3(CX + push, 0.62 * S + GROUND, Z), 0.35, Color(1.0, 0.9, 0.75))
			if _at(t, was, 0.8):
				_play(_kroar, -6.0, 0.95)
			if t > d - 1.2:                                   # shove apart
				var u := _rise(t, d - 1.2, d)
				kx = lerpf(kx, CX - 0.62 * S, u)
				gx = lerpf(gx, CX + 0.62 * S, u)
		"bite":
			K["lunge"] = _pulse(t, 0.2, 0.8, 2.2, 3.2)
			K["bite"] = _pulse(t, 0.3, 0.7, 0.9, 1.0) + 0.6 * _pulse(t, 1.0, 1.1, 1.8, 2.4)
			kx = _k0 + 0.12 * S * K["lunge"]
			if _at(t, was, 0.95):
				_impact(Vector3(gx - 0.32 * S, 0.66 * S + GROUND, Z), 0.8, Color(1.0, 0.85, 0.7))
				_play(_groar, -2.0, 1.15)
			G["recoil"] = _pulse(t, 0.95, 1.2, 2.6, 3.6)
			G["snap"] = -0.8 * G["recoil"]
			gx = _g0 + 0.1 * S * _rise(t, 0.95, 2.0)
		"punch":
			gx = _g0 - 0.1 * S * _rise(t, 0.0, 0.7)
			G["punch_r"] = _pulse(t, 0.5, 0.8, 1.0, 1.4)
			G["punch_l"] = _pulse(t, 1.4, 1.7, 1.9, 2.4)
			if _at(t, was, 0.8) or _at(t, was, 1.7):
				_impact(Vector3(kx + 0.42 * S, 0.8 * S + GROUND, Z), 0.7, Color(1.0, 0.9, 0.7))
			var hit := _pulse(t, 0.8, 1.0, 1.4, 2.0) + _pulse(t, 1.7, 1.9, 2.4, 3.2)
			K["snap"] = -0.9 * _pulse(t, 0.8, 1.0, 1.4, 2.0) + 0.9 * _pulse(t, 1.7, 1.9, 2.4, 3.2)
			K["tilt"] = 0.18 * hit
			kx = _k0 - 0.12 * S * _rise(t, 0.8, 3.0)
			if _at(t, was, 3.4):
				_play(_kroar, -5.0, 1.1)
		"tail":
			var spin := _rise(t, 0.4, 2.0)
			K["yaw"] = spin * TAU
			if _at(t, was, 1.2):
				_impact(Vector3(gx - 0.35 * S, 0.4 * S + GROUND, Z), 0.9, Color(0.85, 0.95, 1.0))
				_play(_groar, -3.0, 1.2)
			G["tilt"] = 0.35 * _pulse(t, 1.2, 1.6, 2.6, 4.0)
			G["recoil"] = _pulse(t, 1.2, 1.5, 3.0, 4.0)
			gx = _g0 + 0.16 * S * _rise(t, 1.2, 2.4)
		"tackle":
			kx = lerpf(_k0, touch_k + 0.1 * S, _rise(t, 0.0, 1.0))
			K["lunge"] = _pulse(t, 0.0, 0.8, 1.6, 2.4)
			_walk(delta, 2.0 * (1.0 - _rise(t, 0.9, 1.1)), 0.0, 1.0, 1.0)
			if _at(t, was, 1.0):
				_impact(Vector3(CX, 0.55 * S + GROUND, Z), 1.0, Color(1.0, 0.9, 0.75))
				_play(_groar, 0.0, 1.25)
			_fall_g(t, 1.0, 4.4, 7.2)
			if _at(t, was, 2.0):
				_dust(Vector3(gx + 0.3 * S, GROUND, Z), 1.0)
				_jolt_later(0.6, 0.9)
			K["roar"] = _pulse(t, 2.4, 2.9, 4.4, 5.0)
			if _at(t, was, 2.5):
				_play(_kroar, -1.0, 0.8)
		"slam":
			gx = lerpf(_g0, touch_g - 0.05 * S, _rise(t, 0.0, 1.0))
			G["grab"] = _pulse(t, 0.4, 1.0, 1.6, 2.0)
			G["rear"] = 1.0 + 0.2 * _pulse(t, 0.6, 1.2, 1.6, 2.0)
			if _at(t, was, 1.7):
				_impact(Vector3(kx + 0.3 * S, 0.7 * S + GROUND, Z), 1.0, Color(1.0, 0.9, 0.75))
				_play(_kroar, 0.0, 1.2)
			_fall_k(t, 1.7, 4.6, 7.4)
			if _at(t, was, 2.6):
				_dust(Vector3(kx - 0.35 * S, GROUND, Z), 1.0)
				_jolt_later(0.6, 0.9)
			G["beat"] = _pulse(t, 3.0, 3.2, 4.4, 4.6)
			if _at(t, was, 3.05):
				_play(_gbeat, -1.0, 1.0)
		"circle":
			var sway := sin(t * 0.9) * 0.07 * S
			kx = lerpf(_k0, face_k + 0.1 * S, _rise(t, 0.0, 2.0)) + sway
			gx = lerpf(_g0, face_g - 0.1 * S, _rise(t, 0.0, 2.0)) + sway
			_walk(delta, 0.6, 0.6, 1.0, 1.0)
			K["roar"] = 0.35 * _pulse(t, 1.0, 1.6, 2.6, 3.2)
		"roars":
			K["roar"] = _pulse(t, 0.2, 0.7, 2.6, 3.2)
			G["roar"] = _pulse(t, 3.4, 3.8, 6.0, 6.6)
			G["beat"] = _pulse(t, 3.2, 3.4, 3.8, 4.0)
			if _at(t, was, 0.3):
				_play(_kroar, 0.0, 0.8)
			if _at(t, was, 3.5):
				_play(_groar, 0.0, 0.85)
		"ice_beam":
			_ice_beam(t, was, d)
		"fireball":
			_fireball_attack(t, was, d)
		"g_retreat":
			# down, frozen; thaws, gets up, turns tail and lopes off into the city
			G["tilt"] = 1.25 * (1.0 - _rise(t, 3.0, 6.0))
			G["sink"] = 0.28 * (1.0 - _rise(t, 3.0, 6.0))
			G["rear"] = 0.0
			_over_g(0.85 * (1.0 - _rise(t, 1.0, 6.0)))
			G["yaw"] = PI * (1.0 - _rise(t, 6.0, 8.0))          # turns tail
			if t > 7.0:
				gx = _g0 + (t - 7.0) * 6.0
				_walk(delta, 0.0, 1.4, 1.0, 0.9)
			K["roar"] = 0.4 * _pulse(t, 6.5, 7.0, 8.0, 8.6)
		"k_retreat":
			K["tilt"] = 1.25 * (1.0 - _rise(t, 3.0, 6.0))
			K["sink"] = 0.3 * (1.0 - _rise(t, 3.0, 6.0))
			_over_k(0.55 * (1.0 - _rise(t, 1.0, 7.0)))
			K["yaw"] = PI * _rise(t, 6.0, 8.0)
			if t > 7.0:
				kx = _k0 - (t - 7.0) * 6.0
				_walk(delta, 1.4, 0.0, 0.9, 1.0)
			G["rear"] = 1.0
		"k_victory":
			K["roar"] = _pulse(t, 0.3, 1.0, 5.0, 6.2)
			K["arms"] = 0.5 * K["roar"]
			if _at(t, was, 0.4):
				_play(_kroar, 2.0, 0.75)
				_jolt_later(0.2, 0.4)
			gx += delta * 6.0
			_walk(delta, 0.0, 1.4, 1.0, 0.9)
			G["yaw"] = 0.0
			G["rear"] = 0.0
		"g_victory":
			G["rear"] = 1.0
			G["beat"] = _pulse(t, 0.4, 0.6, 2.2, 2.4)
			G["roar"] = _pulse(t, 2.6, 3.0, 6.0, 7.0)
			if _at(t, was, 0.45):
				_play(_gbeat, 0.0, 0.9)
			if _at(t, was, 2.7):
				_play(_groar, 2.0, 0.8)
				_jolt_later(0.2, 0.4)
			kx -= delta * 6.0
			_walk(delta, 1.4, 0.0, 0.9, 1.0)
			K["yaw"] = PI
		"k_exit":
			K["yaw"] = PI
			kx = _k0 - t * 5.0
			gx += delta * 6.0
			G["yaw"] = 0.0
			G["rear"] = 0.0
			_walk(delta, 1.0, 1.4, 1.75, 0.9)
			if kx < CX - 2.6 * S and gx > CX + 2.6 * S:
				_bt = d
		"g_exit":
			G["yaw"] = 0.0
			G["rear"] = 0.0
			gx = _g0 + t * 5.0
			kx -= delta * 6.0
			K["yaw"] = PI
			_walk(delta, 1.4, 1.0, 0.9, 1.3)
			if kx < CX - 2.6 * S and gx > CX + 2.6 * S:
				_bt = d
		"clash":
			kx = lerpf(_k0, touch_k, _rise(t, 0.0, 0.6))
			gx = lerpf(_g0, touch_g, _rise(t, 0.0, 0.6))
			K["lunge"] = _pulse(t, 0.0, 0.5, 0.8, 1.4)
			G["punch_r"] = _pulse(t, 0.2, 0.5, 0.7, 1.2)
			if _at(t, was, 0.6):
				_impact(Vector3(CX, 0.65 * S + GROUND, Z), 1.2, Color(1.0, 0.95, 0.8))
				_play(_kroar, 0.0, 1.2)
				_play(_groar, 0.0, 1.2)
			var back := _rise(t, 0.6, 2.0)
			kx -= 0.3 * S * back
			gx += 0.3 * S * back
			K["tilt"] = 0.4 * _pulse(t, 0.6, 1.2, 3.0, 4.5)
			G["tilt"] = 0.4 * _pulse(t, 0.6, 1.2, 3.0, 4.5)
			K["roar"] = _pulse(t, 4.5, 5.0, 6.2, 6.9)
			G["roar"] = _pulse(t, 4.7, 5.2, 6.4, 7.0)
			if _at(t, was, 4.6):
				_play(_kroar, -3.0, 1.0)
		"both_exit":
			K["yaw"] = PI
			G["yaw"] = 0.0
			G["rear"] = 0.0
			kx = _k0 - t * 5.0
			gx = _g0 + t * 5.0
			_walk(delta, 1.0, 1.0, 1.75, 1.3)
			if t > 26.0:
				_bt = d


func _fall_k(t: float, hit: float, up: float, done: float) -> void:
	K["tilt"] = 1.3 * _rise(t, hit, hit + 0.9) * (1.0 - _rise(t, up, done))
	K["sink"] = 0.3 * _rise(t, hit + 0.3, hit + 1.0) * (1.0 - _rise(t, up, done))
	K["roar"] = maxf(K["roar"], 0.5 * _pulse(t, up, up + 0.5, done - 0.5, done))


func _fall_g(t: float, hit: float, up: float, done: float) -> void:
	G["rear"] = 0.0
	G["tilt"] = 1.3 * _rise(t, hit, hit + 0.9) * (1.0 - _rise(t, up, done))
	G["sink"] = 0.28 * _rise(t, hit + 0.3, hit + 1.0) * (1.0 - _rise(t, up, done))
	G["rear"] = _rise(t, done - 0.6, done)


# walk cycles: the T-Rex takes a step every 1.8 s, King Gaboon every 1.3 s (rate scales each)
func _walk(delta: float, k_amt: float, g_amt: float, k_rate: float, g_rate: float) -> void:
	if k_amt > 0.0:
		var before := int(_kph / PI)
		_kph += delta * PI / 1.8 * k_rate
		K["walk"] = minf(k_amt, 1.0)
		if int(_kph / PI) != before:
			_step(kx)
	if g_amt > 0.0:
		var before := int(_gph / PI)
		_gph += delta * PI / 1.3 * g_rate
		G["walk"] = minf(g_amt, 1.0)
		if int(_gph / PI) != before:
			_step(gx)


func _step(x: float) -> void:
	var near := clampf(1.0 - absf(x - CX) / (3.0 * S), 0.15, 0.6)
	_later.append([_T + 0.25, _thump, 0.8, linear_to_db(near * 0.5)])


# ---- the finishers

# the T-Rex's crest glows brighter and brighter, then a beam of ice pours from its jaws and freezes King Gaboon
func _ice_beam(t: float, was: float, d: float) -> void:
	var charge := _rise(t, 0.0, 2.6)
	K["roar"] = _pulse(t, 2.0, 2.6, 6.2, 7.0)
	K["lunge"] = 0.25 * K["roar"]
	_ice_mat.emission_energy_multiplier = _ice_glow_base + 1.2 * charge * (1.0 - _rise(t, 6.2, 8.0))
	G["rear"] = 1.0 - _rise(t, 3.4, 4.2)
	if _at(t, was, 0.3):
		_play(_kroar, -6.0, 0.7)
	var firing := t > 2.6 and t < 6.4
	_beam.visible = firing
	if firing:
		var mouth := (_kp["jaw"] as Node3D).to_global(Vector3(0.12, 0.03, 0.0))
		var target := Vector3(gx - 0.2 * S, 0.5 * S + GROUND, Z)
		_aim_beam(mouth, target, 1.0 - _rise(t, 6.0, 6.4))
		_beam_mat.set_shader_parameter("amount", _pulse(t, 2.6, 2.9, 6.0, 6.4))
		_over_g(0.9 * _rise(t, 2.8, 4.6))
		if int(was * 4.0) != int(t * 4.0):
			_impact(target, 0.5, Color(0.7, 0.92, 1.0))
	if _at(t, was, 2.6):
		_play(_zap, 0.0, 1.0)
	_crystal_burst(Vector3(gx - 0.05 * S, GROUND, Z), _rise(t, 3.0, 4.6) * (1.0 - _rise(t, 7.6, 9.0)))
	_fall_g(t, 3.6, 99.0, 100.0)
	if _at(t, was, 4.4):
		_dust(Vector3(gx + 0.3 * S, GROUND, Z), 1.0)
		_jolt_later(0.6, 1.0)
	if t >= d - 0.05:
		_ice_mat.emission_energy_multiplier = _ice_glow_base


# King Gaboon rears up, a fireball swells between his hands, and he hurls it into the T-Rex's chest
func _fireball_attack(t: float, was: float, d: float) -> void:
	G["rear"] = 1.0
	G["grab"] = _pulse(t, 0.3, 1.0, 2.6, 2.8)                 # hands forward, cupping the fire
	G["punch_r"] = _pulse(t, 2.6, 2.9, 3.1, 3.6)              # the throw
	G["roar"] = _pulse(t, 0.4, 1.0, 2.4, 3.0)
	if _at(t, was, 0.5):
		_play(_groar, -4.0, 0.7)
	var hands := ((_gp["elbows"][0] as Node3D).global_position + (_gp["elbows"][1] as Node3D).global_position) * 0.5 + Vector3(-0.14 * S, 0.02 * S, 0.0)
	var target := Vector3(kx + 0.15 * S, 0.55 * S + GROUND, Z)
	var grow := _rise(t, 0.4, 2.6)
	var fly := _rise(t, 2.8, 3.6)
	_fireball.visible = t > 0.4 and t < 3.6
	if _fireball.visible:
		_fireball.global_position = hands.lerp(target, fly) + Vector3(0, sin(fly * PI) * 0.12 * S, 0)
		_fireball.scale = Vector3.ONE * (0.03 + 0.09 * grow) * S
		_fire_mat.set_shader_parameter("amount", 1.0)
	if _at(t, was, 2.8):
		_play(_whoosh, 0.0, 1.0)
	if _at(t, was, 3.6):
		_explode(target)
		_play(_kroar, 0.0, 1.3)
	_over_k(0.55 * _rise(t, 3.6, 4.0))
	_fall_k(t, 3.6, 99.0, 100.0)
	if _at(t, was, 4.5):
		_dust(Vector3(kx - 0.35 * S, GROUND, Z), 1.0)
		_jolt_later(0.6, 1.0)


# ---- poses

func _reset_pose() -> void:
	K = {"walk": 0.0, "roar": 0.0, "lunge": 0.0, "bite": 0.0, "snap": 0.0, "arms": 0.0, "tilt": 0.0, "sink": 0.0, "yaw": 0.0}
	G = {"walk": 0.0, "rear": 1.0, "beat": 0.0, "roar": 0.0, "grab": 0.0, "punch_r": 0.0, "punch_l": 0.0, "recoil": 0.0,
		"snap": 0.0, "tilt": 0.0, "sink": 0.0, "yaw": PI}


func _apply_k() -> void:
	var s := sin(_kph) * float(K["walk"])
	var lunge: float = K["lunge"]
	var roar: float = K["roar"]
	(_kp["body"] as Node3D).rotation = Vector3(0.05 * s, 0.0, 0.04 * sin(_kph * 2.0) * float(K["walk"]) + 0.12 * roar - 0.35 * lunge)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var sw := s * side
		(_kp["legs"][i] as Node3D).rotation.z = -0.38 * sw + lunge * (0.25 if i == 0 else -0.15)
		(_kp["knees"][i] as Node3D).rotation.z = 0.45 * maxf(0.0, sw) + 0.2 * lunge
		(_kp["arms"][i] as Node3D).rotation.z = 0.2 * sw + 0.9 * float(K["arms"]) + 0.4 * lunge
	(_kp["head"] as Node3D).rotation = Vector3(0.0, 0.5 * float(K["snap"]), 0.42 * roar - 0.2 * lunge + 0.04 * sin(_T * 0.7))
	var open := maxf(roar, float(K["bite"]))
	(_kp["jaw"] as Node3D).rotation.z = -0.5 * open - 0.04 * open * sin(_T * 30.0)
	_kt.rotation.z = K["tilt"]
	var bob := -absf(cos(_kph)) * 0.012 * S * float(K["walk"])
	_kh.position = Vector3(kx, GROUND - float(K["sink"]) * S + bob, Z)
	_kh.rotation.y = K["yaw"]


func _apply_g() -> void:
	var p := _gp
	var w: float = G["walk"]
	var s := sin(_gph) * w
	var rear: float = G["rear"]
	var beat: float = G["beat"]
	var roar: float = G["roar"]
	var grab: float = G["grab"]
	var recoil: float = G["recoil"]
	(p["body"] as Node3D).rotation = Vector3(0.03 * sin(_gph * 2.0) * w - 0.55 * rear + 0.18 * recoil, 0.0, 0.035 * s)
	(p["head"] as Node3D).rotation = Vector3(0.45 * rear - 0.25 * roar - 0.1 * recoil, 0.45 * float(G["snap"]), 0.0)
	(p["jaw"] as Node3D).rotation = Vector3(0.55 * roar + 0.04 * roar * sin(_T * 30.0), 0.0, 0.0)
	(p["tail"] as Node3D).rotation = Vector3(0.25 * rear, 0.15 * sin(_T * 2.0) * rear + 0.12 * s, 0.0)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var front := s * side
		var back := -front
		var hit := 0.5 + 0.5 * sin(_T * 14.0 + (0.0 if i == 0 else PI))
		var punch: float = G["punch_r"] if i == 1 else G["punch_l"]
		var reach := maxf(punch, grab)
		(p["arms"][i] as Node3D).rotation = Vector3(-0.3 * front + rear * (0.8 - 0.25 * beat * hit) - 1.6 * reach, 0.0, -0.4 * side * rear * (1.0 - reach))
		(p["elbows"][i] as Node3D).rotation = Vector3(-0.35 * maxf(0.0, front) + rear * (-1.9 + 0.3 * beat * hit) + 1.7 * rear * reach, 0.0, 0.0)
		(p["legs"][i] as Node3D).rotation = Vector3(-0.28 * back + 0.35 * rear, 0.0, 0.0)
		(p["knees"][i] as Node3D).rotation = Vector3(0.5 * maxf(0.0, back) - 0.25 * rear, 0.0, 0.0)
	_gt.rotation.z = G["tilt"]
	var bob := absf(sin(_gph)) * 0.008 * S * w
	_gh.position = Vector3(gx, GROUND - float(G["sink"]) * S + bob, Z)
	_gh.rotation.y = G["yaw"]


# ---- building it all (the first time a fight starts)

func _build() -> void:
	_built = true
	_fx_shader = Shader.new()
	_fx_shader.code = FX_SHADER
	# the T-Rex
	_kh = Node3D.new()
	_kh.name = "FightKaiju"
	main.room.add_child(_kh)
	_kt = Node3D.new()
	_kh.add_child(_kt)
	var k: Node3D = KModel.build()
	k.scale = Vector3.ONE * S
	_kt.add_child(k)
	var body: Node3D = k.get_node("Body")
	_kp = {"body": body, "head": body.get_node("Head"), "jaw": body.get_node("Head/Jaw"),
		"legs": [body.get_node("LegL"), body.get_node("LegR")], "knees": [body.get_node("LegL/Knee"), body.get_node("LegR/Knee")],
		"arms": [body.get_node("ArmL"), body.get_node("ArmR")]}
	for mi in k.find_children("*", "MeshInstance3D", true, false):       # its own crest material, to make it glow
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m != null and m.vertex_color_use_as_albedo:
			if _ice_mat == null:
				_ice_mat = m.duplicate()
				_ice_glow_base = _ice_mat.emission_energy_multiplier
			(mi as MeshInstance3D).material_override = _ice_mat
	if _ice_mat == null:
		_ice_mat = StandardMaterial3D.new()
	_k_over = _overlay(Color(0.9, 0.3, 0.06), Color(0.12, 0.07, 0.06))   # scorched by the fireball
	_k_meshes = k.find_children("*", "MeshInstance3D", true, false)
	# King Gaboon
	_gh = Node3D.new()
	_gh.name = "FightGaboon"
	main.room.add_child(_gh)
	_gt = Node3D.new()
	_gh.add_child(_gt)
	var g: Node3D = GModel.build()
	g.scale = Vector3.ONE * S
	_gt.add_child(g)
	_gp = GaboonScript._parts(g)
	_g_over = _overlay(Color(0.6, 0.9, 1.0), Color(0.82, 0.93, 1.0))       # frozen by the ice beam
	_g_meshes = g.find_children("*", "MeshInstance3D", true, false)
	# King Gaboon's dark fur would vanish into the night sky: a touch of its own glow on this big one
	for mi in _g_meshes:
		var fm := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if fm != null and not fm.emission_enabled:
			fm.emission_enabled = true
			fm.emission = fm.albedo_color
			fm.emission_energy_multiplier = 0.45
	# their own light: a cool moonlit key from above the street (visual layer 2, so it only lights these two)
	for mi in _k_meshes + _g_meshes:
		(mi as MeshInstance3D).layers = 1 | 2
	_key = OmniLight3D.new()
	_key.light_cull_mask = 2
	_key.omni_range = 110.0
	_key.omni_attenuation = 0.6
	_key.light_energy = 2.6
	_key.light_color = Color(0.8, 0.85, 1.0)
	_key.position = Vector3(CX, 70.0, Z + 40.0)
	_key.visible = false
	main.room.add_child(_key)
	_fill = OmniLight3D.new()                     # and the city's pink glow from below, in front
	_fill.light_cull_mask = 2
	_fill.omni_range = 90.0
	_fill.light_energy = 1.4
	_fill.light_color = Color(1.0, 0.55, 0.8)
	_fill.position = Vector3(CX, 12.0, Z + 45.0)
	_fill.visible = false
	main.room.add_child(_fill)
	_kh.visible = false
	_gh.visible = false
	_build_fx()
	_build_helis()
	_thump = _player(KaijuScript._make_thump(), -4.0)
	_kroar = _player(KaijuScript._make_rumble(), -2.0)
	_groar = _player(GaboonScript._make_roar(), -2.0)
	_gbeat = _player(GaboonScript._make_chest_beat(), -3.0)
	_zap = _player(_make_zap(), -4.0)
	_whoosh = _player(_make_whoosh(), -2.0)


# frost / scorch only goes on while it shows (an overlay pass on every part costs something)
var _k_meshes: Array = []
var _g_meshes: Array = []
var _k_on := false
var _g_on := false


func _over_k(a: float) -> void:
	_k_over.set_shader_parameter("amount", a)
	if (a > 0.001) != _k_on:
		_k_on = a > 0.001
		for mi in _k_meshes:
			(mi as MeshInstance3D).material_overlay = _k_over if _k_on else null


func _over_g(a: float) -> void:
	_g_over.set_shader_parameter("amount", a)
	if (a > 0.001) != _g_on:
		_g_on = a > 0.001
		for mi in _g_meshes:
			(mi as MeshInstance3D).material_overlay = _g_over if _g_on else null


func _overlay(glow: Color, base: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = OVERLAY_SHADER
	m.shader = sh
	m.set_shader_parameter("tint", base)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("amount", 0.0)
	return m


func _player(st: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = db
	p.max_polyphony = 3
	add_child(p)
	return p


func _play(p: AudioStreamPlayer, db: float, pitch: float) -> void:
	p.volume_db = db - 4.0                          # far off across the city
	p.pitch_scale = pitch
	p.play()


func _sounds_tick() -> void:
	var keep: Array = []
	for e in _later:
		if _T >= float(e[0]):
			var p: AudioStreamPlayer = e[1]
			p.pitch_scale = e[2]
			p.volume_db = e[3]
			p.play()
		else:
			keep.append(e)
	_later = keep


# the window rattles a moment after the hit, as the shock arrives
func _jolt_later(after: float, near: float) -> void:
	get_tree().create_timer(after).timeout.connect(func() -> void:
		if active and main.kaiju != null:
			main.kaiju.jolt(near * 0.55))


# ---- effects (meshes with small shaders; no particle systems)

func _fx_mat(mode: int, col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _fx_shader
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("amount", 1.0)
	return m


func _build_fx() -> void:
	var lp := Plat.low_power()
	for i in 4:                                          # impact flashes: a glowing card and (on a PC) a light
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = _fx_mat(0, Color.WHITE)
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.room.add_child(mi)
		var l: OmniLight3D = null
		if not lp:
			l = OmniLight3D.new()
			l.omni_range = 70.0
			l.light_energy = 0.0
			l.visible = false
			main.room.add_child(l)
		_flashes.append([mi, l, 1.0, 1.0, 1.0])
	for i in (5 if lp else 9):                           # dust: soft round puffs that rise, spread and fade
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = _fx_mat(1, Color(0.55, 0.5, 0.55))
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.room.add_child(mi)
		_puffs.append([mi, 1.0, 1.0, Vector3.ZERO, 1.0])
	# the ice beam: a streaming core inside a softer sheath, pointing along its -z
	_beam = Node3D.new()
	_beam.visible = false
	main.room.add_child(_beam)
	_beam_mat = _fx_mat(2, Color(0.55, 0.88, 1.0))
	for k in 2:
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 16
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = _beam_mat
		mi.rotation.x = PI / 2.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.add_child(mi)
		if k == 0:
			_beam_core = mi
	# ice crystals bursting up round King Gaboon where the beam lands: a few long blades, not a cluster
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.7, 0.9, 1.0, 0.85)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.emission_enabled = true
	ice.emission = Color(0.4, 0.75, 1.0)
	ice.emission_energy_multiplier = 1.4
	ice.roughness = 0.1
	ice.disable_fog = true
	for i in 7:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 5
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = ice
		mi.visible = false
		main.room.add_child(mi)
		_crystals.append(mi)
	# the fireball: a swirling sphere of flame; the blast: a shell that swells and fades
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	_fire_mat = _fx_mat(3, Color(1.0, 0.55, 0.15))
	_fireball = MeshInstance3D.new()
	_fireball.mesh = sm
	_fireball.material_override = _fire_mat
	_fireball.visible = false
	main.room.add_child(_fireball)
	_boom_mat = _fx_mat(4, Color(1.0, 0.5, 0.12))
	_boom = MeshInstance3D.new()
	_boom.mesh = sm
	_boom.material_override = _boom_mat
	_boom.visible = false
	main.room.add_child(_boom)
	_charge = MeshInstance3D.new()
	_charge.mesh = sm
	_charge.material_override = _fx_mat(0, Color(0.6, 0.9, 1.0))
	_charge.visible = false
	main.room.add_child(_charge)


func _impact(at: Vector3, power: float, col: Color) -> void:
	for f in _flashes:
		if float(f[2]) >= float(f[3]):
			f[2] = 0.0
			f[3] = 0.35 + 0.25 * power
			f[4] = (0.12 + 0.14 * power) * S
			var mi: MeshInstance3D = f[0]
			mi.global_position = at + Vector3(0, 0, 2.0)
			(mi.material_override as ShaderMaterial).set_shader_parameter("col", col)
			mi.visible = true
			if f[1] != null:
				var l: OmniLight3D = f[1]
				l.global_position = at + Vector3(0, 0, 8.0)
				l.light_color = col
				l.visible = true
			break
	_later.append([_T + 0.2, _thump, 1.0 + 0.1 * (1.0 - power), linear_to_db(clampf(0.35 + 0.4 * power, 0.0, 1.0))])
	if power >= 0.6:
		_jolt_later(0.25, 0.35 * power)


func _dust(at: Vector3, power: float) -> void:
	var n := 0
	for p in _puffs:
		if float(p[1]) >= float(p[2]):
			p[1] = 0.0
			p[2] = 3.0 + _rng.randf() * 2.0
			var off := Vector3(_rng.randf_range(-0.35, 0.35) * S, _rng.randf_range(0.15, 0.3) * S, _rng.randf_range(-0.1, 0.1) * S)
			(p[0] as MeshInstance3D).global_position = at + off
			p[3] = Vector3(off.x * 0.08, _rng.randf_range(2.0, 5.0), 0.0)
			p[4] = (0.18 + 0.1 * _rng.randf()) * S * power
			(p[0] as MeshInstance3D).visible = true
			n += 1
			if n >= 6:
				break


func _explode(at: Vector3) -> void:
	_boom_t = 0.0
	_boom.global_position = at
	_boom.visible = true
	_impact(at, 1.4, Color(1.0, 0.6, 0.2))
	_dust(Vector3(at.x, GROUND, Z), 0.8)


func _aim_beam(from: Vector3, to: Vector3, width: float) -> void:
	var len := from.distance_to(to)
	_beam.global_position = (from + to) * 0.5
	_beam.look_at(to, Vector3.UP)
	var r := 0.035 * S * width
	_beam_core.scale = Vector3(r * 0.45, len, r * 0.45)
	(_beam.get_child(1) as MeshInstance3D).scale = Vector3(r, len, r)


func _crystal_burst(at: Vector3, k: float) -> void:
	for i in _crystals.size():
		var c := _crystals[i]
		c.visible = k > 0.01
		if not c.visible:
			continue
		var a := TAU * i / _crystals.size() + 0.4
		var tall := (0.25 + 0.12 * sin(i * 2.3)) * S * k
		c.scale = Vector3(0.045 * S, tall, 0.045 * S)
		c.global_position = at + Vector3(cos(a) * 0.22 * S, tall * 0.5 - 0.02 * S, sin(a) * 0.1 * S)
		c.rotation = Vector3(sin(a) * 0.35, 0.0, -cos(a) * 0.45)


func _fx_tick(delta: float) -> void:
	var cam := main.get_viewport().get_camera_3d()
	var face := Basis.IDENTITY
	if cam != null:
		face = cam.global_transform.basis            # the cards turn to face you
	for f in _flashes:
		if float(f[2]) >= float(f[3]):
			continue
		f[2] = float(f[2]) + delta
		var u := clampf(float(f[2]) / float(f[3]), 0.0, 1.0)
		var mi: MeshInstance3D = f[0]
		var sz: float = float(f[4]) * (0.6 + 0.8 * u)
		mi.global_transform.basis = face.scaled(Vector3.ONE * sz)
		(mi.material_override as ShaderMaterial).set_shader_parameter("amount", 1.0 - u)
		if f[1] != null:
			(f[1] as OmniLight3D).light_energy = 6.0 * (1.0 - u) * (1.0 - u)
		if u >= 1.0:
			mi.visible = false
			if f[1] != null:
				(f[1] as OmniLight3D).visible = false
	for p in _puffs:
		if float(p[1]) >= float(p[2]):
			continue
		p[1] = float(p[1]) + delta
		var u := clampf(float(p[1]) / float(p[2]), 0.0, 1.0)
		var mi: MeshInstance3D = p[0]
		mi.global_position += (p[3] as Vector3) * delta
		mi.global_transform.basis = face.scaled(Vector3.ONE * float(p[4]) * (1.0 + 1.6 * u))
		(mi.material_override as ShaderMaterial).set_shader_parameter("amount", 0.55 * smoothstep(0.0, 0.15, u) * (1.0 - u))
		if u >= 1.0:
			mi.visible = false
	if _boom_t >= 0.0:
		_boom_t += delta
		var u := clampf(_boom_t / 1.6, 0.0, 1.0)
		_boom.scale = Vector3.ONE * (0.05 + 0.32 * sqrt(u)) * S
		_boom_mat.set_shader_parameter("amount", 1.0 - u)
		if u >= 1.0:
			_boom.visible = false
			_boom_t = -1.0


# ---- helicopters: news and police choppers circling the fight, searchlights on the monsters

func _build_helis() -> void:
	var lp := Plat.low_power()
	var chop := _make_chop()
	for i in HELIS:
		var root := Node3D.new()
		root.visible = false
		main.room.add_child(root)
		var police := i % 2 == 1
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(0.12, 0.13, 0.18) if police else Color(0.85, 0.85, 0.88)
		paint.roughness = 0.4
		paint.metallic = 0.3
		paint.disable_fog = true
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.05, 0.05, 0.07)
		dark.disable_fog = true
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.3, 0.45, 0.6)
		glass.emission_enabled = true
		glass.emission = Color(0.4, 0.55, 0.7)
		glass.emission_energy_multiplier = 0.6
		glass.disable_fog = true
		var body := Node3D.new()
		body.scale = Vector3.ONE * 1.3
		root.add_child(body)
		# cabin, nose glass, tail boom and fin, skids: about 4 units long, facing -z
		var cab := CapsuleMesh.new()
		cab.radius = 0.55
		cab.height = 2.0
		var c := _mesh(body, cab, paint, Vector3.ZERO)
		c.rotation.x = PI / 2.0
		var nose := SphereMesh.new()
		nose.radius = 0.45
		nose.height = 0.8
		_mesh(body, nose, glass, Vector3(0, 0.08, -0.72))
		var boom := CylinderMesh.new()
		boom.top_radius = 0.1
		boom.bottom_radius = 0.18
		boom.height = 2.2
		_mesh(body, boom, paint, Vector3(0, 0.1, 1.8)).rotation.x = PI / 2.0
		var fin := BoxMesh.new()
		fin.size = Vector3(0.06, 0.6, 0.35)
		_mesh(body, fin, paint, Vector3(0, 0.38, 2.8))
		for sx in [-1.0, 1.0]:
			var sk := BoxMesh.new()
			sk.size = Vector3(0.06, 0.06, 1.8)
			_mesh(body, sk, dark, Vector3(sx * 0.45, -0.72, 0.0))
		var mast := CylinderMesh.new()
		mast.top_radius = 0.06
		mast.bottom_radius = 0.06
		mast.height = 0.3
		_mesh(body, mast, dark, Vector3(0, 0.65, 0.0))
		var rotor := Node3D.new()
		rotor.position = Vector3(0, 0.8, 0)
		body.add_child(rotor)
		for k in 2:
			var bl := BoxMesh.new()
			bl.size = Vector3(4.2, 0.03, 0.18)
			_mesh(rotor, bl, dark, Vector3.ZERO).rotation.y = k * PI / 2.0
		var trotor := Node3D.new()
		trotor.position = Vector3(0.12, 0.38, 2.85)
		body.add_child(trotor)
		var tb := BoxMesh.new()
		tb.size = Vector3(0.02, 0.8, 0.08)
		_mesh(trotor, tb, dark, Vector3.ZERO)
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(1.0, 0.1, 0.1)
		red.emission_enabled = true
		red.emission = Color(1.0, 0.1, 0.1)
		red.emission_energy_multiplier = 4.0
		red.disable_fog = true
		var bm := SphereMesh.new()
		bm.radius = 0.12
		bm.height = 0.24
		var blink := _mesh(body, bm, red, Vector3(0, -0.55, 0.3))
		# the searchlight: an aimed spotlight (on a PC) and a soft beam you can see
		var aim := Node3D.new()
		aim.position = Vector3(0, -0.5, -0.6)
		body.add_child(aim)
		if not lp:
			var sl := SpotLight3D.new()
			sl.spot_range = 160.0
			sl.spot_angle = 7.0
			sl.light_energy = 6.0
			sl.light_color = Color(1.0, 0.97, 0.88)
			aim.add_child(sl)
			var cone := CylinderMesh.new()
			cone.top_radius = 7.0                      # (+y ends up far from the chopper)
			cone.bottom_radius = 0.25
			cone.height = 1.0
			cone.radial_segments = 16
			cone.cap_top = false
			cone.cap_bottom = false
			var beam := MeshInstance3D.new()
			beam.mesh = cone
			beam.material_override = _fx_mat(5, Color(1.0, 0.97, 0.85))
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			aim.add_child(beam)
		var snd := AudioStreamPlayer3D.new()
		snd.stream = chop
		snd.unit_size = 14.0
		snd.max_distance = 220.0
		snd.volume_db = -6.0
		snd.pitch_scale = 0.9 + 0.05 * i
		body.add_child(snd)
		_helis.append({"node": root, "rotor": rotor, "trotor": trotor, "blink": blink, "aim": aim, "sound": snd,
			"t": 0.0, "r": 40.0 + 9.0 * i, "w": (0.16 + 0.025 * i) * (1.0 if i % 2 == 0 else -1.0), "a0": i * 1.3,
			"h": 52.0 + 7.0 * (i % 3), "cz": Z + 14.0 - 4.0 * i})


func _mesh(parent: Node3D, m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _helis_tick(delta: float) -> void:
	var ending := _bi >= _beats.size() - 1
	for h in _helis:
		var root: Node3D = h["node"]
		h["t"] = float(h["t"]) + delta
		var t: float = h["t"]
		if t < 0.0:
			continue
		if not root.visible:
			root.visible = true
			(h["sound"] as AudioStreamPlayer3D).play()
		# fly in from the side, then circle the fight, bobbing and banking; leave as it ends
		var arrive := smoothstep(0.0, 12.0, t)
		var leave := smoothstep(0.0, 1.0, (_bt - 6.0) / 14.0) if ending else 0.0
		var a: float = float(h["a0"]) + float(h["w"]) * t
		var r: float = float(h["r"]) * (1.0 + 2.5 * (1.0 - arrive) + 3.0 * leave)
		var pos := Vector3(CX + cos(a) * r, float(h["h"]) + 3.0 * sin(t * 0.6 + a), float(h["cz"]) + sin(a) * r * 0.55)
		var ahead := Vector3(CX + cos(a + 0.05 * sign(float(h["w"]))) * r, pos.y, float(h["cz"]) + sin(a + 0.05 * sign(float(h["w"]))) * r * 0.55)
		root.global_position = pos
		if pos.distance_to(ahead) > 0.01:
			root.look_at(ahead, Vector3.UP)
			root.rotate_object_local(Vector3.FORWARD, -0.25 * sign(float(h["w"])))      # banked into the turn
			root.rotate_object_local(Vector3.RIGHT, -0.12)                                 # nose down a touch
		(h["rotor"] as Node3D).rotation.y += delta * 28.0
		(h["trotor"] as Node3D).rotation.x += delta * 40.0
		(h["blink"] as Node3D).visible = fmod(_T + float(h["a0"]), 1.0) < 0.15
		# the searchlight finds whichever monster is nearer
		var tk := Vector3(kx, (0.62 - float(K["sink"])) * S + GROUND, Z)
		var tg := Vector3(gx, (0.55 - float(G["sink"])) * S + GROUND, Z)
		var tgt := tk if pos.distance_to(tk) < pos.distance_to(tg) else tg
		var aim: Node3D = h["aim"]
		aim.look_at(tgt + Vector3(sin(_T * 0.7 + a) * 4.0, 0.0, 0.0), Vector3.UP)
		if aim.get_child_count() > 1:
			var beam := aim.get_child(1) as MeshInstance3D
			var len := clampf(aim.global_position.distance_to(tgt), 10.0, 150.0) / 1.3
			beam.scale = Vector3(1.0, len, 1.0)
			beam.position = Vector3(0, 0, -len * 0.5)
			beam.rotation.x = -PI / 2.0
		root.visible = leave < 0.98


# ---- shared rooms: the fight's number and seed travel together

func state() -> int:
	return count * 100000 + fight_seed


func apply_remote(n: int) -> void:
	var c := n / 100000
	if c > count:
		count = c
		fight_seed = n % 100000
		start()


# ---- sounds, made here

static func _make_zap() -> AudioStreamWAV:
	var rate := 22050
	var n := int(3.8 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var ph := 0.0
	var ph2 := 0.0
	var hp := 0.0
	var last := 0.0
	for i in n:
		var t := float(i) / rate
		ph += (420.0 + 260.0 * smoothstep(0.0, 0.5, t) + 25.0 * sin(t * 40.0)) / rate
		ph2 += 61.0 / rate
		var x := rng.randf_range(-1.0, 1.0)
		hp = 0.85 * (hp + x - last)                    # a bright, crackling hiss
		last = x
		var crackle := hp * (0.6 + 0.4 * sin(t * 90.0))
		var env := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(3.0, 3.8, t))
		var s := (sin(ph * TAU) * 0.35 + sin(ph * TAU * 1.5) * 0.15 + crackle * 0.35 + sin(ph2 * TAU) * 0.3) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	return KaijuScript._wav(data, rate)


static func _make_whoosh() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.4 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var cut := 0.05 + 0.4 * smoothstep(0.0, 0.8, t)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cut      # a roar of flame that brightens as it flies
		var env := smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.9, 1.4, t))
		data.encode_s16(i * 2, int(clampf(lp * 2.2 * env, -1.0, 1.0) * 28000.0))
	return KaijuScript._wav(data, rate)


# a rotor's chop, looping: soft thuds eleven times a second over a low turbine hum
static func _make_chop() -> AudioStreamWAV:
	var rate := 22050
	var n := rate                                      # one second, loops cleanly (11 beats)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var beat := fmod(t * 11.0, 1.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.12
		var thud := lp * 2.4 * exp(-beat * 9.0)
		var hum := sin(TAU * 110.0 * t) * 0.05 + sin(TAU * 220.0 * t) * 0.03
		data.encode_s16(i * 2, int(clampf((thud + hum) * 0.8, -1.0, 1.0) * 26000.0))
	var w := KaijuScript._wav(data, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


# ---- shaders

# mode 0: a round glowing flash card; 1: a soft dust puff; 2: the ice beam; 3: the fireball; 4: the blast shell;
# 5: a searchlight beam. All smooth gradients and flowing streaks (no spotty or cellular patterns).
const FX_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform int mode = 0;
uniform vec4 col : source_color = vec4(1.0);
uniform float amount = 1.0;

float h(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float flow(vec3 p) { return 0.6 * vnoise(p) + 0.3 * vnoise(p * 2.1 + 3.7) + 0.1 * vnoise(p * 4.3 + 1.3); }

void fragment() {
	float fres = abs(dot(normalize(NORMAL), normalize(VIEW)));
	if (mode == 0) {                                   // flash: bright centre, soft edge
		float d = length(UV - 0.5) * 2.0;
		float g = pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
		ALBEDO = mix(col.rgb, vec3(1.0), g * g) * (1.0 + 2.0 * g);
		ALPHA = g * amount;
	} else if (mode == 1) {                            // dust: a soft round cloud, a little uneven at the rim
		vec2 c = UV - 0.5;
		float d = length(c) * 2.0 + 0.18 * (flow(vec3(c * 3.0, TIME * 0.2)) - 0.5);
		float g = smoothstep(1.0, 0.2, d);
		ALBEDO = col.rgb * (0.8 + 0.2 * (1.0 - d));
		ALPHA = g * amount;
	} else if (mode == 2) {                            // ice beam: a white-hot core and streaks rushing along it
		float core = pow(fres, 3.0);
		float streak = 0.6 + 0.4 * sin(UV.y * 60.0 - TIME * 40.0 + 3.0 * flow(vec3(UV * 4.0, TIME)));
		ALBEDO = mix(col.rgb, vec3(1.0), core) * (1.2 + streak);
		ALPHA = clamp((0.25 + 0.75 * core) * streak, 0.0, 1.0) * amount;
	} else if (mode == 3) {                            // fireball: swirling flame, hotter at the heart
		vec3 p = NORMAL * 2.0 + vec3(0.0, -TIME * 1.6, TIME * 0.7);
		float f = flow(p * 1.4);
		float heat = clamp(fres * 1.2 + 0.4 * f - 0.15, 0.0, 1.0);
		ALBEDO = mix(vec3(0.75, 0.12, 0.02), mix(col.rgb, vec3(1.0, 0.85, 0.45), heat * heat), heat) * (0.9 + 0.6 * heat);
		ALPHA = clamp(0.35 + heat, 0.0, 1.0) * amount;
	} else if (mode == 4) {                            // blast: a fiery shell, darkening to smoke as it grows
		float rim = 1.0 - fres;
		float f = flow(NORMAL * 2.5 + vec3(TIME * 0.6));
		vec3 fire = mix(vec3(0.25, 0.2, 0.2), col.rgb * 2.0, amount);
		ALBEDO = fire * (0.6 + 0.6 * f);
		ALPHA = clamp(rim * 1.4 + 0.25 * f, 0.0, 1.0) * amount;
	} else {                                           // searchlight: brightest along its middle, fading with length
		ALBEDO = col.rgb;
		ALPHA = 0.06 * pow(fres, 2.0) * (1.0 - UV.y * 0.7) * amount;
	}
}
"""

# laid over a monster: frost (pale ice creeping over the fur) or scorch (embers fading to soot)
const OVERLAY_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 glow : source_color = vec4(1.0);
uniform float amount = 0.0;
void fragment() {
	float fres = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint.rgb;
	EMISSION = glow.rgb * (0.4 + 1.2 * fres) * amount;
	ROUGHNESS = 0.2;
	ALPHA = clamp(amount * (0.55 + 0.45 * fres), 0.0, 0.95);
}
"""
