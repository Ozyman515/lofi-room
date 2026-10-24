extends Node
## Breaking news: while the T-Rex and King Gaboon fight (fight.gd), the TV cuts in with a live report. An
## old-school 1950s newsman stands on a rooftop with the fight going on behind him, chrome microphone in hand,
## and talks you through it; the broadcast cuts between him and the station's cameras on other rooftops.
## Lower third: CH 3 NEWS, LIVE, what he's saying, and a ticker. His voice is a mumbling old-TV murmur on the
## TV's sound (so speakers set to TV carry it too); his words are in the caption.
## The picture is a small SubViewport looking at the same city (240 lines, like the CRT; the headset renders it
## at a lower rate). He and his rooftop are on visual layer 3, which only the news camera sees.
## The TV is borrowed only when it isn't busy with a game: a playing tape pauses and resumes afterwards, and a
## TV that was off switches itself on for the broadcast and back off after.

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
var _murmur: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _end_t := -1.0
var _look := 0.0                     # how far he has turned to look back at the fight
var _duck := 0.0
var _queued := ""                    # a moment that happened during his opening words

const SPOT := Vector3(-30.0, 0.0, -30.0)     # his rooftop, off to one side, the fight beyond it


func setup(m: Node3D, f: Node3D) -> void:
	main = m
	fight = f
	fight.moment.connect(_on_moment)
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
	_build_overlay()
	_murmur = AudioStreamPlayer.new()
	_murmur.stream = _make_murmur()
	_murmur.bus = "TV" if AudioServer.get_bus_index("TV") >= 0 else "Master"
	_murmur.volume_db = -8.0
	add_child(_murmur)


# ---- the newsman: dark suit, white shirt, thin tie, slicked-back hair going grey at the temples, heavy brows,
# a chrome microphone on a cable. Built from simple rounded shapes; faces +z.

func _build_reporter() -> void:
	_rep = Node3D.new()
	main.room.add_child(_rep)
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
	var body := Node3D.new()                  # the man (about 1.8 units tall)
	body.name = "Man"
	_rep.add_child(body)
	_cap(body, Vector3(-0.13, 0.45, 0), 0.11, 0.9, suit)                 # legs
	_cap(body, Vector3(0.13, 0.45, 0), 0.11, 0.9, suit)
	_box(body, Vector3(-0.13, 0.04, 0.06), Vector3(0.14, 0.08, 0.28), dark)   # shoes
	_box(body, Vector3(0.13, 0.04, 0.06), Vector3(0.14, 0.08, 0.28), dark)
	var torso := Node3D.new()
	torso.position = Vector3(0, 0.95, 0)
	body.add_child(torso)
	_ell(torso, Vector3(0, 0.3, 0), Vector3(0.27, 0.36, 0.17), suit)     # jacket
	var vee := PrismMesh.new()                                            # shirt in the V of the jacket
	vee.size = Vector3(0.16, 0.26, 0.02)
	vee.left_to_right = 0.5
	_put(torso, vee, Vector3(0, 0.43, 0.155), shirt).rotation.z = PI
	_box(torso, Vector3(0, 0.38, 0.17), Vector3(0.035, 0.3, 0.012), tie)      # thin tie
	_ell(torso, Vector3(-0.27, 0.56, 0), Vector3(0.1, 0.07, 0.11), suit)  # shoulders
	_ell(torso, Vector3(0.27, 0.56, 0), Vector3(0.1, 0.07, 0.11), suit)
	var head := Node3D.new()
	head.position = Vector3(0, 0.72, 0)
	torso.add_child(head)
	_cap(head, Vector3(0, 0.0, 0), 0.055, 0.14, skin)                     # neck
	_ell(head, Vector3(0, 0.16, 0.01), Vector3(0.1, 0.13, 0.11), skin)    # head
	_ell(head, Vector3(0, 0.22, -0.01), Vector3(0.105, 0.09, 0.11), hair)  # hair, combed back
	_ell(head, Vector3(-0.095, 0.17, -0.01), Vector3(0.025, 0.05, 0.06), grey)   # grey temples
	_ell(head, Vector3(0.095, 0.17, -0.01), Vector3(0.025, 0.05, 0.06), grey)
	_box(head, Vector3(-0.04, 0.2, 0.1), Vector3(0.05, 0.014, 0.02), hair)        # heavy brows
	_box(head, Vector3(0.04, 0.2, 0.1), Vector3(0.05, 0.014, 0.02), hair)
	_ell(head, Vector3(-0.035, 0.175, 0.1), Vector3(0.012, 0.009, 0.006), dark)   # eyes
	_ell(head, Vector3(0.035, 0.175, 0.1), Vector3(0.012, 0.009, 0.006), dark)
	_ell(head, Vector3(0, 0.14, 0.115), Vector3(0.018, 0.03, 0.02), skin)         # nose
	_ell(head, Vector3(-0.1, 0.16, 0.0), Vector3(0.014, 0.03, 0.02), skin)        # ears
	_ell(head, Vector3(0.1, 0.16, 0.0), Vector3(0.014, 0.03, 0.02), skin)
	var mouth := _ell(head, Vector3(0, 0.095, 0.1), Vector3(0.03, 0.008, 0.01), dark)
	# arms: the right one holds the microphone up near his chin, the left one gestures
	var arm_r := Node3D.new()
	arm_r.position = Vector3(0.29, 0.52, 0)
	torso.add_child(arm_r)
	_cap(arm_r, Vector3(0.02, -0.16, 0.04), 0.06, 0.34, suit)
	var fore_r := Node3D.new()
	fore_r.position = Vector3(0.02, -0.32, 0.06)
	arm_r.add_child(fore_r)
	var fr := _cap(fore_r, Vector3(-0.06, 0.1, 0.1), 0.05, 0.3, suit)
	fr.rotation = Vector3(-1.1, 0.0, 0.5)
	_ell(fore_r, Vector3(-0.13, 0.2, 0.2), Vector3(0.045, 0.05, 0.045), skin)      # hand
	var mic := Node3D.new()
	mic.position = Vector3(-0.15, 0.26, 0.22)
	fore_r.add_child(mic)
	_cap(mic, Vector3(0, 0.0, 0), 0.018, 0.16, chrome).rotation.x = -0.4
	_ell(mic, Vector3(0, 0.1, 0.04), Vector3(0.045, 0.06, 0.04), chrome)           # the round head
	_box(mic, Vector3(0, 0.1, 0.075), Vector3(0.06, 0.006, 0.006), dark)          # its grille bar
	_cap(mic, Vector3(0.0, -0.18, -0.05), 0.008, 0.25, dark).rotation.x = 0.3     # the cable
	var arm_l := Node3D.new()
	arm_l.position = Vector3(-0.29, 0.52, 0)
	torso.add_child(arm_l)
	_cap(arm_l, Vector3(-0.02, -0.17, 0.0), 0.06, 0.34, suit)
	var fore_l := Node3D.new()
	fore_l.position = Vector3(-0.03, -0.34, 0.0)
	arm_l.add_child(fore_l)
	_cap(fore_l, Vector3(0, -0.13, 0.02), 0.05, 0.28, suit)
	_ell(fore_l, Vector3(0, -0.29, 0.03), Vector3(0.045, 0.055, 0.04), skin)
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

func _start() -> void:
	if _vp == null:
		_build()
	if main.console_on or main.vcr.remote_video:
		return                                            # the TV is busy with a game or a guest's tape
	on_air = true
	_T = 0.0
	_end_t = -1.0
	_rep.visible = true
	_was_tv_on = main.vcr.tv_on
	if not _was_tv_on:
		main.vcr.toggle_tv()                              # it clicks on by itself
	_paused_tape = main.vcr.state == main.vcr.State.PLAYING and not main.vcr._paused_flag
	if _paused_tape:
		main.vcr._set_paused(true)
	main.vcr._show_status("")
	main.vcr._osd_show("BREAKING NEWS", 3.0)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_ticker.text = "  BREAKING: TWO GIANT MONSTERS CLASH DOWNTOWN  *  RESIDENTS URGED TO STAY INDOORS  *  BRIDGES CLOSED  *  NEWS CHOPPERS ON THE SCENE  *  STAY TUNED TO CH 3  *"
	_cut("rep", 10.0)
	_say("We interrupt this program for a special bulletin. I'm on a rooftop downtown, and something enormous is moving out there.", 7.0)
	set_process(true)


func _stop() -> void:
	on_air = false
	set_process(false)
	_rep.visible = false
	_murmur.stop()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var tm: ShaderMaterial = main.tv_mat
	var vt: Texture2D = main.vcr.current_frame_texture()
	if vt != null:
		tm.set_shader_parameter("video_tex", vt)
	tm.set_shader_parameter("use_video", main.vcr.state == main.vcr.State.PLAYING)
	if _paused_tape:
		main.vcr._set_paused(false)
	elif main.vcr.state == main.vcr.State.IDLE:
		main.vcr._show_idle_status()
	if not _was_tv_on and main.vcr.tv_on:
		main.vcr.toggle_tv()


func _on_moment(kind: String) -> void:
	if kind == "start":
		_start()
		return
	if not on_air:
		return
	if kind == "end":
		_cut("rep", 99.0)
		_say(_pick(LINES["signoff"]), 6.0)
		_end_t = _T + 7.0
		return
	if kind == "enter" or _T < 8.0:
		_queued = kind                                    # (after the opening words)
		return
	if LINES.has(kind):
		var big := kind in ["tackle", "slam", "ice_beam", "fireball", "clash", "tail", "bk_arrive", "ufo_swarm", "abduct"]
		if big or _rng.randf() < 0.6:
			_cut("field", _rng.randf_range(6.0, 10.0))
		_say(_pick(LINES[kind]), 6.0)
		if big:
			_duck = 1.0


func _pick(list: Array) -> String:
	return str(list[_rng.randi() % list.size()])


func _say(text: String, _secs: float) -> void:
	_line = text
	_shown = 0.0
	_speak = 0.4 + text.length() / 16.0
	if not _murmur.playing:
		_murmur.play(_rng.randf() * 4.0)


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
	if not fight.active and _end_t < 0.0:
		_on_moment("end")
	# back to the reporter now and then; out to the cameras again after
	if _shot_t >= _next_cut:
		if _shot == "rep":
			_cut("field", _rng.randf_range(7.0, 12.0))
			if _queued != "" and LINES.has(_queued):
				_say(_pick(LINES[_queued]), 6.0)
				_queued = ""
		else:
			_cut("rep", _rng.randf_range(5.0, 8.0))
			if _speak <= 0.0:
				_say(_pick(LINES["filler"]), 6.0)
	_camera(delta)
	_animate(delta)
	# the caption types out as he speaks
	_shown = minf(_shown + delta * 22.0, _line.length())
	_caption.text = "\"" + _line.left(int(_shown)) + ("\"" if int(_shown) >= _line.length() else "")
	_speak -= delta
	if _speak <= 0.0 and _murmur.playing:
		_murmur.stop()
	_ticker.position.x -= delta * 40.0 * (_vp.size.x / 320.0)
	if _ticker.position.x < -_ticker.size.x:
		_ticker.position.x = _vp.size.x
	_live.visible = fmod(_T, 1.6) < 1.2
	# the headset: the news picture refreshes at half rate
	if Plat.low_power():
		_frame += 1
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if _frame % 2 == 0 else SubViewport.UPDATE_DISABLED
	# keep the TV on the broadcast (the VCR would otherwise put its own picture back)
	var tm: ShaderMaterial = main.tv_mat
	tm.set_shader_parameter("video_tex", _vp.get_texture())
	tm.set_shader_parameter("video_aspect", float(_vp.size.x) / float(_vp.size.y))
	tm.set_shader_parameter("use_video", true)


func _camera(delta: float) -> void:
	var shake := Vector3(sin(_T * 1.7), sin(_T * 2.3 + 1.0), 0.0) * 0.02
	var c := _fight_centre()
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
	var talk := 1.0 if _speak > 0.0 else 0.0
	var m: MeshInstance3D = _rp["mouth"]
	m.scale.y = 0.008 + 0.012 * talk * maxf(0.0, sin(_T * 15.0) * sin(_T * 4.1 + 1.0))
	_duck = move_toward(_duck, 0.0, delta * 0.7)
	var look_target := 1.0 if (_shot == "rep" and fmod(_T, 9.0) > 6.5) else 0.0
	_look = move_toward(_look, look_target, delta * 1.5)
	(_rp["head"] as Node3D).rotation = Vector3(0.05 * sin(_T * 1.3) * talk + 0.2 * _duck, 1.9 * _look + 0.08 * sin(_T * 0.7), 0.04 * sin(_T * 0.9))
	(_rp["torso"] as Node3D).rotation = Vector3(0.25 * _duck, 0.5 * _look, 0.0)
	(_rp["man"] as Node3D).position.y = -0.12 * _duck
	(_rp["arm_l"] as Node3D).rotation = Vector3(-0.5 - 0.4 * talk * (0.5 + 0.5 * sin(_T * 2.2)) - 0.6 * _look, 0.0, -0.15)
	(_rp["fore_l"] as Node3D).rotation = Vector3(-0.6 * talk, 0.0, 0.0)


# ---- what he says

const LINES := {
	"enter": ["They're both coming in from opposite ends of the city. The ground is shaking up here.",
		"There it is. Two of them. I never thought I'd say that on the air."],
	"faceoff": ["They've stopped. They're staring each other down. I can hear them from here.",
		"That roar shattered windows three blocks away. The big ape is answering it."],
	"grapple": ["They're locked together, shoving, neither one giving an inch.",
		"They've grabbed hold of each other. The whole skyline is swaying."],
	"bite": ["The white one has its jaws on the ape's shoulder!", "A savage bite! King Gaboon is reeling!"],
	"punch": ["King Gaboon lands a blow right across its jaw!", "A punch you could feel in your teeth, folks."],
	"tail": ["It spun around and caught him with that enormous tail!", "That tail swept him clean off his feet!"],
	"tackle": ["The ape is down! He's down behind the towers!", "A head-on charge, and King Gaboon goes over!"],
	"slam": ["He's thrown it! The white one is down in a cloud of dust!", "King Gaboon picked it up and slammed it into the street!"],
	"circle": ["They're circling now. Catching their breath, if monsters breathe.", "A lull. But nobody down there believes it's over."],
	"roars": ["Listen to that. I don't think there's a glass window left on Fifth Street.", "They're roaring at each other across the rooftops."],
	"ice_beam": ["Its back is glowing! It's breathing... ice? The ape is freezing solid!", "A beam of pure cold! I can see frost forming from here!"],
	"fireball": ["He's holding fire in his hands! He's thrown it!", "A ball of fire! It hit the white one square in the chest!"],
	"clash": ["They've hit each other at the same moment! Both of them are staggering!", "Head to head! Neither one is standing straight!"],
	"g_retreat": ["The ape is thawing out and backing away. He's leaving!", "King Gaboon is retreating into the city."],
	"k_retreat": ["The white one is limping off, smoke trailing behind it.", "It's turning away. It's had enough."],
	"k_victory": ["The white one is roaring over the city. It's claimed the night.", "Listen to that victory cry."],
	"g_victory": ["King Gaboon beats his chest. There's no doubt who won tonight.", "He's standing tall over the skyline."],
	"bk_arrive": ["Wait. Something else is coming up behind them. A third one! Black as night!",
		"There's another one! It's bigger than both of them!"],
	"bk_roar": ["Listen to that! Its stripes are glowing like the signs on Main Street!", "All three of them, roaring at each other. God help us."],
	"ufo_swarm": ["Lights in the clouds... dozens of them. Those are not helicopters.", "Flying saucers! A whole fleet of them, circling the monsters!"],
	"abduct": ["Beams of light! They're lifting them! All three of them are leaving the ground!", "They're being pulled up into the sky. I can't believe what I'm seeing."],
	"fleet_leaves": ["They're gone. Up into the clouds, monsters and all.", "And just like that, the sky is empty."],
	"both_exit": ["They're both walking away. Nobody won. The city lost.", "Each going their own way, for now."],
	"filler": ["If you're just joining us: two giant creatures are fighting downtown. Stay indoors.",
		"Authorities advise residents to keep away from windows. Well, I'm on a roof, so.",
		"Our cameras are on several rooftops. We'll stay with this as long as we can.",
		"I've covered fires, floods and a strike at the docks. Nothing like this."],
	"signoff": ["And that's it. They're gone, into the night. This has been a special report. Back to your regular program.",
		"The city is quiet again. Reporting live from downtown, for Channel 3. Good night."],
}


# an old TV voice: a muffled, pitched murmur in syllables (no real words; his words are in the caption)
static func _make_murmur() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 6
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var ph := 0.0
	var lp := 0.0
	var bp := 0.0
	var syl := 0.0
	var syl_len := 0.18
	var pitch := 115.0
	for i in n:
		var t := float(i) / rate
		syl += 1.0 / rate
		if syl > syl_len:
			syl = 0.0
			syl_len = rng.randf_range(0.09, 0.26)
			pitch = rng.randf_range(100.0, 140.0)
		var env := sin(PI * clampf(syl / syl_len, 0.0, 1.0))
		if fmod(t, 2.3) > 2.05:
			env *= 0.1                               # a breath now and then
		ph += pitch / rate
		var buzz := 2.0 * fmod(ph, 1.0) - 1.0
		lp += (buzz - lp) * 0.18                     # muffled, like a small TV speaker
		bp += (lp - bp) * 0.04
		var s := (lp - bp) * env * 0.9
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


# ---- small builders

static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.disable_fog = true
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
