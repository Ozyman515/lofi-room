extends Node3D
const Plat := preload("res://platform.gd")
## Weather outside the window: clear dusk, rain, snow or a thunderstorm.
## Particles fall in front of the city, the sky and fog change, and the sounds are made in code
## (rain, wind, thunder), so there are no audio files to ship. Sounds go through a "Weather" bus
## that gets muffled when the blackout curtains are down.

enum Mode { CLEAR, RAIN, SNOW, STORM }
const NAMES := ["Clear", "Rain", "Snow", "Storm"]
const LEVEL_LABELS := [["", ""], ["Drizzle", "Downpour"], ["Flurries", "Whiteout"], ["Light storm", "Heavy storm"]]

signal mode_changed(mode: int)

var mode: int = Mode.CLEAR
var volume := 0.55                 # 0..1, set from the PC
var overcast := 0.0                # current (smoothed) values, read by main.gd for the room lighting
var flash := 0.0                   # lightning brightness 0..1
var window_open := 1.0             # 1 = curtains up, 0 = fully closed (set by main.gd)
var sound_open := 1.0              # how much weather sound gets in (stays high when the curtain is only partly down)

var env: Environment
var sky_mat: ShaderMaterial
var flash_light: OmniLight3D
var city_mat: ShaderMaterial
var room_flash := 0.0              # 0..1 whole-room afterglow after a big strike (heavy storms), read by main.gd
var _glow_t := 0.0
var _bolt_core: MeshInstance3D
var _bolt_halo: MeshInstance3D
var _bolt_core_m: StandardMaterial3D
var _bolt_halo_m: StandardMaterial3D

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var below_fog := 1.0                # 0..1: the fog layer down below the building (main.gd sets it)
var _rain_e: GPUParticles3D        # the same again past the balcony's east side (it's a corner flat)
var _snow_e: GPUParticles3D
var _rain_pl: AudioStreamPlayer
var _wind_pl: AudioStreamPlayer
var _thunder_pl: AudioStreamPlayer
var _bus := -1
var _lp: AudioEffectLowPassFilter

var _snowy := 0.0
var _fog := 0.0
var _rain_amt := 0.0
var _snow_amt := 0.0
var _rain_vol := 0.0
var _wind_vol := 0.0
var _t_over := 0.0
var _t_snowy := 0.0
var _t_fog := 0.0
var _t_rain := 0.0
var _t_snow := 0.0
var _t_rain_vol := 0.0
var _t_wind_vol := 0.0
var _t_sky_fog := 0.0
var _sky_fog := 0.0
var levels := [0.0, 0.4, 0.4, 0.4]       # intensity per weather: index = Mode

var _bolt_t := 6.0                 # countdown to the next lightning
var _bolt: Array = []              # [start time, strength] of each flash pulse in the current bolt
var _bolt_clock := -1.0
var _thunder_in := -1.0
var _thunder_db := -6.0
var _thunder_pitch := 1.0
var _sounds_ready := false
# city traffic ambience: a low rumble plus cars passing by now and then; it fades out as the weather gets heavier
var _city_bus := -1
var _city_lp: AudioEffectLowPassFilter
var _traffic_rumble: AudioStreamPlayer
var _cars: Array[AudioStreamPlayer] = []
var _car_streams: Array = []
var _horn_pl: AudioStreamPlayer
var _siren_pl: AudioStreamPlayer
var _siren_streams: Array = []        # [kind][direction]
var _horn_next := 5.0
var _siren_next := 14.0
var _car_next := 2.0
var _car_idx := 0
var locked := false                # the weather is under the control of the easter egg: the PC can not change it
var bolt_rate := 1.0               # < 1 = lightning more often
var _saved_event := {}
var traffic_muted := false         # set from the PC: silences the city traffic only
var _traffic := 1.0                # current traffic loudness 0..1
var _rng := RandomNumberGenerator.new()


func setup(environment: Environment, sky_material: ShaderMaterial, light: OmniLight3D, city: ShaderMaterial = null) -> void:
	city_mat = city
	env = environment
	sky_mat = sky_material
	flash_light = light
	_rng.randomize()
	_build_bus()
	_build_traffic()
	_build_particles()
	_build_bolt_nodes()
	_apply_mode_targets()
	_update_audio_params(0.0, true)


func set_mode(m: int) -> void:
	if m == mode:
		return
	mode = m
	_apply_mode_targets()
	if mode != Mode.CLEAR and not _sounds_ready:
		_make_sounds()
	_bolt_t = _rng.randf_range(2.0, 6.0)
	mode_changed.emit(mode)


# jump straight to the current weather (no fade) - used for the random weather at start-up
func snap() -> void:
	overcast = _t_over
	_snowy = _t_snowy
	_fog = _t_fog
	_rain_amt = _t_rain
	_snow_amt = _t_snow
	_rain_vol = _t_rain_vol
	_wind_vol = _t_wind_vol
	_sky_fog = _t_sky_fog
	_traffic = _traffic_target()


# The easter egg takes over: full storm (whatever was selected is remembered), then hands the weather back.
func begin_event() -> void:
	_saved_event = {"mode": mode, "storm": levels[Mode.STORM]}
	locked = true
	levels[Mode.STORM] = 1.0
	mode = Mode.STORM
	_apply_mode_targets()
	if not _sounds_ready:
		_make_sounds()
	bolt_rate = 0.3
	_bolt_t = 0.4
	mode_changed.emit(mode)


func end_event() -> void:
	if _saved_event.is_empty():
		return
	bolt_rate = 1.0
	locked = false
	levels[Mode.STORM] = _saved_event["storm"]
	mode = _saved_event["mode"]
	_saved_event = {}
	_apply_mode_targets()
	_bolt_t = _rng.randf_range(4.0, 9.0)
	mode_changed.emit(mode)


# Noir Night: a steady downpour until it ends, then whatever was on before
var _saved_noir := {}


func begin_noir() -> void:
	if not _saved_noir.is_empty() or locked:
		return
	_saved_noir = {"mode": mode, "rain": levels[Mode.RAIN]}
	locked = true
	levels[Mode.RAIN] = 0.9
	mode = Mode.RAIN
	_apply_mode_targets()
	if not _sounds_ready:
		_make_sounds()
	mode_changed.emit(mode)


func end_noir() -> void:
	if _saved_noir.is_empty():
		return
	locked = false
	levels[Mode.RAIN] = _saved_noir["rain"]
	mode = _saved_noir["mode"]
	_saved_noir = {}
	_apply_mode_targets()
	mode_changed.emit(mode)


# the level the player chose (not the one Noir Night is borrowing), for saving
func real_level(m: int) -> float:
	if m == Mode.RAIN and not _saved_noir.is_empty():
		return _saved_noir["rain"]
	return levels[m]


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)


func mode_name() -> String:
	return NAMES[mode]


func set_level(m: int, v: float) -> void:
	levels[m] = clampf(v, 0.0, 1.0)
	if m == mode:
		_apply_mode_targets()


func get_level(m: int) -> float:
	return levels[m]


# Everything below scales with the intensity slider of the active weather (0 = lightest, 1 = heaviest):
# rain: drizzle -> downpour, snow: flurries -> whiteout, storm: light storm -> heavy storm.
func _apply_mode_targets() -> void:
	var i: float = levels[mode]
	_t_sky_fog = 0.0
	match mode:
		Mode.CLEAR:
			_t_over = 0.0; _t_snowy = 0.0; _t_fog = 0.0; _t_rain = 0.0; _t_snow = 0.0
			_t_rain_vol = 0.0; _t_wind_vol = 0.0
		Mode.RAIN:
			_t_over = lerpf(0.35, 0.8, i); _t_snowy = 0.0; _t_fog = lerpf(0.003, 0.016, i)
			_t_rain = lerpf(0.05, 1.0, i); _t_snow = 0.0
			_t_rain_vol = lerpf(0.2, 1.0, i); _t_wind_vol = lerpf(0.0, 0.3, i)
		Mode.SNOW:
			_t_over = lerpf(0.3, 0.8, i); _t_snowy = 1.0; _t_fog = lerpf(0.003, 0.16, i * i)
			_t_rain = 0.0; _t_snow = lerpf(0.05, 1.0, i)
			_t_rain_vol = 0.0; _t_wind_vol = lerpf(0.08, 0.7, i)
			_t_sky_fog = clampf((i - 0.5) * 2.0, 0.0, 1.0) * 0.9
		Mode.STORM:
			_t_over = lerpf(0.7, 1.0, i); _t_snowy = 0.0; _t_fog = lerpf(0.010, 0.030, i)
			_t_rain = lerpf(0.3, 1.0, i); _t_snow = 0.0
			_t_rain_vol = lerpf(0.55, 0.40, i); _t_wind_vol = lerpf(0.25, 0.9, i)
	if _rain != null:
		(_rain.draw_pass_1.material as StandardMaterial3D).albedo_color.a = lerpf(0.30, 0.55, i)


# ---------------------------------------------------------------- particles

func _build_particles() -> void:
	# rain: thin streaks falling in front of the city
	_rain = GPUParticles3D.new()
	_rain.amount = 7500 if not Plat.low_power() else 4000
	_rain.lifetime = 0.9
	_rain.visibility_aabb = AABB(Vector3(-14, -16, -16), Vector3(28, 30, 28))
	_rain.position = Vector3(-0.35, 9.0, -8.45)              # outside the windows, over the balcony too
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10.15, 0.2, 6.15)
	pm.direction = Vector3(0.12, -1.0, 0.0)
	pm.spread = 1.5
	pm.initial_velocity_min = 13.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3.ZERO
	_rain.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.014, 0.5)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.78, 0.84, 1.0, 0.45)
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	streak.material = rm
	_rain.draw_pass_1 = streak
	_rain.emitting = false
	add_child(_rain)

	# snow: soft slow flakes that drift about
	_snow = GPUParticles3D.new()
	_snow.amount = 6500 if not Plat.low_power() else 3500
	_snow.lifetime = 10.0
	_snow.visibility_aabb = AABB(Vector3(-14, -16, -16), Vector3(28, 30, 28))
	_snow.position = Vector3(-0.35, 9.0, -8.45)
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(10.15, 0.2, 6.15)
	sm.direction = Vector3(0.1, -1.0, 0.0)
	sm.spread = 12.0
	sm.initial_velocity_min = 0.9
	sm.initial_velocity_max = 1.4
	sm.gravity = Vector3(0.0, -0.15, 0.0)
	sm.scale_min = 0.6
	sm.scale_max = 1.6
	_snow.process_material = sm
	var flake := QuadMesh.new()
	flake.size = Vector2(0.11, 0.11)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(1.0, 0.97, 1.0, 0.9)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = _soft_dot()
	flake.material = fm
	_snow.draw_pass_1 = flake
	_snow.emitting = false
	add_child(_snow)
	# and down the east side
	_rain_e = _rain.duplicate()
	_rain_e.process_material = pm.duplicate()
	(_rain_e.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(5.3, 0.2, 8.9)
	_rain_e.position = Vector3(15.1, 9.0, -5.7)
	_rain_e.amount = 4000 if not Plat.low_power() else 2000
	add_child(_rain_e)
	_snow_e = _snow.duplicate()
	_snow_e.process_material = sm.duplicate()
	(_snow_e.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(5.3, 0.2, 8.9)
	_snow_e.position = Vector3(15.1, 9.0, -5.7)
	_snow_e.amount = 3500 if not Plat.low_power() else 1800
	add_child(_snow_e)


func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


# ---------------------------------------------------------------- sounds (all generated)

func _build_bus() -> void:
	_bus = AudioServer.get_bus_index("Weather")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "Weather")
		AudioServer.set_bus_send(_bus, "Master")
		_lp = AudioEffectLowPassFilter.new()
		_lp.cutoff_hz = 16000.0
		AudioServer.add_bus_effect(_bus, _lp)
		var lim := AudioEffectLimiter.new()          # keeps a loud thunder clap from clipping
		lim.ceiling_db = -1.0
		lim.threshold_db = -4.0
		AudioServer.add_bus_effect(_bus, lim)
	else:
		_lp = AudioServer.get_bus_effect(_bus, 0) as AudioEffectLowPassFilter


func _make_sounds() -> void:
	_sounds_ready = true
	_rain_pl = _player(_noise_loop(22050, 2.5, 0.30, 0.9, 1.0, false))
	_wind_pl = _player(_noise_loop(11025, 6.0, 0.035, 0.35, 0.0, true))
	_thunder_pl = _player(_thunder_stream())
	_rain_pl.play()
	_wind_pl.play()


func _player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Weather"
	p.volume_db = -80.0
	add_child(p)
	return p


# A loopable noise: two one-pole filters mixed (alpha = how bright), optional slow swell for wind.
func _noise_loop(rate: int, secs: float, alpha: float, gain: float, hiss: float, swell: bool) -> AudioStreamWAV:
	var n := int(rate * secs)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var lo := 0.0
	var lo2 := 0.0
	var peak := 0.0001
	for i in n:
		var w := _rng.randf_range(-1.0, 1.0)
		lo += (w - lo) * alpha
		lo2 += (lo - lo2) * alpha * 0.5
		var s := lo * (0.5 + hiss * 0.5) + (w * 0.18 * hiss) + lo2 * 0.6
		if swell:
			var ph := float(i) / float(n)
			s *= 0.55 + 0.45 * sin(ph * TAU * 2.0) * sin(ph * TAU * 3.0 + 1.0)
		raw[i] = s
		peak = maxf(peak, absf(s))
	# crossfade the end into the start so the loop has no click
	var fade := mini(int(rate * 0.12), n / 4)
	for i in fade:
		var t := float(i) / float(fade)
		raw[n - fade + i] = raw[n - fade + i] * (1.0 - t) + raw[i] * t
	var bytes := PackedByteArray()
	bytes.resize((n - fade) * 2)
	for i in n - fade:
		bytes.encode_s16(i * 2, int(clampf(raw[i] / peak * gain, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n - fade
	return wav


# Thunder: a sharp crack, then a long low rumble that rolls away.
func _thunder_stream() -> AudioStreamWAV:
	var rate := 11025
	var secs := 6.0
	var n := int(rate * secs)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var lo := 0.0
	var lo2 := 0.0
	var bumps := [_rng.randf() * 6.0, _rng.randf() * 6.0, _rng.randf() * 6.0]
	var peak := 0.0001
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / rate
		var w := _rng.randf_range(-1.0, 1.0)
		lo += (w - lo) * 0.06
		lo2 += (lo - lo2) * 0.25
		var env_roll := exp(-t / 1.9) * (0.65 + 0.35 * sin(t * 6.0 + bumps[0]) * sin(t * 2.3 + bumps[1]))
		var crack := exp(-t / 0.09) * w * 0.7
		var s := lo2 * 3.0 * env_roll + crack
		s *= minf(t / 0.01, 1.0) * minf((secs - t) / 0.5, 1.0)
		raw[i] = s
		peak = maxf(peak, absf(s))
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(raw[i] / peak, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	return wav


# ---------------------------------------------------------------- traffic ambience (generated)

# Full at clear weather and light weather, fading to silent as the active weather's intensity reaches 60 %.
func _traffic_target() -> float:
	if traffic_muted:
		return 0.0
	if mode == Mode.CLEAR:
		return 1.0
	return 1.0 - smoothstep(0.30, 0.60, levels[mode])


func _build_traffic() -> void:
	_city_bus = AudioServer.get_bus_index("City")
	if _city_bus < 0:
		AudioServer.add_bus()
		_city_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_city_bus, "City")
		AudioServer.set_bus_send(_city_bus, "Master")
		_city_lp = AudioEffectLowPassFilter.new()
		_city_lp.cutoff_hz = 16000.0
		AudioServer.add_bus_effect(_city_bus, _city_lp)
	else:
		_city_lp = AudioServer.get_bus_effect(_city_bus, 0) as AudioEffectLowPassFilter
	_traffic_rumble = AudioStreamPlayer.new()
	_traffic_rumble.stream = _noise_loop(11025, 7.0, 0.014, 0.5, 0.0, false)
	_traffic_rumble.bus = "City"
	_traffic_rumble.volume_db = -80.0
	add_child(_traffic_rumble)
	_traffic_rumble.play()
	for i in 3:
		var pl := AudioStreamPlayer.new()
		pl.bus = "City"
		add_child(pl)
		_cars.append(pl)
	for dir in [1.0, -1.0]:
		for kind in 2:
			_car_streams.append(_car_stream(dir, kind))
	_horn_pl = AudioStreamPlayer.new()
	_horn_pl.bus = "City"
	add_child(_horn_pl)
	_siren_pl = AudioStreamPlayer.new()
	_siren_pl.bus = "City"
	add_child(_siren_pl)
	for kind in 3:
		_siren_streams.append(_siren_pair(kind))
	_horn_next = _rng.randf_range(3.0, 8.0)
	_siren_next = _rng.randf_range(10.0, 25.0)
	_car_next = _rng.randf_range(1.0, 3.0)
	_traffic = _traffic_target()


# One car driving past, in stereo: engine hum that drops in pitch, tyre hiss, loudest in the middle.
# dir = +1 left to right, -1 right to left; kind 0 = quiet car, kind 1 = bigger / louder one.
func _car_stream(dir: float, kind: int) -> AudioStreamWAV:
	var rate := 22050
	var secs := 3.6 + float(kind) * 1.2
	var n := int(rate * secs)
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	var lo := 0.0
	var phase := 0.0
	var f0 := _rng.randf_range(62.0, 95.0) * (0.8 if kind == 1 else 1.0)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var peak := 0.0001
	for i in n:
		var x := float(i) / n
		var amp := pow(sin(x * PI), 2.0)
		var w := _rng.randf_range(-1.0, 1.0)
		lo += (w - lo) * (0.03 + 0.10 * amp)
		var f := f0 * (1.12 - 0.3 * x)
		phase += TAU * f / rate
		var hum := sin(phase) + 0.5 * sin(phase * 2.0 + 0.7) + 0.25 * sin(phase * 3.0 + 1.9)
		var s := (lo * 3.2 + hum * (0.35 + 0.2 * float(kind))) * amp
		raw[i] = s
		peak = maxf(peak, absf(s))
	for i in n:
		var x := float(i) / n
		var pan := 0.5 + 0.5 * dir * (x * 2.0 - 1.0) * 0.9           # moves across the stereo field
		var v := raw[i] / peak * 0.8
		bytes.encode_s16(i * 4, int(clampf(v * sqrt(1.0 - pan), -1.0, 1.0) * 30000.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(v * sqrt(pan), -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = true
	wav.data = bytes
	return wav


# A random honk: 2 to 4 beeps (never more), each randomly short or long, spread over 2 to 4 seconds in total.
# Silence between two honks: 4 s about 30 % of the time, 8 s about 60 %, anything in between for the rest.
func _horn_gap() -> float:
	var p := _rng.randf()
	if p < 0.30:
		return 4.0
	if p < 0.90:
		return 8.0
	return _rng.randf_range(4.0, 8.0)


func _horn(r: RandomNumberGenerator = null) -> AudioStreamWAV:
	var rng := r if r != null else _rng
	var rate := 11025
	var pairs := [[392.0, 494.0], [330.0, 415.0], [440.0, 554.0], [370.0, 466.0]]
	var pr: Array = pairs[rng.randi() % pairs.size()]
	var beeps := rng.randi_range(2, 4)
	var length := rng.randf_range(2.0, 4.0)
	var durs: Array = []
	var sum := 0.0
	for i in beeps:
		var d := rng.randf_range(0.12, 0.30) if rng.randf() < 0.5 else rng.randf_range(0.6, 1.0)     # short or long
		durs.append(d)
		sum += d
	var min_gap := 0.12
	if sum + min_gap * (beeps - 1) > length:               # long beeps don't fit in this length: squeeze them
		var f := (length - min_gap * (beeps - 1)) / sum
		for i in beeps:
			durs[i] = durs[i] * f
		sum *= f
	var gap := (length - sum) / float(beeps - 1)
	var segs: Array = []                                   # [start, length]
	var t := 0.0
	for i in beeps:
		segs.append([t, durs[i]])
		t += durs[i] + gap
	var n := int(rate * length) + rate / 10
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var ts := float(i) / rate
		var env := 0.0
		for sg in segs:
			var u: float = ts - float(sg[0])
			if u >= 0.0 and u < float(sg[1]):
				env = minf(u * 90.0, 1.0) * minf((float(sg[1]) - u) * 60.0, 1.0)
		var s := (sin(TAU * pr[0] * ts) + sin(TAU * pr[1] * ts) + 0.4 * sin(TAU * pr[1] * 2.0 * ts)) * 0.3 * env
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	return wav


# A siren going past (about 4.5 s): louder as it gets close, quieter as it leaves, pitch dropping slightly
# like a real Doppler pass, sweeping across the stereo field. kind 0 ambulance (hi-lo), 1 police wail, 2 police yelp.
# Returns [left-to-right stream, right-to-left stream].
func _siren_pair(kind: int) -> Array:
	var rate := 16000
	var secs := 4.5
	var n := int(rate * secs)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var phase := 0.0
	for i in n:
		var x := float(i) / n
		var ts := float(i) / rate
		var f := 0.0
		match kind:
			0:
				f = 960.0 if fmod(ts, 1.1) < 0.55 else 770.0
			1:
				var ph := fmod(ts / 3.0, 1.0)
				f = 650.0 + 600.0 * (1.0 - absf(ph * 2.0 - 1.0))
			_:
				var ph2 := fmod(ts / 0.32, 1.0)
				f = 700.0 + 650.0 * ph2
		f *= 1.07 - 0.14 * x                               # Doppler
		phase += TAU * f / rate
		var tone := sin(phase) + 0.30 * sin(phase * 3.0) + 0.12 * sin(phase * 5.0)
		var amp := pow(sin(x * PI), 1.6)
		raw[i] = tone * amp * 0.45
	var out: Array = []
	for dir in [1.0, -1.0]:
		var bytes := PackedByteArray()
		bytes.resize(n * 4)
		for i in n:
			var x := float(i) / n
			var pan: float = 0.5 + 0.5 * dir * (x * 2.0 - 1.0) * 0.9
			bytes.encode_s16(i * 4, int(clampf(raw[i] * sqrt(1.0 - pan), -1.0, 1.0) * 28000.0))
			bytes.encode_s16(i * 4 + 2, int(clampf(raw[i] * sqrt(pan), -1.0, 1.0) * 28000.0))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = rate
		wav.stereo = true
		wav.data = bytes
		out.append(wav)
	return out


func _update_traffic(delta: float) -> void:
	_traffic = lerpf(_traffic, _traffic_target(), clampf(delta * 0.8, 0.0, 1.0))
	if _traffic_rumble != null:
		_traffic_rumble.volume_db = linear_to_db(maxf(_traffic * 0.28, 0.00001))
	_horn_next -= delta
	if _horn_next <= 0.0:
		_horn_next = _horn_gap()
		if _traffic > 0.05 and not _horn_pl.playing:
			_horn_pl.stream = _horn()
			_horn_next += _horn_pl.stream.get_length()      # the silence is counted after the honk ends
			_horn_pl.volume_db = linear_to_db(_traffic * _rng.randf_range(0.10, 0.2))
			_horn_pl.play()
	_siren_next -= delta
	if _siren_next <= 0.0:
		_siren_next = _rng.randf_range(25.0, 70.0)
		if _traffic > 0.05 and not _siren_pl.playing:
			var pair: Array = _siren_streams[_rng.randi() % _siren_streams.size()]
			_siren_pl.stream = pair[_rng.randi() % 2]
			_siren_pl.volume_db = linear_to_db(_traffic * 0.5)
			_siren_pl.play()
	_car_next -= delta
	if _car_next > 0.0:
		return
	_car_next = _rng.randf_range(2.0, 7.5)
	if _traffic < 0.05:
		return
	var pl := _cars[_car_idx]
	_car_idx = (_car_idx + 1) % _cars.size()
	pl.stream = _car_streams[_rng.randi() % _car_streams.size()]
	pl.volume_db = linear_to_db(_traffic * _rng.randf_range(0.18, 0.42))
	pl.pitch_scale = _rng.randf_range(0.9, 1.15)
	pl.play()


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	var k := clampf(delta * 0.8, 0.0, 1.0)         # ~ a few seconds to change the weather
	overcast = lerpf(overcast, _t_over, k)
	_snowy = lerpf(_snowy, _t_snowy, k)
	_fog = lerpf(_fog, _t_fog, k)
	_rain_amt = lerpf(_rain_amt, _t_rain, k)
	_snow_amt = lerpf(_snow_amt, _t_snow, k)
	_rain_vol = lerpf(_rain_vol, _t_rain_vol, k)
	_wind_vol = lerpf(_wind_vol, _t_wind_vol, k)
	_sky_fog = lerpf(_sky_fog, _t_sky_fog, k)

	_rain.emitting = _rain_amt > 0.02
	_rain.amount_ratio = clampf(_rain_amt, 0.01, 1.0)
	_snow.emitting = _snow_amt > 0.02
	_snow.amount_ratio = clampf(_snow_amt, 0.01, 1.0)
	var rpm := _rain.process_material as ParticleProcessMaterial
	rpm.direction = Vector3(0.10 + 0.25 * clampf(_wind_vol, 0.0, 1.0), -1.0, 0.0)
	var spm := _snow.process_material as ParticleProcessMaterial
	spm.direction = Vector3(0.1 + 0.6 * clampf(_wind_vol, 0.0, 1.0), -1.0, 0.0)
	if _rain_e != null:
		_rain_e.emitting = _rain.emitting
		_rain_e.amount_ratio = _rain.amount_ratio
		(_rain_e.process_material as ParticleProcessMaterial).direction = rpm.direction
		_snow_e.emitting = _snow.emitting
		_snow_e.amount_ratio = _snow.amount_ratio
		(_snow_e.process_material as ParticleProcessMaterial).direction = spm.direction

	_update_lightning(delta)

	if sky_mat != null:
		sky_mat.set_shader_parameter("overcast", overcast)
		sky_mat.set_shader_parameter("snowy", _snowy)
		sky_mat.set_shader_parameter("flash", maxf(flash, room_flash * 0.7))
	if city_mat != null:
		city_mat.set_shader_parameter("flash", maxf(flash * 0.6, room_flash * 0.9))
	if env != null:
		env.fog_enabled = _fog > 0.0015 or below_fog > 0.0
		env.fog_density = _fog
		# a thick layer of fog down below the balconies: the street stays hidden, you stay up high
		env.fog_height = -1.5
		env.fog_height_density = 1.2 * below_fog
		env.fog_light_color = Color(0.42, 0.22, 0.52).lerp(Color(0.80, 0.70, 0.86), _snowy).lerp(Color(0.07, 0.03, 0.13), overcast * 0.8 * (1.0 - _snowy))
		env.fog_sky_affect = _sky_fog
	if flash_light != null:
		flash_light.light_energy = (flash * (3.0 + 4.0 * levels[Mode.STORM]) + room_flash * 7.0) * window_open
	_update_audio_params(delta, false)
	_update_traffic(delta)


func _update_lightning(delta: float) -> void:
	# schedule bolts only in a storm
	if mode == Mode.STORM:
		_bolt_t -= delta
		if _bolt_t <= 0.0:
			var iv := lerpf(26.0, 5.0, levels[Mode.STORM])      # heavier storm = bolts more often
			_bolt_t = iv * _rng.randf_range(0.7, 1.3) * bolt_rate
			_start_bolt()
	# play out the flash pulses of the current bolt
	var f := 0.0
	if _bolt_clock >= 0.0:
		_bolt_clock += delta
		for p in _bolt:
			var dt: float = _bolt_clock - p[0]
			if dt >= 0.0:
				var e := 1.0 if dt < 0.07 else maxf(0.0, 1.0 - (dt - 0.07) / 0.15)
				f = maxf(f, p[1] * e)
		if _bolt_clock > 1.5:
			_bolt_clock = -1.0
	flash = lerpf(flash, f, clampf(delta * 40.0, 0.0, 1.0))
	# the bolt itself shows only while a flash pulse is on
	var bk := clampf(f * 1.2, 0.0, 1.0)
	_bolt_core.visible = bk > 0.03 and window_open > 0.05
	_bolt_halo.visible = _bolt_core.visible
	if _bolt_core.visible:
		_bolt_core_m.albedo_color = Color(2.4 * bk, 2.5 * bk, 3.0 * bk)
		_bolt_halo_m.albedo_color = Color(0.3 * bk, 0.4 * bk, 0.9 * bk)
	# heavy storms: after the strike the whole room (and the city) stays lit for a few seconds, flickering as it fades
	var rf := 0.0
	if _glow_t > 0.0:
		_glow_t -= delta
		var span := 3.0
		var env_t := clampf(_glow_t / span, 0.0, 1.0)
		rf = pow(env_t, 1.4) * (0.82 + 0.18 * sin(_glow_t * 31.0 + sin(_glow_t * 7.0) * 3.0))
		rf *= smoothstep(0.78, 0.88, levels[Mode.STORM])
	room_flash = lerpf(room_flash, rf, clampf(delta * 12.0, 0.0, 1.0))
	if _thunder_in >= 0.0:
		_thunder_in -= delta
		if _thunder_in < 0.0 and _thunder_pl != null:
			_thunder_pl.volume_db = _thunder_db
			_thunder_pl.pitch_scale = _thunder_pitch * _rng.randf_range(0.95, 1.05)
			_thunder_pl.play()


func _start_bolt() -> void:
	# flickers, then thunder. Light storm: far away (long delay, quiet). Heavy storm: right overhead
	# (almost instant, loud), with brighter and more flickers, and above ~80 % the whole room lights up for a few seconds.
	var i: float = levels[Mode.STORM]
	_bolt.clear()
	var t := 0.0
	for j in _rng.randi_range(2, 2 + int(round(i * 2.0))):
		_bolt.append([t, _rng.randf_range(lerpf(0.35, 0.75, i), lerpf(0.6, 1.0, i))])
		t += _rng.randf_range(0.12, 0.3)
	_bolt_clock = 0.0
	var near := clampf(i + _rng.randf_range(-0.2, 0.2), 0.0, 1.0)       # a bit of variety bolt to bolt
	_thunder_in = lerpf(3.6, 0.15, near)
	# Thunder is measured against the rain: about 16 dB under it for a light storm, level with it at 50 %,
	# and 10 dB over it at 100 %, so from the middle of the slider upwards thunder drowns the rain out.
	var rain_db := linear_to_db(maxf(_t_rain_vol, 0.01) * 0.55)
	var rel := lerpf(-16.0, 0.0, near / 0.5) if near < 0.5 else lerpf(0.0, 10.0, (near - 0.5) / 0.5)
	_thunder_db = minf(rain_db + rel, 6.0)
	_thunder_pitch = lerpf(1.15, 0.8, near)
	_build_bolt(i)
	if i >= 0.78:
		_glow_t = lerpf(2.0, 3.6, clampf((i - 0.78) / 0.22, 0.0, 1.0))


# ---------------------------------------------------------------- lightning bolt drawn in the sky

func _build_bolt_nodes() -> void:
	_bolt_core_m = _bolt_material(Color(2.4, 2.5, 3.0))
	_bolt_halo_m = _bolt_material(Color(0.3, 0.4, 0.9))
	_bolt_core = MeshInstance3D.new()
	_bolt_core.material_override = _bolt_core_m
	_bolt_core.visible = false
	add_child(_bolt_core)
	_bolt_halo = MeshInstance3D.new()
	_bolt_halo.material_override = _bolt_halo_m
	_bolt_halo.visible = false
	add_child(_bolt_halo)


func _bolt_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	m.albedo_color = c
	return m


# A jagged trunk from high in the sky down towards the skyline, with a few forks; heavier storms get more forks.
func _build_bolt(level: float) -> void:
	# drawn just outside the window, in front of the skyline (the sky itself is mostly hidden behind the buildings)
	var z := _rng.randf_range(-7.5, -10.0)
	var x0 := -2.7 + _rng.randf_range(-6.0, 6.0)
	var top := 34.0
	var bottom := _rng.randf_range(0.3, 2.5)
	var core_pts: Array = []       # list of polylines; each is [Vector2...]
	var trunk := _jagged(Vector2(x0, top), Vector2(x0 + _rng.randf_range(-2.0, 2.0), bottom), 20, 1.2)
	core_pts.append([trunk, 1.0])
	var forks := _rng.randi_range(1, 2 + int(round(level * 3.0)))
	for f in forks:
		var k := _rng.randi_range(3, trunk.size() - 4)
		var from: Vector2 = trunk[k]
		var dir := signf(_rng.randf() - 0.5)
		var to := from + Vector2(dir * _rng.randf_range(1.0, 3.0), -_rng.randf_range(2.0, 5.0))
		core_pts.append([_jagged(from, to, 7, 0.45), 0.55])
	var w := 0.085 * (-z / 14.0)
	_bolt_core.mesh = _ribbons(core_pts, z, w, 1.0)
	_bolt_halo.mesh = _ribbons(core_pts, z - 0.05, w * 4.0, 1.0)


func _jagged(a: Vector2, b: Vector2, segs: int, amp: float) -> Array:
	var pts: Array = [a]
	for s in range(1, segs):
		var t := float(s) / segs
		var p := a.lerp(b, t)
		p.x += _rng.randf_range(-amp, amp)
		pts.append(p)
	pts.append(b)
	return pts


func _ribbons(lines: Array, z: float, width: float, _unused: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for entry in lines:
		var pts: Array = entry[0]
		var wd: float = width * float(entry[1])
		for k in pts.size() - 1:
			var p: Vector2 = pts[k]
			var q: Vector2 = pts[k + 1]
			var d := (q - p).normalized()
			var n := Vector2(-d.y, d.x) * wd * 0.5
			var base := verts.size()
			verts.append(Vector3(p.x - n.x, p.y - n.y, z))
			verts.append(Vector3(p.x + n.x, p.y + n.y, z))
			verts.append(Vector3(q.x + n.x, q.y + n.y, z))
			verts.append(Vector3(q.x - n.x, q.y - n.y, z))
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-60, -5, -40), Vector3(120, 60, 40))
	return mesh


func _update_audio_params(delta: float, force: bool) -> void:
	if _bus < 0:
		return
	var mute := 1.0 - sound_open
	var k := 1.0 if force else clampf(delta * 6.0, 0.0, 1.0)
	_lp.cutoff_hz = lerpf(_lp.cutoff_hz, lerpf(16000.0, 700.0, mute), k)
	AudioServer.set_bus_volume_db(_bus, linear_to_db(maxf(volume, 0.0001)) + lerpf(0.0, -6.0, mute))
	if _city_bus >= 0:
		_city_lp.cutoff_hz = lerpf(_city_lp.cutoff_hz, lerpf(16000.0, 600.0, mute), k)
		AudioServer.set_bus_volume_db(_city_bus, linear_to_db(maxf(volume, 0.0001)) + lerpf(0.0, -5.0, mute))
	if _rain_pl != null:
		_rain_pl.volume_db = linear_to_db(maxf(_rain_vol * 0.55, 0.00001))
		_wind_pl.volume_db = linear_to_db(maxf(_wind_vol * 0.5, 0.00001))
