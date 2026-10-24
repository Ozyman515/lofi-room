extends Node3D

const ScreenUI := preload("res://screen_ui.gd")
const Plat := preload("res://platform.gd")
const FileBrowser := preload("res://file_browser.gd")
const SpeakerBank := preload("res://speaker_bank.gd")
## The PC in the room: a small music player drawn on the monitor. Click "Music" in the taskbar,
## browse your PC's folders and click a song. Plays mp3, ogg and 16-bit wav.

const AUDIO_EXTS := ["mp3", "ogg", "wav"]

var ui: ScreenUI
var audio: SpeakerBank
var playlist: Array[String] = []
var index := -1

var _window: PanelContainer
var _browser: FileBrowser
var _title: Label
var _info: Label
var _time: Label
var _seek: HSlider
var _vol: HSlider
var _spk_window: PanelContainer
var _spk_rows: VBoxContainer
var _spk_vol: HSlider
var _lt_window: PanelContainer
var _st_window: PanelContainer
var _st_update_label: Label
var _st_update_btn: Button
var repeat_mode := 0                  # 0 off, 1 repeat the track, 2 repeat the folder
var _rep_track_btn: Button
var _rep_folder_btn: Button
var _st_weather_btn: Button
var _st_resume_btn: Button
var _st_cart_btn: Button
var _st_reticle_btn: Button
var _st_full_btn: Button
var _st_color_btns: Array[Button] = []
var _ct_window: PanelContainer
var _dbg_window: PanelContainer
var _room_window: PanelContainer
var _room_slap_btns: Array[Button] = []
var _room_guest_btns := {}
var _room_mic_btn: Button
var _room_poster_btn: Button
var _room_ptt_btn: Button
var _dbg_seat_btns: Array[Button] = []
var _dbg_phone_btn: Button
var _ct_dev := "key"
var _ct_listen := ""
var _ct_listen_t := 0.0
var _ct_base := {}
var _ct_dev_btn: Button
var _ct_swap_ab: Button
var _ct_swap_xy: Button
var _ct_btns := {}
var _ct_note: Label
var _lt_rows: VBoxContainer
var _wx_window: PanelContainer
var _wx_buttons: Array[Button] = []
var _wx_cur_btn: Button
var _music_was_playing := false
var _wx_traffic_btn: Button
var _wx_cur_slider: VSlider
var _cur_drag := false
var _wx_vol: HSlider
var _wx_int: HSlider
var _wx_int_title: Label
var _wx_int_lo: Label
var _wx_int_hi: Label
var _wx_int_row: VBoxContainer
var _weather: Node
var _main: Node
var _bar_row: HBoxContainer
var _play_btn: Button
var _clock: Label
var _seeking := false
var _clock_t := 1.0


func setup(screen_ui: ScreenUI, bank: SpeakerBank) -> void:
	ui = screen_ui
	audio = bank
	audio.finished.connect(_on_finished)
	audio.changed.connect(refresh_speakers)
	_build_ui()
	_set_volume(0.7)


func _build_ui() -> void:
	var root := ui.root

	# taskbar along the bottom
	var bar := PanelContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = -56.0
	bar.offset_bottom = 0.0
	root.add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var music_btn := Button.new()
	music_btn.text = "  Music  "
	music_btn.pressed.connect(_toggle_window)
	row.add_child(music_btn)
	var spk_btn := Button.new()
	spk_btn.text = "  Speakers  "
	spk_btn.pressed.connect(_toggle_speakers)
	row.add_child(spk_btn)
	_bar_row = row
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_clock = Label.new()
	_clock.text = "00:00"
	row.add_child(_clock)

	# the player window
	_window = PanelContainer.new()
	_window.offset_left = 40.0
	_window.offset_top = 24.0
	_window.offset_right = 984.0
	_window.offset_bottom = 500.0
	_window.visible = false
	root.add_child(_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_window.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Music Player"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = " x "
	close.pressed.connect(_toggle_window)
	head.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	v.add_child(body)

	_browser = FileBrowser.new()
	_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browser.size_flags_stretch_ratio = 1.5
	body.add_child(_browser)
	var room_songs := default_music_dir()
	_browser.setup(PackedStringArray(AUDIO_EXTS), "music_loc", [["Room songs", room_songs], ["Music", OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)],
		["Downloads", OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)]], room_songs)
	_browser.file_chosen.connect(_on_file_chosen)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	var np := Label.new()
	np.text = "Now playing"
	right.add_child(np)
	_title = Label.new()
	_title.text = "(nothing yet)"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(0, 96)
	right.add_child(_title)
	_info = Label.new()
	_info.text = "Click a song to play it."
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_info)
	_time = Label.new()
	_time.text = "0:00 / 0:00"
	right.add_child(_time)
	_seek = HSlider.new()
	_seek.min_value = 0.0
	_seek.max_value = 1.0
	_seek.step = 0.001
	_seek.custom_minimum_size = Vector2(0, 36)
	_seek.drag_started.connect(_on_seek_started)
	_seek.drag_ended.connect(_on_seek_ended)
	right.add_child(_seek)

	var ctl := HBoxContainer.new()
	ctl.add_theme_constant_override("separation", 8)
	right.add_child(ctl)
	var prev_b := Button.new()
	prev_b.text = "<<"
	prev_b.pressed.connect(_prev)
	ctl.add_child(prev_b)
	_play_btn = Button.new()
	_play_btn.text = " PLAY "
	_play_btn.pressed.connect(_toggle_play)
	ctl.add_child(_play_btn)
	var next_b := Button.new()
	next_b.text = ">>"
	next_b.pressed.connect(_next)
	ctl.add_child(next_b)
	var stop_b := Button.new()
	stop_b.text = "STOP"
	stop_b.pressed.connect(_stop)
	ctl.add_child(stop_b)

	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	right.add_child(rrow)
	var rl := Label.new()
	rl.text = "Repeat"
	rrow.add_child(rl)
	_rep_track_btn = Button.new()
	_rep_track_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rep_track_btn.pressed.connect(func() -> void: _set_repeat(0 if repeat_mode == 1 else 1))
	rrow.add_child(_rep_track_btn)
	_rep_folder_btn = Button.new()
	_rep_folder_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rep_folder_btn.pressed.connect(func() -> void: _set_repeat(0 if repeat_mode == 2 else 2))
	rrow.add_child(_rep_folder_btn)
	_set_repeat(0)

	var vrow := HBoxContainer.new()
	right.add_child(vrow)
	var vl := Label.new()
	vl.text = "VOL "
	vrow.add_child(vl)
	_vol = HSlider.new()
	_vol.min_value = 0.0
	_vol.max_value = 1.0
	_vol.step = 0.01
	_vol.value = 0.7
	_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol.custom_minimum_size = Vector2(0, 36)
	_vol.value_changed.connect(_set_volume)
	vrow.add_child(_vol)
	_build_speakers_window(root)


func _build_speakers_window(root: Control) -> void:
	_spk_window = PanelContainer.new()
	_spk_window.offset_left = 150.0
	_spk_window.offset_top = 40.0
	_spk_window.offset_right = 874.0
	_spk_window.offset_bottom = 500.0
	_spk_window.visible = false
	root.add_child(_spk_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_spk_window.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Speakers"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = " x "
	close.pressed.connect(_toggle_speakers)
	head.add_child(close)
	var vrow := HBoxContainer.new()
	v.add_child(vrow)
	var vl := Label.new()
	vl.text = "VOLUME "
	vrow.add_child(vl)
	_spk_vol = HSlider.new()
	_spk_vol.min_value = 0.0
	_spk_vol.max_value = 1.0
	_spk_vol.step = 0.01
	_spk_vol.value = 0.7
	_spk_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spk_vol.custom_minimum_size = Vector2(0, 36)
	_spk_vol.value_changed.connect(_set_volume)
	vrow.add_child(_spk_vol)
	var hint := Label.new()
	hint.text = "Switch each speaker on or off here (you can also click the speakers in the room)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_spk_rows = VBoxContainer.new()
	_spk_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spk_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_spk_rows)


# Call after the speakers have been added (and again whenever one is switched).
func refresh_speakers() -> void:
	if _spk_rows == null:
		return
	for c in _spk_rows.get_children():
		_spk_rows.remove_child(c)
		c.queue_free()
	var all_row := HBoxContainer.new()
	var all_lab := Label.new()
	all_lab.text = "ALL SPEAKERS"
	all_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_row.add_child(all_lab)
	for m in ["pc", "tv", "off"]:
		var ab := Button.new()
		ab.text = "  ALL %s  " % m.to_upper()
		ab.pressed.connect(audio.set_all_mode.bind(m))
		all_row.add_child(ab)
	_spk_rows.add_child(all_row)
	_spk_rows.add_child(HSeparator.new())
	for i in audio.speakers.size():
		var r := HBoxContainer.new()
		var l := Label.new()
		l.text = str(audio.speakers[i]["name"])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		var b := Button.new()
		b.text = "  %s  " % audio.get_mode(i).to_upper()           # click: PC -> TV -> OFF
		b.tooltip_text = "PC: plays the music.  TV: plays the TV's sound.  OFF: silent."
		b.pressed.connect(audio.cycle.bind(i))
		r.add_child(b)
		_spk_rows.add_child(r)


func _process(delta: float) -> void:
	_ct_tick(delta)
	if _wx_window != null and _wx_window.visible and _main != null:
		if not _cur_drag:
			_wx_cur_slider.set_value_no_signal(1.0 - _main.curtain_amt)      # follows the real curtain, even when a wall switch moves it
		_wx_cur_btn.text = _cur_btn_text()
	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = 1.0
		_clock.text = Time.get_time_string_from_system().substr(0, 5)
	if audio.stream != null and audio.playing and not _seeking:
		var length := audio.stream.get_length()
		var pos := audio.get_playback_position()
		if length > 0.0:
			_seek.set_value_no_signal(clampf(pos / length, 0.0, 1.0))
		_time.text = "%s / %s" % [_fmt(pos), _fmt(length)]


func _toggle_window() -> void:
	_window.visible = not _window.visible
	if _window.visible:
		_spk_window.visible = false
		_wx_hide()


func _toggle_speakers() -> void:
	_spk_window.visible = not _spk_window.visible
	if _spk_window.visible:
		_window.visible = false
		_wx_hide()


func _wx_hide() -> void:
	if _wx_window != null:
		_wx_window.visible = false
	if _lt_window != null:
		_lt_window.visible = false
	if _st_window != null:
		_st_window.visible = false
	if _ct_window != null:
		_ct_window.visible = false
		_ct_listen = ""
	if _dbg_window != null:
		_dbg_window.visible = false
	if _room_window != null:
		_room_window.visible = false


func _toggle_weather() -> void:
	_wx_window.visible = not _wx_window.visible
	if _wx_window.visible:
		_window.visible = false
		_spk_window.visible = false
		_lt_window.visible = false
		_st_window.visible = false
		_wx_refresh()


func _toggle_lights() -> void:
	_lt_window.visible = not _lt_window.visible
	if _lt_window.visible:
		_window.visible = false
		_spk_window.visible = false
		_wx_window.visible = false
		_st_window.visible = false
		_lt_refresh()


# ---- settings window (the dot in the middle of the view)

func _toggle_settings() -> void:
	_st_window.visible = not _st_window.visible
	if _ct_window != null:
		_ct_window.visible = false
		_ct_listen = ""
	if _dbg_window != null:
		_dbg_window.visible = false
	if _room_window != null:
		_room_window.visible = false
	if _st_window.visible:
		_window.visible = false
		_spk_window.visible = false
		_wx_window.visible = false
		_lt_window.visible = false
		_st_refresh()


func _build_settings_window() -> void:
	var btn := Button.new()
	btn.text = "  Settings  "
	btn.pressed.connect(_toggle_settings)
	_bar_row.add_child(btn)
	_bar_row.move_child(btn, 4)
	_st_window = PanelContainer.new()
	_st_window.offset_left = 150.0
	_st_window.offset_top = 6.0
	_st_window.offset_right = 874.0
	_st_window.offset_bottom = 545.0
	_st_window.visible = false
	ui.root.add_child(_st_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_st_window.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Settings"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var ctl_btn := Button.new()
	ctl_btn.text = "  Controls...  "
	ctl_btn.pressed.connect(_open_controls_window)
	head.add_child(ctl_btn)
	var room_btn := Button.new()
	room_btn.text = "  Friends...  "
	room_btn.pressed.connect(_open_room_window)
	head.add_child(room_btn)
	var dbg_btn := Button.new()
	dbg_btn.text = "  Debug...  "
	dbg_btn.pressed.connect(_open_debug_window)
	head.add_child(dbg_btn)
	var cr_btn := Button.new()
	cr_btn.text = "  Credits...  "
	cr_btn.pressed.connect(_open_credits_window)
	head.add_child(cr_btn)
	var close := Button.new()
	close.text = " x "
	close.pressed.connect(_toggle_settings)
	head.add_child(close)
	_st_full_btn = Button.new()
	_st_full_btn.tooltip_text = "F11 or Alt+Enter does the same"
	_st_full_btn.pressed.connect(func() -> void: _main.set_fullscreen(not _main.fullscreen))
	head.add_child(_st_full_btn)
	head.move_child(_st_full_btn, 1)
	_st_reticle_btn = Button.new()
	_st_reticle_btn.custom_minimum_size = Vector2(0, 42)
	_st_reticle_btn.pressed.connect(func() -> void: _main.set_reticle_on(not _main.reticle_on))
	v.add_child(_st_reticle_btn)
	var wst := Button.new()
	wst.custom_minimum_size = Vector2(0, 42)
	wst.pressed.connect(func() -> void: _main.set_weather_start("random" if _main.weather_start == "remember" else "remember"))
	v.add_child(wst)
	_st_weather_btn = wst
	_st_resume_btn = Button.new()
	_st_resume_btn.custom_minimum_size = Vector2(0, 42)
	_st_resume_btn.pressed.connect(func() -> void: _main.set_resume_games(not _main.emu.resume_games))
	v.add_child(_st_resume_btn)
	_st_cart_btn = Button.new()
	_st_cart_btn.custom_minimum_size = Vector2(0, 42)
	_st_cart_btn.pressed.connect(func() -> void: _main.set_cart_style(not _main.cart_wash))
	v.add_child(_st_cart_btn)
	var ct := Label.new()
	ct.text = "Dot colour"
	v.add_child(ct)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	for i in _main.RETICLE_COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", _main.RETICLE_COLORS[i][1])
		b.add_theme_color_override("font_hover_color", _main.RETICLE_COLORS[i][1])
		b.add_theme_color_override("font_pressed_color", _main.RETICLE_COLORS[i][1])
		b.pressed.connect(func() -> void: _main.set_reticle_color(i))
		row.add_child(b)
		_st_color_btns.append(b)
	var ut := Label.new()
	ut.text = "Updates"
	v.add_child(ut)
	_st_update_label = Label.new()
	_st_update_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_st_update_label)
	_st_update_btn = Button.new()
	_st_update_btn.custom_minimum_size = Vector2(0, 42)
	_st_update_btn.pressed.connect(func() -> void:
		var u: Node = _main.updater
		if u.state == "available":
			u.install()
		elif not u.busy():
			u.check())
	v.add_child(_st_update_btn)
	_main.updater.changed.connect(_st_refresh)
	_main.updater.changed.connect(_on_updater_changed)
	_main.settings_changed.connect(_st_refresh)
	_st_refresh()
	_build_controls_window()
	_build_debug_window()
	_build_credits_window()
	_build_room_window()


# ---- friends window: what guests may do in your room

func _build_room_window() -> void:
	_room_window = PanelContainer.new()
	_room_window.offset_left = 150.0
	_room_window.offset_top = 6.0
	_room_window.offset_right = 874.0
	_room_window.offset_bottom = 545.0
	_room_window.visible = false
	ui.root.add_child(_room_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_room_window.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Friends in the room"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back := Button.new()
	back.text = "  Back  "
	back.pressed.connect(func() -> void:
		_room_window.visible = false
		_st_window.visible = true
		_st_refresh())
	head.add_child(back)
	var note := Label.new()
	note.text = "Slapping the controller out of somebody's hands. Each person can do it once per:"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 17)
	v.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	for mins in _main.SLAP_CHOICES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _main.set_slap_minutes(mins))
		row.add_child(b)
		_room_slap_btns.append(b)
	var gt := Label.new()
	gt.text = "What guests may change in your room:"
	gt.add_theme_font_size_override("font_size", 17)
	v.add_child(gt)
	for gg in _main.GUEST_GROUPS:
		var gb := Button.new()
		gb.custom_minimum_size = Vector2(0, 40)
		var key: String = gg[0]
		gb.pressed.connect(func() -> void: _main.set_guest_allow(key, not _main.guest_allow[key]))
		v.add_child(gb)
		_room_guest_btns[key] = gb
	_room_poster_btn = Button.new()
	_room_poster_btn.custom_minimum_size = Vector2(0, 40)
	_room_poster_btn.pressed.connect(func() -> void: _main.set_share_poster(not _main.share_poster))
	v.add_child(_room_poster_btn)
	var vt := Label.new()
	vt.text = "Your voice (M mutes, hold T to talk when push-to-talk is on; point at a friend and scroll to set how loud you hear them):"
	vt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vt.add_theme_font_size_override("font_size", 17)
	v.add_child(vt)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 8)
	v.add_child(vrow)
	_room_mic_btn = Button.new()
	_room_mic_btn.custom_minimum_size = Vector2(0, 40)
	_room_mic_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_mic_btn.pressed.connect(func() -> void:
		if _main.net_voice != null:
			_main.net_voice.set_mic_on(not _main.net_voice.mic_on)
			_room_refresh())
	vrow.add_child(_room_mic_btn)
	_room_ptt_btn = Button.new()
	_room_ptt_btn.custom_minimum_size = Vector2(0, 40)
	_room_ptt_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_ptt_btn.pressed.connect(func() -> void:
		if _main.net_voice != null:
			_main.net_voice.set_push_to_talk(not _main.net_voice.push_to_talk)
			_room_refresh())
	vrow.add_child(_room_ptt_btn)
	var hint := Label.new()
	hint.text = "The room settings above are the host's: they apply to everyone in your room. Beds, naps and the bookshelf are never shared."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 15)
	v.add_child(hint)
	_room_refresh()
	_main.settings_changed.connect(_room_refresh)


func _open_room_window() -> void:
	_st_window.visible = false
	_room_window.visible = true
	_room_refresh()


func _room_refresh() -> void:
	for i in _room_slap_btns.size():
		var mins: int = _main.SLAP_CHOICES[i]
		var txt := "Never" if mins < 0 else ("%d h" % (mins / 60) if mins >= 60 else "%d min" % mins)
		var on: bool = mins == _main.slap_minutes
		_room_slap_btns[i].text = ("[ %s ]" if on else "%s") % txt
	if _room_mic_btn != null and _main.net_voice != null:
		_room_mic_btn.text = "Microphone  [%s]" % ("ON" if _main.net_voice.mic_on else "MUTED")
		_room_ptt_btn.text = "Push to talk  [%s]" % ("ON" if _main.net_voice.push_to_talk else "OFF: open mic")
	if _room_poster_btn != null:
		_room_poster_btn.text = "Guests see my poster   [%s]" % ("YES" if _main.share_poster else "NO: they see the room's posters")
	for gg in _main.GUEST_GROUPS:
		if _room_guest_btns.has(gg[0]):
			_room_guest_btns[gg[0]].text = "%s   [%s]" % [gg[1], "GUESTS MAY" if _main.guest_allow[gg[0]] else "HOST ONLY"]


# ---- debug window: things that are handy while testing the room

# ---- credits: the artists whose songs play in the room (music/CREDITS.txt)

var _cr_window: PanelContainer


func _build_credits_window() -> void:
	_cr_window = PanelContainer.new()
	_cr_window.offset_left = 150.0
	_cr_window.offset_top = 6.0
	_cr_window.offset_right = 874.0
	_cr_window.offset_bottom = 545.0
	_cr_window.visible = false
	ui.root.add_child(_cr_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_cr_window.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Credits"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back := Button.new()
	back.text = "  Back  "
	back.pressed.connect(func() -> void:
		_cr_window.visible = false
		_st_window.visible = true
		_st_refresh())
	head.add_child(back)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 16)
	var txt := FileAccess.get_file_as_string("res://music/CREDITS.txt")
	body.text = txt if txt != "" else "Music credits are in music/CREDITS.txt."
	sc.add_child(body)


func _open_credits_window() -> void:
	_st_window.visible = false
	_cr_window.visible = true


var _dbg_purr_btn: Button
var _dbg_shelf_btn: Button


func _build_debug_window() -> void:
	_dbg_window = PanelContainer.new()
	_dbg_window.offset_left = 150.0
	_dbg_window.offset_top = 6.0
	_dbg_window.offset_right = 874.0
	_dbg_window.offset_bottom = 545.0
	_dbg_window.visible = false
	ui.root.add_child(_dbg_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_dbg_window.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Debug"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back := Button.new()
	back.text = "  Back  "
	back.pressed.connect(func() -> void:
		_dbg_window.visible = false
		_st_window.visible = true
		_st_refresh())
	head.add_child(back)
	var note := Label.new()
	note.text = "Seats in front of the TV. Players = as many as there are people in the room (one when you're alone)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 17)
	v.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	for i in 5:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _main.set_debug_seats(i))
		row.add_child(b)
		_dbg_seat_btns.append(b)
	_dbg_phone_btn = Button.new()
	_dbg_phone_btn.custom_minimum_size = Vector2(0, 42)
	_dbg_phone_btn.pressed.connect(func() -> void: _main.set_phone_hidden(not _main.phone_hidden))
	v.add_child(_dbg_phone_btn)
	_dbg_shelf_btn = Button.new()
	_dbg_shelf_btn.custom_minimum_size = Vector2(0, 42)
	_dbg_shelf_btn.pressed.connect(func() -> void: _main.set_shelf_hints(not _main.shelf_hints))
	v.add_child(_dbg_shelf_btn)
	_dbg_purr_btn = Button.new()
	_dbg_purr_btn.custom_minimum_size = Vector2(0, 42)
	_dbg_purr_btn.pressed.connect(func() -> void: _main.set_cat_purr(not _main.cat_purr_on))
	v.add_child(_dbg_purr_btn)
	var ct := Label.new()
	ct.text = "Cats (for testing the easter egg):"
	ct.add_theme_font_size_override("font_size", 17)
	v.add_child(ct)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	v.add_child(crow)
	var kb := Button.new()
	kb.text = "Kaiju: walk past the window now"
	kb.custom_minimum_size = Vector2(0, 42)
	kb.pressed.connect(func() -> void:
		if _main.kaiju != null:
			_main.kaiju.request_walk())
	v.add_child(kb)
	var gb := Button.new()
	gb.text = "King Gaboon: walk past and roar now"
	gb.custom_minimum_size = Vector2(0, 42)
	gb.pressed.connect(func() -> void:
		if _main.gaboon != null:
			_main.gaboon.request_walk())
	v.add_child(gb)
	var fb := Button.new()
	fb.text = "Kaiju vs King Gaboon: fight now"
	fb.custom_minimum_size = Vector2(0, 42)
	fb.pressed.connect(func() -> void:
		if _main.fight != null:
			_main.fight.request_fight())
	v.add_child(fb)
	var fe := HBoxContainer.new()                  # ...or pick how it ends
	fe.add_theme_constant_override("separation", 6)
	for spec in [["T-Rex wins", "k"], ["King Gaboon wins", "g"], ["Draw (black kaiju + UFO fleet)", "draw"]]:
		var eb := Button.new()
		eb.text = spec[0]
		eb.custom_minimum_size = Vector2(0, 38)
		eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var end_code: String = spec[1]
		eb.pressed.connect(func() -> void:
			if _main.fight != null:
				_main.fight.request_fight(end_code))
		fe.add_child(eb)
	v.add_child(fe)
	var ub := Button.new()
	ub.text = "UFO: stop at the window now"
	ub.custom_minimum_size = Vector2(0, 42)
	ub.pressed.connect(func() -> void:
		if _main.ufo != null:
			_main.ufo.request_visit())
	v.add_child(ub)
	var nb := Button.new()
	nb.text = "Noir Night with the grey visitor"
	nb.custom_minimum_size = Vector2(0, 42)
	nb.pressed.connect(func() -> void:
		if _main.noir != null and not _main.noir.active:
			_main.noir.force_visitor = true
			_main.noir.request_start())
	v.add_child(nb)
	for opt in [["Call the tux", "tux"], ["Calico: rug", "rug"], ["Calico: beanbag", "beanbag"], ["Calico: console", "console"], ["No cats", "none"]]:
		var cb := Button.new()
		cb.text = opt[0]
		cb.custom_minimum_size = Vector2(0, 42)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var what: String = opt[1]
		cb.pressed.connect(func() -> void:
			if _main.cats != null:
				_main.cats.debug_set(what))
		crow.add_child(cb)
	_dbg_refresh()
	_main.settings_changed.connect(_dbg_refresh)


func _open_debug_window() -> void:
	_st_window.visible = false
	_dbg_window.visible = true
	_dbg_refresh()


func _dbg_refresh() -> void:
	for i in _dbg_seat_btns.size():
		var on: bool = i == _main.debug_seats
		_dbg_seat_btns[i].text = ("[ %s ]" if on else "%s") % ("Players" if i == 0 else str(i))
	if _dbg_shelf_btn != null:
		_dbg_shelf_btn.text = "Book titles when pointing at the shelf  [%s]" % ("ON" if _main.shelf_hints else "OFF")
	if _dbg_purr_btn != null:
		_dbg_purr_btn.text = "Cat purring  [%s]" % ("ON" if _main.cat_purr_on else "MUTED")
	if _dbg_phone_btn != null:
		_dbg_phone_btn.text = "Wall phone (buddy bois)  [%s]" % ("HIDDEN" if _main.phone_hidden else "SHOWN")


var _sleep_q: PanelContainer
var _last_up_state := ""


# When an update has just been installed from the PC, ask whether to sleep now (wake up in the new room).
func _on_updater_changed() -> void:
	var s: String = _main.updater.state
	if s == "done" and _last_up_state == "downloading" and not _main.sleeping and not _main.egg_active:
		_show_sleep_q()
	_last_up_state = s


func _show_sleep_q() -> void:
	if _sleep_q == null:
		_sleep_q = PanelContainer.new()
		_sleep_q.offset_left = 262.0
		_sleep_q.offset_top = 190.0
		_sleep_q.offset_right = 762.0
		_sleep_q.offset_bottom = 370.0
		ui.root.add_child(_sleep_q)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 14)
		_sleep_q.add_child(v)
		var t := Label.new()
		t.text = "The update is installed."
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
		var q := Label.new()
		q.text = "Take a Nap?"
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.add_theme_font_size_override("font_size", 26)
		v.add_child(q)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(row)
		var yes := Button.new()
		yes.text = "  Yes  "
		yes.custom_minimum_size = Vector2(150, 48)
		yes.pressed.connect(func() -> void:
			_sleep_q.visible = false
			_main._go_to_sleep())
		row.add_child(yes)
		var no := Button.new()
		no.text = "  No  "
		no.custom_minimum_size = Vector2(150, 48)
		no.pressed.connect(func() -> void: _sleep_q.visible = false)
		row.add_child(no)
	_sleep_q.visible = true
	ui.root.move_child(_sleep_q, ui.root.get_child_count() - 1)


func _st_refresh() -> void:
	if _st_reticle_btn == null:
		return
	_st_reticle_btn.text = "Aiming dot:  %s" % ("ON" if _main.reticle_on else "OFF")
	if _st_full_btn != null:
		_st_full_btn.text = "  Fullscreen: %s (F11)  " % ("ON" if _main.fullscreen else "OFF")
	if _st_resume_btn != null:
		_st_resume_btn.text = "Games keep your place:  " + ("ON" if _main.emu.resume_games else "OFF")
	if _st_cart_btn != null:
		_st_cart_btn.text = "Cartridge colours:  " + ("LOFI PINK" if _main.cart_wash else "ORIGINAL")
	if _st_weather_btn != null:
		_st_weather_btn.text = "Weather at start:  " + ("THE LAST ONE" if _main.weather_start == "remember" else "RANDOM")
	if _st_update_label != null:
		var u: Node = _main.updater
		_st_update_label.text = "This is version %d.  %s" % [u.local_version, u.message]
		_st_update_btn.text = "Install the update" if u.state == "available" else ("Please wait..." if u.busy() else "Check for updates")
		_st_update_btn.disabled = u.busy()
	for i in _st_color_btns.size():
		var sel: bool = i == _main.reticle_color_idx
		_st_color_btns[i].text = ("[ %s ]" if sel else "%s") % String(_main.RETICLE_COLORS[i][0])


# ---- controller inputs (Settings > Controls...): the same bindings the TV consoles and the arcade cabinet use

func _ct_devices() -> Array:
	return ["vr"] if _main.xr_active else ["key", "pad"]


func _open_controls_window() -> void:
	_st_window.visible = false
	_ct_window.visible = true
	var d := _ct_devices()
	if not d.has(_ct_dev):
		_ct_dev = d[0]
	_ct_listen = ""
	_ct_refresh()


func _close_controls_window() -> void:
	_ct_listen = ""
	_ct_window.visible = false
	_st_window.visible = true
	_st_refresh()


func _build_controls_window() -> void:
	_ct_window = PanelContainer.new()
	_ct_window.offset_left = 150.0
	_ct_window.offset_top = 6.0
	_ct_window.offset_right = 874.0
	_ct_window.offset_bottom = 545.0
	_ct_window.visible = false
	ui.root.add_child(_ct_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_ct_window.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Controls"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back := Button.new()
	back.text = "  Back  "
	back.pressed.connect(_close_controls_window)
	head.add_child(back)
	_ct_note = Label.new()
	_ct_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ct_note.add_theme_font_size_override("font_size", 17)
	v.add_child(_ct_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_ct_dev_btn = Button.new()
	_ct_dev_btn.custom_minimum_size = Vector2(0, 36)
	_ct_dev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ct_dev_btn.pressed.connect(func() -> void:
		var d := _ct_devices()
		_ct_dev = d[(d.find(_ct_dev) + 1) % d.size()]
		_ct_listen = ""
		_ct_refresh())
	row.add_child(_ct_dev_btn)
	_ct_swap_ab = Button.new()
	_ct_swap_ab.custom_minimum_size = Vector2(0, 36)
	_ct_swap_ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ct_swap_ab.pressed.connect(func() -> void:
		_main.padmap.swap_pair(_ct_dev, "a", "b")
		_ct_refresh())
	row.add_child(_ct_swap_ab)
	_ct_swap_xy = Button.new()
	_ct_swap_xy.custom_minimum_size = Vector2(0, 36)
	_ct_swap_xy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ct_swap_xy.pressed.connect(func() -> void:
		_main.padmap.swap_pair(_ct_dev, "x", "y")
		_ct_refresh())
	row.add_child(_ct_swap_xy)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for a in ["a", "b", "x", "y", "l", "r", "start", "select", "up", "down", "left", "right"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_ct_start_listen.bind(a))
		grid.add_child(b)
		_ct_btns[a] = b
	var rst := Button.new()
	rst.custom_minimum_size = Vector2(0, 36)
	rst.text = "Reset this device to the defaults"
	rst.pressed.connect(func() -> void:
		_main.padmap.reset(_ct_dev)
		_ct_listen = ""
		_ct_refresh())
	v.add_child(rst)


func _ct_start_listen(action: String) -> void:
	_ct_listen = action
	_ct_listen_t = 8.0
	_ct_base = {}
	if _ct_dev != "key":
		var lh: Node = _main.left_hand if _main.xr_active else null
		var rh: Node = _main.right_hand if _main.xr_active else null
		_ct_base = _main.padmap.held(_ct_dev, lh, rh)
	_ct_refresh()


func _ct_refresh() -> void:
	if _ct_window == null:
		return
	var pm = _main.padmap
	var dev_names := {"pad": "GAMEPAD", "key": "KEYBOARD", "vr": "VR CONTROLLERS"}
	_ct_dev_btn.text = "Device:  " + String(dev_names[_ct_dev])
	_ct_swap_ab.text = "A and B:  " + ("SWAPPED" if pm.is_swapped(_ct_dev, "a", "b") else "normal")
	_ct_swap_xy.text = "X and Y:  " + ("SWAPPED" if pm.is_swapped(_ct_dev, "x", "y") else "normal")
	for a in _ct_btns.keys():
		var val: String = "press a key..." if (_ct_listen == a and _ct_dev == "key") else ("press a button..." if _ct_listen == a else pm.name_of(pm.maps[_ct_dev][a]))
		_ct_btns[a].text = "%s  =  %s" % [String(pm.LABELS[a]), val]
	if _ct_listen != "":
		_ct_note.text = "Press the %s you want for %s.  Esc cancels." % ["key" if _ct_dev == "key" else "button", String(pm.LABELS[_ct_listen])]
	elif _ct_dev == "pad" and not pm.has_gamepad():
		_ct_note.text = "No gamepad is connected. Plug one in to change its buttons."
	else:
		_ct_note.text = "Used by the TV consoles and the arcade. Click one, then press the new key. (Arcade: SELECT = coin, START = start.)"


# main.gd hands key presses here first; true means the press was used for a new binding
func ct_wants_key(event: InputEvent) -> bool:
	if _ct_window == null or not _ct_window.visible or _ct_listen == "" or _ct_dev != "key":
		return false
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	if event.keycode == KEY_ESCAPE:
		_ct_listen = ""
	else:
		_main.padmap.assign("key", _ct_listen, "k:%d" % int(event.physical_keycode))
		_ct_listen = ""
	_ct_refresh()
	return true


func _ct_tick(delta: float) -> void:
	if _ct_listen == "":
		return
	_ct_listen_t -= delta
	if _ct_dev != "key":
		var lh: Node = _main.left_hand if _main.xr_active else null
		var rh: Node = _main.right_hand if _main.xr_active else null
		var got: String = _main.padmap.poll(_ct_dev, lh, rh, _ct_base)
		if got != "":
			_main.padmap.assign(_ct_dev, _ct_listen, got)
			_ct_listen = ""
			_ct_refresh()
			return
	if _ct_listen_t <= 0.0:
		_ct_listen = ""
		_ct_refresh()


# ---- lights window (lamps, lantern, fairy lights, ceiling strip)

func _build_lights_window() -> void:
	var btn := Button.new()
	btn.text = "  Lights  "
	btn.pressed.connect(_toggle_lights)
	_bar_row.add_child(btn)
	_bar_row.move_child(btn, 3)
	_lt_window = PanelContainer.new()
	_lt_window.offset_left = 150.0
	_lt_window.offset_top = 40.0
	_lt_window.offset_right = 874.0
	_lt_window.offset_bottom = 500.0
	_lt_window.visible = false
	ui.root.add_child(_lt_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_lt_window.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Lights"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = " x "
	close.pressed.connect(_toggle_lights)
	head.add_child(close)
	var hint := Label.new()
	hint.text = "Switch the room's lights (you can also click the lamps in the room). The TV and monitor have their own power buttons."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var allrow := HBoxContainer.new()
	allrow.add_theme_constant_override("separation", 10)
	v.add_child(allrow)
	var all_on := Button.new()
	all_on.text = "  ALL ON  "
	all_on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_on.custom_minimum_size = Vector2(0, 56)
	all_on.pressed.connect(_main.set_all_lights.bind(true))
	allrow.add_child(all_on)
	var all_off := Button.new()
	all_off.text = "  ALL OFF  "
	all_off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_off.custom_minimum_size = Vector2(0, 56)
	all_off.pressed.connect(_main.set_all_lights.bind(false))
	allrow.add_child(all_off)
	v.add_child(HSeparator.new())
	_lt_rows = VBoxContainer.new()
	_lt_rows.add_theme_constant_override("separation", 8)
	v.add_child(_lt_rows)
	_main.lights_changed.connect(_lt_refresh)
	_lt_refresh()


func _lt_refresh() -> void:
	if _lt_rows == null:
		return
	for c in _lt_rows.get_children():
		_lt_rows.remove_child(c)
		c.queue_free()
	for gi in _main.light_groups.size():
		var on: bool = _main.is_light_on(gi)
		var b := Button.new()
		b.text = "%s:  %s" % [_main.light_groups[gi]["name"], "ON" if on else "OFF"]
		b.custom_minimum_size = Vector2(0, 48)
		b.pressed.connect(_main.toggle_light.bind(gi))
		_lt_rows.add_child(b)


# ---- weather + curtains window

# The easter egg locks the PC: the music pauses and (via the alert on the screen) nothing can be clicked.
func set_alert_lock(on: bool) -> void:
	if on:
		_music_was_playing = audio.playing and not audio.stream_paused
		audio.stream_paused = true
	else:
		if _music_was_playing:
			audio.stream_paused = false
		_music_was_playing = false


func setup_weather(weather: Node, main: Node) -> void:
	_weather = weather
	_main = main
	var btn := Button.new()
	btn.text = "  Weather  "
	btn.pressed.connect(_toggle_weather)
	_bar_row.add_child(btn)
	_bar_row.move_child(btn, 2)
	_wx_window = PanelContainer.new()
	_wx_window.offset_left = 150.0
	_wx_window.offset_top = 10.0
	_wx_window.offset_right = 874.0
	_wx_window.offset_bottom = 500.0
	_wx_window.visible = false
	ui.root.add_child(_wx_window)
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	_wx_window.add_child(outer)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Weather"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = " x "
	close.pressed.connect(_toggle_weather)
	head.add_child(close)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	for i in 4:
		var b := Button.new()
		b.text = " %s " % weather.NAMES[i]
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_weather.bind(i))
		row.add_child(b)
		_wx_buttons.append(b)
	# intensity slider: each weather remembers its own setting
	_wx_int_row = VBoxContainer.new()
	v.add_child(_wx_int_row)
	_wx_int_title = Label.new()
	_wx_int_row.add_child(_wx_int_title)
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 10)
	_wx_int_row.add_child(irow)
	_wx_int_lo = Label.new()
	_wx_int_lo.custom_minimum_size = Vector2(130, 0)
	irow.add_child(_wx_int_lo)
	_wx_int = HSlider.new()
	_wx_int.min_value = 0.0
	_wx_int.max_value = 1.0
	_wx_int.step = 0.01
	_wx_int.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wx_int.custom_minimum_size = Vector2(0, 32)
	_wx_int.value_changed.connect(_on_intensity)
	irow.add_child(_wx_int)
	_wx_int_hi = Label.new()
	_wx_int_hi.custom_minimum_size = Vector2(130, 0)
	_wx_int_hi.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	irow.add_child(_wx_int_hi)
	var vrow := HBoxContainer.new()
	v.add_child(vrow)
	var vl := Label.new()
	vl.text = "AMBIENT VOLUME "
	vrow.add_child(vl)
	_wx_vol = HSlider.new()
	_wx_vol.min_value = 0.0
	_wx_vol.max_value = 1.0
	_wx_vol.step = 0.01
	_wx_vol.value = weather.volume
	_wx_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wx_vol.custom_minimum_size = Vector2(0, 30)
	_wx_vol.value_changed.connect(weather.set_volume)
	vrow.add_child(_wx_vol)
	_wx_traffic_btn = Button.new()
	_wx_traffic_btn.custom_minimum_size = Vector2(0, 40)
	_wx_traffic_btn.pressed.connect(_toggle_traffic)
	v.add_child(_wx_traffic_btn)
	# curtains live in their own column on the right: the slider runs up and down like the curtain itself
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	cv.custom_minimum_size = Vector2(170, 0)
	outer.add_child(cv)
	var cl := Label.new()
	cl.text = "Curtains"
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(cl)
	var cl1 := Label.new()
	cl1.text = "UP"
	cl1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(cl1)
	_wx_cur_slider = VSlider.new()
	_wx_cur_slider.min_value = 0.0
	_wx_cur_slider.max_value = 1.0
	_wx_cur_slider.step = 0.01
	_wx_cur_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wx_cur_slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wx_cur_slider.custom_minimum_size = Vector2(40, 0)
	_wx_cur_slider.value_changed.connect(_on_curtain_slider)
	_wx_cur_slider.drag_started.connect(func(): _cur_drag = true)
	_wx_cur_slider.drag_ended.connect(func(_c: bool): _cur_drag = false)
	cv.add_child(_wx_cur_slider)
	var cl2 := Label.new()
	cl2.text = "DOWN"
	cl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(cl2)
	_wx_cur_btn = Button.new()
	_wx_cur_btn.custom_minimum_size = Vector2(0, 44)
	_wx_cur_btn.pressed.connect(_toggle_curtains)
	cv.add_child(_wx_cur_btn)
	_wx_refresh()
	_build_lights_window()
	_build_settings_window()


func _on_intensity(val: float) -> void:
	_weather.set_level(_weather.mode, val)


func _set_weather(i: int) -> void:
	_weather.set_mode(i)
	_wx_refresh()


func _on_curtain_slider(val: float) -> void:
	_main.set_curtain(1.0 - val)       # the slider's top is 'up' = open


func _cur_btn_text() -> String:
	var m = _main
	if m._curtain_moving():
		return "Curtains: STOP"
	if m.curtain_amt < 0.001:
		return "Curtains: lower"
	if m.curtain_amt > 0.999:
		return "Curtains: raise"
	return "Curtains: raise" if m.curtain_last_down else "Curtains: lower"


func _toggle_traffic() -> void:
	_weather.traffic_muted = not _weather.traffic_muted
	_wx_refresh()


func _toggle_curtains() -> void:
	_main.toggle_curtains()
	_wx_refresh()


func _wx_refresh() -> void:
	if _wx_window == null:
		return
	for i in _wx_buttons.size():
		var on: bool = _weather.mode == i
		_wx_buttons[i].text = (" [ %s ] " if on else " %s ") % _weather.NAMES[i]
	var m: int = _weather.mode
	_wx_int_row.visible = m != 0
	if m != 0:
		_wx_int_title.text = "%s intensity" % _weather.NAMES[m]
		_wx_int_lo.text = _weather.LEVEL_LABELS[m][0]
		_wx_int_hi.text = _weather.LEVEL_LABELS[m][1]
		_wx_int.set_value_no_signal(_weather.get_level(m))
	_wx_cur_slider.set_value_no_signal(1.0 - _main.curtain_amt)
	_wx_cur_btn.text = _cur_btn_text()
	_wx_traffic_btn.text = "City traffic: MUTED  (click to turn on)" if _weather.traffic_muted else "City traffic: ON  (click to mute)"


# The room's own songs live in the "music" folder next to the game; the music player opens there.
static func default_music_dir() -> String:
	if Plat.is_android():
		# the game's own files are read-only on a headset, so the room's songs are copied to a folder the player can add to
		var u := ProjectSettings.globalize_path("user://music")
		DirAccess.make_dir_recursive_absolute(u)
		_seed_songs(u)
		return u
	var d := ProjectSettings.globalize_path("res://music") if FileAccess.file_exists("res://project.godot") else OS.get_executable_path().get_base_dir().path_join("music")
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d


static func _seed_songs(dest: String) -> void:
	var have := DirAccess.open(dest)
	if have == null:
		return
	have.list_dir_begin()
	var f := have.get_next()
	while f != "":
		if not have.current_is_dir() and AUDIO_EXTS.has(f.get_extension().to_lower()):
			have.list_dir_end()
			return                                      # already has songs
		f = have.get_next()
	have.list_dir_end()
	var src := DirAccess.open("res://music")
	if src == null:
		return
	src.list_dir_begin()
	f = src.get_next()
	while f != "":
		if not src.current_is_dir() and AUDIO_EXTS.has(f.get_extension().to_lower()):
			var bytes := FileAccess.get_file_as_bytes("res://music/" + f)
			if not bytes.is_empty():
				var o := FileAccess.open(dest.path_join(f), FileAccess.WRITE)
				if o != null:
					o.store_buffer(bytes)
		f = src.get_next()
	src.list_dir_end()


# At start-up: a random song from the room's folder (nothing happens if the folder is empty).
func play_random_default() -> void:
	var da := DirAccess.open(default_music_dir())
	if da == null:
		return
	var found: Array[String] = []
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if not da.current_is_dir() and AUDIO_EXTS.has(f.get_extension().to_lower()):
			found.append(default_music_dir().path_join(f))
		f = da.get_next()
	da.list_dir_end()
	if found.is_empty():
		return
	found.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	playlist.clear()
	for s in found:
		playlist.append(s)
	_play_index(randi() % playlist.size())


func save_music_dir() -> void:
	if _browser != null:
		_browser.save_dir()


func _on_file_chosen(path: String) -> void:
	playlist.clear()
	for p in _browser.files_in_dir():
		playlist.append(p)
	_play_index(playlist.find(path))


func _play_index(i: int) -> void:
	if i < 0 or i >= playlist.size():
		return
	index = i
	var path := playlist[i]
	var stream := _load_audio(path)
	if stream == null:
		_title.text = path.get_file()
		_info.text = "Couldn't open this file (mp3, ogg and 16-bit wav only)."
		return
	audio.stop()
	audio.stream = stream
	audio.stream_paused = false
	audio.play()
	_title.text = path.get_file().get_basename()
	_info.text = "Track %d of %d in this folder" % [i + 1, playlist.size()]
	_play_btn.text = " PAUSE "


# a guest: what the host is playing shows on the player (the local controls still work, they just wait)
var _remote_song := ""


func show_remote_song(title: String) -> void:
	if title == _remote_song:
		return
	_remote_song = title
	if title != "":
		_title.text = title
		_info.text = "Playing on the host's speakers"
	elif audio.is_live():
		_info.text = "The host's music stopped"


func _toggle_play() -> void:
	if audio.stream == null:
		return
	if audio.stream_paused:
		audio.stream_paused = false
		_play_btn.text = " PAUSE "
	elif audio.playing:
		audio.stream_paused = true
		_play_btn.text = " PLAY "
	else:
		audio.play()
		_play_btn.text = " PAUSE "


func _stop() -> void:
	audio.stop()
	audio.stream_paused = false
	_play_btn.text = " PLAY "
	_seek.set_value_no_signal(0.0)
	_time.text = "0:00 / 0:00"


func _prev() -> void:
	if audio.playing and audio.get_playback_position() > 3.0:
		audio.seek(0.0)
	elif index > 0:
		_play_index(index - 1)


func _next() -> void:
	if index + 1 < playlist.size():
		_play_index(index + 1)
	elif repeat_mode == 2 and not playlist.is_empty():
		_play_index(0)                           # repeat folder: back to the first song
	else:
		_stop()


func _set_repeat(m: int) -> void:
	repeat_mode = m
	_rep_track_btn.text = "[ Track ]" if m == 1 else "Track"
	_rep_folder_btn.text = "[ Folder ]" if m == 2 else "Folder"


func _on_finished() -> void:
	if repeat_mode == 1 and index >= 0 and index < playlist.size():
		_play_index(index)                       # repeat track: the same song again
	else:
		_next()


func _on_seek_started() -> void:
	_seeking = true


func _on_seek_ended(_changed: bool) -> void:
	_seeking = false
	if audio.stream != null:
		audio.seek(_seek.value * audio.stream.get_length())


func _set_volume(v: float) -> void:
	audio.set_master(v)
	_vol.set_value_no_signal(v)
	_spk_vol.set_value_no_signal(v)


func _fmt(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d" % [floori(s / 60.0), s % 60]


# ---- loading audio files from anywhere on the PC ----

func _load_audio(path: String) -> AudioStream:
	var ext := path.get_extension().to_lower()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	if ext == "mp3":
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	if ext == "wav":
		return _load_wav(bytes)
	return null


func _load_wav(b: PackedByteArray) -> AudioStream:
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var pos := 12
	var tag := 0
	var channels := 2
	var rate := 44100
	var bits := 16
	var data := PackedByteArray()
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var sz := b.decode_u32(pos + 4)
		var body := pos + 8
		if id == "fmt ":
			tag = b.decode_u16(body)
			channels = b.decode_u16(body + 2)
			rate = b.decode_u32(body + 4)
			bits = b.decode_u16(body + 14)
		elif id == "data":
			data = b.slice(body, mini(body + sz, b.size()))
			break
		pos = body + sz + (sz & 1)
	if tag != 1 or data.is_empty() or (bits != 16 and bits != 8) or channels > 2:
		return null
	if bits == 8:
		for i in data.size():
			data[i] = data[i] ^ 0x80      # wav 8-bit is unsigned, Godot wants signed
	var wav := AudioStreamWAV.new()
	wav.mix_rate = rate
	wav.stereo = channels == 2
	wav.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	wav.data = data
	return wav
