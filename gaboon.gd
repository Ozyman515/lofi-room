extends Node3D
## King Gaboon (the owner's monster): a giant mandrill-like ape (gaboon_model.gd) knuckle-walks down the street
## outside the window. Every step thumps and rattles the window (the kaiju's jolt: a screen jolts, a headset
## only rumbles the controllers). Halfway across he stops, looks in, rears up, beats his chest and roars at you,
## then drops back down and walks on.
## A little figure of him stands on top of the bookshelf. Pick it up and he shows off in your hand (a chest beat
## and a tiny roar), then he floats back to the shelf. Do that five times and the real one comes (or use the
## Debug window). In a shared room the host's King Gaboon walks past everybody's window.

const Model := preload("res://gaboon_model.gd")
const KaijuScript := preload("res://kaiju.gd")

const SCALE := 22.0                  # a little farther off than the kaiju, so his whole face fits in the window
const STREET := Vector3(0.0, -15.0, -14.0)
const HEAD_X := 0.55 * SCALE         # how far ahead of his middle the snout is
const FROM_X := -30.0 - HEAD_X
const TO_X := 26.0 - HEAD_X
const STEP_TIME := 1.2               # seconds per footfall (four feet, so a little quicker than the kaiju)
const STRIDE := 2.4
const PEEK_X := 0.8 - HEAD_X        # where he stops, face in the middle of the window
const SHOW_TIME := 7.4               # the look, rear-up, chest beat and roar
const REAR_SHIFT := Vector2(0.2, -0.19) * SCALE     # how far his face moves when he rears up, cancelled out
const TOY_POS := Vector3(2.32, 2.215, 0.72)    # on top of the bookshelf, beside the plant
const TOY_SCALE := 0.2
const TOY_PLAYS := 5

var main: Node3D
var active := false
var count := 0
var _g: Node3D
var _gr := {}                        # the giant's moving parts
var _x := FROM_X
var _phase := 0.0
var _shown := false
var _show_t := 0.0
var _thump: AudioStreamPlayer
var _roar: AudioStreamPlayer
var _beat: AudioStreamPlayer
var _squeak: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func setup(m: Node3D) -> void:
	main = m
	_rng.randomize()
	_g = Model.build()
	_g.scale = Vector3.ONE * SCALE
	_g.visible = false
	main.room.add_child(_g)
	_gr = _parts(_g)
	_thump = _player(KaijuScript._make_thump(), 0.0)
	_roar = _player(_make_roar(), -2.0)
	_beat = _player(_make_chest_beat(), -3.0)
	_squeak = _player(_make_roar(), -14.0)
	_squeak.pitch_scale = 2.6
	_build_toy()


func _player(s: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = db
	p.max_polyphony = 2
	add_child(p)
	return p


static func _parts(g: Node3D) -> Dictionary:
	var rig := g.get_node("Rig")
	var body := rig.get_node("Body")
	var head := body.get_node("Head")
	return {
		"body": body, "head": head, "jaw": head.get_node("Muzzle/Jaw"), "tail": body.get_node("Tail"),
		"arms": [body.get_node("ArmL"), body.get_node("ArmR")],
		"elbows": [body.get_node("ArmL/Elbow"), body.get_node("ArmR/Elbow")],
		"legs": [rig.get_node("LegL"), rig.get_node("LegR")],
		"knees": [rig.get_node("LegL/Knee"), rig.get_node("LegR/Knee")],
	}


# ---- starting a walk

func request_walk() -> void:
	if active or main.egg_active or main.sleeping:
		return
	if (main.kaiju != null and main.kaiju.active) or (main.fight != null and main.fight.active):
		return                                            # one giant at a time
	var ng = main.net_game
	if ng != null and ng.net.is_online() and not ng.net.is_host():
		ng.net.send_var(1, ng.Net.K_EVENT, {"k": "gaboon_on"})
		return
	count += 1
	start()


func start() -> void:
	if active:
		return
	active = true
	_x = FROM_X
	_phase = 0.0
	_shown = false
	_show_t = 0.0
	_g.visible = true
	_walk_pose(_gr, 0.0)
	_roar.volume_db = -16.0                               # a far-off roar as he comes into the city
	_roar.play()


func _process(delta: float) -> void:
	_toy_process(delta)
	if not active:
		return
	if not _shown and _x >= PEEK_X:
		_show(delta)
		return
	var before := int(_phase / PI)
	_phase += delta * PI / STEP_TIME
	_x += delta * STRIDE / STEP_TIME
	if int(_phase / PI) != before:
		_footfall()
	_walk_pose(_gr, _phase)
	_g.position = STREET + Vector3(_x, absf(sin(_phase)) * 0.008 * SCALE, 0.0)
	if _x > TO_X:
		active = false
		_g.visible = false


# ---- poses (shared by the giant and the figure)

# diagonal pairs move together, like a real knuckle-walker: front left with back right
static func _walk_pose(p: Dictionary, ph: float) -> void:
	var s := sin(ph)
	(p["body"] as Node3D).rotation = Vector3(0.03 * sin(ph * 2.0), 0.0, 0.035 * s)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var front := s * side                             # + = this front limb swinging forward
		var back := -front                                # its diagonal partner is the other back leg
		(p["arms"][i] as Node3D).rotation = Vector3(-0.3 * front, 0.0, 0.0)
		(p["elbows"][i] as Node3D).rotation = Vector3(-0.35 * maxf(0.0, front), 0.0, 0.0)
		(p["legs"][i] as Node3D).rotation = Vector3(-0.28 * back, 0.0, 0.0)
		(p["knees"][i] as Node3D).rotation = Vector3(0.5 * maxf(0.0, back), 0.0, 0.0)
	(p["tail"] as Node3D).rotation = Vector3(0.05 * sin(ph * 2.0), 0.12 * sin(ph), 0.0)
	(p["head"] as Node3D).rotation = Vector3(0.04 * sin(ph * 2.0), 0.06 * sin(ph * 0.5), 0.0)
	(p["jaw"] as Node3D).rotation = Vector3.ZERO


# t runs 0..SHOW_TIME: look in, rear up, beat the chest, roar, come back down. `turn` is how far the head
# turns toward the room (the figure in your hand keeps looking straight at you). Returns how far he has reared.
static func _show_pose(p: Dictionary, t: float, turn := -0.85) -> float:
	_walk_pose(p, 0.0)
	var look := _ramp(t, 0.0, 1.0) * (1.0 - _ramp(t, SHOW_TIME - 1.0, SHOW_TIME))
	var rear := _ramp(t, 1.0, 1.8) * (1.0 - _ramp(t, 6.0, 7.0))
	var beat := _ramp(t, 1.8, 2.0) * (1.0 - _ramp(t, 3.3, 3.5))
	var roar := _ramp(t, 3.4, 3.8) * (1.0 - _ramp(t, 5.6, 6.1))
	(p["body"] as Node3D).rotation = Vector3(-0.5 * rear, 0.0, 0.0)          # front end rises, pivoting at the hips
	(p["head"] as Node3D).rotation = Vector3(0.45 * rear - 0.25 * roar, turn * look, 0.0)   # toward the room, level while reared
	(p["jaw"] as Node3D).rotation = Vector3(0.55 * roar + 0.04 * roar * sin(t * 30.0), 0.0, 0.0)
	(p["tail"] as Node3D).rotation = Vector3(0.25 * rear, 0.15 * sin(t * 2.0) * rear, 0.0)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var hit := 0.5 + 0.5 * sin(t * 14.0 + (0.0 if i == 0 else PI))       # left, right, left, right
		# upper arms forward, forearms folded up so the fists land on his chest
		(p["arms"][i] as Node3D).rotation = Vector3(0.8 * rear - 0.25 * beat * hit, 0.0, -0.4 * side * rear)
		(p["elbows"][i] as Node3D).rotation = Vector3(-1.9 * rear + 0.3 * beat * hit, 0.0, 0.0)
		(p["legs"][i] as Node3D).rotation = Vector3(0.35 * rear, 0.0, 0.0)  # thighs tuck under him
		(p["knees"][i] as Node3D).rotation = Vector3(-0.25 * rear, 0.0, 0.0)
	return rear


static func _ramp(t: float, a: float, b: float) -> float:
	return smoothstep(a, b, t)


func _show(delta: float) -> void:
	var was := _show_t
	_show_t += delta
	var rear := _show_pose(_gr, _show_t)
	# rearing up lifts his head and pulls it back; sink him and shuffle him forward so his face stays in the window
	_g.position = STREET + Vector3(_x + REAR_SHIFT.x * rear, REAR_SHIFT.y * rear, 0.0)
	if was < 1.85 and _show_t >= 1.85:
		_beat.play()
	if was < 3.4 and _show_t >= 3.4:
		_roar.volume_db = 0.0
		_roar.play()
	# the chest beats shake the window; the roar rattles it for a while
	if _show_t > 1.85 and _show_t < 3.3 and int(was * 7.0) != int(_show_t * 7.0):
		_jolt(0.45)
	if _show_t > 3.5 and _show_t < 5.6 and int(was * 3.0) != int(_show_t * 3.0):
		_jolt(0.35)
	if _show_t >= SHOW_TIME:
		_shown = true


func _footfall() -> void:
	var dist := absf(_x + HEAD_X + 1.4)
	var near := clampf(1.0 - dist / 40.0, 0.35, 1.0)
	_thump.volume_db = linear_to_db(near * 0.9)
	_thump.pitch_scale = _rng.randf_range(0.95, 1.12)
	_thump.play()
	_jolt(near * 0.85)


func _jolt(near: float) -> void:
	if main.kaiju != null:
		main.kaiju.jolt(near)


# ---- the figure on the bookshelf: pick it up and he shows off in your hand

var _toy: Node3D
var _tp := {}
var _toy_plays := 0
var _toy_t := -1.0                   # time since it was picked up (-1 = on the shelf)
const TOY_HOLD := 4.2                # how long he stays in your hand
const TOY_HOME_YAW := PI + 0.35      # facing out into the room


func _build_toy() -> void:
	_toy = Model.build()
	_toy.scale = Vector3.ONE * TOY_SCALE
	_toy.position = TOY_POS + Vector3(0, 0.012, 0)
	_toy.rotation.y = TOY_HOME_YAW
	main.room.add_child(_toy)
	_tp = _parts(_toy)
	_walk_pose(_tp, 0.0)
	var stand := MeshInstance3D.new()            # a little round display base with a gold rim
	var cm := CylinderMesh.new()
	cm.top_radius = 0.075
	cm.bottom_radius = 0.08
	cm.height = 0.012
	stand.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.08, 0.07, 0.1)
	sm.roughness = 0.4
	sm.rim_enabled = true
	sm.rim = 0.5
	stand.material_override = sm
	stand.position = TOY_POS + Vector3(0, 0.006, 0)
	main.room.add_child(stand)
	var hit := Node3D.new()
	hit.position = TOY_POS + Vector3(0, 0.1, 0)
	main.room.add_child(hit)
	main.interactables.append({"node": hit, "half": Vector3(0.12, 0.11, 0.12), "guest_ok": true,
		"label": func() -> String: return "KING GABOON" if not active else "KING GABOON  (he's here)", "cb": pick_up_toy})


func pick_up_toy() -> void:
	if _toy_t >= 0.0:
		return
	_toy_t = 0.0
	_toy_plays += 1
	if main.fight != null and main.fight.toy_played("gaboon"):
		_toy_plays = 0                                    # the T-Rex was played with too: they fight instead


func _toy_process(delta: float) -> void:
	if _toy_t < 0.0:
		return
	var was := _toy_t
	_toy_t += delta
	var k := 1.0 - exp(-8.0 * delta)
	if _toy_t < TOY_HOLD:
		# in front of you, a little low, facing you
		var hx: Transform3D = main.head.global_transform
		var fwd := -hx.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var xa := -fwd                                   # the figure faces +x: turn +x toward you
		var b := Basis(xa, Vector3.UP, xa.cross(Vector3.UP)).scaled(Vector3.ONE * TOY_SCALE)
		var target := Transform3D(b, hx.origin + fwd * 0.42 + Vector3(0, -0.16, 0))
		_glide(_toy, target, k)
		# the show, sped up to fit in your hand
		var st := clampf((_toy_t - 0.4) * 1.9, 0.0, SHOW_TIME - 0.01)
		_show_pose(_tp, st, 0.0)
		if was < 0.4 + 3.4 / 1.9 and _toy_t >= 0.4 + 3.4 / 1.9:
			_squeak.play()
	else:
		var home := Transform3D(Basis(Vector3.UP, TOY_HOME_YAW).scaled(Vector3.ONE * TOY_SCALE), main.room.global_transform * (TOY_POS + Vector3(0, 0.012, 0)))
		_glide(_toy, home, k)
		_walk_pose(_tp, 0.0)
		if _toy.global_position.distance_to(home.origin) < 0.004:
			_toy.global_transform = home
			_toy_t = -1.0
			if _toy_plays >= TOY_PLAYS:
				_toy_plays = 0
				_call_the_real_one()


func _call_the_real_one() -> void:
	await get_tree().create_timer(1.2).timeout
	request_walk()


static func _glide(n: Node3D, t: Transform3D, k: float) -> void:
	var cur := n.global_transform
	var sc := t.basis.get_scale()
	var q := cur.basis.get_rotation_quaternion().slerp(t.basis.get_rotation_quaternion(), k)
	n.global_transform = Transform3D(Basis(q).scaled(sc), cur.origin.lerp(t.origin, k))


# ---- shared rooms

func state() -> int:
	return count


func apply_remote(n: int) -> void:
	if n > count:
		count = n
		start()


# ---- sounds, made here

# a big ape roar: a growling throat that climbs, holds and falls, with breath over it
static func _make_roar() -> AudioStreamWAV:
	var rate := 22050
	var n := int(2.6 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var ph := 0.0
	var lp := 0.0
	var bp := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 70.0 + 55.0 * smoothstep(0.0, 0.5, t) - 40.0 * smoothstep(1.4, 2.6, t)
		f *= 1.0 + 0.03 * sin(t * 37.0)
		ph += f / rate
		var saw := 2.0 * fmod(ph, 1.0) - 1.0
		var throat := saw * (0.65 + 0.35 * sin(t * 47.0)) + 0.5 * sin(ph * TAU * 2.0)
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.25
		bp += (lp - bp) * 0.08
		var breath := (lp - bp) * 2.2
		var env := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(1.8, 2.6, t))
		var s := (throat * 0.6 + breath * 0.5) * env
		s = s / (1.0 + absf(s) * 0.8)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	return KaijuScript._wav(data, rate)


# hollow thumps on a big chest, quick and alternating
static func _make_chest_beat() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.6 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var hits := 7
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		for h in hits:
			var t0 := h * 0.215
			var dt := t - t0
			if dt >= 0.0 and dt < 0.3:
				var f := 95.0 + 40.0 * exp(-dt * 30.0) + (8.0 if h % 2 else 0.0)
				s += sin(TAU * f * dt) * exp(-dt * 16.0) * (0.9 if h % 2 else 1.0)
		s = s / (1.0 + absf(s) * 0.3)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	return KaijuScript._wav(data, rate)
