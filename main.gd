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
const PadMap := preload("res://padmap.gd")
const SETTINGS_FILE := "user://lofi_room.cfg"
const RETICLE_COLORS := [["Pink", Color(1.0, 0.35, 0.65)], ["Cyan", Color(0.20, 0.85, 0.90)], ["Amber", Color(1.0, 0.70, 0.30)], ["Lavender", Color(0.72, 0.58, 1.0)], ["White", Color(1.0, 0.95, 1.0)]]
signal settings_changed
## Lofi bedroom for Steam Frame. The whole room is built in code from simple shapes.

const USE_GLOW := true       # bloom on lamps and window; turn off if the headset struggles
const MOVE_SPEED := 1.6      # metres per second
const SNAP_ANGLE := 30.0     # degrees per snap turn
const DEADZONE := 0.2
const SEAT_EYE_HEIGHT := 1.18   # eye height (m) while sitting
const SIT_RANGE := 1.1          # how close you must be to the chair to sit
const TV_WIDTH := 1.44          # CRT width in metres (80% of the 1.8 m lounge rug)
const FRONT_Z := 3.4            # z of the front wall (the one with the door)
const LOUNGE_DZ := 1.2          # how far the rug/TV/beanbag set sits toward the front wall
const WIN_X0 := -3.75            # window: left edge, right edge, sill height, top
const WIN_X1 := 1.05
const WIN_Y0 := 0.5
const WIN_Y1 := 2.7
const POINTER_RANGE := 4.0       # how far the VR laser / desktop crosshair reaches
const RUG_WIDTH := 1.8          # lounge rug width along the wall
const BED_ASSET := "res://assets/bed.glb"   # drop a bed model here and it replaces the built-in bed
const BED_EXTRA_YAW := 0.0      # rotate the bed asset in 90 degree steps if it faces the wrong way
const ROOM_HALF := Vector2(2.2, 1.75)   # right limit in x, and +-z limit
const ROOM_X_MIN := -3.6                 # left limit in x (room is wider on the left now)
const BLOCKERS := [
	Rect2(-2.6, -2.1, 1.95, 2.4),   # bed
	Rect2(0.4, -2.1, 2.2, 1.05),    # desk
	Rect2(2.0, -0.65, 0.6, 1.9),    # bookshelf
	Rect2(-2.05, 0.35 + LOUNGE_DZ, 1.1, 1.1),   # beanbag
	Rect2(-4.0, 0.1 + LOUNGE_DZ, 1.2, 1.7),    # CRT TV
	Rect2(-4.0, -1.8, 0.75, 1.2),   # dresser
	Rect2(-2.75, 0.1 + LOUNGE_DZ, 0.4, 0.55),   # game console
	Rect2(1.4, 1.55, 1.2, 0.8),   # arcade cabinet (right wall, by the bookshelf)
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
var console_root: Node3D
var console_on := false
var cab_root: Node3D                  # the standing arcade cabinet on the left wall
var arcade_mat: ShaderMaterial
var arcade_light: OmniLight3D
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
	updater = Updater.new()
	updater.name = "Updater"
	add_child(updater)
	updater.changed.connect(func() -> void:
		if updater.state == "done":
			updated_this_session = true)
	room = Node3D.new()
	room.name = "Room"
	add_child(room)
	_build_environment()
	_build_shell()
	_build_window()
	_build_door()
	bank = SpeakerBank.new()
	bank.name = "Speakers"
	room.add_child(bank)
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
	_setup_player()
	_load_prefs()
	pc.play_random_default()


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


func _place(mesh: Mesh, pos: Vector3, mat: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	var p: Node = parent if parent != null else room
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
	room.add_child(l)
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
	if USE_GLOW:
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
	_box(Vector3(-0.7, 1.4, FRONT_Z + 0.05), Vector3(6.8, 2.8, 0.1), wall)     # front
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
const Incense := preload("res://incense.gd")
var incense: Node3D
const BED_POS := Vector3(-1.65, 0.0, -0.9)
var updated_this_session := false      # an update was installed and the player has not napped yet: the easter egg stays locked
var bed_made := true                   # false after sleeping: the next morning the bed is a mess
var bed_node: Node3D


func _rebuild_bed() -> void:
	if bed_node != null and is_instance_valid(bed_node):
		bed_node.queue_free()
	bed_node = BedModel.build(room, BED_POS, "made" if bed_made else "unmade")


func _make_bed() -> void:
	if bed_made:
		return
	bed_made = true
	_rebuild_bed()
	_save_prefs_tick()


func _build_bed() -> void:
	_bed_sleep_spot()
	# if you drop a bed model at BED_ASSET it replaces the built-in bed (auto-scaled to fit)
	if _try_asset(BED_ASSET, Vector3(-1.65, 0.0, -0.9), Vector2(1.68, 2.12), BED_EXTRA_YAW):
		_build_nightstand()
		return
	_rebuild_bed()

	_build_nightstand()


func _build_nightstand() -> void:
	var wood := _mat(Color(0.30, 0.12, 0.18), 0.6)
	var padded := _mat(Color(0.52, 0.22, 0.42), 0.9)
	_box(Vector3(-0.5, 0.23, -1.7), Vector3(0.4, 0.46, 0.4), wood)
	# the drawer slides out; it is where the secret cart is kept
	var face_m := _mat(Color(0.52, 0.22, 0.42), 0.9)
	var knob_m := _mat(Color(1.0, 0.8, 0.55), 0.3, 0.8)
	drawer_node = Node3D.new()
	drawer_node.position = Vector3(-0.5, 0.32, -1.495)
	room.add_child(drawer_node)
	var face := _box(Vector3.ZERO, Vector3(0.34, 0.16, 0.01), face_m, drawer_node)
	_sphere(Vector3(0, 0, 0.01), 0.016, knob_m, Vector3.ONE, drawer_node, 12)
	var tray_m := _mat(Color(0.50, 0.26, 0.40), 0.9)
	_box(Vector3(0, -0.07, -0.16), Vector3(0.31, 0.012, 0.31), tray_m, drawer_node)
	for tx in [-0.155, 0.155]:
		_box(Vector3(tx, -0.035, -0.16), Vector3(0.012, 0.07, 0.31), tray_m, drawer_node)
	_box(Vector3(0, -0.035, -0.315), Vector3(0.31, 0.07, 0.012), tray_m, drawer_node)
	interactables.append({"node": face, "half": Vector3(0.18, 0.09, 0.04), "cb": _toggle_drawer, "hover": _glow_hover(face_m),
		"label": func() -> String: return "CLOSE DRAWER" if drawer_open else "OPEN DRAWER"})
	_lamp(Vector3(-0.5, 0.46, -1.7), 1.0)


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
	room.add_child(root)
	var dark := _mat(Color(0.10, 0.04, 0.12))
	_cyl(Vector3(0, 0.01, 0), 0.07, 0.02, dark, root)
	_cyl(Vector3(0, 0.15, 0), 0.012, 0.3, dark, root)
	var shade_m := _mat(WARM, 0.5, 2.5)
	var shade := _cyl(Vector3(0, 0.33, 0), 0.08, 0.14, shade_m, root)
	(shade.mesh as CylinderMesh).top_radius = 0.05
	lamp_shades.append({"node": shade, "mat": shade_m})


# ---------------------------------------------------------------- desk

func _build_desk() -> void:
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
	room.add_child(pc_ui)
	pc_ui.setup(sm, Vector2(0.72, 0.4), Vector2i(1024, 576), 0.0)
	screens.append(pc_ui)
	monitor_ui = pc_ui
	# monitor power button, bottom right of the bezel
	var mb_m := _mat(Color(0.20, 0.17, 0.24), 0.4)
	var mb := _box(Vector3(1.45 + 0.32, 0.905, -1.704), Vector3(0.06, 0.022, 0.02), mb_m)
	monitor_led_m = _mat(Color(0.2, 1.0, 0.4), 0.4, 3.0)
	_sphere(Vector3(1.45 + 0.27, 0.905, -1.695), 0.005, monitor_led_m, Vector3.ONE, null, 8)
	interactables.append({"node": mb, "half": Vector3(0.05, 0.03, 0.04),
		"label": _monitor_label, "egg_lock": true, "cb": _toggle_monitor, "hover": _glow_hover(mb_m)})
	pc = PCPlayer.new()
	pc.position = Vector3(1.45, 1.0, -1.7)
	room.add_child(pc)
	pc.setup(pc_ui, bank)

	# keyboard, mug, lamp, plant
	_box(Vector3(1.45, 0.80, -1.38), Vector3(0.42, 0.015, 0.14), _mat(Color(0.25, 0.10, 0.28)))
	_cyl(Vector3(1.95, 0.825, -1.42), 0.035, 0.08, _mat(Color(0.95, 0.80, 0.75)))
	_lamp(Vector3(2.2, 0.785, -1.75), 1.0)
	_plant(Vector3(0.7, 0.785, -1.75), 0.5)

	# chair
	chair = Node3D.new()
	chair.position = Vector3(1.45, 0.0, -0.8)
	room.add_child(chair)
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
	room.add_child(sit_label)
	seat_nodes.append(chair)
	seat_eye.append(SEAT_EYE_HEIGHT)
	seat_swivel.append(true)

	# 90s anime poster on the right wall (res://textures/poster.png, swap in your own art any time)
	_box(Vector3(2.485, 1.75, -1.25), Vector3(0.03, 1.0, 0.62), _mat(Color(0.95, 0.80, 0.86), 0.5))
	var poster_mat := StandardMaterial3D.new()
	poster_mat.disable_fog = true      # fog is only for the city outside
	var tex: Texture2D = load("res://textures/poster.png")
	poster_mat.albedo_texture = tex
	poster_mat.roughness = 1.0
	poster_mat.emission_enabled = true
	poster_mat.emission_texture = tex
	poster_mat.emission_energy_multiplier = 0.35
	var poster := QuadMesh.new()
	poster.size = Vector2(0.54, 0.92)
	var poster_node := _place(poster, Vector3(2.455, 1.75, -1.25), poster_mat, null)
	poster_node.rotation.y = -PI / 2.0
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


func _make_speaker(spk_name: String, pos: Vector3, yaw: float, tilt: float, size: Vector3, cone_r: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation = Vector3(tilt, yaw, 0.0)       # local +z is the front of the speaker
	room.add_child(root)
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
		"cb": bank.toggle.bind(idx),
		"hover": _glow_hover(body_m),
	})
	led.name = "LED"


func _speaker_label(idx: int, spk_name: String) -> String:
	return "%s  [%s]" % [spk_name, "ON" if bank.is_enabled(idx) else "OFF"]


func _tv_label(kind: String) -> String:
	match kind:
		"power":
			return "TV POWER  [%s]" % ("ON" if vcr.tv_on else "OFF")
		"vol_down":
			return "TV VOLUME DOWN  [%d/10]" % vcr.tv_volume
	return "TV VOLUME UP  [%d/10]" % vcr.tv_volume


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


func _build_speakers() -> void:
	# two desk speakers either side of the monitor
	_make_speaker("Desk speaker L", Vector3(0.96, 0.915, -1.76), 0.15, 0.0, Vector3(0.14, 0.26, 0.16), 0.046)
	_make_speaker("Desk speaker R", Vector3(1.94, 0.915, -1.76), -0.15, 0.0, Vector3(0.14, 0.26, 0.16), 0.046)
	# wall speakers on the left wall beside the bed, angled down a little toward it
	for i in 3:
		var z := -1.55 + i * 0.8
		_make_speaker("Wall speaker %d" % (i + 1), Vector3(-3.9 + 0.09, 2.05, z), PI / 2.0, 0.2, Vector3(0.18, 0.32, 0.16), 0.055)
	pc.refresh_speakers()


# ---------------------------------------------------------------- bookshelf

func _build_shelf() -> void:
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

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 5:
		var gap_chance := 0.12 if i < 3 else 0.35
		var z := z0 + 0.05
		while z < z1 - 0.1:
			if rng.randf() < gap_chance:
				z += rng.randf_range(0.08, 0.2)
				continue
			var w := rng.randf_range(0.03, 0.06)
			var h := rng.randf_range(0.18, 0.34)
			var m: Material = book_mats[rng.randi() % book_mats.size()]
			_box(Vector3(2.35, boards[i] + 0.015 + h / 2.0, z + w / 2.0), Vector3(0.2, h, w), m)
			z += w + 0.003
	_plant(Vector3(2.34, 2.215, 0.0), 0.6)


# ---------------------------------------------------------------- decor

func _build_decor() -> void:
	# rug
	_box(Vector3(0.1, 0.01, 0.75), Vector3(1.8, 0.02, 1.3), _mat(Color(0.35, 0.12, 0.40), 1.0))
	_box(Vector3(0.1, 0.012, 0.75), Vector3(1.5, 0.02, 1.0), _mat(Color(0.55, 0.22, 0.42), 1.0))
	_build_beanbag(Vector3(-1.5, 0.0, 0.9 + LOUNGE_DZ), 90.0)   # faces the left wall (the TV)
	_build_tv()
	_build_console()
	_build_dresser()
	_box(Vector3(-2.4, 0.01, 0.9 + LOUNGE_DZ), Vector3(3.0, 0.02, RUG_WIDTH), _mat(Color(0.30, 0.10, 0.34), 1.0))
	_box(Vector3(-2.4, 0.012, 0.9 + LOUNGE_DZ), Vector3(2.7, 0.02, RUG_WIDTH - 0.3), _mat(Color(0.42, 0.15, 0.42), 1.0))
	# fairy lights: three strands, kept restrained
	var bulb := _mat(WARM, 0.5, 3.0)
	fairy_mat = bulb
	_fairy(Vector3(-3.86, 2.55, -1.2), Vector3(-3.86, 2.55, FRONT_Z - 0.1), 22, 4, 0.16, bulb)   # left wall
	_fairy(Vector3(-3.8, 2.6, FRONT_Z - 0.04), Vector3(2.4, 2.6, FRONT_Z - 0.04), 18, 4, 0.18, bulb)        # front wall, above the door


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
	room.add_child(root)
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
	var l_night := _light(Vector3(-0.5, 0.95, -1.7), WARM, 1.0, 2.5)                     # nightstand lamp
	var l_desk := _light(Vector3(2.2, 1.15, -1.7), WARM, 1.0, 2.5)                      # desk lamp
	var l_lantern := _light(Vector3(1.6, 2.25, 0.3), Color(1.0, 0.6, 0.35), 0.9, 3.5)     # paper lantern
	monitor_light = _light(Vector3(1.45, 1.1, -1.3), Color(0.65, 0.40, 1.0), 0.9, 2.2)    # monitor
	fill_light = _light(Vector3(-0.8, 2.4, 0.9), Color(0.6, 0.25, 0.7), 0.7, 7.0)      # soft fill
	_light(Vector3(-2.6, 0.6, 0.9 + LOUNGE_DZ), Color(0.45, 0.6, 1.0), 1.0, 3.2)     # CRT glow
	# things you can switch off (click the lamps, or use the PC's Lights window)
	_light_group("Nightstand lamp", [l_night], [lamp_shades[0]["mat"]], lamp_shades[0]["node"], Vector3(0.12, 0.14, 0.12))
	_light_group("Desk lamp", [l_desk], [lamp_shades[1]["mat"]], lamp_shades[1]["node"], Vector3(0.12, 0.14, 0.12))
	_light_group("Paper lantern", [l_lantern], [lantern_mat], lantern_node, Vector3(0.2, 0.2, 0.2))
	_light_group("Fairy lights", [], [fairy_mat], null, Vector3.ZERO)
	_light_group("Ceiling strip", [], [strip_mat], null, Vector3.ZERO)


func _light_group(gname: String, omnis: Array, mats: Array, click_node: Node3D, half: Vector3) -> void:
	var entries: Array = []
	for m in mats:
		entries.append({"m": m, "e": m.emission_energy_multiplier, "a": m.albedo_color})
	light_groups.append({"name": gname, "on": true, "omnis": omnis, "mats": entries})
	var gi := light_groups.size() - 1
	if click_node != null:
		interactables.append({"node": click_node, "half": half,
			"label": _light_label.bind(gi), "cb": toggle_light.bind(gi), "hover": _noop_hover})


func _noop_hover(_on: bool) -> void:
	pass


func _light_label(gi: int) -> String:
	return "%s  [%s]" % [light_groups[gi]["name"], "ON" if light_groups[gi]["on"] else "OFF"]


func is_light_on(gi: int) -> bool:
	return light_groups[gi]["on"]


func set_light(gi: int, on: bool) -> void:
	var g: Dictionary = light_groups[gi]
	if g["on"] == on:
		return
	g["on"] = on
	for l in g["omnis"]:
		(l as OmniLight3D).visible = on
	for e in g["mats"]:
		var m: StandardMaterial3D = e["m"]
		m.emission_energy_multiplier = e["e"] if on else 0.0
		m.albedo_color = e["a"] if on else (e["a"] as Color).darkened(0.65)
	lights_changed.emit()


func toggle_light(gi: int) -> void:
	set_light(gi, not light_groups[gi]["on"])


func set_all_lights(on: bool) -> void:
	for gi in light_groups.size():
		set_light(gi, on)

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
	room.add_child(curtain_node)
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
		"label": _curtain_label, "egg_lock": true, "cb": toggle_curtains, "hover": _glow_hover(plate_m)})


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


func set_curtain(v: float) -> void:
	if egg_active:
		return
	curtain_target = clampf(v, 0.0, 1.0)
	curtain_last_down = curtain_target > curtain_amt


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
	room.add_child(flash_l)
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
	var sky_light := open * (1.0 - 0.35 * cloudy)
	world_env.ambient_light_energy = lerpf(0.05, 0.6, sky_light)
	if weather != null:
		# a big lightning strike lights up everything for a moment, a little of it even leaks past the curtains
		world_env.ambient_light_energy += weather.room_flash * 1.6 * (0.25 + 0.75 * open)
	window_light.light_energy = 2.4 * sky_light
	fill_light.light_energy = lerpf(0.10, 0.7, sky_light)
	for led in curtain_switch_leds:
		led.emission = Color(1.0, 0.7, 0.3) if curtain_target > 0.5 else Color(0.4, 0.8, 1.0)
	if weather != null:
		weather.window_open = open
		weather.sound_open = 1.0 - curtain_amt * curtain_amt      # a half-closed curtain still lets most of the weather sound through


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
	room.add_child(hint_label)

	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		xr_active = true
		head = xr_cam
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
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
	if leave_prompt:
		leave_t -= delta
		if leave_t <= 0.0 or head.global_position.distance_to(leave_panel.global_position) > 3.0:
			_cancel_leave()          # walked away or waited too long: the sign goes
	if reticle != null:
		reticle.visible = reticle_on and not xr_active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not game_mode and not _aim_at_playing_tv() and not (hover_screen != null and hover_screen.cursor_allowed)
		reticle.hot = not hover_item.is_empty() or (hover_screen != null and hover_screen.cursor_allowed)
	_update_held_pad(delta)
	if emu != null:
		emu.set_volume(float(vcr.tv_volume) / 10.0 if (vcr.tv_on or slot_cart == "neo") else 0.0)
		if game_mode:
			_pad_tick(delta)
			if not xr_active and not Input.get_connected_joypads().is_empty():
				var down := Input.is_joy_button_pressed(Input.get_connected_joypads()[0], JOY_BUTTON_RIGHT_STICK)
				if down and not _pad_stick_prev:
					_put_pad()
				_pad_stick_prev = down
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
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-fwd.x, -fwd.z), clampf(4.0 * delta, 0.0, 1.0))
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
			_try_move(dir * MOVE_SPEED * delta)
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
			_try_move(Vector3(v.x, 0.0, -v.y).rotated(Vector3.UP, yaw) * MOVE_SPEED * delta)


func _unhandled_input(event: InputEvent) -> void:
	if xr_active:
		return
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
		elif event.keycode == KEY_V:
			_cycle_view()
		elif event.keycode == KEY_M:
			if game_mode and emu != null:
				emu.to_menu()          # back to the game list without taking the cart out
		elif event.keycode == KEY_Q:
			if not egg_active and not game_mode:
				vcr.cycle_aspect()
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
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and cam_t >= 1.0:
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
		return false
	for r in BLOCKERS:
		if r.has_point(Vector2(x, z)):
			return false
	return true


func _try_move(motion: Vector3) -> void:
	var p := head.global_position
	if _walkable(p.x + motion.x, p.z):
		origin.global_position.x += motion.x
		p.x += motion.x
	if _walkable(p.x, p.z + motion.z):
		origin.global_position.z += motion.z


func _snap_turn(deg: float) -> void:
	var pivot := head.global_position
	pivot.y = 0.0
	origin.global_translate(-pivot)
	origin.global_rotate(Vector3.UP, deg_to_rad(deg))
	origin.global_translate(pivot)


# ---------------------------------------------------------------- beanbag

func _build_beanbag(pos: Vector3, yaw_deg: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = deg_to_rad(yaw_deg)
	room.add_child(root)
	seat_nodes.append(root)
	seat_eye.append(0.85)
	seat_swivel.append(false)
	var fabric := _mat(Color(0.95, 0.45, 0.58), 0.95)
	var fabric_d := _mat(Color(0.78, 0.30, 0.48), 0.95)
	var cushion := _mat(Color(1.0, 0.85, 0.75), 0.95)
	# seat bulge, slumped backrest leaning toward +z, and a dented seat
	_sphere(Vector3(0, 0.26, 0.05), 0.46, fabric, Vector3(1.0, 0.62, 1.0), root, 40)
	var back := _sphere(Vector3(0, 0.5, 0.28), 0.36, fabric, Vector3(1.05, 1.0, 0.75), root, 40)
	back.rotation.x = 0.3
	_sphere(Vector3(0, 0.37, -0.06), 0.3, fabric_d, Vector3(1.0, 0.16, 1.0), root, 32)
	# carry handle loop at the top
	var loop := TorusMesh.new()
	loop.inner_radius = 0.025
	loop.outer_radius = 0.06
	var h := _place(loop, Vector3(0, 0.86, 0.34), fabric_d, root)
	h.rotation.x = PI / 2.0 + 0.3
	# little cushion on the seat
	var c := _sphere(Vector3(0.14, 0.4, -0.02), 0.2, cushion, Vector3(1.0, 0.45, 0.8), root, 24)
	c.rotation.y = 0.5


# ---------------------------------------------------------------- door (front wall)

func _build_door() -> void:
	var wood := _mat(Color(0.42, 0.17, 0.28), 0.65)
	var panel := _mat(Color(0.34, 0.12, 0.24), 0.65)
	var trim := _mat(Color(0.20, 0.07, 0.22), 0.7)
	var brass := _mat(Color(0.95, 0.75, 0.50), 0.3, 0.6)
	var x := 0.9
	var fz := FRONT_Z
	_box(Vector3(x - 0.5, 1.07, fz - 0.035), Vector3(0.07, 2.14, 0.07), trim)     # jambs
	_box(Vector3(x + 0.5, 1.07, fz - 0.035), Vector3(0.07, 2.14, 0.07), trim)
	_box(Vector3(x, 2.14, fz - 0.035), Vector3(1.07, 0.07, 0.07), trim)           # header
	_box(Vector3(x, 1.05, fz - 0.02), Vector3(0.94, 2.1, 0.04), wood)             # slab
	_box(Vector3(x, 1.55, fz - 0.045), Vector3(0.64, 0.78, 0.012), panel)         # raised panels
	_box(Vector3(x, 0.55, fz - 0.045), Vector3(0.64, 0.78, 0.012), panel)
	_box(Vector3(x + 0.36, 1.0, fz - 0.05), Vector3(0.05, 0.16, 0.012), brass)    # handle plate
	_sphere(Vector3(x + 0.36, 1.0, fz - 0.065), 0.032, brass)
	_box(Vector3(x, 0.008, fz - 0.025), Vector3(0.92, 0.012, 0.04), _mat(WARM, 0.5, 2.0))  # light under the door
	# pointing at the door offers to leave; a small "Are you sure?" sign then asks before the game closes
	var slab := _box(Vector3(x, 1.05, fz - 0.02), Vector3(0.94, 2.1, 0.04), wood)
	slab.visible = false
	interactables.append({"node": slab, "half": Vector3(0.47, 1.05, 0.06), "when": func() -> bool: return not leave_prompt,
		"label": func() -> String: return "LEAVE", "cb": _ask_leave})
	leave_panel = Node3D.new()
	leave_panel.position = Vector3(x, 1.5, fz - 0.45)
	leave_panel.visible = false
	room.add_child(leave_panel)
	var sign_m := _mat(Color(0.12, 0.05, 0.16), 0.5)
	_box(Vector3(0, 0, 0), Vector3(0.72, 0.36, 0.02), sign_m, leave_panel)
	var tl := Label3D.new()
	tl.text = "Leave the room?"
	tl.font_size = 64
	tl.pixel_size = 0.0007
	tl.modulate = Color(1.0, 0.9, 0.95)
	tl.outline_size = 0
	tl.rotation = Vector3(0, PI, 0)
	tl.position = Vector3(0, 0.1, -0.012)
	leave_panel.add_child(tl)
	# the player faces +z, so their left is +x: STAY on the left, LEAVE on the right
	var stay_m := _mat(Color(0.20, 0.55, 0.35), 0.5)
	var leave_m := _mat(Color(0.75, 0.22, 0.30), 0.5)
	var stay_b := _box(Vector3(0.17, -0.07, -0.01), Vector3(0.28, 0.12, 0.02), stay_m, leave_panel)
	var leave_b := _box(Vector3(-0.17, -0.07, -0.01), Vector3(0.28, 0.12, 0.02), leave_m, leave_panel)
	for lb in [[stay_b, "STAY", 0.17], [leave_b, "LEAVE", -0.17]]:
		var l := Label3D.new()
		l.text = lb[1]
		l.font_size = 48
		l.pixel_size = 0.0007
		l.modulate = Color(1, 1, 1)
		l.outline_size = 0
		l.rotation = Vector3(0, PI, 0)
		l.position = Vector3(float(lb[2]), -0.07, -0.024)
		leave_panel.add_child(l)
	interactables.append({"node": stay_b, "half": Vector3(0.14, 0.06, 0.03), "when": func() -> bool: return leave_prompt,
		"label": func() -> String: return "STAY", "cb": _cancel_leave})
	interactables.append({"node": leave_b, "half": Vector3(0.14, 0.06, 0.03), "when": func() -> bool: return leave_prompt,
		"label": func() -> String: return "YES, LEAVE", "cb": _do_leave})


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
	var slab := _box(Vector3(-1.65, 0.63, -1.55), Vector3(1.5, 0.16, 0.7), _mat(Color.WHITE), null)
	slab.visible = false
	interactables.append({"node": slab, "half": Vector3(0.75, 0.08, 0.35), "egg_lock": true,
		"when": func() -> bool: return not sleeping and not egg_active and updater != null and not updater.busy(),
		"label": "Nap", "cb": _go_to_sleep})
	# ... and the make-the-bed prompt down by the foot, only while the bed is a mess
	var foot := _box(Vector3(-1.65, 0.63, -0.45), Vector3(1.5, 0.16, 0.9), _mat(Color.WHITE), null)
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
		_sleep_text.modulate.a = a, _sleep_mat.albedo_color.a, to, secs)
	await tw.finished


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
	_sleep_text.text = "Waking up from your nap in the new room..." if updater.state == "done" else "Waking up from your nap..."
	if emu != null:
		emu._stop_host()                      # the running game saves its place first
	bed_made = false                          # you slept in it, so the new room has an unmade bed
	_save_prefs_tick()
	pc.save_music_dir()
	await get_tree().create_timer(0.9).timeout
	if not _relaunch():
		_sleep_text.text = "Could not restart the room"
		bed_made = true
		_save_prefs_tick()
		await get_tree().create_timer(1.6).timeout
		await _fade_veil(0.0, 1.0)
		sleeping = false
		updater.show_toast("The update is installed. Close the room and open it again to use it.")


# Starts a fresh copy of the room (same display / VR options) and closes this one.
func _relaunch() -> bool:
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
	if dry_relaunch:
		print("RELAUNCH ", OS.get_executable_path(), " ", args)
		return false
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		return false
	print("RELAUNCH pid ", pid)
	get_tree().quit()
	return true


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
		var sp := seat_nodes[i].global_position
		var dist := Vector2(p.x, p.z).distance_to(Vector2(sp.x, sp.z))
		if dist < best_d:
			best_d = dist
			best = i
	return best


func _toggle_sit() -> void:
	if seated:
		origin.global_position = stand_origin
		seated = false
		cur_seat = -1
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
	origin.global_position.y = clampf(seat_eye[idx] - head.position.y, -1.0, 0.2)
	seated = true
	cur_seat = idx


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
	room.add_child(holder)
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
	room.add_child(city)
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
		var b := _box(pos, Vector3(w, top + 40.0, depth), mat, city)
		b.rotation.y = -ang
		if rng.randf() < 0.4:
			var tw := w * rng.randf_range(0.45, 0.7)
			var th := rng.randf_range(0.8, 2.0) * grow
			var t := _box(Vector3(pos.x, top + th / 2.0, pos.z), Vector3(tw, th, depth * 0.6), mat, city)
			t.rotation.y = -ang
		ang += side * ((w * 0.5) / r)


# ---------------------------------------------------------------- CRT TV + dresser

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
	room.add_child(root)
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
			interactables.append({"node": k, "half": Vector3(0.055, 0.055, 0.05),
				"label": func() -> String: return "CHANNEL  [%s]" % CRT_NAMES[crt_mode],
				"cb": func() -> void: set_crt_mode((crt_mode + 1) % 3), "hover": _glow_hover(ch_knob_m)})
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
		"label": _tv_label.bind("power"), "egg_lock": true,
		"cb": vcr.toggle_tv, "hover": _glow_hover(pw_m)})
	var vd_m := _mat(Color(0.45, 0.40, 0.50), 0.4)
	var vu_m := _mat(Color(0.45, 0.40, 0.50), 0.4)
	var vd := _box(Vector3(px - 0.045, cy, fz + 0.01), Vector3(0.06, 0.04, 0.02), vd_m, root)
	var vu := _box(Vector3(px + 0.045, cy, fz + 0.01), Vector3(0.06, 0.04, 0.02), vu_m, root)
	interactables.append({"node": vd, "half": Vector3(0.04, 0.03, 0.04),
		"label": _tv_label.bind("vol_down"),
		"cb": vcr.volume_down, "hover": _glow_hover(vd_m)})
	interactables.append({"node": vu, "half": Vector3(0.04, 0.03, 0.04),
		"label": _tv_label.bind("vol_up"),
		"cb": vcr.volume_up, "hover": _glow_hover(vu_m)})
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
	root.position = Vector3(-2.60, 0.022, 0.35 + LOUNGE_DZ)
	root.rotation.y = PI / 2.0          # local +z faces +x (toward the beanbag)
	room.add_child(root)
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
		"label": _console_label, "egg_lock": true, "cb": toggle_console, "hover": _glow_hover(knob_m)})
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
	_controller(Vector3(-2.0, 0.022, 1.62), 0.3)
	_controller(Vector3(-2.25, 0.022, 1.95), -0.25)
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


func toggle_console() -> void:
	if egg_active or slot_cart == "neo":
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
	var arcade_in := slot_cart == "neo"
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
	room.add_child(n)
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
	var root := Node3D.new()
	root.position = CAB_POS
	root.rotation.y = PI                       # local +x (out from the wall) points along -x, into the room
	room.add_child(root)
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
				_cyl(Vector3(0.925 + r * 0.058, 0.911, zc - 0.092 - c * 0.06), 0.0195, 0.018, bm, root)
	var st_cols := [btn_cols[0], btn_cols[1], btn_cols[2], btn_cols[1]]
	for i in 4:
		_cyl(Vector3(0.855, 0.908, 0.045 - i * 0.04 + 0.0), 0.0155, 0.012, _mat(st_cols[i], 0.25, 0.3), root)
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
	var mq := _box(Vector3(0.7125, 1.65, 0), Vector3(0.004, 0.2, CAB_W - 0.09), _mat(Color(0.95, 0.97, 0.92), 0.4, 0.9), root)
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
	# the step from the monitor up to the marquee, the roof, and the sloped back
	_box(Vector3(0.675, 1.515, 0), Vector3(0.08, 0.04, CAB_W - 0.07), white, root)
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
	interactables.append({"node": plate, "half": Vector3(0.12, 0.05, 0.36), "egg_lock": true,
		"label": _arcade_label, "cb": _pick_arcade})


func _arcade_label() -> String:
	if slot_cart != "neo":
		return "ARCADE CONTROLS  (insert the Neo Geo cart first)"
	return "PLAY  (arcade controls)"


func _pick_arcade() -> void:
	if game_mode or slot_cart != "neo":
		return
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


func _build_carts() -> void:
	var lay := Basis(Vector3.RIGHT, -PI / 2.0)       # lying flat, label up
	var nes := _nes_cart_mesh()
	var snes := _snes_cart_mesh()
	var sgb := _sgb_cart_mesh()
	var gen := _gen_cart_mesh()
	var neo := _neo_cart_mesh()
	var egg_c := _nes_cart_mesh(true)
	var tv_top := 0.04 + TV_WIDTH * 0.72
	carts["nes"] = {"node": nes, "name": "NES CART", "busy": false,
		"home": func() -> Transform3D: return Transform3D(Basis(Vector3.UP, 0.5) * lay, Vector3(-2.3, 0.034, 1.12))}
	carts["snes"] = {"node": snes, "name": "SNES CART", "busy": false,
		"home": func() -> Transform3D: return tv_root.global_transform * Transform3D(Basis(Vector3.UP, 0.3) * lay, Vector3(0.52, tv_top + 0.011, 0.05))}
	carts["sgb"] = {"node": sgb, "name": "SUPER GB CART", "busy": false,
		"home": func() -> Transform3D: return Transform3D(Basis(Vector3.UP, -0.4) * lay, Vector3(-2.28, 0.034, 1.36))}
	carts["gen"] = {"node": gen, "name": "SEGA CART", "busy": false,
		"home": func() -> Transform3D: return Transform3D(Basis(Vector3.UP, 0.25) * lay, Vector3(-2.02, 0.034, 1.32))}
	carts["neo"] = {"node": neo, "name": "NEO GEO CART", "busy": false,
		"home": func() -> Transform3D: return Transform3D(Basis(Vector3.UP, -PI / 2.0 + 0.12), Vector3(2.21, 1.066, 0.55))}   # standing on the bookshelf
	carts["egg"] = {"node": egg_c, "name": "CART", "busy": false,
		"home": func() -> Transform3D: return drawer_node.global_transform * Transform3D(Basis(Vector3.UP, 0.15) * lay, Vector3(0, -0.053, -0.15))}
	for id in ["nes", "snes", "sgb", "gen", "neo"]:
		var n: Node3D = carts[id]["node"]
		n.global_transform = (carts[id]["home"] as Callable).call()
	egg_c.reparent(drawer_node, false)
	egg_c.transform = Transform3D(Basis(Vector3.UP, 0.15) * lay, Vector3(0, -0.053, -0.15))
	for id in ["nes", "snes", "sgb", "gen", "neo", "egg"]:
		interactables.append({"node": carts[id]["node"], "half": Vector3(0.085, 0.065, 0.03), "egg_lock": true,
			"label": _cart_label.bind(id), "cb": _cart_click.bind(id)})


func _cart_label(id: String) -> String:
	if slot_cart == id:
		return "EJECT CART"
	return "INSERT " + String(carts[id]["name"])


func _cart_click(id: String) -> void:
	if egg_active or bool(carts[id]["busy"]):
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
	if n.get_parent() != room:
		n.reparent(room, true)
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
	d["levels"] = [snappedf(weather.levels[1], 0.01), snappedf(weather.levels[2], 0.01), snappedf(weather.levels[3], 0.01)]
	for i in bank.speakers.size():
		d["spk_" + String(bank.speakers[i]["name"])] = bank.is_enabled(i)
	for g in light_groups:
		d["light_" + String(g["name"])] = bool(g["on"])
	return d


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and pc != null:
		pc.save_music_dir()                     # closing the window keeps the music folder you were in


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
		weather_start = "remember" if str(cfg.get_value("settings", "weather_start", "random")) == "remember" else "random"
		if weather_start == "remember" and cfg.has_section_key("room", "weather_mode"):
			weather.set_mode(clampi(int(cfg.get_value("room", "weather_mode", 0)), 0, 3))
			weather.snap()
		for i in bank.speakers.size():
			bank.set_enabled(i, bool(g.call("spk_" + String(bank.speakers[i]["name"]), true)))
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


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	cfg.set_value("settings", "reticle_on", reticle_on)
	cfg.set_value("settings", "reticle_color", reticle_color_idx)
	cfg.set_value("settings", "weather_start", weather_start)
	cfg.set_value("settings", "resume_games", emu.resume_games if emu != null else true)
	cfg.set_value("settings", "cart_wash", cart_wash)
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
	room.add_child(root)
	_pad_meshes(root)
	ctrl_exits.append(root.to_global(Vector3(0, 0.014, -0.052)))
	var idx := pad_nodes.size()
	pad_nodes.append(root)
	interactables.append({"node": root, "half": Vector3(0.095, 0.035, 0.065), "label": _pad_label, "cb": _pick_pad.bind(idx)})


func _build_dresser() -> void:
	var wood := _mat(Color(0.34, 0.14, 0.22), 0.6)
	var inset := _mat(Color(0.26, 0.10, 0.18), 0.6)
	var brass := _mat(Color(0.95, 0.75, 0.50), 0.3, 0.5)
	_box(Vector3(-3.62, 0.38, -1.2), Vector3(0.55, 0.76, 1.1), wood)
	for dy in [0.2, 0.42, 0.64]:
		_box(Vector3(-3.335, dy, -1.2), Vector3(0.01, 0.17, 0.96), inset)
		_sphere(Vector3(-3.325, dy, -1.2), 0.016, brass, Vector3.ONE, null, 8)
	_plant(Vector3(-3.6, 0.76, -1.45), 0.6)
	incense = Incense.new()
	incense.setup(self, Vector3(-3.6, 0.76, -0.95))      # a stick of incense on the dresser, under the speakers


# ---------------------------------------------------------------- power: outlets, strips, cords

func _outlet(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	room.add_child(root)
	_box(Vector3(0, 0, 0.006), Vector3(0.075, 0.115, 0.012), _mat(Color(0.92, 0.88, 0.92), 0.5), root)
	var slot := _mat(Color(0.12, 0.08, 0.14), 0.5)
	_box(Vector3(0, 0.028, 0.013), Vector3(0.018, 0.03, 0.004), slot, root)
	_box(Vector3(0, -0.028, 0.013), Vector3(0.018, 0.03, 0.004), slot, root)


func _plug(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	room.add_child(root)
	_box(Vector3(0, 0, 0.03), Vector3(0.04, 0.055, 0.035), _mat(Color(0.08, 0.06, 0.10), 0.5), root)


func _power_strip(pos: Vector3, yaw: float, length: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	room.add_child(root)
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
	cord_paths.append([_smooth_path(ctrl, 6), radius, col])


func _finish_cords() -> void:
	if cord_paths.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	for entry in cord_paths:
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
	room.add_child(mi)


func _build_power() -> void:
	var black := Color(0.06, 0.04, 0.08)
	var white := Color(0.92, 0.88, 0.92)
	var yellow := Color(0.95, 0.80, 0.20)
	# wall outlets (back wall faces +z, left wall faces +x)
	_outlet(Vector3(1.1, 0.3, -2.0), 0.0)             # desk power strip
	_outlet(Vector3(2.2, 0.3, -2.0), 0.0)             # desk lamp
	_outlet(Vector3(-0.15, 0.3, -2.0), 0.0)           # nightstand lamp
	_outlet(Vector3(-3.9, 0.3, -0.2 + LOUNGE_DZ), PI / 2.0)       # TV + console strip
	_outlet(Vector3(-3.9, 0.3, FRONT_Z - 0.2), PI / 2.0)        # fairy lights
	_outlet(Vector3(-3.9, 0.3, 0.3), PI / 2.0)                  # wall speakers
	_plug(Vector3(1.1, 0.3, -2.0), 0.0)
	_plug(Vector3(2.2, 0.3, -2.0), 0.0)
	_plug(Vector3(-0.15, 0.3, -2.0), 0.0)
	_plug(Vector3(-3.9, 0.3, -0.2 + LOUNGE_DZ), PI / 2.0)
	_plug(Vector3(-3.9, 0.3, FRONT_Z - 0.2), PI / 2.0)
	_plug(Vector3(-3.9, 0.3, 0.3), PI / 2.0)

	# desk: strip on the floor under the desk, monitor + keyboard, lamp
	_power_strip(Vector3(1.5, 0.017, -1.88), PI / 2.0, 0.48)
	_cord([Vector3(1.1, 0.3, -1.93), Vector3(1.1, 0.2, -1.92), Vector3(1.14, 0.05, -1.9), Vector3(1.28, 0.034, -1.88)], 0.007, white)
	_cord([Vector3(1.45, 0.95, -1.745), Vector3(1.45, 0.84, -1.8), Vector3(1.47, 0.79, -1.955), Vector3(1.47, 0.5, -1.975), Vector3(1.5, 0.1, -1.93), Vector3(1.5, 0.036, -1.88)], 0.007, black)
	_cord([Vector3(1.45, 0.808, -1.45), Vector3(1.52, 0.80, -1.55), Vector3(1.47, 0.80, -1.66)], 0.004, black)
	_cord([Vector3(2.2, 0.80, -1.78), Vector3(2.2, 0.79, -1.94), Vector3(2.22, 0.5, -1.975), Vector3(2.2, 0.3, -1.95)], 0.005, white)

	# desk speakers to the strip
	_cord([Vector3(0.96, 0.84, -1.84), Vector3(0.97, 0.80, -1.93), Vector3(1.0, 0.5, -1.985), Vector3(1.2, 0.1, -1.95), Vector3(1.34, 0.036, -1.88)], 0.005, black)
	_cord([Vector3(1.94, 0.84, -1.84), Vector3(1.93, 0.80, -1.935), Vector3(1.9, 0.5, -1.99), Vector3(1.7, 0.1, -1.95), Vector3(1.66, 0.036, -1.88)], 0.005, black)
	# wall speakers: chained along the wall under them, then down to their own outlet
	_cord([Vector3(-3.86, 1.89, -1.55), Vector3(-3.885, 1.82, -1.3), Vector3(-3.885, 1.80, -1.15), Vector3(-3.885, 1.82, -0.9), Vector3(-3.86, 1.89, -0.75)], 0.004, black)
	_cord([Vector3(-3.86, 1.89, -0.75), Vector3(-3.885, 1.82, -0.5), Vector3(-3.885, 1.80, -0.35), Vector3(-3.885, 1.82, -0.1), Vector3(-3.86, 1.89, 0.05)], 0.004, black)
	_cord([Vector3(-3.86, 1.89, 0.05), Vector3(-3.885, 1.82, 0.12), Vector3(-3.887, 1.0, 0.25), Vector3(-3.887, 0.45, 0.3), Vector3(-3.84, 0.3, 0.3)], 0.005, black)

	# nightstand lamp
	_cord([Vector3(-0.5, 0.475, -1.73), Vector3(-0.4, 0.465, -1.88), Vector3(-0.37, 0.44, -1.935), Vector3(-0.3, 0.3, -1.96), Vector3(-0.15, 0.3, -1.95)], 0.005, white)

	# TV + console strip on the floor by the left wall
	var dz := LOUNGE_DZ
	_power_strip(Vector3(-3.62, 0.017, -0.05 + dz), 0.0, 0.5)
	_cord([Vector3(-3.85, 0.3, -0.2 + dz), Vector3(-3.8, 0.15, -0.2 + dz), Vector3(-3.72, 0.03, -0.2 + dz), Vector3(-3.62, 0.034, -0.2 + dz)], 0.007, white)
	var tv_back := tv_root.to_global(Vector3(0.45, 0.15, -0.775))
	_cord([tv_back, Vector3(-3.84, 0.06, 0.35 + dz), Vector3(-3.78, 0.012, 0.15 + dz), Vector3(-3.7, 0.012, 0.0 + dz), Vector3(-3.62, 0.034, 0.0 + dz)], 0.009, black)
	var c_back := console_root.to_global(Vector3(0.12, 0.035, -0.19))
	_cord([c_back, Vector3(-2.74, 0.012, 0.14 + dz), Vector3(-3.0, 0.012, 0.09 + dz), Vector3(-3.4, 0.012, 0.04 + dz), Vector3(-3.6, 0.034, 0.05 + dz)], 0.005, black)
	# console to TV (video cable) and the two controller cables
	var av_from := console_root.to_global(Vector3(-0.07, 0.05, -0.19))
	var av_to := tv_root.to_global(Vector3(TV_WIDTH / 2.0 - 0.28, 0.1, 0.235))
	_cord([av_from, Vector3(-2.78, 0.034, 0.4 + dz), Vector3(-2.86, 0.06, 0.37 + dz), av_to], 0.004, yellow)
	var port_a := console_root.to_global(Vector3(-0.004, 0.03, 0.185))
	var port_b := console_root.to_global(Vector3(0.094, 0.03, 0.185))
	_cord([port_a, Vector3(-2.3, 0.034, 0.27 + dz), Vector3(-2.2, 0.034, 0.2 + dz), ctrl_exits[0]], 0.004, black)
	_cord([port_b, Vector3(-2.3, 0.034, 0.5 + dz), Vector3(-2.15, 0.034, 0.65 + dz), ctrl_exits[1]], 0.004, black)

	# VCR on top of the TV: power cord down the back of the TV to the strip, video cable to the TV
	var tl := func(p: Vector3) -> Vector3: return tv_root.to_global(p)
	_cord([tl.call(Vector3(-0.35, 1.13, -0.2)), tl.call(Vector3(-0.38, 1.02, -0.3)), tl.call(Vector3(-0.40, 0.87, -0.5)),
			tl.call(Vector3(-0.42, 0.75, -0.645)), tl.call(Vector3(-0.42, 0.3, -0.645)), tl.call(Vector3(-0.42, 0.05, -0.645)),
			Vector3(-3.86, 0.034, 2.4), Vector3(-3.86, 0.034, 1.6), Vector3(-3.64, 0.034, 1.3)], 0.005, black)
	_cord([tl.call(Vector3(0.3, 1.13, -0.2)), tl.call(Vector3(0.3, 1.02, -0.3)), tl.call(Vector3(0.28, 0.87, -0.5)),
			tl.call(Vector3(0.26, 0.75, -0.645)), tl.call(Vector3(0.26, 0.6, -0.645))], 0.004, yellow)

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
		var best := POINTER_RANGE
		var sc_hit: ScreenUI = null
		var sc_pos := Vector2.ZERO
		var it_hit: Dictionary = {}
		for sc in screens:
			var h: Dictionary = sc.hit(o, d, POINTER_RANGE)
			if not h.is_empty() and float(h["t"]) < best:
				best = float(h["t"])
				sc_hit = sc
				sc_pos = h["pos"]
				it_hit = {}
		for it in interactables:
			if it.has("when") and not bool((it["when"] as Callable).call()):
				continue
			var t := _ray_box(o, d, it["node"], it["half"])
			if t >= 0.0 and t < best:
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
		# the closer you are, the smaller the sign (so it never fills the view); from ~1.2 m away it is full size
		var k := clampf(found_t / 1.2, 0.2, 1.0)
		hint_label.scale = Vector3.ONE * k
		hint_label.global_position = found_point + Vector3(0.0, 0.02 + 0.08 * k, 0.0)
		hint_label.visible = true
	elif game_mode and pad_hint_t > 0.0:
		hint_label.text = "CONTROLLER:  %s  =  PUT IT DOWN" % ("GRIP" if xr_active else "E")
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

	# scroll lists with the right thumbstick while pointing at a screen
	scroll_cd = maxf(0.0, scroll_cd - delta)
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
		down_screen = hover_screen
		ptr_down = true
		hover_screen.send_button(hover_pos, true)
		return true
	if not hover_item.is_empty():
		if egg_active and hover_item.get("egg_lock", false):
			return true                       # locked while the alert is on
		var cb: Callable = hover_item["cb"]
		cb.call()
		return true
	return false


func _pointer_release(_hand: int) -> void:
	if ptr_down and down_screen != null:
		down_screen.send_button(down_screen.last_pos, false)
	ptr_down = false
	down_screen = null


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
		var to: Vector3 = sc.global_position - p
		var dist := to.length()
		if dist > 6.0 or dist < 0.05:
			continue
		var dir := to / dist
		if sc.global_transform.basis.z.dot(-dir) <= 0.0:
			continue      # we're behind it
		var d := f.dot(dir)
		if d > best_dot:
			best_dot = d
			best = sc
	return best


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
