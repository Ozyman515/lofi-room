extends Node
## Breaking news: while the T-Rex and King Gaboon fight (fight.gd), the TV cuts in with a live report. An
## old-school 1950s newsman stands on a rooftop with the fight going on behind him, chrome microphone in hand,
## and talks you through it; the broadcast cuts between him and the station's cameras on other rooftops.
## Lower third: CH 3 NEWS, LIVE, what he's saying, and a ticker. His words are in the caption (no fake voice);
## the broadcast plays a news sting and a faint line hiss on the TV's sound (speakers set to TV carry it too).
## The picture is a small SubViewport looking at the same city (240 lines, like the CRT; the headset renders it
## at a lower rate). He and his rooftop are on visual layer 3, which only the news camera sees.
## The TV is borrowed only when it isn't busy with a game: a playing tape pauses and resumes afterwards, and a
## TV that was off switches itself on for the broadcast and back off after.
## Besides the fight, a short bulletin goes out when Banira or King Gaboon walks past on its own. And the station
## cuts away to interviews, which is how the monsters got their names: an ice cream vendor calling out his flavours
## (the reporter takes "banira" for the creature's name), a big-game hunter who has tracked King Gaboon for twenty
## years, and the grey visitor, who knows Jogari. Each has its own little set on the reporter's layer.

const Plat := preload("res://platform.gd")
const LAYER := 4                     # visual layer 3 (bit value 4): the reporter, his roof and his light
const SIZE := Vector2i(320, 240)

var main: Node3D
var fight: Node3D
var on_air := false
var _vp: SubViewport
var _cam: Camera3D
var _rep: Node3D                     # the reporter (and his bit of roof)
var _rp := {}                        # his moving parts
var _rep_light: OmniLight3D
var _caption: Label
var _ticker: Label
var _live: Label
var _where: Label
var _line := ""
var _shown := 0.0
var _speak := 0.0                    # > 0 while he is talking
var _shot := "rep"
var _shot_t := 0.0
var _next_cut := 0.0
var _field := 0
var _T := 0.0
var _frame := 0
var _was_tv_on := true
var _paused_tape := false
var _audio := {}                     # TV bus -> [hiss, sting]
var _tvs: Array = []                 # the TVs showing the broadcast: {vcr, mat, bus, was_on, paused}
var _rng := RandomNumberGenerator.new()
var _end_t := -1.0
var _look := 0.0                     # how far he has turned to look back at the fight
var _duck := 0.0
var _queued := ""                    # a moment that happened during his opening words

const SPOT := Vector3(-30.0, 0.0, -30.0)     # his rooftop, off to one side, the fight beyond it
const SETS := Vector3(-300.0, 140.0, -300.0)   # the interview sets, out of everyone's way (only the news camera sees them)

var _kind := "fight"                 # "fight", or a bulletin: "k" (Banira walking past) or "g" (King Gaboon)
var _sets := {}                      # who -> {"root", "p" (moving parts), "cam" [from, at]}
var _iv := ""                        # the interview on the air now
var _iv_i := 0
var _iv_t := 0.0
var _iv_dur := 0.0
var _iv_talk := false
var _iv_queue: Array = []            # [at _T, who]
var _named := {}                     # "k" / "g" / "b": the station knows its name now
var _sub := ""                       # a translation under the caption


func setup(m: Node3D, f: Node3D) -> void:
	main = m
	fight = f
	fight.moment.connect(_on_moment)
	if main.kaiju != null:
		main.kaiju.walked.connect(func() -> void: _start("k"))
	if main.gaboon != null:
		main.gaboon.walked.connect(func() -> void: _start("g"))
	_rng.randomize()
	set_process(false)


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = SIZE if not Plat.low_power() else Vector2i(256, 192)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.world_3d = main.get_viewport().world_3d          # the same city
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.cull_mask = 0xFFFFF
	_cam.fov = 50.0
	_cam.far = 900.0
	_vp.add_child(_cam)
	# nobody else's camera sees the reporter's layer
	for c in [main.desktop_cam, main.head]:
		if c is Camera3D:
			(c as Camera3D).cull_mask &= ~LAYER
	_build_reporter()
	_build_sets()
	_build_overlay()
	# the sting and the line hiss, on each TV's own sound (heard from whichever TVs are showing the news)
	var hiss := _make_hiss()
	var sting := _make_sting()
	for bus in ["TV", "TV_living", "TV_theater"]:
		var h := AudioStreamPlayer.new()
		h.stream = hiss
		h.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
		h.volume_db = -26.0
		add_child(h)
		var st := AudioStreamPlayer.new()
		st.stream = sting
		st.bus = h.bus
		st.volume_db = -6.0
		add_child(st)
		_audio[bus] = [h, st]


# ---- the newsman: dark suit, white shirt, thin tie, slicked-back hair going grey at the temples, heavy brows,
# a chrome microphone on a cable. Built from simple rounded shapes; faces +z.

func _build_reporter() -> void:
	_rep = Node3D.new()
	main.outside.add_child(_rep)
	_rep.visible = false
	var roof_y := 33.0                         # the tallest tower downtown, above the other roofs
	_rep.position = SPOT + Vector3(0, roof_y, 0)
	var suit := _mat(Color(0.13, 0.13, 0.15), 0.8)
	var shirt := _mat(Color(0.9, 0.9, 0.88), 0.7)
	var tie := _mat(Color(0.08, 0.08, 0.1), 0.6)
	var skin := _mat(Color(0.82, 0.66, 0.55), 0.6)
	var hair := _mat(Color(0.12, 0.11, 0.11), 0.5)
	var grey := _mat(Color(0.55, 0.55, 0.56), 0.6)
	var chrome := _mat(Color(0.8, 0.82, 0.85), 0.15)
	chrome.metallic = 1.0
	var dark := _mat(Color(0.05, 0.05, 0.05), 0.5)
	var roofm := _mat(Color(0.22, 0.2, 0.24), 0.9)
	# a bit of roof under him, a parapet and an aerial behind
	_box(_rep, Vector3(0, -0.15, -1.0), Vector3(8.0, 0.3, 6.0), roofm)
	var tower := _mat(Color(0.16, 0.14, 0.24), 0.9)
	_box(_rep, Vector3(0, -(roof_y + 40.0) * 0.5 - 0.3, -1.0), Vector3(8.0, roof_y + 40.0, 6.0), tower)
	_box(_rep, Vector3(0, 0.4, -3.6), Vector3(8.0, 0.8, 0.3), roofm)
	_box(_rep, Vector3(2.6, 2.0, -3.4), Vector3(0.08, 4.0, 0.08), dark)
	var p := _person(_rep, {"skin": skin.albedo_color, "legs": suit.albedo_color, "shoes": dark.albedo_color, "jacket": suit.albedo_color,
		"shirt": shirt.albedo_color, "tie": tie.albedo_color, "hair": hair.albedo_color, "temples": grey.albedo_color,
		"brows": Color(0.1, 0.09, 0.09), "eyes": Color(0.2, 0.25, 0.3)})
	(p["man"] as Node3D).name = "Man"
	# the right hand holds the microphone up under his chin; its cable hangs down
	(p["arm_r"] as Node3D).rotation = Vector3(-0.3, 0.0, -0.2)
	(p["fore_r"] as Node3D).rotation = Vector3(-2.45, 0.0, 0.0)
	var mic := Node3D.new()
	mic.position = Vector3(-0.01, -0.07, 0.035)
	(p["hand_r"] as Node3D).add_child(mic)
	_cap(mic, Vector3(0, -0.05, 0), 0.016, 0.16, chrome)
	_ell(mic, Vector3(0, -0.15, 0.0), Vector3(0.036, 0.045, 0.036), chrome)                  # the round head
	_box(mic, Vector3(0, -0.15, 0.03), Vector3(0.05, 0.005, 0.006), dark)                    # its grille bar
	_cap(mic, Vector3(0.0, 0.1, -0.02), 0.007, 0.2, dark)                                   # the cable
	var body: Node3D = p["man"]
	var torso: Node3D = p["torso"]
	var head: Node3D = p["head"]
	var mouth: MeshInstance3D = p["mouth"]
	var arm_l: Node3D = p["arm_l"]
	var fore_l: Node3D = p["fore_l"]
	var arm_r: Node3D = p["arm_r"]
	for n in _rep.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).layers = LAYER
	_rp = {"man": body, "torso": torso, "head": head, "mouth": mouth, "arm_l": arm_l, "fore_l": fore_l, "arm_r": arm_r}
	# the camera crew's light on him (lights only his layer)
	_rep_light = OmniLight3D.new()
	_rep_light.light_cull_mask = LAYER
	_rep_light.omni_range = 9.0
	_rep_light.light_energy = 2.2
	_rep_light.light_color = Color(1.0, 0.95, 0.85)
	_rep_light.position = Vector3(0.8, 2.4, 3.0)
	_rep.add_child(_rep_light)
	# he faces the camera, which stands in front of him with the fight beyond his shoulder
	_rep.look_at(_rep.global_position + (_rep.global_position - _fight_centre()).normalized() * Vector3(1, 0, 1), Vector3.UP)
	_rep.rotate_y(PI)


func _fight_centre() -> Vector3:
	return Vector3(fight.CX, 35.0, fight.Z)


# ---- the picture's overlay: LIVE bug, station name, caption and a ticker

func _build_overlay() -> void:
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(ui)
	var w := float(_vp.size.x)
	var h := float(_vp.size.y)
	var k := w / 320.0
	var band := ColorRect.new()
	band.color = Color(0.05, 0.08, 0.25, 0.85)
	band.position = Vector2(0, h - 58 * k)
	band.size = Vector2(w, 40 * k)
	ui.add_child(band)
	var tick_band := ColorRect.new()
	tick_band.color = Color(0.75, 0.08, 0.08, 0.95)
	tick_band.position = Vector2(0, h - 18 * k)
	tick_band.size = Vector2(w, 18 * k)
	ui.add_child(tick_band)
	_where = _lab(ui, "CH 3 NEWS  -  DOWNTOWN", Vector2(6 * k, h - 57 * k), 9 * k, Color(1.0, 0.85, 0.3))
	_caption = _lab(ui, "", Vector2(6 * k, h - 46 * k), 10 * k, Color.WHITE)
	_caption.size = Vector2(w - 12 * k, 30 * k)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ticker = _lab(ui, "", Vector2(w, h - 16 * k), 10 * k, Color.WHITE)
	_live = _lab(ui, "LIVE", Vector2(w - 44 * k, 6 * k), 11 * k, Color.WHITE)
	var bug := ColorRect.new()
	bug.color = Color(0.8, 0.05, 0.05, 0.9)
	bug.position = Vector2(w - 48 * k, 5 * k)
	bug.size = Vector2(42 * k, 16 * k)
	ui.add_child(bug)
	ui.move_child(bug, _live.get_index())
	_lab(ui, "CH3", Vector2(6 * k, 5 * k), 11 * k, Color(1, 1, 1, 0.7))


func _lab(parent: Control, text: String, pos: Vector2, size: float, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", int(maxf(size, 7.0)))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 2)
	parent.add_child(l)
	return l


# ---- going on and off the air

func _start(kind := "fight") -> void:
	if on_air:
		return
	if _vp == null:
		_build()
	# every TV that isn't busy carries it: the CRT (unless a game or a guest's tape is on it), the Big TV, the
	# Theater Screen
	_tvs.clear()
	if not (main.console_on or main.vcr.remote_video):
		_tvs.append({"vcr": main.vcr, "mat": main.tv_mat, "bus": "TV"})
	if main.apartment != null:
		for rt in [main.apartment.liv_tv, main.apartment.th_tv]:
			if rt != null:
				_tvs.append({"vcr": rt.vcr, "mat": rt.own_mat, "bus": rt.bus})
	if _tvs.is_empty():
		return
	on_air = true
	_kind = kind
	_iv = ""
	_iv_queue.clear()
	_T = 0.0
	_end_t = -1.0
	_rep.visible = true
	for t in _tvs:
		var v = t["vcr"]
		t["was_on"] = v.tv_on
		if not v.tv_on:
			v.toggle_tv()                                 # it clicks on by itself
		t["paused"] = v.state == v.State.PLAYING and not v._paused_flag
		if t["paused"]:
			v._set_paused(true)
		v._show_status("")
		v._osd_show("BREAKING NEWS", 3.0)
		var au: Array = _audio.get(t["bus"], [])
		if au.size() == 2:
			(au[1] as AudioStreamPlayer).play()
			(au[0] as AudioStreamPlayer).play()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_where.text = WHERE
	match kind:
		"k":
			_ticker.text = "  BULLETIN: GIANT CREATURE SIGHTED DOWNTOWN  *  KEEP AWAY FROM WINDOWS  *  ICE CREAM VENDORS REPORT BRISK TRADE  *  STAY TUNED TO CH 3  *"
			_cut("rep", 6.0)
			_say(_pick(LINES["b_open_k"]), 6.0)
			_iv_queue = [[13.0, "vendor"]]
		"g":
			_ticker.text = "  BULLETIN: GIANT MONKEY ON THE LOOSE  *  ZOO SAYS 'NOT OURS'  *  HUNTER ARRIVES AT THE DOCKS  *  STAY TUNED TO CH 3  *"
			_cut("rep", 6.0)
			_say(_pick(LINES["b_open_g"]), 6.0)
			_iv_queue = [[13.0, "hunter"]]
		_:
			_ticker.text = "  BREAKING: TWO GIANT MONSTERS CLASH DOWNTOWN  *  RESIDENTS URGED TO STAY INDOORS  *  BRIDGES CLOSED  *  NEWS CHOPPERS ON THE SCENE  *  STAY TUNED TO CH 3  *"
			_cut("rep", 10.0)
			_say("We interrupt this program for a special bulletin. I'm on a rooftop downtown, and something enormous is moving out there.", 7.0)
			_iv_queue = [[30.0, "vendor"], [68.0, "hunter"]]
	set_process(true)


func _stop() -> void:
	on_air = false
	set_process(false)
	_rep.visible = false
	_iv = ""
	for w in _sets:
		(_sets[w]["root"] as Node3D).visible = false
	for b in _audio:
		(_audio[b][0] as AudioStreamPlayer).stop()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for t in _tvs:
		var v = t["vcr"]
		var tm: ShaderMaterial = t["mat"]
		var vt: Texture2D = v.current_frame_texture()
		if vt != null:
			tm.set_shader_parameter("video_tex", vt)
		tm.set_shader_parameter("use_video", v.state == v.State.PLAYING)
		if t["paused"]:
			v._set_paused(false)
		elif v.state == v.State.IDLE:
			v._show_idle_status()
		if not t["was_on"] and v.tv_on:
			v.toggle_tv()
	_tvs.clear()


func _on_moment(kind: String) -> void:
	if kind == "start":
		_start()
		return
	if not on_air or (_kind != "fight" and kind != "end"):
		return
	if kind == "bk_arrive":
		_iv_queue.append([_T + 9.0, "visitor"])
		_iv_queue.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if kind == "end":
		_iv = ""
		_where.text = WHERE
		for w in _sets:
			(_sets[w]["root"] as Node3D).visible = false
		_cut("rep", 99.0)
		_say(_pick(LINES["signoff" if _kind == "fight" else "b_signoff"]), 6.0)
		for t in _tvs:
			var au: Array = _audio.get(t["bus"], [])
			if au.size() == 2:
				(au[1] as AudioStreamPlayer).play()
		_end_t = _T + 7.0
		return
	if kind == "enter" or _T < 8.0 or _iv != "":
		_queued = kind                                    # (after the opening words, or the interview)
		return
	if LINES.has(kind):
		var big := kind in ["tackle", "slam", "ice_beam", "fireball", "clash", "tail", "bk_arrive", "bk_neon", "ufo_swarm", "abduct"]
		if big or _rng.randf() < 0.6:
			_cut("field", _rng.randf_range(6.0, 10.0))
		_say(_pick(LINES[kind]), 6.0)
		if big:
			_duck = 1.0


func _pick(list: Array) -> String:
	return _names(str(list[_rng.randi() % list.size()]))


# Nobody is called by name until an interview has given the station that name (Banira from the ice cream vendor,
# King Gaboon from the hunter, Jogari from the visitor); until then they're the white one, the monkey, the black one.
# The lines say {K}/{k}, {G}/{g}, {B}/{b} (capitalised or not) where a name goes.
func _names(t: String) -> String:
	var k := _named.has("k")
	var g := _named.has("g")
	var b := _named.has("b")
	t = t.replace("{K}", "Banira" if k else "The white one").replace("{k}", "Banira" if k else "the white one")
	t = t.replace("{G_big}", "King Gaboon" if g else "The big monkey")
	t = t.replace("{G}", "King Gaboon" if g else "The monkey").replace("{g}", "King Gaboon" if g else "the monkey")
	t = t.replace("{B}", "Jogari" if b else "The black one").replace("{b}", "Jogari" if b else "the black one")
	if k:
		t = t.replace("The white one", "Banira").replace("the white one", "Banira").replace("the T-Rex", "Banira")
	if b:
		t = t.replace("the black one", "Jogari").replace("The black one", "Jogari")
	return t


func _say(text: String, _secs: float, sub := "") -> void:
	_line = text
	_sub = sub
	_shown = 0.0
	_speak = 0.4 + text.length() / 16.0



func _cut(shot: String, hold: float) -> void:
	_shot = shot
	_shot_t = 0.0
	_next_cut = hold
	if shot == "field":
		_field = (_field + 1 + _rng.randi() % 2) % 3


# ---- every frame on the air

func _process(delta: float) -> void:
	_T += delta
	_shot_t += delta
	if _end_t >= 0.0 and _T >= _end_t:
		_stop()
		return
	if not _subject_active() and _end_t < 0.0 and _iv == "":
		_on_moment("end")
	# an interview comes up when its time comes (not over the sign-off)
	if _iv == "" and _end_t < 0.0 and not _iv_queue.is_empty() and _T >= float(_iv_queue[0][0]):
		var who: String = _iv_queue.pop_front()[1]
		if _subject_active():
			_start_iv(who)
	if _iv != "":
		_iv_tick(delta)
	# back to the reporter now and then; out to the cameras again after
	elif _shot_t >= _next_cut:
		if _shot == "rep":
			_cut("field", _rng.randf_range(7.0, 12.0))
			if _queued != "" and LINES.has(_queued):
				_say(_pick(LINES[_queued]), 6.0)
				_queued = ""
		else:
			_cut("rep", _rng.randf_range(5.0, 8.0))
			if _speak <= 0.0:
				_say(_pick(LINES["filler" if _kind == "fight" else "b_filler"]), 6.0)
	_camera(delta)
	_animate(delta)
	# the caption types out as he speaks
	_shown = minf(_shown + delta * 22.0, _line.length())
	_caption.text = "\"" + _line.left(int(_shown)) + ("\"" if int(_shown) >= _line.length() else "") \
		+ ("\n" + _sub if _sub != "" and int(_shown) >= _line.length() else "")
	_speak -= delta

	_ticker.position.x -= delta * 40.0 * (_vp.size.x / 320.0)
	if _ticker.position.x < -_ticker.size.x:
		_ticker.position.x = _vp.size.x
	_live.visible = fmod(_T, 1.6) < 1.2
	# the headset: the news picture refreshes at half rate
	if Plat.low_power():
		_frame += 1
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if _frame % 2 == 0 else SubViewport.UPDATE_DISABLED
	# keep the TV on the broadcast (the VCR would otherwise put its own picture back)
	for t in _tvs:
		var tm: ShaderMaterial = t["mat"]
		tm.set_shader_parameter("video_tex", _vp.get_texture())
		tm.set_shader_parameter("video_aspect", float(_vp.size.x) / float(_vp.size.y))
		tm.set_shader_parameter("use_video", true)


func _camera(delta: float) -> void:
	var shake := Vector3(sin(_T * 1.7), sin(_T * 2.3 + 1.0), 0.0) * 0.02
	var c := _fight_centre()
	if _shot.begins_with("iv_"):
		# a handheld medium shot of whoever we're talking to
		var st: Dictionary = _sets[_shot.substr(3)]
		var root: Node3D = st["root"]
		_cam.global_position = root.to_global(st["cam"][0]) + shake * 1.5
		_cam.look_at(root.to_global(st["cam"][1]), Vector3.UP)
		_cam.fov = 40.0
		return
	if _kind != "fight" and _shot != "rep":
		# a bulletin: the station's rooftop cameras on the one walking past
		var who: Node3D = _subject_node()
		if who != null:
			var sc: float = main.kaiju.SCALE if _kind == "k" else main.gaboon.SCALE
			var at := who.global_position + Vector3(0, 0.75 * sc, 0)
			var spots := [Vector3(-3.0, 6.0, -2.4), Vector3(8.5, 7.5, -3.0), Vector3(2.0, 13.0, 1.5)]     # cameras on our own roof
			_cam.global_position = (spots[_field] as Vector3) + Vector3(sin(_T * 0.2) * 0.5, 0, 0) + shake * 4.0
			_cam.look_at(at, Vector3.UP)
			_cam.fov = lerpf(60.0, 42.0, smoothstep(0.0, 6.0, _shot_t))
			return
	if _shot == "rep":
		# a medium shot of him, the fight over his shoulder
		var me := _rep.global_position + Vector3(0, 1.55, 0)
		var away := (me - c)
		away.y = 0.0
		away = away.normalized()
		var side := away.cross(Vector3.UP).normalized()
		var pos := me + away * 2.6 + side * 0.7 + Vector3(0, 0.05, 0)
		_cam.global_position = pos + shake * 2.0
		_cam.look_at(me.lerp(c, 0.04), Vector3.UP)
		_cam.fov = 48.0
	else:
		var spots := [Vector3(c.x - 70.0, 48.0, -26.0), Vector3(c.x + 60.0, 44.0, -30.0), Vector3(c.x + 10.0, 58.0, -18.0)]
		var p: Vector3 = spots[_field]
		var follow := Vector3((fight.kx + fight.gx) * 0.5, 30.0, fight.Z)
		_cam.global_position = p + Vector3(sin(_T * 0.2) * 3.0, 0, 0) + shake * 20.0
		_cam.look_at(follow, Vector3.UP)
		_cam.fov = lerpf(55.0, 38.0, smoothstep(0.0, 6.0, _shot_t))      # a slow zoom in


func _animate(delta: float) -> void:
	if _iv != "":
		_animate_iv(delta)
	var talk := 1.0 if _speak > 0.0 and _iv == "" else 0.0
	var m: MeshInstance3D = _rp["mouth"]
	m.scale.y = 0.004 + 0.012 * talk * maxf(0.0, sin(_T * 15.0) * sin(_T * 4.1 + 1.0))
	_duck = move_toward(_duck, 0.0, delta * 0.7)
	var look_target := 1.0 if (_shot == "rep" and fmod(_T, 9.0) > 6.5) else 0.0
	_look = move_toward(_look, look_target, delta * 1.5)
	(_rp["head"] as Node3D).rotation = Vector3(0.05 * sin(_T * 1.3) * talk + 0.2 * _duck, 1.9 * _look + 0.08 * sin(_T * 0.7), 0.04 * sin(_T * 0.9))
	(_rp["torso"] as Node3D).rotation = Vector3(0.25 * _duck, 0.5 * _look, 0.0)
	(_rp["man"] as Node3D).position.y = -0.12 * _duck
	(_rp["arm_l"] as Node3D).rotation = Vector3(-0.5 - 0.4 * talk * (0.5 + 0.5 * sin(_T * 2.2)) - 0.6 * _look, 0.0, -0.15)
	(_rp["fore_l"] as Node3D).rotation = Vector3(-0.6 * talk, 0.0, 0.0)


func _subject_active() -> bool:
	match _kind:
		"k":
			return main.kaiju != null and main.kaiju.active
		"g":
			return main.gaboon != null and main.gaboon.active
	return fight.active


func _subject_node() -> Node3D:
	if _kind == "k":
		return main.kaiju._k
	if _kind == "g":
		return main.gaboon._g
	return null


# ---- interviews

func _start_iv(who: String) -> void:
	_iv = who
	_iv_i = -1
	_iv_dur = 0.0
	_iv_t = 0.0
	for w in _sets:
		(_sets[w]["root"] as Node3D).visible = w == who
	_where.text = str(IV[who]["strip"])
	_cut("iv_" + who, 999.0)
	_iv_next()


func _iv_next() -> void:
	_iv_i += 1
	var lines: Array = IV[_iv]["lines"]
	if _iv_i >= lines.size():
		# back to the newsman, who has a name for it now
		var who := _iv
		_named[str(IV[who]["name"])] = true
		_iv = ""
		_where.text = WHERE
		(_sets[who]["root"] as Node3D).visible = false
		_cut("rep", 7.0)
		_say(_pick(IV[who]["after"]), 6.0)
		return
	var l: Array = lines[_iv_i]
	_iv_talk = l[0] == "a"
	_say(("CH 3:  " if l[0] == "q" else "") + str(l[1]), 6.0, str(l[2]))
	_speak = 0.0 if not _iv_talk else _speak
	_iv_t = 0.0
	_iv_dur = maxf(3.0, 1.2 + str(l[1]).length() / 12.0 + (1.5 if str(l[2]) != "" else 0.0))


func _iv_tick(delta: float) -> void:
	_iv_t += delta
	if _iv_t >= _iv_dur:
		_iv_next()


const WHERE := "CH 3 NEWS  -  DOWNTOWN"

const IV := {
	"vendor": {"strip": "ICE CREAM VENDOR  -  OLD TOWN", "name": "k", "lines": [
		["q", "Sir! Sir! Do you know what that thing is?", ""],
		["a", "Banira! Chokoreeto! Ichigo!", "(Vanilla! Chocolate! Strawberry!)"],
		["q", "Ba... Banira? Is that its name?", ""],
		["a", "Aisu kuriimu! Hitotsu hyaku en!", "(Ice cream! A hundred yen a scoop!)"]],
		"after": ["You heard him, folks. The creature has a name, and that name is Banira.",
			"Banira. That's what they're calling it down in Old Town. Back to the rooftops."]},
	"hunter": {"strip": "BIG-GAME HUNTER  -  THE DOCKS", "name": "g", "lines": [
		["q", "Sir, you look like a man who knows something about that monkey.", ""],
		["a", "Know him? Ja! I haff tracked him across three continents for twenty years!", ""],
		["a", "He gave me zis scar in ze Congo. I gave him nothing. Not yet.", ""],
		["a", "Zat, my boy, is King Gaboon. Und King Gaboon bows to no one.", ""]],
		"after": ["King Gaboon. A hunter's word for it, folks, and with a scar like that I'm not about to argue.",
			"King Gaboon. Twenty years that man has been chasing him. Back to the rooftops."]},
	"visitor": {"strip": "A VISITOR  -  DECLINED TO GIVE A NAME", "name": "b", "lines": [
		["q", "Excuse me, sir... the black one. Do you know what it is?", ""],
		["a", "Jogari. We left it here a long time ago. It was supposed to stay asleep.", ""],
		["a", "Nobody stays asleep in this town. ...Got a light?", ""]],
		"after": ["Jogari. You heard the... gentleman. Back to the rooftops.",
			"He called it Jogari. And then he asked me for a light. Back to the fight."]},
}


# ---- the interview sets: each a bit of street with its own light, on the reporter's layer

func _build_sets() -> void:
	_sets["vendor"] = _build_vendor(SETS)
	_sets["hunter"] = _build_hunter(SETS + Vector3(-40, 0, 0))
	_sets["visitor"] = _build_visitor_set(SETS + Vector3(-80, 0, 0))
	for w in _sets:
		var root: Node3D = _sets[w]["root"]
		root.visible = false
		for n in root.find_children("*", "VisualInstance3D", true, false):
			(n as VisualInstance3D).layers = LAYER


func _set_root(at: Vector3, wall: Color, lamp: Color) -> Node3D:
	var r := Node3D.new()
	main.outside.add_child(r)
	r.global_position = at
	_box(r, Vector3(0, -0.05, 0), Vector3(8.0, 0.1, 6.0), _mat(Color(0.2, 0.19, 0.21), 0.9))          # pavement
	_box(r, Vector3(0, 2.0, -1.4), Vector3(8.0, 4.0, 0.2), _mat(wall, 0.9))                           # a wall behind
	var l := OmniLight3D.new()
	l.light_cull_mask = LAYER
	l.omni_range = 7.0
	l.light_energy = 2.0
	l.light_color = lamp
	l.position = Vector3(0.9, 2.6, 1.8)
	r.add_child(l)
	var fill := OmniLight3D.new()
	fill.light_cull_mask = LAYER
	fill.omni_range = 6.0
	fill.light_energy = 0.6
	fill.light_color = Color(0.7, 0.75, 1.0)
	fill.position = Vector3(-1.5, 1.6, 1.2)
	r.add_child(fill)
	return r


# the station's woman on the ground: a red blazer, a pencil skirt, a dark bob, a hand microphone she holds out to
# whoever is talking (and back to herself for her questions). Stands at pos turned by yaw, to one side of them.
func _field_rep(r: Node3D, pos: Vector3, yaw: float) -> Dictionary:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	r.add_child(holder)
	var p := _person(holder, {"skin": Color(0.87, 0.71, 0.6), "jacket": Color(0.62, 0.1, 0.14), "shirt": Color(0.95, 0.94, 0.92),
		"legs": Color(0.15, 0.15, 0.18), "skirt": Color(0.15, 0.15, 0.18), "hose": Color(0.72, 0.58, 0.5), "shoes": Color(0.08, 0.06, 0.07),
		"hair": Color(0.16, 0.1, 0.08), "bob": true, "slim": true, "lips": Color(0.7, 0.18, 0.22),
		"brows": Color(0.18, 0.11, 0.09), "eyes": Color(0.3, 0.2, 0.12)})
	holder.scale = Vector3.ONE * 0.95
	var chrome := _mat(Color(0.75, 0.77, 0.8), 0.35)
	chrome.metallic = 0.5
	var mic := Node3D.new()                     # in her right hand, pointing out of her fist
	mic.position = Vector3(0.0, -0.06, 0.03)
	(p["hand_r"] as Node3D).add_child(mic)
	_cap(mic, Vector3(0, -0.05, 0), 0.014, 0.15, chrome)
	_ell(mic, Vector3(0, -0.14, 0.0), Vector3(0.03, 0.038, 0.03), chrome)
	_box(mic, Vector3(0, -0.07, 0.0), Vector3(0.038, 0.03, 0.038), _mat(Color(0.1, 0.2, 0.6), 0.5))   # the station's flag on it
	p["holder"] = holder
	p["mic"] = mic
	return p


# her arm, by two-bone IK: her hand goes to just short of the target (the mic's head ends up under his mouth), the
# elbow bending naturally, down and out to the side. k blends from holding the mic to herself (0) to held out (1).
func _reach(p: Dictionary, target: Vector3, k: float) -> void:
	var arm: Node3D = p["arm_r"]
	var parent := arm.get_parent() as Node3D
	var reach := target - arm.global_position
	reach -= reach.normalized() * 0.2
	var inv := parent.global_transform.basis.orthonormalized().inverse()
	var sc := parent.global_transform.basis.get_scale().x
	var dl := inv * reach / sc
	const L1 := 0.29
	const L2 := 0.31
	var dist := clampf(dl.length(), 0.15, (L1 + L2) * 0.9)          # never quite straight
	var d := dl.normalized()
	var alpha := acos(clampf((L1 * L1 + dist * dist - L2 * L2) / (2.0 * L1 * dist), -1.0, 1.0))
	var beta := acos(clampf((L1 * L1 + L2 * L2 - dist * dist) / (2.0 * L1 * L2), -1.0, 1.0))
	var pole := (Vector3(0.6, -1.0, -0.2)).normalized()               # the elbow drops down and out
	var n := (pole - d * pole.dot(d)).normalized()
	var u := (d * cos(alpha) + n * sin(alpha)).normalized()            # the upper arm
	var z := (d - u * d.dot(u)).normalized()                         # the way the forearm bends
	var y := -u
	var ik := Basis(y.cross(z), y, z).orthonormalized()
	var to_self := Basis.from_euler(Vector3(-0.55, 0.0, -0.45))
	arm.basis = Basis(to_self.get_rotation_quaternion().slerp(ik.get_rotation_quaternion(), k))
	(p["fore_r"] as Node3D).rotation = Vector3(lerpf(-2.3, -(PI - beta), k), 0.0, 0.0)
	# and her wrist turns so the mic points at his mouth
	var hand: Node3D = p["hand_r"]
	var fore: Node3D = p["fore_r"]
	var aim := fore.global_transform.basis.orthonormalized().inverse() * (target - hand.global_position)
	if aim.length() > 0.01:
		hand.quaternion = Quaternion.IDENTITY.slerp(Quaternion(Vector3.DOWN, aim.normalized()), k)


# a standing man, built like a Dreamcast-era character: real proportions (about 7.5 heads tall), a chest that
# narrows to the waist, hips, knees and elbows, hands with a thumb, and a face with whites to the eyes, brows, a
# nose, a jaw and a chin. Faces +z, feet on y = 0, about 1.8 tall. Returns its moving parts.
func _person(parent: Node3D, c: Dictionary) -> Dictionary:
	var body := Node3D.new()
	parent.add_child(body)
	var skin := _mat(c["skin"], 0.55)
	var legs := _mat(c["legs"], 0.8)
	var shoes := _mat(c["shoes"], 0.4)
	var jacket := _mat(c["jacket"], 0.8)
	var shirt := _mat(c["shirt"], 0.7)
	var slim: float = 0.88 if c.has("slim") else 1.0
	# legs: thigh and shin, a little apart; shoes with a rounded toe (or a skirt to the knee, and heels)
	for sx in [-1.0, 1.0]:
		if c.has("skirt"):
			_cap(body, Vector3(sx * 0.08, 0.29, 0.0), 0.05, 0.5, _mat(c["hose"], 0.5))
			_box(body, Vector3(sx * 0.08, 0.05, 0.02), Vector3(0.075, 0.05, 0.19), shoes).rotation.x = -0.25
			_put(body, _taper(0.008, 0.008, 0.07), Vector3(sx * 0.08, 0.035, -0.06), shoes)
		else:
			_cap(body, Vector3(sx * 0.095, 0.7, 0.0), 0.075, 0.48, legs)
			_cap(body, Vector3(sx * 0.095, 0.29, 0.0), 0.06, 0.5, legs)
			_box(body, Vector3(sx * 0.095, 0.035, 0.03), Vector3(0.1, 0.07, 0.22), shoes)
			_ell(body, Vector3(sx * 0.095, 0.04, 0.13), Vector3(0.05, 0.035, 0.06), shoes)
	if c.has("skirt"):
		_put(body, _taper(0.16, 0.15, 0.46), Vector3(0, 0.72, 0), _mat(c["skirt"], 0.8)).scale = Vector3(1.0, 1.0, 0.7)
	var pelvis := _put(body, _taper(0.165 * slim, 0.16 * slim, 0.16), Vector3(0, 0.92, 0), _mat(c["skirt"], 0.8) if c.has("skirt") else legs)
	pelvis.scale = Vector3(1.0, 1.0, 0.66)
	var torso := Node3D.new()
	torso.position = Vector3(0, 0.95, 0)
	body.add_child(torso)
	var chest := _put(torso, _taper(0.19 * slim, 0.15 * slim * slim, 0.52), Vector3(0, 0.28, 0), jacket)   # broad at the shoulders, in at the waist
	chest.scale = Vector3(1.0, 1.0, 0.62)
	var vee := PrismMesh.new()                                                            # the shirt in the V of the jacket
	vee.size = Vector3(0.13, 0.24, 0.02)
	vee.left_to_right = 0.5
	_put(torso, vee, Vector3(0, 0.42, 0.105), shirt).rotation.z = PI
	if c.has("tie"):
		_box(torso, Vector3(0, 0.39, 0.112), Vector3(0.032, 0.2, 0.01), _mat(c["tie"], 0.6))
	for sx in [-1.0, 1.0]:
		_ell(torso, Vector3(sx * 0.2 * slim, 0.48, 0.0), Vector3(0.075 * slim, 0.06, 0.08), jacket)      # shoulders
		var lap := _box(torso, Vector3(sx * 0.06, 0.4, 0.108), Vector3(0.05, 0.22, 0.012), jacket)   # lapels
		lap.rotation.z = sx * 0.3
	_put(torso, _taper(0.05, 0.052, 0.1), Vector3(0, 0.57, 0), skin)                     # neck
	_put(torso, _taper(0.062, 0.066, 0.035), Vector3(0, 0.535, 0), shirt)                 # collar
	var head := Node3D.new()
	head.position = Vector3(0, 0.6, 0)
	torso.add_child(head)
	var mouth := _face(head, c, skin)
	var parts := {"man": body, "torso": torso, "head": head, "mouth": mouth}
	# arms: upper arm, a bend at the elbow, forearm, a shirt cuff, a hand with a thumb
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.22 * slim, 0.47, 0)
		torso.add_child(arm)
		_cap(arm, Vector3(0, -0.145, 0), 0.05 * slim, 0.31, jacket)
		var fore := Node3D.new()
		fore.position = Vector3(0, -0.29, 0)
		arm.add_child(fore)
		_cap(fore, Vector3(0, -0.12, 0), 0.044, 0.27, jacket)
		_put(fore, _taper(0.042, 0.042, 0.03), Vector3(0, -0.245, 0), shirt)
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.27, 0)
		fore.add_child(hand)
		_box(hand, Vector3(0, -0.04, 0.0), Vector3(0.028, 0.08, 0.07), skin)              # palm
		_box(hand, Vector3(side * -0.004, -0.105, 0.004), Vector3(0.024, 0.06, 0.064), skin).rotation.x = 0.25   # fingers, curled a little
		_cap(hand, Vector3(side * -0.012, -0.045, 0.04), 0.012, 0.055, skin).rotation.x = -0.5                 # thumb
		parts["arm_r" if side > 0 else "arm_l"] = arm
		parts["fore_r" if side > 0 else "fore_l"] = fore
		parts["hand_r" if side > 0 else "hand_l"] = hand
	return parts


# the head: skull, cheeks and jaw, a chin, ears, a nose, eyes with whites, brows, lips; hair if he has it.
# Returns the mouth (it opens and closes as he talks).
func _face(head: Node3D, c: Dictionary, skin: Material) -> MeshInstance3D:
	_ell(head, Vector3(0, 0.155, -0.005), Vector3(0.088, 0.105, 0.1), skin)              # skull
	_ell(head, Vector3(0, 0.09, 0.012), Vector3(0.076, 0.07, 0.085), skin)               # cheeks and jaw
	_ell(head, Vector3(0, 0.05, 0.05), Vector3(0.036, 0.03, 0.036), skin)                # chin
	for sx in [-1.0, 1.0]:
		_ell(head, Vector3(sx * 0.088, 0.135, -0.005), Vector3(0.012, 0.027, 0.019), skin)   # ears
	_ell(head, Vector3(0, 0.125, 0.093), Vector3(0.014, 0.032, 0.02), skin)               # nose
	_ell(head, Vector3(0, 0.1, 0.1), Vector3(0.02, 0.012, 0.014), skin)                   # its tip
	var white := _mat(Color(0.95, 0.94, 0.9), 0.3)
	var iris := _mat(c.get("eyes", Color(0.25, 0.17, 0.1)), 0.3)
	var brow := _mat(c.get("brows", Color(0.2, 0.18, 0.17)), 0.6)
	for sx in [-1.0, 1.0]:
		_ell(head, Vector3(sx * 0.032, 0.15, 0.078), Vector3(0.017, 0.01, 0.01), white)
		_ell(head, Vector3(sx * 0.032, 0.15, 0.086), Vector3(0.007, 0.0085, 0.004), iris)
		_ell(head, Vector3(sx * 0.032, 0.158, 0.082), Vector3(0.019, 0.006, 0.01), skin)     # upper lid
		var b := _box(head, Vector3(sx * 0.035, 0.172, 0.088), Vector3(0.042, 0.01, 0.014), brow)
		b.rotation.z = sx * -0.12
	var lips := _mat(c.get("lips", Color(c["skin"]).darkened(0.25)), 0.4)
	_ell(head, Vector3(0, 0.064, 0.08), Vector3(0.024, 0.007, 0.01), lips)                # lower lip
	var mouth := _ell(head, Vector3(0, 0.072, 0.083), Vector3(0.022, 0.004, 0.006), _mat(Color(0.12, 0.04, 0.04), 0.6))
	if c.has("hair"):
		var hair := _mat(c["hair"], 0.55)
		var cap := _ell(head, Vector3(0, 0.19, -0.015), Vector3(0.094, 0.08, 0.1), hair)      # swept back off the forehead
		cap.rotation.x = -0.25
		_ell(head, Vector3(0, 0.14, -0.045), Vector3(0.09, 0.09, 0.075), hair)                 # the back
		if c.has("bob"):                       # a jaw-length bob with a side parting
			_ell(head, Vector3(0, 0.12, -0.035), Vector3(0.1, 0.12, 0.085), hair)
			for sx in [-1.0, 1.0]:
				_ell(head, Vector3(sx * 0.082, 0.1, 0.02), Vector3(0.028, 0.08, 0.06), hair)
			_ell(head, Vector3(0.035, 0.205, 0.05), Vector3(0.07, 0.03, 0.05), hair).rotation.z = -0.3
		else:
			for sx in [-1.0, 1.0]:
				_box(head, Vector3(sx * 0.086, 0.125, 0.02), Vector3(0.01, 0.04, 0.03), _mat(c.get("temples", c["hair"]), 0.6))   # sideburns
	return mouth


static func _taper(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = 14
	m.rings = 1
	return m


# the ice cream vendor at his cart in Old Town: white jacket and paper cap, a striped awning behind him
func _build_vendor(at: Vector3) -> Dictionary:
	var r := _set_root(at, Color(0.42, 0.24, 0.2), Color(1.0, 0.9, 0.75))
	var white := Color(0.93, 0.93, 0.9)
	var p := _person(r, {"skin": Color(0.86, 0.7, 0.56), "legs": Color(0.25, 0.25, 0.3), "shoes": Color(0.1, 0.08, 0.07),
		"jacket": white, "shirt": white, "hair": Color(0.45, 0.44, 0.43), "brows": Color(0.4, 0.39, 0.38)})
	var head: Node3D = p["head"]
	_box(head, Vector3(0, 0.248, -0.01), Vector3(0.18, 0.05, 0.2), _mat(white, 0.7)).rotation.z = 0.08     # paper cap
	_box(head, Vector3(0, 0.226, -0.01), Vector3(0.185, 0.012, 0.205), _mat(Color(0.85, 0.3, 0.35), 0.6)).rotation.z = 0.08
	_box(p["torso"], Vector3(0, 0.08, 0.1), Vector3(0.3, 0.5, 0.012), _mat(Color(0.98, 0.98, 0.96), 0.8)).rotation.x = -0.05   # apron
	_box(p["torso"], Vector3(0, 0.515, 0.11), Vector3(0.07, 0.028, 0.02), _mat(Color(0.8, 0.15, 0.2), 0.6))   # bow tie
	var scoop := _mat(Color(0.75, 0.77, 0.8), 0.2)
	scoop.metallic = 0.8
	_cap(p["hand_r"], Vector3(0, -0.1, 0.05), 0.011, 0.12, scoop)                                            # the scoop in his hand
	# the cart: three tubs under the lid, a parasol over it, a sign on the front
	var cart := _mat(Color(0.95, 0.9, 0.82), 0.6)
	_box(r, Vector3(0.8, 0.42, 0.25), Vector3(0.75, 0.8, 0.45), cart)
	_box(r, Vector3(0.8, 0.83, 0.25), Vector3(0.79, 0.03, 0.49), _mat(Color(0.55, 0.75, 0.9), 0.5))
	for k in 3:
		var col: Color = [Color(0.98, 0.95, 0.82), Color(0.42, 0.25, 0.15), Color(0.98, 0.6, 0.7)][k]
		_put(r, _cyl_mesh(0.08, 0.02), Vector3(0.58 + k * 0.22, 0.855, 0.27), _mat(col, 0.7))
	var sign := Label3D.new()
	sign.text = "ICE CREAM"
	sign.font_size = 48
	sign.pixel_size = 0.0028
	sign.modulate = Color(0.85, 0.2, 0.3)
	sign.position = Vector3(0.8, 0.55, 0.48)
	r.add_child(sign)
	_put(r, _cyl_mesh(0.015, 1.3), Vector3(1.05, 1.5, 0.1), _mat(Color(0.6, 0.6, 0.62), 0.4))             # parasol pole
	var canopy := CylinderMesh.new()
	canopy.top_radius = 0.02
	canopy.bottom_radius = 0.6
	canopy.height = 0.25
	canopy.radial_segments = 12
	_put(r, canopy, Vector3(1.05, 2.18, 0.1), _mat(Color(0.98, 0.65, 0.75), 0.7))
	# the shop behind: a lit window and a striped awning
	_box(r, Vector3(-1.4, 1.4, -1.29), Vector3(1.5, 1.1, 0.02), _mat(Color(1.0, 0.85, 0.55), 0.5, 1.2))
	for k in 5:
		var aw: MeshInstance3D = _box(r, Vector3(-2.0 + k * 0.3, 2.2, -1.0), Vector3(0.3, 0.05, 0.7),
			_mat(Color(0.85, 0.2, 0.25) if k % 2 == 0 else Color(0.95, 0.93, 0.9), 0.7))
		aw.rotation.x = 0.35
	return {"root": r, "p": p, "rep": _field_rep(r, Vector3(-0.62, 0.0, 0.32), 1.25), "mouth": Vector3(0, 1.62, 0.1),
		"cam": [Vector3(0.15, 1.55, 2.8), Vector3(0.05, 1.35, 0.0)], "style": "wave"}


# the big-game hunter on the docks: pith helmet, khaki, a great moustache, binoculars round his neck
func _build_hunter(at: Vector3) -> Dictionary:
	var r := _set_root(at, Color(0.24, 0.2, 0.17), Color(1.0, 0.88, 0.7))
	var khaki := Color(0.66, 0.58, 0.4)
	var p := _person(r, {"skin": Color(0.9, 0.68, 0.58), "legs": Color(0.55, 0.47, 0.32), "shoes": Color(0.3, 0.18, 0.1),
		"jacket": khaki, "shirt": Color(0.88, 0.84, 0.72), "brows": Color(0.75, 0.72, 0.68)})
	var head: Node3D = p["head"]
	var helmet := _mat(Color(0.88, 0.84, 0.68), 0.7)
	_ell(head, Vector3(0, 0.22, -0.005), Vector3(0.12, 0.1, 0.135), helmet)
	_put(head, _cyl_mesh(0.18, 0.012), Vector3(0, 0.2, 0.0), helmet).scale = Vector3(1.0, 1.0, 1.15)
	_put(head, _cyl_mesh(0.122, 0.022), Vector3(0, 0.215, -0.005), _mat(Color(0.35, 0.28, 0.2), 0.6)).scale = Vector3(1.0, 1.0, 1.1)   # hat band
	# a big old scar down across his left eye, brow to cheek (King Gaboon gave him that)
	var scar := _mat(Color(0.78, 0.42, 0.42), 0.5)
	var sp := [Vector3(0.054, 0.205, 0.07), Vector3(0.046, 0.176, 0.09), Vector3(0.04, 0.15, 0.092), Vector3(0.036, 0.122, 0.086), Vector3(0.032, 0.094, 0.09)]
	for i in sp.size() - 1:
		var a: Vector3 = sp[i]
		var b: Vector3 = sp[i + 1]
		var seg := _box(head, (a + b) * 0.5, Vector3(0.009, a.distance_to(b) + 0.004, 0.005), scar)
		var yv := (b - a).normalized()
		var xv := yv.cross(Vector3(0, 0, 1)).normalized()
		seg.basis = Basis(xv, yv, xv.cross(yv))
	var tache := _mat(Color(0.82, 0.8, 0.76), 0.7)                                                          # a grand white moustache
	for sx in [-1.0, 1.0]:
		_ell(head, Vector3(sx * 0.03, 0.084, 0.092), Vector3(0.036, 0.012, 0.014), tache).rotation.z = sx * -0.35
	var blk := _mat(Color(0.06, 0.06, 0.06), 0.4)
	for sx in [-1.0, 1.0]:
		_put(p["torso"], _cyl_mesh(0.024, 0.1), Vector3(sx * 0.028, 0.3, 0.135), blk)        # binoculars, hanging
	for sx in [-1.0, 1.0]:
		_box(p["torso"], Vector3(sx * 0.055, 0.43, 0.12), Vector3(0.01, 0.26, 0.01), blk).rotation.z = sx * 0.3   # the strap
	# the docks: stacked crates, a bollard, a lamp
	var crate := _mat(Color(0.45, 0.32, 0.2), 0.85)
	_box(r, Vector3(-1.2, 0.35, -0.6), Vector3(0.7, 0.7, 0.7), crate)
	_box(r, Vector3(-1.1, 1.0, -0.65), Vector3(0.6, 0.6, 0.6), crate)
	_box(r, Vector3(1.4, 0.3, -0.5), Vector3(0.8, 0.6, 0.7), crate)
	_put(r, _cyl_mesh(0.14, 0.5), Vector3(0.95, 0.25, 0.6), _mat(Color(0.15, 0.15, 0.17), 0.5))
	return {"root": r, "p": p, "rep": _field_rep(r, Vector3(0.62, 0.0, 0.32), -1.25), "mouth": Vector3(0, 1.62, 0.1),
		"cam": [Vector3(0.1, 1.55, 2.7), Vector3(0.2, 1.35, 0.0)], "style": "point"}


# the grey visitor on a bench under a street lamp, coat collar up, cigarette going, a glass in his hand
func _build_visitor_set(at: Vector3) -> Dictionary:
	var r := _set_root(at, Color(0.14, 0.13, 0.15), Color(0.95, 0.9, 0.75))
	var wood := _mat(Color(0.3, 0.2, 0.14), 0.8)
	_box(r, Vector3(0, 0.45, -0.05), Vector3(0.8, 0.08, 0.6), wood)
	_box(r, Vector3(0, 0.8, -0.42), Vector3(0.8, 0.6, 0.08), wood)
	for sx in [-1.0, 1.0]:
		_box(r, Vector3(sx * 0.36, 0.6, -0.05), Vector3(0.08, 0.25, 0.7), wood)
		_box(r, Vector3(sx * 0.36, 0.71, -0.05), Vector3(0.12, 0.03, 0.74), wood)
		_box(r, Vector3(sx * 0.33, 0.2, -0.05), Vector3(0.05, 0.4, 0.5), _mat(Color(0.1, 0.1, 0.11), 0.4))
	var lamp := _mat(Color(0.12, 0.12, 0.13), 0.5)
	_put(r, _cyl_mesh(0.04, 3.0), Vector3(-0.9, 1.5, -0.6), lamp)
	_box(r, Vector3(-0.7, 3.0, -0.6), Vector3(0.5, 0.05, 0.05), lamp)
	_ell(r, Vector3(-0.5, 2.9, -0.6), Vector3(0.12, 0.08, 0.12), _mat(Color(1.0, 0.9, 0.7), 0.5, 2.0))
	var v: Node3D = load("res://stressed_alien.gd").new()
	r.add_child(v)
	v.build(0.5)
	return {"root": r, "p": {}, "rep": _field_rep(r, Vector3(0.68, 0.0, 0.3), -1.2), "mouth": Vector3(0.0, 1.12, -0.04),
		"cam": [Vector3(0.0, 1.35, 2.4), Vector3(0.3, 1.1, 0.0)], "style": "sit"}


# what the interviewee does: talks when it's his line, and the vendor waves his scoop, the hunter points
var _mic_k := 0.0                    # where her microphone is: 0 at her own mouth, 1 held out to them


func _animate_iv(delta: float) -> void:
	var st: Dictionary = _sets[_iv]
	var p: Dictionary = st["p"]
	# the woman on the ground: she asks, then holds the mic out while they answer
	var rp: Dictionary = st["rep"]
	var asking := 0.0 if _iv_talk else (1.0 if _iv_t < _iv_dur - 0.6 else 0.0)
	_mic_k = move_toward(_mic_k, 0.0 if not _iv_talk else 1.0, delta * 2.5)
	(rp["mouth"] as Node3D).scale.y = 0.004 + 0.012 * asking * maxf(0.0, sin(_T * 15.0) * sin(_T * 4.7 + 0.5))
	(rp["head"] as Node3D).rotation = Vector3(0.05 * sin(_T * 1.2), 0.25 + 0.1 * sin(_T * 0.5), 0.0)
	var root: Node3D = st["root"]
	_reach(rp, root.to_global(st["mouth"] + Vector3(0.0, -0.035, 0.06)), smoothstep(0.0, 1.0, _mic_k))
	(rp["arm_l"] as Node3D).rotation = Vector3(-0.15, 0.0, -0.12)
	(rp["fore_l"] as Node3D).rotation = Vector3(-0.5, 0.0, 0.0)
	if p.is_empty():
		return
	var talk := 1.0 if _iv_talk and _iv_t < _iv_dur - 0.6 else 0.0
	(p["mouth"] as Node3D).scale.y = 0.004 + 0.012 * talk * maxf(0.0, sin(_T * 14.0) * sin(_T * 4.3 + 1.0))
	(p["head"] as Node3D).rotation = Vector3(0.06 * sin(_T * 1.4) * talk, 0.15 * sin(_T * 0.6), 0.05 * sin(_T * 0.9))
	match str(st["style"]):
		"wave":                        # the scoop up, waving it like he's calling out to the whole street
			(p["arm_r"] as Node3D).rotation = Vector3(-0.5, 0.0, 2.2 + 0.35 * sin(_T * 5.0) * talk)
			(p["fore_r"] as Node3D).rotation = Vector3(0.0, 0.0, 0.5)
			(p["arm_l"] as Node3D).rotation = Vector3(-0.5, 0.0, -0.1)
			(p["fore_l"] as Node3D).rotation = Vector3(-1.2, 0.0, 0.0)
		"point":                       # one arm up at the sky, where the monkey is; the other fist on his hip
			(p["arm_l"] as Node3D).rotation = Vector3(0.0, 0.0, -2.5 - 0.15 * sin(_T * 3.0) * talk)
			(p["fore_l"] as Node3D).rotation = Vector3(0.0, 0.0, -0.1)
			(p["arm_r"] as Node3D).rotation = Vector3(0.0, 0.0, 0.45)
			(p["fore_r"] as Node3D).rotation = Vector3(0.0, 0.0, -1.6)


# ---- what he says

const LINES := {
	"enter": ["They're both coming in from opposite ends of the city. The ground is shaking up here.",
		"There it is. Two of them. I never thought I'd say that on the air."],
	"faceoff": ["They've stopped. They're staring each other down. I can hear them from here.",
		"That roar shattered windows three blocks away. {G_big} is answering it."],
	"grapple": ["They're locked together, shoving, neither one giving an inch.",
		"They've grabbed hold of each other. The whole skyline is swaying."],
	"bite": ["{K} has its jaws on {g}'s shoulder!", "A savage bite! {G} is reeling!"],
	"punch": ["{G} lands a blow right across its jaw!", "A punch you could feel in your teeth, folks."],
	"tail": ["It spun around and caught him with that enormous tail!", "That tail swept him clean off his feet!"],
	"tackle": ["{G} is down! He's down behind the towers!", "A head-on charge, and {G} goes over!"],
	"slam": ["He's thrown it! {K} is down in a cloud of dust!", "{G} picked it up and slammed it into the street!"],
	"circle": ["They're circling now. Catching their breath, if monsters breathe.", "A lull. But nobody down there believes it's over."],
	"roars": ["Listen to that. I don't think there's a glass window left on Fifth Street.", "They're roaring at each other across the rooftops."],
	"ice_beam": ["Its back is glowing! It's breathing... ice? {G} is freezing solid!", "A beam of pure cold! I can see frost forming from here!"],
	"fireball": ["He's holding fire in his hands! He's thrown it!", "A ball of fire! It hit {k} square in the chest!"],
	"clash": ["They've hit each other at the same moment! Both of them are staggering!", "Head to head! Neither one is standing straight!"],
	"g_retreat": ["{G} is thawing out and backing away. He's leaving!", "{G} is retreating into the city."],
	"k_retreat": ["{K} is limping off, smoke trailing behind it.", "It's turning away. It's had enough."],
	"k_victory": ["{K} is roaring over the city. It's claimed the night.", "Listen to that victory cry."],
	"g_victory": ["{G} beats his chest. There's no doubt who won tonight.", "He's standing tall over the skyline."],
	"bk_arrive": ["Wait. Something else is coming up behind them. A third one! Black as night!",
		"There's another one! It's bigger than both of them!"],
	"bk_roar": ["Listen to that! Its stripes are glowing like the signs on Main Street!", "All three of them, roaring at each other. God help us."],
	"bk_neon": ["Its stripes are blazing! It's breathing... light! Pink and blue, like every sign in town at once!",
		"A beam of neon! It's knocked both of them back! I've never seen colours like that!"],
	"ufo_swarm": ["Lights in the clouds... dozens of them. Those are not helicopters.", "Flying saucers! A whole fleet of them, circling the monsters!"],
	"abduct": ["Beams of light! They're lifting them! All three of them are leaving the ground!", "They're being pulled up into the sky. I can't believe what I'm seeing."],
	"fleet_leaves": ["They're gone. Up into the clouds, monsters and all.", "And just like that, the sky is empty."],
	"both_exit": ["They're both walking away. Nobody won. The city lost.", "Each going their own way, for now."],
	"filler": ["If you're just joining us: two giant creatures are fighting downtown. Stay indoors.",
		"Authorities advise residents to keep away from windows. Well, I'm on a roof, so.",
		"Our cameras are on several rooftops. We'll stay with this as long as we can.",
		"I've covered fires, floods and a strike at the docks. Nothing like this."],
	"b_open_k": ["We interrupt this program. Something enormous is walking through downtown, right past the apartment towers.",
		"This is a Channel 3 bulletin. A giant white creature has been sighted downtown. Stay away from your windows."],
	"b_open_g": ["We interrupt this program. A giant monkey is walking through the city. I repeat, a giant monkey.",
		"This is a Channel 3 bulletin. Something huge and hairy is moving between the towers downtown."],
	"b_filler": ["If you're just joining us: a giant creature is walking through downtown. Stay indoors.",
		"It doesn't seem to be in a hurry. It's just... looking in the windows.",
		"Our cameras are on the rooftops. We'll stay with it as long as we can."],
	"b_signoff": ["And it's gone, past the towers and out of sight. Channel 3 will stay on this story. Back to your program.",
		"The street is quiet again. For Channel 3, reporting live from downtown. Back to your program."],
	"signoff": ["And that's it. They're gone, into the night. This has been a special report. Back to your regular program.",
		"The city is quiet again. Reporting live from downtown, for Channel 3. Good night."],
}


# a faint broadcast line hiss, looping smoothly (soft filtered noise, no tones)
static func _make_hiss() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var lp := 0.0
	for i in n:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		var edge := minf(1.0, minf(i, n - 1 - i) / 400.0)       # fades at the ends so the loop never clicks
		data.encode_s16(i * 2, int(clampf(lp * 0.6 * (0.6 + 0.4 * edge), -1.0, 1.0) * 20000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


# the station's news sting: three bright, rising notes and a held chord, like an old bulletin intro
static func _make_sting() -> AudioStreamWAV:
	var rate := 22050
	var n := int(2.4 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var notes := [[0.0, 523.25], [0.22, 659.25], [0.44, 783.99]]
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		for nt in notes:
			var dt: float = t - float(nt[0])
			if dt >= 0.0:
				var f: float = nt[1]
				var env := minf(1.0, dt * 60.0) * exp(-dt * (1.2 if t > 0.44 else 4.0))
				s += (sin(TAU * f * dt) + 0.3 * sin(TAU * f * 2.0 * dt) + 0.12 * sin(TAU * f * 3.0 * dt)) * env * 0.28
		s *= 1.0 - smoothstep(1.9, 2.4, t)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# ---- small builders

static func _mat(c: Color, rough: float, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.disable_fog = true
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _box(parent: Node3D, pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _put(parent, b, pos, m)


func _ell(parent: Node3D, pos: Vector3, radii: Vector3, m: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 16
	s.rings = 8
	var mi := _put(parent, s, pos, m)
	mi.scale = radii
	return mi


func _cap(parent: Node3D, pos: Vector3, r: float, h: float, m: Material) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 12
	c.rings = 4
	return _put(parent, c, pos, m)


func _put(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _cyl_mesh(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	return c
