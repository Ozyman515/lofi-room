extends Node
const Plat := preload("res://platform.gd")
const Diary := preload("res://diary.gd")
## Plays NES and SNES games on the room's TV.
##
## The emulator itself runs in a small separate program (bin/retro_host.exe on Windows) that loads a libretro core from
## cores/. This script starts it, talks to it over a loopback socket, shows its picture on the TV, plays its sound and
## draws the game menu. Games live in carts/<system>/roms and the battery saves in carts/<system>/saves.

signal screen_changed(tex: Texture2D)
signal frame_out(img: Image)                    # host: every new picture (for guests)
signal audio_out(pcm: PackedByteArray, count: int)   # host: float stereo pairs (for guests)
signal buttons_out(mask: int)                   # guest: the pad state to send to the host

enum State { IDLE, MENU, STARTING, RUNNING, ERROR }

const NEO_BIOS := ["neogeo.zip", "aes.zip", "neocdz.zip", "neocd.zip", "irrmaze.zip"]   # system files, not games
const SYSTEMS := {
	"nes": {"title": "NES", "core": "fceumm_libretro", "ext": ["nes", "fds", "unf", "unif"]},
	"snes": {"title": "SNES", "core": "snes9x2010_libretro", "ext": ["sfc", "smc", "swc", "fig"]},
	"sgb": {"title": "SGB", "core": "mgba_libretro", "ext": ["gb", "gbc", "gba", "sgb"]},
	"neo": {"title": "NEO GEO", "core": "fbneo_neogeo_libretro", "ext": ["zip", "7z"]},
	"gen": {"title": "GENESIS", "core": "genesis_plus_gx_libretro", "ext": ["md", "gen", "smd", "bin", "sms", "gg", "sg"]},
	"ps": {"title": "PLAYSTATION", "core": "pcsx_rearmed_libretro", "ext": ["cue", "chd", "pbp", "m3u", "bin", "iso", "img", "exe"]},
}
# libretro joypad bits
const B_B := 1 << 0
const B_Y := 1 << 1
const B_SELECT := 1 << 2
const B_START := 1 << 3
const B_UP := 1 << 4
const B_DOWN := 1 << 5
const B_LEFT := 1 << 6
const B_RIGHT := 1 << 7
const B_A := 1 << 8
const B_X := 1 << 9
const B_L := 1 << 10
const B_R := 1 << 11

const ROWS := 9

var state := State.IDLE
var system := ""
var powered := false            # console on and the TV showing it
var pad_held := false
var volume := 1.0               # 0..1, the TV volume
var tex: Texture2D              # what the TV should show
var base := ""

var _vp: SubViewport
var _title: Label
var _lines: Array[Label] = []
var _foot: Label
var _roms: Array = []
var _sel := 0
var _top := 0
var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _pid := -1
var _rx := PackedByteArray()
var _fps := 60.0
var _rate := 44100.0
var _speed := 100
var _cap := 1
var _img_tex: ImageTexture
var _audio: AudioStreamPlayer
var _gen: AudioStreamGenerator
var _pb: AudioStreamGeneratorPlayback
var _prev_mask := 0
var _sent_mask := -1
var streaming := false              # host with guests: publish picture and sound
var remote := false                 # guest: the game runs on the host, we only show its picture and sound
var local_port := 0                 # which libretro port the pad in your hand drives: 0 = player 1 (left), 1 = player 2 (right)
var _remote_mask := 0               # the other player's buttons (a guest in the room), on the other port
var _rep_t := 0.0
var _combo_t := 0.0
var resume_games := true         # keep the place in each game (set from the Settings window)
var _t_start := 0
var _err_text := ""
var _err_cd := 0.0
var _game_name := ""
var frames_done := 0
var custom_active := false      # the room is drawing its own screen (the controls screen) over the menu
var _ctop := 0


func _ready() -> void:
	base = _find_base()
	_ensure_dirs()
	_build_ui()
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	tex = _vp.get_texture()
	set_process(true)


func _exit_tree() -> void:
	_stop_host()


func _find_base() -> String:
	var res := ProjectSettings.globalize_path("res://")
	if DirAccess.dir_exists_absolute(res.path_join("bin")):
		return res
	return OS.get_executable_path().get_base_dir()


func carts_dir() -> String:
	return base.path_join("carts")


func _ensure_dirs() -> void:
	for s in SYSTEMS:
		DirAccess.make_dir_recursive_absolute(carts_dir().path_join(s).path_join("roms"))
		DirAccess.make_dir_recursive_absolute(carts_dir().path_join(s).path_join("saves"))
	var readme := carts_dir().path_join("README.txt")
	if not FileAccess.file_exists(readme):
		var f := FileAccess.open(readme, FileAccess.WRITE)
		if f != null:
			f.store_string("Game carts\n==========\n\nPut your own game files here, one folder per console:\n\n  nes/roms     .nes files\n  snes/roms    .sfc or .smc files (not zipped)\n  sgb/roms     .gb, .gbc or .gba files (Game Boy, Game Boy Color and Game Boy Advance)\n  gen/roms     .md, .gen or .smd files (Sega Genesis / Mega Drive), also .sms (Master System) and .gg (Game Gear)\n  neo/roms     Neo Geo games as .zip (for example mslug3.zip) AND the BIOS file neogeo.zip in the same folder (arcade cabinet)\n  ps/roms      PlayStation discs: .cue (with its .bin tracks next to it), .chd or .pbp (the disc console; a real BIOS file such as scph5501.bin in the cores folder is optional)\n\nBattery saves are written to the saves folder next to roms.\nIn the room: put a cart in the console, switch it on, pick up a controller from the rug and choose a game.\nHold START + SELECT for a second to go back to the game list.\nIf something does not start, look at emulator.log in this folder.\n")


# ---------------------------------------------------------------- the text screen (menu, messages)

func _build_ui() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(320, 240)
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.16)
	bg.size = Vector2(320, 240)
	_vp.add_child(bg)
	var frame := ColorRect.new()
	frame.color = Color(0.20, 0.70, 0.80)
	frame.position = Vector2(8, 34)
	frame.size = Vector2(304, 2)
	_vp.add_child(frame)
	_title = _label(Vector2(14, 8), 20, Color(1.0, 0.85, 0.3))
	for i in ROWS:
		_lines.append(_label(Vector2(18, 42 + i * 18), 14, Color(0.9, 0.95, 1.0)))
	_foot = _label(Vector2(14, 214), 11, Color(0.95, 0.5, 0.75))


func _label(pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(300, size + 6)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	l.clip_text = true
	_vp.add_child(l)
	return l


# A list screen drawn by the room (the controls screen). `sel` is the highlighted row; the list scrolls by itself.
func show_custom(title: String, lines: Array, sel: int, foot: String) -> void:
	custom_active = true
	if sel < _ctop:
		_ctop = sel
	elif sel >= _ctop + ROWS:
		_ctop = sel - ROWS + 1
	_ctop = clampi(_ctop, 0, maxi(lines.size() - ROWS, 0))
	_show_text(title, lines.slice(_ctop, _ctop + ROWS), foot, sel - _ctop)


func end_custom() -> void:
	custom_active = false
	_ctop = 0
	_refresh_screen()


func _show_text(title: String, lines: Array, foot: String, sel: int = -1) -> void:
	_title.text = title
	for i in ROWS:
		var l := _lines[i]
		if i < lines.size():
			l.text = ("> " if i == sel else "  ") + str(lines[i])
			l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3) if i == sel else Color(0.9, 0.95, 1.0))
		else:
			l.text = ""
	_foot.text = foot
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_set_tex(_vp.get_texture())


func _set_tex(t: Texture2D) -> void:
	if t != tex:
		tex = t
		screen_changed.emit(tex)


func _refresh_screen() -> void:
	if custom_active:
		return
	match state:
		State.IDLE:
			if system == "":
				_show_text("NO CART", ["", "  Put a game cart in the console."], "SELECT  CONTROLS" if pad_held else "")
			elif remote:
				_show_text(SYSTEMS[system]["title"], ["", "  WAITING FOR THE HOST", "  TO PICK A GAME"], "")
			else:
				_show_text(SYSTEMS[system]["title"], [], "")
		State.MENU:
			_draw_menu()
		State.STARTING:
			_show_text(SYSTEMS[system]["title"], ["", "  LOADING..."], _game_name)
		State.ERROR:
			var ls: Array = ["", "  COULD NOT PLAY THIS GAME", ""]
			for part in _err_text.split("\n"):
				ls.append("  " + part)
			_show_text("ERROR", ls, "PRESS A TO GO BACK")


func _draw_menu() -> void:
	var title: String = SYSTEMS[system]["title"] + "  GAMES"
	var foot := "UP/DOWN CHOOSE    A PLAY    SELECT CONTROLS" if pad_held else ("USE THE LEFT OR RIGHT PLAYER PANEL" if system == "neo" else "PICK UP A CONTROLLER FROM THE RUG")
	if _roms.is_empty():
		_show_text(title, ["", "  NO GAMES FOUND", "", "  Put your game files in the folder", "  carts/%s/roms" % system, "  next to the game, then put the cart", "  back in the console."], foot)
		return
	var shown: Array = []
	var last := mini(_roms.size(), _top + ROWS)
	for i in range(_top, last):
		shown.append(_pretty(_roms[i]))
	_show_text(title, shown, foot, _sel - _top)


func _pretty(file: String) -> String:
	var n := file.get_basename().replace("_", " ")
	if n.length() > 34:
		n = n.substr(0, 33) + "~"
	return n


func _scan_roms() -> void:
	_roms.clear()
	var dir := carts_dir().path_join(system).path_join("roms")
	var exts: Array = SYSTEMS[system]["ext"]
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in exts and not (system == "neo" and f.to_lower() in NEO_BIOS):
			if system == "ps" and f.get_extension().to_lower() == "bin" and not _lone_bin(dir, f):
				continue                                    # (the tracks of a game with a .cue: the .cue is the game)
			_roms.append(f)
	_roms.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	_sel = clampi(_sel, 0, maxi(_roms.size() - 1, 0))
	_top = clampi(_top, 0, maxi(_roms.size() - ROWS, 0))


# a PlayStation .bin with no .cue naming it (a single-track disc image you can load as it is)
func _lone_bin(dir: String, bin: String) -> bool:
	for f in DirAccess.get_files_at(dir):
		var e := f.get_extension().to_lower()
		if e == "cue" or e == "m3u":
			var txt := FileAccess.get_file_as_string(dir.path_join(f))
			if txt.findn(bin) >= 0 or f.get_basename() == bin.get_basename():
				return false
	return true


# ---------------------------------------------------------------- called by the room

# "" = no cart, "nes", "snes", "sgb", "gen", "neo". Anything else (the secret cart) is not ours.
func set_system(sys: String) -> void:
	if sys == system:
		return
	_stop_host()
	system = sys if SYSTEMS.has(sys) else ""
	_enter_idle_or_menu()


func set_power(on: bool) -> void:
	if on == powered:
		return
	powered = on
	if on:
		if state != State.RUNNING and state != State.STARTING:
			_enter_idle_or_menu()
	else:
		# pausing: keep the game in memory but run nothing (the sound just runs dry)
		if state == State.RUNNING:
			_flush_save()
	if state == State.RUNNING and _peer != null:
		_peer.put_data(PackedByteArray([80, 0 if on else 1]))      # 'P': the emulator program pauses itself


func set_pad(held: bool) -> void:
	if held == pad_held:
		return
	pad_held = held
	if not held:
		_prev_mask = 0
		_send_buttons(0)
	if state == State.MENU:
		_refresh_screen()


# which bus the game's sound goes out on: "Arcade" (the cabinet's grill) or "Console" (the TV, or the speakers set to TV)
func set_bus(b: String) -> void:
	if _audio != null and _audio.bus != b and AudioServer.get_bus_index(b) >= 0:
		_audio.bus = b


func set_volume(v: float) -> void:
	volume = v
	if _audio != null:
		_audio.volume_db = -80.0 if v <= 0.01 else linear_to_db(v)


func is_running() -> bool:
	return state == State.RUNNING


# back to the game list (the same as holding START + SELECT); the game saves its place first
func to_menu() -> void:
	if remote:
		return                      # a guest can't change the host's game
	if state == State.RUNNING or state == State.STARTING or state == State.ERROR:
		_stop_host()
		_enter_idle_or_menu()


func uses_texture() -> bool:
	return system != ""


func _enter_idle_or_menu() -> void:
	if system == "" or remote:
		state = State.IDLE
	else:
		_scan_roms()
		state = State.MENU
	_refresh_screen()


# the pad state as libretro bits; call every frame while the controller is held
func set_buttons(mask: int) -> void:
	var pressed := mask & ~_prev_mask
	_prev_mask = mask
	match state:
		State.MENU:
			if pad_held and powered:
				_menu_press(pressed)
				if mask & (B_UP | B_DOWN) == 0:
					_rep_t = 0.0
		State.ERROR:
			if pressed & (B_A | B_START | B_B) and _err_cd <= 0.0:
				_enter_idle_or_menu()
		State.RUNNING:
			if remote:
				buttons_out.emit(mask)
			else:
				_send_buttons(mask)


func _menu_press(pressed: int) -> void:
	if _roms.is_empty():
		return
	var moved := false
	if pressed & B_UP:
		_sel = (_sel - 1 + _roms.size()) % _roms.size()
		moved = true
		_rep_t = -0.35
	elif pressed & B_DOWN:
		_sel = (_sel + 1) % _roms.size()
		moved = true
		_rep_t = -0.35
	if moved:
		if _sel < _top:
			_top = _sel
		elif _sel >= _top + ROWS:
			_top = _sel - ROWS + 1
		_draw_menu()
	if pressed & (B_A | B_START):
		_launch(_roms[_sel])


# ---------------------------------------------------------------- the emulator program

func _launch(rom_file: String) -> void:
	if not Plat.can_spawn_programs():
		return _fail("Game consoles can't run on this headset yet.\nThey work in the PC version of the room.")
	var win := OS.get_name() == "Windows"
	var host := base.path_join("bin").path_join("retro_host.exe" if win else "retro_host_linux")
	var core := base.path_join("cores").path_join(SYSTEMS[system]["core"] + (".dll" if win else ".so"))
	var rom := carts_dir().path_join(system).path_join("roms").path_join(rom_file)
	var saves := carts_dir().path_join(system).path_join("saves")
	_game_name = _pretty(rom_file)
	if not FileAccess.file_exists(host):
		return _fail("The emulator program is missing:\nbin/" + host.get_file())
	if not FileAccess.file_exists(core):
		return _fail("The emulator core is missing:\ncores/" + core.get_file())
	if not FileAccess.file_exists(rom):
		return _fail("The game file is gone.")
	if not win:
		OS.execute("chmod", ["+x", host])
	var port := 0
	for i in 60:
		var p := 47000 + randi() % 3000
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	if port == 0:
		return _fail("Could not open a local port.")
	var state_path := saves.path_join(rom_file + ".state") if resume_games else ""
	if win and system == "neo":
		rom = rom.replace("/", "\\")          # FBNeo finds the game folder by looking for a backslash on Windows
	_pid = OS.create_process(host, [str(port), core, rom, saves, base.path_join("cores"), carts_dir().path_join("emulator.log"), state_path, "1" if resume_games else "0"])
	if _pid <= 0:
		_server.stop()
		return _fail("Could not start the emulator program.")
	_rx.clear()
	_speed = 100
	_sent_mask = -1
	_combo_t = 0.0
	_t_start = Time.get_ticks_msec()
	state = State.STARTING
	_refresh_screen()


func _fail(text: String) -> void:
	_stop_host()
	_err_text = text
	_err_cd = 1.0
	state = State.ERROR
	_refresh_screen()


func _flush_save() -> void:
	if _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_peer.put_data(PackedByteArray([83]))
		_peer.put_data(PackedByteArray([84]))          # 'T': also remember exactly where the game is


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_host()                                    # closing the room: the game saves its place first


func _stop_host() -> void:
	if state == State.RUNNING:
		Diary.game_stopped()
	if _peer != null:
		if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_peer.put_data(PackedByteArray([81]))      # 'Q': save and quit
		_peer.disconnect_from_host()
		_peer = null
	_server.stop()
	if _pid > 0:
		var pid := _pid
		get_tree().create_timer(2.0).timeout.connect(func():
			if OS.is_process_running(pid):
				OS.kill(pid))
		_pid = -1
	_audio.stop()
	_pb = null
	_img_tex = null
	if state == State.RUNNING or state == State.STARTING:
		state = State.IDLE


func _send_buttons(mask: int) -> void:
	var key := mask | (_remote_mask << 16) | (local_port << 32)
	if state != State.RUNNING or _peer == null or key == _sent_mask:
		return
	_sent_mask = key
	var p := [0, 0]
	p[local_port] = mask
	p[1 - local_port] = _remote_mask
	var b := PackedByteArray([66, p[0] & 255, (p[0] >> 8) & 255, p[1] & 255, (p[1] >> 8) & 255])
	_peer.put_data(b)


# the buttons of the second person (a guest): they drive the port you are not using
func set_remote_buttons(mask: int) -> void:
	if mask == _remote_mask:
		return
	_remote_mask = mask
	_send_buttons(_prev_mask if pad_held else 0)


func _process(delta: float) -> void:
	if _err_cd > 0.0:
		_err_cd -= delta
	# menu auto repeat
	if state == State.MENU and pad_held and powered and not _roms.is_empty():
		if _prev_mask & (B_UP | B_DOWN):
			_rep_t += delta
			if _rep_t >= 0.09:
				_rep_t = 0.0
				_menu_press(_prev_mask & (B_UP | B_DOWN))
	if state == State.STARTING:
		_process_starting()
	elif state == State.RUNNING:
		_process_running(delta)


func _process_starting() -> void:
	if _peer == null and _server.is_listening() and _server.is_connection_available():
		_peer = _server.take_connection()
		_peer.set_no_delay(true)
	if _peer != null:
		_peer.poll()
		_read()
		_parse()
		return
	if Time.get_ticks_msec() - _t_start > 1500 and _pid > 0 and not OS.is_process_running(_pid):
		_fail("The emulator program stopped at once.\nSee carts/emulator.log")
	elif Time.get_ticks_msec() - _t_start > 12000:
		_fail("The emulator program did not answer.\nSee carts/emulator.log")


func _process_running(delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_fail("The emulator program closed.\nSee carts/emulator.log")
		return
	_read()
	_parse()
	if state != State.RUNNING:
		return
	# hold START + SELECT: back to the game list
	if pad_held and (_prev_mask & (B_START | B_SELECT)) == (B_START | B_SELECT):
		_combo_t += delta
		if _combo_t > 0.7:
			_combo_t = 0.0
			_stop_host()
			_enter_idle_or_menu()
			return
	else:
		_combo_t = 0.0
	if not powered:
		return
	# the emulator program runs by itself at the game's speed; we only nudge it by 1 % to keep a small sound cushion
	if _pb != null and _gen != null:
		var buffered := float(_cap - _pb.get_frames_available()) / _rate
		var want := _speed
		if _speed == 100 and buffered < 0.05:
			want = 101
		elif _speed == 101 and buffered > 0.10:
			want = 100
		elif _speed == 100 and buffered > 0.22:
			want = 99
		elif _speed == 99 and buffered < 0.14:
			want = 100
		elif _speed >= 99 and buffered > 0.30:
			want = 98                          # only just after starting: drain the first rush of sound quickly
		elif _speed == 98 and buffered < 0.20:
			want = 99
		if want != _speed:
			_speed = want
			_peer.put_data(PackedByteArray([77, _speed]))


func _read() -> void:
	var n := _peer.get_available_bytes()
	if n > 0:
		var r := _peer.get_data(n)
		if r[0] == OK:
			_rx.append_array(r[1] as PackedByteArray)


func _parse() -> void:
	var p := 0
	var n := _rx.size()
	var vid_w := 0
	var vid_h := 0
	var vid_at := -1
	while p < n:
		var t := _rx[p]
		if t == 75:                               # 'K' one frame finished
			if n - p < 5: break
			frames_done += 1
			p += 5
		elif t == 86:                             # 'V' picture
			if n - p < 9: break
			var w := _rx.decode_u32(p + 1)
			var h := _rx.decode_u32(p + 5)
			var bytes := w * h * 4
			if w == 0 or h == 0 or w > 2048 or h > 2048:
				p = n
				break
			if n - p < 9 + bytes: break
			vid_w = w
			vid_h = h
			vid_at = p + 9
			p += 9 + bytes
		elif t == 65:                             # 'A' sound
			if n - p < 5: break
			var cnt := _rx.decode_u32(p + 1)
			if cnt > 100000:
				p = n
				break
			if n - p < 5 + cnt * 8: break
			_push_audio(p + 5, cnt)
			p += 5 + cnt * 8
		elif t == 72:                             # 'H' the game is running
			if n - p < 25: break
			_fps = clampf(_rx.decode_double(p + 1), 20.0, 120.0)
			_rate = clampf(_rx.decode_double(p + 9), 8000.0, 192000.0)       # the Game Boy core plays at 131072 Hz
			p += 25
			_on_hello()
		elif t == 69:                             # 'E' error
			if n - p < 2: break
			var len := _rx[p + 1]
			if n - p < 2 + len: break
			var msg := _rx.slice(p + 2, p + 2 + len).get_string_from_utf8()
			p += 2 + len
			_rx = _rx.slice(p)
			_fail(msg.capitalize() if msg.length() < 3 else msg.substr(0, 1).to_upper() + msg.substr(1) + ".")
			return
		else:
			p = n
			break
	if vid_at >= 0:
		var img := Image.create_from_data(vid_w, vid_h, false, Image.FORMAT_RGBA8, _rx.slice(vid_at, vid_at + vid_w * vid_h * 4))
		if _img_tex == null or _img_tex.get_width() != vid_w or _img_tex.get_height() != vid_h:
			_img_tex = ImageTexture.create_from_image(img)
		else:
			_img_tex.update(img)
		_set_tex(_img_tex)
		if streaming:
			frame_out.emit(img)
		_peer.put_data(PackedByteArray([68]))      # 'D': picture shown, the program may send the next one
	if p > 0:
		_rx = _rx.slice(p) if p < n else PackedByteArray()


func _on_hello() -> void:
	state = State.RUNNING
	Diary.game_started(system, _game_name)
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = _rate
	_gen.buffer_length = 0.5
	_audio.stream = _gen
	set_volume(volume)
	_audio.play()
	_pb = _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	_cap = maxi(_pb.get_frames_available(), 1)          # the buffer's real size (Godot rounds it up)
	_sent_mask = -1
	if not powered:
		_peer.put_data(PackedByteArray([80, 1]))
	if pad_held:
		_send_buttons(_prev_mask)
	_set_tex(tex)


func _push_audio(at: int, cnt: int) -> void:
	if streaming:
		audio_out.emit(_rx.slice(at, at + cnt * 8), cnt)
	if _pb == null or not powered:
		return
	if _pb.get_frames_available() < cnt:
		return
	# the program sends float pairs; wrapping them in the header of a PackedVector2Array lets Godot convert in one native call
	var head := PackedByteArray([35, 0, 0, 0, 0, 0, 0, 0])
	head.encode_u32(4, cnt)
	var arr: PackedVector2Array = bytes_to_var(head + _rx.slice(at, at + cnt * 8))
	_pb.push_buffer(arr)


# ---------------------------------------------------------------- guest side: show the host's game

func remote_frame(img: Image) -> void:
	if not remote or img == null or img.get_width() == 0:
		return
	if state != State.RUNNING:
		state = State.RUNNING
	if _img_tex == null or _img_tex.get_width() != img.get_width() or _img_tex.get_height() != img.get_height():
		_img_tex = ImageTexture.create_from_image(img)
	else:
		_img_tex.update(img)
	_set_tex(_img_tex)


func remote_audio(pcm: PackedByteArray, rate: float, count: int) -> void:
	if not remote or not powered or count <= 0 or pcm.size() < count * 4:
		return
	if _gen == null or absf(_gen.mix_rate - rate) > 1.0:
		_gen = AudioStreamGenerator.new()
		_gen.mix_rate = rate
		_gen.buffer_length = 0.5
		_audio.stream = _gen
		set_volume(volume)
		_audio.play()
		_pb = _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if _pb == null or _pb.get_frames_available() < count:
		return
	var arr := PackedVector2Array()
	arr.resize(count)
	for i in count:
		arr[i] = Vector2(pcm.decode_s16(i * 4), pcm.decode_s16(i * 4 + 2)) / 32768.0
	_pb.push_buffer(arr)


# the host stopped the game (or went back to the list)
func remote_stopped() -> void:
	if remote and state == State.RUNNING:
		state = State.IDLE
		if _audio != null:
			_audio.stop()
		_pb = null
		_gen = null
		_img_tex = null
		_refresh_screen()


func set_remote_mode(on: bool) -> void:
	if remote == on:
		return
	remote = on
	_stop_host()
	_enter_idle_or_menu()
