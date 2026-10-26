extends Node3D

const GifPlayer := preload("res://gif_player.gd")
const ScreenUI := preload("res://screen_ui.gd")
const PCPlayer := preload("res://pc_player.gd")
const VCR := preload("res://vcr.gd")
const SpeakerBank := preload("res://speaker_bank.gd")
const Weather := preload("res://weather.gd")
const TornadoEvent := preload("res://tornado_event.gd")
const Updater := preload("res://updater.gd")
var updater: Node
const Emu := preload("res://emu.gd")
const Reticle := preload("res://reticle.gd")
const Plat := preload("res://platform.gd")
const PadMap := preload("res://padmap.gd")
const SETTINGS_FILE := "user://lofi_room.cfg"
const RETICLE_COLORS := [["Pink", Color(1.0, 0.35, 0.65)], ["Cyan", Color(0.20, 0.85, 0.90)], ["Amber", Color(1.0, 0.70, 0.30)], ["Lavender", Color(0.72, 0.58, 1.0)], ["White", Color(1.0, 0.95, 1.0)]]
signal settings_changed
## Lofi bedroom for Steam Frame. The whole room is built in code from simple shapes.

const USE_GLOW := true       # bloom on lamps and window; turn off if the headset struggles
const MOVE_SPEED := 1.6      # metres per second
const RUN_SPEED := 3.4       # holding Shift / clicking the left stick in: for getting round the apartment
const SNAP_ANGLE := 30.0     # degrees per snap turn
const DEADZONE := 0.2
const SEAT_EYE_HEIGHT := 1.18   # eye height (m) while sitting
const SIT_RANGE := 1.1          # how close you must be to the chair to sit
const TV_WIDTH := 1.44          # CRT width in metres (80% of the 1.8 m lounge rug)
const FRONT_Z := 3.4            # z of the front wall (the one with the door)
const LOUNGE_DZ := 1.2          # the TV set's own coordinates (kept from when it stood along the left wall)
const LOUNGE_YAW := PI / 4.0    # the whole TV set is turned by this into the front-left corner
const TV_CORNER_GAP := 0.03     # how close the TV's back corners come to the two walls
const WIN_X0 := -3.75            # window: left edge, right edge, sill height, top
const WIN_X1 := 1.05
const WIN_Y0 := 0.5
const WIN_Y1 := 2.7
const POINTER_RANGE := 4.0       # how far the VR laser / desktop crosshair reaches
const FAR_RANGE := 9.0           # ...for the few things that say they reach further (the theater's speakers, from the seats)
const RUG_WIDTH := 1.8          # lounge rug width along the wall
const BED_ASSET := "res://assets/bed.glb"   # drop a bed model here and it replaces the built-in bed
const BED_EXTRA_YAW := 0.0      # rotate the bed asset in 90 degree steps if it faces the wrong way
const ROOM_HALF := Vector2(2.2, 1.75)   # right limit in x, and +-z limit
const ROOM_X_MIN := -3.6                 # left limit in x (room is wider on the left now)
const LOUNGE_BLOCKERS := [
	Rect2(-4.0, 0.1 + LOUNGE_DZ, 1.2, 1.7),     # CRT TV
	Rect2(-2.75, 1.15 + LOUNGE_DZ, 0.4, 0.55),  # game console (on the door side of the TV)
]
var _blockers_extra: Array[Rect2] = []    # bedroom furniture added after BLOCKERS was written
const ARCADE_BLOCK := Rect2(1.4, 1.55, 1.2, 0.8)     # the arcade cabinet, in its kit's coordinates
const STUDY_BLOCKS := [Rect2(0.4, -2.1, 2.2, 1.05), Rect2(2.0, -0.65, 0.6, 1.9)]   # the desk and the bookshelf, in the study kit's
const BLOCKERS := [
	Rect2(-2.15, -2.1, 1.95, 2.4),  # bed (and the nightstand)
	Rect2(-4.0, -0.45, 0.75, 1.2),  # dresser (moved toward the TV corner)
]

const WARM := Color(1.0, 0.62, 0.30)
const PINK := Color(1.0, 0.35, 0.65)

var room: Node3D
var origin: XROrigin3D
var head: Node3D
var left_hand: XRController3D
var right_hand: XRController3D
var desktop_cam: Camera3D
var xr_active := false
var snap_ready := true
var pitch := 0.0
var chair: Node3D
var seat_nodes: Array[Node3D] = []
var seat_eye: Array[float] = []
var seat_swivel: Array[bool] = []
var cur_seat := -1
var tv_root: Node3D
var tv_rating: Node3D             # thumbs up / down on the TV
var lounge: Node3D                    # TV, console, controllers and carts live here (built in old wall coordinates, then turned into the corner)
var console_root: Node3D
var console_on := false
var cab_root: Node3D                  # the standing arcade cabinet on the left wall
var arcade_mat: ShaderMaterial
var arcade_light: OmniLight3D
var arcade_on := true                  # the power switch on the cabinet's side
var arcade_marquee_m: StandardMaterial3D
var arcade_marquee_label: Label3D
var poster: Node3D                     # poster.gd: the picture on the right wall
var noir: Node3D                       # noir.gd: Noir Night (an easter egg)
var ufo: Node3D                        # ufo.gd: a saucer stops at the window and an alien looks in (an easter egg)
var kaiju: Node3D                      # kaiju.gd: a giant monster walks past the window (an easter egg)
var gaboon: Node3D                     # gaboon.gd: King Gaboon, the owner's giant ape, walks past and roars (figure on the bookshelf)
var fight: Node3D                      # fight.gd: the T-Rex and King Gaboon fight out past the rooftops, helicopters circling
var keyboard_node: Node3D              # the desk's keyboard and mug (Noir Night swaps in a typewriter and a whiskey)
var mug_node: Node3D
var cats: Node3D                       # cats.gd: the tuxedo (shake the treats) and the calico (drops by now and then)
var share_poster := false              # host: guests see my poster (off: they see the room's own posters)
var arcade_glow: Array = []            # [material, lit energy]: the buttons and coin lights, dark while the power is off
var arcade_volume := 7                 # 0..10, the cabinet's own volume (the TV's buttons set the console's)
var arcade_vol_label: Label3D
var emu: Node                         # NES / SNES games (emu.gd)
var slot_cart := ""                   # the cart in the console: "", "nes", "snes", "sgb", "gen", "neo" or "egg" (the secret one)
var carts: Dictionary = {}            # id -> {node, name, home (Callable returning a Transform3D), busy}
var drawer_node: Node3D               # the nightstand drawer
var drawer_open := false
var drawer_busy := false
var leave_prompt := false             # the "Leave the room?" sign at the door is showing
var leave_t := 0.0
var leave_panel: Node3D
var game_mode := false                # holding a controller: it drives the game and you cannot walk
var pad_nodes: Array[Node3D] = []     # the controllers lying on the rug
var held_pad_idx := -1
var outside: Node3D                      # the city, the monsters, the saucers (not part of any room)
var apartment: Node3D                    # apartment.gd: the hallway, living room and balcony round the bedroom
var net: Node                            # NetSession (null when the WebRTC plugin isn't loaded)
var net_avatars: Node3D
var net_phone: Node3D
var net_game: Node
var net_room_tvs: Node
var net_books: Node
var net_voice: Node
var _net_toast_t := 0
var _net_moved := false
var arcade_side := 0                     # 0 = left player, 1 = right player
var held_pad: Node3D
var reticle: Control
var padmap: PadMap
var ctl_open := false                  # the controls (remap) screen is showing on the TV
var ctl_dev := "key"
var ctl_sel := 0
var ctl_listen := ""                   # the button being rebound ("" = not waiting for a press)
var ctl_listen_t := 0.0
var ctl_base := {}
var _ctl_prev := 0
var _ctl_rep := 0.0
var _ctl_block := 0.0
var _nav_prev := 0
var reticle_on := true
var reticle_color_idx := 0
var pad_hint_t := 0.0
var _pad_stick_prev := false
var egg: Node                         # the Konami-code easter egg (tornado_event.gd)
var egg_active := false               # while it plays: VCR, console, TV power, PC and curtains are locked
const KONAMI := ["U", "U", "D", "D", "L", "R", "L", "R", "B", "A"]
var konami_progress := 0
var konami_t := 0.0
var _stick_dir := ""
var console_knob: MeshInstance3D
var console_led_m: StandardMaterial3D
var tv_mat: ShaderMaterial
var crt_mats: Array[ShaderMaterial] = []   # every screen that uses the CRT shader (TV, arcade)
var crt_mode := 1                       # 0 clean picture, 1 old TV, 2 stronger CRT
const CRT_NAMES := ["CLEAN", "OLD TV", "STRONG CRT"]
var tv_screen_ui: ScreenUI
var ctrl_exits: Array[Vector3] = []
var cord_paths: Array = []
var screens: Array = []
var interactables: Array = []
var vcr: VCR
var bank: SpeakerBank
var pc: PCPlayer
var weather: Weather
var world_env: Environment
var sky_mat: ShaderMaterial
var window_light: OmniLight3D
var fill_light: OmniLight3D
var monitor_light: OmniLight3D
var monitor_on := true
var monitor_quad: MeshInstance3D
var monitor_ui: ScreenUI
var monitor_led_m: StandardMaterial3D
var curtain_node: Node3D
var curtain_target := 0.0          # what the switch / slider says: 0 = up, 1 = fully down
var curtain_last_down := false       # direction of the last move (for the stop / reverse switch)
var curtain_amt := 0.0              # 0 = open, 1 = fully down (animated)
signal lights_changed
var light_groups: Array = []        # [{name, on, omnis, mats:[{m, e, a}]}] the lamps etc. you can switch off
var lamp_shades: Array = []         # filled by _lamp(): {node, mat}
var lantern_node: MeshInstance3D
var lantern_mat: StandardMaterial3D
var fairy_mat: StandardMaterial3D
var strip_mat: StandardMaterial3D
var city_mat: ShaderMaterial
var curtain_switch_leds: Array[StandardMaterial3D] = []
var laser_l: MeshInstance3D
var laser_r: MeshInstance3D
var hint_label: Label3D
var hover_screen: ScreenUI = null
var hover_item: Dictionary = {}
var _running := false               # the faster walk, on a stick click (back to a walk when you stop)
var _run_click := false
var hover_node: Node3D = null
var hover_hand := -1
var hover_pos := Vector2.ZERO
var ptr_down := false
var down_screen: ScreenUI = null
var scroll_cd := 0.0
var focus_level := 0                 # 0 = normal, 1 = zoomed in, 2 = fills the view
var focus_screen: ScreenUI = null
var cam_from := Transform3D.IDENTITY
var cam_to := Transform3D.IDENTITY
var cam_t := 1.0
var saved_cam_local := Transform3D.IDENTITY
var saved_pitch := 0.0
var saved_origin_xf := Transform3D.IDENTITY
var seated := false
var stand_origin := Vector3.ZERO
var sit_label: Label3D


func _ready() -> void:
	SpeakerBank.setup_out_bus()        # (see speaker_bank.gd: the quiet theater)
	get_tree().node_added.connect(SpeakerBank.reroute)
	SpeakerBank.reroute_all(self)
	if get_tree().get_script() == null:       # (not under a test script)
		var one := preload("res://single_instance.gd").new()
		one.name = "SingleInstance"
		add_child(one)
		if not one.claim():
			print("The room is already open: bringing that one to the front.")
			set_process(false)
			set_physics_process(false)
			set_process_input(false)
			set_process_unhandled_input(false)
			get_tree().quit()
			return
		one.poked.connect(_on_second_copy)
	_relaunch_ack.call_deferred()             # once the room is built: proof this copy really started
	updater = Updater.new()
	updater.name = "Updater"
	add_child(updater)
	updater.changed.connect(func() -> void:
		if updater.state == "done":
			updated_this_session = true)
	room = Node3D.new()
	room.name = "Room"
	add_child(room)
	outside = Node3D.new()                    # the city and whatever goes on in it: drawn from every room
	outside.name = "Outside"
	add_child(outside)
	game_kit = Node3D.new()
	game_kit.name = "GameKit"
	add_child(game_kit)
	arcade_kit = Node3D.new()
	arcade_kit.name = "ArcadeKit"
	add_child(arcade_kit)
	study_kit = Node3D.new()
	study_kit.name = "StudyKit"
	add_child(study_kit)
	_build_environment()
	_build_shell()
	_build_window()
	_build_door()
	bank = SpeakerBank.new()
	bank.name = "Speakers"
	_host().add_child(bank)
	_build_bed()
	_build_desk()
	_build_shelf()
	_build_decor()
	_build_speakers()
	_build_lights()
	_build_curtains()
	_build_weather()
	_build_power()
	_finish_cords()
	apartment = load("res://apartment.gd").new()
	apartment.build(self)
	_setup_player()
	var pr: Node = load("res://page_renderer.gd").new()
	pr.name = "PageRenderer"
	add_child(pr)
	ComicBook.renderer = pr
	_build_multiplayer()
	_load_prefs()
	_apply_below_view()
	pc.play_random_default()


# ---------------------------------------------------------------- multiplayer

const GUEST_SPAWNS := [Vector3(0.2, 0.0, 1.0), Vector3(-2.7, 0.0, 4.6), Vector3(-2.1, 0.0, 4.1), Vector3(-1.5, 0.0, 4.7),
	Vector3(-0.9, 0.0, 4.2), Vector3(-0.3, 0.0, 4.7), Vector3(0.3, 0.0, 4.2), Vector3(1.6, 0.0, 4.7),
	Vector3(2.2, 0.0, 4.2)]           # the host's own spot, then just inside the front door (up to 8 players)


func _build_multiplayer() -> void:
	# The net scripts use WebRTC classes, so they are only loaded when the plugin is there.
	# (After an update that adds the plugin, the Godot editor must be opened once to register it.)
	if not ClassDB.class_exists("WebRTCPeerConnection"):
		print("Multiplayer unavailable: WebRTC plugin not loaded.")
		return
	net = load("res://net_session.gd").new()
	net.name = "Net"
	add_child(net)
	net_avatars = load("res://net_avatars.gd").new()
	net_avatars.name = "NetAvatars"
	add_child(net_avatars)
	net_avatars.setup(net, self)
	net_phone = load("res://net_phone.gd").new()
	net_phone.name = "WallPhone"
	net_phone.position = Vector3(-3.0, 1.45, FRONT_Z + 0.1 + 0.025)    # in the hallway by the front door
	net_phone.rotation.y = PI
	net_phone.scale = Vector3.ONE * 1.5
	apartment.hallway.add_child(net_phone)
	net_phone.build(net, func(it: Dictionary) -> void: interactables.append(it))
	if noir != null:
		net_phone.secret_cb = noir.request_start         # the keypad's secret code
	screens.append(net_phone.ui)
	net.state_changed.connect(_on_net_state)
	net.roster_changed.connect(_on_net_roster)
	net.knock.connect(func(_id: int, who: String) -> void:
		updater.show_toast("%s is knocking. Let them in (or not) on the phone." % who, 10.0))
	net_game = load("res://net_game.gd").new()
	net_game.name = "NetGame"
	add_child(net_game)
	net_game.setup(net, self, emu)
	net_room_tvs = load("res://net_room_tvs.gd").new()      # the Big TV and the Theater Screen, shared like the CRT
	net_room_tvs.name = "NetRoomTVs"
	add_child(net_room_tvs)
	net_room_tvs.setup(net, self)
	net_books = load("res://net_books.gd").new()
	net_books.name = "NetBooks"
	add_child(net_books)
	net_books.setup(net, self)
	var na: Node = load("res://net_audio.gd").new()
	na.name = "NetAudio"
	add_child(na)
	na.setup(net, self)
	net_voice = load("res://net_voice.gd").new()
	net_voice.name = "NetVoice"
	add_child(net_voice)
	net_voice.setup(net, self, net_avatars)


func _is_guest() -> bool:
	return net != null and net.state == net.State.JOINED


# What guests may touch. The host's choice, kept in settings and sent to everyone with the room state.
const GUEST_GROUPS := [["music", "Music, speakers and the monitor"], ["lights", "Lights and curtains"],
	["tv", "TV, VCR and tapes"], ["games", "Console, arcade and carts"]]
var guest_allow := {"music": false, "lights": false, "tv": false, "games": false}
var guest_allow_seen := {}             # a guest's copy of the host's choice


func _guest_may(it: Dictionary) -> bool:
	if it.get("guest_ok", false):
		return true
	var g := str(it.get("group", ""))
	if g == "":
		return false
	return bool(guest_allow_seen.get(g, false))


func set_guest_allow(group: String, on: bool) -> void:
	guest_allow[group] = on
	_save_settings()
	settings_changed.emit()


# true (with a short message) when somebody else is playing: carts, console power and TV power stay put
func _net_play_lock() -> bool:
	if net_game != null and net_game.guests_playing():
		_net_say("Someone is playing. Wait until they put the controller down.")
		return true
	return false


func _net_say(msg: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _net_toast_t > 2500:
		_net_toast_t = now
		updater.show_toast(msg, 3.0)


# guests copy what the host does to the console
func net_apply_game(d: Dictionary) -> void:
	if egg_active:
		return
	var cart := str(d.get("cart", ""))
	if cart != slot_cart and (cart == "" or (carts.has(cart) and cart != "egg")):
		var busy := (slot_cart != "" and bool(carts[slot_cart]["busy"])) or (cart != "" and bool(carts[cart]["busy"]))
		if not busy:
			if cart == "":
				_eject_cart()
			else:
				_insert_cart(cart)
	if bool(d.get("console", false)) != console_on and slot_cart != "neo" and slot_cart != "egg":
		toggle_console()
	if bool(d.get("tv", true)) != vcr.tv_on:
		vcr.toggle_tv()
	if bool(d.get("arcade", true)) != arcade_on:
		set_arcade_on(bool(d.get("arcade", true)))
	var ga = d.get("guests", {})
	if ga is Dictionary:
		guest_allow_seen = ga
	if ufo != null and d.has("ufo"):
		ufo.apply_remote(int(d.get("ufo", 0)))
	if kaiju != null and d.has("kaiju"):
		kaiju.apply_remote(int(d.get("kaiju", 0)))
	if gaboon != null and d.has("gaboon"):
		gaboon.apply_remote(int(d.get("gaboon", 0)))
	if fight != null and d.has("fight"):
		fight.apply_remote(int(d.get("fight", 0)))
	if noir != null and d.has("noir"):
		noir.apply_remote(bool(d.get("noir", false)))
	var cd = d.get("cats", null)
	if cats != null and cd is Dictionary:
		cats.apply_remote(cd)
	var song := str(d.get("song", ""))
	if pc != null:
		pc.show_remote_song(song)


func _on_net_roster() -> void:
	_refresh_beanbag_count()


# Debug: force a number of seats (0 = follow the number of players in the room)
var debug_seats := 0


func set_debug_seats(n: int) -> void:
	debug_seats = clampi(n, 0, 4)
	_refresh_beanbag_count()
	settings_changed.emit()


# ---- slapping: point at a friend holding a controller and knock it out of their hands (once per cooldown)

const SLAP_CHOICES := [-1, 5, 15, 30, 60, 120]      # minutes; -1 = never
var slap_minutes := 30


static func slap_minutes_of(mins: int) -> int:
	return maxi(mins, 0) * 60


static func fmt_wait(secs: int) -> String:
	if secs >= 90:
		return "%d min" % int(ceil(secs / 60.0))
	return "%d s" % secs


func set_slap_minutes(mins: int) -> void:
	slap_minutes = mins
	_save_settings()
	settings_changed.emit()


# pointing at a player: their name, how loud you have them, how loud they have you; the wheel / stick adjusts
func player_label(pid: int) -> String:
	var who := str(net.roster.get(pid, {}).get("name", "them"))
	if net_game != null and net_game.holds_pad(pid):
		return slap_label(pid)
	if net_voice == null:
		return who.to_upper()
	var mine: float = net_voice.volume_of(pid)
	var theirs: float = net_voice.volume_they_have_me(pid)
	var s := "%s     YOU HEAR THEM AT %d%%" % [who.to_upper(), int(round(mine * 100.0))]
	if theirs >= 0.0:
		s += "     THEY HEAR YOU AT %d%%" % int(round(theirs * 100.0))
	if net_voice.is_speaking(pid):
		s += "     (talking)"
	return s + "\n" + ("STICK UP / DOWN  =  LOUDER / QUIETER" if xr_active else "WHEEL  =  LOUDER / QUIETER")


func player_scroll(pid: int, up: bool) -> void:
	if net_voice != null:
		net_voice.set_volume_of(pid, net_voice.volume_of(pid) + (0.1 if up else -0.1))


func slap_label(pid: int) -> String:
	var who := str(net.roster.get(pid, {}).get("name", "them"))
	if net_game.slap_minutes() < 0:
		return "%s IS PLAYING  (slapping is off in this room)" % who.to_upper()
	var wait: int = net_game.slap_wait()
	if wait > 0:
		return "%s IS PLAYING  (you can slap again in %s)" % [who.to_upper(), fmt_wait(wait)]
	return "SLAP THE CONTROLLER OUT OF %s'S HANDS" % who.to_upper()


func try_slap(pid: int) -> void:
	if net_game != null:
		net_game.slap(pid)


# somebody slapped the controller out of my hands
func get_slapped(by: String) -> void:
	if game_mode:
		_put_pad()
		updater.show_toast("%s slapped the controller out of your hands!" % by, 5.0)


# Debug: hide the wall phone (it's also absent when the WebRTC plugin isn't loaded)
var phone_hidden := false


func set_phone_hidden(on: bool) -> void:
	phone_hidden = on
	if net_phone != null:
		net_phone.visible = not on
		net_phone.ui.enabled = not on
	_save_settings()
	settings_changed.emit()


func _refresh_beanbag_count() -> void:
	if debug_seats > 0:
		set_beanbag_count(debug_seats)
	else:
		set_beanbag_count(net.player_count() if net != null and net.is_online() else 1)


func _on_net_state() -> void:
	_on_net_roster()
	# guests appear at their own spot so nobody stands inside the host
	if net.state == net.State.JOINED and not _net_moved and not seated:
		_net_moved = true
		origin.position = GUEST_SPAWNS[1 + (net.my_id - 2) % (GUEST_SPAWNS.size() - 1)] if net.my_id >= 2 else GUEST_SPAWNS[1]
		if not xr_active and desktop_cam != null:
			desktop_cam.rotation.y = -PI / 2.0         # facing down the hallway, away from the door
	elif net.state == net.State.OFFLINE and _net_moved:
		_net_moved = false
		if not seated:
			origin.position = GUEST_SPAWNS[0]


# ---------------------------------------------------------------- helpers

func _mat(color: Color, rough: float = 0.85, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.disable_fog = true      # fog is only for the city outside
	m.albedo_color = color
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


# where new things go while building: the bedroom, or one of the kits that get carried off to another room
var _into: Node3D = null
var game_kit: Node3D                     # the TV corner (TV, VCR, console, carts, pads, rug, beanbags, speakers): in the game room
var arcade_kit: Node3D                   # the arcade cabinet: in the game room
var study_kit: Node3D                    # the desk with the PC, its speakers and lamp, the bookshelf: in the study
func _host() -> Node3D:
	return _into if _into != null else room


func _place(mesh: Mesh, pos: Vector3, mat: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	var p: Node = parent if parent != null else _host()
	p.add_child(mi)
	return mi


func _box(pos: Vector3, size: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _place(mesh, pos, mat, parent)


func _cyl(pos: Vector3, radius: float, height: float, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	return _place(mesh, pos, mat, parent)


func _sphere(pos: Vector3, radius: float, mat: Material, scl: Vector3 = Vector3.ONE, parent: Node = null, segs: int = 16) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segs
	mesh.rings = int(segs * 0.5)
	var mi := _place(mesh, pos, mat, parent)
	mi.scale = scl
	return mi


func _light(pos: Vector3, color: Color, energy: float, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	_host().add_child(l)
	return l


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.25, 0.60)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25
	var glow_on := USE_GLOW and not Plat.low_power()            # bloom is costly on the headset: off there unless the config asks for it
	if FileAccess.file_exists(SETTINGS_FILE):
		var gcfg := ConfigFile.new()
		if gcfg.load(SETTINGS_FILE) == OK:
			glow_on = bool(gcfg.get_value("settings", "glow", glow_on))
	if glow_on:
		env.glow_enabled = true
		env.glow_intensity = 0.9
		env.glow_bloom = 0.15
		env.glow_hdr_threshold = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	world_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ---------------------------------------------------------------- room shell

func _build_shell() -> void:
	var wall := _mat(Color(0.30, 0.12, 0.38))
	var floor_m := _mat(Color(0.20, 0.07, 0.17), 0.6)
	var ceil_m := _mat(Color(0.20, 0.08, 0.26))
	_box(Vector3(-0.7, -0.05, (FRONT_Z - 2.0) / 2.0), Vector3(6.8, 0.1, 4.2 + (FRONT_Z - 2.0)), floor_m)
	_box(Vector3(-0.7, 2.85, (FRONT_Z - 2.0) / 2.0), Vector3(6.8, 0.1, 4.2 + (FRONT_Z - 2.0)), ceil_m)
	# front wall, with the doorway out to the hallway (x 0.43 .. 1.37, 2.12 high)
	_box(Vector3((-4.1 + 0.43) / 2.0, 1.4, FRONT_Z + 0.05), Vector3(0.43 + 4.1, 2.8, 0.1), wall)
	_box(Vector3((1.37 + 2.7) / 2.0, 1.4, FRONT_Z + 0.05), Vector3(2.7 - 1.37, 2.8, 0.1), wall)
	_box(Vector3(0.9, (2.12 + 2.8) / 2.0, FRONT_Z + 0.05), Vector3(0.94, 2.8 - 2.12, 0.1), wall)
	_box(Vector3(-3.95, 1.4, (FRONT_Z - 2.0) / 2.0), Vector3(0.1, 2.8, 4.0 + (FRONT_Z - 2.0)), wall)       # left (moved out: wider room)
	_box(Vector3(2.55, 1.4, (FRONT_Z - 2.0) / 2.0), Vector3(0.1, 2.8, 4.0 + (FRONT_Z - 2.0)), wall)        # right
	# back wall with a big window opening (see WIN_X0 / WIN_X1 / WIN_Y0 / WIN_Y1)
	var wx := (WIN_X0 + WIN_X1) / 2.0
	var ww := WIN_X1 - WIN_X0
	_box(Vector3(wx, WIN_Y0 / 2.0, -2.05), Vector3(ww, WIN_Y0, 0.1), wall)                         # under the window
	_box(Vector3(wx, (WIN_Y1 + 2.8) / 2.0, -2.05), Vector3(ww, 2.8 - WIN_Y1, 0.1), wall)           # above the window
	_box(Vector3((-3.9 + WIN_X0) / 2.0, 1.4, -2.05), Vector3(WIN_X0 + 3.9, 2.8, 0.1), wall)        # left of the window
	_box(Vector3((WIN_X1 + 2.5) / 2.0, 1.4, -2.05), Vector3(2.5 - WIN_X1, 2.8, 0.1), wall)         # right of the window


func _build_window() -> void:
	var trim := _mat(Color(0.14, 0.05, 0.16))
	var wx := (WIN_X0 + WIN_X1) / 2.0
	var ww := WIN_X1 - WIN_X0
	var wh := WIN_Y1 - WIN_Y0
	# thin ledge hugging the wall (4 cm deep) so it can't clip the desk, the headboard or the nightstand
	_box(Vector3(wx, WIN_Y0 + 0.02, -1.98), Vector3(ww + 0.1, 0.04, 0.04), trim)
	var panes := maxi(2, int(roundf(ww / 1.2)))
	var pane_w := ww / panes
	for i in range(1, panes):
		_box(Vector3(WIN_X0 + i * pane_w, WIN_Y0 + wh / 2.0, -2.0), Vector3(0.06, wh, 0.06), trim)   # mullions

	# half-lowered blinds on every pane
	var blind := _mat(Color(0.50, 0.20, 0.52), 0.8)
	for i in panes:
		var cx := WIN_X0 + (i + 0.5) * pane_w
		for j in 6:
			_box(Vector3(cx, WIN_Y1 - 0.05 - j * 0.1, -1.94), Vector3(pane_w - 0.1, 0.04, 0.05), blind)

	# the sky itself comes from the Environment; real 3D buildings wrap around in front of it
	_build_city()

	# glowing pink strip in the ceiling above the window
	strip_mat = _mat(PINK, 0.5, 2.5)
	_box(Vector3(wx, 2.775, -1.5), Vector3(ww, 0.03, 0.35), strip_mat)


# ---------------------------------------------------------------- bed

const BedModel := preload("res://bed_model.gd")
const BeanbagModel := preload("res://beanbag_model.gd")
const Book := preload("res://book.gd")
const ComicBook := preload("res://comic_book.gd")
const Incense := preload("res://incense.gd")
var incense: Node3D
const BED_POS := Vector3(-1.2, 0.0, -0.9)      # (moved 45 cm toward the window seat, to give the recliner room)
const NIGHT_X := -0.05                            # the nightstand, on the bed's right
var updated_this_session := false      # an update was installed and the player has not napped yet: the easter egg stays locked
var bed_made := true                   # false after sleeping: the next morning the bed is a mess
var bed_node: Node3D


func _rebuild_bed() -> void:
	if bed_node != null and is_instance_valid(bed_node):
		bed_node.queue_free()
	bed_node = BedModel.build(room, BED_POS, "made" if bed_made else "unmade")

# the highest mesh top over a point (x, z) among a node's meshes
func _top_of(n: Node, p: Vector3, best: float) -> float:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			var bb: AABB = (ch as MeshInstance3D).global_transform * (ch as MeshInstance3D).get_aabb()
			if p.x > bb.position.x and p.x < bb.end.x and p.z > bb.position.z and p.z < bb.end.z:
				best = maxf(best, bb.end.y)
		best = _top_of(ch, p, best)
	return best


func _make_bed() -> void:
	if bed_made:
		return
	bed_made = true
	_rebuild_bed()
	_save_prefs_tick()


func _build_bed() -> void:
	_bed_sleep_spot()
	# if you drop a bed model at BED_ASSET it replaces the built-in bed (auto-scaled to fit)
	if _try_asset(BED_ASSET, BED_POS, Vector2(1.68, 2.12), BED_EXTRA_YAW):
		_build_nightstand()
		return
	_rebuild_bed()

	_build_nightstand()


func _build_nightstand() -> void:
	var wood := _mat(Color(0.30, 0.12, 0.18), 0.6)
	var padded := _mat(Color(0.52, 0.22, 0.42), 0.9)
	_box(Vector3(NIGHT_X, 0.23, -1.7), Vector3(0.4, 0.46, 0.4), wood)
	# the drawer slides out; it is where the secret cart is kept
	var face_m := _mat(Color(0.52, 0.22, 0.42), 0.9)
	var knob_m := _mat(Color(1.0, 0.8, 0.55), 0.3, 0.8)
	drawer_node = Node3D.new()
	drawer_node.position = Vector3(NIGHT_X, 0.32, -1.495)
	_host().add_child(drawer_node)
	var face := _box(Vector3.ZERO, Vector3(0.34, 0.16, 0.01), face_m, drawer_node)
	_sphere(Vector3(0, 0, 0.01), 0.016, knob_m, Vector3.ONE, drawer_node, 12)
	var tray_m := _mat(Color(0.50, 0.26, 0.40), 0.9)
	_box(Vector3(0, -0.07, -0.16), Vector3(0.31, 0.012, 0.31), tray_m, drawer_node)
	for tx in [-0.155, 0.155]:
		_box(Vector3(tx, -0.035, -0.16), Vector3(0.012, 0.07, 0.31), tray_m, drawer_node)
	_box(Vector3(0, -0.035, -0.315), Vector3(0.31, 0.07, 0.012), tray_m, drawer_node)
	interactables.append({"node": face, "half": Vector3(0.18, 0.09, 0.04), "cb": _toggle_drawer, "hover": _glow_hover(face_m), "group": "games",
		"label": func() -> String: return "CLOSE DRAWER" if drawer_open else "OPEN DRAWER"})
	_lamp(Vector3(NIGHT_X, 0.46, -1.7), 1.0)
	# the diary, lying beside the lamp
	diary = load("res://diary_book.gd").new()
	diary.name = "Diary"
	diary.position = Vector3(NIGHT_X + 0.08, 0.46, -1.6)
	diary.rotation.y = -0.2
	_host().add_child(diary)
	diary.build(self)
	screens.append(diary.ui)
	interactables.append({"node": diary.cover, "half": Vector3(0.1, 0.03, 0.14), "guest_ok": true,
		"when": func() -> bool: return not diary.open_book,
		"label": func() -> String: return "READ THE DIARY", "cb": pick_diary})


func _toggle_drawer() -> void:
	if drawer_busy:
		return
	drawer_busy = true
	drawer_open = not drawer_open
	var tw := create_tween()
	tw.tween_property(drawer_node, "position:z", -1.495 + (0.26 if drawer_open else 0.0), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func() -> void: drawer_busy = false)


func _lamp(pos: Vector3, s: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.scale = Vector3.ONE * s
	_host().add_child(root)
	var dark := _mat(Color(0.10, 0.04, 0.12))
	_cyl(Vector3(0, 0.01, 0), 0.07, 0.02, dark, root)
	_cyl(Vector3(0, 0.15, 0), 0.012, 0.3, dark, root)
	var shade_m := _mat(WARM, 0.5, 2.5)
	var shade := _cyl(Vector3(0, 0.33, 0), 0.08, 0.14, shade_m, root)
	(shade.mesh as CylinderMesh).top_radius = 0.05
	lamp_shades.append({"node": shade, "mat": shade_m})


# ---------------------------------------------------------------- desk

func _build_desk() -> void:
	_into = study_kit
	var wood := _mat(Color(0.55, 0.25, 0.22), 0.6)
	var dark := _mat(Color(0.12, 0.05, 0.14))
	_box(Vector3(1.45, 0.76, -1.55), Vector3(1.9, 0.05, 0.8), wood)
	for sx in [-0.9, 0.9]:
		for sz in [-0.35, 0.35]:
			_box(Vector3(1.45 + sx, 0.37, -1.55 + sz), Vector3(0.05, 0.74, 0.05), dark)

	# monitor with animated screen
	_box(Vector3(1.45, 0.795, -1.7), Vector3(0.22, 0.01, 0.14), dark)
	_box(Vector3(1.45, 0.87, -1.7), Vector3(0.04, 0.14, 0.04), dark)
	_box(Vector3(1.45, 1.13, -1.72), Vector3(0.78, 0.50, 0.03), dark)
	var screen := QuadMesh.new()
	screen.size = Vector2(0.72, 0.4)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/screen.gdshader")
	monitor_quad = _place(screen, Vector3(1.45, 1.15, -1.70), sm, null)
	_attach_media(sm, "res://media/monitor")
	var pc_ui := ScreenUI.new()
	pc_ui.position = Vector3(1.45, 1.15, -1.70)
	_host().add_child(pc_ui)
	pc_ui.setup(sm, Vector2(0.72, 0.4), Vector2i(1024, 576), 0.0)
	screens.append(pc_ui)
	monitor_ui = pc_ui
	# monitor power button, bottom right of the bezel
	var mb_m := _mat(Color(0.20, 0.17, 0.24), 0.4)
	var mb := _box(Vector3(1.45 + 0.32, 0.905, -1.704), Vector3(0.06, 0.022, 0.02), mb_m)
	monitor_led_m = _mat(Color(0.2, 1.0, 0.4), 0.4, 3.0)
	_sphere(Vector3(1.45 + 0.27, 0.905, -1.695), 0.005, monitor_led_m, Vector3.ONE, null, 8)
	interactables.append({"node": mb, "half": Vector3(0.05, 0.03, 0.04),
		"label": _monitor_label, "egg_lock": true, "cb": _toggle_monitor, "hover": _glow_hover(mb_m), "group": "music"})
	pc = PCPlayer.new()
	pc.position = Vector3(1.45, 1.0, -1.7)
	_host().add_child(pc)
	pc.setup(pc_ui, bank)

	# keyboard, mug, lamp, plant
	keyboard_node = _box(Vector3(1.45, 0.80, -1.38), Vector3(0.42, 0.015, 0.14), _mat(Color(0.25, 0.10, 0.28)))
	mug_node = _cyl(Vector3(1.95, 0.825, -1.42), 0.035, 0.08, _mat(Color(0.95, 0.80, 0.75)))
	_lamp(Vector3(2.2, 0.785, -1.75), 1.0)
	_plant(Vector3(0.7, 0.785, -1.75), 0.5)

	# chair
	chair = Node3D.new()
	chair.position = Vector3(1.45, 0.0, -0.8)
	_host().add_child(chair)
	var chair_m := _mat(Color(0.42, 0.17, 0.45))
	_box(Vector3(0, 0.46, 0), Vector3(0.46, 0.06, 0.46), chair_m, chair)
	_box(Vector3(0, 0.74, 0.22), Vector3(0.46, 0.5, 0.05), chair_m, chair)
	_cyl(Vector3(0, 0.23, 0), 0.03, 0.4, dark, chair)
	_cyl(Vector3(0, 0.02, 0), 0.25, 0.03, dark, chair)
	sit_label = Label3D.new()
	sit_label.text = "Sit  (E)"
	sit_label.font_size = 56
	sit_label.pixel_size = 0.0009
	sit_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sit_label.no_depth_test = true
	sit_label.modulate = Color(1.0, 0.85, 0.95)
	sit_label.outline_modulate = Color(0.2, 0.05, 0.3)
	sit_label.position = Vector3(1.45, 1.3, -0.8)
	sit_label.visible = false
	add_child(sit_label)                      # (shown over whichever seat is near, in any room)
	seat_nodes.append(chair)
	seat_eye.append(SEAT_EYE_HEIGHT)
	seat_swivel.append(true)

	_into = null
	# the poster on the right wall: the 90s anime one, or any picture you pick (poster.gd)
	poster = load("res://poster.gd").new()
	poster.name = "Poster"
	poster.position = Vector3(2.5, 1.75, -1.25)
	poster.rotation.y = -PI / 2.0
	_host().add_child(poster)
	poster.build(_mat(Color(0.95, 0.80, 0.86), 0.5))
	screens.append(poster.ui)
	interactables.append({"node": poster.frame, "half": Vector3(0.6, 0.55, 0.05), "guest_ok": true,
		"half_fn": func() -> Vector3: return poster.frame.mesh.size * 0.5 + Vector3(0, 0, 0.03),
		"hint_at": func() -> Vector3: return poster.hint_spot(),
		"no_reticle": true,                        # no crosshair dot over the picture (clicking it still opens the picker)
		"label": func() -> String: return poster.label(), "cb": func() -> void: poster.toggle_picker()})
	# paper lantern hanging from the ceiling on a cord
	_cyl(Vector3(1.6, 2.65, 0.3), 0.004, 0.3, _mat(Color(0.10, 0.04, 0.12)))
	lantern_mat = _mat(WARM, 0.5, 2.5)
	lantern_node = _sphere(Vector3(1.6, 2.4, 0.3), 0.15, lantern_mat)
	_cyl(Vector3(1.6, 2.79, 0.3), 0.04, 0.02, _mat(Color(0.92, 0.88, 0.92), 0.6))   # ceiling rose


# ---------------------------------------------------------------- speakers (PC sound comes out of these)

func _glow_hover(m: StandardMaterial3D) -> Callable:
	return func(on: bool) -> void:
		m.emission_enabled = on
		if on:
			m.emission = Color(1.0, 0.9, 1.0)
			m.emission_energy_multiplier = 0.6


func _make_speaker(spk_name: String, pos: Vector3, yaw: float, tilt: float, size: Vector3, cone_r: float, parent: Node3D = null) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation = Vector3(tilt, yaw, 0.0)       # local +z is the front of the speaker
	(parent if parent != null else _host()).add_child(root)
	var body_m := _mat(Color(0.15, 0.10, 0.18), 0.55)
	var body := _box(Vector3.ZERO, size, body_m, root)
	var cone_m := _mat(Color(0.07, 0.05, 0.09), 0.9)
	var ring_m := _mat(Color(0.34, 0.27, 0.38), 0.4)
	var fz := size.z / 2.0
	var woof := _cyl(Vector3(0, -size.y * 0.16, fz + 0.002), cone_r, 0.01, cone_m, root)
	woof.rotation.x = PI / 2.0
	var ring := _cyl(Vector3(0, -size.y * 0.16, fz + 0.001), cone_r * 1.12, 0.006, ring_m, root)
	ring.rotation.x = PI / 2.0
	_sphere(Vector3(0, -size.y * 0.16, fz + 0.008), cone_r * 0.3, ring_m, Vector3(1, 1, 0.5), root, 8)
	var tweet := _cyl(Vector3(0, size.y * 0.30, fz + 0.002), cone_r * 0.32, 0.01, ring_m, root)
	tweet.rotation.x = PI / 2.0
	var led_m := StandardMaterial3D.new()
	led_m.disable_fog = true      # fog is only for the city outside
	var led := _sphere(Vector3(size.x * 0.34, -size.y * 0.43, fz + 0.004), 0.006, led_m, Vector3.ONE, root, 8)
	var idx := bank.add_speaker(spk_name, root.position + root.basis * Vector3(0, 0, fz + 0.05), led_m)
	interactables.append({
		"node": body,
		"half": size / 2.0 + Vector3(0.03, 0.03, 0.03),
		"label": _speaker_label.bind(idx, spk_name),
		"cb": bank.toggle.bind(idx), "group": "music",
		"hover": _glow_hover(body_m),
	})
	led.name = "LED"


func _speaker_label(idx: int, spk_name: String) -> String:
	var names: Array[String] = []
	for m in bank.sources(idx):
		names.append(bank.source_name(idx, m).to_upper())
	return "%s  [%s]\nclick: %s" % [spk_name, bank.source_name(idx, bank.get_mode(idx)).to_upper(), "  >  ".join(names)]


# [name, position, yaw] of the two speakers beside the TV (it stands across the front-left corner)
func _tv_speaker_spots() -> Array:
	return [["TV speaker L", Vector3(-3.9 + 0.12, 1.3, 1.5), 2.1], ["TV speaker R", Vector3(-1.95, 1.3, FRONT_Z - 0.12), 2.6]]


func _tv_label(kind: String) -> String:
	match kind:
		"power":
			return "CRT TV POWER  [%s]" % ("ON" if vcr.tv_on else "OFF")
		"vol_down":
			return "CRT TV VOLUME DOWN  [%d/10]" % vcr.tv_volume
	return "CRT TV VOLUME UP  [%d/10]" % vcr.tv_volume


func _on_tv_power(on: bool, led_m: StandardMaterial3D) -> void:
	led_m.albedo_color = Color(0.2, 1.0, 0.4) if on else Color(0.3, 0.05, 0.05)
	led_m.emission = Color(0.2, 1.0, 0.4) if on else Color(0.6, 0.05, 0.05)
	led_m.emission_energy_multiplier = 3.0 if on else 0.5


func _monitor_label() -> String:
	return "MONITOR  [%s]" % ("ON" if monitor_on else "OFF")


func _toggle_monitor() -> void:
	if egg_active:
		return
	_set_monitor(not monitor_on)


func _set_monitor(on: bool) -> void:
	monitor_on = on
	monitor_quad.visible = monitor_on
	monitor_ui.enabled = monitor_on
	monitor_light.visible = monitor_on
	monitor_led_m.albedo_color = Color(0.2, 1.0, 0.4) if monitor_on else Color(0.3, 0.05, 0.05)
	monitor_led_m.emission = Color(0.2, 1.0, 0.4) if monitor_on else Color(0.6, 0.05, 0.05)
	monitor_led_m.emission_energy_multiplier = 3.0 if monitor_on else 0.5
	if not monitor_on and focus_screen == monitor_ui and focus_level > 0:
		_end_focus(true)


var study_speakers: Array[int] = []        # the desk speakers (went with the study kit)
var kit_speakers: Array[int] = []          # speakers that went with the game kit (their sound has to follow)

func _build_speakers() -> void:
	# two desk speakers either side of the monitor
	_into = study_kit
	_make_speaker("Desk speaker L", Vector3(0.96, 0.915, -1.76), 0.15, 0.0, Vector3(0.14, 0.26, 0.16), 0.046)
	study_speakers.append(bank.speakers.size() - 1)
	_make_speaker("Desk speaker R", Vector3(1.94, 0.915, -1.76), -0.15, 0.0, Vector3(0.14, 0.26, 0.16), 0.046)
	study_speakers.append(bank.speakers.size() - 1)
	_into = null
	# wall speakers: one up on the left wall over the recliner, tipped down toward it, and one either side of the
	# TV (on the left wall and the front wall), both turned a little toward the room
	var ws := Vector3(0.18, 0.32, 0.16)
	_make_speaker("Recliner speaker", Vector3(-3.9 + 0.09, 1.8, RECLINER_POS.z), PI / 2.0, 0.25, ws, 0.055)
	_into = game_kit
	for sp in _tv_speaker_spots():
		_make_speaker(str(sp[0]), sp[1], float(sp[2]), 0.06, ws, 0.055)
		kit_speakers.append(bank.speakers.size() - 1)
	_into = null
	pc.refresh_speakers()


# ---------------------------------------------------------------- bookshelf

func _build_shelf() -> void:
	_into = study_kit
	var wood := _mat(Color(0.30, 0.12, 0.20), 0.7)
	var z0 := -0.5
	var z1 := 1.1
	var zc := (z0 + z1) / 2.0
	var width := z1 - z0
	var boards := [0.03, 0.5, 0.95, 1.4, 1.85, 2.2]
	_box(Vector3(2.485, 1.1, zc), Vector3(0.03, 2.2, width), wood)
	_box(Vector3(2.34, 1.1, z0), Vector3(0.3, 2.2, 0.04), wood)
	_box(Vector3(2.34, 1.1, z1), Vector3(0.3, 2.2, 0.04), wood)
	for y in boards:
		_box(Vector3(2.34, y, zc), Vector3(0.3, 0.03, width), wood)

	var palette := [
		Color(0.85, 0.45, 0.55), Color(0.35, 0.55, 0.62), Color(0.75, 0.65, 0.50),
		Color(0.55, 0.30, 0.65), Color(0.90, 0.55, 0.30), Color(0.25, 0.25, 0.45),
	]
	var book_mats: Array = []
	for c in palette:
		book_mats.append(_mat(c, 0.8))

	_shelf_z0 = z0
	_shelf_z1 = z1
	_shelf_boards = boards
	_shelf_book_mats = book_mats
	_fill_shelf()
	_plant(Vector3(2.34, 2.215, 0.0), 0.6)
	_into = null


# ---------------------------------------------------------------- comics on the shelf

var _shelf_z0 := 0.0
var _shelf_z1 := 0.0
var _shelf_boards: Array = []
var _shelf_book_mats: Array = []
var _shelf_nodes: Array = []           # everything standing on the boards (rebuilt when the folder changes)
var _shelf_items: Array = []           # interactables that belong to the shelf
var _shelf_mtime := -1
var _shelf_check_t := 0.0
var library: Array = []                # [{"title", "path", "size"}], what is in the books folder
var books: Array = []                  # Book nodes in the room (held or lying about)
var held_book: Node3D
var diary: Node3D                   # the little book on the nightstand (diary_book.gd)
var _diary_home := Transform3D.IDENTITY
var book_hint_t := 0.0


static func books_dir() -> String:
	var d: String
	if Plat.is_android():
		d = ProjectSettings.globalize_path("user://books")
	else:
		d = ProjectSettings.globalize_path("res://books") if FileAccess.file_exists("res://project.godot") else OS.get_executable_path().get_base_dir().path_join("books")
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d


# A .cbz is a book; a folder of .cbz files is one book whose issues are chapters.
func _scan_library() -> void:
	library.clear()
	var dir := books_dir()
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not n.begins_with("."):
			var p := dir.path_join(n)
			if d.current_is_dir():
				var issues: Array = ComicBook.issues_in(p)
				if not issues.is_empty():
					var total := 0
					for f in issues:
						total += _file_size(f)
					library.append({"title": ComicBook.nice_title(p), "path": p, "size": total, "issues": issues.size()})
			elif ComicBook.BOOK_EXTS.has(n.get_extension().to_lower()):
				library.append({"title": ComicBook.nice_title(p), "path": p, "size": _file_size(p), "issues": 1})
		n = d.get_next()
	d.list_dir_end()
	library.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ComicBook._nat_key(str(a["title"])) < ComicBook._nat_key(str(b["title"])))


static func _file_size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


func _fill_shelf() -> void:
	var was := _into
	_into = study_kit                          # (it's rebuilt when the folder changes, long after building)
	_fill_shelf_now()
	_into = was


func _fill_shelf_now() -> void:
	for n in _shelf_nodes:
		n.queue_free()
	_shelf_nodes.clear()
	for it in _shelf_items:
		interactables.erase(it)
	_shelf_items.clear()
	_scan_library()
	var z0 := _shelf_z0
	var z1 := _shelf_z1
	var spine := _mat(Color(0.95, 0.9, 1.0), 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var next_book := 0
	# the most recently read books stand face-out at the front of the eye-level boards, showing their covers
	var faced := {}
	var recent := _recent_books(3)
	for i in [3, 2, 4, 1, 0]:          # comics fill the eye-level boards first
		var z := z0 + 0.05
		var gap_chance := 0.12 if i < 3 else 0.35
		if i == 3 or i == 2:
			for rp in recent:
				if faced.has(rp) or z > z1 - 0.3:
					continue
				var rb := _library_entry(rp)
				if rb.is_empty():
					continue
				faced[rp] = true
				var ch := 0.27 if i == 3 else 0.24
				var cw := ch * 0.66
				var node := _face_out_book(rb, Vector3(2.30, _shelf_boards[i] + 0.015 + ch / 2.0, z + cw / 2.0 + 0.01), cw, ch)
				_shelf_nodes.append(node)
				var it := {"node": node, "half": Vector3(0.035, ch / 2.0, cw / 2.0 + 0.004), "guest_ok": true, "shelf": true,
					"hint_at": _shelf_hint_spot.bind(node, ch),
					"label": _book_label.bind(rb), "cb": _open_book.bind(str(rb["path"]))}
				interactables.append(it)
				_shelf_items.append(it)
				z += cw + 0.05
		while z < z1 - 0.1:
			if next_book < library.size() and faced.has(str(library[next_book]["path"])):
				next_book += 1
				continue
			if next_book < library.size():
				# a real comic: the spine carries its name, pointing at it says READ
				var b: Dictionary = library[next_book]
				next_book += 1
				var w := clampf(0.03 + float(b["size"]) / (1024.0 * 1024.0) * 0.0002, 0.03, 0.08)
				var h := 0.27 if i < 3 else 0.24
				var m: Material = _shelf_book_mats[hash(str(b["title"])) % _shelf_book_mats.size()]
				var bx := _box(Vector3(2.35, _shelf_boards[i] + 0.015 + h / 2.0, z + w / 2.0), Vector3(0.2, h, w), m)
				_shelf_nodes.append(bx)
				var lb := Label3D.new()
				lb.text = _spine_text(str(b["title"]), h)
				lb.font_size = 40
				lb.pixel_size = 0.00042
				lb.outline_size = 0
				lb.modulate = Color(0.98, 0.94, 0.9)
				lb.position = Vector3(2.247, _shelf_boards[i] + 0.015 + h / 2.0, z + w / 2.0)
				lb.rotation = Vector3(0.0, -PI / 2.0, -PI / 2.0)     # reads top to bottom along the spine, facing the room
				_host().add_child(lb)
				_shelf_nodes.append(lb)
				var it := {"node": bx, "half": Vector3(0.1, h / 2.0, w / 2.0 + 0.002), "guest_ok": true, "shelf": true,
					"hint_at": _shelf_hint_spot.bind(bx, h),
					"label": _book_label.bind(b), "cb": _open_book.bind(str(b["path"]))}
				interactables.append(it)
				_shelf_items.append(it)
				z += w + 0.004
				continue
			if rng.randf() < gap_chance:
				z += rng.randf_range(0.08, 0.2)
				continue
			var w2 := rng.randf_range(0.03, 0.06)
			var h2 := rng.randf_range(0.18, 0.34)
			var m2: Material = _shelf_book_mats[rng.randi() % _shelf_book_mats.size()]
			_shelf_nodes.append(_box(Vector3(2.35, _shelf_boards[i] + 0.015 + h2 / 2.0, z + w2 / 2.0), Vector3(0.2, h2, w2), m2))
			z += w2 + 0.003
	if library.is_empty():
		# nothing yet: pointing anywhere at the shelf says where comics go
		var hit := _box(Vector3(2.28, 1.1, (z0 + z1) / 2.0), Vector3(0.1, 2.1, z1 - z0), spine)
		hit.visible = false
		_shelf_nodes.append(hit)
		var it := {"node": hit, "half": Vector3(0.05, 1.05, (z1 - z0) / 2.0), "guest_ok": true,
			"hint_at": func() -> Vector3: return Vector3(2.17, _shelf_boards[2], (z0 + z1) / 2.0),     # on the middle shelf's front edge
			"label": func() -> String: return "PUT COMICS (.CBZ, OR A FOLDER OF THEM) IN THE BOOKS FOLDER",
			"cb": func() -> void: updater.show_toast("Comics go in:  " + books_dir(), 10.0)}
		interactables.append(it)
		_shelf_items.append(it)
	_shelf_mtime = FileAccess.get_modified_time(books_dir())


# the sign for a book on the shelf: just under its shelf board, out in front, so it never covers the books
func _shelf_hint_spot(node: Node3D, h: float) -> Vector3:
	var p := node.global_position
	return Vector3(2.17, p.y - h / 2.0 - 0.015, p.z)          # on the front edge of the shelf board the book stands on


# Debug: the book titles' pointing signs on the shelf (off by default: the spines already say what they are)
var shelf_hints := false


func set_shelf_hints(on: bool) -> void:
	shelf_hints = on
	_save_settings()
	settings_changed.emit()


# the books in the diary, newest first
func _recent_books(n: int) -> Array:
	var out: Array = []
	for e in load("res://diary.gd").entries():
		if e["kind"] == "book" and e.has("path"):
			out.append(str(e["path"]))
			if out.size() >= n:
				break
	return out


func _library_entry(path: String) -> Dictionary:
	for b in library:
		if str(b["path"]) == path:
			return b
	return {}


# a book standing face-out, its cover (the first page) on the front; the cover picture arrives when it has been cached
func _face_out_book(b: Dictionary, pos: Vector3, w: float, h: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = -PI / 2.0 + 0.12            # face into the room, leaning a touch
	_host().add_child(root)
	var m: Material = _shelf_book_mats[hash(str(b["title"])) % _shelf_book_mats.size()]
	_box(Vector3(0, 0, -0.012), Vector3(w, h, 0.02), m, root)        # the block of pages
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.2, 0.12, 0.2)
	cm.roughness = 0.7
	cm.disable_fog = true
	var cover := MeshInstance3D.new()
	cover.mesh = q
	cover.material_override = cm
	cover.position = Vector3(0, 0, 0.0005)
	root.add_child(cover)
	# until (or unless) a cover picture turns up, the title is printed on the front like a plain hardback
	var tl := Label3D.new()
	tl.text = str(b["title"])
	tl.font_size = 36
	tl.pixel_size = 0.00045
	tl.width = w / 0.00045 - 20
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.outline_size = 0
	tl.modulate = Color(0.95, 0.85, 0.6)
	tl.position = Vector3(0, h * 0.18, 0.0012)
	root.add_child(tl)
	_cover_for(str(b["path"]), func(tex: Texture2D) -> void:
		if tex != null and is_instance_valid(cover):
			cm.albedo_color = Color.WHITE
			cm.albedo_texture = tex
			tl.visible = false
			cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	return root


# Cover thumbnails live in user://covers/<md5>.png so the shelf never decodes a comic twice.
var _cover_jobs := {}


func _cover_for(path: String, done: Callable) -> void:
	var key := path.md5_text()
	var cache := "user://covers/%s.png" % key
	if FileAccess.file_exists(cache):
		var img := Image.load_from_file(ProjectSettings.globalize_path(cache))
		if img != null:
			done.call(ImageTexture.create_from_image(img))
			return
	DirAccess.make_dir_recursive_absolute("user://covers")
	var task := WorkerThreadPool.add_task(func() -> void:
		var c = ComicBook.new()
		var img: Image = null
		if c.open(path) and c.page_count() > 0 and not c.text_mode:
			img = ComicBook._decode(c.pages[0][0], c.pages[0][1], 512)
		if img != null:
			img.save_png(ProjectSettings.globalize_path(cache))
		c.close())
	_cover_jobs[task] = [cache, done]


func _poll_covers() -> void:
	for task in _cover_jobs.keys():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			var job: Array = _cover_jobs[task]
			_cover_jobs.erase(task)
			if FileAccess.file_exists(job[0]):
				var img := Image.load_from_file(ProjectSettings.globalize_path(job[0]))
				if img != null:
					(job[1] as Callable).call(ImageTexture.create_from_image(img))


static func _spine_text(t: String, h: float) -> String:
	var max_chars := int(h / 0.0115)
	return t if t.length() <= max_chars else t.left(max_chars - 1) + "…"


func _book_label(b: Dictionary) -> String:
	var t: String = str(b["title"])
	if int(b["issues"]) > 1:
		t += "  (%d issues)" % int(b["issues"])
	return "READ  " + t


# the shelf follows the folder: a new file shows up the next time you look at the shelf
func _check_shelf(delta: float) -> void:
	_shelf_check_t -= delta
	if _shelf_check_t > 0.0:
		return
	_shelf_check_t = 3.0
	if hover_item.is_empty() or not _shelf_items.has(hover_item):
		return
	if FileAccess.get_modified_time(books_dir()) != _shelf_mtime:
		_fill_shelf()


# ---- the book in the room

func _open_book(path: String) -> void:
	if held_book != null and held_book.comic != null and held_book.comic.path == path:
		return
	# the same book may already lie somewhere in the room: pick that one up instead of opening a second copy
	for b in books:
		if b.comic != null and b.comic.path == path:
			_hold_book(b)
			return
	var bk: Node3D = Book.new()
	var err: String = bk.open_file(path)
	if err != "":
		bk.free()
		updater.show_toast(err, 6.0)
		return
	add_child(bk)                               # (books get carried from room to room)
	_add_book(bk)
	_hold_book(bk)
	if net_books != null:
		net_books._my_book_opened(bk)


func _add_book(bk: Node3D) -> void:
	books.append(bk)
	bk.turned.connect(func() -> void:
		if net_books != null:
			net_books._my_book_turned(bk))
	if bk.toc != null:
		screens.append(bk.toc)
	# the two little tabs on a held book: front page (left) and bookmark (right, hold to set)
	interactables.append({"node": bk.tab_home, "half": Vector3(0.03, 0.014, 0.012), "guest_ok": true,
		"when": func() -> bool: return bk == held_book,
		"label": func() -> String: return "FRONT PAGE", "cb": func() -> void: bk.go_front()})
	interactables.append({"node": bk.tab_mark, "half": Vector3(0.03, 0.014, 0.012), "guest_ok": true,
		"when": func() -> bool: return bk == held_book,
		"label": func() -> String: return bk.mark_label(), "cb": func() -> void: _mark_press(bk), "hold": func() -> void: bk.set_mark_here()})
	interactables.append({"node": bk, "half": Vector3(0.3, 0.22, 0.03), "guest_ok": true,
		"when": func() -> bool: return bk.lying,
		"label": func() -> String: return "PICK UP  " + bk.title, "cb": _hold_book.bind(bk)})


func _hold_book(bk: Node3D) -> void:
	if held_book == bk:
		return
	if held_book != null:
		_put_book()
	held_book = bk
	bk.lying = false
	bk.held_by_me = true
	bk._update_toc()
	book_hint_t = 8.0
	_book_placed = false
	book_zoom = 0
	if net_books != null and bk.net_id != "":
		net_books._my_book_taken(bk)
	var xf := _book_target()
	bk.global_transform = Transform3D(xf.basis, xf.origin - xf.basis.z * 0.3)


# where a held book floats: in front of the face, a little low, tilted up toward the eyes
func _book_target() -> Transform3D:
	return _held_book_target()


func _book_pose_for(hx: Transform3D, zoom := 0) -> Transform3D:
	var fwd := -hx.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var dist := 0.6
	var drop := -0.14
	var tilt := -0.3
	if zoom == 1:
		dist = 0.42
		drop = -0.06
		tilt = -0.15
	elif zoom == 2:
		# the pages fill the height of the view: straight ahead, square on
		dist = _book_fill_distance()
		drop = 0.0
		tilt = 0.0
	var pos := hx.origin + fwd * dist + Vector3(0.0, drop, 0.0)
	var basis := Basis.looking_at(fwd, Vector3.UP)      # local -z looks where you look, so +z (the pages) faces you
	basis = basis * Basis(Vector3.RIGHT, tilt)          # tilted back so the pages face up toward your eyes
	return Transform3D(basis, pos)


func _book_fill_distance() -> float:
	var h := Book.PAGE_H + 0.03
	if xr_active:
		return maxf(0.45, (h / 2.0) / tan(deg_to_rad(40.0)))
	var vfov := deg_to_rad(desktop_cam.fov)
	return (h / 2.0) / tan(vfov / 2.0) / 0.93


# The held book only follows you once you look well away from it, so you can aim at the contents page
# (and at the pages themselves) without dragging it along.
var book_zoom := 0              # 0 = in your hands, 1 = close, 2 = fills the view
var _book_yaw := 0.0            # the yaw the book was last placed at
var _book_placed := false


func _held_book_target() -> Transform3D:
	var fwd := -head.global_transform.basis.z
	fwd.y = 0.0
	var yaw := atan2(fwd.x, fwd.z) if fwd.length() > 0.01 else _book_yaw
	# the book stays put while you look anywhere on it (its half-width as seen from your eye, plus a margin),
	# so every corner of both pages can be aimed at, at every zoom; look well past its edge and it comes along
	var dist: float = [0.6, 0.42, _book_fill_distance()][book_zoom]
	var dead: float = atan((Book.PAGE_W * 1.35 + 0.02) / dist) + 0.12
	if not _book_placed or absf(angle_difference(yaw, _book_yaw)) > dead:
		_book_placed = true
		_book_yaw = yaw
	var hx := Transform3D(Basis(Vector3.UP, _book_yaw) * Basis(Vector3.UP, PI), head.global_position)   # a head looking along _book_yaw
	return _book_pose_for(hx, book_zoom)


func toggle_book_zoom() -> void:
	book_zoom = (book_zoom + 1) % 3
	_book_placed = false


func _put_book() -> void:
	var bk := held_book
	if bk == null:
		return
	held_book = null
	bk.held_by_me = false
	bk.lying = true
	bk._update_toc()
	var fwd := -head.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var p := head.global_position + fwd * 0.6
	if not _walkable(p.x, p.z):
		p = head.global_position + fwd * 0.25
	p.y = 0.012
	var yaw := atan2(fwd.x, fwd.z)
	bk.global_transform = Transform3D(Basis(Vector3.UP, yaw + PI) * Basis(Vector3.RIGHT, -PI / 2.0), p)   # open, pages up, the top away from you
	bk._save_bookmark()
	_shelf_mtime = -1                          # the "recently read" row may have changed: rebuild next time the shelf is looked at
	if net_books != null:
		net_books._my_book_put(bk)


func _remove_book(bk: Node3D) -> void:
	if held_book == bk:
		held_book = null
	books.erase(bk)
	for it in interactables.duplicate():
		if it.get("node") == bk:
			interactables.erase(it)
	if bk.toc != null:
		screens.erase(bk.toc)
		if hover_screen == bk.toc:
			hover_screen = null
	bk.queue_free()


func _update_book(delta: float) -> void:
	var k := 1.0 - exp(-10.0 * delta)
	if held_book != null:
		_glide(held_book, _book_target(), k)
	# books in other people's hands float in front of their avatars
	if net_avatars != null:
		for bk in books:
			if bk == held_book or bk.lying or bk.holder_id == 0 or not net_avatars.avatars.has(bk.holder_id):
				continue
			var av: Node3D = net_avatars.avatars[bk.holder_id]
			if av.visible:
				_glide(bk, _book_pose_for(av.head.global_transform), k)
	_check_shelf(delta)
	_poll_covers()
	_update_diary(delta)


func _glide(bk: Node3D, t: Transform3D, k: float) -> void:
	var cur := bk.global_transform
	if cur.origin.distance_to(t.origin) > 3.0:
		bk.global_transform = t
		return
	bk.global_transform = Transform3D(cur.basis.get_rotation_quaternion().slerp(t.basis.get_rotation_quaternion(), k), cur.origin.lerp(t.origin, k))


var _mark_down_t := 0.0
var _mark_bk: Node3D


func _mark_press(bk: Node3D) -> void:
	# a tap jumps to the bookmark; holding ~0.6 s sets it on the page you're on
	_mark_bk = bk
	_mark_down_t = Time.get_ticks_msec() / 1000.0


func _mark_release() -> void:
	if _mark_bk == null:
		return
	var held := Time.get_ticks_msec() / 1000.0 - _mark_down_t
	if held >= 0.6:
		_mark_bk.set_mark_here()
		updater.show_toast("Bookmark set on page %d." % (_mark_bk.mark_page + 1), 3.0)
	else:
		if _mark_bk.mark_page < 0:
			_mark_bk.set_mark_here()
			updater.show_toast("Bookmark set on page %d. Hold the tab to move it later." % (_mark_bk.mark_page + 1), 4.0)
		else:
			_mark_bk.go_mark()
	_mark_bk = null


# ---- the diary floats in front of you like a book; put it down and it goes back to the nightstand

func pick_diary() -> void:
	if diary.open_book:
		return
	if held_book != null:
		_put_book()
	_diary_home = diary.global_transform
	diary.set_open(true)
	_book_placed = false
	book_zoom = 1
	book_hint_t = 8.0


func put_diary() -> void:
	if not diary.open_book:
		return
	diary.set_open(false)
	diary.global_transform = _diary_home
	book_zoom = 0


func _update_diary(delta: float) -> void:
	if diary == null or not diary.open_book:
		return
	var t := _held_book_target()
	var k := 1.0 - exp(-10.0 * delta)
	# the diary is smaller than a comic: bring it a little closer
	t.origin += -t.basis.z * -0.1
	_glide(diary, t, k)


func _book_page(dir: int) -> void:
	if held_book == null:
		return
	if dir > 0:
		held_book.next_spread()
	else:
		held_book.prev_spread()


# ---------------------------------------------------------------- decor

func _build_decor() -> void:
	# rug
	_box(Vector3(0.1, 0.01, 0.75), Vector3(1.8, 0.02, 1.3), _mat(Color(0.35, 0.12, 0.40), 1.0))
	_box(Vector3(0.1, 0.012, 0.75), Vector3(1.5, 0.02, 1.0), _mat(Color(0.55, 0.22, 0.42), 1.0))
	_into = game_kit
	_build_lounge_frame()
	_build_tv()
	_build_console()
	# round lounge rug in front of the corner TV
	var rug_c := tv_root.to_global(Vector3(0.0, 0.0, 1.35))
	rug_c.x = maxf(rug_c.x, -3.9 + 1.3)
	rug_c.z = minf(rug_c.z, FRONT_Z - 1.3)
	_cyl(Vector3(rug_c.x, 0.01, rug_c.z), 1.3, 0.02, _mat(Color(0.30, 0.10, 0.34), 1.0))
	_cyl(Vector3(rug_c.x, 0.012, rug_c.z), 1.15, 0.02, _mat(Color(0.42, 0.15, 0.42), 1.0))
	_build_beanbags()
	_into = null
	_build_bedroom_corner()
	_build_recliner()
	_build_dresser()
	# fairy lights: three strands, kept restrained
	var bulb := _mat(WARM, 0.5, 3.0)
	fairy_mat = bulb
	_fairy(Vector3(-3.86, 2.55, -1.2), Vector3(-3.86, 2.55, FRONT_Z - 0.1), 22, 4, 0.16, bulb)   # left wall
	_fairy(Vector3(-3.8, 2.6, FRONT_Z - 0.04), Vector3(2.4, 2.6, FRONT_Z - 0.04), 18, 4, 0.18, bulb)        # front wall, above the door


# where the TV used to stand (it's in the game room now): a big plant, a floor lamp and a pile of floor cushions
func _build_bedroom_corner() -> void:
	_plant(Vector3(-3.55, 0.0, FRONT_Z - 0.35), 2.2)
	var lamp_m := _mat(Color(0.12, 0.08, 0.14), 0.5)
	_cyl(Vector3(-3.6, 0.02, 1.75), 0.15, 0.04, lamp_m)
	_cyl(Vector3(-3.6, 0.78, 1.75), 0.014, 1.5, lamp_m)
	var shade := _cyl(Vector3(-3.6, 1.58, 1.75), 0.19, 0.28, _mat(Color(1.0, 0.72, 0.55), 0.6, 1.3))
	shade.scale = Vector3(1.0, 1.0, 1.0)
	if not Plat.low_power():
		_light(Vector3(-3.45, 1.5, 1.85), WARM, 0.7, 3.0)
	var cols := [Color(0.95, 0.55, 0.65), Color(0.55, 0.40, 0.85), Color(1.0, 0.75, 0.45)]
	var spots := [Vector3(-2.75, 0.07, 2.6), Vector3(-2.35, 0.07, 2.95), Vector3(-2.6, 0.2, 2.82)]
	for i in 3:
		var c := _cyl(spots[i], 0.3, 0.14, _mat(cols[i], 0.95))
		c.rotation = Vector3(0.0 if i < 2 else 0.12, 0.0, 0.0 if i < 2 else -0.1)
	# a window seat where the desk used to be: cushions to sit on and watch the city
	var bench_m := _mat(Color(0.34, 0.14, 0.22), 0.6)
	_box(Vector3(1.45, 0.22, -1.72), Vector3(1.9, 0.44, 0.5), bench_m)
	_box(Vector3(1.45, 0.47, -1.72), Vector3(1.84, 0.08, 0.46), _mat(Color(0.92, 0.62, 0.72), 0.95))
	for k in 3:
		var pil := _box(Vector3(0.75 + k * 0.7, 0.63, -1.88), Vector3(0.38, 0.3, 0.12), _mat([Color(1.0, 0.78, 0.5), Color(0.6, 0.45, 0.9), Color(0.45, 0.75, 0.85)][k], 0.95))
		pil.rotation = Vector3(-0.3, 0.1 * (k - 1), 0.08 * (k - 1))
	for k in 2:
		var ws := Node3D.new()
		ws.position = Vector3(1.0 + k * 0.9, 0.0, -1.62)
		_host().add_child(ws)
		seat_nodes.append(ws)
		seat_eye.append(1.08)
		seat_swivel.append(false)
	_blockers_extra.append(Rect2(0.45, -2.1, 2.0, 0.66))
	_blockers_extra.append(Rect2(-3.95, FRONT_Z - 0.75, 0.8, 0.8))
	_blockers_extra.append(Rect2(-3.85, 1.55, 0.45, 0.4))


func _fairy(a: Vector3, b: Vector3, count: int, swags: int, drop: float, mat: Material) -> void:
	var wire: Array = []
	for i in count:
		var t := i / float(count - 1)
		var p := a.lerp(b, t)
		p.y -= drop * absf(sin(t * PI * swags))
		_sphere(p, 0.022, mat, Vector3.ONE, null, 8)
		wire.append(p)
	_cord(wire, 0.0035, Color(0.10, 0.07, 0.12))


func _plant(pos: Vector3, s: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.scale = Vector3.ONE * s
	_host().add_child(root)
	_cyl(Vector3(0, 0.1, 0), 0.11, 0.2, _mat(Color(0.75, 0.40, 0.35)), root)
	var leaf_a := _mat(Color(0.12, 0.32, 0.30), 0.7)
	var leaf_b := _mat(Color(0.20, 0.38, 0.25), 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 100.0 + pos.z * 10.0 + pos.y * 1000.0)
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf() * 0.4
		var tilt := rng.randf_range(0.5, 1.0)
		var h := rng.randf_range(0.28, 0.55)
		var lp := Vector3(cos(a) * 0.1 * tilt, 0.2 + h * 0.45, sin(a) * 0.1 * tilt)
		var leaf := _sphere(lp, 0.5, leaf_a if i % 2 == 0 else leaf_b, Vector3(0.09, h, 0.04), root)
		leaf.rotation = Vector3(0.0, -a, -0.5 * tilt)


# ---------------------------------------------------------------- lights

func _build_lights() -> void:
	window_light = _light(Vector3((WIN_X0 + WIN_X1) / 2.0, 1.7, -1.6), PINK, 2.4, 6.5)      # window glow
	var l_night := _light(Vector3(NIGHT_X, 0.95, -1.7), WARM, 1.0, 2.5)                     # nightstand lamp
	_into = study_kit
	var l_desk := _light(Vector3(2.2, 1.15, -1.7), WARM, 1.0, 2.5)                      # desk lamp
	_into = null
	var l_lantern := _light(Vector3(1.6, 2.25, 0.3), Color(1.0, 0.6, 0.35), 0.9, 3.5)     # paper lantern
	_into = study_kit
	monitor_light = _light(Vector3(1.45, 1.1, -1.3), Color(0.65, 0.40, 1.0), 0.9, 2.2)    # monitor
	_into = null
	fill_light = _light(Vector3(-0.8, 2.4, 0.9), Color(0.6, 0.25, 0.7), 0.7, 7.0)      # soft fill
	var glow := _light(Vector3(-2.6, 0.6, 0.9 + LOUNGE_DZ), Color(0.45, 0.6, 1.0), 1.0, 3.2)     # CRT glow
	glow.reparent(lounge, false)
	# things you can switch off (click the lamps, or use the PC's Lights window)
	_light_group("Nightstand lamp", [l_night], [lamp_shades[0]["mat"]], lamp_shades[0]["node"], Vector3(0.12, 0.14, 0.12))
	_light_group("Desk lamp", [l_desk], [lamp_shades[1]["mat"]], lamp_shades[1]["node"], Vector3(0.12, 0.14, 0.12))
	_light_group("Paper lantern", [l_lantern], [lantern_mat], lantern_node, Vector3(0.2, 0.2, 0.2))
	var g_fairy := _light_group("Fairy lights", [], [fairy_mat], null, Vector3.ZERO)
	var g_strip := _light_group("Ceiling strip", [], [strip_mat], null, Vector3.ZERO)
	var g_lantern := light_groups.size() - 3
	wall_switch(Vector3(1.62, 1.2, 3.35), PI, [g_strip, g_fairy, g_lantern], _host())     # inside the bedroom door


func _light_group(gname: String, omnis: Array, mats: Array, click_node: Node3D, half: Vector3) -> int:
	var entries: Array = []
	for m in mats:
		entries.append({"m": m, "e": m.emission_energy_multiplier, "a": m.albedo_color})
	light_groups.append({"name": gname, "on": true, "omnis": omnis, "mats": entries, "rockers": []})
	var gi := light_groups.size() - 1
	if click_node != null:
		interactables.append({"node": click_node, "half": half,
			"label": _light_label.bind(gi), "cb": toggle_light.bind(gi), "hover": _noop_hover, "group": "lights"})
	return gi


# the rooms' own lights (apartment.gd); they show up in the PC's Lights window too
func add_light_group(gname: String, omnis: Array, mats: Array, click_node: Node3D = null, half := Vector3.ZERO) -> int:
	return _light_group(gname, omnis, mats, click_node, half)


# a light that keeps its own state (the theater's house lights): the group just asks it
func add_light_group_fn(gname: String, get_on: Callable, set_on: Callable) -> int:
	light_groups.append({"name": gname, "on": true, "omnis": [], "mats": [], "rockers": [], "get": get_on, "set": set_on})
	return light_groups.size() - 1


# A light switch on the wall: one rocker per light group. pos is the wall's surface, yaw turns the plate's front
# (local +z) to face into the room.
func wall_switch(pos: Vector3, yaw: float, groups: Array, parent: Node3D) -> void:
	var sw := Node3D.new()
	sw.position = pos
	sw.rotation.y = yaw
	parent.add_child(sw)
	var n := groups.size()
	_box(Vector3(0, 0, 0.006), Vector3(0.075 + 0.045 * (n - 1), 0.115, 0.012), _mat(Color(0.85, 0.80, 0.88), 0.5), sw)
	for k in n:
		var gi: int = groups[k]
		var x := (k - (n - 1) / 2.0) * 0.045
		var rm := _mat(Color(0.30, 0.22, 0.36), 0.4)
		var rocker := _box(Vector3(x, 0.0, 0.016), Vector3(0.032, 0.06, 0.012), rm, sw)
		rocker.rotation.x = 0.25 if is_light_on(gi) else -0.25
		_sphere(Vector3(x, 0.045, 0.014), 0.0045, _mat(Color(1.0, 0.7, 0.3), 0.4, 1.2), Vector3.ONE, sw, 8)   # (to find it in the dark)
		(light_groups[gi]["rockers"] as Array).append(rocker)
		interactables.append({"node": rocker, "half": Vector3(0.022, 0.05, 0.04),
			"label": _light_label.bind(gi), "cb": toggle_light.bind(gi), "hover": _glow_hover(rm), "group": "lights"})


func _noop_hover(_on: bool) -> void:
	pass


func _light_label(gi: int) -> String:
	return "%s  [%s]" % [String(light_groups[gi]["name"]).to_upper(), "ON" if is_light_on(gi) else "OFF"]


func is_light_on(gi: int) -> bool:
	var g: Dictionary = light_groups[gi]
	if g.has("get"):
		return bool((g["get"] as Callable).call())
	return g["on"]


func set_light(gi: int, on: bool, from_net := false) -> void:
	var g: Dictionary = light_groups[gi]
	if g.has("set"):
		if is_light_on(gi) != on:
			(g["set"] as Callable).call(on)
		return
	if g["on"] == on:
		return
	if not from_net and _is_guest() and net_game != null:
		if not bool(guest_allow_seen.get("lights", false)):
			_net_say("The host's lights: ask them to let guests use the lights.")
			return
		shade_sync("light", [gi, on])                # the host switches it for everyone; ours flips right away
	g["on"] = on
	for l in g["omnis"]:
		if is_instance_valid(l):
			(l as Light3D).visible = on
	for e in g["mats"]:
		var m: StandardMaterial3D = e["m"]
		m.emission_energy_multiplier = e["e"] if on else 0.0
		m.albedo_color = e["a"] if on else (e["a"] as Color).darkened(0.65)
	for r in g["rockers"]:
		(r as Node3D).rotation.x = 0.25 if on else -0.25
	lights_changed.emit()
	if net_game != null and not _is_guest():
		net_game.push_state_soon()


func toggle_light(gi: int) -> void:
	set_light(gi, not is_light_on(gi))


func set_all_lights(on: bool) -> void:
	for gi in light_groups.size():
		set_light(gi, on)


# for the room state sent to guests (the groups that keep their own state are synced their own way)
func lights_state() -> Array:
	var a := []
	for g in light_groups:
		a.append(bool(g["on"]))
	return a


func apply_lights_state(a: Array) -> void:
	for gi in mini(a.size(), light_groups.size()):
		if not light_groups[gi].has("set"):
			set_light(gi, bool(a[gi]), true)

# ---------------------------------------------------------------- blackout curtains + weather

func _build_curtains() -> void:
	var wx := (WIN_X0 + WIN_X1) / 2.0
	var ww := WIN_X1 - WIN_X0
	var cz := -2.045                       # sits in the window opening, behind the blinds, so nothing in the room clips it
	var cloth := ShaderMaterial.new()
	cloth.shader = load("res://shaders/curtain.gdshader")
	cloth.set_shader_parameter("folds", ceilf(ww * 6.0))
	curtain_node = Node3D.new()
	curtain_node.name = "BlackoutCurtain"
	_host().add_child(curtain_node)
	var quad := QuadMesh.new()
	quad.size = Vector2(ww + 0.3, 1.0)
	quad.material = cloth
	var cm := MeshInstance3D.new()
	cm.mesh = quad
	cm.position = Vector3(wx, 0.0, cz)
	curtain_node.add_child(cm)
	# roller tube on top, hem bar at the bottom
	var metal := _mat(Color(0.10, 0.07, 0.14), 0.5)
	var tube := _cyl(Vector3(wx, WIN_Y1 + 0.05, cz + 0.02), 0.035, ww + 0.3, metal, curtain_node)
	tube.rotation.z = PI / 2.0
	var hem := _cyl(Vector3(wx, 0.0, cz + 0.015), 0.018, ww + 0.2, metal, curtain_node)
	hem.rotation.z = PI / 2.0
	hem.name = "Hem"
	cm.name = "Cloth"
	curtain_node.visible = false
	_update_curtain_mesh()
	# a wall switch on each side of the window
	_curtain_switch(Vector3(WIN_X0 - 0.09, 1.55, -2.0), "left")
	_curtain_switch(Vector3(WIN_X1 + 0.14, 1.75, -2.0), "right")


func _curtain_switch(pos: Vector3, side: String) -> void:
	var plate_m := _mat(Color(0.85, 0.80, 0.88), 0.5)
	var plate := _box(pos + Vector3(0, 0, 0.008), Vector3(0.07, 0.11, 0.016), plate_m)
	var rocker_m := _mat(Color(0.30, 0.22, 0.36), 0.4)
	_box(pos + Vector3(0, 0.0, 0.02), Vector3(0.035, 0.06, 0.012), rocker_m)
	var led := _mat(Color(1.0, 0.7, 0.3), 0.4, 1.2)       # faint glow so you can find it in the dark
	_sphere(pos + Vector3(0, 0.043, 0.018), 0.0045, led, Vector3.ONE, null, 8)
	curtain_switch_leds.append(led)
	interactables.append({"node": plate, "half": Vector3(0.07, 0.09, 0.06),
		"label": _curtain_label, "egg_lock": true, "cb": toggle_curtains, "hover": _glow_hover(plate_m), "group": "lights"})


func _curtain_moving() -> bool:
	return not is_equal_approx(curtain_amt, curtain_target)


func _curtain_label() -> String:
	var state: String
	if _curtain_moving():
		state = "LOWERING" if curtain_target > curtain_amt else "RAISING"
	elif curtain_amt < 0.02:
		state = "UP"
	elif curtain_amt > 0.98:
		state = "DOWN"
	else:
		state = "%d%%" % roundi(curtain_amt * 100.0)
	return "BLACKOUT CURTAINS  [%s]" % state


# Wall switches and the PC button: up -> press to lower, press while moving to stop, press again to go the other way.
func toggle_curtains() -> void:
	if egg_active:
		return
	if _curtain_moving():
		curtain_target = curtain_amt                 # stop right here
		return
	if curtain_amt < 0.001:
		curtain_target = 1.0
	elif curtain_amt > 0.999:
		curtain_target = 0.0
	else:
		curtain_target = 0.0 if curtain_last_down else 1.0    # stopped part-way: head back the way it didn't just go
	curtain_last_down = curtain_target > curtain_amt
	shade_sync("curt", curtain_target)


func set_curtain(v: float) -> void:
	if egg_active:
		return
	curtain_target = clampf(v, 0.0, 1.0)
	curtain_last_down = curtain_target > curtain_amt
	shade_sync("curt", curtain_target)


# curtains and the balcony door are the same for everyone in a room: a guest's change goes to the host (whose
# copy decides, if guests may use "lights and curtains"), and the host's state brings everyone into line
var shade_local_ms := 0

func shade_sync(what: String, v) -> void:
	if _is_guest() and net_game != null:
		shade_local_ms = Time.get_ticks_msec()
		net.send_var(1, net_game.Net.K_EVENT, {"k": "shade", "w": what, "v": v})


func _update_curtain_mesh() -> void:
	var wx := (WIN_X0 + WIN_X1) / 2.0
	var top := WIN_Y1 + 0.05
	var bottom := lerpf(top, WIN_Y0 - 0.03, curtain_amt)
	var cloth := curtain_node.get_node("Cloth") as MeshInstance3D
	cloth.scale = Vector3(1.0, maxf(top - bottom, 0.001), 1.0)
	cloth.position.y = (top + bottom) / 2.0
	var hem := curtain_node.get_node("Hem") as MeshInstance3D
	hem.position.y = bottom
	curtain_node.visible = curtain_amt > 0.002


func _build_weather() -> void:
	var flash_l := OmniLight3D.new()
	flash_l.position = Vector3((WIN_X0 + WIN_X1) / 2.0, 2.0, -1.2)
	flash_l.light_color = Color(0.75, 0.80, 1.0)
	flash_l.light_energy = 0.0
	flash_l.omni_range = 9.0
	flash_l.shadow_enabled = false
	_host().add_child(flash_l)
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(world_env, sky_mat, flash_l, city_mat)
	# every run starts with a random weather (clear, rain, snow or storm) at a random intensity
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var wm := rng.randi_range(0, 3)
	if wm != 0:
		weather.set_level(wm, rng.randf())
		weather.set_mode(wm)
	weather.snap()
	pc.setup_weather(weather, self)
	cats = load("res://cats.gd").new()
	cats.name = "Cats"
	add_child(cats)
	cats.setup(self)
	ufo = load("res://ufo.gd").new()
	ufo.name = "UFO"
	add_child(ufo)
	ufo.setup(self)
	kaiju = load("res://kaiju.gd").new()
	kaiju.name = "Kaiju"
	add_child(kaiju)
	kaiju.setup(self)
	gaboon = load("res://gaboon.gd").new()
	gaboon.name = "KingGaboon"
	add_child(gaboon)
	gaboon.setup(self)
	fight = load("res://fight.gd").new()
	fight.name = "KaijuFight"
	add_child(fight)
	fight.setup(self)
	var news: Node = load("res://news.gd").new()
	news.name = "BreakingNews"
	add_child(news)
	news.setup(self, fight)
	noir = load("res://noir.gd").new()
	noir.name = "NoirNight"
	add_child(noir)
	noir.setup(self)
	egg = TornadoEvent.new()
	egg.name = "TornadoEvent"
	add_child(egg)
	egg.setup(self)
	_build_reticle()
	padmap = PadMap.new()


# Called every frame: animates the curtain and sets how dark the room is.
func _update_lighting(delta: float) -> void:
	if not is_equal_approx(curtain_amt, curtain_target):
		curtain_amt = move_toward(curtain_amt, curtain_target, delta / 3.2)       # takes ~3 seconds to roll all the way
		_update_curtain_mesh()
	var open := 1.0 - curtain_amt          # fraction of the window still uncovered
	var cloudy := weather.overcast if weather != null else 0.0
	# daylight-ish light (window glow, ambient, soft fill) fades away with the curtain, and dims a bit with clouds
	# out of the bedroom its curtain doesn't matter: the living room and the balcony are open to the sky
	var where: String = apartment.current if apartment != null else "bedroom"
	var room_open := open if where == "bedroom" else (0.75 if where == "hallway" else 1.0)
	if where == "theater":
		room_open = 0.0 if apartment.th_dark else 0.3        # no windows in there; lights off is properly dark
	elif where in ["game", "study", "noir"]:
		room_open = 0.45                                      # inside rooms, no windows
	var sky_light := room_open * (1.0 - 0.35 * cloudy)
	world_env.ambient_light_energy = lerpf(0.05, 0.6, sky_light)
	if weather != null:
		# a big lightning strike lights up everything for a moment, a little of it even leaks past the curtains
		world_env.ambient_light_energy += weather.room_flash * 1.6 * (0.25 + 0.75 * room_open)
	window_light.light_energy = 2.4 * open * (1.0 - 0.35 * cloudy)
	fill_light.light_energy = lerpf(0.10, 0.7, open * (1.0 - 0.35 * cloudy))
	for led in curtain_switch_leds:
		led.emission = Color(1.0, 0.7, 0.3) if curtain_target > 0.5 else Color(0.4, 0.8, 1.0)
	if weather != null:
		weather.window_open = room_open
		var snd := 1.0 - curtain_amt * curtain_amt      # a half-closed curtain still lets most of the weather sound through
		match where:
			"balcony": snd = 1.0
			"living": snd = lerpf(0.9, 0.3, apartment.bal_shut if apartment != null else 0.0)     # the balcony door shut: quieter
			"hallway": snd = lerpf(0.45, 0.2, apartment.bal_shut if apartment != null else 0.0)
		weather.sound_open = snd


# ---------------------------------------------------------------- player

func _make_hand(tracker_name: String) -> XRController3D:
	var c := XRController3D.new()
	c.tracker = tracker_name
	origin.add_child(c)
	_sphere(Vector3.ZERO, 0.035, _mat(Color(1.0, 0.7, 0.9), 0.5, 2.5), Vector3.ONE, c)
	return c


func _setup_player() -> void:
	origin = XROrigin3D.new()
	origin.name = "XROrigin3D"
	origin.position = Vector3(0.2, 0.0, 1.0)
	add_child(origin)

	var xr_cam := XRCamera3D.new()
	origin.add_child(xr_cam)
	left_hand = _make_hand("left_hand")
	right_hand = _make_hand("right_hand")
	left_hand.button_pressed.connect(_on_button.bind(0))
	right_hand.button_pressed.connect(_on_button.bind(1))
	left_hand.button_released.connect(_on_button_released.bind(0))
	right_hand.button_released.connect(_on_button_released.bind(1))
	laser_l = _make_laser(left_hand)
	laser_r = _make_laser(right_hand)
	hint_label = Label3D.new()
	hint_label.font_size = 48
	hint_label.pixel_size = 0.0009
	hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint_label.no_depth_test = true
	hint_label.modulate = Color(1.0, 0.9, 1.0)
	hint_label.outline_modulate = Color(0.2, 0.05, 0.3)
	hint_label.visible = false
	_host().add_child(hint_label)

	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		xr_active = true
		head = xr_cam
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		if Plat.is_android():
			_tune_quest_xr(xr)
		sit_label.text = "Sit  (A or trigger)"
		print("OpenXR active - put the headset on.")
	else:
		# No headset: fall back to a flat WASD + mouse view so you can still test the room.
		xr_cam.queue_free()
		left_hand.visible = false
		right_hand.visible = false
		desktop_cam = Camera3D.new()
		desktop_cam.position = Vector3(0, 1.6, 0)
		desktop_cam.current = true
		origin.add_child(desktop_cam)
		head = desktop_cam
		var hud := CanvasLayer.new()
		add_child(hud)
		var dot := ColorRect.new()
		dot.color = Color(1, 1, 1, 0.8)
		dot.size = Vector2(6, 6)
		dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		hud.add_child(dot)
		print("OpenXR not available - desktop mode (click to look, WASD to move, Esc to release mouse).")
		_apply_fullscreen_setting()


# True while the TV is really showing a video or a running game and the view is pointed at the glass.
var arcade_focus: ScreenUI


func _arcade_playing() -> bool:
	return slot_cart == "neo" and emu != null and emu.state == Emu.State.RUNNING and not ctl_open


func _aim_at_playing_tv() -> bool:
	if desktop_cam == null:
		return false
	if arcade_focus != null and _arcade_playing() and _aim_hits(arcade_focus):
		return true                 # a game is running on the arcade monitor: no dot over it
	if tv_screen_ui == null or not vcr.tv_on:
		return false
	var playing := false
	if console_on:
		playing = (emu != null and emu.state == Emu.State.RUNNING and not ctl_open) or (slot_cart == "egg" and not ctl_open)
	else:
		playing = vcr.state == vcr.State.PLAYING and not vcr._paused_flag
	if not playing:
		return false
	return _aim_hits(tv_screen_ui)


# true when the desktop view is looking at this screen
func _aim_hits(ui: ScreenUI) -> bool:
	var xf := ui.global_transform
	var n := xf.basis.z.normalized()
	var o := desktop_cam.global_position
	var d := -desktop_cam.global_transform.basis.z
	var den := d.dot(n)
	if den > -0.0001:
		return false
	var t := (xf.origin - o).dot(n) / den
	if t < 0.0 or t > 12.0:
		return false
	var l := xf.affine_inverse() * (o + d * t)
	return absf(l.x) <= ui.screen_size.x * 0.5 and absf(l.y) <= ui.screen_size.y * 0.5


func _process(delta: float) -> void:
	pad_hint_t = maxf(0.0, pad_hint_t - delta)
	book_hint_t = maxf(0.0, book_hint_t - delta)
	if leave_prompt:
		leave_t -= delta
		if leave_t <= 0.0 or head.global_position.distance_to(leave_panel.global_position) > 3.0:
			_cancel_leave()          # walked away or waited too long: the sign goes
	if reticle != null:
		reticle.visible = reticle_on and not xr_active and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or pad_in_use) and not game_mode and not _aim_at_playing_tv() and not (hover_screen != null and hover_screen.cursor_allowed) and not hover_item.get("no_reticle", false)
		reticle.hot = not hover_item.is_empty() or (hover_screen != null and hover_screen.cursor_allowed)
	_room_pad_tick(delta)
	_update_held_pad(delta)
	_update_book(delta)
	if emu != null:
		var gv: int = arcade_volume if slot_cart == "neo" else vcr.tv_volume
		emu.set_volume(float(gv) / 10.0 if (vcr.tv_on or slot_cart == "neo") else 0.0)
		emu.set_bus("Arcade" if slot_cart == "neo" else "Console")
		if game_mode:
			_pad_tick(delta)
			if not xr_active and not Input.get_connected_joypads().is_empty():
				var down := Input.is_joy_button_pressed(Input.get_connected_joypads()[0], JOY_BUTTON_RIGHT_STICK)
				if down and not _pad_stick_prev:
					_put_pad()
				_pad_stick_prev = down
	_recliner_tick(delta)
	if not seated and not sleeping and apartment != null:
		# walking up and down the theater's steps
		var fy: float = apartment.floor_y(head.global_position.x, head.global_position.z)
		if absf(origin.global_position.y - fy) > 0.001:
			origin.global_position.y = move_toward(origin.global_position.y, fy, delta * 1.6)
	_update_lighting(delta)
	_update_focus_anim(delta)
	_update_pointer(delta)
	var near_idx := -1 if seated else _nearest_seat()
	sit_label.visible = near_idx >= 0
	if near_idx >= 0:
		sit_label.global_position = seat_nodes[near_idx].global_position + Vector3(0.0, seat_eye[near_idx] + 0.15, 0.0)
		var sd := sit_label.global_position.distance_to(head.global_position)
		sit_label.scale = Vector3.ONE * clampf(sd / 1.5, 0.25, 1.0)
	if seated and seat_swivel[cur_seat]:
		# the chair swivels to follow where you look
		var fwd := -head.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() > 0.2:
			var node := seat_nodes[cur_seat]
			node.global_rotation.y = lerp_angle(node.global_rotation.y, atan2(-fwd.x, -fwd.z), clampf(4.0 * delta, 0.0, 1.0))
	if konami_t > 0.0:
		konami_t -= delta
		if konami_t <= 0.0:
			konami_progress = 0
	if xr_active:
		var stick := left_hand.get_vector2("primary")
		var kd := ""
		if stick.length() > 0.7:
			if absf(stick.y) > absf(stick.x):
				kd = "U" if stick.y > 0.0 else "D"
			else:
				kd = "R" if stick.x > 0.0 else "L"
		if kd != _stick_dir:
			_stick_dir = kd
			if kd != "":
				_konami_feed(kd)
		if stick.length() > DEADZONE and not seated and not game_mode:
			if focus_level > 0:
				focus_level = 0          # walking away ends the close-up view
				focus_screen = null
			var yaw := head.global_rotation.y
			var dir := Vector3(stick.x, 0.0, -stick.y).rotated(Vector3.UP, yaw)
			if left_hand.is_button_pressed("primary_click") and not _run_click:
				_running = not _running                      # click the stick in to walk faster (until you stop)
			_run_click = left_hand.is_button_pressed("primary_click")
			_try_move(dir * (RUN_SPEED if _running else MOVE_SPEED) * delta)
		elif stick.length() <= DEADZONE:
			_running = false
		var turn := 0.0 if game_mode else right_hand.get_vector2("primary").x
		if absf(turn) < 0.5:
			snap_ready = true
		elif snap_ready:
			snap_ready = false
			_snap_turn(-signf(turn) * SNAP_ANGLE)
	else:
		var v := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W): v.y += 1.0
		if Input.is_physical_key_pressed(KEY_S): v.y -= 1.0
		if Input.is_physical_key_pressed(KEY_D): v.x += 1.0
		if Input.is_physical_key_pressed(KEY_A): v.x -= 1.0
		if v != Vector2.ZERO and not seated and not game_mode:
			v = v.normalized()
			if focus_level > 0:
				_end_focus(false)
			var yaw := desktop_cam.global_rotation.y
			var run := Input.is_physical_key_pressed(KEY_SHIFT)            # hold Shift to walk faster
			_try_move(Vector3(v.x, 0.0, -v.y).rotated(Vector3.UP, yaw) * (RUN_SPEED if run else MOVE_SPEED) * delta)


# ---- a gamepad (DualSense, DualShock, Xbox...) in the room on a PC
# left stick walks, right stick looks; R2 or CROSS / A is the click; CIRCLE / B sits and stands (or puts a
# controller or book down); TRIANGLE / Y zooms like V; SQUARE / X puts a book down; L1 / R1 and the d-pad
# left / right turn pages; d-pad up / down scrolls a screen. While you hold a console pad the gamepad plays.
const PAD_LOOK_SPEED := 2.4            # radians a second at full tilt
const PAD_DEAD := 0.18
var pad_in_use := false                # the gamepad moved recently (shows the crosshair without the mouse)
var _pad_prev := {}
var _pad_idle := 0.0


func _room_pad_tick(delta: float) -> void:
	if xr_active or padmap == null:
		return
	var d := padmap.pad_device()
	if d < 0:
		pad_in_use = false
		return
	var ls := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
	var rs := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
	ls = Vector2.ZERO if ls.length() < PAD_DEAD else ls * ((ls.length() - PAD_DEAD) / (1.0 - PAD_DEAD)) / ls.length()
	rs = Vector2.ZERO if rs.length() < PAD_DEAD else rs * ((rs.length() - PAD_DEAD) / (1.0 - PAD_DEAD)) / rs.length()
	var any := ls != Vector2.ZERO or rs != Vector2.ZERO
	_pad_idle = 0.0 if any else _pad_idle + delta
	if any:
		pad_in_use = true
	if game_mode or sleeping:
		_pad_edges(d, true)                 # the console has the gamepad; only keep the edge state current
		return
	# look
	if rs != Vector2.ZERO and cam_t >= 1.0:
		desktop_cam.rotation.y -= rs.x * PAD_LOOK_SPEED * delta
		pitch = clampf(pitch - rs.y * PAD_LOOK_SPEED * 0.75 * delta, -1.2, 1.2)
		desktop_cam.rotation.x = pitch
	# walk
	if ls != Vector2.ZERO and not seated:
		if focus_level > 0:
			_end_focus(false)
		var yaw := desktop_cam.global_rotation.y
		if Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_STICK) and not _run_click:
			_running = not _running                          # click the left stick in to walk faster (until you stop)
		_run_click = Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_STICK)
		_try_move(Vector3(ls.x, 0.0, ls.y).rotated(Vector3.UP, yaw) * (RUN_SPEED if _running else MOVE_SPEED) * delta)
	elif ls == Vector2.ZERO:
		_running = false
	_pad_edges(d, false)


func _pad_edges(d: int, quiet: bool) -> void:
	var now := {
		"click": Input.is_joy_button_pressed(d, JOY_BUTTON_A) or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5,
		"back": Input.is_joy_button_pressed(d, JOY_BUTTON_B),
		"zoom": Input.is_joy_button_pressed(d, JOY_BUTTON_Y),
		"drop": Input.is_joy_button_pressed(d, JOY_BUTTON_X),
		"next": Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER) or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT),
		"prev": Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT),
		"up": Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP),
		"down": Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN),
	}
	var was := _pad_prev
	_pad_prev = now
	if quiet:
		return
	var pressed := func(k: String) -> bool: return bool(now[k]) and not bool(was.get(k, true))
	if bool(now["click"]) != bool(was.get("click", false)):
		if now["click"]:
			pad_in_use = true
			_pointer_press(2)
		else:
			_pointer_release(2)
	if pressed.call("back"):
		if held_book != null:
			_put_book()
		elif diary != null and diary.open_book:
			put_diary()
		else:
			_toggle_sit()
	if pressed.call("drop"):
		if held_book != null:
			_put_book()
		elif diary != null and diary.open_book:
			put_diary()
	if pressed.call("zoom"):
		if held_book != null:
			toggle_book_zoom()
		else:
			_cycle_view()
	if pressed.call("next") and held_book != null:
		_book_page(1)
	if pressed.call("prev") and held_book != null:
		_book_page(-1)
	if hover_screen != null:
		if pressed.call("up"):
			hover_screen.send_scroll(hover_pos, true)
		if pressed.call("down"):
			hover_screen.send_scroll(hover_pos, false)
	elif not hover_item.is_empty() and hover_item.has("player"):
		if pressed.call("up"):
			player_scroll(int(hover_item["player"]), true)
		if pressed.call("down"):
			player_scroll(int(hover_item["player"]), false)


func _unhandled_input(event: InputEvent) -> void:
	if xr_active:
		return
	if event is InputEventKey and not event.pressed and event.keycode == KEY_T and net_voice != null:
		net_voice.talking = false
	if pc != null and pc.ct_wants_key(event):
		get_viewport().set_input_as_handled()
		return
	if ctl_open and ctl_listen != "" and ctl_dev == "key" and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.keycode == KEY_ESCAPE:
			ctl_listen = ""
			_ctl_block = 0.35
			_ctl_draw()
		else:
			_ctl_bind("k:%d" % int(event.physical_keycode))
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ksym := ""
		match event.keycode:
			KEY_UP: ksym = "U"
			KEY_DOWN: ksym = "D"
			KEY_LEFT: ksym = "L"
			KEY_RIGHT: ksym = "R"
			KEY_B: ksym = "B"
			KEY_A: ksym = "A"
		if ksym != "":
			_konami_feed(ksym)
		if event.keycode == KEY_E:
			if game_mode:
				_put_pad()
			else:
				_toggle_sit()
		elif held_book != null and event.keycode == KEY_G:
			_put_book()
		elif diary != null and diary.open_book and event.keycode == KEY_G:
			put_diary()
		elif held_book != null and (event.keycode == KEY_RIGHT or event.keycode == KEY_PAGEDOWN):
			_book_page(1)
		elif held_book != null and (event.keycode == KEY_LEFT or event.keycode == KEY_PAGEUP):
			_book_page(-1)
		elif event.keycode == KEY_V:
			if held_book != null:
				toggle_book_zoom()
			else:
				_cycle_view()
		elif event.keycode == KEY_M:
			if game_mode and emu != null:
				emu.to_menu()          # back to the game list without taking the cart out
			elif net_voice != null and net != null and net.is_online():
				net_voice.set_mic_on(not net_voice.mic_on)
				updater.show_toast("Microphone %s" % ("on" if net_voice.mic_on else "muted"), 2.0)
		elif event.keycode == KEY_T and net_voice != null:
			net_voice.talking = true
		elif event.keycode == KEY_Q:
			if not egg_active and not game_mode:
				vcr.cycle_aspect()
		elif event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			set_fullscreen(not fullscreen)
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pointer_press(2)
			else:
				_pointer_release(2)
		elif event.pressed and hover_screen != null:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				hover_screen.send_scroll(hover_pos, true)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				hover_screen.send_scroll(hover_pos, false)
		elif event.pressed and not hover_item.is_empty() and hover_item.has("player") and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			player_scroll(int(hover_item["player"]), event.button_index == MOUSE_BUTTON_WHEEL_UP)
		elif event.pressed and held_book != null:
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_book_page(1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_book_page(-1)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and cam_t >= 1.0:
		pad_in_use = false
		desktop_cam.rotation.y -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -1.2, 1.2)
		desktop_cam.rotation.x = pitch


# Konami code: up up down down left right left right B A, entered while the console is on and the TV is showing it.
func _konami_feed(sym: String) -> bool:
	if egg_active or sleeping or not console_on or not vcr.tv_on or egg == null or slot_cart != "egg":
		konami_progress = 0
		return false
	if sym == KONAMI[konami_progress]:
		konami_progress += 1
		konami_t = 2.5
		if konami_progress >= KONAMI.size():
			konami_progress = 0
			konami_t = 0.0
			if updated_this_session:                  # the running room is out of date until you nap: the egg stays locked
				updater.show_toast("Something feels off after that update... take a nap in the bed first.", 6.0)
			else:
				egg.start()
		return true
	konami_progress = 1 if sym == "U" else 0
	konami_t = 2.5 if konami_progress > 0 else 0.0
	return false


func _walkable(x: float, z: float) -> bool:
	if x < ROOM_X_MIN or x > ROOM_HALF.x or z < -ROOM_HALF.y or z > FRONT_Z - 0.25:
		if apartment == null or not apartment.walkable(x, z):        # out of the bedroom: the rest of the flat
			return false
	else:
		for r in BLOCKERS:
			if r.has_point(Vector2(x, z)):
				return false
		for r in _blockers_extra:
			if r.has_point(Vector2(x, z)):
				return false
	if arcade_kit != null:
		var ak := arcade_kit.to_local(Vector3(x, 0.0, z))
		if ARCADE_BLOCK.has_point(Vector2(ak.x, ak.z)):
			return false
	if study_kit != null:
		var sk := study_kit.to_local(Vector3(x, 0.0, z))
		for r in STUDY_BLOCKS:
			if (r as Rect2).has_point(Vector2(sk.x, sk.z)):
				return false
	if lounge != null:
		var l := lounge.to_local(Vector3(x, 0.0, z))
		for r in LOUNGE_BLOCKERS:
			if r.has_point(Vector2(l.x, l.z)):
				return false
	if recliner != null:
		var rc := Vector2(recliner.global_position.x, recliner.global_position.z)
		var fwd := Vector2(-sin(recliner.rotation.y), -cos(recliner.rotation.y))
		if Vector2(x, z).distance_to(rc) < 0.55 or (recliner.reclined and Vector2(x, z).distance_to(rc + fwd * 0.55) < 0.4):
			return false
	for i in beanbags.size():
		if beanbags[i].visible and Vector2(x, z).distance_to(Vector2(beanbags[i].global_position.x, beanbags[i].global_position.z)) < 0.55:
			return false
	return true


func _try_move(motion: Vector3) -> void:
	var p := head.global_position
	# something ended up on top of me (a seat appeared, a friend swung the recliner round): never lock me in,
	# let me walk out of it
	var stuck := not _walkable(p.x, p.z)
	if _walkable(p.x + motion.x, p.z) or (stuck and _in_room(p.x + motion.x, p.z)):
		origin.global_position.x += motion.x
		p.x += motion.x
	if _walkable(p.x, p.z + motion.z) or (stuck and _in_room(p.x, p.z + motion.z)):
		origin.global_position.z += motion.z


func _in_room(x: float, z: float) -> bool:
	if apartment != null and apartment.in_bounds(x, z):
		return true
	return x >= ROOM_X_MIN and x <= ROOM_HALF.x and z >= -ROOM_HALF.y and z <= FRONT_Z - 0.25


# if I'm standing inside something, step to the nearest clear spot
func _unstick() -> void:
	if seated or head == null:
		return
	var p := head.global_position
	if _walkable(p.x, p.z):
		return
	for ring in range(1, 25):                    # 5 cm rings out to 1.2 m
		var r := ring * 0.05
		var steps := 8 + ring * 2
		for k in steps:
			var a := TAU * k / steps
			var x := p.x + cos(a) * r
			var z := p.z + sin(a) * r
			if _walkable(x, z):
				origin.global_position.x += x - p.x
				origin.global_position.z += z - p.z
				return


func _snap_turn(deg: float) -> void:
	var pivot := head.global_position
	pivot.y = 0.0
	origin.global_translate(-pivot)
	origin.global_rotate(Vector3.UP, deg_to_rad(deg))
	origin.global_translate(pivot)


# ---------------------------------------------------------------- beanbag

# One beanbag when you're alone; more appear as friends join. They sit in a fan in front of the corner TV:
# alone you sit straight in front; two sit side by side with nobody in the middle; three are one in front
# and one each side; four make a quarter circle. Spots are world x/z, every seat turns to face the screen.
const BEANBAG_LAYOUTS := [
	[Vector2(-1.5, 1.0)],
	[Vector2(-1.0, 1.8), Vector2(-1.95, 0.9)],
	[Vector2(-0.8, 2.0), Vector2(-1.49, 0.99), Vector2(-2.5, 0.84)],
	[Vector2(-0.6, 2.8), Vector2(-0.9, 1.85), Vector2(-1.55, 1.0), Vector2(-2.5, 0.84)],
]
const BEANBAG_COLORS := [Color(0.95, 0.45, 0.58), Color(0.56, 0.36, 0.80), Color(0.35, 0.55, 0.95), Color(1.0, 0.72, 0.42)]
var beanbags: Array[Node3D] = []


func _build_beanbags() -> void:
	for i in 4:
		var root := Node3D.new()
		_host().add_child(root)
		seat_nodes.append(root)
		seat_eye.append(0.95)
		seat_swivel.append(false)
		# the root is the sitting spot (in the bowl); the ball itself sits a little behind it
		var ball := BeanbagModel.build(root, Vector3(0.0, 0.0, 0.14), 0.0, BEANBAG_COLORS[i])
		ball.scale = Vector3.ONE * 1.12
		beanbags.append(root)
	set_beanbag_count(1)


# ---- the recliner on the rug: swivels in 45 degree steps, leans back, starts facing the window

const RECLINER_POS := Vector3(-3.2, 0.0, -1.45)    # in the corner by the window, where the dresser used to be
const RECLINER_YAW := -PI / 4.0                     # turned to look out of the window from the side
var recliner: Node3D
var recliner_seat := -1
var _rec_base_y := 0.0
var _rec_view_k := 0.0


func _build_recliner() -> void:
	recliner = load("res://recliner.gd").new()
	recliner.name = "Recliner"
	recliner.position = RECLINER_POS
	_host().add_child(recliner)
	recliner.build()
	recliner.rotation.y = RECLINER_YAW
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK and int(cfg.get_value("room", "recliner_v", 1)) >= 2:   # (it moved: start in the new spot once)
		recliner.rotation.y = float(cfg.get_value("room", "recliner_yaw", RECLINER_YAW))
		recliner.reclined = bool(cfg.get_value("room", "recliner_back", false))
	recliner_seat = seat_nodes.size()
	seat_nodes.append(recliner)
	seat_eye.append(0.98)
	seat_swivel.append(false)
	recliner.turned.connect(_on_recliner_turned)
	for side in [-1, 1]:
		var sd: int = side
		interactables.append({"node": recliner.arm_node(sd), "half": Vector3(0.12, 0.1, 0.12), "guest_ok": true,
			"label": func() -> String: return "TURN THE RECLINER  " + ("LEFT" if sd < 0 else "RIGHT"),
			"when": func() -> bool: return not _recliner_taken(),
			"cb": func() -> void: recliner.turn(-1 if sd < 0 else 1)})
	interactables.append({"node": recliner.lever_node(), "half": Vector3(0.06, 0.12, 0.08), "guest_ok": true,
		"when": func() -> bool: return not _recliner_taken(),
		"label": func() -> String: return "SIT UP" if recliner.reclined else "LEAN BACK",
		"cb": func() -> void:
			recliner.toggle_recline()
			_save_recliner()
			_rec_report(recliner.rotation.y, true)})


# Noir Night's grey visitor is sitting in it
func _recliner_taken() -> bool:
	return false                                  # (the Noir visitor has an office of his own now)


func _on_recliner_turned(dy: float) -> void:
	_save_recliner.call_deferred()
	_rec_report(recliner.rotation.y + dy, true)
	if not (seated and cur_seat == recliner_seat):
		return
	# turning in it turns you with it
	if xr_active:
		var pivot := head.global_position
		pivot.y = 0.0
		var tw := create_tween()
		var done := [0.0]
		tw.tween_method(func(k: float) -> void:
			var step: float = dy * k - float(done[0])
			done[0] = dy * k
			origin.global_translate(-pivot)
			origin.global_rotate(Vector3.UP, step)
			origin.global_translate(pivot), 0.0, 1.0, 0.45)
	else:
		var tw2 := create_tween()
		tw2.tween_property(desktop_cam, "rotation:y", desktop_cam.rotation.y + dy, 0.45).set_trans(Tween.TRANS_SINE)


# the chair swivels round with you: turn your view (mouse, stick, snap turn or your head) and it turns too.
# In a headset it lets you glance around a little first, so it isn't twitching with every look.
const REC_FOLLOW_SLACK := 0.4          # radians of head turn before the chair comes round (headset only)
var _rec_following := false

func _recliner_follow(delta: float) -> void:
	if recliner._turning:
		return                                       # the arm buttons are already turning it (and you with it)
	var fwd := -head.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return                                       # looking straight up or down: no heading to follow
	var yaw := atan2(-fwd.x, -fwd.z)
	var diff := angle_difference(recliner.rotation.y, yaw)
	if xr_active and not _rec_following:
		if absf(diff) < REC_FOLLOW_SLACK:
			return
		_rec_following = true
	if absf(diff) < 0.01:
		_rec_following = false
		return
	recliner.rotation.y = lerp_angle(recliner.rotation.y, yaw, 1.0 - exp(-(6.0 if xr_active else 12.0) * delta))
	_rec_report(recliner.rotation.y, false)


# ---- everyone in a room sees the same recliner: the host's copy is the real one and goes out with the room
# state; a guest who turns it, swivels in it or leans it back tells the host. Whoever's sitting in it steers.
const NetSession := preload("res://net_session.gd")
var _rec_target := NAN                # a turn that came over the network, eased into
var _rec_sent_ms := 0
var _rec_local_ms := -100000          # when I last moved it myself (the room state lags behind that a little)
var _rec_sent_yaw := NAN
var _rec_sent_back := false

func _in_recliner() -> bool:
	return seated and cur_seat == recliner_seat


func _rec_report(yaw: float, now: bool) -> void:
	_rec_local_ms = Time.get_ticks_msec()
	if net == null or not net.is_online() or net.is_host():
		return                                       # (the host's chair goes out with the room state)
	var t := Time.get_ticks_msec()
	if not now and t - _rec_sent_ms < 100:
		return
	if not now and is_equal_approx(yaw, _rec_sent_yaw) and recliner.reclined == _rec_sent_back:
		return
	_rec_sent_ms = t
	_rec_sent_yaw = yaw
	_rec_sent_back = recliner.reclined
	net.send_var(1, NetSession.K_EVENT, {"k": "rec", "y": wrapf(yaw, -PI, PI), "b": recliner.reclined})


# host: what goes out in the room state
func recliner_state() -> Array:
	if recliner == null:
		return []
	var y := recliner.rotation.y if is_nan(_rec_target) else _rec_target
	return [snappedf(wrapf(y, -PI, PI), 0.001), recliner.reclined]


# host: a guest moved it
func recliner_from_guest(d: Dictionary) -> void:
	if recliner == null or _in_recliner() or _recliner_taken():
		return                                       # I'm in it (or the Noir visitor is): I steer
	var y := float(d.get("y", 0.0))
	if is_nan(y) or is_inf(y):
		return
	_rec_target = wrapf(y, -PI, PI)
	recliner.reclined = bool(d.get("b", false))


# guest: the host's room state
func recliner_from_host(s) -> void:
	if recliner == null or not (s is Array) or s.size() < 2:
		return
	if _in_recliner() or Time.get_ticks_msec() - _rec_local_ms < 1500:
		return                                       # I'm steering it, or the host hasn't heard my last move yet
	var y := float(s[0])
	if is_nan(y) or is_inf(y):
		return
	_rec_target = y
	recliner.reclined = bool(s[1])


# eases a turn that came over the network
func _rec_net_tick(delta: float) -> void:
	if recliner == null or is_nan(_rec_target):
		return
	if _in_recliner() or recliner._turning:
		_rec_target = NAN
		return
	var d := angle_difference(recliner.rotation.y, _rec_target)
	if absf(d) < 0.002:
		recliner.rotation.y = _rec_target
		_rec_target = NAN
		_unstick()                                   # a friend swung it round onto me
		return
	recliner.rotation.y = lerp_angle(recliner.rotation.y, _rec_target, 1.0 - exp(-8.0 * delta))


func _save_recliner() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	cfg.set_value("room", "recliner_yaw", wrapf(recliner.rotation.y, -PI, PI))
	cfg.set_value("room", "recliner_back", recliner.reclined)
	cfg.set_value("room", "recliner_v", 2)
	cfg.save(SETTINGS_FILE)


# sitting down in it: face the way it faces; leaning back lowers you a little and tips the view up
func _recliner_tick(delta: float) -> void:
	_rec_net_tick(delta)
	if recliner == null or not seated or cur_seat != recliner_seat:
		_rec_view_k = 0.0
		return
	_recliner_follow(delta)
	var k: float = recliner.recline_amount()
	origin.global_position.y = _rec_base_y - 0.1 * k
	if not xr_active:
		pitch += (0.22 * k - 0.22 * _rec_view_k)
		pitch = clampf(pitch, -1.2, 1.2)
		desktop_cam.rotation.x = pitch
	_rec_view_k = k


func set_beanbag_count(n: int) -> void:
	n = clampi(n, 1, beanbags.size())
	var layout: Array = BEANBAG_LAYOUTS[n - 1]
	var screen: Vector3 = (beanbags[0].get_parent() as Node3D).to_local(tv_root.to_global(Vector3(0.0, 0.0, 0.225)))
	for i in beanbags.size():
		beanbags[i].visible = i < n
		if i < n:
			var sp: Vector2 = layout[i]
			beanbags[i].position = Vector3(sp.x, 0.0, sp.y)
			beanbags[i].rotation.y = atan2(-(screen.x - sp.x), -(screen.z - sp.y))     # local -z looks at the screen
	# the seats moved: if I'm in one, I go with it (or stand up if it went away); if one landed on me, step off it
	if seated and cur_seat >= 0 and cur_seat < seat_nodes.size() and seat_nodes[cur_seat] in beanbags:
		var sn := seat_nodes[cur_seat]
		if not sn.visible:
			_toggle_sit()
		else:
			var hp := head.global_position
			origin.global_position.x += sn.global_position.x - hp.x
			origin.global_position.z += sn.global_position.z - hp.z
	_unstick.call_deferred()


# ---------------------------------------------------------------- door (front wall)

func _build_door() -> void:
	# the bedroom side of the doorway out to the hallway; the door itself (it swings out into the hallway by
	# itself as you walk up) and the front door with its "Leave?" sign are in apartment.gd
	var trim := _mat(Color(0.20, 0.07, 0.22), 0.7)
	var x := 0.9
	var fz := FRONT_Z
	_box(Vector3(x - 0.5, 1.07, fz - 0.035), Vector3(0.07, 2.14, 0.07), trim)     # jambs
	_box(Vector3(x + 0.5, 1.07, fz - 0.035), Vector3(0.07, 2.14, 0.07), trim)
	_box(Vector3(x, 2.14, fz - 0.035), Vector3(1.07, 0.07, 0.07), trim)           # header


func _ask_leave() -> void:
	if egg_active:
		return
	leave_prompt = true
	leave_t = 15.0
	leave_panel.visible = true


func _cancel_leave() -> void:
	leave_prompt = false
	leave_panel.visible = false


func _do_leave() -> void:
	leave_prompt = false
	leave_panel.visible = false
	if emu != null:
		emu._stop_host()                      # the running game saves its place first
	_save_prefs_tick()
	pc.save_music_dir()
	get_tree().quit()


# ---------------------------------------------------------------- sleep: the bed installs a waiting update and wakes you in the new room

var sleeping := false
var dry_relaunch := false             # tests: print the restart command instead of running it
var relaunch_extra := PackedStringArray()   # tests: extra start-up flags for the new copy
var _sleep_veil: MeshInstance3D
var _sleep_mat: StandardMaterial3D
var _sleep_text: Label3D


func _bed_sleep_spot() -> void:
	# the Sleep prompt sits up by the pillows ...
	var slab := _box(Vector3(BED_POS.x, 0.63, -1.55), Vector3(1.5, 0.16, 0.7), _mat(Color.WHITE), null)
	slab.visible = false
	interactables.append({"node": slab, "half": Vector3(0.75, 0.08, 0.35), "egg_lock": true,
		"when": func() -> bool: return not sleeping and not egg_active and updater != null and not updater.busy(),
		"label": "Nap", "cb": _go_to_sleep})
	# ... and the make-the-bed prompt down by the foot, only while the bed is a mess
	var foot := _box(Vector3(BED_POS.x, 0.63, -0.45), Vector3(1.5, 0.16, 0.9), _mat(Color.WHITE), null)
	foot.visible = false
	interactables.append({"node": foot, "half": Vector3(0.75, 0.08, 0.45),         # never locked, not even during the easter egg
		"when": func() -> bool: return not bed_made and not sleeping,
		"label": "If you want to change the world,\nstart off by making your bed, bud.", "cb": _make_bed})


func _make_sleep_veil() -> void:
	if _sleep_veil != null and is_instance_valid(_sleep_veil):
		_sleep_veil.queue_free()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	_sleep_mat = StandardMaterial3D.new()
	_sleep_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sleep_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sleep_mat.cull_mode = BaseMaterial3D.CULL_FRONT          # we see the inside of the ball around the head
	_sleep_mat.no_depth_test = true
	_sleep_mat.render_priority = 100
	_sleep_mat.albedo_color = Color(0.02, 0.0, 0.06, 0.0)
	_sleep_veil = MeshInstance3D.new()
	_sleep_veil.mesh = sm
	_sleep_veil.material_override = _sleep_mat
	_sleep_veil.extra_cull_margin = 16.0
	head.add_child(_sleep_veil)
	_sleep_text = Label3D.new()
	_sleep_text.text = "Napping..."
	_sleep_text.font_size = 48
	_sleep_text.pixel_size = 0.0008
	_sleep_text.no_depth_test = true
	_sleep_text.render_priority = 101
	_sleep_text.modulate = Color(0.95, 0.85, 1.0, 0.0)
	_sleep_text.position = Vector3(0, 0, -0.3)
	_sleep_veil.add_child(_sleep_text)


func _fade_veil(to: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void:
		_sleep_mat.albedo_color.a = a
		_sleep_text.modulate.a = a
		_sleep_text.outline_modulate.a = a, _sleep_mat.albedo_color.a, to, secs)     # the outline too, or dark letters stay behind
	await tw.finished
	if to <= 0.0 and _sleep_veil != null and is_instance_valid(_sleep_veil):
		_sleep_veil.visible = false


# a nap from somewhere else (Noir Night's third whiskey), with its own words on the way out
func go_to_sleep(message: String) -> void:
	_nap_message = message
	_go_to_sleep()


var _nap_message := ""


func _go_to_sleep() -> void:
	if sleeping or egg_active or updater == null or updater.busy():
		return
	sleeping = true
	_make_sleep_veil()
	await _fade_veil(1.0, 1.4)
	if updater.state == "available":            # a waiting update installs while you nap
		updater.install()
		while updater.busy():
			await updater.changed
		if updater.state != "done":
			_sleep_text.text = "Could not install the update"
			await get_tree().create_timer(1.6).timeout
			await _fade_veil(0.0, 1.0)
			sleeping = false
			updater.show_toast(updater.message if updater.state == "error" else "There was nothing to install.")
			return
	_sleep_text.text = "Waking up from your nap in the new room..." if updater.state == "done" else ("Waking up from your nap..." if _nap_message == "" else _nap_message)
	if emu != null:
		emu._stop_host()                      # the running game saves its place first
	bed_made = false                          # you slept in it, so the new room has an unmade bed
	_save_prefs_tick()
	pc.save_music_dir()
	await get_tree().create_timer(0.9).timeout
	if updater.state != "done" and not updated_this_session and not dry_relaunch:
		# nothing new to load: the room just starts over inside this run (no second copy of the program needed)
		_nap_message = ""
		get_tree().reload_current_scene.call_deferred()
		return
	if not await _relaunch():
		_sleep_text.text = "Could not restart the room"
		bed_made = true
		_save_prefs_tick()
		await get_tree().create_timer(1.6).timeout
		await _fade_veil(0.0, 1.0)
		sleeping = false
		_nap_message = ""
		updater.show_toast("Couldn't reopen the room by itself. Close it and open it again (the update is installed).", 8.0)


# Starts a fresh copy of the room (same display / VR options) and closes this one.
func _relaunch() -> bool:
	if not Plat.can_spawn_programs() and not dry_relaunch:
		# a headset app can't start a second copy of itself, so the room starts over inside this run instead
		get_tree().reload_current_scene.call_deferred()
		return true
	var args := PackedStringArray()
	if FileAccess.file_exists("res://project.godot"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	var drv := ""
	if RenderingServer.has_method("get_current_rendering_driver_name"):          # newer Godot versions only
		drv = str(RenderingServer.call("get_current_rendering_driver_name"))
	if drv != "":
		args.append_array(["--rendering-driver", drv])                # the same graphics driver this run is using (Godot hides its own start-up flags from scripts)
	var wm := DisplayServer.window_get_mode()
	if wm == DisplayServer.WINDOW_MODE_FULLSCREEN or wm == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		args.append("--fullscreen")
	args.append_array(relaunch_extra)
	var token := "%d_%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	args.append_array(["--", "lofi_relaunch=" + token])
	if dry_relaunch:
		print("RELAUNCH ", OS.get_executable_path(), " ", args)
		return false
	# The new copy starts once this one has fully closed (Godot does it on the way out). Starting it while this
	# copy was still open made it close again within 0.3 s on Windows, every time (relaunch.log), so the room
	# never came back by itself after an update.
	_relaunch_log("restarting on exit: %s %s" % [OS.get_executable_path(), " ".join(args)])
	OS.set_restart_on_exit(true, args)
	get_tree().quit()
	return true


func _relaunch_log(line: String) -> void:
	var path := "user://relaunch.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s  %s" % [Time.get_datetime_string_from_system(), line])


# someone opened the room again while it was already open: show this one instead
func _on_second_copy() -> void:
	print("Another copy of the room tried to open; showing this one.")
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	if updater != null:
		updater.show_toast("The room is already open (this is it).", 4.0)


# a copy started by _relaunch tells the old one it made it
func _relaunch_ack() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("lofi_relaunch="):
			_relaunch_log("the new copy is up (%s)" % a.trim_prefix("lofi_relaunch="))
			var f := FileAccess.open("user://relaunch_%s.ok" % a.trim_prefix("lofi_relaunch="), FileAccess.WRITE)
			if f != null:
				f.store_string("ok")


# Meta Quest 3: ask for 90 Hz and let the runtime lower the resolution toward the edges of the lenses.
func _tune_quest_xr(xr: XRInterface) -> void:
	if xr.has_method("get_available_display_refresh_rates"):
		var rates: Array = xr.call("get_available_display_refresh_rates")
		for want in [90.0, 120.0, 72.0]:
			if rates.has(want):
				xr.set("display_refresh_rate", want)
				break
	for p in xr.get_property_list():
		if p["name"] == "foveation_level":
			xr.set("foveation_level", 2)
		elif p["name"] == "foveation_dynamic":
			xr.set("foveation_dynamic", true)


# ---------------------------------------------------------------- sitting (chair + beanbag)

func _on_button(button_name: String, hand: int) -> void:
	# the end of the Konami code: B then A. Those two presses are used up by the code instead of sitting / changing the view
	if button_name == "by_button" or button_name == "ax_button":
		var want := "B" if button_name == "by_button" else "A"
		if konami_progress >= 8 and _konami_feed(want):
			return
	if game_mode:
		if button_name == "grip_click":
			_put_pad()
		return
	if diary != null and diary.open_book and button_name == "grip_click":
		put_diary()
		return
	if held_book != null:
		# reading: A/X turns forward, B/Y back, grip puts the book down; the trigger still points at things
		if button_name == "grip_click":
			_put_book()
			return
		if button_name == "ax_button":
			_book_page(1)
			return
		if button_name == "by_button":
			_book_page(-1)
			return
		if button_name == "primary_click" or button_name == "secondary_click":
			toggle_book_zoom()
			return
	if button_name == "trigger_click":
		if _pointer_press(hand):
			return
		_toggle_sit()
	elif button_name == "ax_button":
		_toggle_sit()
	elif button_name == "by_button":
		_cycle_view()


func _on_button_released(button_name: String, hand: int) -> void:
	if button_name == "trigger_click":
		_pointer_release(hand)


func _nearest_seat() -> int:
	var p := head.global_position
	var best := -1
	var best_d := SIT_RANGE
	for i in seat_nodes.size():
		if not seat_nodes[i].visible:
			continue
		if net_game != null and net_game.seat_taken(i):
			continue                                   # another player is sitting there
		if apartment != null and not apartment.can_reach(seat_nodes[i]):
			continue                                   # on the other side of a wall
		var sp := seat_nodes[i].global_position
		var dist := Vector2(p.x, p.z).distance_to(Vector2(sp.x, sp.z))
		if dist < best_d:
			best_d = dist
			best = i
	return best


func _toggle_sit() -> void:
	if seated:
		if cur_seat == recliner_seat:
			_save_recliner()                     # keep whichever way you swivelled it
		_rec_following = false
		origin.global_position = stand_origin
		seated = false
		cur_seat = -1
		_unstick()                                   # (where I stood up from may have filled up meanwhile)
		if net_game != null:
			net_game.report_seat(-1)
		return
	var idx := _nearest_seat()
	if idx < 0:
		return
	stand_origin = origin.global_position
	var p := head.global_position
	var sp := seat_nodes[idx].global_position
	origin.global_position.x += sp.x - p.x
	origin.global_position.z += sp.z - p.z
	# lowers the rig if you're physically standing; if you're really sitting this does ~nothing
	origin.global_position.y = clampf(seat_eye[idx] - head.position.y, -1.0, 0.2) + seat_nodes[idx].global_position.y   # (theater rows sit lower)
	seated = true
	cur_seat = idx
	if net_game != null:
		net_game.report_seat(idx)
	if idx == recliner_seat:
		_rec_base_y = origin.global_position.y
		_rec_view_k = 0.0
		if not xr_active:
			desktop_cam.rotation.y = recliner.rotation.y      # settle in facing the way it faces
			pitch = 0.0
			desktop_cam.rotation.x = 0.0


# ---------------------------------------------------------------- optional 3D assets

# Loads a .glb/.gltf from res://, scales it to fit the footprint (x, z in metres), rotates it
# 90 degrees if its long side doesn't match, and stands it on the floor at `center`.
# Returns false (and does nothing) when the file isn't there, so the built-in version is used.
func _try_asset(path: String, center: Vector3, footprint: Vector2, extra_yaw_deg: float = 0.0) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return false
	var acc: Array = []
	_collect_aabb(inst, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		inst.queue_free()
		return false
	var box: AABB = acc[0]
	var yaw := extra_yaw_deg
	if (box.size.x > box.size.z) != (footprint.x > footprint.y):
		yaw += 90.0
	var quarter := int(absf(roundf(yaw / 90.0))) % 2 == 1
	var sx := box.size.z if quarter else box.size.x
	var sz := box.size.x if quarter else box.size.z
	var s := minf(footprint.x / maxf(sx, 0.001), footprint.y / maxf(sz, 0.001))
	var c := box.get_center()
	inst.position -= Vector3(c.x, box.position.y, c.z)
	var holder := Node3D.new()
	holder.position = center
	holder.rotation.y = deg_to_rad(yaw)
	holder.scale = Vector3.ONE * s
	_host().add_child(holder)
	holder.add_child(inst)
	return true


func _collect_aabb(node: Node, parent_xf: Transform3D, acc: Array) -> void:
	var t := parent_xf
	if node is Node3D:
		t = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var tb: AABB = t * (node as MeshInstance3D).get_aabb()
		if acc.is_empty():
			acc.append(tb)
		else:
			acc[0] = (acc[0] as AABB).merge(tb)
	for child in node.get_children():
		_collect_aabb(child, t, acc)


# ---------------------------------------------------------------- city outside the window

func _build_city() -> void:
	var city := Node3D.new()
	city.name = "City"
	outside.add_child(city)                    # (not the bedroom's: it's seen from the balcony and the living room too)
	var mat := ShaderMaterial.new()
	city_mat = mat
	mat.shader = load("res://shaders/building.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var ext := RandomNumberGenerator.new()
	ext.seed = 77
	# [z, min height, max height, x start, x end]  (far rows are bigger so they still read as buildings)
	var rows := [
		[-14.0, 3.5, 6.5, -22.0, 15.0],
		[-20.0, 5.0, 9.0, -31.0, 21.0],
		[-27.0, 6.0, 12.0, -41.0, 28.0],
		[-35.0, 8.0, 15.0, -53.0, 37.0],
		[-45.0, 10.0, 19.0, -68.0, 47.0],
		[-58.0, 12.0, 22.0, -88.0, 60.0],
	]
	var idx := 0
	for row in rows:
		var z: float = row[0]
		var x: float = row[3] - rng.randf() * 3.0
		var x_first := x
		var grow := 1.0 + 0.35 * idx
		while x < row[4]:
			var w := rng.randf_range(2.6, 5.0) * grow
			var depth := rng.randf_range(3.0, 5.0) * grow
			var top := rng.randf_range(row[1], row[2])
			var bottom := -40.0
			var bx := x + w / 2.0
			var bz := z + rng.randf_range(-1.5, 1.5)
			_box(Vector3(bx, (top + bottom) / 2.0, bz), Vector3(w, top - bottom, depth), mat, city)
			var roof := rng.randf()
			if roof < 0.45:
				var tw := w * rng.randf_range(0.45, 0.7)
				var th := rng.randf_range(0.8, 2.0) * grow
				_box(Vector3(bx, top + th / 2.0, bz), Vector3(tw, th, depth * 0.6), mat, city)
			elif roof < 0.7:
				var ah := rng.randf_range(1.5, 3.5) * grow
				_box(Vector3(bx, top + ah / 2.0, bz), Vector3(0.12 * grow, ah, 0.12 * grow), mat, city)
			x += w + rng.randf_range(0.8, 2.6) * grow
		# continue the row around the room on both ends so you never see it stop
		_wrap_row(city, mat, ext, z, x, row[1], row[2], grow, 1)
		_wrap_row(city, mat, ext, z, x_first, row[1], row[2], grow, -1)
		idx += 1


# Continues a row along a circle around the room (side = +1 right, -1 left) until it is behind the room.
func _wrap_row(city: Node3D, mat: Material, rng: RandomNumberGenerator, z: float, edge_x: float, hmin: float, hmax: float, grow: float, side: int) -> void:
	var r := Vector2(edge_x, z).length()
	var ang := atan2(edge_x, -z)
	var limit := deg_to_rad(105.0)
	while absf(ang) < limit:
		var w := rng.randf_range(2.6, 5.0) * grow
		var depth := rng.randf_range(3.0, 5.0) * grow
		var top := rng.randf_range(hmin, hmax)
		ang += side * ((rng.randf_range(0.8, 2.6) * grow + w * 0.5) / r)
		var pos := Vector3(r * sin(ang), (top - 40.0) / 2.0, -r * cos(ang))
		if pos.x > 4.0 and Vector2(pos.x - 11.8, pos.z + 1.0).length() < 18.0:
			ang += side * ((w * 0.5) / r)
			continue                                   # keep a view open off the balcony's east side
		var b := _box(pos, Vector3(w, top + 40.0, depth), mat, city)
		b.rotation.y = -ang
		if rng.randf() < 0.4:
			var tw := w * rng.randf_range(0.45, 0.7)
			var th := rng.randf_range(0.8, 2.0) * grow
			var t := _box(Vector3(pos.x, top + th / 2.0, pos.z), Vector3(tw, th, depth * 0.6), mat, city)
			t.rotation.y = -ang
		ang += side * ((w * 0.5) / r)


# ---------------------------------------------------------------- CRT TV + dresser

# The TV set was first built standing along the left wall; `lounge` turns all of it by LOUNGE_YAW
# so the TV sits across the front-left corner with its back corners almost touching both walls.
func _build_lounge_frame() -> void:
	lounge = Node3D.new()
	lounge.name = "Lounge"
	_host().add_child(lounge)
	var fd := 0.45
	var bd := 0.40
	var old_tv := Vector3(-3.9 + fd / 2.0 + bd + 0.01, 0.0, 0.9 + LOUNGE_DZ)
	var rot := Basis(Vector3.UP, LOUNGE_YAW)
	# the TV's back corners, in its own frame, after the turn: right one toward the left wall, left one toward the front wall
	var back := -(bd + fd / 2.0)
	var tv_basis := Basis(Vector3.UP, PI / 2.0 + LOUNGE_YAW)
	var c_right := tv_basis * Vector3(TV_WIDTH / 2.0, 0.0, back)
	var c_left := tv_basis * Vector3(-TV_WIDTH / 2.0, 0.0, back)
	var tv_pos := Vector3(-3.9 + TV_CORNER_GAP - c_right.x, 0.0, FRONT_Z - TV_CORNER_GAP - c_left.z)
	lounge.transform = Transform3D(rot, tv_pos - rot * old_tv)


# lounge-local (old wall) coordinates -> world
func _lg(p: Vector3) -> Vector3:
	return lounge.to_global(p)


# mirrored across the TV's axis: things that used to lie on the bed side of the TV now lie on the door side
func _lm(p: Vector3) -> Vector3:
	return lounge.to_global(Vector3(p.x, p.y, 2.0 * (0.9 + LOUNGE_DZ) - p.z))


func _build_tv() -> void:
	var w := TV_WIDTH
	var h := w * 0.72
	var fd := 0.45            # front housing depth
	var bd := 0.40            # sloped back depth (flatter than before)
	var base_y := 0.04
	var root := Node3D.new()
	tv_root = root
	root.position = Vector3(-3.9 + fd / 2.0 + bd + 0.01, 0.0, 0.9 + LOUNGE_DZ)
	root.rotation.y = PI / 2.0          # local +z (the screen) faces +x, into the room
	lounge.add_child(root)
	var shell := _mat(Color(0.16, 0.13, 0.19), 0.5)
	var lip := _mat(Color(0.30, 0.25, 0.33), 0.5)
	var knob := _mat(Color(0.78, 0.72, 0.80), 0.4)
	var jack_y := _mat(Color(0.95, 0.80, 0.20), 0.4)
	var jack_w := _mat(Color(0.92, 0.92, 0.95), 0.4)
	var jack_r := _mat(Color(0.90, 0.20, 0.25), 0.4)
	var cy := base_y + h / 2.0
	_box(Vector3(0, cy, 0), Vector3(w, h, fd), shell, root)                                    # front housing
	# modern-ish back: the top slopes down from the front housing to a narrow, flat rear, with vent slots on the slope
	var f_top := base_y + h - 0.02
	var b_top := base_y + h * 0.68
	_frustum(w * 0.47, base_y + 0.02, f_top, -fd / 2.0, w * 0.36, base_y + 0.07, b_top, -(fd / 2.0 + bd), shell, root)
	var slope_len := Vector2(bd, f_top - b_top).length()
	var slope_rot := atan2(f_top - b_top, -bd)
	var vent_m := _mat(Color(0.05, 0.04, 0.07), 0.8)
	for vi in 9:
		var vt := 0.16 + 0.085 * vi
		_box(Vector3(0.0, lerpf(f_top, b_top, vt) + 0.002, lerpf(-fd / 2.0, -(fd / 2.0 + bd), vt)), Vector3(w * 0.46, 0.006, 0.016), vent_m, root).rotation.x = slope_rot
	# something scratched into the side with a key: the Konami code, a bit slanted
	var scratch := QuadMesh.new()
	scratch.size = Vector2(0.38, 0.0594)
	var sc_m := StandardMaterial3D.new()
	sc_m.albedo_texture = _konami_texture()
	sc_m.albedo_color = Color(0.86, 0.84, 0.90)
	sc_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sc_m.roughness = 0.9
	sc_m.disable_fog = true
	var sc := _place(scratch, Vector3(w / 2.0 + 0.0015, cy - 0.12, 0.02), sc_m, root)
	sc.basis = Basis(Vector3.UP, PI / 2.0) * Basis(Vector3(0, 0, 1), deg_to_rad(-7.0))
	_box(Vector3(0, base_y / 2.0, 0), Vector3(w * 0.8, base_y, fd * 0.9), lip, root)            # base
	# screen: 4:3, shifted left to leave room for the control panel
	var sw := w - 0.40
	var sh := sw * 0.75
	var sx := -w / 2.0 + 0.10 + sw / 2.0
	var fz := fd / 2.0 + 0.003
	_box(Vector3(sx, cy + sh / 2.0 + 0.018, fz), Vector3(sw + 0.07, 0.035, 0.012), lip, root)
	_box(Vector3(sx, cy - sh / 2.0 - 0.018, fz), Vector3(sw + 0.07, 0.035, 0.012), lip, root)
	_box(Vector3(sx - sw / 2.0 - 0.018, cy, fz), Vector3(0.035, sh, 0.012), lip, root)
	_box(Vector3(sx + sw / 2.0 + 0.018, cy, fz), Vector3(0.035, sh, 0.012), lip, root)
	var screen := QuadMesh.new()
	screen.size = Vector2(sw, sh)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/crt.gdshader")
	_place(screen, Vector3(sx, cy, fd / 2.0 + 0.006), sm, root)
	_attach_media(sm, "res://media/tv")
	tv_mat = sm
	crt_mats.append(sm)
	var tv_ui := ScreenUI.new()
	tv_ui.position = Vector3(sx, cy, fd / 2.0 + 0.006)
	root.add_child(tv_ui)
	tv_ui.setup(sm, Vector2(sw, sh), Vector2i(1024, 768), 0.08)
	tv_screen_ui = tv_ui
	screens.append(tv_ui)
	# VCR on top of the TV
	vcr = VCR.new()
	vcr.position = Vector3(0.0, base_y + h, 0.0)
	root.add_child(vcr)
	vcr.setup(sm, tv_ui)
	for vb in vcr.buttons:
		vb["egg_lock"] = true                  # the VCR is out of action during the easter egg
	for bi in vcr.buttons.size():
		var vb2: Dictionary = vcr.buttons[bi]
		vb2["group"] = "tv"
		# in a room, the tape buttons act on whoever's tape is on the TV
		var local_cb: Callable = vb2["cb"]
		var idx := bi
		vb2["cb"] = func() -> void:
			if net_game != null and net_game.vcr_button_remote(idx):
				return
			local_cb.call()
	interactables.append_array(vcr.buttons)
	# control panel on the right: knobs, speaker slits
	var px := w / 2.0 - 0.15
	var ch_knob_m := _mat(Color(0.78, 0.72, 0.80), 0.4)
	for ky in [cy + 0.28, cy + 0.12]:
		var is_ch: bool = ky > cy + 0.2
		var k := _cyl(Vector3(px, ky, fz + 0.012), 0.045, 0.03, ch_knob_m if is_ch else knob, root)
		k.rotation.x = PI / 2.0
		if is_ch:
			_box(Vector3(px, ky + 0.02, fz + 0.03), Vector3(0.006, 0.026, 0.004), _mat(Color(0.15, 0.12, 0.18), 0.6), root)   # pointer mark
			interactables.append({"node": k, "half": Vector3(0.055, 0.055, 0.05), "group": "tv",
				"label": func() -> String: return "CHANNEL  [%s]" % CRT_NAMES[crt_mode],
				"cb": func() -> void:
					set_crt_mode((crt_mode + 1) % 3)
					if noir != null:
						noir.on_channel_turned(), "hover": _glow_hover(ch_knob_m)})
	for i in 8:
		_box(Vector3(px, cy - 0.05 - i * 0.035, fz), Vector3(0.16, 0.012, 0.01), lip, root)
	# AV jacks, lower right
	for j in 3:
		var jm := jack_y if j == 0 else (jack_w if j == 1 else jack_r)
		var jk := _cyl(Vector3(w / 2.0 - 0.28 + j * 0.07, 0.1, fz + 0.01), 0.02, 0.02, jm, root)
		jk.rotation.x = PI / 2.0
	# power button + volume buttons on the control panel
	var pw_m := _mat(Color(0.72, 0.14, 0.17), 0.4)
	var pw := _box(Vector3(px, cy + 0.40, fz + 0.012), Vector3(0.07, 0.045, 0.024), pw_m, root)
	var led_m := _mat(Color(0.2, 1.0, 0.4), 0.4, 3.0)
	_sphere(Vector3(px + 0.075, cy + 0.40, fz + 0.012), 0.008, led_m, Vector3.ONE, root, 8)
	vcr.power_changed.connect(_on_tv_power.bind(led_m))
	vcr.power_changed.connect(func(_on: bool): _apply_console())
	interactables.append({"node": pw, "half": Vector3(0.05, 0.035, 0.04),
		"label": _tv_label.bind("power"), "egg_lock": true, "group": "tv",
		"cb": func() -> void:
			if _is_guest():
				net_game.request_tv_power()          # the host's TV: the host switches it
			elif not _net_play_lock():
				vcr.toggle_tv(), "hover": _glow_hover(pw_m)})
	var vd_m := _mat(Color(0.45, 0.40, 0.50), 0.4)
	var vu_m := _mat(Color(0.45, 0.40, 0.50), 0.4)
	var vd := _box(Vector3(px - 0.045, cy, fz + 0.01), Vector3(0.06, 0.04, 0.02), vd_m, root)
	var vu := _box(Vector3(px + 0.045, cy, fz + 0.01), Vector3(0.06, 0.04, 0.02), vu_m, root)
	interactables.append({"node": vd, "half": Vector3(0.04, 0.03, 0.04),
		"label": _tv_label.bind("vol_down"), "group": "tv",
		"cb": vcr.volume_down, "hover": _glow_hover(vd_m)})
	interactables.append({"node": vu, "half": Vector3(0.04, 0.03, 0.04),
		"label": _tv_label.bind("vol_up"), "group": "tv",
		"cb": vcr.volume_up, "hover": _glow_hover(vu_m)})
	# thumbs up / down for the video that's on, between the speaker slits and the jacks
	tv_rating = load("res://tv_rating.gd").new()
	for it in tv_rating.build(self, root, Vector3(px, 0.2, fz + 0.01)):
		it["egg_lock"] = true
		interactables.append(it)
	for lab in [["PWR", cy + 0.45, 0.0], ["VOL  -  +", cy + 0.035, 0.0], ["CH", cy + 0.34, 0.0]]:
		var l3 := Label3D.new()
		l3.text = lab[0]
		l3.font_size = 28
		l3.pixel_size = 0.0007
		l3.modulate = Color(0.8, 0.75, 0.85)
		l3.position = Vector3(px, lab[1], fz + 0.003)
		root.add_child(l3)
	# rabbit-ear antenna
	for sgn in [-1.0, 1.0]:
		var ant := _cyl(Vector3(sgn * 0.2, base_y + h * 0.86 + 0.30, -0.45), 0.008, 0.7, lip, root)
		ant.rotation.z = -sgn * 0.5
		ant.rotation.x = -0.12


# A solid with a rectangular front and a smaller rectangular back (used for the sloped back of the CRT).
func _frustum(fx: float, fy0: float, fy1: float, z0: float, bx: float, by0: float, by1: float, z1: float, mat: Material, parent: Node3D) -> MeshInstance3D:
	var v: Array[Vector3] = [Vector3(-fx, fy0, z0), Vector3(fx, fy0, z0), Vector3(fx, fy1, z0), Vector3(-fx, fy1, z0),
		Vector3(-bx, by0, z1), Vector3(bx, by0, z1), Vector3(bx, by1, z1), Vector3(-bx, by1, z1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_fquad(st, v[5], v[4], v[7], v[6], Vector3(0, 0, -1))
	_fquad(st, v[3], v[2], v[6], v[7], Vector3(0, 1, -0.3))
	_fquad(st, v[0], v[4], v[5], v[1], Vector3(0, -1, 0))
	_fquad(st, v[0], v[3], v[7], v[4], Vector3(-1, 0, 0))
	_fquad(st, v[1], v[5], v[6], v[2], Vector3(1, 0, 0))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _fquad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	var order: Array[Vector3] = [a, b, c, a, c, d]
	if (b - a).cross(c - a).dot(outward) > 0.0:        # Godot wants clockwise triangles seen from the outside
		order = [a, c, b, a, d, c]
	for p in order:
		st.add_vertex(p)


# The Konami code (up up down down left right left right B A) drawn as rough scratches on a transparent image.
func _konami_texture() -> ImageTexture:
	var W := 640
	var H := 100
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var glyphs := {
		"U": [[0.5, 0.92, 0.5, 0.1], [0.5, 0.1, 0.22, 0.42], [0.5, 0.1, 0.78, 0.42]],
		"D": [[0.5, 0.1, 0.5, 0.92], [0.5, 0.92, 0.22, 0.6], [0.5, 0.92, 0.78, 0.6]],
		"L": [[0.92, 0.5, 0.1, 0.5], [0.1, 0.5, 0.42, 0.18], [0.1, 0.5, 0.42, 0.82]],
		"R": [[0.1, 0.5, 0.92, 0.5], [0.92, 0.5, 0.6, 0.18], [0.92, 0.5, 0.6, 0.82]],
		"B": [[0.2, 0.1, 0.2, 0.92], [0.2, 0.1, 0.62, 0.1], [0.62, 0.1, 0.78, 0.28], [0.78, 0.28, 0.62, 0.5], [0.2, 0.5, 0.62, 0.5],
			[0.62, 0.5, 0.82, 0.7], [0.82, 0.7, 0.62, 0.92], [0.2, 0.92, 0.62, 0.92]],
		"A": [[0.12, 0.92, 0.5, 0.1], [0.5, 0.1, 0.88, 0.92], [0.28, 0.62, 0.72, 0.62]],
	}
	var cell := 56.0
	var gap := 8.0
	for i in KONAMI.size():
		var ox := 4.0 + i * (cell + gap)
		for g in glyphs[KONAMI[i]]:
			_scratch_line(img, Vector2(ox + g[0] * cell, 8.0 + g[1] * 84.0), Vector2(ox + g[2] * cell, 8.0 + g[3] * 84.0), rng)
	for k in 14:                                           # a few stray scratches around it
		var p0 := Vector2(rng.randf_range(0.0, W), rng.randf_range(0.0, H))
		_scratch_line(img, p0, p0 + Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-6.0, 6.0)), rng, 0.4)
	return ImageTexture.create_from_image(img)


func _scratch_line(img: Image, a: Vector2, b: Vector2, rng: RandomNumberGenerator, strength: float = 1.0) -> void:
	var steps := int(a.distance_to(b) * 1.5) + 1
	var jit := 0.0
	for i in steps + 1:
		var t := float(i) / steps
		var p := a.lerp(b, t)
		jit = clampf(jit + rng.randf_range(-0.35, 0.35), -1.0, 1.0)
		if rng.randf() < 0.05:
			continue                                       # the key skipped a little
		var al := rng.randf_range(0.55, 1.0) * strength
		var px := int(round(p.x + jit * 0.6))
		var py := int(round(p.y + jit * 0.4))
		for dx in 4:
			for dy in 4:
				var edge := dx == 0 or dy == 0 or dx == 3 or dy == 3
				_plot(img, px + dx - 1, py + dy - 1, al * (0.6 if edge else 1.0))
		_plot(img, px + 4, py + 4, al * 0.3)               # lighter ridge beside the groove


func _plot(img: Image, x: int, y: int, alpha: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var old := img.get_pixel(x, y)
	if alpha > old.a:
		img.set_pixel(x, y, Color(1, 1, 1, alpha))


# ---------------------------------------------------------------- game console (cartridge based)

# The console is modelled on the unreleased Nintendo PlayStation prototype: a tan lower layer with two controller ports,
# a cream upper layer with a disc tray, eject / reset buttons and a little display, and a cover over the cartridge slot.
const CON_W := 0.36
const CON_D := 0.38
const CON_LOW := 0.067          # top of the tan lower layer
const CON_TOP := 0.11           # top of the cream upper layer
const CON_SLOT_Z := -0.115      # where cartridges stand in the slot


func _build_console() -> void:
	var root := Node3D.new()
	console_root = root
	root.position = Vector3(-2.60, 0.022, 1.45 + LOUNGE_DZ)       # on the door side of the TV
	root.rotation.y = PI / 2.0          # local +z faces +x (toward the beanbags)
	lounge.add_child(root)
	var cream := _mat(Color(0.91, 0.89, 0.85), 0.5)
	var cream_hi := _mat(Color(0.95, 0.93, 0.90), 0.45)
	var tan := _mat(Color(0.93, 0.86, 0.62), 0.55)
	var tan_dk := _mat(Color(0.84, 0.77, 0.54), 0.6)
	var grey := _mat(Color(0.60, 0.60, 0.58), 0.5)
	var olive := _mat(Color(0.66, 0.60, 0.38), 0.5)
	var dark := _mat(Color(0.10, 0.10, 0.12), 0.6)
	var seam := _mat(Color(0.50, 0.48, 0.45), 0.7)
	var hw := CON_W / 2.0
	var hd := CON_D / 2.0
	var fz := hd + 0.0                                  # front of the upper layer
	var fl := hd - 0.005                                # front of the (slightly inset) lower layer
	_box(Vector3(0, CON_LOW / 2.0, 0), Vector3(CON_W - 0.01, CON_LOW, CON_D - 0.01), tan, root)
	_box(Vector3(0, CON_LOW + 0.0015, 0), Vector3(CON_W - 0.006, 0.003, CON_D - 0.006), seam, root)
	var up_h := CON_TOP - CON_LOW - 0.003
	_box(Vector3(0, CON_LOW + 0.003 + up_h / 2.0, 0), Vector3(CON_W, up_h, CON_D), cream, root)
	# ---- lower front: a pill-shaped panel with the two controller ports, a headphone jack and a level slider
	_box(Vector3(0.046, 0.03, fl + 0.0008), Vector3(0.20, 0.036, 0.0016), tan_dk, root)
	for ex in [-0.1, 0.1]:
		var cap := _cyl(Vector3(0.046 + ex, 0.03, fl + 0.0008), 0.018, 0.0016, tan_dk, root)
		cap.rotation.x = PI / 2.0
	for px in [-0.004, 0.094]:
		_box(Vector3(px, 0.03, fl + 0.0014), Vector3(0.064, 0.024, 0.0014), cream, root)
		_box(Vector3(px - 0.0165, 0.03, fl + 0.0024), Vector3(0.025, 0.012, 0.0014), dark, root)
		_box(Vector3(px + 0.0155, 0.03, fl + 0.0024), Vector3(0.03, 0.012, 0.0014), dark, root)
		for k in 3:
			_box(Vector3(px - 0.0225 + k * 0.0065, 0.03, fl + 0.0032), Vector3(0.0036, 0.006, 0.001), cream, root)
		for k in 4:
			_box(Vector3(px + 0.0045 + k * 0.0065, 0.03, fl + 0.0032), Vector3(0.0036, 0.006, 0.001), cream, root)
	var jack := _cyl(Vector3(-0.128, 0.034, fl + 0.0015), 0.0085, 0.003, grey, root)
	jack.rotation.x = PI / 2.0
	var jack_in := _cyl(Vector3(-0.128, 0.034, fl + 0.0032), 0.0042, 0.003, dark, root)
	jack_in.rotation.x = PI / 2.0
	_box(Vector3(-0.097, 0.034, fl + 0.0015), Vector3(0.017, 0.006, 0.003), dark, root)                      # level slider track
	_box(Vector3(-0.0975, 0.034, fl + 0.0032), Vector3(0.004, 0.011, 0.0025), grey, root)
	# ---- upper front: the disc tray with its tab and eject key, and the power switch
	_box(Vector3(0.0164, 0.067, fz + 0.0006), Vector3(0.259, 0.026, 0.0016), grey, root)
	_box(Vector3(-0.092, 0.067, fz + 0.0016), Vector3(0.044, 0.026, 0.0016), _mat(Color(0.52, 0.52, 0.50), 0.6), root)  # the tab on the left
	_box(Vector3(0.0275, 0.067, fz + 0.0016), Vector3(0.212, 0.020, 0.0014), _mat(Color(0.56, 0.56, 0.54), 0.5), root)   # the disc slot door
	_cart_text("COMPACT DISC", 22, 0.0004, Color(0.2, 0.2, 0.22), Vector3(0.015, 0.067, fz + 0.0030), root)
	_box(Vector3(0.1595, 0.067, fz + 0.0014), Vector3(0.024, 0.026, 0.003), olive, root)                       # eject key
	var knob_m := _mat(Color(0.88, 0.80, 0.55), 0.45)
	console_knob = _box(Vector3(-0.157, 0.081, fz + 0.005), Vector3(0.028, 0.018, 0.011), knob_m, root)      # the power switch: slides right = ON
	interactables.append({"node": console_knob, "half": Vector3(0.04, 0.03, 0.04),
		"label": _console_label, "egg_lock": true, "cb": func() -> void:
			if not _cat_on_console():
				toggle_console(), "hover": _glow_hover(knob_m), "group": "games"})
	_cart_text("POWER", 20, 0.0004, Color(0.3, 0.26, 0.2), Vector3(-0.157, 0.0645, fz + 0.0014), root)
	# ---- the top: eject and reset buttons, the little display with its row of keys, and the cover over the cartridge slot
	_cyl(Vector3(-0.152, CON_TOP + 0.002, 0.137), 0.028, 0.004, tan, root)
	_cyl(Vector3(-0.078, CON_TOP + 0.002, 0.099), 0.018, 0.004, tan, root)
	console_led_m = _mat(Color(0.12, 0.16, 0.14), 0.4, 0.5)
	_box(Vector3(0.115, CON_TOP + 0.001, 0.115), Vector3(0.07, 0.0025, 0.031), dark, root)
	_box(Vector3(0.115, CON_TOP + 0.0022, 0.115), Vector3(0.062, 0.0025, 0.024), console_led_m, root)         # the display
	for cx in [0.1, 0.133]:
		for cz in [0.142, 0.157, 0.172]:
			_box(Vector3(cx, CON_TOP + 0.0015, cz), Vector3(0.028, 0.003, 0.009), tan, root)
	_box(Vector3(0, CON_TOP + 0.0008, CON_SLOT_Z), Vector3(0.30, 0.0016, 0.15), _mat(Color(0.74, 0.72, 0.68), 0.6), root)   # the bay under the cover
	_box(Vector3(0, CON_TOP + 0.002, CON_SLOT_Z), Vector3(0.17, 0.002, 0.03), dark, root)                    # the cartridge slot itself
	_cart_text("LOFI", 40, 0.0004, Color(0.45, 0.43, 0.42), Vector3(0.0, CON_TOP + 0.0012, 0.0), root).rotation.x = -PI / 2.0
	console_lid = Node3D.new()
	console_lid.position = Vector3(0, CON_TOP, -hd + 0.0)           # hinged along the back edge
	root.add_child(console_lid)
	_box(Vector3(0, 0.006, 0.075), Vector3(0.30, 0.012, 0.15), cream_hi, console_lid)
	_box(Vector3(0, 0.0125, 0.075), Vector3(0.27, 0.002, 0.12), cream, console_lid)
	_box(Vector3(0, 0.0125, 0.138), Vector3(0.10, 0.0025, 0.012), tan_dk, console_lid)                         # finger dip
	# ---- the back: a plate with the video sockets
	_box(Vector3(-0.02, 0.05, -hd + 0.0015), Vector3(0.22, 0.04, 0.003), dark, root)
	for i in 3:
		var jk := _cyl(Vector3(-0.07 + i * 0.026, 0.05, -hd - 0.002), 0.0075, 0.004,
			_mat([Color(0.85, 0.15, 0.15), Color(0.95, 0.95, 0.95), Color(0.95, 0.82, 0.15)][i], 0.4), root)
		jk.rotation.x = PI / 2.0
	# two controllers on the rug
	_controller(Vector3(-2.0, 0.022, 2.58), -0.3)
	_controller(Vector3(-2.25, 0.022, 2.25), 0.25)
	emu = Emu.new()
	emu.name = "Emu"
	add_child(emu)
	emu.screen_changed.connect(_on_emu_screen)
	_build_arcade()
	_build_carts()
	_apply_console()


var console_lid: Node3D
var _lid_tween: Tween


# The cover over the cartridge slot lifts while a cartridge is in.
func _set_lid(open: bool) -> void:
	if console_lid == null:
		return
	if _lid_tween != null and _lid_tween.is_valid():
		_lid_tween.kill()
	_lid_tween = create_tween()
	_lid_tween.tween_property(console_lid, "rotation:x", -1.9 if open else 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _console_label() -> String:
	return "CONSOLE POWER  [%s]" % ("ON" if console_on else "OFF")


# the calico asleep on the console: nothing gets in or switched on until it's moved
func _cat_on_console() -> bool:
	if cats != null and cats.blocks_console():
		_net_say("%s is asleep on the console. Pick her up and put her on the bed." % cats.name_of("calico"))
		return true
	return false


func toggle_console() -> void:
	if egg_active or slot_cart == "neo" or (not _is_guest() and _net_play_lock()):
		return
	console_on = not console_on
	vcr.external_hold = console_on
	if console_on and vcr.state == VCR.State.PLAYING and not vcr._paused_flag:
		vcr._set_paused(true)            # the tape waits while the TV shows the console
		vcr._tv_paused = true
	elif not console_on and vcr._tv_paused and vcr.tv_on:
		vcr._set_paused(false)
		vcr._tv_paused = false
	_apply_console()


# The console takes over the TV picture; the TV's own power button still works.
func _apply_console() -> void:
	if tv_mat == null:
		return
	var arcade_in := slot_cart == "neo" and arcade_on
	tv_mat.set_shader_parameter("use_console", console_on and not arcade_in)
	if arcade_mat != null:
		arcade_mat.set_shader_parameter("console_tex", emu.tex if emu != null else null)
		arcade_mat.set_shader_parameter("use_console", arcade_in)
		arcade_mat.set_shader_parameter("tv_power", 1.0 if arcade_in else 0.0)
		arcade_light.light_energy = 0.7 if arcade_in else 0.0
	if ctl_open and (not (console_on or arcade_in) or slot_cart == "egg"):
		_close_controls()
	var from_emu := slot_cart != "egg"           # the secret cart plays the built-in scene, the others the emulator / its menu
	tv_mat.set_shader_parameter("console_file", from_emu)
	if from_emu and emu != null:
		tv_mat.set_shader_parameter("console_tex", emu.tex)
		_console_fit(emu.tex)
	else:
		_console_fit(null)
	if emu != null:
		emu.set_power(arcade_in or (console_on and vcr.tv_on))
	if tv_screen_ui != null:
		tv_screen_ui.enabled = vcr.tv_on and not console_on
		if console_on:
			tv_screen_ui.clear_hover()
	if console_knob != null:
		console_knob.position.x = -0.145 if console_on else -0.157
	if console_led_m != null:
		console_led_m.albedo_color = Color(0.35, 0.6, 0.45) if console_on else Color(0.12, 0.16, 0.14)
		console_led_m.emission = Color(0.35, 0.95, 0.5) if console_on else Color(0.12, 0.16, 0.14)
		console_led_m.emission_energy_multiplier = 1.6 if console_on else 0.2


func _on_emu_screen(t: Texture2D) -> void:
	if tv_mat != null and slot_cart != "egg":
		tv_mat.set_shader_parameter("console_tex", t)
		_console_fit(t)
	if arcade_mat != null and not egg_active:
		arcade_mat.set_shader_parameter("console_tex", t)


# NES / SNES fill the 4:3 glass; the handheld picture keeps its own shape (black bars at the sides or top).
func _console_fit(t: Texture2D) -> void:
	if tv_mat == null:
		return
	var handheld := t != null and t.get_height() > 0 and (slot_cart == "sgb" or (slot_cart == "gen" and t.get_width() <= 160))   # Game Gear is 160 wide
	tv_mat.set_shader_parameter("console_contain", handheld)
	tv_mat.set_shader_parameter("console_aspect", float(t.get_width()) / float(t.get_height()) if handheld else 1.3333)


# ---- game carts. Every cart is built around its centre, label toward +z. Meta "bottom" = distance from the centre down to the contacts,
# "depth" = how far it sinks into the console slot.

const CartArt := preload("res://cart_art.gd")
const GOLD := Color(0.80, 0.66, 0.30)


func _label_quad(tex: Texture2D, size: Vector2, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.4
	m.disable_fog = true
	return _place(q, pos, m, parent)


func _cart_text(text: String, fsize: int, psize: float, col: Color, pos: Vector3, parent: Node3D) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = fsize
	lb.pixel_size = psize
	lb.outline_size = 0
	lb.modulate = col
	lb.position = pos
	parent.add_child(lb)
	return lb


# A lofi wash over the plastic: every cart body leans toward the room's magenta.
const CART_WASH := Color(0.86, 0.30, 0.58)


var cart_wash := true                  # true = the lofi pink wash, false = the plastic's original colours
var _cart_tints: Array = []            # [material, colour function] for every cart body part


func _wc(base: Color, k: float, wash: bool) -> Color:
	return base.lerp(CART_WASH, k) if wash else base


func _tm(fn: Callable, rough: float) -> StandardMaterial3D:
	var m := _mat(fn.call(cart_wash), rough)
	_cart_tints.append([m, fn])
	return m


func set_cart_style_quiet(wash: bool) -> void:
	cart_wash = wash
	for e in _cart_tints:
		(e[0] as StandardMaterial3D).albedo_color = (e[1] as Callable).call(cart_wash)


func set_cart_style(wash: bool) -> void:
	set_cart_style_quiet(wash)
	_save_settings()
	settings_changed.emit()


func _cart_node(bottom: float, depth: float) -> Node3D:
	var n := Node3D.new()
	_host().add_child(n)
	n.set_meta("bottom", bottom)
	n.set_meta("depth", depth)
	return n


# NES: grey, tall, a ribbed column beside a label set into the right of the face, a triangle mark near the bottom.
func _nes_cart_mesh(egg: bool = false) -> Node3D:
	var n := _cart_node(0.09, 0.04)
	var base := Color(0.19, 0.18, 0.22) if egg else Color(0.60, 0.60, 0.62)
	var k := 0.30 if egg else 0.38
	var body := _tm(func(w: bool) -> Color: return _wc(base, k, w), 0.55)
	var dark := _tm(func(w: bool) -> Color: return _wc(base, k, w).darkened(0.32), 0.7)
	var light := _tm(func(w: bool) -> Color: return _wc(base, k, w).lightened(0.07), 0.5)
	var t := 0.024
	_extrude_poly([Vector2(-0.075, -0.0825), Vector2(0.075, -0.0825), Vector2(0.075, 0.0765), Vector2(0.063, 0.0765), Vector2(0.063, 0.0825),
		Vector2(-0.063, 0.0825), Vector2(-0.063, 0.0765), Vector2(-0.075, 0.0765)], -t / 2.0, t / 2.0, body, n)
	_box(Vector3(0, -0.0865, 0), Vector3(0.12, 0.008, 0.012), _mat(GOLD, 0.4), n)                                   # contacts
	_box(Vector3(-0.0353, 0.009, t / 2.0 + 0.0003), Vector3(0.032, 0.14, 0.0006), dark, n)                       # ribbed column
	for i in 22:
		_box(Vector3(-0.0353, 0.0758 - i * 0.0066, t / 2.0 + 0.0008), Vector3(0.032, 0.0042, 0.0014), light, n)
	_box(Vector3(0.019, 0.0269, t / 2.0 + 0.0002), Vector3(0.0726, 0.1163, 0.0004), dark, n)                      # the label's pocket
	var lab_tex := CartArt.egg_label() if egg else CartArt.nes_label()
	_label_quad(lab_tex, Vector2(0.0686, 0.1123), Vector3(0.019, 0.0269, t / 2.0 + 0.0008), n)
	_extrude_poly([Vector2(-0.0155, -0.0369), Vector2(-0.0015, -0.0519), Vector2(0.0125, -0.0369)], t / 2.0 - 0.0004, t / 2.0 + 0.0006, dark, n)   # the triangle
	if not egg:
		_cart_text("NES", 52, 0.0006, Color(0.98, 0.92, 0.98), Vector3(0.019, -0.0192, t / 2.0 + 0.0014), n)
	return n


# SNES: wide and short, ribbed shoulders, a raised middle with the label, a recessed panel at the bottom and two screws.
func _snes_cart_mesh() -> Node3D:
	var n := _cart_node(0.049, 0.04)
	var base := Color(0.73, 0.72, 0.78)
	var body := _tm(func(w: bool) -> Color: return _wc(base, 0.38, w), 0.55)
	var dark := _tm(func(w: bool) -> Color: return _wc(base, 0.38, w).darkened(0.30), 0.7)
	var t := 0.022
	_extrude_poly([Vector2(-0.075, -0.0468), Vector2(0.075, -0.0468), Vector2(0.075, 0.0432), Vector2(0.0513, 0.0432), Vector2(0.0513, 0.0467),
		Vector2(-0.0513, 0.0467), Vector2(-0.0513, 0.0432), Vector2(-0.075, 0.0432)], -t / 2.0, t / 2.0, body, n)
	_box(Vector3(0, -0.0485, 0), Vector3(0.1, 0.004, 0.012), _mat(GOLD, 0.4), n)
	for sx in [-1.0, 1.0]:
		for gy in [0.0271, 0.0121, -0.0029, -0.0179, -0.0329]:                                                    # the grooves in the shoulders
			_box(Vector3(sx * 0.0631, gy, 0), Vector3(0.022, 0.0016, t + 0.0004), dark, n)
		var sc := _cyl(Vector3(sx * 0.0605, -0.040, t / 2.0 + 0.0004), 0.0033, 0.0014, _mat(Color(0.78, 0.66, 0.35), 0.4), n)
		sc.rotation.x = PI / 2.0
	_box(Vector3(0, -0.03, t / 2.0 + 0.0002), Vector3(0.091, 0.0335, 0.0006), _tm(func(w: bool) -> Color: return _wc(base, 0.38, w).darkened(0.07), 0.6), n)    # the recess at the bottom
	for vx in [-0.0165, 0.0165]:
		_box(Vector3(vx, -0.03, t / 2.0 + 0.0007), Vector3(0.0016, 0.0335, 0.0006), dark, n)
	_box(Vector3(0.0006, 0.0241, t / 2.0 + 0.0002), Vector3(0.0953, 0.0462, 0.0004), _mat(Color(0.05, 0.04, 0.08), 0.6), n)
	_label_quad(CartArt.snes_label(), Vector2(0.0923, 0.0432), Vector3(0.0006, 0.0241, t / 2.0 + 0.0008), n)
	_cart_text("SNES", 28, 0.00045, Color(0.98, 0.92, 0.98), Vector3(0.031, 0.0298, t / 2.0 + 0.0014), n)
	return n


# Super GB: taller grey body, ridged sides, a raised top block, four screws, a lavender label.
func _sgb_cart_mesh() -> Node3D:
	var n := _cart_node(0.0605, 0.035)
	var base := Color(0.66, 0.65, 0.64)
	var body := _tm(func(w: bool) -> Color: return _wc(base, 0.38, w), 0.55)
	var dark := _mat(Color(0.22, 0.22, 0.24), 0.7)
	_box(Vector3(0, 0.005, 0), Vector3(0.15, 0.12, 0.022), body, n)
	_box(Vector3(0, 0.07, 0), Vector3(0.088, 0.024, 0.024), _tm(func(w: bool) -> Color: return _wc(base, 0.38, w).lightened(0.05), 0.5), n)               # raised top block
	_box(Vector3(0, 0.0595, 0.0), Vector3(0.088, 0.004, 0.0245), dark, n)                                       # the dark gap under it
	_box(Vector3(0.0, 0.074, 0.0125), Vector3(0.02, 0.01, 0.0015), dark, n)                                       # little embossed mark
	for sx in [-1.0, 1.0]:
		for i in 6:                                                                                               # grooves on both sides
			_box(Vector3(sx * 0.0545, 0.036 - i * 0.0165, 0.0), Vector3(0.037, 0.0028, 0.0232), dark, n)
		for sy in [0.03, -0.043]:                                                                                 # screws
			var sc := _cyl(Vector3(sx * 0.0345, sy, 0.0116), 0.0036, 0.0012, dark, n)
			sc.rotation.x = PI / 2.0
	_box(Vector3(0, -0.046, 0.0), Vector3(0.07, 0.03, 0.0236), _tm(func(w: bool) -> Color: return _wc(base, 0.38, w).darkened(0.04), 0.6), n)                  # the lower panel
	_box(Vector3(0, -0.0575, 0.0), Vector3(0.06, 0.0025, 0.0238), dark, n)
	_box(Vector3(0, -0.0585, 0), Vector3(0.12, 0.004, 0.012), _mat(GOLD, 0.4), n)                              # contacts
	_box(Vector3(0, 0.014, 0.0125), Vector3(0.088, 0.054, 0.003), _mat(Color(0.86, 0.78, 0.96), 0.5), n)        # lavender label
	_cart_text("Super", 36, 0.0006, Color(0.88, 0.25, 0.55), Vector3(0, 0.0295, 0.0147), n)
	_box(Vector3(0.0, 0.0205, 0.0143), Vector3(0.06, 0.0018, 0.0006), _mat(Color(0.88, 0.25, 0.55), 0.5), n)    # swoosh
	_cart_text("GB", 64, 0.0008, Color(0.20, 0.12, 0.45), Vector3(0, 0.0035, 0.0147), n)
	return n


# Sega style: black shell, thick grippy side pillars, a flat middle with the label, a grid panel and a name plate under it.
func _gen_cart_mesh() -> Node3D:
	var n := _cart_node(0.059, 0.022)
	var blk := _tm(func(w: bool) -> Color: return _wc(Color(0.07, 0.07, 0.085), 0.28, w), 0.5)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.7)
	_extrude_poly([Vector2(-0.056, -0.051), Vector2(0.056, -0.051), Vector2(0.056, 0.051), Vector2(-0.056, 0.051)], -0.010, 0.010, blk, n)
	for sx in [-1.0, 1.0]:                                                                                       # side pillars, rounded at the top
		var pts := [Vector2(0.056, -0.051), Vector2(0.075, -0.051), Vector2(0.075, 0.040), Vector2(0.066, 0.051), Vector2(0.056, 0.051)]
		if sx < 0.0:
			pts = [Vector2(-0.056, 0.051), Vector2(-0.066, 0.051), Vector2(-0.075, 0.040), Vector2(-0.075, -0.051), Vector2(-0.056, -0.051)]
		_extrude_poly(pts, -0.013, 0.013, blk, n)
		for i in 4:
			_box(Vector3(sx * 0.0658, 0.025 - i * 0.017, 0.0132), Vector3(0.013, 0.003, 0.0006), dark, n)         # grips
	_box(Vector3(0, -0.055, 0), Vector3(0.12, 0.008, 0.012), _mat(GOLD, 0.4), n)                                 # contacts
	_box(Vector3(0, 0.0215, 0.0102), Vector3(0.1134, 0.0630, 0.0004), dark, n)                                   # label pocket
	_label_quad(CartArt.gen_label(), Vector2(0.1094, 0.059), Vector3(0, 0.0215, 0.0108), n)
	_label_quad(CartArt.gen_grid(), Vector2(0.1094, 0.034), Vector3(0, -0.0255, 0.0104), n)
	var sil := _mat(Color(0.74, 0.76, 0.84), 0.35, 0.0)
	sil.metallic = 0.5
	_box(Vector3(0, -0.0185, 0.0108), Vector3(0.060, 0.0135, 0.0012), sil, n)                                    # name plate
	_box(Vector3(0, -0.0185, 0.0116), Vector3(0.054, 0.0095, 0.0012), _mat(Color(0.10, 0.17, 0.46), 0.5), n)
	_cart_text("SEGA", 40, 0.0005, Color(0.92, 0.96, 1.0), Vector3(0, -0.0185, 0.0124), n)
	return n


# ---- the standing arcade cabinet (right wall, beside the bookshelf). Local axes: x = out from the wall, y = up, z = across the front.
const CAB_POS := Vector3(2.5, 0.0, 1.95)       # against the right wall, next to the bookshelf, facing into the room
const CAB_W := 0.72
const ARC_SPLIT_Z := -0.015               # where the arcade shelf divides: +z is the left player, -z the right player
const CAB_PROFILE := [Vector2(0, 0), Vector2(0.78, 0), Vector2(0.78, 0.82), Vector2(1.05, 0.82), Vector2(1.05, 0.90), Vector2(0.83, 0.90),
	Vector2(0.83, 0.96), Vector2(0.64, 1.50), Vector2(0.71, 1.53), Vector2(0.71, 1.77), Vector2(0.50, 1.80), Vector2(0.0, 1.40)]
const CAB_TILT := 0.3384        # the monitor leans back by atan(0.19 / 0.54)


# A flat shape (u, y points) pushed out between z0 and z1, drawn from both sides.
func _extrude_poly(pts: Array, z0: float, z1: float, mat: Material, parent: Node3D) -> MeshInstance3D:
	var p2 := PackedVector2Array()
	for p in pts:
		p2.append(p)
	var idx := Geometry2D.triangulate_polygon(p2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cap in [[z1, Vector3(0, 0, 1)], [z0, Vector3(0, 0, -1)]]:
		st.set_normal(cap[1])
		for i in idx:
			st.add_vertex(Vector3(p2[i].x, p2[i].y, cap[0]))
	var n := p2.size()
	for i in n:
		var a := p2[i]
		var b := p2[(i + 1) % n]
		var e := (b - a).normalized()
		var nrm := Vector3(e.y, -e.x, 0.0)        # outward for a counter-clockwise outline
		st.set_normal(nrm)
		for v in [Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)]:
			st.add_vertex(v)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var cm := mat.duplicate() as BaseMaterial3D
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = cm
	parent.add_child(mi)
	return mi


# A box with its own rotation (used for the leaning monitor board, the roof and so on).
func _rbox(pos: Vector3, size: Vector3, basis: Basis, mat: Material, parent: Node3D) -> MeshInstance3D:
	var b := _box(pos, size, mat, parent)
	b.basis = basis
	return b


func _build_arcade() -> void:
	var was := _into
	_into = arcade_kit
	_build_arcade_body()
	_into = was


func _build_arcade_body() -> void:
	var root := Node3D.new()
	root.position = CAB_POS
	root.rotation.y = PI                       # local +x (out from the wall) points along -x, into the room
	_host().add_child(root)
	cab_root = root
	var white := _mat(Color(0.88, 0.88, 0.90), 0.45)
	var green := _mat(Color(0.14, 0.74, 0.30), 0.45)
	var deck_m := _mat(Color(0.10, 0.16, 0.14), 0.35)
	var grey := _mat(Color(0.52, 0.54, 0.56), 0.5)
	var dark := _mat(Color(0.04, 0.04, 0.05), 0.6)
	var yellow := _mat(Color(0.98, 0.82, 0.15), 0.4, 1.2)
	var hw := CAB_W / 2.0
	# the two side panels (the cabinet's silhouette), and a green stripe along the monitor edge on each
	_extrude_poly(CAB_PROFILE, -hw, -hw + 0.035, white, root)
	_extrude_poly(CAB_PROFILE, hw - 0.035, hw, white, root)
	for sz in [-1.0, 1.0]:
		var zz: float = sz * hw
		_extrude_poly([Vector2(0.83, 0.96), Vector2(0.64, 1.50), Vector2(0.607, 1.488), Vector2(0.797, 0.948)], zz - 0.0015 if sz > 0 else zz - 0.0035, zz + 0.0035 if sz > 0 else zz + 0.0015, green, root)
		_extrude_poly([Vector2(0.60, 1.79), Vector2(0.71, 1.765), Vector2(0.71, 1.735), Vector2(0.52, 1.765)], zz - 0.0015 if sz > 0 else zz - 0.0035, zz + 0.0035 if sz > 0 else zz + 0.0015, green, root)
	# lower front: kick plate, the front panel with coin doors and the cart slot
	_box(Vector3(0.755, 0.06, 0), Vector3(0.05, 0.12, CAB_W - 0.07), grey, root)
	var fw := CAB_W - 0.07
	_box(Vector3(0.7675, 0.27, 0), Vector3(0.025, 0.30, fw), white, root)                    # front panel, with an open cart bay in it
	_box(Vector3(0.7675, 0.72, 0), Vector3(0.025, 0.20, fw), white, root)
	for bz in [-1.0, 1.0]:
		_box(Vector3(0.7675, 0.52, bz * 0.23), Vector3(0.025, 0.20, 0.19), white, root)
	_box(Vector3(0.7545, 0.52, 0), Vector3(0.002, 0.21, 0.27), _mat(Color(0.015, 0.015, 0.02), 0.8), root)   # back of the bay
	_box(Vector3(0.7665, 0.42, 0), Vector3(0.025, 0.004, 0.27), _mat(Color(0.015, 0.015, 0.02), 0.8), root)  # its dark floor edge
	for cz in [-0.21, 0.21]:
		_box(Vector3(0.7815, 0.40, cz), Vector3(0.006, 0.20, 0.13), grey, root)                       # coin door plate
		_box(Vector3(0.785, 0.46, cz), Vector3(0.004, 0.05, 0.012), dark, root)                       # coin slot
		_box(Vector3(0.785, 0.36, cz), Vector3(0.004, 0.025, 0.05), yellow, root)                     # "coin" light
	arcade_glow.append([yellow, 1.2, yellow.albedo_color])
	_box(Vector3(0.7815, 0.22, 0.0), Vector3(0.004, 0.18, 0.30), grey, root)                          # cash door
	_box(Vector3(0.784, 0.22, 0.0), Vector3(0.003, 0.012, 0.05), dark, root)                          # its lock
	var cl := Label3D.new()
	cl.text = "CART BAY"
	cl.font_size = 22
	cl.pixel_size = 0.0007
	cl.modulate = Color(0.25, 0.28, 0.3)
	cl.rotation = Vector3(0, PI / 2.0, 0)
	cl.position = Vector3(0.7815, 0.395, 0.0)
	root.add_child(cl)
	# the control panel: a speckled grey deck like a classic fighting-game cabinet. Two black ball-top sticks, two rows of three
	# buttons each (red, white, blue) and four start buttons in the middle.
	var nimg := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var nrng := RandomNumberGenerator.new()
	nrng.seed = 11
	for yy in 64:
		for xx in 64:
			var g := 0.58 + nrng.randf_range(-0.08, 0.08)
			if nrng.randf() < 0.16:
				g = 0.16 if nrng.randf() < 0.55 else 0.9
			nimg.set_pixel(xx, yy, Color(g, g, g + 0.02))
	var speck := StandardMaterial3D.new()
	speck.albedo_texture = ImageTexture.create_from_image(nimg)
	speck.uv1_scale = Vector3(5, 4, 1)
	speck.roughness = 0.45
	speck.disable_fog = true
	_box(Vector3(0.94, 0.885, 0), Vector3(0.22, 0.03, CAB_W - 0.07), speck, root)
	_box(Vector3(1.0435, 0.86, 0), Vector3(0.0125, 0.08, CAB_W - 0.07), white, root)
	_box(Vector3(1.044, 0.896, 0), Vector3(0.012, 0.012, CAB_W - 0.07), dark, root)
	var plate := _box(Vector3(0.94, 0.9005, 0), Vector3(0.2, 0.001, CAB_W - 0.09), speck, root)
	# the shelf is split in two: a dark divider down the middle, and a label on the front lip for each player
	_box(Vector3(0.94, 0.9025, ARC_SPLIT_Z), Vector3(0.2, 0.003, 0.004), dark, root)
	for sd in 2:
		var pl := Label3D.new()
		pl.text = "LEFT PLAYER" if sd == 0 else "RIGHT PLAYER"
		pl.font_size = 28
		pl.pixel_size = 0.0007
		pl.outline_size = 0
		pl.modulate = Color(0.16, 0.18, 0.22)
		pl.rotation = Vector3(0, PI / 2.0, 0)
		pl.position = Vector3(1.0507, 0.86, 0.17 if sd == 0 else -0.185)
		root.add_child(pl)
	_box(Vector3(0.826, 0.93, 0), Vector3(0.008, 0.07, CAB_W - 0.07), white, root)          # closes the step between the control deck and the monitor board
	var black_g := _mat(Color(0.04, 0.04, 0.05), 0.25)
	var stick_m := _mat(Color(0.8, 0.8, 0.84), 0.35)
	var btn_cols := [Color(0.92, 0.12, 0.10), Color(0.94, 0.94, 0.97), Color(0.12, 0.34, 0.95)]
	for zc in [0.285, -0.055]:   # local +z is the player's left, so each stick sits left of its buttons
		_cyl(Vector3(0.935, 0.9015, zc), 0.05, 0.002, black_g, root)                  # the round dish under the stick
		_cyl(Vector3(0.935, 0.93, zc), 0.0065, 0.056, stick_m, root)
		_sphere(Vector3(0.935, 0.972, zc), 0.027, black_g, Vector3(1, 1.05, 1), root, 16)
		for r in 2:
			for c in 3:
				var bm := _mat(btn_cols[c], 0.25, 0.3)
				arcade_glow.append([bm, 0.3, bm.albedo_color])
				_cyl(Vector3(0.925 + r * 0.058, 0.911, zc - 0.092 - c * 0.06), 0.0195, 0.018, bm, root)
	var st_cols := [btn_cols[0], btn_cols[1], btn_cols[2], btn_cols[1]]
	for i in 4:
		var stm := _mat(st_cols[i], 0.25, 0.3)
		arcade_glow.append([stm, 0.3, stm.albedo_color])
		_cyl(Vector3(0.855, 0.908, 0.045 - i * 0.04 + 0.0), 0.0155, 0.012, stm, root)
	# the monitor: a leaning white board with a black glass and the live screen
	var tb := Basis(Vector3(0, 0, 1), CAB_TILT) * Basis(Vector3.UP, PI / 2.0)
	var a := Vector2(0.83, 0.96)
	var b2 := Vector2(0.64, 1.50)
	var mid := (a + b2) * 0.5
	var nrm := Vector3(cos(CAB_TILT), sin(CAB_TILT), 0.0)
	_rbox(Vector3(mid.x, mid.y, 0) + nrm * 0.004, Vector3(CAB_W - 0.07, 0.585, 0.03), tb, white, root)
	_rbox(Vector3(mid.x, mid.y, 0) + nrm * 0.0185, Vector3(0.64, 0.50, 0.003), tb, dark, root)
	var q := QuadMesh.new()
	q.size = Vector2(0.58, 0.435)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/crt.gdshader")
	sm.set_shader_parameter("use_console", true)
	sm.set_shader_parameter("console_file", true)
	sm.set_shader_parameter("console_accurate", true)
	sm.set_shader_parameter("crt_mode", crt_mode)
	arcade_mat = sm
	crt_mats.append(sm)
	var scr := _place(q, Vector3(mid.x, mid.y, 0) + nrm * 0.0205, sm, root)
	scr.basis = tb
	# an invisible, unclickable "screen" so the zoom / fill-the-view buttons work on the arcade monitor like on the TV and PC
	var arc_focus := ScreenUI.new()
	arc_focus.screen_size = q.size
	arc_focus.enabled = false
	scr.add_child(arc_focus)
	screens.append(arc_focus)
	arcade_focus = arc_focus
	# marquee: a lit panel above the monitor
	arcade_marquee_m = _mat(Color(0.95, 0.97, 0.92), 0.4, 0.9)
	var mq := _box(Vector3(0.7125, 1.65, 0), Vector3(0.004, 0.2, CAB_W - 0.09), arcade_marquee_m, root)
	_box(Vector3(0.7145, 1.74, 0), Vector3(0.002, 0.012, CAB_W - 0.09), green, root)
	_box(Vector3(0.7145, 1.56, 0), Vector3(0.002, 0.012, CAB_W - 0.09), green, root)
	var ml := Label3D.new()
	ml.text = "ARCADE"
	ml.font_size = 90
	ml.pixel_size = 0.0014
	ml.outline_size = 0
	ml.modulate = Color(0.08, 0.45, 0.2)
	ml.rotation = Vector3(0, PI / 2.0, 0)
	ml.position = Vector3(0.7165, 1.65, 0)
	root.add_child(ml)
	arcade_marquee_label = ml
	# the power switch: a red rocker low on the side panel, round the back
	var sw_m := _mat(Color(0.85, 0.12, 0.12), 0.4)
	var sw_plate := _box(Vector3(0.14, 0.32, -hw - 0.006), Vector3(0.06, 0.09, 0.012), _mat(Color(0.2, 0.2, 0.22), 0.5), root)
	var sw := _box(Vector3(0.14, 0.32, -hw - 0.016), Vector3(0.028, 0.05, 0.012), sw_m, root)
	sw.rotation.x = -0.25
	interactables.append({"node": sw_plate, "half": Vector3(0.05, 0.07, 0.03), "egg_lock": true, "group": "games",
		"label": func() -> String: return "ARCADE POWER  [%s]" % ("ON" if arcade_on else "OFF"),
		"cb": _toggle_arcade_power, "hover": _glow_hover(sw_m)})
	# volume: two small buttons on the front panel under the control deck, and a little readout between them
	var vol_m := _mat(Color(0.12, 0.12, 0.14), 0.4)
	for vi in 2:
		var up := vi == 1
		var vz := -0.07 if up else 0.04
		var vb := _box(Vector3(1.052, 0.862, vz), Vector3(0.006, 0.03, 0.032), vol_m, root)
		var vl := Label3D.new()
		vl.text = "+" if up else "-"
		vl.font_size = 40
		vl.pixel_size = 0.0007
		vl.outline_size = 0
		vl.modulate = Color(0.92, 0.92, 0.95)
		vl.rotation = Vector3(0, PI / 2.0, 0)
		vl.position = Vector3(1.0556, 0.863, vz)
		root.add_child(vl)
		interactables.append({"node": vb, "half": Vector3(0.025, 0.025, 0.025), "guest_ok": true,
			"label": func() -> String: return "ARCADE VOLUME  %s  [%d / 10]" % ["+" if up else "-", arcade_volume],
			"cb": func() -> void: set_arcade_volume(arcade_volume + (1 if up else -1)), "hover": _glow_hover(vol_m)})
	arcade_vol_label = Label3D.new()
	arcade_vol_label.font_size = 30
	arcade_vol_label.pixel_size = 0.0007
	arcade_vol_label.outline_size = 0
	arcade_vol_label.modulate = Color(0.25, 0.85, 0.4)
	arcade_vol_label.rotation = Vector3(0, PI / 2.0, 0)
	arcade_vol_label.position = Vector3(1.0514, 0.862, -0.015)
	root.add_child(arcade_vol_label)
	_show_arcade_volume()
	# the step from the monitor up to the marquee, the roof, and the sloped back
	_box(Vector3(0.675, 1.515, 0), Vector3(0.08, 0.04, CAB_W - 0.07), white, root)
	_arcade_grill(root, white)
	var rf := Vector2(0.50, 1.80) - Vector2(0.71, 1.77)
	_rbox(Vector3(0.605, 1.785, 0), Vector3(CAB_W - 0.07, 0.03, 0.23), Basis(Vector3(0, 0, 1), atan2(rf.y, rf.x) + PI) * Basis(Vector3.UP, PI / 2.0), white, root)
	var bk := Vector2(0.0, 1.40) - Vector2(0.50, 1.80)
	_rbox(Vector3(0.25, 1.60, 0), Vector3(CAB_W - 0.07, 0.03, 0.64), Basis(Vector3(0, 0, 1), atan2(bk.y, bk.x) + PI) * Basis(Vector3.UP, PI / 2.0), white, root)
	_box(Vector3(0.2, 0.7, 0), Vector3(0.4, 1.4, CAB_W - 0.07), white, root)       # filler so the inside never shows
	# a little glow on the floor and the player from the screen
	arcade_light = OmniLight3D.new()
	arcade_light.position = Vector3(1.05, 1.25, 0)
	arcade_light.light_color = Color(0.6, 0.85, 1.0)
	arcade_light.light_energy = 0.0
	arcade_light.omni_range = 2.2
	root.add_child(arcade_light)
	# interaction: the arcade controls (stick and buttons)
	var zl := CAB_W * 0.5 - 0.02                      # the shelf runs from -zl to +zl; the split divides it
	for sd in 2:
		var z0: float = ARC_SPLIT_Z if sd == 0 else -zl
		var z1: float = zl if sd == 0 else ARC_SPLIT_Z
		var hit := _box(Vector3(0.94, 0.9005, (z0 + z1) * 0.5), Vector3(0.2, 0.001, z1 - z0), speck, root)
		hit.visible = false
		interactables.append({"node": hit, "half": Vector3(0.12, 0.05, (z1 - z0) * 0.5), "egg_lock": true, "when": func() -> bool: return arcade_on,
			"label": _arcade_label.bind(sd), "cb": _pick_arcade.bind(sd), "guest_ok": true})


func _arcade_label(side: int) -> String:
	var who := "LEFT PLAYER" if side == 0 else "RIGHT PLAYER"
	if slot_cart != "neo":
		return who + " CONTROLS  (insert the Neo Geo cart first)"
	return "PLAY AS " + who


func _toggle_arcade_power() -> void:
	if egg_active or _net_play_lock():
		return
	set_arcade_on(not arcade_on)
	_save_settings()


func set_arcade_on(on: bool) -> void:
	arcade_on = on
	if not on and game_mode and held_pad_idx == -1:
		_put_pad()                             # you were at the sticks: step away
	if arcade_marquee_m != null:
		arcade_marquee_m.emission_energy_multiplier = 0.9 if on else 0.0
		arcade_marquee_m.albedo_color = Color(0.95, 0.97, 0.92) if on else Color(0.45, 0.46, 0.44)
		arcade_marquee_label.modulate = Color(0.08, 0.45, 0.2) if on else Color(0.1, 0.22, 0.14)
	for gm in arcade_glow:
		var gmat := gm[0] as StandardMaterial3D
		gmat.emission_energy_multiplier = float(gm[1]) if on else 0.0
		gmat.albedo_color = gm[2] if on else (gm[2] as Color).darkened(0.72)      # unlit plastic, not glowing
	_show_arcade_volume()
	_apply_console()


var cat_purr_on := true               # PC setting: the cats' purring can be switched off


func set_cat_purr(on: bool) -> void:
	cat_purr_on = on
	load("res://cozy_cat.gd").muted = not on
	_save_settings()
	settings_changed.emit()


func set_share_poster(on: bool) -> void:
	share_poster = on
	_save_settings()
	settings_changed.emit()


# the cabinet's own speaker: a black slotted grill in the underside of a hood along the marquee, facing down. Only the arcade's games
# play out of it (their sound comes from right here, not from the room's speakers).
var arcade_feed: Node


func _arcade_grill(root: Node3D, body: Material) -> void:
	# a shallow hood along the bottom of the marquee, sticking out over the screen, with the grill in its
	# underside facing down at the player
	var gw := CAB_W - 0.07
	var x0 := 0.714
	var x1 := 0.80
	var yb := 1.517                                  # the hood's underside
	_box(Vector3((x0 + x1) / 2.0, yb + 0.015, 0), Vector3(x1 - x0, 0.03, gw), body, root)
	var plate := _mat(Color(0.11, 0.11, 0.12), 0.45, 0.5)
	var holes := _mat(Color(0.0, 0.0, 0.0), 1.0)
	_box(Vector3((x0 + x1) / 2.0 + 0.002, yb - 0.001, 0), Vector3(x1 - x0 - 0.016, 0.002, gw - 0.05), plate, root)
	# two speaker patches, left and right, each a few long straight slots (no round holes: trypophobia)
	var xc := (x0 + x1) / 2.0 + 0.002
	var hx := (x1 - x0 - 0.03) / 2.0
	var hz := gw * 0.19
	for side in [-1.0, 1.0]:
		var zc: float = side * gw * 0.25
		for k in 5:
			var x := xc - hx + (k + 0.5) * (2.0 * hx / 5.0)
			_box(Vector3(x, yb - 0.0025, zc), Vector3(0.0035, 0.001, hz * 2.0), holes, root)
	var BusFeed := preload("res://bus_feed.gd")
	var p: AudioStreamPlayer3D = BusFeed.make_player(3.0)
	p.position = Vector3(0.76, 1.5, 0)
	root.add_child(p)
	arcade_feed = BusFeed.new()
	arcade_feed.name = "ArcadeFeed"
	add_child(arcade_feed)
	arcade_feed.setup("Arcade")              # (its sound plays straight from the bus: the re-played copy went silent on Windows)


func set_arcade_volume(v: int) -> void:
	arcade_volume = clampi(v, 0, 10)
	_show_arcade_volume()
	_save_settings()


func _show_arcade_volume() -> void:
	if arcade_vol_label != null:
		arcade_vol_label.text = "VOL %d" % arcade_volume
		arcade_vol_label.visible = arcade_on


func _pick_arcade(side: int) -> void:
	if game_mode or slot_cart != "neo" or not arcade_on:
		return
	arcade_side = side
	if emu != null:
		emu.local_port = side                    # left player = port 0, right player = port 1
	game_mode = true
	held_pad_idx = -1
	_pad_stick_prev = false
	pad_hint_t = 8.0
	if emu != null:
		emu.set_pad(true)


# Neo Geo: a big black block, stepped shoulders, fins across the lower part and a small label up top with blue stripes beside it.
func _neo_cart_mesh() -> Node3D:
	var n := _cart_node(0.0975, 0.0)
	var blk := _tm(func(w: bool) -> Color: return _wc(Color(0.105, 0.105, 0.12), 0.28, w), 0.5)
	var fin := _tm(func(w: bool) -> Color: return _wc(Color(0.12, 0.12, 0.14), 0.36, w), 0.5)
	var dark := _mat(Color(0.02, 0.02, 0.03), 0.7)
	var t := 0.032
	_extrude_poly([Vector2(-0.125, -0.0925), Vector2(0.125, -0.0925), Vector2(0.125, 0.073), Vector2(0.108, 0.073), Vector2(0.108, 0.0925),
		Vector2(-0.108, 0.0925), Vector2(-0.108, 0.073), Vector2(-0.125, 0.073)], -t / 2.0, t / 2.0, blk, n)
	_box(Vector3(0, -0.0965, 0), Vector3(0.19, 0.008, 0.014), _mat(GOLD, 0.4), n)                                   # contacts
	for i in 7:
		_box(Vector3(0, -0.0865 + i * 0.0072, 0), Vector3(0.25, 0.0034, t + 0.002), fin, n)                      # fins
	_box(Vector3(0, 0.052, t / 2.0 + 0.0002), Vector3(0.126, 0.0625, 0.0004), dark, n)                            # label pocket
	_label_quad(CartArt.neo_label(), Vector2(0.116, 0.056), Vector3(0, 0.052, t / 2.0 + 0.0008), n)
	for sx in [-1.0, 1.0]:
		for off in [0.0705, 0.0745]:
			_box(Vector3(sx * off, 0.052, t / 2.0 + 0.0004), Vector3(0.0018, 0.058, 0.0006), _mat(Color(0.20, 0.80, 0.85), 0.5), n)
	_cart_text("NEO", 46, 0.0005, Color(1.0, 0.93, 0.8), Vector3(0.031, 0.0635, t / 2.0 + 0.0014), n)
	_cart_text("GEO", 46, 0.0005, Color(1.0, 0.93, 0.8), Vector3(0.031, 0.0435, t / 2.0 + 0.0014), n)
	return n


# The carts lie on the floor around the console, somewhere new every visit: never inside the console, the TV,
# the controllers, a wall or a beanbag spot, and never through each other.
var cart_spots := {}                   # id -> Transform3D in lounge coordinates
const CART_RADIUS := {"nes": 0.085, "snes": 0.085, "sgb": 0.08, "gen": 0.085, "neo": 0.14}


func _scatter_carts() -> void:
	var lay := Basis(Vector3.RIGHT, -PI / 2.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var centre := Vector2(-2.60, 1.45 + LOUNGE_DZ)                # the console
	var console_rect := Rect2(-2.75, 1.15 + LOUNGE_DZ, 0.4, 0.55)
	var tv_rect := Rect2(-4.0, 0.1 + LOUNGE_DZ, 1.2, 1.7)
	var pads := [Vector2(-2.0, 2.58), Vector2(-2.25, 2.25)]
	var placed: Array = []                                           # [Vector2, radius]
	var ids := ["neo", "nes", "snes", "gen", "sgb"]                  # biggest first, it is the hardest to fit
	for id in ids:
		var r: float = CART_RADIUS[id]
		var best := Vector2.ZERO
		var found := false
		for attempt in 400:
			var ang := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(0.42, 0.78)
			var p := centre + Vector2(cos(ang), sin(ang)) * dist
			if console_rect.grow(r + 0.03).has_point(p) or tv_rect.grow(r + 0.02).has_point(p):
				continue
			var ok := true
			for pd in pads:
				if p.distance_to(pd) < r + 0.17:
					ok = false
			for o in placed:
				if p.distance_to(o[0]) < r + float(o[1]) + 0.01:
					ok = false
			var w := lounge.to_global(Vector3(p.x, 0.0, p.y))
			if w.x < -3.9 + r + 0.05 or w.z > FRONT_Z - r - 0.05 or not _walkable(w.x, w.z):
				ok = false
			for layout in BEANBAG_LAYOUTS:
				for sp in layout:
					if Vector2(w.x, w.z).distance_to(sp) < r + 0.6:
						ok = false
			if ok:
				best = p
				found = true
				break
		if not found:
			best = centre + Vector2(0.55, 0.0).rotated(float(placed.size()) * 1.2)     # the fallback keeps them apart at least
		placed.append([best, r])
		cart_spots[id] = Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)) * lay, Vector3(best.x, 0.034, best.y))


func _build_carts() -> void:
	var lay := Basis(Vector3.RIGHT, -PI / 2.0)       # lying flat, label up
	var nes := _nes_cart_mesh()
	var snes := _snes_cart_mesh()
	var sgb := _sgb_cart_mesh()
	var gen := _gen_cart_mesh()
	var neo := _neo_cart_mesh()
	var egg_c := _nes_cart_mesh(true)
	_scatter_carts()
	carts["nes"] = {"node": nes, "name": "NES CART", "busy": false,
		"home": func() -> Transform3D: return lounge.global_transform * cart_spots["nes"]}
	carts["snes"] = {"node": snes, "name": "SNES CART", "busy": false,
		"home": func() -> Transform3D: return lounge.global_transform * cart_spots["snes"]}
	carts["sgb"] = {"node": sgb, "name": "SUPER GB CART", "busy": false,
		"home": func() -> Transform3D: return lounge.global_transform * cart_spots["sgb"]}
	carts["gen"] = {"node": gen, "name": "SEGA CART", "busy": false,
		"home": func() -> Transform3D: return lounge.global_transform * cart_spots["gen"]}
	carts["neo"] = {"node": neo, "name": "NEO GEO CART", "busy": false,
		"home": func() -> Transform3D: return lounge.global_transform * cart_spots["neo"]}
	carts["egg"] = {"node": egg_c, "name": "CART", "busy": false,
		"home": func() -> Transform3D: return drawer_node.global_transform * Transform3D(Basis(Vector3.UP, 0.15) * lay, Vector3(0, -0.053, -0.15))}
	for id in ["nes", "snes", "sgb", "gen", "neo"]:
		var n: Node3D = carts[id]["node"]
		n.global_transform = (carts[id]["home"] as Callable).call()
	egg_c.reparent(drawer_node, false)
	egg_c.transform = Transform3D(Basis(Vector3.UP, 0.15) * lay, Vector3(0, -0.053, -0.15))
	for id in ["nes", "snes", "sgb", "gen", "neo", "egg"]:
		interactables.append({"node": carts[id]["node"], "half": Vector3(0.085, 0.065, 0.03), "egg_lock": true, "group": "games",
			"label": _cart_label.bind(id), "cb": _cart_click.bind(id)})


func _cart_label(id: String) -> String:
	if slot_cart == id:
		return "EJECT CART"
	return "INSERT " + String(carts[id]["name"])


func _cart_click(id: String) -> void:
	if egg_active or bool(carts[id]["busy"]) or _net_play_lock() or _cat_on_console():
		return
	if slot_cart == id:
		_eject_cart()
	else:
		_insert_cart(id)


func _fly_cart(id: String, to: Transform3D, on_done: Callable = Callable()) -> void:
	var c: Dictionary = carts[id]
	var n: Node3D = c["node"]
	c["busy"] = true
	var from := n.global_transform
	var q0 := from.basis.get_rotation_quaternion()
	var q1 := to.basis.get_rotation_quaternion()
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		var e := k * k * (3.0 - 2.0 * k)
		n.global_transform = Transform3D(Basis(q0.slerp(q1, e)), from.origin.lerp(to.origin, e) + Vector3(0.0, sin(e * PI) * 0.14, 0.0)),
		0.0, 1.0, 0.55)
	tw.finished.connect(func() -> void:
		n.global_transform = to
		c["busy"] = false
		if on_done.is_valid():
			on_done.call())


func _insert_cart(id: String) -> void:
	if slot_cart != "":
		_eject_cart()
	slot_cart = id
	var n: Node3D = carts[id]["node"]
	if n.get_parent() != game_kit:
		n.reparent(game_kit, true)
	if id == "neo":
		_fly_cart(id, cab_root.global_transform * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.776, 0.52, 0.0)))   # upright in the cart bay, label out
	else:
		_fly_cart(id, console_root.global_transform * Transform3D(Basis.IDENTITY,
			Vector3(0, CON_TOP - float(n.get_meta("depth")) + float(n.get_meta("bottom")), CON_SLOT_Z)))
	_cart_changed()


func _eject_cart() -> void:
	var id := slot_cart
	if id == "":
		return
	slot_cart = ""
	var home: Transform3D = (carts[id]["home"] as Callable).call()
	if id == "egg":
		_fly_cart(id, home, func() -> void: (carts["egg"]["node"] as Node3D).reparent(drawer_node, true))
	else:
		_fly_cart(id, home)
	_cart_changed()


func _cart_changed() -> void:
	konami_progress = 0
	_close_controls()
	if slot_cart != "" and slot_cart != "neo":
		_set_lid(true)
	else:
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if slot_cart == "" or slot_cart == "neo":
				_set_lid(false))
	if emu != null:
		emu.set_system(slot_cart if (slot_cart in ["nes", "snes", "sgb", "gen", "neo"]) else "")
	_apply_console()


# ---- remembered between visits: volumes, speakers, lights, curtains, weather levels, music repeat, TV volume

var _prefs_last := {}
var weather_start := "random"          # "random" = a new random weather every visit, "remember" = the weather you left


func set_resume_games(on: bool) -> void:
	if emu != null:
		emu.resume_games = on
	_save_settings()
	settings_changed.emit()


# what you see looking down off the balcony: a sea of fog, the street far below, or the street under thinner fog
const BELOW_VIEWS := ["fog", "street", "both"]
var below_view := "fog"

func set_below_view(v: String) -> void:
	below_view = v if v in BELOW_VIEWS else "fog"
	_apply_below_view()
	_save_settings()
	settings_changed.emit()


func _apply_below_view() -> void:
	if weather != null:
		weather.below_fog = {"fog": 1.0, "street": 0.0, "both": 0.45}[below_view]
	if apartment != null and apartment.street != null:
		apartment.street.visible = below_view != "fog"


func set_weather_start(s: String) -> void:
	weather_start = "remember" if s == "remember" else "random"
	_save_settings()
	settings_changed.emit()


func set_crt_mode(v: int) -> void:
	crt_mode = clampi(v, 0, 2)
	for cm in crt_mats:
		cm.set_shader_parameter("crt_mode", crt_mode)


func _prefs_now() -> Dictionary:
	var d := {}
	d["crt_mode"] = crt_mode
	d["music_vol"] = snappedf(bank.master, 0.01)
	d["bed_made"] = bed_made
	d["repeat"] = pc.repeat_mode
	d["tv_volume"] = vcr.tv_volume
	d["curtain"] = snappedf(curtain_target, 0.01) if not egg_active else float(_prefs_last.get("curtain", 0.0))
	if not weather.locked:
		d["weather_mode"] = weather.mode
	elif _prefs_last.has("weather_mode"):
		d["weather_mode"] = _prefs_last["weather_mode"]
	d["traffic_muted"] = weather.traffic_muted
	d["weather_vol"] = snappedf(weather.volume, 0.01)
	d["levels"] = [snappedf(weather.real_level(1), 0.01), snappedf(weather.real_level(2), 0.01), snappedf(weather.real_level(3), 0.01)]
	for i in bank.speakers.size():
		d["spk_" + String(bank.speakers[i]["name"])] = bank.get_mode(i)
	d["spk_ver"] = 2
	for gi in light_groups.size():
		d["light_" + String(light_groups[gi]["name"])] = is_light_on(gi)
	return d


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and pc != null:
		pc.save_music_dir()                     # closing the window keeps the music folder you were in
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		load("res://diary.gd").close_open_session()      # a game still running counts up to now


func _save_prefs_tick() -> void:
	if egg_active or weather == null or bank == null:
		return
	var d := _prefs_now()
	if d == _prefs_last:
		return
	_prefs_last = d
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	for k in d:
		cfg.set_value("room", k, d[k])
	cfg.save(SETTINGS_FILE)


func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK and cfg.has_section("room"):
		var g := func(k: String, def: Variant) -> Variant: return cfg.get_value("room", k, def)
		pc._set_volume(clampf(float(g.call("music_vol", 0.7)), 0.0, 1.0))
		bed_made = bool(g.call("bed_made", true))
		if not bed_made:
			_rebuild_bed()
		pc._set_repeat(clampi(int(g.call("repeat", 0)), 0, 2))
		vcr.tv_volume = clampi(int(g.call("tv_volume", vcr.tv_volume)), 0, 10)
		set_crt_mode(int(g.call("crt_mode", 1)))
		vcr._apply_volume()
		weather.set_volume(float(g.call("weather_vol", weather.volume)))
		pc._wx_vol.set_value_no_signal(weather.volume)
		weather.traffic_muted = bool(g.call("traffic_muted", false))
		var lv: Variant = g.call("levels", [])
		if lv is Array and (lv as Array).size() == 3:
			for i in 3:
				weather.set_level(i + 1, float(lv[i]))              # the kind of weather is still random, its strength is yours
			weather.snap()
		emu.resume_games = bool(cfg.get_value("settings", "resume_games", true))
		set_cart_style_quiet(bool(cfg.get_value("settings", "cart_wash", true)))
		below_view = str(cfg.get_value("settings", "below_view", "fog"))
		slap_minutes = int(cfg.get_value("settings", "slap_minutes", 30))
		for gk in guest_allow:
			guest_allow[gk] = bool(cfg.get_value("guests", gk, false))
		arcade_volume = clampi(int(cfg.get_value("settings", "arcade_volume", 7)), 0, 10)
		share_poster = bool(cfg.get_value("settings", "share_poster", false))
		shelf_hints = bool(cfg.get_value("settings", "shelf_hints", false))
		cat_purr_on = bool(cfg.get_value("settings", "cat_purr", true))
		load("res://cozy_cat.gd").muted = not cat_purr_on
		_show_arcade_volume()
		if not bool(cfg.get_value("settings", "arcade_on", true)):
			set_arcade_on(false)
		if bool(cfg.get_value("settings", "phone_hidden", false)):
			phone_hidden = true
			if net_phone != null:
				net_phone.visible = false
				net_phone.ui.enabled = false
		weather_start = "remember" if str(cfg.get_value("settings", "weather_start", "random")) == "remember" else "random"
		if weather_start == "remember" and cfg.has_section_key("room", "weather_mode"):
			weather.set_mode(clampi(int(cfg.get_value("room", "weather_mode", 0)), 0, 3))
			weather.snap()
		for i in bank.speakers.size():
			var sn := String(bank.speakers[i]["name"])
			var def := "tv" if sn.begins_with("Living") or sn.begins_with("Theater") else ("lp" if sn.begins_with("Record") else "pc")
			var sv: Variant = g.call("spk_" + sn, def)
			if int(g.call("spk_ver", 1)) < 2 and def != "pc":
				sv = def                    # (the TVs and the record player became separate: their speakers start on them once)
			bank.set_mode(i, ("pc" if sv else "off") if sv is bool else str(sv))     # (older copies saved on/off)
		for gi in light_groups.size():
			set_light(gi, bool(g.call("light_" + String(light_groups[gi]["name"]), true)))
		var cu := clampf(float(g.call("curtain", 0.0)), 0.0, 1.0)
		curtain_amt = cu
		curtain_target = cu
		curtain_last_down = cu > 0.5
		_update_curtain_mesh()          # the cloth itself has to follow, or it stays hidden while the room goes dark
		pc._wx_refresh()
	_prefs_last = _prefs_now()
	var tm := Timer.new()
	tm.wait_time = 1.5
	tm.autostart = true
	tm.timeout.connect(_save_prefs_tick)
	add_child(tm)


# ---- settings (the PC has a Settings window): the dot in the middle of the view

func _build_reticle() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	reticle = Reticle.new()
	layer.add_child(reticle)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK:
		reticle_on = bool(cfg.get_value("settings", "reticle_on", true))
		reticle_color_idx = clampi(int(cfg.get_value("settings", "reticle_color", 0)), 0, RETICLE_COLORS.size() - 1)
	_apply_reticle()


func _apply_reticle() -> void:
	if reticle != null:
		reticle.dot_color = RETICLE_COLORS[reticle_color_idx][1]


# ---- fullscreen on a screen (F11 or Alt+Enter, or the PC's Settings); on by default, remembered

var fullscreen := true


func _apply_fullscreen_setting() -> void:
	if get_tree().get_script() != null:
		return                                   # (test scripts keep their own window size)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK:
		fullscreen = bool(cfg.get_value("settings", "fullscreen", true))
	_set_window(fullscreen)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_set_window(on)
	_save_settings()
	settings_changed.emit()


func _set_window(on: bool) -> void:
	if xr_active or Plat.is_android() or DisplayServer.get_name() == "headless":
		return
	var cur := DisplayServer.window_get_mode()
	if on and cur != DisplayServer.WINDOW_MODE_FULLSCREEN and cur != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)      # borderless: no title bar, no taskbar
	elif not on and cur != DisplayServer.WINDOW_MODE_WINDOWED and cur != DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	cfg.set_value("settings", "fullscreen", fullscreen)
	cfg.set_value("settings", "reticle_on", reticle_on)
	cfg.set_value("settings", "reticle_color", reticle_color_idx)
	cfg.set_value("settings", "weather_start", weather_start)
	cfg.set_value("settings", "resume_games", emu.resume_games if emu != null else true)
	cfg.set_value("settings", "cart_wash", cart_wash)
	cfg.set_value("settings", "below_view", below_view)
	cfg.set_value("settings", "phone_hidden", phone_hidden)
	cfg.set_value("settings", "slap_minutes", slap_minutes)
	cfg.set_value("settings", "arcade_on", arcade_on)
	cfg.set_value("settings", "arcade_volume", arcade_volume)
	cfg.set_value("settings", "share_poster", share_poster)
	cfg.set_value("settings", "shelf_hints", shelf_hints)
	cfg.set_value("settings", "cat_purr", cat_purr_on)
	for g in guest_allow:
		cfg.set_value("guests", g, guest_allow[g])
	cfg.save(SETTINGS_FILE)


func set_reticle_on(on: bool) -> void:
	reticle_on = on
	_save_settings()
	settings_changed.emit()


func set_reticle_color(i: int) -> void:
	reticle_color_idx = clampi(i, 0, RETICLE_COLORS.size() - 1)
	_apply_reticle()
	_save_settings()
	settings_changed.emit()


# ---- controllers (the ones on the rug can be picked up; while held they drive the game)

# Where the held pad sits in the desktop view: normal, zoomed in on the screen, screen fills the view.
# The closer the screen, the lower the pad, so it never covers the picture.
const PAD_VIEW_POS := [Vector3(0.13, -0.17, -0.34), Vector3(0.13, -0.225, -0.34), Vector3(0.13, -0.42, -0.34)]


func _update_held_pad(delta: float) -> void:
	if held_pad == null or xr_active:
		return
	var target: Vector3 = PAD_VIEW_POS[clampi(focus_level, 0, 2)]
	if seated:
		target.y += 0.05
	held_pad.position = held_pad.position.lerp(target, clampf(8.0 * delta, 0.0, 1.0))


func _pick_pad(idx: int) -> void:
	if game_mode:
		return
	game_mode = true
	if emu != null:
		emu.local_port = 0                       # the console pads are player 1 for now
	held_pad_idx = idx
	pad_nodes[idx].visible = false
	held_pad = Node3D.new()
	_pad_meshes(held_pad)
	if xr_active:
		var hand := left_hand if hover_hand == 0 else right_hand
		hand.add_child(held_pad)
		held_pad.position = Vector3(0.0, -0.03, -0.09)
	else:
		desktop_cam.add_child(held_pad)
		_draw_on_top(held_pad)
		held_pad.position = PAD_VIEW_POS[0]
		held_pad.rotation = Vector3(0.9, 0.0, 0.0)
		held_pad.scale = Vector3.ONE * 1.15
	_pad_stick_prev = false
	pad_hint_t = 8.0
	if emu != null:
		emu.set_pad(true)


# Draws a node's meshes and labels over the scene (no depth test), so the held pad never clips
# into the beanbag, the cushions or the TV when you sit or lean in.
func _draw_on_top(n: Node, prio: Array = [0]) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var src: Material = mi.material_override
		if src == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			src = mi.mesh.surface_get_material(0)
		if src is BaseMaterial3D:
			var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
			m.no_depth_test = true
			prio[0] += 1
			m.render_priority = mini(prio[0], 100)
			mi.material_override = m
	elif n is Label3D:
		(n as Label3D).no_depth_test = true
		(n as Label3D).render_priority = 110
	for c in n.get_children():
		_draw_on_top(c, prio)


func _put_pad() -> void:
	if not game_mode:
		return
	_close_controls()
	game_mode = false
	if held_pad != null:
		held_pad.queue_free()
		held_pad = null
	if held_pad_idx >= 0:
		pad_nodes[held_pad_idx].visible = true
	held_pad_idx = -1
	if emu != null:
		emu.set_pad(false)


# What the pad does is set by padmap.gd (bindings for gamepad, keyboard and VR; the menus have fixed controls).
func _pad_tick(delta: float) -> void:
	var lh: Node = left_hand if xr_active else null
	var rh: Node = right_hand if xr_active else null
	var mapped := padmap.mask(xr_active, lh, rh)
	var nav := padmap.nav_mask(xr_active, lh, rh)
	var all := nav | mapped
	var sel_edge := all & ~_nav_prev & Emu.B_SELECT
	_nav_prev = all
	if emu.state == Emu.State.RUNNING:
		emu.set_buttons(mapped)
	elif ctl_open:
		_controls_tick(nav | (mapped & Emu.B_A), delta)
		emu.set_buttons(0)
	elif sel_edge != 0 and (console_on or slot_cart == "neo") and slot_cart != "egg":
		_open_controls(nav)
		emu.set_buttons(0)
	else:
		emu.set_buttons(all)


# ---- the controls (remap) screen, drawn on the TV by emu.gd while you hold a controller

const CTL_ROWS := 17             # device, swap A/B, swap X/Y, 12 buttons, reset, back


func _ctl_devices() -> Array:
	if xr_active:
		return ["vr"]
	var d := ["key"]
	if padmap.has_gamepad():
		d.append("pad")
	return d


func _open_controls(nav: int) -> void:
	ctl_open = true
	var d := _ctl_devices()
	ctl_dev = "vr" if xr_active else ("pad" if d.has("pad") else "key")
	ctl_sel = 0
	ctl_listen = ""
	_ctl_prev = nav
	_ctl_block = 0.35
	_ctl_draw()


func _close_controls() -> void:
	if not ctl_open:
		return
	ctl_open = false
	ctl_listen = ""
	_nav_prev = 0xFFFF
	if emu != null:
		emu.end_custom()


func _ctl_draw() -> void:
	var dev_names := {"pad": "GAMEPAD", "key": "KEYBOARD", "vr": "VR CONTROLLERS"}
	var lines: Array = ["DEVICE:  " + String(dev_names[ctl_dev])]
	lines.append("A AND B:  " + ("SWAPPED" if padmap.is_swapped(ctl_dev, "a", "b") else "NORMAL"))
	lines.append("X AND Y:  " + ("SWAPPED" if padmap.is_swapped(ctl_dev, "x", "y") else "NORMAL"))
	for a in PadMap.ACTIONS:
		var v := "PRESS A BUTTON..." if ctl_listen == a else padmap.name_of(padmap.maps[ctl_dev][a])
		lines.append("%s  =  %s" % [PadMap.LABELS[a], v])
	lines.append("RESET THIS DEVICE")
	lines.append("BACK")
	var foot := "UP/DOWN CHOOSE    A CHANGE    SELECT BACK"
	if ctl_listen != "":
		foot = "PRESS THE BUTTON YOU WANT FOR %s" % String(PadMap.LABELS[ctl_listen])
	emu.show_custom("CONTROLS", lines, ctl_sel, foot)


func _ctl_cycle_device(step: int) -> void:
	var d := _ctl_devices()
	var i := d.find(ctl_dev)
	ctl_dev = d[(i + step + d.size()) % d.size()]
	_ctl_draw()


func _ctl_swap(a: String, b: String) -> void:
	padmap.swap_pair(ctl_dev, a, b)
	_ctl_draw()


func _ctl_activate() -> void:
	if ctl_sel == 0:
		_ctl_cycle_device(1)
	elif ctl_sel == 1:
		_ctl_swap("a", "b")
	elif ctl_sel == 2:
		_ctl_swap("x", "y")
	elif ctl_sel <= 14:
		ctl_listen = PadMap.ACTIONS[ctl_sel - 3]
		ctl_listen_t = 8.0
		var lh: Node = left_hand if xr_active else null
		var rh: Node = right_hand if xr_active else null
		ctl_base = padmap.held(ctl_dev, lh, rh)
		_ctl_draw()
	elif ctl_sel == 15:
		padmap.reset(ctl_dev)
		_ctl_draw()
	else:
		_close_controls()


func _ctl_bind(binding: String) -> void:
	padmap.assign(ctl_dev, ctl_listen, binding)
	ctl_listen = ""
	_ctl_block = 0.35
	_ctl_draw()


func _controls_tick(nav: int, delta: float) -> void:
	_ctl_block = maxf(0.0, _ctl_block - delta)
	if ctl_listen != "":
		ctl_listen_t -= delta
		if ctl_dev != "key":
			var lh: Node = left_hand if xr_active else null
			var rh: Node = right_hand if xr_active else null
			var got := padmap.poll(ctl_dev, lh, rh, ctl_base)
			if got != "":
				_ctl_bind(got)
				_ctl_prev = nav
				return
		if ctl_listen_t <= 0.0:
			ctl_listen = ""
			_ctl_block = 0.35
			_ctl_draw()
		_ctl_prev = nav
		return
	var edge := nav & ~_ctl_prev
	if _ctl_block > 0.0:
		edge = 0
	if nav & (Emu.B_UP | Emu.B_DOWN) != 0 and _ctl_prev & (Emu.B_UP | Emu.B_DOWN) != 0:
		_ctl_rep += delta                          # held: repeat after a short wait
		if _ctl_rep > 0.4:
			_ctl_rep = 0.32
			edge |= nav & (Emu.B_UP | Emu.B_DOWN)
	else:
		_ctl_rep = 0.0
	_ctl_prev = nav
	if edge & Emu.B_UP:
		ctl_sel = (ctl_sel - 1 + CTL_ROWS) % CTL_ROWS
		_ctl_draw()
	elif edge & Emu.B_DOWN:
		ctl_sel = (ctl_sel + 1) % CTL_ROWS
		_ctl_draw()
	elif edge & (Emu.B_LEFT | Emu.B_RIGHT) and ctl_sel <= 2:
		if ctl_sel == 0:
			_ctl_cycle_device(1)
		elif ctl_sel == 1:
			_ctl_swap("a", "b")
		else:
			_ctl_swap("x", "y")
	elif edge & Emu.B_A:
		_ctl_activate()
	elif edge & Emu.B_SELECT:
		_close_controls()


func _pad_label() -> String:
	return "PICK UP CONTROLLER"


# A modern pad in the style of the reference picture: black rounded body with long grips, grey shoulder buttons, two big
# round dials (arrows on the left, Y X A B on the right), SELECT / HOME / START and a small P button.
# Long axis along x, the dials face up (+y), the shoulder buttons and the cable are on the far edge (-z). Top surface y = 0.024.
func _flat_label(root: Node3D, text: String, pos: Vector3, size: int, col: Color, yaw: float = 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.00028
	l.modulate = col
	l.outline_size = 0
	l.rotation = Vector3(-PI / 2.0, yaw, 0.0)
	l.position = pos
	root.add_child(l)


func _flat_tri(root: Node3D, pos: Vector3, r: float, yaw: float, mat: Material) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = 0.0006
	m.radial_segments = 3
	m.rings = 1
	var mi := _place(m, pos, mat, root)
	mi.rotation.y = yaw


func _pad_meshes(root: Node3D) -> void:
	var black := _mat(Color(0.075, 0.075, 0.085), 0.55)
	var ring_m := _mat(Color(0.15, 0.15, 0.17), 0.5)
	var recess := _mat(Color(0.03, 0.03, 0.035), 0.6)
	var grey := _mat(Color(0.52, 0.52, 0.55), 0.5)
	var mid := _mat(Color(0.30, 0.30, 0.33), 0.5)
	var light := Color(0.86, 0.86, 0.9)
	var light_m := _mat(light, 0.5)
	# body and grips
	_sphere(Vector3(0, 0.012, -0.006), 1.0, black, Vector3(0.076, 0.012, 0.040), root, 40)
	for sx in [-1.0, 1.0]:
		var g := _sphere(Vector3(sx * 0.064, 0.011, 0.030), 1.0, black, Vector3(0.025, 0.011, 0.048), root, 28)
		g.rotation.y = -sx * 0.17
	# shoulder buttons and triggers (grey), along the far edge
	for sx in [-1.0, 1.0]:
		var bm := _box(Vector3(sx * 0.052, 0.0185, -0.033), Vector3(0.034, 0.008, 0.012), grey, root)
		bm.rotation.y = sx * 0.10
		_sphere(Vector3(sx * 0.058, 0.0150, -0.038), 1.0, grey, Vector3(0.020, 0.0075, 0.010), root, 16)
	# tiny buttons between the shoulders
	for bx in [-0.018, 0.018]:
		_sphere(Vector3(bx, 0.0235, -0.040), 1.0, mid, Vector3(0.006, 0.0014, 0.0025), root, 10)
	_cyl(Vector3(0, 0.0236, -0.041), 0.0035, 0.0016, recess, root)
	var zc := -0.006               # the row the dials sit on
	for side in [-1.0, 1.0]:
		var cx: float = side * 0.048
		_cyl(Vector3(cx, 0.0236, zc), 0.0245, 0.0012, recess, root)                      # recess under the dial
		var tr := TorusMesh.new()
		tr.inner_radius = 0.0165
		tr.outer_radius = 0.0238
		tr.rings = 32
		tr.ring_segments = 8
		var tmi := _place(tr, Vector3(cx, 0.0258, zc), ring_m, root)
		tmi.scale = Vector3(1.0, 0.45, 1.0)
		_sphere(Vector3(cx, 0.0262, zc), 1.0, grey, Vector3(0.0158, 0.0036, 0.0158), root, 28)      # the grey dial
		for t in 4:
			var ang := t * PI / 2.0
			var tk := _box(Vector3(cx + sin(ang) * 0.0105, 0.0299, zc - cos(ang) * 0.0105), Vector3(0.0011, 0.0004, 0.0042), mid, root)
			tk.rotation.y = ang
	# left ring: arrows
	var lx := -0.048
	_flat_tri(root, Vector3(lx, 0.0272, zc - 0.0203), 0.0033, PI / 2.0 * 0 + PI, light_m)      # up
	_flat_tri(root, Vector3(lx, 0.0272, zc + 0.0203), 0.0033, 0.0, light_m)                    # down
	_flat_tri(root, Vector3(lx - 0.0203, 0.0272, zc), 0.0033, -PI / 2.0, light_m)              # left
	_flat_tri(root, Vector3(lx + 0.0203, 0.0272, zc), 0.0033, PI / 2.0, light_m)               # right
	# right ring: Y top, X left, A right, B bottom
	var rx := 0.048
	_flat_label(root, "Y", Vector3(rx, 0.0292, zc - 0.0203), 30, light)
	_flat_label(root, "B", Vector3(rx, 0.0292, zc + 0.0203), 30, light)
	_flat_label(root, "X", Vector3(rx - 0.0203, 0.0292, zc), 30, light)
	_flat_label(root, "A", Vector3(rx + 0.0203, 0.0292, zc), 30, light)
	# centre: SELECT, HOME, START, and the small P button
	for bx in [-0.0125, 0.0125]:
		_cyl(Vector3(bx, 0.0242, zc), 0.0040, 0.0016, ring_m, root)
	_cyl(Vector3(0, 0.0242, zc), 0.0062, 0.0016, ring_m, root)
	_cyl(Vector3(0, 0.0246, zc), 0.0046, 0.0012, recess, root)
	_flat_tri(root, Vector3(0, 0.0256, zc - 0.0012), 0.0024, PI, light_m)                      # a little house
	_box(Vector3(0, 0.0256, zc + 0.0014), Vector3(0.0031, 0.0006, 0.0024), light_m, root)
	_flat_label(root, "SELECT", Vector3(-0.0125, 0.0250, zc + 0.0088), 11, light)
	_flat_label(root, "START", Vector3(0.0125, 0.0250, zc + 0.0088), 11, light)
	_flat_label(root, "HOME", Vector3(0, 0.0250, zc + 0.0102), 11, light)
	_cyl(Vector3(-0.0125, 0.0242, zc + 0.0185), 0.0038, 0.0016, ring_m, root)
	_flat_label(root, "P", Vector3(-0.0125, 0.0252, zc + 0.0185), 20, light)


func _controller(pos: Vector3, yaw_off: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = PI / 2.0 + yaw_off     # long axis along the wall, cable toward the console
	lounge.add_child(root)
	_pad_meshes(root)
	ctrl_exits.append(root.to_global(Vector3(0, 0.014, -0.052)))
	var idx := pad_nodes.size()
	pad_nodes.append(root)
	interactables.append({"node": root, "half": Vector3(0.095, 0.035, 0.065), "label": _pad_label, "cb": _pick_pad.bind(idx), "guest_ok": true,
		"when": func() -> bool: return root.visible or idx == held_pad_idx})       # a pad a friend is holding can't be grabbed


const DRESSER_Z := 0.15                  # the dresser's middle along the left wall


func _build_dresser() -> void:
	var wood := _mat(Color(0.34, 0.14, 0.22), 0.6)
	var inset := _mat(Color(0.26, 0.10, 0.18), 0.6)
	var brass := _mat(Color(0.95, 0.75, 0.50), 0.3, 0.5)
	_box(Vector3(-3.62, 0.38, DRESSER_Z), Vector3(0.55, 0.76, 1.1), wood)
	for dy in [0.2, 0.42, 0.64]:
		_box(Vector3(-3.335, dy, DRESSER_Z), Vector3(0.01, 0.17, 0.96), inset)
		_sphere(Vector3(-3.325, dy, DRESSER_Z), 0.016, brass, Vector3.ONE, null, 8)
	_plant(Vector3(-3.6, 0.76, DRESSER_Z - 0.25), 0.6)
	incense = Incense.new()
	incense.setup(self, Vector3(-3.6, 0.76, DRESSER_Z + 0.25))      # a stick of incense on the dresser


# ---------------------------------------------------------------- power: outlets, strips, cords

func _outlet(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	_host().add_child(root)
	_box(Vector3(0, 0, 0.006), Vector3(0.075, 0.115, 0.012), _mat(Color(0.92, 0.88, 0.92), 0.5), root)
	var slot := _mat(Color(0.12, 0.08, 0.14), 0.5)
	_box(Vector3(0, 0.028, 0.013), Vector3(0.018, 0.03, 0.004), slot, root)
	_box(Vector3(0, -0.028, 0.013), Vector3(0.018, 0.03, 0.004), slot, root)


func _plug(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	_host().add_child(root)
	_box(Vector3(0, 0, 0.03), Vector3(0.04, 0.055, 0.035), _mat(Color(0.08, 0.06, 0.10), 0.5), root)


func _power_strip(pos: Vector3, yaw: float, length: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	_host().add_child(root)
	_box(Vector3(0, 0, 0), Vector3(0.07, 0.032, length), _mat(Color(0.90, 0.88, 0.92), 0.5), root)
	var slot := _mat(Color(0.12, 0.08, 0.14), 0.5)
	for i in 4:
		_box(Vector3(0, 0.0165, -length / 2.0 + 0.07 + i * (length - 0.14) / 3.0), Vector3(0.05, 0.003, 0.03), slot, root)
	_sphere(Vector3(0.0, 0.0165, length / 2.0 - 0.025), 0.006, _mat(Color(1.0, 0.3, 0.2), 0.5, 3.0), Vector3.ONE, root, 8)


func _smooth_path(ctrl: Array, steps: int) -> Array:
	var out: Array = []
	var n := ctrl.size()
	for i in n - 1:
		var p0: Vector3 = ctrl[maxi(i - 1, 0)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[mini(i + 2, n - 1)]
		for k in steps:
			var t := k / float(steps)
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(ctrl[n - 1])
	return out


# Registers a cord; all cords are merged into one mesh in _finish_cords().
func _cord(ctrl: Array, radius: float = 0.006, col: Color = Color(0.06, 0.04, 0.08)) -> void:
	cord_paths.append([_smooth_path(ctrl, 6), radius, col, _host()])


func _finish_cords() -> void:
	var hosts: Array = []
	for entry in cord_paths:
		if not (entry[3] in hosts):
			hosts.append(entry[3])
	for h in hosts:
		_finish_cords_in(h)


func _finish_cords_in(host: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	for entry in cord_paths:
		if entry[3] != host:
			continue
		var pts: Array = entry[0]
		var radius: float = entry[1]
		var col: Color = entry[2]
		var rings: Array = []
		for i in pts.size():
			var prev: Vector3 = pts[maxi(i - 1, 0)]
			var next: Vector3 = pts[mini(i + 1, pts.size() - 1)]
			var tangent := (next - prev).normalized()
			var nrm := tangent.cross(Vector3.UP)
			if nrm.length() < 0.05:
				nrm = tangent.cross(Vector3.RIGHT)
			nrm = nrm.normalized()
			var bin := tangent.cross(nrm).normalized()
			var ring: Array = []
			for k in sides:
				var ang := TAU * k / sides
				ring.append((pts[i] as Vector3) + (nrm * cos(ang) + bin * sin(ang)) * radius)
			rings.append(ring)
		for i in rings.size() - 1:
			for k in sides:
				var k2 := (k + 1) % sides
				var v00: Vector3 = rings[i][k]
				var v01: Vector3 = rings[i][k2]
				var v10: Vector3 = rings[i + 1][k]
				var v11: Vector3 = rings[i + 1][k2]
				st.set_color(col)
				for v in [v00, v10, v11, v00, v11, v01]:
					st.add_vertex(v)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.disable_fog = true      # fog is only for the city outside
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	host.add_child(mi)


func _build_power() -> void:
	var black := Color(0.06, 0.04, 0.08)
	var white := Color(0.92, 0.88, 0.92)
	var yellow := Color(0.95, 0.80, 0.20)
	# wall outlets (back wall faces +z, left wall faces +x)
	_into = study_kit
	_outlet(Vector3(1.1, 0.3, -2.0), 0.0)             # desk power strip
	_outlet(Vector3(2.2, 0.3, -2.0), 0.0)             # desk lamp
	_plug(Vector3(1.1, 0.3, -2.0), 0.0)
	_plug(Vector3(2.2, 0.3, -2.0), 0.0)
	_into = null
	_outlet(Vector3(NIGHT_X + 0.35, 0.3, -2.0), 0.0)  # nightstand lamp
	_into = game_kit
	_outlet(Vector3(-3.9, 0.3, _lg(Vector3(-3.62, 0.0, -0.2 + LOUNGE_DZ)).z), PI / 2.0)       # TV + console strip
	_plug(Vector3(-3.9, 0.3, _lg(Vector3(-3.62, 0.0, -0.2 + LOUNGE_DZ)).z), PI / 2.0)
	_into = null
	_outlet(Vector3(-3.9, 0.3, FRONT_Z - 0.2), PI / 2.0)        # fairy lights
	_outlet(Vector3(-3.9, 0.3, -0.62), PI / 2.0)                # the recliner's wall speaker
	_plug(Vector3(-0.15, 0.3, -2.0), 0.0)
	_plug(Vector3(-3.9, 0.3, FRONT_Z - 0.2), PI / 2.0)
	_plug(Vector3(-3.9, 0.3, -0.62), PI / 2.0)

	# desk: strip on the floor under the desk, monitor + keyboard, lamp
	_into = study_kit
	_power_strip(Vector3(1.5, 0.017, -1.88), PI / 2.0, 0.48)
	_cord([Vector3(1.1, 0.3, -1.93), Vector3(1.1, 0.2, -1.92), Vector3(1.14, 0.05, -1.9), Vector3(1.28, 0.034, -1.88)], 0.007, white)
	_cord([Vector3(1.45, 0.95, -1.745), Vector3(1.45, 0.84, -1.8), Vector3(1.47, 0.79, -1.955), Vector3(1.47, 0.5, -1.975), Vector3(1.5, 0.1, -1.93), Vector3(1.5, 0.036, -1.88)], 0.007, black)
	_cord([Vector3(1.45, 0.808, -1.45), Vector3(1.52, 0.80, -1.55), Vector3(1.47, 0.80, -1.66)], 0.004, black)
	_cord([Vector3(2.2, 0.80, -1.78), Vector3(2.2, 0.79, -1.94), Vector3(2.22, 0.5, -1.975), Vector3(2.2, 0.3, -1.95)], 0.005, white)

	# desk speakers to the strip
	_cord([Vector3(0.96, 0.84, -1.84), Vector3(0.97, 0.80, -1.93), Vector3(1.0, 0.5, -1.985), Vector3(1.2, 0.1, -1.95), Vector3(1.34, 0.036, -1.88)], 0.005, black)
	_cord([Vector3(1.94, 0.84, -1.84), Vector3(1.93, 0.80, -1.935), Vector3(1.9, 0.5, -1.99), Vector3(1.7, 0.1, -1.95), Vector3(1.66, 0.036, -1.88)], 0.005, black)
	_into = null
	# the recliner's wall speaker: down the wall behind the chair to its outlet
	var rz := RECLINER_POS.z
	_cord([Vector3(-3.86, 1.64, rz + 0.05), Vector3(-3.887, 1.5, rz + 0.12), Vector3(-3.887, 0.9, rz + 0.3), Vector3(-3.887, 0.45, -0.62), Vector3(-3.84, 0.3, -0.62)], 0.005, black)

	# nightstand lamp
	_cord([Vector3(NIGHT_X, 0.475, -1.73), Vector3(NIGHT_X + 0.1, 0.465, -1.88), Vector3(NIGHT_X + 0.13, 0.44, -1.935), Vector3(NIGHT_X + 0.2, 0.3, -1.96), Vector3(NIGHT_X + 0.35, 0.3, -1.95)], 0.005, white)

	# TV + console strip on the floor, against the left wall behind the TV
	_into = game_kit
	var dz := LOUNGE_DZ
	var strip := _lg(Vector3(-3.62, 0.017, -0.05 + dz))
	_power_strip(Vector3(-3.84, 0.017, strip.z), 0.0, 0.5)
	_cord([Vector3(-3.85, 0.3, strip.z - 0.15), Vector3(-3.8, 0.15, strip.z - 0.17), Vector3(-3.84, 0.034, strip.z - 0.2)], 0.007, white)
	var tv_back := tv_root.to_global(Vector3(0.45, 0.15, -0.775))
	_cord([tv_back, _lg(Vector3(-3.84, 0.06, 0.35 + dz)), _lg(Vector3(-3.78, 0.012, 0.15 + dz)), Vector3(-3.84, 0.034, strip.z + 0.1)], 0.009, black)
	# the console sits on the door side of the TV; its cord runs round the back of the TV to the strip
	var c_back := console_root.to_global(Vector3(0.12, 0.035, -0.19))
	_cord([c_back, _lg(Vector3(-2.9, 0.012, 2.75 + dz - 0.9)), _lg(Vector3(-3.5, 0.012, 2.7 + dz - 0.9)), _lg(Vector3(-4.0, 0.012, 2.3 + dz - 0.9)),
			_lg(Vector3(-4.05, 0.012, 1.6 + dz - 0.9)), Vector3(-3.84, 0.034, strip.z + 0.2)], 0.005, black)
	# the speakers beside the TV: straight down the wall, then along the skirting to the strip behind the TV
	var tsp := _tv_speaker_spots()
	var lz: float = (tsp[0][1] as Vector3).z
	_cord([Vector3(-3.865, 1.15, lz), Vector3(-3.887, 1.0, lz + 0.02), Vector3(-3.887, 0.2, lz + 0.03), Vector3(-3.885, 0.02, lz + 0.05),
			Vector3(-3.86, 0.012, strip.z + 0.15), Vector3(-3.84, 0.034, strip.z + 0.25)], 0.004, black)
	var rx: float = (tsp[1][1] as Vector3).x
	_cord([Vector3(rx, 1.15, FRONT_Z - 0.035), Vector3(rx - 0.02, 1.0, FRONT_Z - 0.013), Vector3(rx - 0.03, 0.2, FRONT_Z - 0.013), Vector3(rx - 0.06, 0.02, FRONT_Z - 0.015),
			Vector3(-3.86, 0.012, FRONT_Z - 0.03), Vector3(-3.885, 0.012, FRONT_Z - 0.4), Vector3(-3.885, 0.012, strip.z + 0.6), Vector3(-3.84, 0.034, strip.z + 0.25)], 0.004, black)
	# console to TV (video cable) and the two controller cables
	var av_from := console_root.to_global(Vector3(-0.07, 0.05, -0.19))
	var av_to := tv_root.to_global(Vector3(-(TV_WIDTH / 2.0 - 0.28), 0.1, 0.235))
	_cord([av_from, _lm(Vector3(-2.78, 0.034, 0.4 + dz)), _lm(Vector3(-2.86, 0.06, 0.37 + dz)), av_to], 0.004, yellow)
	var port_a := console_root.to_global(Vector3(-0.004, 0.03, 0.185))
	var port_b := console_root.to_global(Vector3(0.094, 0.03, 0.185))
	_cord([port_a, _lm(Vector3(-2.3, 0.034, 0.27 + dz)), _lm(Vector3(-2.2, 0.034, 0.2 + dz)), ctrl_exits[0]], 0.004, black)
	_cord([port_b, _lm(Vector3(-2.3, 0.034, 0.5 + dz)), _lm(Vector3(-2.15, 0.034, 0.65 + dz)), ctrl_exits[1]], 0.004, black)

	# VCR on top of the TV: power cord down the back of the TV to the strip, video cable to the TV
	var tl := func(p: Vector3) -> Vector3: return tv_root.to_global(p)
	_cord([tl.call(Vector3(-0.35, 1.13, -0.2)), tl.call(Vector3(-0.38, 1.02, -0.3)), tl.call(Vector3(-0.40, 0.87, -0.5)),
			tl.call(Vector3(-0.42, 0.75, -0.645)), tl.call(Vector3(-0.42, 0.3, -0.645)), tl.call(Vector3(-0.42, 0.05, -0.645)),
			_lg(Vector3(-3.86, 0.034, 2.4)), _lg(Vector3(-3.86, 0.034, 1.6)), Vector3(-3.84, 0.034, strip.z - 0.1)], 0.005, black)
	_cord([tl.call(Vector3(0.3, 1.13, -0.2)), tl.call(Vector3(0.3, 1.02, -0.3)), tl.call(Vector3(0.28, 0.87, -0.5)),
			tl.call(Vector3(0.26, 0.75, -0.645)), tl.call(Vector3(0.26, 0.6, -0.645))], 0.004, yellow)

	_into = null
	# fairy lights: chained strands, one plug at the left-front corner
	var fz := FRONT_Z
	_cord([Vector3(-3.86, 2.55, fz - 0.1), Vector3(-3.84, 2.58, fz - 0.05), Vector3(-3.8, 2.6, fz - 0.04)], 0.0035, Color(0.10, 0.07, 0.12))
	_cord([Vector3(-3.88, 2.55, fz - 0.1), Vector3(-3.885, 1.5, fz - 0.12), Vector3(-3.885, 0.5, fz - 0.17), Vector3(-3.84, 0.3, fz - 0.2)], 0.0045, black)


# Plays res://media/<name>.gif (or a still .png/.jpg/.webp) on a screen's shader material.
# With no file there it keeps the built-in screen.
func _attach_media(mat: ShaderMaterial, base_path: String) -> void:
	var player := GifPlayer.new()
	add_child(player)
	player.setup(mat, base_path)


# ---------------------------------------------------------------- pointer: screens + VCR buttons

func _make_laser(parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0025
	mesh.bottom_radius = 0.0025
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = _mat(Color(1.0, 0.6, 0.9), 0.5, 2.5)
	mi.rotation.x = PI / 2.0
	mi.visible = false
	parent.add_child(mi)
	return mi


# Distance along the ray to a box (centred on `node`, half-sizes in its local space), or -1.
func _ray_box(o: Vector3, d: Vector3, node: Node3D, half: Vector3) -> float:
	var inv := node.global_transform.affine_inverse()
	var lo := inv * o
	var ld := inv.basis * d
	var tmin := 0.0
	var tmax := 1.0e9
	for axis in 3:
		var da := ld[axis]
		var oa := lo[axis]
		if absf(da) < 1.0e-8:
			if absf(oa) > half[axis]:
				return -1.0
		else:
			var t1 := (-half[axis] - oa) / da
			var t2 := (half[axis] - oa) / da
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
			if tmin > tmax:
				return -1.0
	return tmin


func _update_pointer(delta: float) -> void:
	var rays: Array = []
	if game_mode:
		pass                      # holding a controller: no pointing
	elif xr_active:
		rays.append([right_hand.global_position, -right_hand.global_transform.basis.z.normalized(), 1])
		rays.append([left_hand.global_position, -left_hand.global_transform.basis.z.normalized(), 0])
	elif desktop_cam != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rays.append([desktop_cam.global_position, -desktop_cam.global_transform.basis.z.normalized(), 2])

	var found_screen: ScreenUI = null
	var found_item: Dictionary = {}
	var found_pos := Vector2.ZERO
	var found_hand := -1
	var found_point := Vector3.ZERO
	var found_t := 0.0
	for ray in rays:
		var o: Vector3 = ray[0]
		var d: Vector3 = ray[1]
		var best := FAR_RANGE
		var sc_hit: ScreenUI = null
		var sc_pos := Vector2.ZERO
		var it_hit: Dictionary = {}
		for sc in screens:
			if apartment != null and not apartment.can_reach(sc):
				continue
			var h: Dictionary = sc.hit(o, d, POINTER_RANGE)
			if not h.is_empty() and float(h["t"]) < best:
				best = float(h["t"])
				sc_hit = sc
				sc_pos = h["pos"]
				it_hit = {}
		for it in interactables:
			if it.has("when") and not bool((it["when"] as Callable).call()):
				continue
			if apartment != null and not apartment.can_reach(it["node"]):
				continue                                 # (things in other rooms, behind the walls)
			var t := _ray_box(o, d, it["node"], (it["half_fn"] as Callable).call() if it.has("half_fn") else it["half"])
			if t >= 0.0 and t < best and t <= float(it.get("range", POINTER_RANGE)):
				best = t
				it_hit = it
				sc_hit = null
		if sc_hit != null or not it_hit.is_empty():
			found_screen = sc_hit
			found_item = it_hit
			found_pos = sc_pos
			found_hand = int(ray[2])
			found_t = best
			found_point = o + d * best
			break

	if hover_screen != null and hover_screen != found_screen:
		hover_screen.clear_hover()
	hover_screen = found_screen
	var new_node: Node3D = null
	if not found_item.is_empty():
		new_node = found_item["node"]
	if new_node != hover_node:
		if not hover_item.is_empty() and hover_item.has("hover"):
			(hover_item["hover"] as Callable).call(false)
		hover_node = new_node
		if not found_item.is_empty() and found_item.has("hover"):
			(found_item["hover"] as Callable).call(true)
	hover_item = found_item
	hover_hand = found_hand
	if hover_screen != null:
		hover_pos = found_pos
		hover_screen.send_motion(found_pos, ptr_down)

	if not found_item.is_empty():
		var lbl: Variant = found_item["label"]
		hint_label.text = str((lbl as Callable).call()) if lbl is Callable else str(lbl)
		if egg_active and found_item.get("egg_lock", false):
			hint_label.text += "  [LOCKED]"
		elif _is_guest() and not _guest_may(found_item):
			hint_label.text += "  [HOST ONLY]"
		# the closer you are, the smaller the sign (so it never fills the view); from ~1.2 m away it is full size
		var k := clampf(found_t / 1.2, 0.2, 1.0)
		hint_label.scale = Vector3.ONE * k
		hint_label.global_position = found_point + Vector3(0.0, 0.02 + 0.08 * k, 0.0)
		if found_item.has("hint_at"):                 # a fixed spot for the sign (e.g. under a picture, not on it)
			hint_label.global_position = (found_item["hint_at"] as Callable).call()
			hint_label.scale = Vector3.ONE * clampf(found_t / 1.6, 0.35, 0.8)
		hint_label.visible = not (found_item.get("shelf", false) and not shelf_hints)
	elif diary != null and diary.open_book and book_hint_t > 0.0:
		hint_label.text = ("GRIP  =  PUT IT DOWN" if xr_active else "G  =  PUT IT DOWN")
		hint_label.scale = Vector3.ONE * 0.45
		hint_label.global_position = head.global_position - head.global_transform.basis.z * 0.8 + Vector3(0.0, -0.3, 0.0)
		hint_label.visible = true
	elif held_book != null and book_hint_t > 0.0:
		hint_label.text = ("A / B  =  NEXT / PREVIOUS PAGE     STICK CLICK  =  ZOOM     GRIP  =  PUT IT DOWN" if xr_active else "ARROWS OR WHEEL  =  TURN PAGES     V  =  ZOOM     G  =  PUT IT DOWN")
		hint_label.scale = Vector3.ONE * 0.45
		hint_label.global_position = head.global_position - head.global_transform.basis.z * 0.8 + Vector3(0.0, -0.42 if book_zoom > 0 else -0.3, 0.0)
		hint_label.visible = book_zoom < 2         # nothing over the pages when they fill the view
		hint_label.visible = true
	elif game_mode and pad_hint_t > 0.0:
		hint_label.text = "%s:  %s  =  %s" % ["ARCADE" if held_pad_idx == -1 else "CONTROLLER", "GRIP" if xr_active else "E", "STEP AWAY" if held_pad_idx == -1 else "PUT IT DOWN"]
		if emu != null and emu.state != Emu.State.MENU:
			hint_label.text += "\n" + ("HOLD START + SELECT  =  GAME LIST" if xr_active else "M  =  GAME LIST")
		hint_label.scale = Vector3.ONE * 0.45
		hint_label.global_position = head.global_position - head.global_transform.basis.z * 0.8 + Vector3(0.0, -0.3, 0.0)
		hint_label.visible = true
	else:
		hint_label.visible = false

	var active := (hover_screen != null and hover_screen.cursor_allowed) or not hover_item.is_empty()
	laser_l.visible = active and hover_hand == 0
	laser_r.visible = active and hover_hand == 1
	var laser := laser_l if hover_hand == 0 else laser_r
	if active and (hover_hand == 0 or hover_hand == 1):
		laser.scale = Vector3(1.0, found_t, 1.0)
		laser.position = Vector3(0.0, 0.0, -found_t / 2.0)

	# scroll lists with the right thumbstick while pointing at a screen (or set a friend's volume while pointing at them)
	scroll_cd = maxf(0.0, scroll_cd - delta)
	if xr_active and hover_screen == null and not hover_item.is_empty() and hover_item.has("player") and scroll_cd <= 0.0:
		var sy2 := right_hand.get_vector2("primary").y
		if absf(sy2) > 0.6:
			player_scroll(int(hover_item["player"]), sy2 > 0.0)
			scroll_cd = 0.25
	if xr_active and hover_screen != null and scroll_cd <= 0.0:
		var sy := right_hand.get_vector2("primary").y
		if absf(sy) > 0.6:
			hover_screen.send_scroll(hover_pos, sy > 0.0)
			scroll_cd = 0.12


# Trigger / left mouse button. Returns true if it was used by a screen or a VCR button.
func _pointer_press(hand: int) -> bool:
	if hover_hand != hand:
		return false
	if hover_screen != null:
		if _is_guest() and hover_screen == monitor_ui and not (guest_allow_seen.get("music", false) or guest_allow_seen.get("lights", false)):
			_net_say("The host hasn't opened the PC up to guests.")
			return true
		if _is_guest() and hover_screen == tv_screen_ui and not guest_allow_seen.get("tv", false):
			_net_say("The host hasn't opened the TV up to guests.")
			return true
		down_screen = hover_screen
		ptr_down = true
		hover_screen.send_button(hover_pos, true)
		return true
	if not hover_item.is_empty():
		if egg_active and hover_item.get("egg_lock", false):
			return true                       # locked while the alert is on
		if _is_guest() and not _guest_may(hover_item):
			_net_say("The host hasn't opened that up to guests.")
			return true
		var cb: Callable = hover_item["cb"]
		cb.call()
		return true
	return false


func _pointer_release(_hand: int) -> void:
	if ptr_down and down_screen != null:
		down_screen.send_button(down_screen.last_pos, false)
	ptr_down = false
	down_screen = null
	_mark_release()


# ---------------------------------------------------------------- view cycling (V / B or Y button)

# Cycles: normal -> zoomed in on a screen -> screen fills the view -> back to where you were.
# Targets the screen you're pointing at, otherwise the one you're looking toward.
func _cycle_view() -> void:
	if focus_level == 0:
		var sc := _pick_focus_screen()
		if sc == null:
			return
		focus_screen = sc
		_begin_focus(1)
	elif focus_level == 1:
		_begin_focus(2)
	else:
		_end_focus(true)


func _pick_focus_screen() -> ScreenUI:
	if hover_screen != null:
		return hover_screen
	var p := head.global_position
	var f := -head.global_transform.basis.z
	var best: ScreenUI = null
	var best_dot := 0.5
	for sc in screens:
		if apartment != null and not apartment.can_reach(sc):
			continue                                   # (behind a wall)
		var to: Vector3 = sc.global_position - p
		var dist := to.length()
		if dist > 9.0 or dist < 0.05:
			continue
		var dir := to / dist
		if sc.global_transform.basis.z.dot(-dir) <= 0.0:
			continue      # we're behind it
		var d := f.dot(dir)
		if d > best_dot:
			best_dot = d
			best = sc
	return best


# zoomed in on a screen: would this point (a friend's head, say) be in the way of it?
func blocks_focus(pt: Vector3) -> bool:
	if focus_level == 0 or focus_screen == null or head == null:
		return false
	var cam := head.global_position
	var sc := focus_screen.global_transform
	var to_scr := sc.origin - cam
	var to_pt := pt - cam
	if to_pt.dot(to_scr.normalized()) <= 0.0 or to_pt.length() > to_scr.length():
		return false                                   # behind me, or behind the screen
	# where the line from my eye through the point lands on the screen's plane
	var n := sc.basis.z.normalized()
	var den := to_pt.normalized().dot(n)
	if absf(den) < 0.0001:
		return false
	var t := (sc.origin - cam).dot(n) / den
	var hit := cam + to_pt.normalized() * t
	var l := sc.affine_inverse() * hit
	var half: Vector2 = focus_screen.screen_size * 0.5 + Vector2(0.4, 0.4)
	return absf(l.x) <= half.x and absf(l.y) <= half.y


# How far in front of the screen to stand so it fills about 55% (zoom) or 95% (full) of the view.
func _view_distance(sc: ScreenUI, level: int) -> float:
	var frac := 0.55 if level == 1 else 0.95
	var w := sc.screen_size.x
	var h := sc.screen_size.y
	if xr_active:
		# assume roughly 100 x 90 degrees of view and never come closer than 45 cm (uncomfortable to focus)
		var dw := (w / 2.0) / tan(deg_to_rad(50.0))
		var dh := (h / 2.0) / tan(deg_to_rad(45.0))
		return maxf(0.45, maxf(dw, dh) / frac)
	var vfov := deg_to_rad(desktop_cam.fov)
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	var hfov := 2.0 * atan(tan(vfov / 2.0) * aspect)
	var dw2 := (w / 2.0) / tan(hfov / 2.0)
	var dh2 := (h / 2.0) / tan(vfov / 2.0)
	return maxf(dw2, dh2) / frac


func _begin_focus(level: int) -> void:
	var sc := focus_screen
	var n := sc.global_transform.basis.z.normalized()
	var dist := _view_distance(sc, level)
	var center := sc.global_position
	if xr_active:
		# VR can't zoom without making you sick, so move you in front of the screen instead
		if focus_level == 0:
			saved_origin_xf = origin.global_transform
		var target := center + n * dist
		target.y = clampf(center.y, 0.85, 1.7)
		origin.global_position += target - head.global_position
		var to := center - target
		to.y = 0.0
		var fwd := -head.global_transform.basis.z
		fwd.y = 0.0
		if to.length() > 0.01 and fwd.length() > 0.01:
			var delta := angle_difference(atan2(-fwd.x, -fwd.z), atan2(-to.x, -to.z))
			_snap_turn(rad_to_deg(delta))
	else:
		if focus_level == 0:
			saved_cam_local = desktop_cam.transform
			saved_pitch = pitch
		cam_from = desktop_cam.global_transform
		cam_to = Transform3D(Basis.looking_at(-n, Vector3.UP), center + n * dist)
		cam_t = 0.0
	focus_level = level


func _end_focus(animate: bool) -> void:
	if focus_level == 0:
		return
	if xr_active:
		origin.global_transform = saved_origin_xf
	elif animate:
		cam_from = desktop_cam.global_transform
		cam_to = origin.global_transform * saved_cam_local
		cam_t = 0.0
	else:
		desktop_cam.transform = saved_cam_local
		pitch = saved_pitch
		cam_t = 1.0
	focus_level = 0
	focus_screen = null


func _update_focus_anim(delta: float) -> void:
	if cam_t >= 1.0 or desktop_cam == null:
		return
	cam_t = minf(1.0, cam_t + delta * 2.5)
	var e := 1.0 - pow(1.0 - cam_t, 3.0)
	var q := cam_from.basis.get_rotation_quaternion().slerp(cam_to.basis.get_rotation_quaternion(), e)
	desktop_cam.global_transform = Transform3D(Basis(q), cam_from.origin.lerp(cam_to.origin, e))
	if cam_t >= 1.0:
		if focus_level == 0:
			desktop_cam.transform = saved_cam_local
			pitch = saved_pitch
		else:
			pitch = desktop_cam.rotation.x
