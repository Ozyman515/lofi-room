extends Node3D
## The cats (an easter egg). Two of them, both cozy_cat.gd:
##  - the tuxedo comes when called: open the nightstand drawer and shake the bag of treats. A moment later
##    the door creaks, and soon after it's asleep at the foot of the bed.
##  - the calico just turns up now and then (1 visit in 10, 1 in 4 late at night): asleep on the rug at the
##    foot of the bed, in a beanbag, or on top of the console. On the console it's in the way: pick it up and
##    put it on the bed. In a beanbag, it hops off to the bed when you sit there.
## Both can be petted (the diary keeps count). When both are on the bed they curl up together.
## In a shared room the host's cats are the ones everybody sees; a guest's pets, treats and moves go to the host.

const CozyCat := preload("res://cozy_cat.gd")
const CatFrames := preload("res://cat_frames.gd")
const CFG := "user://lofi_room.cfg"
const DEFAULT_NAMES := {"tux": "Kitty", "calico": "Lola"}     # the black one is Kitty, the calico Lola
const Diary := preload("res://diary.gd")

const CALICO_CHANCE := 0.10
const CALICO_CHANCE_NIGHT := 0.25         # between 11 pm and 5 am
const CAL_SPOTS := ["rug", "beanbag", "console"]
const BED_SOLO := Vector2(-1.40, -0.02)  # x, z on the bed near the foot
const BED_TUX := Vector2(-1.50, -0.12)   # together: the tux on the left...
const BED_CAL := Vector2(-1.25, -0.06)   # ...the calico snuggled against its tail, both faces toward the room
const RUG := Vector3(-0.98, 0.0, 0.34)   # on the floor just past the foot of the bed (the icon's cat)
const FACE_ROOM := 1.43                   # a cat's yaw that turns its face toward the middle of the room

var main: Node3D
var tux: Node3D
var calico: Node3D
var tux_here := false
var cal_spot := ""                        # "", "rug", "beanbag", "console", "bed"
var carrying := false                     # holding the calico (to take it off the console)
var _tux_coming := false
var _own := {}                            # my own cats' state while a host's are shown
var _remote := false
var _bag: Node3D
var _sfx: AudioStreamPlayer3D
var _door_sfx: AudioStreamPlayer3D
var _items: Array = []
var frames: Node3D                        # cat_frames.gd: the photos on the dresser
var _names := {}                          # my names for them
var _host_names := {}                     # the host's, while their cats are shown
var _unlocked := {}                       # "tux", "calico", "both" -> met

static var _rustle: AudioStreamWAV
static var _creak: AudioStreamWAV


func setup(m: Node3D) -> void:
	main = m
	_load_names()
	tux = CozyCat.new()
	tux.coat = "tux"
	tux.name = "TuxedoCat"
	tux.visible = false
	main.room.add_child(tux)
	calico = CozyCat.new()
	calico.coat = "calico"
	calico.name = "CalicoCat"
	calico.visible = false
	main.room.add_child(calico)
	_build_treats()
	_door_sfx = AudioStreamPlayer3D.new()
	if _creak == null:
		_creak = _make_creak()
	_door_sfx.stream = _creak
	_door_sfx.unit_size = 3.0
	_door_sfx.position = Vector3(0.9, 1.0, main.FRONT_Z - 0.1)
	main.room.add_child(_door_sfx)
	# pointing at a cat: pet it (or, on the console, pick it up)
	for c in [tux, calico]:
		var cat: Node3D = c
		var hit := Node3D.new()                     # the pointer box sits on the curl, not half under the bed
		hit.position = Vector3(0, 0.07, 0)
		cat.add_child(hit)
		var it := {"node": hit, "half": Vector3(0.17, 0.08, 0.17), "guest_ok": true,
			"when": func() -> bool: return cat.visible and not (cat == calico and carrying),
			"label": func() -> String: return _cat_label(cat), "cb": func() -> void: _cat_click(cat)}
		main.interactables.append(it)
	# while carrying the calico: the whole bed top says "put it here"
	var bed_hit := Node3D.new()
	bed_hit.position = Vector3(-1.65, 0.62, -0.9)
	main.room.add_child(bed_hit)
	main.interactables.append({"node": bed_hit, "half": Vector3(0.84, 0.16, 1.06), "guest_ok": true,
		"when": func() -> bool: return carrying,
		"label": func() -> String: return "PUT %s ON THE BED" % name_of("calico").to_upper(), "cb": put_on_bed})
	# who's visiting today
	var forced := OS.get_environment("LOFI_CATS")       # testing: "tux", "calico:console", "tux,calico:bed" ...
	if forced != "":
		for part in forced.split(","):
			if part.begins_with("tux"):
				tux_here = true
			elif part.begins_with("calico"):
				cal_spot = part.get_slice(":", 1) if part.contains(":") else "rug"
	else:
		var h := Time.get_datetime_dict_from_system()["hour"] as int
		var chance := CALICO_CHANCE_NIGHT if (h >= 23 or h < 5) else CALICO_CHANCE
		if randf() < chance:
			cal_spot = CAL_SPOTS[randi() % CAL_SPOTS.size()]
	frames = CatFrames.new()
	frames.name = "CatFrames"
	add_child(frames)
	frames.setup(main, self)
	layout()


# ---- names, and which cats you've met (the frames on the dresser fill in as you do)

func _load_names() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	for k in ["tux", "calico"]:
		_names[k] = str(cf.get_value("cats", "name_" + k, DEFAULT_NAMES[k]))
	for k in ["tux", "calico", "both"]:
		_unlocked[k] = bool(cf.get_value("cats", "met_" + k, false))


func default_name(which: String) -> String:
	return DEFAULT_NAMES.get(which, "Cat")


func name_of(which: String) -> String:
	if _remote and _host_names.has(which):
		return str(_host_names[which])
	return str(_names.get(which, default_name(which)))


func set_name_of(which: String, n: String) -> void:
	_names[which] = n
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("cats", "name_" + which, n)
	cf.save(CFG)
	if frames != null:
		frames.refresh()


func is_unlocked(which: String) -> bool:
	return bool(_unlocked.get(which, false))


func _meet(which: String) -> void:
	if is_unlocked(which):
		return
	_unlocked[which] = true
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("cats", "met_" + which, true)
	cf.save(CFG)
	if frames != null:
		frames.refresh()


func showing_hosts_cats() -> bool:
	return _remote


# ---- where everybody is

func layout() -> void:
	tux.visible = tux_here
	calico.visible = cal_spot != "" or carrying
	var together := tux_here and cal_spot == "bed"
	if tux_here:
		_meet("tux")
	if cal_spot != "" or carrying:
		_meet("calico")
	if together:
		_meet("both")
	if tux_here:
		_put(tux, _bed_point(BED_TUX if together else BED_SOLO), FACE_ROOM)
	if carrying:
		return
	match cal_spot:
		"bed":
			if together:
				_put(calico, _bed_point(BED_CAL), FACE_ROOM - 0.7)
			else:
				_put(calico, _bed_point(BED_SOLO), FACE_ROOM)
		"rug":
			_put(calico, RUG, 2.3)
		"console":
			var con: Node3D = main.console_root
			_put(calico, con.to_global(Vector3(0.0, main.CON_TOP, 0.0)), con.global_rotation.y + 0.4)
		"beanbag":
			# down in the bowl, which is pressed in at a tilt toward the front (beanbag_model.gd's AXIS)
			var bb: Node3D = main.beanbags[0]
			_put(calico, bb.to_global(Vector3(0.0, 0.385, 0.10)), 0.0)
			calico.global_basis = bb.global_basis * Basis(Vector3.RIGHT, -0.45) * Basis(Vector3.UP, PI * 0.8)


func _put(cat: Node3D, pos: Vector3, yaw: float) -> void:
	var home: Node3D = main.apartment.room_node_at(pos.x, pos.z) if main.apartment != null else main.room
	if cat.get_parent() != home:
		cat.get_parent().remove_child(cat)
		home.add_child(cat)
		cat.scale = Vector3.ONE
	cat.global_position = pos
	cat.global_rotation = Vector3(0.0, yaw, 0.0)


func _bed_point(p: Vector2) -> Vector3:
	var spot := Vector3(p.x, 0.0, p.y)
	var y: float = main._top_of(main.bed_node, spot, 0.6) if main.bed_node != null else 0.68
	return Vector3(p.x, y - 0.015, p.y)


# the calico on the console is in the way of the carts and the power button
func blocks_console() -> bool:
	return cal_spot == "console" and not carrying


func _process(_delta: float) -> void:
	# sitting down in the beanbag the calico is sleeping in: it hops off to the bed
	if cal_spot == "beanbag" and main.seated and main.cur_seat >= 0 and main.cur_seat < main.seat_nodes.size() \
			and main.seat_nodes[main.cur_seat] == main.beanbags[0] and not _remote:
		cal_spot = "bed"
		layout()
		main.updater.show_toast("%s hops off to the bed." % name_of("calico"), 3.0)
	if carrying:
		_hold_pose()


# ---- petting, carrying

func _cat_label(cat: Node3D) -> String:
	var name := name_of("tux" if cat == tux else "calico").to_upper()
	if cat == calico and cal_spot == "console":
		return "PICK UP %s  (asleep on the console)" % name
	return "PET THE %s" % name + ("  (purring)" if cat.is_petted() else "")


func _cat_click(cat: Node3D) -> void:
	if cat == calico and cal_spot == "console":
		if _remote:
			main.net_game.net.send_var(1, main.net_game.Net.K_EVENT, {"k": "cat_bed"})     # the host moves it
		else:
			pick_up()
		return
	pet(cat == tux)


func pet(is_tux: bool, from_net := false) -> void:
	var cat: Node3D = tux if is_tux else calico
	if not cat.visible:
		return
	cat.pet()
	if from_net:
		return
	Diary.cat_petted("tux" if is_tux else "calico")
	var ng = main.net_game
	if ng != null and ng.net.is_online():
		var d := {"k": "cat_pet", "w": "t" if is_tux else "c"}
		if ng.net.is_host():
			for id in ng.net.peer_ids():
				ng.net.send_var(id, ng.Net.K_EVENT, d)
		else:
			ng.net.send_var(1, ng.Net.K_EVENT, d)


func pick_up() -> void:
	if cal_spot != "console" or carrying:
		return
	carrying = true
	var parent: Node3D = main.right_hand if main.xr_active else main.desktop_cam
	calico.get_parent().remove_child(calico)
	parent.add_child(calico)
	calico.scale = Vector3.ONE * (1.0 if main.xr_active else 0.8)
	_hold_pose()
	main.updater.show_toast("Point at the bed and click to put %s down." % name_of("calico"), 4.0)


func _hold_pose() -> void:
	if main.xr_active:
		calico.position = Vector3(0.0, -0.06, -0.16)
		calico.rotation = Vector3(0.0, PI * 0.5, 0.0)
	else:
		calico.position = Vector3(0.0, -0.30, -0.55)
		calico.rotation = Vector3(0.35, PI * 0.5, 0.0)


func put_on_bed() -> void:
	if not carrying and cal_spot != "console":
		return
	carrying = false
	cal_spot = "bed"
	layout()
	calico.pet()                           # it settles in with a purr


# ---- the treats

func _build_treats() -> void:
	_bag = Node3D.new()
	_bag.position = Vector3(0.07, -0.035, -0.12)
	_bag.rotation.y = 0.3
	main.drawer_node.add_child(_bag)
	var foil := StandardMaterial3D.new()
	foil.albedo_color = Color(0.25, 0.55, 0.85)
	foil.metallic = 0.6
	foil.roughness = 0.35
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.05, 0.035)
	var body := MeshInstance3D.new()
	body.mesh = bm
	body.material_override = foil
	_bag.add_child(body)
	var top := MeshInstance3D.new()                 # the crimped top
	var tm := BoxMesh.new()
	tm.size = Vector3(0.092, 0.01, 0.012)
	top.mesh = tm
	top.material_override = foil
	top.position = Vector3(0, 0.03, 0)
	_bag.add_child(top)
	var lbl := Label3D.new()
	lbl.text = "TREATS"
	lbl.font_size = 22
	lbl.pixel_size = 0.0006
	lbl.outline_size = 0
	lbl.modulate = Color(1.0, 0.85, 0.3)
	lbl.position = Vector3(0, 0.0, 0.0182)
	_bag.add_child(lbl)
	_sfx = AudioStreamPlayer3D.new()
	if _rustle == null:
		_rustle = _make_rustle()
	_sfx.stream = _rustle
	_sfx.unit_size = 1.5
	_bag.add_child(_sfx)
	main.interactables.append({"node": body, "half": Vector3(0.06, 0.04, 0.04), "guest_ok": true,
		"when": func() -> bool: return main.drawer_open,
		"label": func() -> String: return "SHAKE THE TREATS", "cb": shake_treats})


func shake_treats() -> void:
	_sfx.play()
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_bag, "rotation:z", 0.25 if i % 2 == 0 else -0.25, 0.08)
	tw.tween_property(_bag, "rotation:z", 0.0, 0.08)
	if _remote:
		main.net_game.net.send_var(1, main.net_game.Net.K_EVENT, {"k": "cat_treats"})
		return
	call_tux()


# the tux heard the bag: the door creaks, then it's on the bed
func call_tux() -> void:
	if tux_here:
		tux.pet()                       # already here: an ear twitch and a purr
		return
	if _tux_coming:
		return
	_tux_coming = true
	await get_tree().create_timer(3.5).timeout
	_door_sfx.play()
	await get_tree().create_timer(3.0).timeout
	_tux_coming = false
	tux_here = true
	if cal_spot == "rug" or cal_spot == "beanbag":
		cal_spot = "bed"                # the calico joins it
	layout()
	tux.pet()


# Debug window: call / place the cats without waiting for luck
func debug_set(what: String) -> void:
	if _remote:
		return
	match what:
		"tux":
			call_tux()
		"none":
			if carrying:
				carrying = false
			tux_here = false
			cal_spot = ""
			layout()
		_:
			if carrying:
				put_on_bed()
			cal_spot = what
			layout()


# ---- shared rooms: the host's cats

func state() -> Dictionary:
	return {"t": tux_here, "c": cal_spot, "carry": carrying, "n": {"tux": _names.get("tux", ""), "calico": _names.get("calico", "")}}


func apply_remote(d: Dictionary) -> void:
	if not _remote:
		_own = {"t": tux_here, "c": cal_spot}
		if carrying:
			put_on_bed()
		_remote = true
	tux_here = bool(d.get("t", false))
	var hn = d.get("n", {})
	_host_names = {}
	if hn is Dictionary:
		for k in ["tux", "calico"]:
			var nm := str(hn.get(k, "")).strip_edges().left(12)
			if nm != "":
				_host_names[k] = nm
	var c := str(d.get("c", ""))
	cal_spot = c if c in ["", "rug", "beanbag", "console", "bed"] else ""
	if bool(d.get("carry", false)) and cal_spot == "console":
		cal_spot = "console"                # the host is carrying it: still shows where it was until it lands
	layout()


func end_remote() -> void:
	if not _remote:
		return
	_remote = false
	_host_names = {}
	tux_here = bool(_own.get("t", false))
	cal_spot = str(_own.get("c", ""))
	layout()


# host side: a guest asked
func on_guest_event(d: Dictionary) -> void:
	match str(d.get("k", "")):
		"cat_pet":
			pet(str(d.get("w", "t")) == "t", true)
		"cat_treats":
			call_tux()
		"cat_bed":
			if cal_spot == "console" and not carrying:
				put_on_bed()


# ---- sounds, made here

static func _make_rustle() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.75 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hp := 0.0
	var last := 0.0
	for i in n:
		var t := float(i) / rate
		var shake := fmod(t, 0.17) / 0.17                 # four shakes: a crinkle and the kibble rattling
		var env := exp(-shake * 7.0) * (1.0 if t < 0.68 else (0.75 - t) / 0.07)
		var x := rng.randf_range(-1.0, 1.0)
		hp = 0.6 * (hp + x - last)                          # bright, crinkly
		last = x
		var tick := 0.0
		if rng.randf() < 0.004 * env:
			tick = rng.randf_range(0.5, 1.0)                # a bit of kibble hitting the foil
		var s := clampf((hp * 0.5 + tick) * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 26000.0))
	return _wav(data, rate)


static func _make_creak() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.3 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / rate
		var f := 160.0 + 120.0 * sin(t * 2.2) + 40.0 * sin(t * 17.0)      # a slow wobbling hinge
		ph += f / rate
		var saw := 2.0 * fmod(ph, 1.0) - 1.0
		var stick := 1.0 if fmod(ph, 1.0) < 0.15 else 0.3                  # stick-slip: a buzzy edge
		lp += (saw * stick + rng.randf_range(-0.2, 0.2) - lp) * 0.25
		var env := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(1.0, 1.3, t))
		data.encode_s16(i * 2, int(clampf(lp * env * 0.6, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
