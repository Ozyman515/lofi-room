extends Node3D

const ScreenUI := preload("res://screen_ui.gd")
const FileBrowser := preload("res://file_browser.gd")
## A VHS-style VCR that sits on top of the TV. Point at its slot or EJECT button to pick a video file
## from your PC; the TV plays it. Godot can only play Ogg Theora (.ogv) video, so other formats are
## converted with ffmpeg (if it's installed) and cached in the user:// folder.
## If the godot-vlc add-on is in res://addons (it is, in this project, on Windows/Linux PCs), VLC plays
## the files directly instead: any format, instant start, seeking, and VLC's own audio/subtitle tracks.
## The AUDIO/SUBS button lists the file's audio languages and (text) subtitles, like VLC does.
## The TV's own buttons (power, volume) are built in main.gd and call toggle_tv / volume_up / volume_down.

signal power_changed(on: bool)

enum State { IDLE, MENU, LOADING, PLAYING, PAUSED, STOPPED }

const VIDEO_EXTS := ["ogv", "mp4", "mkv", "avi", "mov", "webm", "m4v", "wmv", "flv", "mpg", "mpeg", "ts"]

var buttons: Array = []          # interactables: {"node", "half", "label", "cb"}
var state := State.IDLE
var has_tape := false
var tv_on := true
var tv_volume := 7                # 0..10

var _mat: ShaderMaterial
var _ui: ScreenUI
var _holder: SubViewport
var _player: VideoStreamPlayer
var _menu: PanelContainer
var _browser: FileBrowser
var _status_panel: PanelContainer
var _status: Label
var _osd: Label
var _osd_t := 0.0
var _display: Label3D
var _tape: Node3D
var _return_state := State.IDLE
var _waiting_tex := false
var _current := ""
var _ffmpeg := ""
var _remux := false
var _seek_pending := -1             # where the last seek asked to go (ms), until VLC catches up
var _seek_wall := 0
var aspect_mode := 0                 # 0 original, 1 zoom (crop to fill), 2 stretch, 3 widescreen 16:9
const ASPECT_NAMES := ["ORIGINAL", "ZOOM  (crop to fill)", "STRETCH  (fill 4:3)", "WIDESCREEN  16:9"]
var _pid := -1
var _progress_path := ""
var _tmp_out := ""
var _final_out := ""
var _poll_t := 0.0
var _power_t := 1.0
var external_hold := false         # the game console is on, so a TV power-on must not resume the tape
var _tv_paused := false           # we paused the tape because the TV was switched off
var _ended := false
var _osd_clock := false
var _src := ""                    # the file the person picked (before conversion)
var _offset := 0.0                # seconds of the original that the converted file skips
var _tracks := {"audio": [], "subs": []}
var _audio_sel := -1              # -1 = ffmpeg's default audio track, else the n-th audio stream
var _sub_sel := -1                # -1 = off, else index into _tracks["subs"]
var _temp_file := ""              # partial-length conversion to delete later
var _cues: Array = []             # [[start, end, text], ...]
var _sub_label: Label
var _sub_pid := -1
var _sub_out := ""
var _sub_final := ""
var _sub_want := -1
var _sub_poll := 0.0
var _opts: PanelContainer
var _audio_list: ItemList
var _sub_list: ItemList
var _opts_note: Label
var _opts_stats: Label
var _mix_btn: Button
var _diag_t := 0.0
var _diag_last := ""
var _vlc: Control = null          # VLCMediaPlayer node (when the add-on is present)
var _use_vlc := false
var _paused_flag := false
var _vlc_seen := false
var _vlc_t := 0.0
var _last_tex: Texture2D = null
var _last_size := Vector2i.ZERO
var _audio_tl: RefCounted = null
var _sub_tl: RefCounted = null
var _audio_tracks: Array = []
var _sub_tracks: Array = []
var _resume_after_modal := false


func setup(tv_mat: ShaderMaterial, tv_ui: ScreenUI) -> void:
	_mat = tv_mat
	_ui = tv_ui
	_build_model()
	_build_player()
	_build_ui()
	_show_idle_status()


func _exit_tree() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	if _sub_pid > 0 and OS.is_process_running(_sub_pid):
		OS.kill(_sub_pid)
	_cleanup_temp()


# ---------------------------------------------------------------- the 3D model

func _mk(pos: Vector3, size: Vector3, color: Color, emit: float = 0.0, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.disable_fog = true
	m.albedo_color = color
	m.roughness = 0.5
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	mi.material_override = m
	mi.position = pos
	var p: Node = parent if parent != null else self
	p.add_child(mi)
	return mi


func _build_model() -> void:
	_mk(Vector3(0, 0.05, 0), Vector3(0.86, 0.10, 0.40), Color(0.11, 0.10, 0.14))
	_mk(Vector3(0, 0.1035, 0), Vector3(0.86, 0.007, 0.40), Color(0.20, 0.18, 0.23))
	# tape slot + flap
	var slot := _mk(Vector3(-0.14, 0.062, 0.2), Vector3(0.44, 0.05, 0.008), Color(0.02, 0.02, 0.03))
	_mk(Vector3(-0.14, 0.092, 0.204), Vector3(0.44, 0.010, 0.012), Color(0.30, 0.28, 0.34))
	# the cassette sticking out of the slot (only visible when a tape is in)
	_tape = Node3D.new()
	add_child(_tape)
	_mk(Vector3(-0.14, 0.062, 0.165), Vector3(0.40, 0.03, 0.20), Color(0.08, 0.08, 0.10), 0.0, _tape)
	_mk(Vector3(-0.14, 0.0775, 0.23), Vector3(0.30, 0.002, 0.07), Color(0.92, 0.86, 0.80), 0.0, _tape)
	_mk(Vector3(-0.14, 0.0780, 0.255), Vector3(0.30, 0.002, 0.02), Color(0.95, 0.35, 0.60), 0.0, _tape)
	_tape.visible = false
	# display
	_mk(Vector3(0.26, 0.07, 0.2), Vector3(0.15, 0.05, 0.008), Color(0.02, 0.03, 0.03))
	_display = Label3D.new()
	_display.text = "12:00"
	_display.font_size = 40
	_display.pixel_size = 0.0009
	_display.modulate = Color(0.45, 1.0, 0.55)
	_display.position = Vector3(0.26, 0.07, 0.2065)
	add_child(_display)
	_mk(Vector3(0.375, 0.095, 0.2), Vector3(0.012, 0.012, 0.006), Color(1.0, 0.2, 0.2), 2.0)   # power LED

	# buttons you can point at
	var defs := [
		[0.025, Color(0.55, 0.55, 0.65), "REWIND  10 s", seek_rel.bind(-10.0)],
		[0.085, Color(0.55, 0.55, 0.65), "FAST FORWARD  30 s", seek_rel.bind(30.0)],
		[0.145, Color(0.25, 0.70, 0.35), "PLAY / PAUSE", play_pause],
		[0.205, Color(0.70, 0.30, 0.30), "STOP", stop],
		[0.265, Color(0.75, 0.62, 0.25), "EJECT", eject],
		[0.34, Color(0.30, 0.45, 0.80), "AUDIO / SUBTITLES", open_options],
		[0.40, Color(0.55, 0.35, 0.75), _picture_label, cycle_aspect],
	]
	for d in defs:
		var mi := _mk(Vector3(d[0], 0.022, 0.204), Vector3(0.05, 0.026, 0.012), d[1])
		buttons.append({"node": mi, "half": Vector3(0.034, 0.03, 0.04), "label": d[2], "cb": d[3], "hover": _glow(mi)})
	buttons.append({"node": slot, "half": Vector3(0.24, 0.04, 0.05), "label": "TAPE SLOT", "cb": open_menu, "hover": _glow(slot)})


func _glow(mi: MeshInstance3D) -> Callable:
	var m := mi.material_override as StandardMaterial3D
	return func(on: bool) -> void:
		m.emission_enabled = on
		if on:
			m.emission = Color(1.0, 0.9, 1.0)
			m.emission_energy_multiplier = 0.8


# ---------------------------------------------------------------- video + UI

func _build_player() -> void:
	_holder = SubViewport.new()
	_holder.size = Vector2i(2, 2)
	_holder.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_holder)
	_player = VideoStreamPlayer.new()
	_player.finished.connect(_on_finished)
	_holder.add_child(_player)
	_use_vlc = ClassDB.class_exists("VLCMediaPlayer") and Engine.has_singleton("VLCInstance")


# A fresh VLC player for every file: the add-on keeps the first video's frame size otherwise.
func _new_vlc_player() -> void:
	if _vlc != null:
		_vlc.stop_async()
		_holder.remove_child(_vlc)
		_vlc.queue_free()
	_vlc = ClassDB.instantiate("VLCMediaPlayer")
	_vlc.size = Vector2(640, 360)
	_holder.add_child(_vlc)
	_audio_tl = null
	_sub_tl = null
	_audio_tracks.clear()
	_sub_tracks.clear()


# ---- tiny wrappers so the rest of the script doesn't care which player is used

func _set_paused(on: bool) -> void:
	_paused_flag = on
	if _use_vlc:
		if _vlc != null:
			_vlc.set_pause(on)
	else:
		_player.paused = on


func _p_stop() -> void:
	_paused_flag = false
	_player.stop()
	if _use_vlc and _vlc != null:
		_vlc.stop_async()


func _play_file(path: String) -> void:
	if _use_vlc:
		_start_vlc(path)
	else:
		_start_video(path)


func _build_ui() -> void:
	var root := _ui.root

	_menu = PanelContainer.new()
	_menu.offset_left = 60.0
	_menu.offset_top = 50.0
	_menu.offset_right = 964.0
	_menu.offset_bottom = 718.0
	_menu.visible = false
	root.add_child(_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_menu.add_child(v)
	var title := Label.new()
	title.text = "VCR  -  pick a tape (any video file on your PC)"
	v.add_child(title)
	_browser = FileBrowser.new()
	_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_browser)
	var movies := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
	_browser.setup(PackedStringArray(VIDEO_EXTS), "video", [["Videos", movies], ["Downloads", OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)], ["Desktop", OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)]], movies)
	_browser.file_chosen.connect(_on_file_chosen)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_menu)
	v.add_child(close)

	# audio / subtitle chooser
	_opts = PanelContainer.new()
	_opts.offset_left = 60.0
	_opts.offset_top = 50.0
	_opts.offset_right = 964.0
	_opts.offset_bottom = 718.0
	_opts.visible = false
	root.add_child(_opts)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 10)
	_opts.add_child(ov)
	var ot := Label.new()
	ot.text = "AUDIO / SUBTITLES"
	ov.add_child(ot)
	_opts_note = Label.new()
	_opts_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ov.add_child(_opts_note)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	ov.add_child(cols)
	for kind in ["audio", "subs"]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
		var cl := Label.new()
		cl.text = "Audio language" if kind == "audio" else "Subtitles"
		col.add_child(cl)
		var il := ItemList.new()
		il.size_flags_vertical = Control.SIZE_EXPAND_FILL
		il.allow_reselect = false
		col.add_child(il)
		if kind == "audio":
			_audio_list = il
			il.item_selected.connect(_select_audio)
		else:
			_sub_list = il
			il.item_selected.connect(_select_sub)
	_opts_stats = Label.new()
	_opts_stats.add_theme_font_size_override("font_size", 16)
	ov.add_child(_opts_stats)
	_mix_btn = Button.new()
	_mix_btn.text = "Audio mix: Stereo  (click to change)"
	_mix_btn.visible = _use_vlc
	_mix_btn.pressed.connect(cycle_mix)
	ov.add_child(_mix_btn)
	var oclose := Button.new()
	oclose.text = "Close"
	oclose.pressed.connect(_close_menu)
	ov.add_child(oclose)

	_status_panel = PanelContainer.new()
	_status_panel.offset_left = 112.0
	_status_panel.offset_top = 560.0
	_status_panel.offset_right = 912.0
	_status_panel.offset_bottom = 720.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.04, 0.38, 0.88)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16.0)
	_status_panel.add_theme_stylebox_override("panel", sb)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 30)
	_status.add_theme_color_override("font_color", Color(0.85, 1.0, 0.9))
	_status_panel.add_child(_status)
	root.add_child(_status_panel)

	# subtitles, bottom centre
	_sub_label = Label.new()
	_sub_label.anchor_left = 0.0
	_sub_label.anchor_right = 1.0
	_sub_label.anchor_top = 1.0
	_sub_label.anchor_bottom = 1.0
	_sub_label.offset_left = 50.0
	_sub_label.offset_right = -50.0
	_sub_label.offset_top = -190.0
	_sub_label.offset_bottom = -50.0
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_label.add_theme_font_size_override("font_size", 34)
	_sub_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_sub_label.add_theme_constant_override("outline_size", 10)
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_label.visible = false
	root.add_child(_sub_label)

	_osd = Label.new()
	_osd.offset_left = 48.0
	_osd.offset_top = 36.0
	_osd.add_theme_font_size_override("font_size", 46)
	_osd.add_theme_color_override("font_color", Color(0.7, 1.0, 0.75))
	_osd.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_osd.add_theme_constant_override("outline_size", 8)
	_osd.visible = false
	root.add_child(_osd)
	_apply_volume()


func _show_status(text: String) -> void:
	_status.text = text
	_status_panel.visible = text != ""


func _show_idle_status() -> void:
	_show_status("NO TAPE\nPoint at EJECT or the tape slot on the VCR\nand click to pick a video")


func _refresh_status() -> void:
	match state:
		State.IDLE:
			_show_idle_status()
		State.STOPPED:
			if _ended:
				_show_status("END OF TAPE\nPress PLAY on the VCR to watch again")
			else:
				_show_status("STOPPED\nPress PLAY on the VCR to carry on from here")
		_:
			_show_status("")


func _osd_show(text: String, secs: float = 3.0, clock: bool = false) -> void:
	_osd.text = text
	_osd.visible = true
	_osd_t = secs
	_osd_clock = clock


# ---------------------------------------------------------------- TV power + volume (buttons are on the TV)

func toggle_tv() -> void:
	tv_on = not tv_on
	_ui.enabled = tv_on
	if not tv_on:
		_ui.clear_hover()
		_osd.visible = false
		if state == State.PLAYING and not _paused_flag:
			_set_paused(true)             # like a VCR: the tape stays where it was
			_tv_paused = true
	else:
		if _tv_paused and not external_hold:
			_set_paused(false)
			_tv_paused = false
	power_changed.emit(tv_on)


func volume_up() -> void:
	_change_volume(1)


func volume_down() -> void:
	_change_volume(-1)


func _change_volume(d: int) -> void:
	if not tv_on:
		return
	tv_volume = clampi(tv_volume + d, 0, 10)
	_apply_volume()
	_osd_show("VOL  " + "|".repeat(tv_volume) + ".".repeat(10 - tv_volume), 2.0)


func _apply_volume() -> void:
	var db := -80.0 if tv_volume == 0 else linear_to_db(tv_volume / 10.0)
	if _player != null:
		_player.volume_db = db
	if _vlc != null:
		_vlc.volume_db = db


# ---------------------------------------------------------------- controls (called by the buttons)

func _hide_panels() -> void:
	_menu.visible = false
	_opts.visible = false


func _enter_modal() -> void:
	if state == State.LOADING:
		return
	_resume_after_modal = false
	if state == State.PLAYING and not _paused_flag:
		_set_paused(true)
		state = State.PAUSED
		_resume_after_modal = true
	_return_state = state
	state = State.MENU
	_show_status("")
	_sub_label.visible = false


func open_menu() -> void:
	if not tv_on:
		return
	if state == State.LOADING:
		_show_status("RECORDING TAPE...\nplease wait (EJECT cancels)")
		return
	if state == State.MENU:
		_hide_panels()
	else:
		_enter_modal()
	_menu.visible = true


func open_options() -> void:
	if not tv_on:
		return
	if state == State.LOADING:
		_show_status("RECORDING TAPE...\nplease wait (EJECT cancels)")
		return
	if state == State.MENU:
		_hide_panels()
	else:
		_enter_modal()
	_refresh_options()
	_opts.visible = true


func _close_menu() -> void:
	_hide_panels()
	if state == State.MENU:
		state = _return_state
		if _resume_after_modal and state == State.PAUSED and tv_on:
			_set_paused(false)         # carry on where you were
			state = State.PLAYING
			_return_state = State.PLAYING
	_resume_after_modal = false
	_refresh_status()


func play_pause() -> void:
	if not tv_on:
		return
	match state:
		State.IDLE:
			open_menu()
		State.PLAYING:
			_set_paused(true)
			state = State.PAUSED
			_osd_show("PAUSE", 1.0e6)
		State.PAUSED:
			_set_paused(false)
			state = State.PLAYING
			_osd_show("PLAY", 3.0, true)
		State.STOPPED:
			if _current == "":
				open_menu()
			elif _ended:
				_play_file(_current)
			else:
				_set_paused(false)              # carry on from where it was stopped
				_set_video(true)
				state = State.PLAYING
				_return_state = State.PLAYING
				_refresh_status()
				_osd_show("PLAY", 3.0, true)
		_:
			pass


func stop() -> void:
	if not tv_on:
		return
	if state == State.PLAYING or state == State.PAUSED:
		_set_paused(true)                       # keeps the place, like stopping a tape
		_set_video(false)
		state = State.STOPPED
		_return_state = State.STOPPED
		_ended = false
		_sub_label.visible = false
		_refresh_status()
		_osd_show("STOP")


func eject() -> void:
	if not tv_on:
		return
	if state == State.LOADING:
		_cancel_conversion()
		return
	_p_stop()
	_set_video(false)
	_cleanup_temp()
	has_tape = false
	_tape.visible = false
	_current = ""
	_src = ""
	_offset = 0.0
	_audio_sel = -1
	_clear_subs()
	_tracks = {"audio": [], "subs": []}
	_ended = false
	_tv_paused = false
	_osd.visible = false
	_hide_panels()
	state = State.IDLE
	_return_state = State.IDLE
	open_menu()


func _on_file_chosen(path: String) -> void:
	_hide_panels()
	_p_stop()
	_set_video(false)
	_cleanup_temp()
	_clear_subs()
	_audio_sel = -1
	_offset = 0.0
	_src = path
	_ended = false
	_tracks = {"audio": [], "subs": []}
	has_tape = true
	_tape.visible = true
	if _use_vlc:
		_start_vlc(path)
	elif path.get_extension().to_lower() == "ogv":
		_start_video(path)
	else:
		_convert_and_play(path)


func _start_video(ogv_path: String) -> void:
	var vs := VideoStreamTheora.new()
	vs.file = ogv_path
	_player.stream = vs
	_player.paused = false
	_paused_flag = false
	_player.play()
	_apply_volume()
	_current = ogv_path
	state = State.PLAYING
	_return_state = State.PLAYING
	_ended = false
	_waiting_tex = true
	_tv_paused = false
	if not tv_on:
		_set_paused(true)                # the TV is off: it will carry on when the TV comes back
		_tv_paused = true
	_show_status("")
	_osd_show("PLAY", 3.0, true)


# ---- VLC playback (any format, no converting)

# TrueHD (the usual Blu-ray rip lossless track) comes out of LibVLC as mostly silence with little bursts.
# If ffmpeg is around, swap just that audio track for FLAC (video/subs are copied, so it's far quicker than a
# full conversion) and cache the result; otherwise play the file as it is.
func _start_vlc(path: String) -> void:
	var ff := _find_ffmpeg()
	if ff != "":
		var cache := ProjectSettings.globalize_path("user://vcr_cache")
		var key := (path + str(FileAccess.get_modified_time(path))).md5_text()
		var fixed := cache.path_join(key + "_flac.mkv")
		if FileAccess.file_exists(fixed):
			_open_vlc(fixed)
			return
		var tr := _probe(path, ff)
		var bad := false
		var args := PackedStringArray(["-y", "-nostdin", "-loglevel", "error", "-i", path, "-map", "0", "-c", "copy"])
		var n := 0
		for a in tr["audio"]:
			if str(a["codec"]) in ["truehd", "mlp"]:
				bad = true
				args.append_array(["-c:a:%d" % n, "flac"])
			n += 1
		if bad:
			DirAccess.make_dir_recursive_absolute(cache)
			_final_out = fixed
			_tmp_out = fixed + ".part"
			_progress_path = cache.path_join(key + ".progress")
			args.append_array(["-f", "matroska", "-progress", _progress_path, _tmp_out])
			_pid = OS.create_process(ff, args)
			if _pid > 0:
				_remux = true
				_temp_file = ""
				state = State.LOADING
				_return_state = State.LOADING
				_poll_t = 0.0
				_show_status("PREPARING TAPE...\nfixing the TrueHD audio (one time only, EJECT cancels)")
				return
	_open_vlc(path)


func _open_vlc(path: String) -> void:
	_seek_pending = -1
	print("[VCR] opening in VLC: ", path, "  (ffmpeg: ", _ffmpeg if _ffmpeg != "" else "not found", ")")
	var media = Engine.get_singleton("VLCInstance").load_media_file(path)
	if media == null:
		_fail_tape("VLC couldn't open that file.")
		return
	_new_vlc_player()
	_paused_flag = false
	_vlc.media = media
	_vlc.play()
	_apply_volume()
	_current = path
	state = State.PLAYING
	_return_state = State.PLAYING
	_ended = false
	_waiting_tex = true
	_last_tex = null
	_vlc_seen = false
	_vlc_t = 0.0
	_tv_paused = false
	_paused_flag = false
	if not tv_on:
		_set_paused(true)
		_tv_paused = true
	_show_status("")
	_osd_show("PLAY", 3.0, true)


# VLC hands over a frame buffer padded to multiples of 32 (+2) rows and 16 columns, and the picture is
# stretched to fill it. Undo that by picking the common aspect ratio that fits the padded size.
func _vlc_aspect(w: int, h: int) -> float:
	if _vlc.is_gpu_output_active():
		return float(w) / float(h)
	var hmax := float(h - 2)
	var hmin := maxf(hmax - 31.0, 1.0)
	var lo := maxf(float(w - 15), 1.0) / hmax
	var hi := float(w) / hmin
	var best := 0.0
	var best_d := 1.0e9
	var centre := sqrt(lo * hi)
	for a in [1.0, 1.25, 4.0 / 3.0, 1.5, 1.6, 1.7778, 1.85, 2.0, 2.2, 2.35, 2.39, 2.4, 2.76]:
		if a >= lo - 0.005 and a <= hi + 0.005 and absf(a - centre) < best_d:
			best_d = absf(a - centre)
			best = a
	return best if best > 0.0 else centre


func _picture_label() -> String:
	return "PICTURE SHAPE  [%s]" % String(ASPECT_NAMES[aspect_mode]).split("  ")[0]


# Q / the PICTURE button: original shape -> zoom (crops the picture so it fills the screen) -> stretch -> 16:9
func cycle_aspect() -> void:
	if not tv_on:
		return
	aspect_mode = (aspect_mode + 1) % ASPECT_NAMES.size()
	_mat.set_shader_parameter("video_mode", aspect_mode)
	if state == State.PLAYING or state == State.PAUSED:
		_osd_show("PICTURE  " + ASPECT_NAMES[aspect_mode], 2.5)


func _set_video(on: bool) -> void:
	_mat.set_shader_parameter("use_video", on)
	if not on:
		_waiting_tex = false


func _on_finished() -> void:
	state = State.STOPPED
	_return_state = State.STOPPED
	_ended = true
	_set_video(false)
	_sub_label.visible = false
	_refresh_status()
	_osd_show("END")


# VLC keeps reporting the OLD position for a moment after a seek (a precise seek in a big video can take a second
# or two). Pressing REW again in that window used to start from the stale time and so landed later than the first
# press, which felt like the tape moving forward. So after a seek we use where we asked to be, plus the time that
# has passed, until VLC's own clock agrees.
func _vlc_ms() -> int:
	if _vlc == null:
		return 0
	var vt := int(_vlc.get_time())
	if _seek_pending < 0:
		return vt
	var elapsed := 0 if _paused_flag else Time.get_ticks_msec() - _seek_wall
	var predicted := _seek_pending + elapsed
	if absi(vt - predicted) < 1500 or Time.get_ticks_msec() - _seek_wall > 10000:
		_seek_pending = -1
		return vt
	return predicted


func _now() -> float:
	if _use_vlc:
		return float(_vlc_ms()) / 1000.0
	return _offset + _player.stream_position


func seek_rel(secs: float) -> void:
	if not tv_on or (state != State.PLAYING and state != State.PAUSED):
		return
	if not _use_vlc:
		_osd_show("CAN'T SEEK  (needs the VLC add-on)", 2.5)
		return
	if _vlc == null or not _vlc.is_seekable():
		_osd_show("CAN'T SEEK THIS FILE", 2.0)
		return
	var t := maxi(0, _vlc_ms() + int(secs * 1000.0))
	var length := int(_vlc.get_length())
	if length > 1000:
		t = mini(t, length - 1000)
	_vlc.set_time(t, false)
	_seek_pending = t
	_seek_wall = Time.get_ticks_msec()
	var sec := t / 1000
	_osd_show("%s  %d:%02d:%02d" % ["FF" if secs > 0.0 else "REW", sec / 3600, (sec / 60) % 60, sec % 60], 1.5)



# ---------------------------------------------------------------- audio language + subtitles

func _lang_name(code: String) -> String:
	var names := {
		"eng": "English", "jpn": "Japanese", "spa": "Spanish", "fre": "French", "fra": "French",
		"ger": "German", "deu": "German", "ita": "Italian", "por": "Portuguese", "rus": "Russian",
		"kor": "Korean", "chi": "Chinese", "zho": "Chinese", "ara": "Arabic", "hin": "Hindi",
		"dut": "Dutch", "nld": "Dutch", "pol": "Polish", "swe": "Swedish", "tur": "Turkish",
		"tha": "Thai", "vie": "Vietnamese", "und": "Unknown", "": "Unknown",
	}
	return str(names.get(code, code.capitalize()))


func _track_label(t: Dictionary, n: int) -> String:
	var txt := "%d. %s" % [n, _lang_name(str(t["lang"]))]
	if str(t["title"]) != "":
		txt += " - " + str(t["title"])
	txt += "  (" + str(t["codec"]) + ")"
	return txt


func _refresh_options_vlc() -> void:
	_audio_list.clear()
	_sub_list.clear()
	_audio_tracks.clear()
	_sub_tracks.clear()
	if _src == "" or _vlc == null:
		_opts_note.text = "No tape in. Pick a video first."
		return
	_opts_note.text = "Pick an audio language and subtitles, just like in VLC. Changes apply straight away."
	_opts_stats.text = _vlc_stats_text()
	_mix_btn.text = "Audio mix: " + ["Stereo", "Surround", "Center"][int(_vlc.mix_target)] + "  (click to change)"
	_audio_tl = _vlc.get_tracklist(0, false)
	for i in _audio_tl.tracklist_count():
		_audio_tracks.append(_audio_tl.tracklist_at(i))
	for i in _audio_tracks.size():
		var t = _audio_tracks[i]
		_audio_list.add_item("%d. %s" % [i + 1, _vlc_track_name(t)])
		if t.is_selected():
			_audio_list.select(i)
	_sub_list.add_item("Off")
	_sub_list.select(0)
	_sub_tl = _vlc.get_tracklist(2, false)
	for i in _sub_tl.tracklist_count():
		_sub_tracks.append(_sub_tl.tracklist_at(i))
	for i in _sub_tracks.size():
		var t = _sub_tracks[i]
		_sub_list.add_item("%d. %s" % [i + 1, _vlc_track_name(t)])
		if t.is_selected():
			_sub_list.select(i + 1)
	if _audio_tracks.is_empty():
		_opts_note.text = "No audio tracks found (VLC may still be opening the file). Close this and try again in a second."


func _vlc_track_name(t) -> String:
	var n := str(t.get_name())
	if n == "":
		n = _lang_name(str(t.get_language()))
	var codec := str(t.get_codec_description())
	return n + ("  (" + codec + ")" if codec != "" else "")


func _vlc_stats_text() -> String:
	if _vlc == null or _vlc.get_media() == null:
		return ""
	var st: Dictionary = _vlc.get_media().get_stats()
	return "Lost audio buffers: %d   Late/lost frames: %d / %d   Audio mix: %s" % [
		int(st.get("lost_abuffers", 0)), int(st.get("late_pictures", 0)), int(st.get("lost_pictures", 0)),
		["Stereo", "Surround", "Center"][int(_vlc.mix_target)]]


func cycle_mix() -> void:
	if _vlc == null:
		return
	_vlc.mix_target = (int(_vlc.mix_target) + 1) % 3
	_mix_btn.text = "Audio mix: " + ["Stereo", "Surround", "Center"][int(_vlc.mix_target)] + "  (click to change)"
	_opts_stats.text = _vlc_stats_text()


func _refresh_options() -> void:
	if _use_vlc:
		_refresh_options_vlc()
		return
	_audio_list.clear()
	_sub_list.clear()
	var ext := _src.get_extension().to_lower()
	if _src == "":
		_opts_note.text = "No tape in. Pick a video first."
		return
	if ext == "ogv":
		_opts_note.text = "Ogg files have one audio track and no subtitle tracks."
		_audio_list.add_item("Default")
		_audio_list.select(0)
		_sub_list.add_item("Off")
		_sub_list.select(0)
		return
	_opts_note.text = "Changing the audio language re-records the tape from where you are (a short wait).\nSubtitles: text subtitles only; picture subtitles (DVD / Blu-ray) can't be shown."
	_audio_list.add_item("Default")
	var n := 1
	for t in _tracks["audio"]:
		_audio_list.add_item(_track_label(t, n))
		n += 1
	_audio_list.select(_audio_sel + 1)
	_sub_list.add_item("Off")
	n = 1
	for t in _tracks["subs"]:
		var lab := _track_label(t, n)
		if not bool(t["text"]):
			lab += "  [picture]"
		_sub_list.add_item(lab)
		n += 1
	_sub_list.select(_sub_sel + 1)


func _select_audio(row: int) -> void:
	if _use_vlc:
		if row >= 0 and row < _audio_tracks.size():
			_vlc.select_track(_audio_tracks[row])
			_osd_show("AUDIO  " + _vlc_track_name(_audio_tracks[row]), 2.5)
		return
	var sel := row - 1
	if sel == _audio_sel or _src == "" or _src.get_extension().to_lower() == "ogv":
		return
	var cur := _now() if (_return_state == State.PLAYING or _return_state == State.PAUSED) else _offset
	_audio_sel = sel
	_offset = cur if cur > 1.0 else 0.0
	_p_stop()
	_set_video(false)
	_cleanup_temp()
	_hide_panels()
	if state == State.MENU:
		state = State.IDLE
	_return_state = State.IDLE
	_start_convert()


func _select_sub(row: int) -> void:
	if _use_vlc:
		if row <= 0:
			_vlc.unselect_track_type(2)
			_osd_show("SUBTITLES OFF", 2.0)
		elif row - 1 < _sub_tracks.size():
			_vlc.select_track(_sub_tracks[row - 1])
			_osd_show("SUBS  " + _vlc_track_name(_sub_tracks[row - 1]), 2.5)
		return
	var sel := row - 1
	if sel == _sub_sel:
		return
	_clear_subs()
	if sel < 0:
		_sub_sel = -1
		return
	var t: Dictionary = _tracks["subs"][sel]
	if not bool(t["text"]):
		_opts_note.text = "That one is a picture subtitle track (DVD / Blu-ray style). Only text subtitles work. Pick another."
		_sub_list.select(0)
		_sub_sel = -1
		return
	_sub_sel = sel
	var ff := _find_ffmpeg()
	if ff == "":
		return
	var cache := ProjectSettings.globalize_path("user://vcr_cache")
	var key := (_src + str(FileAccess.get_modified_time(_src))).md5_text()
	_sub_final = cache.path_join("%s_s%d.srt" % [key, int(t["idx"])])
	if FileAccess.file_exists(_sub_final):
		_load_cues(_sub_final)
		return
	_sub_out = _sub_final + ".part"
	_sub_pid = OS.create_process(ff, PackedStringArray(["-y", "-nostdin", "-loglevel", "error", "-i", _src, "-map", "0:%d" % int(t["idx"]), "-c:s", "srt", "-f", "srt", _sub_out]))
	_sub_want = sel
	_sub_poll = 0.0
	_opts_note.text = "Loading subtitles..."


func _clear_subs() -> void:
	if _sub_pid > 0 and OS.is_process_running(_sub_pid):
		OS.kill(_sub_pid)
	_sub_pid = -1
	_sub_want = -1
	_cues.clear()
	_sub_sel = -1
	if _sub_label != null:
		_sub_label.visible = false


func _poll_subs() -> void:
	if OS.is_process_running(_sub_pid):
		return
	_sub_pid = -1
	var ok := false
	if FileAccess.file_exists(_sub_out):
		var f := FileAccess.open(_sub_out, FileAccess.READ)
		ok = f != null and f.get_length() > 0
	if ok:
		DirAccess.rename_absolute(_sub_out, _sub_final)
		_load_cues(_sub_final)
		_opts_note.text = "Subtitles loaded."
	else:
		_sub_sel = -1
		_sub_list.select(0)
		_opts_note.text = "Couldn't read that subtitle track."
	_sub_want = -1


func _load_cues(path: String) -> void:
	_cues = _parse_srt(FileAccess.get_file_as_string(path))
	if _cues.is_empty():
		_osd_show("NO SUBTITLES FOUND", 3.0)


func _srt_time(txt: String) -> float:
	var p := txt.strip_edges().split(" ")[0].replace(",", ".").split(":")
	if p.size() < 3:
		return 0.0
	return float(p[0]) * 3600.0 + float(p[1]) * 60.0 + float(p[2])


func _parse_srt(text: String) -> Array:
	var out: Array = []
	var tags := RegEx.new()
	tags.compile("<[^>]*>|\\{\\\\[^}]*\\}")
	text = text.replace("\r\n", "\n").replace("\r", "\n")
	for block in text.split("\n\n"):
		var lines := block.strip_edges().split("\n")
		var ti := -1
		for i in mini(lines.size(), 3):
			if lines[i].contains("-->"):
				ti = i
				break
		if ti < 0:
			continue
		var parts := lines[ti].split("-->")
		if parts.size() < 2:
			continue
		var body := "\n".join(lines.slice(ti + 1))
		body = tags.sub(body, "", true).strip_edges()
		if body == "":
			continue
		out.append([_srt_time(parts[0]), _srt_time(parts[1]), body])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


func _update_subtitles() -> void:
	if _cues.is_empty() or not tv_on or (state != State.PLAYING and state != State.PAUSED):
		_sub_label.visible = false
		return
	var t := _now()
	var lo := 0
	var hi := _cues.size() - 1
	var found := -1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if float(_cues[mid][0]) <= t:
			found = mid
			lo = mid + 1
		else:
			hi = mid - 1
	if found >= 0 and t <= float(_cues[found][1]):
		_sub_label.text = str(_cues[found][2])
		_sub_label.visible = true
	else:
		_sub_label.visible = false


func _probe(src: String, ff: String) -> Dictionary:
	var out := []
	OS.execute(ff, PackedStringArray(["-hide_banner", "-nostdin", "-i", src]), out, true)
	var text := ""
	for o in out:
		text += str(o)
	var res := {"audio": [], "subs": []}
	var re := RegEx.new()
	re.compile("Stream #0:(\\d+)(?:\\[[^\\]]*\\])?(?:\\(([^)]*)\\))?: (Audio|Subtitle): ([^\\n]*)")
	var text_codecs := ["subrip", "srt", "ass", "ssa", "mov_text", "webvtt", "text", "subviewer", "microdvd", "sami", "realtext", "jacosub"]
	var cur: Dictionary = {}
	for ln in text.replace("\r", "").split("\n"):
		var st := ln.strip_edges()
		var m := re.search(ln)
		if m != null:
			var detail := m.get_string(4)
			var codec := detail.split(" ")[0].split(",")[0]
			cur = {"idx": int(m.get_string(1)), "lang": m.get_string(2), "codec": codec, "title": "", "text": text_codecs.has(codec)}
			if m.get_string(3) == "Audio":
				res["audio"].append(cur)
			else:
				res["subs"].append(cur)
		elif st.begins_with("Stream #"):
			cur = {}
		elif not cur.is_empty() and st.begins_with("title") and st.contains(":"):
			cur["title"] = st.substr(st.find(":") + 1).strip_edges()
	return res


# ---------------------------------------------------------------- converting other formats with ffmpeg

func _find_ffmpeg() -> String:
	if _ffmpeg != "":
		return _ffmpeg
	var candidates: Array[String] = [
		ProjectSettings.globalize_path("res://tools/ffmpeg.exe"),
		ProjectSettings.globalize_path("res://tools/ffmpeg"),
		"ffmpeg", "ffmpeg.exe",
		_src.get_base_dir().path_join("ffmpeg.exe"),             # next to the video you picked
		OS.get_environment("USERPROFILE").path_join("Videos/ffmpeg.exe"),
		OS.get_environment("USERPROFILE").path_join("Downloads/ffmpeg.exe"),
		OS.get_environment("USERPROFILE").path_join("Desktop/ffmpeg.exe"),
		OS.get_environment("LOCALAPPDATA").path_join("Microsoft/WinGet/Links/ffmpeg.exe"),
		OS.get_environment("USERPROFILE").path_join("scoop/shims/ffmpeg.exe"),
		"C:/ProgramData/chocolatey/bin/ffmpeg.exe",
		"C:/ffmpeg/bin/ffmpeg.exe",
		"C:/Program Files/ffmpeg/bin/ffmpeg.exe",
		"/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg",
	]
	for c in candidates:
		if (c.contains("/") or c.contains("\\")) and not FileAccess.file_exists(c):
			continue
		var out := []
		if OS.execute(c, ["-version"], out, true) == 0:
			_ffmpeg = c
			return c
	return ""


func _fail_tape(msg: String) -> void:
	has_tape = false
	_tape.visible = false
	state = State.IDLE
	_return_state = State.IDLE
	_show_status(msg)


func _convert_and_play(src: String) -> void:
	var ff := _find_ffmpeg()
	if ff == "":
		_fail_tape("This video needs ffmpeg to convert it to .ogv, and ffmpeg wasn't found.\nPut ffmpeg.exe in the project's tools folder,\nor install ffmpeg and restart. (.ogv files play without it)")
		return
	_tracks = _probe(src, ff)
	_start_convert()


func _start_convert() -> void:
	var ff := _find_ffmpeg()
	var cache := ProjectSettings.globalize_path("user://vcr_cache")
	DirAccess.make_dir_recursive_absolute(cache)
	var key := (_src + str(FileAccess.get_modified_time(_src))).md5_text()
	if _audio_sel < 0 and _offset < 0.5:
		_final_out = cache.path_join(key + ".ogv")          # the normal, cached full conversion
		_temp_file = ""
	else:
		_final_out = cache.path_join("%s_a%d_s%d.ogv" % [key, _audio_sel, int(_offset)])
		_temp_file = _final_out if _offset >= 0.5 else ""
	if FileAccess.file_exists(_final_out):
		_start_video(_final_out)
		return
	_progress_path = cache.path_join(key + ".progress")
	_tmp_out = _final_out + ".part"
	var args := PackedStringArray(["-y", "-nostdin", "-loglevel", "error"])
	if _offset >= 0.5:
		args.append_array(["-ss", "%.3f" % _offset])
	args.append_array(["-i", _src])
	if _audio_sel >= 0:
		args.append_array(["-map", "0:v:0", "-map", "0:a:%d" % _audio_sel])
	args.append_array([
		"-vf", "scale='min(640,iw)':-2",
		"-c:v", "libtheora", "-q:v", "6", "-c:a", "libvorbis", "-q:a", "4",
		"-f", "ogg", "-progress", _progress_path, _tmp_out,
	])
	_pid = OS.create_process(ff, args)
	if _pid <= 0:
		_fail_tape("Couldn't start ffmpeg.")
		return
	state = State.LOADING
	_return_state = State.LOADING
	_poll_t = 0.0
	_show_status("RECORDING TAPE...\nconverting with ffmpeg (EJECT cancels)")


func _cleanup_temp() -> void:
	if _temp_file != "" and FileAccess.file_exists(_temp_file):
		DirAccess.remove_absolute(_temp_file)
	_temp_file = ""


func _cancel_conversion() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	_remux = false
	_cleanup_temp()
	has_tape = false
	_tape.visible = false
	_src = ""
	_offset = 0.0
	_audio_sel = -1
	_clear_subs()
	state = State.IDLE
	_return_state = State.IDLE
	_show_idle_status()


func _poll_conversion() -> void:
	if OS.is_process_running(_pid):
		var f := FileAccess.open(_progress_path, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			var i := txt.rfind("out_time=")
			if i >= 0:
				var j := txt.find("\n", i)
				var t := txt.substr(i + 9, (j if j > 0 else txt.length()) - i - 9).strip_edges().substr(0, 8)
				_show_status(("PREPARING TAPE...\nprocessed so far: %s\n(EJECT cancels)" if _remux else "RECORDING TAPE...\nconverted so far: %s\n(EJECT cancels)") % t)
		return
	_pid = -1
	var ok := false
	if FileAccess.file_exists(_tmp_out):
		var f2 := FileAccess.open(_tmp_out, FileAccess.READ)
		ok = f2 != null and f2.get_length() > 1000
	var was_remux := _remux
	_remux = false
	if ok:
		DirAccess.rename_absolute(_tmp_out, _final_out)
		if was_remux:
			_open_vlc(_final_out)
		else:
			_start_video(_final_out)
	elif was_remux:
		_open_vlc(_src)                      # the fix failed: play the original anyway
	else:
		_fail_tape("ffmpeg couldn't convert that video.\nTry a different file.")


# ---------------------------------------------------------------- per-frame

func _vlc_tick(delta: float) -> void:
	var tex: Texture2D = _vlc.get_texture()
	if tex != null and tex.get_width() > 8:
		var sz := Vector2i(tex.get_width(), tex.get_height())
		if tex != _last_tex or sz != _last_size:
			_last_tex = tex
			_last_size = sz
			_mat.set_shader_parameter("video_tex", tex)
			_mat.set_shader_parameter("video_aspect", _vlc_aspect(sz.x, sz.y))
		if _waiting_tex:
			_mat.set_shader_parameter("use_video", state == State.PLAYING)
			_waiting_tex = false
	_diag_t -= delta
	if _diag_t <= 0.0 and state == State.PLAYING:
		_diag_t = 5.0
		var line := _vlc_stats_text()
		if line != _diag_last:
			_diag_last = line
			print("[VCR] ", line)
	if state == State.PLAYING and not _paused_flag:
		var st := int(_vlc.get_state())
		if st == 3:
			_vlc_seen = true
		elif st == 7 or (not _vlc_seen and _vlc_t > 20.0):
			_p_stop()
			_set_video(false)
			_fail_tape("VLC couldn't play that file.")
		elif _vlc_seen and (st == 5 or st == 0):
			_on_finished()
		if not _vlc_seen:
			_vlc_t += delta


func _process(delta: float) -> void:
	# CRT power animation
	var target := 1.0 if tv_on else 0.0
	if not is_equal_approx(_power_t, target):
		_power_t = move_toward(_power_t, target, delta / 0.35)
		_mat.set_shader_parameter("tv_power", _power_t)
	_ui.set_cursor_allowed(not (state == State.PLAYING and tv_on))

	if _osd.visible and _osd_t < 1.0e5:
		_osd_t -= delta
		if _osd_t <= 0.0:
			_osd.visible = false
	if _use_vlc and _vlc != null and state != State.IDLE:
		_vlc_tick(delta)
	if _waiting_tex and not _use_vlc:
		var tex := _player.get_video_texture()
		if tex != null and tex.get_width() > 8:
			_mat.set_shader_parameter("video_tex", tex)
			_mat.set_shader_parameter("video_aspect", float(tex.get_width()) / float(tex.get_height()))
			_mat.set_shader_parameter("use_video", state == State.PLAYING)
			_waiting_tex = false
	if state == State.LOADING:
		_poll_t -= delta
		if _poll_t <= 0.0:
			_poll_t = 0.5
			_poll_conversion()
	if _sub_pid > 0:
		_sub_poll -= delta
		if _sub_poll <= 0.0:
			_sub_poll = 0.4
			_poll_subs()
	_update_subtitles()

	var blink := floori(Time.get_ticks_msec() / 500.0) % 2 == 0
	match state:
		State.IDLE:
			_display.text = "12:00" if blink else "     "
		State.MENU:
			_display.text = "----"
		State.LOADING:
			_display.text = "REC" if blink else "   "
		State.PLAYING:
			var pos := _now()
			_display.text = "%d:%02d:%02d" % [floori(pos / 3600.0), floori(pos / 60.0) % 60, int(pos) % 60]
			if _tv_paused:
				_display.text = "PAUSE" if blink else "     "
			elif _osd.visible and _osd_clock:
				_osd.text = "PLAY  " + _display.text
		State.PAUSED:
			_display.text = "PAUSE" if blink else "     "
		State.STOPPED:
			_display.text = "STOP"
