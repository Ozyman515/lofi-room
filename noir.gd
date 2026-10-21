extends Node3D
## Noir Night (an easter egg). Two ways in: type DETECT on the wall phone's keypad and press JOIN, or turn
## the TV's channel knob after midnight (12 to 4 am) while the TV is on with nothing playing.
## The room turns into an old detective film: the colour drains away, the other lights go out and the desk
## lamp is the only light, striped shadows of blinds fall across the floor and wall, rain pours, the incense
## fills the room with smoke, and "Gritty Noir" by KonstantinPazuzuStudio plays instead of the lofi music. On the desk: a typewriter (in
## place of the keyboard) that types up tonight's case, a revolver, one round, a whiskey (in place of the mug,
## click it to take a sip) and a lit cigarette, with a fedora, an open case file and a badge.
## Switch the desk lamp off and it all comes back. In a shared room the host's Noir Night is everybody's.

const Props := preload("res://noir_props.gd")
const Plat := preload("res://platform.gd")

const MUSIC := "res://noir/konstantinpazuzustudio-gritty-noir.ogg"
const POSTER := "res://noir/noir_poster.png"
const MUSIC_CREDIT := "Now playing:  Gritty Noir (ASMR Noir Jazz)  by KonstantinPazuzuStudio"      # music/CREDITS.txt
const FADE := 2.5                     # seconds for the colour to drain / come back
const SAT := 0.06                     # how much colour is left
const DESK_Y := 0.785

var main: Node3D
var active := false
var amount := 0.0                     # 0 = normal room, 1 = full noir
var _remote := false                  # following the host's Noir Night
var _desk: Node3D
var _typewriter: Node3D
var _text: Label3D
var _whisky: MeshInstance3D
var _surface: MeshInstance3D
var _ice: MeshInstance3D
var _sips := 0
var _glasses := 0                     # glasses finished tonight; the third one sends you to sleep
const GLASSES_TO_NAP := 3
var _bottle_liquid: MeshInstance3D
var _blinds: Array[MeshInstance3D] = []
var _music: AudioStreamPlayer
var _clack: AudioStreamPlayer3D
var _ding: AudioStreamPlayer3D
var _static: AudioStreamPlayer
var _saved := {}
var _lit_incense := false
var _case := ""
var _typed := 0.0
var _clack_t := 0.0
var _sat_base := 1.25
var _con_base := 1.0
var _bri_base := 1.0
var _desk_lamp := -1
var _rng := RandomNumberGenerator.new()


const VISITOR_CHANCE := 0.33         # how often the grey visitor is sitting on the bed when Noir Night starts
var visitor: Node3D
var force_visitor := false


func setup(m: Node3D) -> void:
	main = m
	visitor = load("res://stressed_alien.gd").new()
	visitor.name = "NoirVisitor"
	main.room.add_child(visitor)
	visitor.build()
	visitor.position = Vector3(-0.95, 0.0, -0.75)        # on the edge of the bed, facing the desk lamp
	visitor.rotation.y = PI / 2.0
	visitor.visible = false
	_rng.randomize()
	process_priority = 50             # after the incense, which also sets the colour
	for gi in main.light_groups.size():
		if str(main.light_groups[gi]["name"]) == "Desk lamp":
			_desk_lamp = gi
	_build_desk()
	_build_blinds()
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_static = AudioStreamPlayer.new()
	_static.stream = _make_static()
	add_child(_static)
	if main.net_phone != null:
		main.net_phone.secret_cb = func() -> void: request_start()
	set_process(false)


# ---- ways in

func on_channel_turned() -> void:
	var h := int(Time.get_datetime_dict_from_system()["hour"])
	var v = main.vcr
	var quiet: bool = v.tv_on and not main.console_on and not (v.state == v.State.PLAYING or v.state == v.State.PAUSED)
	if (h < 4 or OS.get_environment("LOFI_NOIR_ANYTIME") == "1") and quiet and not active:
		_static.play()                # the dead channel hisses, then the room changes
		await get_tree().create_timer(1.2).timeout
		request_start()


func request_start() -> void:
	if active or main.egg_active:
		return
	var ng = main.net_game
	if ng != null and ng.net.is_online() and not ng.net.is_host():
		ng.net.send_var(1, ng.Net.K_EVENT, {"k": "noir_on"})          # the host's room: ask the host
		return
	start()


func start() -> void:
	if active:
		return
	active = true
	var e: Environment = main.world_env
	_sat_base = e.adjustment_saturation if amount <= 0.0 else _sat_base
	_con_base = e.adjustment_contrast if amount <= 0.0 else _con_base
	_bri_base = e.adjustment_brightness if amount <= 0.0 else _bri_base
	if main.incense != null and main.incense._base_read:
		_sat_base = main.incense._sat_base
	# lights: only the desk lamp
	_saved["lights"] = []
	for gi in main.light_groups.size():
		_saved["lights"].append(main.is_light_on(gi))
		main.set_light(gi, gi == _desk_lamp)
	main.weather.begin_noir()
	# as little electricity as possible: the monitor, the arcade and the TV go off (the console too, unless
	# somebody is playing on it); they come back on afterwards
	if not _remote:
		_power_down()
	# smoke: light the incense if it isn't
	_lit_incense = main.incense != null and not main.incense.lit
	if _lit_incense:
		main.incense.toggle()
	# the music
	_saved["music_paused"] = main.bank.playing and not main.bank.stream_paused
	if _saved["music_paused"]:
		main.bank.stream_paused = true
	if _music.stream == null:
		var s := AudioStreamOggVorbis.load_from_file(MUSIC)
		if s != null:
			s.loop = true
			_music.stream = s
	_music.volume_db = -80.0
	if _music.stream != null:
		_music.play()
		main.updater.show_toast(MUSIC_CREDIT, 6.0)
	# the poster: a dark-deco city in the rain
	if main.poster != null:
		var pimg := Image.load_from_file(POSTER)
		if pimg != null and not pimg.is_empty():
			main.poster.show_override(pimg)
	# sometimes there's somebody on the edge of the bed, having a worse night than you
	visitor.visible = force_visitor or randf() < VISITOR_CHANCE
	force_visitor = false
	# the desk
	_sips = 0
	_glasses = 0
	_set_whisky()
	_set_bottle()
	_desk.visible = true
	main.keyboard_node.visible = false
	main.mug_node.visible = false
	for b in _blinds:
		b.visible = true
	new_case()
	set_process(true)


func _power_down() -> void:
	_saved["monitor"] = main.monitor_on
	main._set_monitor(false)
	_saved["arcade"] = main.arcade_on
	if main.arcade_on and not (main.game_mode and main.held_pad_idx == -1):
		main.set_arcade_on(false)
	_saved["tv"] = main.vcr.tv_on
	_saved["console"] = main.console_on
	var playing: bool = main.game_mode or (main.net_game != null and main.net_game.guests_playing())
	if main.console_on and not playing and main.slot_cart != "neo" and main.slot_cart != "egg":
		main.toggle_console()
	if main.vcr.tv_on and not main.console_on:
		main.vcr.toggle_tv()


func stop() -> void:
	if not active:
		return
	active = false
	main.weather.end_noir()
	visitor.visible = false
	if main.poster != null:
		main.poster.clear_override()
	if bool(_saved.get("console", false)) and not main.console_on:
		main.toggle_console()
	if bool(_saved.get("tv", false)) and not main.vcr.tv_on:
		main.vcr.toggle_tv()
	if bool(_saved.get("arcade", false)) and not main.arcade_on:
		main.set_arcade_on(true)
	if bool(_saved.get("monitor", false)):
		main._set_monitor(true)
	var lights: Array = _saved.get("lights", [])
	for gi in mini(lights.size(), main.light_groups.size()):
		main.set_light(gi, bool(lights[gi]))
	if _lit_incense and main.incense != null and main.incense.lit:
		main.incense.toggle()
	_lit_incense = false
	if bool(_saved.get("music_paused", false)):
		main.bank.stream_paused = false
	_saved = {}


func _process(delta: float) -> void:
	# the desk lamp going off ends it (the host's lamp, in a shared room)
	if active and not _remote and _desk_lamp >= 0 and not main.is_light_on(_desk_lamp):
		stop()
		_broadcast()
	amount = move_toward(amount, 1.0 if active else 0.0, delta / FADE)
	var e: Environment = main.world_env
	var inc = main.incense
	var base := _sat_base
	if inc != null and inc._base_read:
		base = lerpf(inc._sat_base, inc._sat_base * 0.86, inc.haze)
	e.adjustment_saturation = lerpf(base, SAT, amount)
	e.adjustment_contrast = lerpf(_con_base, _con_base * 1.18, amount)
	e.ambient_light_energy *= lerpf(1.0, 0.4, amount)     # main.gd sets it fresh each frame: the desk lamp does the lighting
	e.adjustment_brightness = lerpf(_bri_base, _bri_base * 0.88, amount)
	var mvol: float = main.bank.master if main.bank != null else 0.7
	_music.volume_db = linear_to_db(maxf(amount * mvol * 0.9, 0.0001))
	for b in _blinds:
		(b.material_override as StandardMaterial3D).albedo_color.a = 0.22 * amount
	_type_tick(delta)
	if not active and amount <= 0.0:
		_music.stop()
		_desk.visible = false
		main.keyboard_node.visible = true
		main.mug_node.visible = true
		for b in _blinds:
			b.visible = false
		e.adjustment_saturation = base
		e.adjustment_contrast = _con_base
		e.adjustment_brightness = _bri_base
		set_process(false)


# ---- the desk

func _build_desk() -> void:
	_desk = Node3D.new()
	_desk.visible = false
	main.room.add_child(_desk)
	# typewriter where the keyboard is, facing the chair
	_typewriter = Props.typewriter()
	_typewriter.position = Vector3(1.45, DESK_Y, -1.40)
	_desk.add_child(_typewriter)
	_text = _typewriter.get_node("Sheet/Text")
	_clack = AudioStreamPlayer3D.new()
	_clack.stream = _make_clack()
	_clack.unit_size = 1.2
	_clack.max_polyphony = 4
	_typewriter.add_child(_clack)
	_ding = AudioStreamPlayer3D.new()
	_ding.stream = _make_ding()
	_ding.unit_size = 1.5
	_typewriter.add_child(_ding)
	main.interactables.append({"node": _typewriter, "half": Vector3(0.19, 0.12, 0.16), "guest_ok": true,
		"when": func() -> bool: return active,
		"label": func() -> String: return "THE TYPEWRITER  (a new case)", "cb": func() -> void: new_case()})
	# the still life by the lamp, where the mug was
	var still := Props.build(_desk, Vector3(1.97, DESK_Y, -1.43), -0.35)
	var glass: Node3D = still.get_node("Tumbler")
	_whisky = glass.get_node("Whisky")
	_surface = glass.get_node("Surface")
	_ice = glass.get_node("Ice")
	main.interactables.append({"node": glass, "half": Vector3(0.05, 0.11, 0.05), "guest_ok": true,
		"when": func() -> bool: return active,
		"label": func() -> String: return "A SIP OF WHISKEY" if _sips < 3 else "THE GLASS IS EMPTY", "cb": _sip})
	# the bottle, beside the glass: pour another
	var bottle := Props.bottle()
	bottle.position = Vector3(2.25, DESK_Y, -1.42)
	_desk.add_child(bottle)
	_bottle_liquid = bottle.get_node("Liquid")
	main.interactables.append({"node": bottle, "half": Vector3(0.05, 0.16, 0.05), "guest_ok": true,
		"when": func() -> bool: return active,
		"label": _bottle_label, "cb": _pour})
	# the detective's things on the other side of the typewriter
	var hat := Props.fedora()
	hat.position = Vector3(1.12, 1.375, -1.72)         # hung on the monitor's top left corner
	hat.rotation = Vector3(0.1, 0.4, 0.28)
	_desk.add_child(hat)
	var file := Props.case_file()
	file.position = Vector3(1.0, DESK_Y, -1.33)
	file.rotation.y = 0.12
	_desk.add_child(file)
	var badge := Props.badge()
	badge.position = Vector3(1.13, DESK_Y + 0.006, -1.25)
	badge.rotation.y = -0.4
	_desk.add_child(badge)


func _sip() -> void:
	if _sips >= 3:
		return
	_sips += 1
	_set_whisky()
	if _sips >= 3:
		_glasses += 1
		_set_bottle()
		if _glasses >= GLASSES_TO_NAP:
			_pass_out()
		elif _glasses == GLASSES_TO_NAP - 1:
			main.updater.show_toast("The room tilts a little.", 3.0)


func _bottle_label() -> String:
	if _glasses >= GLASSES_TO_NAP:
		return "OLD GUMSHOE  (that's enough for tonight)"
	if _glasses >= GLASSES_TO_NAP - 1 and _sips >= 3:
		return "POUR ONE MORE  (the last)"
	if _sips >= 3:
		return "POUR ANOTHER"
	return "OLD GUMSHOE  (finish your glass first)"


func _pour() -> void:
	if _sips < 3 or _glasses >= GLASSES_TO_NAP:
		return
	_sips = 0
	_set_whisky()
	_set_bottle()


func _set_bottle() -> void:
	# full for the first glass's refill, a little lower with each one poured
	var poured := _glasses + (1 if _sips < 3 and _glasses > 0 else 0)
	var k := clampf(1.0 - poured * 0.3, 0.1, 1.0)
	_bottle_liquid.scale = Vector3(1.0, k, 1.0)
	_bottle_liquid.position.y = 0.008 + 0.075 * k


# three glasses down: the desk lamp blurs and you wake up from a nap (the room starts fresh, colour and all)
func _pass_out() -> void:
	await get_tree().create_timer(1.5).timeout
	if not active:
		return
	stop()                            # put the lights, music and weather back first, so the new room wakes up normal
	main.go_to_sleep("You dozed off at the desk. The rain is still falling...")


func _set_whisky() -> void:
	var k := 1.0 - _sips / 3.0
	_whisky.visible = k > 0.0
	_whisky.scale = Vector3(1.0, maxf(k, 0.01), 1.0)
	_whisky.position.y = 0.014 + 0.017 * k
	_surface.visible = k > 0.0
	_surface.position.y = 0.014 + 0.034 * k
	_ice.position.y = 0.018 + 0.029 * k


# ---- tonight's case, typed out a letter at a time

const CASES := {
	"title": ["THE VANISHING TREATS", "THE CARTRIDGE THAT KNEW TOO MUCH", "A HIGH SCORE IN THE RAIN",
		"THE LAST SLICE", "THE MISSING CONTROLLER", "BLUE MOON OVER THE ARCADE", "THE SAVE FILE",
		"THE STOLEN BEANBAG", "SMOKE AND SAXOPHONES", "THE NAP THAT WENT TOO LONG", "THE DIARY'S LAST PAGE",
		"THE MAN WHO PRESSED START"],
	"open": ["She walked in out of the rain like trouble wearing a raincoat.", "It was a Tuesday. It's always a Tuesday.",
		"The rain hadn't let up in three days, and neither had my landlord.", "Somebody in this town was lying. I just had to figure out who.",
		"The phone rang twice and stopped. I didn't like it.", "The city never sleeps. Neither does the cat.",
		"I poured a drink and stared at the window. The window stared back."],
	"what": ["the treat bag is empty", "the high score was erased", "a cartridge went missing from the console",
		"the last slice of pizza vanished", "the TV was left on the static channel", "somebody moved the beanbag two inches to the left",
		"the diary is missing a page", "the controller cable was tied in a knot", "the poster on the wall was hung crooked"],
	"suspect": ["Kitty", "Lola", "the landlord", "the guy from 4B", "a dame named Marlowe", "the arcade machine",
		"the incense", "the pizza delivery kid", "nobody. That's what bothers me"],
	"alibi": ["asleep on the bed, or so she says", "claims to have been in the drawer all night", "won't talk without a lawyer",
		"has a paw print on the evidence", "says the rain did it", "was seen near the treats at midnight",
		"plays a mean saxophone and an even meaner hand of cards"],
	"close": ["I lit another cigarette and let the rain do the talking.", "Case closed. Probably.", "Some cases you solve. This one solved me.",
		"I'd sleep on it. The cat had the right idea.", "The rain kept falling. So did my standards.", "Tomorrow, I'd find the truth. Tonight, the sax."],
}


func new_case() -> void:
	var c := CASES
	var who := _pick(c["suspect"])
	var t := "CASE #%04d\n%s\n\n%s Word is %s. The prime suspect: %s, who %s.\n\n%s" % [
		_rng.randi_range(1, 9999), _pick(c["title"]), _pick(c["open"]), _pick(c["what"]), _name_swap(who), _pick(c["alibi"]), _pick(c["close"])]
	_case = t
	_typed = 0.0
	_text.text = ""


# the cats' names, as the player named them
func _name_swap(who: String) -> String:
	if main.cats != null:
		if who == "Kitty":
			return main.cats.name_of("tux")
		if who == "Lola":
			return main.cats.name_of("calico")
	return who


func _pick(list: Array) -> String:
	return str(list[_rng.randi() % list.size()])


func _type_tick(delta: float) -> void:
	if _case == "" or int(_typed) >= _case.length() or not active:
		return
	var before := int(_typed)
	_typed += delta * 22.0
	var n := mini(int(_typed), _case.length())
	_text.text = _case.left(n)
	_clack_t -= delta
	if n > before and _clack_t <= 0.0 and _case[n - 1] != " ":
		_clack.pitch_scale = _rng.randf_range(0.9, 1.15)
		_clack.play()
		_clack_t = 0.035
	if n >= _case.length():
		_ding.play()                # the bell at the end of the line


# ---- blinds: the light through the window slats, across the floor and up the right-hand wall

func _build_blinds() -> void:
	var img := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		var band := fposmod(y, 32.0) / 32.0
		var a := smoothstep(0.0, 0.12, band) * (1.0 - smoothstep(0.5, 0.62, band))     # soft-edged bright slat
		for x in 64:
			var edge := smoothstep(0.0, 0.15, x / 64.0) * (1.0 - smoothstep(0.85, 1.0, x / 64.0))
			img.set_pixel(x, y, Color(1, 0.97, 0.9, a * edge))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	for spec in [
			[Vector3(0.6, 0.012, -0.35), Vector3(-PI / 2.0, 0.55, 0.0), Vector2(1.5, 2.2)],       # the floor, slanting in
			[Vector3(2.485, 1.15, 0.15), Vector3(0.0, -PI / 2.0, 0.18), Vector2(1.3, 1.6)]]:      # the right wall
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1, 1, 1, 0.0)
		m.disable_fog = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var q := QuadMesh.new()
		q.size = spec[2]
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.position = spec[0]
		mi.rotation = spec[1]
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.room.add_child(mi)
		_blinds.append(mi)


# ---- shared rooms

func state() -> bool:
	return active


func apply_remote(on: bool) -> void:
	_remote = true
	if on and not active:
		start()
	elif not on and active:
		stop()


func end_remote() -> void:
	if _remote and active:
		stop()
	_remote = false


func on_guest_event(d: Dictionary) -> void:
	if str(d.get("k", "")) == "noir_on":
		request_start()


func _broadcast() -> void:
	pass                              # the host's game state carries "noir"; nothing extra to send


# ---- sounds, made here

static func _make_clack() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.06 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var t := float(i) / rate
		var s := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) + sin(t * TAU * 1900.0) * exp(-t * 60.0) * 0.4
		data.encode_s16(i * 2, int(clampf(s * 0.6, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)


static func _make_ding() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.2 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s := (sin(t * TAU * 2093.0) + 0.5 * sin(t * TAU * 5230.0) * exp(-t * 6.0)) * exp(-t * 3.0)
		data.encode_s16(i * 2, int(clampf(s * 0.35, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)


static func _make_static() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.4 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for i in n:
		var t := float(i) / rate
		var env := smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(1.1, 1.4, t))
		data.encode_s16(i * 2, int(rng.randf_range(-1.0, 1.0) * env * 0.35 * 32767.0))
	return _wav(data, rate)


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
