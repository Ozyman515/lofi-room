extends Node3D
## Noir Night (an easter egg), now an office of its own. Find it first: type DETECT on the wall phone's keypad
## and press JOIN, or turn the game room TV's channel knob after midnight (12 to 4 am) while the TV is on with
## nothing playing. "Something changed..." From then on a red book sticks out of the bookcase by the study desk:
## pull it and the bookcase swings open onto a hidden detective's office.
## Inside it's an old detective film: the colour drains away, the green desk lamp is the light, the slats of
## the blinds fall across the floor, rain runs down the window, a neon sign across the street blinks, cigarette
## smoke hangs in the air and "Lofi Jazz Noir Cinematic Soundtrack - Late Night" by Yulius2Tudio plays. The grey
## visitor sits across the desk telling tonight's case while the typewriter types it up. A revolver, one round,
## a whiskey (click it to take a sip) and the bottle, a lit cigarette, the fedora, an open case file, a badge.
## Step back out and the colour comes back. In a shared room the host's discovery is everybody's.

const Props := preload("res://noir_props.gd")
const Plat := preload("res://platform.gd")

const MUSIC := "res://noir/yulius2tudio-lofi-jazz-noir-late-night.ogg"
const POSTER := "res://noir/noir_poster.png"
const MUSIC_CREDIT := "Now playing:  Lofi Jazz Noir Cinematic Soundtrack - Late Night  by Yulius2Tudio (Youssef Canar)"      # music/CREDITS.txt
const FADE := 1.6                     # seconds for the colour to drain / come back
const SAT := 0.06                     # how much colour is left
const DESK_Y := 0.785
# the office (room coordinates): behind the study, through the bookcase by the desk
const X0 := 0.5
const X1 := 4.55
const Z0 := 10.45
const Z1 := 14.2
const DESK_SHIFT := Vector3(0.95, 0.0, 14.15)   # the desk props were laid out for the old bedroom desk: moved here

var main: Node3D
var office: Node3D                    # everything in the office (apartment.gd hangs it in the office room)
var found := false                    # the office has been discovered (saved; in a shared room, the host's)
var active := false                   # I'm in the office
var amount := 0.0                     # 0 = normal, 1 = full noir
var _remote := false
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
var _creak: AudioStreamPlayer
var _case := ""
var _typed := 0.0
var _clack_t := 0.0
var _sat_base := 1.25
var _con_base := 1.0
var _bri_base := 1.0
var _base_read := false
var _rng := RandomNumberGenerator.new()
var _neon_m: StandardMaterial3D
var _neon_l: OmniLight3D
var _neon_t := 0.0
var _neon_sign: Label3D
var _neon_halo: Label3D
var _neon_sign_light: OmniLight3D
var _folds: Array = []                  # [fold, side, window edge, index]
var _tiebacks: Array[MeshInstance3D] = []
var _cur_cx := 0.0
var _cur_closed := false
var _cur := 0.0                         # 0 open .. 1 drawn
var _win: Array = []                    # the windows across the street: {m, on, x (the walker), v, stop}
var _win_t := 2.0
var _lamp_t := 12.0
var _fan: Node3D
var _haze: Array[MeshInstance3D] = []
var _rain_m: ShaderMaterial
var _credit_shown := false

var visitor: Node3D
var force_visitor := false            # (kept for the debug window; he's always there now)
var _bubble: Node3D                  # the visitor's speech bubble: he tells you the case as it is typed
var _bubble_text: Label3D
const BUBBLE_W := 1.0
const BUBBLE_H := 0.5


func setup(m: Node3D) -> void:
	main = m
	office = Node3D.new()
	office.name = "NoirOfficeKit"
	main.add_child(office)
	visitor = load("res://stressed_alien.gd").new()
	visitor.name = "NoirVisitor"
	office.add_child(visitor)
	visitor.build(0.5)                                    # sitting
	_build_bubble()
	_rng.randomize()
	process_priority = 50             # after the incense, which also sets the colour
	_build_office()
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_static = AudioStreamPlayer.new()
	_static.stream = _make_static()
	add_child(_static)
	_creak = AudioStreamPlayer.new()
	_creak.stream = _make_creak()
	_creak.volume_db = -6.0
	add_child(_creak)
	if main.net_phone != null:
		main.net_phone.secret_cb = func() -> void: request_start()
	var cfg := ConfigFile.new()
	if cfg.load(main.SETTINGS_FILE) == OK:
		found = bool(cfg.get_value("room", "noir_found", false))
	new_case()


# ---- ways to find it

func on_channel_turned() -> void:
	var h := int(Time.get_datetime_dict_from_system()["hour"])
	var v = main.vcr
	var quiet: bool = v.tv_on and not main.console_on and not (v.state == v.State.PLAYING or v.state == v.State.PAUSED)
	if (h < 4 or OS.get_environment("LOFI_NOIR_ANYTIME") == "1") and quiet:
		_static.play()                # the dead channel hisses, then something changes
		await get_tree().create_timer(1.2).timeout
		request_start()


# DETECT on the phone (or the channel trick): the office is found
func request_start() -> void:
	if main.egg_active:
		return
	var ng = main.net_game
	if ng != null and ng.net.is_online() and not ng.net.is_host():
		ng.net.send_var(1, ng.Net.K_EVENT, {"k": "noir_on"})          # the host's apartment: ask the host
		return
	discover()


func discover() -> void:
	if found:
		main.updater.show_toast("The rain taps on the glass. You already know where to look.", 5.0)
		return
	set_found(true)
	_creak.play()
	main.updater.show_toast("Something changed...  somewhere in the apartment, a book isn't where it was.", 7.0)


func set_found(on: bool) -> void:
	found = on
	if not _remote:
		var cfg := ConfigFile.new()
		cfg.load(main.SETTINGS_FILE)
		cfg.set_value("room", "noir_found", on)
		cfg.save(main.SETTINGS_FILE)


# (kept so older callers still work: the office is the noir now)
func start() -> void:
	discover()


func stop() -> void:
	pass


# ---- per frame: the colour drains while I'm in the office

func _process(delta: float) -> void:
	var inside: bool = main.apartment != null and main.apartment.current == "noir"
	if inside and not active:
		_enter()
	elif not inside and active:
		active = false
	var e: Environment = main.world_env
	if amount <= 0.0 and not active:
		_sat_base = e.adjustment_saturation
		_con_base = e.adjustment_contrast
		_bri_base = e.adjustment_brightness
		if main.incense != null and main.incense._base_read:
			_sat_base = main.incense._sat_base
	var was := amount
	amount = move_toward(amount, 1.0 if active else 0.0, delta / FADE)
	if amount > 0.0 or was > 0.0:
		var inc = main.incense
		var base := _sat_base
		if inc != null and inc._base_read:
			base = lerpf(inc._sat_base, inc._sat_base * 0.86, inc.haze)
		e.adjustment_saturation = lerpf(base, SAT, amount)
		e.adjustment_contrast = lerpf(_con_base, _con_base * 1.18, amount)
		e.ambient_light_energy *= lerpf(1.0, 0.35, amount)     # main.gd sets it fresh each frame: the desk lamp does the lighting
		e.adjustment_brightness = lerpf(_bri_base, _bri_base * 0.88, amount)
		if amount <= 0.0:
			e.adjustment_saturation = base
			e.adjustment_contrast = _con_base
			e.adjustment_brightness = _bri_base
	var mvol: float = main.bank.master if main.bank != null else 0.7
	_music.volume_db = linear_to_db(maxf(amount * mvol * 0.9, 0.0001))
	if main.bank != null:
		main.bank.set_duck(amount)            # the lofi music fades down in here
	if amount <= 0.0 and not active and _music.playing:
		_music.stop()
	# the office keeps living while anyone can see it
	if office.is_visible_in_tree():
		_type_tick(delta)
		_bubble_tick()
		_office_tick(delta)


func _enter() -> void:
	active = true
	if _music.stream == null:
		var s := AudioStreamOggVorbis.load_from_file(MUSIC)
		if s != null:
			s.loop = true
			_music.stream = s
	if _music.stream != null and not _music.playing:
		_music.volume_db = -80.0
		_music.play()
		if not _credit_shown:
			_credit_shown = true
			main.updater.show_toast(MUSIC_CREDIT, 6.0)
	if _case == "" or int(_typed) >= _case.length():
		new_case()


func _office_tick(delta: float) -> void:
	# the neon sign across the street: steady, with the odd stutter
	_neon_t -= delta
	var on := true
	if _neon_t < 0.0:
		_neon_t = _rng.randf_range(2.5, 7.0)
	elif _neon_t < 0.35:
		on = int(_neon_t * 20.0) % 2 == 0
	_neon_m.emission_energy_multiplier = 3.2 if on else 0.4
	var lit := 1.0 if on else 0.15
	_neon_sign.modulate = Color(1.0, 0.75, 0.75) * lit + Color(0.12, 0.03, 0.03) * (1.0 - lit)
	_neon_sign.outline_modulate.a = lit
	_neon_halo.outline_modulate.a = 0.35 * lit
	_neon_sign_light.light_energy = 2.0 * lit
	_windows_tick(delta)
	# the curtains, drawn or open
	var was_cur := _cur
	_cur = move_toward(_cur, 1.0 if _cur_closed else 0.0, delta / 1.2)
	if _cur != was_cur:
		_set_curtains(_cur)
	_neon_l.light_energy = (0.9 if on else 0.1) * (1.0 - 0.85 * _cur)
	if _fan != null:
		_fan.rotation.y += delta * 1.1
	for i in _haze.size():
		var h := _haze[i]
		h.position.x = 2.5 + sin(Time.get_ticks_msec() / 1000.0 * 0.05 + i * 2.0) * 0.6
	for b in _blinds:
		(b.material_override as StandardMaterial3D).albedo_color.a = (0.10 + 0.14 * maxf(amount, 0.4)) * (1.0 - 0.85 * _cur)


# the windows across the street: now and then someone walks past behind a lit one (sometimes stopping a moment),
# and now and then a light goes on or off
func _windows_tick(delta: float) -> void:
	if _win.is_empty():
		return
	_win_t -= delta
	if _win_t <= 0.0:
		_win_t = _rng.randf_range(2.0, 6.0)
		var w: Dictionary = _win[_rng.randi() % _win.size()]
		if w["on"] and w["v"] == 0.0:
			var dir := 1.0 if _rng.randf() < 0.5 else -1.0
			w["x"] = -0.55 if dir > 0.0 else 0.55
			w["v"] = dir * _rng.randf_range(0.12, 0.3)
			w["stop"] = _rng.randf_range(1.0, 4.0) if _rng.randf() < 0.35 else 0.0
			(w["m"] as ShaderMaterial).set_shader_parameter("tall", _rng.randf_range(0.9, 1.12))
	_lamp_t -= delta
	if _lamp_t <= 0.0:
		_lamp_t = _rng.randf_range(8.0, 22.0)
		var w: Dictionary = _win[_rng.randi() % _win.size()]
		if w["v"] == 0.0:
			w["on"] = not w["on"]
			(w["m"] as ShaderMaterial).set_shader_parameter("lit", 1.0 if w["on"] else 0.0)
	for w in _win:
		if w["v"] == 0.0:
			continue
		var x: float = w["x"]
		if w["stop"] > 0.0 and absf(x) < 0.06:
			w["stop"] = maxf(0.0, w["stop"] - delta)
		else:
			x += w["v"] * delta
			w["x"] = x
		if absf(x) > 0.6:
			w["v"] = 0.0
		(w["m"] as ShaderMaterial).set_shader_parameter("sil", Vector3(x, 1.0 if w["v"] != 0.0 else 0.0, 1.0))


func _window_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
uniform float lit = 1.0;
uniform float tint = 1.0;
uniform float tall = 1.0;
uniform vec3 sil = vec3(-1.0, 0.0, 1.0);    // the walker: x across the window (m, 0 = middle), shown, -
float box(vec2 p, vec2 b, float r) { return length(max(abs(p) - b, 0.0)) - r; }
void fragment() {
	vec2 m = vec2((UV.x - 0.5) * 0.6, (1.0 - UV.y) * 0.75);     // metres: x from the middle, y up from the sill
	vec3 room = vec3(1.0, 0.86, 0.62) * tint * (0.7 + 0.45 * m.y / 0.75);
	vec3 dark = vec3(0.07, 0.075, 0.09) + vec3(0.07) * smoothstep(0.1, 0.9, UV.x * 0.6 + (1.0 - UV.y) * 0.5);   // dark glass, a sheen
	// someone passing: a head and shoulders
	vec2 q = (m - vec2(sil.x, 0.0)) / tall;
	float body = 1.0 - smoothstep(-0.005, 0.005, box(q - vec2(0.0, 0.12), vec2(0.12, 0.2), 0.06));
	float neck = 1.0 - smoothstep(-0.005, 0.005, box(q - vec2(0.0, 0.4), vec2(0.025, 0.05), 0.0));
	float head = 1.0 - smoothstep(0.065, 0.075, length((q - vec2(0.0, 0.5)) * vec2(1.0, 0.85)));
	float s = max(max(body, neck), head) * sil.y;
	vec3 col = mix(dark, mix(room, room * 0.1, s), lit);
	// the frame and the glazing bars
	float fr = step(abs(m.x), 0.27) * step(0.03, m.y) * step(m.y, 0.72);
	fr *= step(0.012, abs(m.x)) * step(0.01, abs(m.y - 0.64));
	ALBEDO = mix(vec3(0.05, 0.045, 0.05), col, fr);
}
"""
	return sh


# t: 0 open (bunched at the sides, tied back) .. 1 drawn across the window
func _set_curtains(t: float) -> void:
	var e := t * t * (3.0 - 2.0 * t)
	for fd in _folds:
		var f: MeshInstance3D = fd[0]
		var side: float = fd[1]
		var edge: float = fd[2]
		var k: int = fd[3]
		var open_x := edge + side * (k * 0.065 - 0.06)
		var shut_x := lerpf(_cur_cx + side * 0.03, edge + side * 0.265, k / 5.0)
		f.position.x = lerpf(open_x, shut_x, e)
		var gap := lerpf(0.065, absf(edge + side * 0.265 - _cur_cx) / 5.0, e)
		f.scale.x = gap * 1.25 / 0.065
		f.rotation.y = side * (0.35 if k % 2 == 0 else -0.35) * lerpf(1.0, 0.6, e)
	for tb in _tiebacks:
		tb.visible = e < 0.15


# ---- the office

func _m(c: Color, rough := 0.8, emit := 0.0) -> StandardMaterial3D:
	return main._mat(c, rough, emit)


func _build_office() -> void:
	var o := office
	var wood := _m(Color(0.30, 0.18, 0.14), 0.6)
	var wood_dk := _m(Color(0.20, 0.11, 0.09), 0.6)
	var metal := _m(Color(0.25, 0.25, 0.27), 0.4)
	metal.metallic = 0.6
	var cx := (X0 + X1) / 2.0
	# the desk: a big old wooden one, facing the door
	var dc := Vector3(2.4, 0.0, 12.6)
	main._box(dc + Vector3(0, 0.76, 0), Vector3(1.6, 0.05, 0.8), wood, o)
	for sx in [-0.62, 0.62]:
		main._box(dc + Vector3(sx, 0.37, 0), Vector3(0.36, 0.74, 0.76), wood_dk, o)      # pedestals with drawers
		for dy in [0.2, 0.42, 0.62]:
			main._box(dc + Vector3(sx, dy, -0.385), Vector3(0.3, 0.16, 0.01), wood, o)
			main._sphere(dc + Vector3(sx, dy, -0.395), 0.012, _m(Color(0.8, 0.65, 0.35), 0.3), Vector3.ONE, o, 8)
	main._box(dc + Vector3(0, 0.45, 0.36), Vector3(0.9, 0.6, 0.02), wood_dk, o)           # modesty panel
	# green banker's lamp, the one light
	var lamp := Vector3(1.85, DESK_Y, 12.5)
	main._box(lamp + Vector3(0, 0.015, 0), Vector3(0.16, 0.03, 0.1), _m(Color(0.75, 0.6, 0.3), 0.3), o)
	main._cyl(lamp + Vector3(0, 0.2, 0), 0.01, 0.36, _m(Color(0.75, 0.6, 0.3), 0.3), o)
	var shade: MeshInstance3D = main._cyl(lamp + Vector3(0, 0.38, -0.02), 0.06, 0.32, _m(Color(0.1, 0.45, 0.25), 0.3, 0.6), o)
	shade.rotation.z = PI / 2.0
	shade.scale = Vector3(1.0, 1.0, 0.55)
	var ll := OmniLight3D.new()
	ll.position = lamp + Vector3(0.0, 0.3, 0.05)
	ll.light_color = Color(1.0, 0.85, 0.6)
	ll.light_energy = 1.4
	ll.omni_range = 3.4
	o.add_child(ll)
	# the detective's chair (yours) behind the desk, facing the door; the client's chair in front
	var chair_m := _m(Color(0.22, 0.10, 0.08), 0.5)
	var dch := Node3D.new()
	dch.position = Vector3(2.4, 0.0, 13.15)
	o.add_child(dch)
	main._box(Vector3(0, 0.46, 0), Vector3(0.52, 0.08, 0.5), chair_m, dch)
	main._box(Vector3(0, 0.85, 0.24), Vector3(0.52, 0.72, 0.08), chair_m, dch)
	main._cyl(Vector3(0, 0.23, 0), 0.03, 0.42, metal, dch)
	main._cyl(Vector3(0, 0.02, 0), 0.26, 0.03, metal, dch)
	main.seat_nodes.append(dch)
	main.seat_eye.append(main.SEAT_EYE_HEIGHT)
	main.seat_swivel.append(true)
	# the client's chair: a worn leather club chair, its arms where his arms rest
	var leather := _m(Color(0.20, 0.10, 0.07), 0.45)
	var leather_dk := _m(Color(0.14, 0.07, 0.05), 0.5)
	var cch := Node3D.new()
	cch.position = Vector3(2.55, 0.0, 11.6)
	o.add_child(cch)
	main._box(Vector3(0, 0.22, 0.0), Vector3(0.74, 0.32, 0.66), leather_dk, cch)                # base
	main._box(Vector3(0, 0.43, 0.02), Vector3(0.5, 0.12, 0.6), leather, cch)                    # seat cushion (top at 0.49)
	main._box(Vector3(0, 0.72, -0.4), Vector3(0.74, 0.86, 0.14), leather_dk, cch)              # back
	main._box(Vector3(0, 0.66, -0.31), Vector3(0.5, 0.5, 0.05), leather, cch)                   # back cushion
	for sx in [-1.0, 1.0]:
		main._box(Vector3(sx * 0.33, 0.5, -0.04), Vector3(0.14, 0.4, 0.74), leather_dk, cch)     # arms (tops at 0.70)
		main._box(Vector3(sx * 0.33, 0.7, -0.04), Vector3(0.16, 0.03, 0.76), leather, cch)
		for lz in [-0.28, 0.28]:
			main._box(Vector3(sx * 0.3, 0.03, lz), Vector3(0.05, 0.06, 0.05), wood_dk, cch)
	visitor.position = cch.position
	visitor.rotation.y = 0.0                              # facing the desk (+z)
	# the props on the desk (laid out for the old desk, moved over)
	_desk = Node3D.new()
	_desk.position = DESK_SHIFT
	o.add_child(_desk)
	_build_desk()
	# filing cabinet, coat rack with the trench coat and the fedora, a safe
	var fc := Vector3(0.85, 0.0, 10.85)
	main._box(fc + Vector3(0, 0.65, 0), Vector3(0.5, 1.3, 0.6), _m(Color(0.30, 0.32, 0.30), 0.5), o)
	for dy in [0.25, 0.65, 1.05]:
		main._box(fc + Vector3(0.255, dy, 0), Vector3(0.01, 0.34, 0.52), _m(Color(0.36, 0.38, 0.36), 0.5), o)
		main._box(fc + Vector3(0.265, dy + 0.1, 0), Vector3(0.015, 0.03, 0.14), metal, o)
	var radio := Vector3(0.85, 1.3, 10.85)
	main._box(radio + Vector3(0, 0.13, 0), Vector3(0.3, 0.26, 0.4), wood, o)                # an old radio up top
	main._cyl(radio + Vector3(0.152, 0.15, 0), 0.08, 0.01, _m(Color(0.75, 0.65, 0.45), 0.6), o).rotation.z = PI / 2.0
	var rack := Vector3(4.2, 0.0, Z1 - 0.35)
	main._cyl(rack + Vector3(0, 0.9, 0), 0.02, 1.8, wood_dk, o)
	main._cyl(rack + Vector3(0, 0.02, 0), 0.22, 0.04, wood_dk, o)
	var coat := _m(Color(0.55, 0.47, 0.35), 0.9)
	var tc: MeshInstance3D = main._box(rack + Vector3(0.05, 1.15, 0.02), Vector3(0.36, 0.95, 0.16), coat, o)
	tc.rotation.y = 0.3
	var hat := Props.fedora()
	hat.position = rack + Vector3(0, 1.82, 0)
	hat.rotation = Vector3(0.15, 0.6, 0.1)
	o.add_child(hat)
	# the window behind the desk: venetian blinds half down, rain on the glass, a neon sign across the street
	var wx0 := 1.5
	var wx1 := 3.3
	var wy0 := 1.0
	var wy1 := 2.4
	var frame := _m(Color(0.18, 0.12, 0.10), 0.6)
	var wz := Z1 - 0.06
	main._box(Vector3((wx0 + wx1) / 2.0, wy0 - 0.02, wz), Vector3(wx1 - wx0 + 0.12, 0.05, 0.14), frame, o)
	main._box(Vector3((wx0 + wx1) / 2.0, (wy0 + wy1) / 2.0, wz), Vector3(0.05, wy1 - wy0, 0.06), frame, o)
	var q := QuadMesh.new()
	q.size = Vector2(wx1 - wx0, wy1 - wy0)
	_rain_m = ShaderMaterial.new()
	_rain_m.shader = _rain_shader()
	var glass := MeshInstance3D.new()
	glass.mesh = q
	glass.material_override = _rain_m
	glass.position = Vector3((wx0 + wx1) / 2.0, (wy0 + wy1) / 2.0, wz + 0.01)
	glass.rotation.y = PI                    # faces into the office (-z)
	o.add_child(glass)
	var slat := _m(Color(0.75, 0.70, 0.60), 0.6)
	for k in 3:                              # the blind is pulled most of the way up: a few slats at the top, the street below
		var sy := wy1 - 0.04 - k * 0.075
		var sl: MeshInstance3D = main._box(Vector3((wx0 + wx1) / 2.0, sy, wz - 0.08), Vector3(wx1 - wx0 - 0.04, 0.05, 0.01), slat, o)
		sl.rotation.x = 0.9                  # tilted open: the light comes through in stripes
	main._box(Vector3((wx0 + wx1) / 2.0, wy1 - 0.25, wz - 0.08), Vector3(wx1 - wx0 - 0.02, 0.025, 0.04), slat, o)   # bottom rail
	# heavy curtains either side of the window, on a rod, with a pelmet over the top
	var drape := _m(Color(0.30, 0.10, 0.10), 0.95)
	var drape_dk := _m(Color(0.20, 0.06, 0.06), 0.95)
	var rod_y := wy1 + 0.22
	main._cyl(Vector3((wx0 + wx1) / 2.0, rod_y, wz - 0.14), 0.015, wx1 - wx0 + 1.1, _m(Color(0.6, 0.48, 0.3), 0.3), o).rotation.z = PI / 2.0
	main._box(Vector3((wx0 + wx1) / 2.0, rod_y + 0.06, wz - 0.16), Vector3(wx1 - wx0 + 1.0, 0.24, 0.05), drape_dk, o)   # pelmet
	_cur_cx = (wx0 + wx1) / 2.0
	for side in [-1.0, 1.0]:
		var edge: float = wx0 if side < 0.0 else wx1
		for k in 6:                                   # folds: alternating light and dark strips, swaying in and out
			var fz: float = wz - 0.12 - (0.025 if k % 2 == 0 else 0.0)
			var f: MeshInstance3D = main._box(Vector3(edge, (0.1 + rod_y) / 2.0, fz), Vector3(0.07, rod_y - 0.1, 0.03), drape if k % 2 == 0 else drape_dk, o)
			_folds.append([f, side, edge, k])
		var tb: MeshInstance3D = main._box(Vector3(edge + side * 0.1, 1.05, wz - 0.17), Vector3(0.36, 0.05, 0.06), _m(Color(0.6, 0.48, 0.3), 0.4), o)   # tie-back
		_tiebacks.append(tb)
	_set_curtains(0.0)
	var cur_hit := Node3D.new()
	cur_hit.position = Vector3(_cur_cx, (wy0 + wy1) / 2.0, wz - 0.13)
	o.add_child(cur_hit)
	main.interactables.append({"node": cur_hit, "half": Vector3((wx1 - wx0) / 2.0 + 0.25, (wy1 - wy0) / 2.0 + 0.1, 0.06), "guest_ok": true,
		"label": func() -> String: return "OPEN THE CURTAINS" if _cur_closed else "CLOSE THE CURTAINS",
		"cb": func() -> void: _cur_closed = not _cur_closed})
	# across the street: a building a floor lower than ours, rows of windows (some lit, people passing behind them
	# now and then), the HOTEL sign up on its roof, and taller blocks behind it against the sky
	var street := Node3D.new()
	street.position = Vector3(2.4, 0.0, Z1 + 4.5)
	o.add_child(street)
	var roof_y := 1.5
	var brick := _m(Color(0.08, 0.07, 0.09), 0.9)
	main._box(Vector3(0, (roof_y - 14.0) / 2.0, 0), Vector3(16.0, roof_y + 14.0, 0.5), brick, street)
	main._box(Vector3(0, roof_y + 0.05, -0.05), Vector3(16.3, 0.12, 0.66), _m(Color(0.13, 0.12, 0.13), 0.8), street)   # cornice
	main._box(Vector3(0, roof_y + 0.25, -0.24), Vector3(16.0, 0.3, 0.08), brick, street)                              # parapet
	var sill := _m(Color(0.16, 0.15, 0.16), 0.8)
	var ws := _window_shader()
	_win = []
	for ry in [-3.5, -2.2, -0.9, 0.55]:
		for k in 14:
			var wxp := -7.15 + k * 1.1
			var wm := ShaderMaterial.new()
			wm.shader = ws
			var on := _rng.randf() < 0.42
			wm.set_shader_parameter("lit", 1.0 if on else 0.0)
			wm.set_shader_parameter("tint", _rng.randf_range(0.75, 1.1))
			wm.set_shader_parameter("sil", Vector3(-1.0, 0.0, 1.0))
			var wq := QuadMesh.new()
			wq.size = Vector2(0.6, 0.75)
			var wmi := MeshInstance3D.new()
			wmi.mesh = wq
			wmi.material_override = wm
			wmi.position = Vector3(wxp, ry, -0.26)
			wmi.rotation.y = PI
			street.add_child(wmi)
			main._box(Vector3(wxp, ry - 0.4, -0.29), Vector3(0.72, 0.05, 0.1), sill, street)
			_win.append({"m": wm, "on": on, "x": -1.0, "v": 0.0, "stop": 0.0})
	# the blocks behind, darker, with the odd lit window high up
	var far := _m(Color(0.05, 0.05, 0.06), 0.95)
	var far_lit := _m(Color(0.8, 0.75, 0.6), 0.8, 0.9)
	for bk in [[-6.5, 7.0, 3.0], [-2.6, 5.0, 4.5], [1.8, 8.5, 3.6], [5.6, 6.0, 3.2], [9.5, 9.5, 4.0], [-10.0, 4.5, 4.0]]:
		var bx: float = bk[0]
		var bh: float = bk[1]
		var bw: float = bk[2]
		main._box(Vector3(bx, (bh - 6.0) / 2.0, 7.0 + absf(bx) * 0.2), Vector3(bw, bh + 6.0, 3.0), far, street)
		for n in 5:
			var fx := bx + _rng.randf_range(-bw * 0.4, bw * 0.4)
			var fy := _rng.randf_range(roof_y + 1.0, bh - 0.3)
			main._box(Vector3(fx, fy, 7.0 + absf(bx) * 0.2 - 1.52), Vector3(0.3, 0.4, 0.02), far_lit, street)
	# the sign: a big HOTEL in neon on a dark board, standing on the roof on a steel frame
	_neon_m = _m(Color(1.0, 0.25, 0.3), 0.4, 3.2)
	_neon_m.disable_fog = true
	var steel := _m(Color(0.12, 0.12, 0.13), 0.5)
	var sy0 := roof_y + 0.95
	main._box(Vector3(0, sy0, -0.12), Vector3(5.2, 1.3, 0.1), _m(Color(0.04, 0.035, 0.04), 0.7), street)   # the board
	for b in [[Vector3(0, sy0 + 0.6, -0.19), Vector3(5.0, 0.04, 0.04)], [Vector3(0, sy0 - 0.6, -0.19), Vector3(5.0, 0.04, 0.04)],
			[Vector3(2.5, sy0, -0.19), Vector3(0.04, 1.24, 0.04)], [Vector3(-2.5, sy0, -0.19), Vector3(0.04, 1.24, 0.04)]]:
		main._box(b[0], b[1], _neon_m, street)
	for lx in [-2.2, -0.75, 0.75, 2.2]:            # the frame it stands on: legs, braces back to the roof
		main._box(Vector3(lx, (roof_y + sy0 - 0.65) / 2.0 + 0.1, -0.08), Vector3(0.06, sy0 - 0.65 - roof_y + 0.2, 0.06), steel, street)
		var br: MeshInstance3D = main._box(Vector3(lx, sy0 - 0.2, 0.35), Vector3(0.04, 1.4, 0.04), steel, street)
		br.rotation.x = 0.55
	main._box(Vector3(0, sy0 - 0.62, -0.06), Vector3(5.1, 0.05, 0.05), steel, street)
	_neon_halo = Label3D.new()                     # a soft glow behind the letters
	_neon_halo.text = "HOTEL"
	_neon_halo.font_size = 160
	_neon_halo.pixel_size = 0.0085
	_neon_halo.outline_size = 48
	_neon_halo.modulate = Color(1.0, 0.25, 0.3, 0.0)
	_neon_halo.outline_modulate = Color(1.0, 0.2, 0.25, 0.35)
	_neon_halo.position = Vector3(0, sy0, -0.19)
	_neon_halo.rotation.y = PI
	_neon_halo.shaded = false
	street.add_child(_neon_halo)
	_neon_sign = Label3D.new()
	_neon_sign.text = "HOTEL"
	_neon_sign.font_size = 160
	_neon_sign.pixel_size = 0.0085
	_neon_sign.outline_size = 14
	_neon_sign.modulate = Color(1.0, 0.75, 0.75)
	_neon_sign.outline_modulate = Color(1.0, 0.2, 0.28)
	_neon_sign.position = Vector3(0, sy0, -0.21)
	_neon_sign.rotation.y = PI
	_neon_sign.shaded = false
	street.add_child(_neon_sign)
	_neon_sign_light = OmniLight3D.new()            # the sign lights the roof and the top of the wall
	_neon_sign_light.position = Vector3(0, sy0 - 0.3, -1.0)
	_neon_sign_light.light_color = Color(1.0, 0.3, 0.35)
	_neon_sign_light.light_energy = 2.0
	_neon_sign_light.omni_range = 4.0
	street.add_child(_neon_sign_light)
	_neon_l = OmniLight3D.new()
	_neon_l.position = Vector3(2.2, 2.0, Z1 - 0.4)
	_neon_l.light_color = Color(1.0, 0.3, 0.35)
	_neon_l.light_energy = 0.9
	_neon_l.omni_range = 4.0
	o.add_child(_neon_l)
	# the light through the slats, across the floor and up the north wall
	_build_blinds()
	# a ceiling fan, turning slowly
	_fan = Node3D.new()
	_fan.position = Vector3(cx, 2.62, 12.0)
	o.add_child(_fan)
	main._cyl(Vector3(0, 0.1, 0), 0.015, 0.2, metal, _fan)
	main._cyl(Vector3(0, -0.02, 0), 0.08, 0.08, metal, _fan)
	for k in 4:
		var bl: MeshInstance3D = main._box(Vector3(0, -0.04, 0), Vector3(0.9, 0.012, 0.12), wood_dk, _fan)
		bl.rotation.y = k * PI / 4.0
		bl.position = Vector3.ZERO
	# the poster: a dark-deco city in the rain
	var pimg := Image.load_from_file(POSTER) if FileAccess.file_exists(POSTER) else null
	if pimg == null:
		var tex = load(POSTER) if ResourceLoader.exists(POSTER) else null
		if tex is Texture2D:
			pimg = (tex as Texture2D).get_image()
	var pf := Node3D.new()
	pf.position = Vector3(X0 + 0.04, 1.6, 12.2)
	pf.rotation.y = PI / 2.0
	o.add_child(pf)
	main._box(Vector3.ZERO, Vector3(0.66, 0.92, 0.03), _m(Color(0.08, 0.06, 0.06), 0.5), pf)
	if pimg != null and not pimg.is_empty():
		var pm := StandardMaterial3D.new()
		pm.albedo_texture = ImageTexture.create_from_image(pimg)
		pm.roughness = 0.8
		pm.disable_fog = true
		var pq := QuadMesh.new()
		pq.size = Vector2(0.6, 0.86)
		var pmi := MeshInstance3D.new()
		pmi.mesh = pq
		pmi.material_override = pm
		pmi.position.z = 0.017
		pf.add_child(pmi)
	# cigarette smoke hanging in the air (a couple of faint, slow sheets; one on the headset)
	var puff := _soft_tex()
	for i in (1 if Plat.low_power() else 2):
		var hm := StandardMaterial3D.new()
		hm.albedo_texture = puff
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hm.albedo_color = Color(0.85, 0.85, 0.82, 0.07)
		hm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		hm.disable_fog = true
		hm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var hq := QuadMesh.new()
		hq.size = Vector2(2.6, 0.9)
		var hmi := MeshInstance3D.new()
		hmi.mesh = hq
		hmi.material_override = hm
		hmi.position = Vector3(2.5, 1.85 + i * 0.35, 12.0 - i * 0.6)
		hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		o.add_child(hmi)
		_haze.append(hmi)


func _soft_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


# rain on the window: dark glass with streaks running down it (no texture needed)
func _rain_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
float h(float n) { return fract(sin(n * 91.3) * 47453.5); }
void fragment() {
	vec2 uv = UV;
	vec3 col = vec3(0.10, 0.10, 0.14) + vec3(0.25, 0.06, 0.08) * smoothstep(1.0, 0.2, uv.y);   // a cold pane, the neon's glow in it
	float lines = 0.0;
	for (int i = 0; i < 3; i++) {
		float cols = 40.0 + float(i) * 23.0;
		float c = floor(uv.x * cols);
		float sp = 0.25 + h(c + float(i) * 7.0) * 0.5;
		float y = fract(uv.y * (1.0 + float(i)) + TIME * sp + h(c) * 9.0);
		float x = fract(uv.x * cols);
		lines += smoothstep(0.08, 0.0, abs(x - 0.5)) * smoothstep(0.0, 0.15, y) * smoothstep(0.6, 0.15, y) * 0.35;
	}
	ALBEDO = col + vec3(0.55, 0.58, 0.65) * lines;
	ALPHA = clamp(0.16 + lines * 0.9, 0.0, 0.85);      // see-through, with the rain running down it
}
"""
	return sh


func _build_desk() -> void:
	# typewriter, facing your chair
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
		"label": func() -> String: return "THE TYPEWRITER  (a new case)", "cb": func() -> void: new_case()})
	# the still life: revolver, one round, the whiskey, a lit cigarette in the ashtray
	var still := Props.build(_desk, Vector3(1.97, DESK_Y, -1.43), -0.35)
	var glass: Node3D = still.get_node("Tumbler")
	_whisky = glass.get_node("Whisky")
	_surface = glass.get_node("Surface")
	_ice = glass.get_node("Ice")
	main.interactables.append({"node": glass, "half": Vector3(0.05, 0.11, 0.05), "guest_ok": true,
		"label": func() -> String: return "A SIP OF WHISKEY" if _sips < 3 else "THE GLASS IS EMPTY", "cb": _sip})
	var bottle := Props.bottle()
	bottle.position = Vector3(2.1, DESK_Y, -1.72)        # back corner of the desk, clear of the glass
	_desk.add_child(bottle)
	_bottle_liquid = bottle.get_node("Liquid")
	main.interactables.append({"node": bottle, "half": Vector3(0.05, 0.16, 0.05), "guest_ok": true,
		"label": _bottle_label, "cb": _pour})
	var file := Props.case_file()
	file.position = Vector3(1.0, DESK_Y, -1.33)
	file.rotation.y = 0.12
	_desk.add_child(file)
	var badge := Props.badge()
	badge.position = Vector3(1.13, DESK_Y + 0.006, -1.25)
	badge.rotation.y = -0.4
	_desk.add_child(badge)
	_set_whisky()
	_set_bottle()


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
	_glasses = 0
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

const Cases := preload("res://noir_cases.gd")
var _deck: Array = []                 # the cases left to deal, shuffled; reshuffled when it runs out


func new_case() -> void:
	if _deck.is_empty():
		for k in Cases.CASES.size():
			_deck.append(k)
		_deck.shuffle()
	var c: Array = Cases.CASES[_deck.pop_back()]
	var body := _names(str(c[1]))
	var t := "CASE #%04d\n%s\n\n%s\n\n%s" % [_rng.randi_range(1, 9999), str(c[0]), body, _names(str(c[2]))]
	_case = t
	_typed = 0.0
	_text.text = ""
	if _bubble_text != null:
		_bubble_text.text = ""


func _names(t: String) -> String:
	if main.cats != null:
		t = t.replace("{tux}", main.cats.name_of("tux")).replace("{calico}", main.cats.name_of("calico"))
	else:
		t = t.replace("{tux}", "Kitty").replace("{calico}", "Lola")
	return t


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
	if _case == "" or int(_typed) >= _case.length():
		return
	var before := int(_typed)
	_typed += delta * 22.0
	var n := mini(int(_typed), _case.length())
	_text.text = _case.left(n)
	_bubble_text.text = _said(_case.left(n))
	_clack_t -= delta
	if n > before and _clack_t <= 0.0 and _case[n - 1] != " ":
		_clack.pitch_scale = _rng.randf_range(0.9, 1.15)
		_clack.play()
		_clack_t = 0.035
	if n >= _case.length():
		_ding.play()                # the bell at the end of the line


# ---- the visitor's speech bubble: a paper-white bubble over his hat that always turns to face you, with the
# part of the case being typed right now (the heading, then each paragraph as it comes)

func _build_bubble() -> void:
	_bubble = Node3D.new()
	_bubble.name = "VisitorBubble"
	office.add_child(_bubble)
	_bubble.visible = false
	var paper := StandardMaterial3D.new()
	paper.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paper.albedo_color = Color(0.8, 0.79, 0.76)          # (not pure white: the bloom would make it glow)
	paper.disable_fog = true
	var edge := StandardMaterial3D.new()
	edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge.albedo_color = Color(0.08, 0.08, 0.09)
	edge.disable_fog = true
	# a rounded panel: a box with round caps on the corners, a dark rim behind, and a little tail toward his head
	for layer in 2:
		var grow := 0.012 if layer == 0 else 0.0
		var m: Material = edge if layer == 0 else paper
		var z := -0.002 if layer == 0 else 0.0
		var r := 0.05 + grow
		for k in 2:
			var bm := BoxMesh.new()
			bm.size = Vector3(BUBBLE_W + 2.0 * grow - (2.0 * r if k == 0 else 0.0), BUBBLE_H + 2.0 * grow - (0.0 if k == 0 else 2.0 * r), 0.002)
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = m
			mi.position.z = z
			_bubble.add_child(mi)
		for cx in [-1.0, 1.0]:
			for cy in [-1.0, 1.0]:
				var cm := CylinderMesh.new()
				cm.top_radius = r
				cm.bottom_radius = r
				cm.height = 0.002
				cm.radial_segments = 20
				var c := MeshInstance3D.new()
				c.mesh = cm
				c.material_override = m
				c.rotation.x = PI / 2.0
				c.position = Vector3(cx * (BUBBLE_W / 2.0 - 0.05), cy * (BUBBLE_H / 2.0 - 0.05), z)
				_bubble.add_child(c)
		var tail := PrismMesh.new()
		tail.size = Vector3(0.09 + 2.0 * grow, 0.11 + grow, 0.002)
		var t := MeshInstance3D.new()
		t.mesh = tail
		t.material_override = m
		t.rotation.z = PI
		t.position = Vector3(-BUBBLE_W * 0.22, -BUBBLE_H / 2.0 - 0.045, z)
		_bubble.add_child(t)
	_bubble_text = Label3D.new()
	_bubble_text.font_size = 34
	_bubble_text.pixel_size = 0.0017
	_bubble_text.outline_size = 0
	_bubble_text.modulate = Color(0.06, 0.06, 0.07)
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.width = (BUBBLE_W - 0.08) / 0.0017
	_bubble_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_bubble_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_bubble_text.position = Vector3(-(BUBBLE_W - 0.08) / 2.0, BUBBLE_H / 2.0 - 0.035, 0.002)     # (left-aligned text starts at the label's origin)
	_bubble_text.shaded = false
	_bubble_text.no_depth_test = false
	_bubble.add_child(_bubble_text)


# the bit he's saying right now: the paragraph being typed, cut to its last few sentences if it runs long
static func _said(typed: String) -> String:
	var paras := typed.split("\n\n")
	var p := paras[paras.size() - 1]
	if p.strip_edges() == "" and paras.size() > 1:
		p = paras[paras.size() - 2]
	p = p.replace("\n", "  -  ") if p.begins_with("CASE #") else p
	while p.length() > 140:
		var cut := p.find(". ", 20)
		if cut < 0:
			p = p.right(140)
			break
		p = p.substr(cut + 2)
	return p


func _bubble_tick() -> void:
	var show := visitor.visible and _bubble_text.text != ""
	_bubble.visible = show
	if not show:
		return
	var cam := main.get_viewport().get_camera_3d()
	var top: Vector3 = visitor.global_position + Vector3(0, 1.98, 0.05)
	_bubble.global_position = top
	if cam != null:
		var to := cam.global_position - top
		to.y = 0.0
		if to.length() > 0.01:
			_bubble.rotation = Vector3(0.0, atan2(to.x, to.z), 0.0)     # turns to face you, stays upright


# ---- the light through the window slats, across the floor and up the north wall

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
			[Vector3(2.4, 0.012, 11.6), Vector3(-PI / 2.0, PI + 0.3, 0.0), Vector2(1.6, 2.4)],     # the floor, slanting in
			[Vector3(2.0, 1.25, Z0 + 0.04), Vector3(0.0, 0.0, 0.15), Vector2(1.5, 1.7)]]:          # the north wall, by the bookcase
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1, 1, 1, 0.2)
		m.disable_fog = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var q := QuadMesh.new()
		q.size = spec[2]
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.position = spec[0]
		mi.rotation = spec[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		office.add_child(mi)
		_blinds.append(mi)


# ---- shared rooms: the host's discovery

func state() -> bool:
	return found


func apply_remote(on: bool) -> void:
	_remote = true
	found = on


func end_remote() -> void:
	if _remote:
		_remote = false
		var cfg := ConfigFile.new()
		found = cfg.load(main.SETTINGS_FILE) == OK and bool(cfg.get_value("room", "noir_found", false))


func on_guest_event(d: Dictionary) -> void:
	if str(d.get("k", "")) == "noir_on":
		request_start()


# ---- sounds, made here

static func _make_clack() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.06 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		# a woody "tock": a low knock of the type bar on the platen, a quick thud of noise, no ringing
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		var s := (sin(t * TAU * 380.0) * 0.7 + sin(t * TAU * 720.0) * 0.3) * exp(-t * 70.0) + lp * exp(-t * 260.0) * 1.2
		data.encode_s16(i * 2, int(clampf(s * 0.7, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)


static func _make_ding() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.2 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s := (sin(t * TAU * 1320.0) + 0.3 * sin(t * TAU * 2650.0) * exp(-t * 10.0)) * exp(-t * 4.0)   # a softer, lower bell
		data.encode_s16(i * 2, int(clampf(s * 0.18, -1.0, 1.0) * 32767.0))
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


static func _make_creak() -> AudioStreamWAV:
	# a wooden creak and a soft click, far off
	var rate := 22050
	var n := int(1.3 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		var f := 140.0 + 60.0 * sin(t * 3.0)
		var creak := sin(t * TAU * f + sin(t * TAU * 23.0) * 2.0) * smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.7, 1.0, t)) * 0.35
		var click := lp * exp(-maxf(t - 1.05, 0.0) * 60.0) * (1.0 if t > 1.05 else 0.0) * 2.0
		data.encode_s16(i * 2, int(clampf((creak + click) * 0.5, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)
