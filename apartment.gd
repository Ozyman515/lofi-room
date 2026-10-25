extends Node3D
## The rest of the apartment around the bedroom. It's a corner unit: the city is to the north (-z) and the east
## (+x), and a covered balcony wraps round that corner so the skyline (and whatever is stomping about in it) can
## be watched from two sides.
##
##            city
##   ┌─────────────────────────────────────┐
##   │ balcony ............................│..
##   ├──────────────┬──────────────────────┤..
##   │ bedroom      │ living room          │.. city
##   │ (main.room)  │                      │..
##   ├──── door ────┴──── arch ────────────┤..
##   │ front door   hallway                │
##   └──── game room ── study ── theater ──┘   (the last three are still being done up: their doors stay shut)
##
## Each room is its own node, and only the room you're in (plus whatever you can see from it) is drawn. Doors open
## by themselves when somebody walks up to them. Room coordinates: +x east, -z north, the floor at y = 0.

const Plat := preload("res://platform.gd")

const H := 2.8                    # wall height (the ceilings sit on top)
const NORTH_Z := -2.05            # the window wall line (bedroom and living room)
const FRONT_Z := 3.4              # bedroom front wall / living room south wall line
const HALL_S := 5.35              # hallway south wall line
const WEST_X := -3.95             # bedroom / hallway west wall line
const MID_X := 2.55               # bedroom east wall line
const EAST_X := 9.65              # the building's east wall (living room and hallway)
const BAL_N := -4.35              # balcony railing, north side
const BAL_E := 11.8               # balcony railing, east side
const BED_DOOR := Vector2(0.43, 1.37)        # x span of the bedroom door
const DOOR_TOP := 2.12
const ARCH := Vector2(3.6, 5.6)              # x span of the arch from the hallway into the living room
const ARCH_TOP := 2.35
const BAL_DOOR := Vector2(5.0, 6.8)          # x span of the living room's sliding door onto the balcony
const BAL_DOOR_TOP := 2.25
const LIV_WIN := [Vector2(2.9, 4.7), Vector2(7.1, 9.35)]   # living room north windows (x spans)
const EAST_WIN := Vector2(-1.75, 2.95)       # living room east window (z span)
const WIN_LO := 0.5
const WIN_HI := 2.5
const FRONT_DOOR_Z := 4.4
const LOCKED := [[7.0, "THEATER"]]          # hallway south wall: x, name (still being done up)
const STUDY_DOOR := 2.4
const STUDY_E := 4.6                         # study east wall line
const STUDY_WALK := Rect2(0.72, 5.68, 3.56, 4.37)
# the desk and the bookshelf were built in the bedroom's back-right corner; turned round, that corner is the study's
# front-left: the desk against the study's south wall, the bookshelf against its west wall
const STUDY_KIT_XF := Transform3D(Basis(Vector3.UP, PI), Vector3(2.95, 0.0, 8.3))
const GAME_DOOR := -1.6                     # x of the game room door (hallway south wall)
const GAME_S := 10.35                       # game room south wall line
const GAME_E := 0.4                         # game room east wall line
const GAME_WALK := Rect2(-3.65, 5.68, 3.75, 4.37)
# the TV corner was built in the bedroom's front-left corner: moved down here, the corner lines up with the game
# room's south-west corner (same west wall line, the bedroom's front wall becomes the game room's south wall)
const GAME_KIT_SHIFT := Vector3(0.0, 0.0, GAME_S - 3.45)
# the arcade was built against the bedroom's right wall (x 2.5): here it stands against the game room's east wall
const ARCADE_KIT_SHIFT := Vector3(GAME_E - 0.05 - 2.5, 0.0, 6.45 - 1.95)

# where people can walk (x, z, w, h), with a margin from the walls
const HALL_WALK := Rect2(-3.65, 3.72, 12.95, 1.33)
const LIV_WALK := Rect2(2.88, -1.75, 6.47, 4.85)
const BAL_WALK_N := Rect2(-3.7, -4.08, 15.25, 1.75)
const BAL_WALK_E := Rect2(9.95, -4.08, 1.6, 7.15)
const DOORWAYS := [Rect2(0.55, 3.0, 0.7, 0.9), Rect2(3.75, 2.9, 1.7, 1.0), Rect2(5.15, -2.55, 1.5, 0.95),
	Rect2(GAME_DOOR - 0.35, 4.95, 0.7, 0.85), Rect2(STUDY_DOOR - 0.35, 4.95, 0.7, 0.85)]

var main: Node3D
var hallway: Node3D
var living: Node3D
var balcony: Node3D
var game: Node3D
var study: Node3D
var exterior: Node3D
var doors_root: Node3D
var rooms := {}                   # id -> root node ("bedroom" is the main room)
var current := "bedroom"          # the room I'm in (stays put while I'm in a doorway)
var _blockers := {}               # room id -> Array of Rect2 (furniture)
var _doors: Array = []            # [{pivot, at: Vector2, open: float, sign: float}]
var _room_of := {}                # node instance id -> room id (cached, for the pointer)
var _seen := {}                   # what's drawn right now

# who sees whom (besides through doors that are open)
const SEES := {
	"bedroom": ["balcony"],
	"hallway": ["living"],
	"game": [],
	"study": [],
	"living": ["hallway", "balcony"],
	"balcony": ["bedroom", "living"],
}


func build(m: Node3D) -> void:
	main = m
	name = "Apartment"
	m.add_child(self)
	rooms["bedroom"] = main.room
	hallway = _root("Hallway")
	living = _root("LivingRoom")
	balcony = _root("Balcony")
	game = _root("GameRoom")
	study = _root("Study")
	exterior = _root("Exterior")
	doors_root = _root("Doors")             # seen from both sides, so always drawn
	for id in ["hallway", "living", "balcony", "game", "study"]:
		_blockers[id] = []
	rooms["hallway"] = hallway
	rooms["living"] = living
	rooms["balcony"] = balcony
	rooms["game"] = game
	rooms["study"] = study
	_build_hallway()
	_build_living()
	_build_balcony()
	_build_game()
	_build_study()
	_build_exterior()


func _root(n: String) -> Node3D:
	var r := Node3D.new()
	r.name = n
	add_child(r)
	return r


# ---------------------------------------------------------------- helpers

func _box(pos: Vector3, size: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	return main._box(pos, size, mat, parent)


func _mat(c: Color, rough := 0.85, emit := 0.0) -> StandardMaterial3D:
	return main._mat(c, rough, emit)


# a wall running along x at depth z (from z0 to z1), with rectangular openings [x0, x1, y0, y1]
func _wall_x(x0: float, x1: float, z0: float, z1: float, holes: Array, mat: Material, parent: Node3D) -> void:
	var zc := (z0 + z1) / 2.0
	var d := z1 - z0
	var x := x0
	holes.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	for hl in holes:
		if hl[0] > x:
			_box(Vector3((x + hl[0]) / 2.0, H / 2.0, zc), Vector3(hl[0] - x, H, d), mat, parent)
		var w: float = hl[1] - hl[0]
		var cx: float = (hl[0] + hl[1]) / 2.0
		if hl[2] > 0.0:
			_box(Vector3(cx, hl[2] / 2.0, zc), Vector3(w, hl[2], d), mat, parent)
		if hl[3] < H:
			_box(Vector3(cx, (hl[3] + H) / 2.0, zc), Vector3(w, H - hl[3], d), mat, parent)
		x = hl[1]
	if x1 > x:
		_box(Vector3((x + x1) / 2.0, H / 2.0, zc), Vector3(x1 - x, H, d), mat, parent)


# a wall running along z at x (from x0 to x1), with openings [z0, z1, y0, y1]
func _wall_z(z0: float, z1: float, x0: float, x1: float, holes: Array, mat: Material, parent: Node3D) -> void:
	var xc := (x0 + x1) / 2.0
	var d := x1 - x0
	var z := z0
	holes.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	for hl in holes:
		if hl[0] > z:
			_box(Vector3(xc, H / 2.0, (z + hl[0]) / 2.0), Vector3(d, H, hl[0] - z), mat, parent)
		var w: float = hl[1] - hl[0]
		var cz: float = (hl[0] + hl[1]) / 2.0
		if hl[2] > 0.0:
			_box(Vector3(xc, hl[2] / 2.0, cz), Vector3(d, hl[2], w), mat, parent)
		if hl[3] < H:
			_box(Vector3(xc, (hl[3] + H) / 2.0, cz), Vector3(d, H - hl[3], w), mat, parent)
		z = hl[1]
	if z1 > z:
		_box(Vector3(xc, H / 2.0, (z + z1) / 2.0), Vector3(d, H, z1 - z), mat, parent)


func _light(pos: Vector3, col: Color, energy: float, reach: float, parent: Node3D) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	parent.add_child(l)
	return l


func _label(text: String, pos: Vector3, yaw: float, size: int, col: Color, parent: Node3D) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0009
	l.outline_size = 0
	l.modulate = col
	l.position = pos
	l.rotation.y = yaw
	parent.add_child(l)
	return l


# a door slab on a hinge: `hinge` is the hinge corner on the floor, the slab runs along +x (before turning);
# `yaw` turns the whole door to its wall
func _door_slab(parent: Node3D, hinge: Vector3, yaw: float, width: float, wood: Material, panel: Material, brass: Material) -> Node3D:
	var frame := Node3D.new()
	frame.position = hinge
	frame.rotation.y = yaw
	parent.add_child(frame)
	var pivot := Node3D.new()
	frame.add_child(pivot)
	_box(Vector3(width / 2.0, 1.05, 0.0), Vector3(width - 0.02, 2.08, 0.04), wood, pivot)
	for side in [-1.0, 1.0]:
		_box(Vector3(width / 2.0, 1.52, side * 0.024), Vector3(width * 0.68, 0.74, 0.01), panel, pivot)
		_box(Vector3(width / 2.0, 0.55, side * 0.024), Vector3(width * 0.68, 0.74, 0.01), panel, pivot)
		main._sphere(Vector3(width - 0.1, 1.0, side * 0.045), 0.03, brass, Vector3.ONE, pivot)
	return pivot


# jambs and a header around a door opening (x span along the frame's local x, at local z = 0)
func _door_frame(parent: Node3D, center: Vector3, yaw: float, width: float, top: float, trim: Material) -> void:
	var f := Node3D.new()
	f.position = center
	f.rotation.y = yaw
	parent.add_child(f)
	_box(Vector3(-width / 2.0 - 0.035, top / 2.0, 0.0), Vector3(0.07, top, 0.16), trim, f)
	_box(Vector3(width / 2.0 + 0.035, top / 2.0, 0.0), Vector3(0.07, top, 0.16), trim, f)
	_box(Vector3(0.0, top + 0.035, 0.0), Vector3(width + 0.14, 0.07, 0.16), trim, f)


# ---------------------------------------------------------------- hallway: front door, the phone, three shut doors

func _build_hallway() -> void:
	var p := hallway
	var wall := _mat(Color(0.28, 0.12, 0.35))
	var floor_m := _mat(Color(0.22, 0.09, 0.16), 0.6)
	var ceil_m := _mat(Color(0.20, 0.08, 0.26))
	var trim := _mat(Color(0.20, 0.07, 0.22), 0.7)
	var wood := _mat(Color(0.42, 0.17, 0.28), 0.65)
	var panel := _mat(Color(0.34, 0.12, 0.24), 0.65)
	var brass := _mat(Color(0.95, 0.75, 0.50), 0.3, 0.6)
	var x0 := WEST_X - 0.05
	var x1 := EAST_X + 0.05
	var zc := (FRONT_Z + HALL_S) / 2.0
	var zl := HALL_S - FRONT_Z
	_box(Vector3((x0 + x1) / 2.0, -0.05, zc), Vector3(x1 - x0, 0.1, zl + 0.1), floor_m, p)
	_box(Vector3((x0 + x1) / 2.0, H + 0.05, zc), Vector3(x1 - x0, 0.1, zl + 0.1), ceil_m, p)
	# its own north wall (the bedroom and living room have theirs: this is the hallway's face of it)
	_wall_x(x0, x1, FRONT_Z + 0.05, FRONT_Z + 0.1, [[BED_DOOR.x, BED_DOOR.y, 0.0, DOOR_TOP], [ARCH.x, ARCH.y, 0.0, ARCH_TOP]], wall, p)
	_wall_x(x0, x1, HALL_S, HALL_S + 0.1, [[GAME_DOOR - 0.47, GAME_DOOR + 0.47, 0.0, DOOR_TOP], [STUDY_DOOR - 0.47, STUDY_DOOR + 0.47, 0.0, DOOR_TOP]], wall, p)   # south: game room, study
	_box(Vector3(WEST_X, H / 2.0, zc), Vector3(0.1, H, zl + 0.1), wall, p)                               # west (front door)
	_box(Vector3(EAST_X, H / 2.0, zc), Vector3(0.1, H, zl + 0.1), wall, p)                               # east end
	# baseboards
	_box(Vector3((x0 + x1) / 2.0, 0.05, HALL_S - 0.01), Vector3(x1 - x0, 0.1, 0.02), trim, p)
	# a runner down the middle
	_box(Vector3(2.6, 0.006, zc), Vector3(11.5, 0.012, 0.9), _mat(Color(0.55, 0.18, 0.36), 0.95), p)
	_box(Vector3(2.6, 0.007, zc), Vector3(11.2, 0.012, 0.7), _mat(Color(0.40, 0.12, 0.30), 0.95), p)

	# the bedroom door: on a hinge, swings out into the hallway
	_door_frame(p, Vector3((BED_DOOR.x + BED_DOOR.y) / 2.0, 0.0, FRONT_Z + 0.08), 0.0, BED_DOOR.y - BED_DOOR.x, DOOR_TOP, trim)
	var bd := _door_slab(doors_root, Vector3(BED_DOOR.x, 0.0, FRONT_Z), 0.0, BED_DOOR.y - BED_DOOR.x, wood, panel, brass)
	_doors.append({"pivot": bd, "at": Vector2((BED_DOOR.x + BED_DOOR.y) / 2.0, FRONT_Z), "open": 0.0, "sign": -1.0,
		"links": ["bedroom", "hallway"]})
	# the arch into the living room
	_door_frame(p, Vector3((ARCH.x + ARCH.y) / 2.0, 0.0, FRONT_Z + 0.05), 0.0, ARCH.y - ARCH.x, ARCH_TOP, trim)

	# the front door (west end): pointing at it offers to leave
	_door_frame(p, Vector3(WEST_X + 0.05, 0.0, FRONT_DOOR_Z), PI / 2.0, 0.94, DOOR_TOP, trim)
	var fd_wood := _mat(Color(0.30, 0.12, 0.22), 0.6)
	_door_slab(p, Vector3(WEST_X + 0.07, 0.0, FRONT_DOOR_Z + 0.47), PI / 2.0, 0.94, fd_wood, panel, brass)
	main._sphere(Vector3(WEST_X + 0.08, 1.55, FRONT_DOOR_Z), 0.018, _mat(Color(0.9, 0.9, 0.95), 0.2, 0.4), Vector3.ONE, p)  # peephole
	_box(Vector3(WEST_X + 0.07, 0.008, FRONT_DOOR_Z), Vector3(0.04, 0.012, 0.92), _mat(main.WARM, 0.5, 2.0), p)   # light under the door
	_label("12", Vector3(WEST_X + 0.08, 1.85, FRONT_DOOR_Z), PI / 2.0, 90, Color(0.95, 0.78, 0.5), p)
	var mat_m := _mat(Color(0.45, 0.30, 0.22), 0.95)
	_box(Vector3(WEST_X + 0.5, 0.008, FRONT_DOOR_Z), Vector3(0.55, 0.016, 0.85), mat_m, p)                     # doormat
	var hit := _box(Vector3(WEST_X + 0.1, 1.05, FRONT_DOOR_Z), Vector3(0.04, 2.1, 0.94), wood, p)
	hit.visible = false
	main.interactables.append({"node": hit, "half": Vector3(0.06, 1.05, 0.47), "when": func() -> bool: return not main.leave_prompt,
		"label": func() -> String: return "LEAVE", "cb": main._ask_leave, "guest_ok": true})
	_build_leave_sign(p)
	# coat hooks and a shoe rack by the door
	for i in 3:
		var hz := FRONT_DOOR_Z + 0.75 + i * 0.16
		_box(Vector3(WEST_X + 0.08, 1.7, hz), Vector3(0.05, 0.03, 0.03), brass, p)
	_box(Vector3(WEST_X + 0.06, 1.68, FRONT_DOOR_Z + 0.91), Vector3(0.02, 0.06, 0.5), trim, p)
	var coat := _mat(Color(0.25, 0.32, 0.55), 0.9)
	_box(Vector3(WEST_X + 0.14, 1.3, FRONT_DOOR_Z + 0.75), Vector3(0.12, 0.75, 0.3), coat, p)
	_box(Vector3(WEST_X + 0.22, 0.12, FRONT_DOOR_Z - 0.75), Vector3(0.3, 0.24, 0.5), trim, p)                 # shoe rack
	for i in 2:
		_box(Vector3(WEST_X + 0.22, 0.29, FRONT_DOOR_Z - 0.88 + i * 0.26), Vector3(0.26, 0.1, 0.1), _mat(Color(0.9, 0.85, 0.9), 0.7), p)
	_blockers["hallway"].append(Rect2(WEST_X, FRONT_DOOR_Z - 1.05, 0.5, 0.6))

	# three doors still shut while those rooms are done up
	var tape := _mat(Color(1.0, 0.82, 0.15), 0.6, 0.3)
	for lk in LOCKED:
		var lx: float = lk[0]
		_door_frame(p, Vector3(lx, 0.0, HALL_S - 0.06), 0.0, 0.94, DOOR_TOP, trim)
		_box(Vector3(lx, 1.05, HALL_S - 0.03), Vector3(0.92, 2.08, 0.04), wood, p)
		_box(Vector3(lx, 1.52, HALL_S - 0.055), Vector3(0.64, 0.74, 0.01), panel, p)
		_box(Vector3(lx, 0.55, HALL_S - 0.055), Vector3(0.64, 0.74, 0.01), panel, p)
		main._sphere(Vector3(lx + 0.36, 1.0, HALL_S - 0.075), 0.03, brass, Vector3.ONE, p)
		for k in [-1.0, 1.0]:
			var t := _box(Vector3(lx, 1.25, HALL_S - 0.085), Vector3(1.15, 0.09, 0.005), tape, p)
			t.rotation.z = k * 0.55
		var sign_m := _mat(Color(0.95, 0.92, 0.85), 0.8)
		_box(Vector3(lx, 1.7, HALL_S - 0.09), Vector3(0.5, 0.2, 0.01), sign_m, p)
		_label(str(lk[1]), Vector3(lx, 1.74, HALL_S - 0.097), PI, 44, Color(0.15, 0.08, 0.15), p)
		_label("coming soon", Vector3(lx, 1.66, HALL_S - 0.097), PI, 32, Color(0.45, 0.2, 0.35), p)
	# a little table and a picture
	_box(Vector3(5.8, 0.42, HALL_S - 0.22), Vector3(0.9, 0.04, 0.32), wood, p)
	for lx2 in [5.4, 6.2]:
		_box(Vector3(lx2, 0.2, HALL_S - 0.22), Vector3(0.04, 0.4, 0.28), trim, p)
	_blockers["hallway"].append(Rect2(5.3, HALL_S - 0.42, 1.0, 0.42))
	main._sphere(Vector3(5.55, 0.52, HALL_S - 0.22), 0.07, _mat(Color(0.3, 0.6, 0.5), 0.6), Vector3(1, 1.3, 1), p)
	var bowl := _mat(Color(0.95, 0.75, 0.5), 0.4)
	_box(Vector3(6.05, 0.46, HALL_S - 0.22), Vector3(0.22, 0.04, 0.16), bowl, p)
	# ceiling lights
	for lx3 in [-1.8, 3.4, 7.8]:
		main._cyl(Vector3(lx3, H - 0.02, zc), 0.16, 0.03, _mat(Color(1.0, 0.85, 0.65), 0.4, 2.2), p)
	_light(Vector3(-1.8, 2.4, zc), main.WARM, 0.8, 4.2, p)
	_light(Vector3(5.6, 2.4, zc), main.WARM, 0.8, 5.0, p)


func _build_leave_sign(p: Node3D) -> void:
	var lp := Node3D.new()
	lp.position = Vector3(WEST_X + 0.5, 1.5, FRONT_DOOR_Z)
	lp.rotation.y = PI / 2.0                  # its front (local +z) faces down the hallway, toward you
	lp.visible = false
	p.add_child(lp)
	main.leave_panel = lp
	var sign_m := _mat(Color(0.12, 0.05, 0.16), 0.5)
	_box(Vector3.ZERO, Vector3(0.72, 0.36, 0.02), sign_m, lp)
	var tl := Label3D.new()
	tl.text = "Leave the room?"
	tl.font_size = 64
	tl.pixel_size = 0.0007
	tl.modulate = Color(1.0, 0.9, 0.95)
	tl.outline_size = 0
	tl.position = Vector3(0, 0.1, 0.012)
	lp.add_child(tl)
	var stay_m := _mat(Color(0.20, 0.55, 0.35), 0.5)
	var leave_m := _mat(Color(0.75, 0.22, 0.30), 0.5)
	var stay_b := _box(Vector3(-0.17, -0.07, 0.01), Vector3(0.28, 0.12, 0.02), stay_m, lp)
	var leave_b := _box(Vector3(0.17, -0.07, 0.01), Vector3(0.28, 0.12, 0.02), leave_m, lp)
	for lb in [["STAY", -0.17], ["LEAVE", 0.17]]:
		var l := Label3D.new()
		l.text = lb[0]
		l.font_size = 48
		l.pixel_size = 0.0007
		l.modulate = Color(1, 1, 1)
		l.outline_size = 0
		l.position = Vector3(float(lb[1]), -0.07, 0.024)
		lp.add_child(l)
	main.interactables.append({"node": stay_b, "guest_ok": true, "half": Vector3(0.14, 0.06, 0.03), "when": func() -> bool: return main.leave_prompt,
		"label": func() -> String: return "STAY", "cb": main._cancel_leave})
	main.interactables.append({"node": leave_b, "guest_ok": true, "half": Vector3(0.14, 0.06, 0.03), "when": func() -> bool: return main.leave_prompt,
		"label": func() -> String: return "YES, LEAVE", "cb": main._do_leave})


# ---------------------------------------------------------------- living room (moving boxes for now)

func _build_living() -> void:
	var p := living
	var wall := _mat(Color(0.27, 0.12, 0.37))
	var floor_m := _mat(Color(0.21, 0.08, 0.17), 0.6)
	var ceil_m := _mat(Color(0.20, 0.08, 0.26))
	var trim := _mat(Color(0.14, 0.05, 0.16))
	var x0 := MID_X + 0.05
	var cx := (x0 + EAST_X) / 2.0
	var zc := (NORTH_Z + FRONT_Z) / 2.0
	var zl := FRONT_Z - NORTH_Z
	_box(Vector3(cx, -0.05, zc), Vector3(EAST_X - x0 + 0.05, 0.1, zl + 0.1), floor_m, p)
	_box(Vector3(cx, H + 0.05, zc), Vector3(EAST_X - x0 + 0.05, 0.1, zl + 0.1), ceil_m, p)
	_box(Vector3(x0 + 0.03, H / 2.0, zc), Vector3(0.06, H, zl), wall, p)                                    # west (the bedroom's on the other side)
	_wall_x(x0, EAST_X + 0.05, FRONT_Z - 0.05, FRONT_Z + 0.05, [[ARCH.x, ARCH.y, 0.0, ARCH_TOP]], wall, p)      # south, the arch
	var holes: Array = [[BAL_DOOR.x, BAL_DOOR.y, 0.0, BAL_DOOR_TOP]]
	for w in LIV_WIN:
		holes.append([w.x, w.y, WIN_LO, WIN_HI])
	_wall_x(x0, EAST_X + 0.05, NORTH_Z - 0.05, NORTH_Z + 0.05, holes, wall, p)                                 # north: windows, door
	_wall_z(NORTH_Z - 0.05, FRONT_Z + 0.05, EAST_X - 0.05, EAST_X + 0.05, [[EAST_WIN.x, EAST_WIN.y, WIN_LO, WIN_HI]], wall, p)   # east
	# window frames and mullions
	for w in LIV_WIN:
		_box(Vector3((w.x + w.y) / 2.0, WIN_LO + 0.02, NORTH_Z + 0.07), Vector3(w.y - w.x + 0.1, 0.04, 0.04), trim, p)
		_box(Vector3((w.x + w.y) / 2.0, (WIN_LO + WIN_HI) / 2.0, NORTH_Z), Vector3(0.06, WIN_HI - WIN_LO, 0.06), trim, p)
	_box(Vector3(EAST_X - 0.07, WIN_LO + 0.02, (EAST_WIN.x + EAST_WIN.y) / 2.0), Vector3(0.04, 0.04, EAST_WIN.y - EAST_WIN.x + 0.1), trim, p)
	for k in [1, 2]:
		var mz: float = EAST_WIN.x + (EAST_WIN.y - EAST_WIN.x) * k / 3.0
		_box(Vector3(EAST_X, (WIN_LO + WIN_HI) / 2.0, mz), Vector3(0.06, WIN_HI - WIN_LO, 0.06), trim, p)
	# the sliding glass door, slid open
	_door_frame(p, Vector3((BAL_DOOR.x + BAL_DOOR.y) / 2.0, 0.0, NORTH_Z), 0.0, BAL_DOOR.y - BAL_DOOR.x, BAL_DOOR_TOP, trim)
	var glass := _mat(Color(0.6, 0.7, 0.95), 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.18
	var gw := (BAL_DOOR.y - BAL_DOOR.x) / 2.0
	_box(Vector3(BAL_DOOR.y + gw / 2.0 - 0.1, BAL_DOOR_TOP / 2.0, NORTH_Z + 0.09), Vector3(gw, BAL_DOOR_TOP - 0.04, 0.02), glass, p)
	_box(Vector3(BAL_DOOR.y + gw / 2.0 - 0.1, BAL_DOOR_TOP - 0.02, NORTH_Z + 0.09), Vector3(gw, 0.04, 0.04), trim, p)
	_box(Vector3(BAL_DOOR.y + gw / 2.0 - 0.1, 0.02, NORTH_Z + 0.09), Vector3(gw, 0.04, 0.04), trim, p)
	_box(Vector3(BAL_DOOR.y + 0.03, BAL_DOOR_TOP / 2.0, NORTH_Z + 0.09), Vector3(0.04, BAL_DOOR_TOP, 0.04), trim, p)
	_furnish_living(p)


# the 70" flat screen on the west wall, a couch facing it, a coffee table, an armchair by the east window, a record
# shelf, plants and lamps
const LIV_TV := Vector3(2.68, 1.3, 0.7)      # the screen's centre (on the west wall, facing east)
const LIV_TV_SIZE := Vector2(1.55, 0.87)     # 70 inches across
var liv_tv_mat: ShaderMaterial               # (a copy of the bedroom TV's picture, without the old-TV look)
var liv_tv_on := true
var _liv_glow: OmniLight3D
var _liv_screen: MeshInstance3D
var _liv_led: StandardMaterial3D

func _furnish_living(p: Node3D) -> void:
	var lp := Plat.low_power()
	var wood := _mat(Color(0.30, 0.15, 0.18), 0.6)
	var dark := _mat(Color(0.07, 0.05, 0.09), 0.4)
	var metal := _mat(Color(0.12, 0.10, 0.14), 0.35)
	metal.metallic = 0.6
	# ---- the TV and its stand
	var stand_x := MID_X + 0.05 + 0.22
	_box(Vector3(stand_x, 0.25, LIV_TV.z), Vector3(0.42, 0.5, 1.9), wood, p)                       # media console
	_box(Vector3(stand_x + 0.212, 0.25, LIV_TV.z), Vector3(0.01, 0.4, 1.8), _mat(Color(0.24, 0.11, 0.15), 0.6), p)
	for dz in [-0.47, 0.47]:
		_box(Vector3(stand_x + 0.22, 0.25, LIV_TV.z + dz), Vector3(0.01, 0.005, 0.85), dark, p)    # drawer lines
	_blockers["living"].append(Rect2(MID_X, LIV_TV.z - 1.0, 0.55, 2.0))
	var tv := Node3D.new()
	tv.position = LIV_TV
	tv.rotation.y = PI / 2.0                   # local +z faces east, into the room
	p.add_child(tv)
	_box(Vector3(0, 0, -0.02), Vector3(LIV_TV_SIZE.x + 0.03, LIV_TV_SIZE.y + 0.03, 0.04), dark, tv)   # thin bezel
	var q := QuadMesh.new()
	q.size = LIV_TV_SIZE
	liv_tv_mat = (main.tv_mat as ShaderMaterial).duplicate()
	_liv_screen = MeshInstance3D.new()
	_liv_screen.mesh = q
	_liv_screen.material_override = liv_tv_mat
	_liv_screen.position = Vector3(0, 0, 0.001)
	tv.add_child(_liv_screen)
	# a soft pink light strip behind it (bias lighting)
	var strip := _mat(main.PINK, 0.5, 2.2)
	_box(Vector3(0, LIV_TV_SIZE.y / 2.0 - 0.05, -0.05), Vector3(LIV_TV_SIZE.x - 0.1, 0.012, 0.012), strip, tv)
	_box(Vector3(0, -LIV_TV_SIZE.y / 2.0 + 0.05, -0.05), Vector3(LIV_TV_SIZE.x - 0.1, 0.012, 0.012), strip, tv)
	# a power LED, and a power button on the console
	_liv_led = _mat(Color(0.2, 1.0, 0.4), 0.4, 3.0)
	main._sphere(Vector3(LIV_TV_SIZE.x / 2.0 - 0.03, -LIV_TV_SIZE.y / 2.0 - 0.008, 0.005), 0.005, _liv_led, Vector3.ONE, tv, 8)
	var pw_m := _mat(Color(0.25, 0.22, 0.30), 0.5)
	var pw := _box(Vector3(stand_x + 0.17, 0.505, LIV_TV.z + 0.8), Vector3(0.07, 0.015, 0.05), pw_m, p)
	main.interactables.append({"node": pw, "half": Vector3(0.05, 0.03, 0.04), "guest_ok": true,
		"label": func() -> String: return "BIG TV  [%s]" % ("ON" if liv_tv_on else "OFF"),
		"cb": func() -> void: set_liv_tv(not liv_tv_on),
		"hover": main._glow_hover(pw_m)})
	_label("TV", Vector3(stand_x + 0.178, 0.514, LIV_TV.z + 0.8), PI / 2.0, 24, Color(0.85, 0.8, 0.9), p).rotation.x = -PI / 2.0
	_liv_glow = _light(Vector3(LIV_TV.x + 0.6, 1.25, LIV_TV.z), Color(0.45, 0.6, 1.0), 0.9, 4.0, p)
	# things on the console: a game console under the TV, a little plant, a speaker each side
	_box(Vector3(stand_x, 0.53, LIV_TV.z - 0.35), Vector3(0.28, 0.06, 0.32), _mat(Color(0.9, 0.9, 0.93), 0.4), p)
	main._cyl(Vector3(stand_x, 0.58, LIV_TV.z + 0.45), 0.06, 0.12, _mat(Color(0.85, 0.45, 0.55), 0.7), p)
	main._sphere(Vector3(stand_x, 0.69, LIV_TV.z + 0.45), 0.08, _mat(Color(0.18, 0.45, 0.30), 0.8), Vector3(1, 1.2, 1), p, 10)
	# ---- the couch: three cushions, facing the TV (west)
	var fabric := _mat(Color(0.42, 0.24, 0.55), 0.95)
	var fabric_dk := _mat(Color(0.32, 0.17, 0.43), 0.95)
	var pillow_a := _mat(Color(0.95, 0.55, 0.65), 0.95)
	var pillow_b := _mat(Color(1.0, 0.75, 0.45), 0.95)
	var cx := 6.3
	var cz := LIV_TV.z
	var cl := 2.3                               # length (along z)
	var c := Node3D.new()
	c.position = Vector3(cx, 0, cz)
	c.rotation.y = PI / 2.0                     # local -z faces west (the TV); local +x is along -z... local x runs along the couch
	p.add_child(c)
	_box(Vector3(0, 0.22, 0.05), Vector3(cl, 0.3, 0.9), fabric_dk, c)                     # base
	for i in 3:
		var sx := -cl / 2.0 + 0.2 + (cl - 0.4) * (i + 0.5) / 3.0
		_box(Vector3(sx, 0.44, -0.02), Vector3((cl - 0.4) / 3.0 - 0.02, 0.14, 0.72), fabric, c)        # seat cushions
		_box(Vector3(sx, 0.72, 0.36), Vector3((cl - 0.4) / 3.0 - 0.02, 0.48, 0.2), fabric, c)          # back cushions
		var seat := Node3D.new()
		seat.position = Vector3(sx, 0.0, -0.05)
		c.add_child(seat)
		main.seat_nodes.append(seat)
		main.seat_eye.append(1.12)
		main.seat_swivel.append(false)
	_box(Vector3(0, 0.6, 0.47), Vector3(cl, 0.8, 0.12), fabric_dk, c)                     # back
	for sx2 in [-cl / 2.0 + 0.1, cl / 2.0 - 0.1]:
		_box(Vector3(sx2, 0.5, 0.05), Vector3(0.2, 0.36, 0.9), fabric_dk, c)              # arms
		_box(Vector3(sx2, 0.04, 0.4), Vector3(0.05, 0.08, 0.05), dark, c)                 # feet
		_box(Vector3(sx2, 0.04, -0.3), Vector3(0.05, 0.08, 0.05), dark, c)
	var pl1 := _box(Vector3(-cl / 2.0 + 0.35, 0.68, 0.2), Vector3(0.36, 0.34, 0.12), pillow_a, c)
	pl1.rotation = Vector3(-0.25, 0.3, 0.1)
	var pl2 := _box(Vector3(cl / 2.0 - 0.35, 0.68, 0.2), Vector3(0.36, 0.34, 0.12), pillow_b, c)
	pl2.rotation = Vector3(-0.25, -0.3, -0.1)
	var throw_m := _mat(Color(0.98, 0.85, 0.80), 0.95)
	_box(Vector3(cl / 2.0 - 0.3, 0.98, 0.42), Vector3(0.5, 0.03, 0.3), throw_m, c)        # a blanket over the back
	_blockers["living"].append(Rect2(cx - 0.5, cz - cl / 2.0, 1.0, cl))
	# ---- rug and coffee table
	var rug_m := _mat(Color(0.55, 0.22, 0.45), 0.95)
	_box(Vector3(4.6, 0.006, cz), Vector3(2.6, 0.012, 2.6), rug_m, p)
	_box(Vector3(4.6, 0.007, cz), Vector3(2.3, 0.012, 2.3), _mat(Color(0.45, 0.16, 0.38), 0.95), p)
	var tx := 5.1
	_box(Vector3(tx, 0.4, cz), Vector3(0.6, 0.05, 1.1), wood, p)
	_box(Vector3(tx, 0.12, cz), Vector3(0.5, 0.03, 1.0), wood, p)                           # lower shelf
	for lx in [-0.26, 0.26]:
		for lz in [-0.5, 0.5]:
			_box(Vector3(tx + lx, 0.2, cz + lz), Vector3(0.04, 0.4, 0.04), metal, p)
	_blockers["living"].append(Rect2(tx - 0.35, cz - 0.6, 0.7, 1.2))
	main._cyl(Vector3(tx + 0.1, 0.475, cz - 0.3), 0.045, 0.1, _mat(Color(0.95, 0.9, 0.85), 0.5), p)      # mug
	_box(Vector3(tx - 0.05, 0.435, cz + 0.15), Vector3(0.05, 0.02, 0.17), dark, p)                       # remote
	for k in 3:                                                                                           # magazines
		var mg := _box(Vector3(tx + 0.02, 0.145 + k * 0.012, cz + 0.2), Vector3(0.24, 0.01, 0.32),
			_mat([Color(0.9, 0.5, 0.6), Color(0.4, 0.6, 0.9), Color(0.95, 0.8, 0.4)][k], 0.8), p)
		mg.rotation.y = k * 0.25
	# ---- an armchair by the east window, turned toward the TV
	var ac := Node3D.new()
	ac.position = Vector3(8.4, 0, -0.9)
	ac.rotation.y = PI / 2.0 - 0.45
	p.add_child(ac)
	var chair_m := _mat(Color(0.85, 0.45, 0.30), 0.95)
	var chair_dk := _mat(Color(0.70, 0.35, 0.24), 0.95)
	_box(Vector3(0, 0.24, 0.02), Vector3(0.8, 0.3, 0.8), chair_dk, ac)
	_box(Vector3(0, 0.44, -0.04), Vector3(0.56, 0.12, 0.62), chair_m, ac)
	_box(Vector3(0, 0.7, 0.36), Vector3(0.8, 0.62, 0.14), chair_dk, ac)
	for sx3 in [-0.34, 0.34]:
		_box(Vector3(sx3, 0.5, 0.02), Vector3(0.14, 0.32, 0.8), chair_dk, ac)
	var aseat := Node3D.new()
	aseat.position = Vector3(0, 0, -0.05)
	ac.add_child(aseat)
	main.seat_nodes.append(aseat)
	main.seat_eye.append(1.12)
	main.seat_swivel.append(false)
	_blockers["living"].append(Rect2(7.95, -1.4, 0.95, 1.0))
	# a side table with a lamp beside it
	_box(Vector3(8.75, 0.28, 0.0), Vector3(0.4, 0.56, 0.4), wood, p)
	main._cyl(Vector3(8.75, 0.62, 0.0), 0.05, 0.12, metal, p)
	main._cyl(Vector3(8.75, 0.78, 0.0), 0.13, 0.18, _mat(Color(1.0, 0.75, 0.55), 0.6, 1.4), p)
	_blockers["living"].append(Rect2(8.5, -0.25, 0.5, 0.5))
	# ---- a record shelf against the south wall, with a turntable on top
	var rx := 7.4
	var rz := FRONT_Z - 0.25
	_box(Vector3(rx, 0.45, rz), Vector3(1.5, 0.9, 0.4), wood, p)
	for k in 2:
		_box(Vector3(rx - 0.37 + k * 0.74, 0.45, rz - 0.2), Vector3(0.68, 0.78, 0.01), dark, p)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for k in 22:                                                                              # record sleeves
		var sx4 := rx - 0.68 + k * 0.062
		var col := Color.from_hsv(rng.randf(), 0.5, 0.75)
		var sl := _box(Vector3(sx4, 0.32, rz - 0.06), Vector3(0.012, 0.3, 0.28), _mat(col, 0.8), p)
		sl.rotation.z = rng.randf_range(-0.06, 0.06)
	_box(Vector3(rx - 0.25, 0.94, rz), Vector3(0.45, 0.08, 0.36), dark, p)                    # turntable
	main._cyl(Vector3(rx - 0.28, 0.985, rz), 0.15, 0.01, _mat(Color(0.03, 0.03, 0.04), 0.3), p)
	main._cyl(Vector3(rx - 0.28, 0.99, rz), 0.05, 0.01, _mat(Color(0.95, 0.45, 0.55), 0.6), p)
	_box(Vector3(rx - 0.1, 1.0, rz - 0.08), Vector3(0.02, 0.02, 0.18), metal, p)              # tone arm
	_box(Vector3(rx + 0.4, 1.02, rz), Vector3(0.22, 0.24, 0.2), _mat(Color(0.15, 0.10, 0.18), 0.55), p)   # speaker
	_blockers["living"].append(Rect2(rx - 0.8, rz - 0.3, 1.6, 0.6))
	# ---- plants and the floor lamp in the corners
	var pot := _mat(Color(0.55, 0.25, 0.20), 0.8)
	var leaf := _mat(Color(0.18, 0.45, 0.30), 0.8)
	for pp in [Vector3(9.25, 0, -1.7), Vector3(3.05, 0, 3.05)]:
		main._cyl(pp + Vector3(0, 0.22, 0), 0.2, 0.44, pot, p)
		main._sphere(pp + Vector3(0, 0.75, 0), 0.3, leaf, Vector3(1.0, 1.4, 1.0), p, 10)
		main._sphere(pp + Vector3(0.12, 1.05, 0.05), 0.2, leaf, Vector3(1.0, 1.3, 1.0), p, 10)
		_blockers["living"].append(Rect2(pp.x - 0.3, pp.z - 0.3, 0.6, 0.6))
	var lamp_m := _mat(Color(0.12, 0.08, 0.14), 0.5)
	main._cyl(Vector3(9.2, 0.02, 2.95), 0.16, 0.04, lamp_m, p)
	main._cyl(Vector3(9.2, 0.8, 2.95), 0.015, 1.56, lamp_m, p)
	main._cyl(Vector3(9.2, 1.62, 2.95), 0.2, 0.3, _mat(Color(1.0, 0.75, 0.55), 0.6, 1.4), p)
	_blockers["living"].append(Rect2(8.95, 2.7, 0.5, 0.5))
	# ---- a big print on the south wall, over the records
	var frame_m := _mat(Color(0.10, 0.06, 0.12), 0.5)
	_box(Vector3(7.4, 1.75, FRONT_Z - 0.04), Vector3(1.2, 0.7, 0.03), frame_m, p)
	var art := _mat(Color(0.95, 0.55, 0.45), 0.8, 0.3)
	_box(Vector3(7.4, 1.75, FRONT_Z - 0.058), Vector3(1.1, 0.6, 0.01), art, p)
	main._sphere(Vector3(7.25, 1.82, FRONT_Z - 0.065), 0.16, _mat(Color(1.0, 0.85, 0.45), 0.6, 0.8), Vector3(1, 1, 0.05), p, 16)   # a sun
	_box(Vector3(7.4, 1.58, FRONT_Z - 0.066), Vector3(1.1, 0.26, 0.005), _mat(Color(0.45, 0.20, 0.50), 0.8), p)                     # hills
	# ---- lights
	_light(Vector3(9.1, 1.6, 2.75), main.WARM, 1.0, 5.5, p)
	_light(Vector3(6.0, 2.2, -1.2), main.PINK, 0.7, 5.0, p)          # the city's glow through the glass
	if not lp:                                                        # (the headset gets fewer lights)
		_light(Vector3(8.75, 0.9, 0.05), main.WARM, 0.7, 3.0, p)
		_light(Vector3(5.0, 2.5, 2.4), Color(0.6, 0.3, 0.75), 0.5, 5.0, p)   # soft fill
	# ---- two speakers either side of the TV (they play the TV's sound unless you set them otherwise)
	main._make_speaker("Living room speaker L", Vector3(MID_X + 0.15, 1.3, LIV_TV.z - 1.15), PI / 2.0, 0.0, Vector3(0.18, 0.32, 0.16), 0.055, p)
	main._make_speaker("Living room speaker R", Vector3(MID_X + 0.15, 1.3, LIV_TV.z + 1.15), PI / 2.0, 0.0, Vector3(0.18, 0.32, 0.16), 0.055, p)
	main.bank.set_mode(main.bank.speakers.size() - 2, "tv")
	main.bank.set_mode(main.bank.speakers.size() - 1, "tv")
	if main.pc != null:
		main.pc.refresh_speakers()


func set_liv_tv(on: bool) -> void:
	liv_tv_on = on
	_liv_led.albedo_color = Color(0.2, 1.0, 0.4) if on else Color(0.3, 0.05, 0.05)
	_liv_led.emission = Color(0.2, 1.0, 0.4) if on else Color(0.6, 0.05, 0.05)
	_liv_led.emission_energy_multiplier = 3.0 if on else 0.5


# the big TV shows what the bedroom TV shows (a tape, a game, the news), as a clean flat picture
var _liv_params: Array = []
func _mirror_tv() -> void:
	if liv_tv_mat == null or main.tv_mat == null:
		return
	if _liv_params.is_empty():
		for u in (main.tv_mat.shader as Shader).get_shader_uniform_list():
			var n := str(u["name"])
			if n != "crt_mode" and n != "screen_aspect" and n != "tv_power":
				_liv_params.append(n)
	var src: ShaderMaterial = main.tv_mat
	for n in _liv_params:
		liv_tv_mat.set_shader_parameter(n, src.get_shader_parameter(n))
	liv_tv_mat.set_shader_parameter("crt_mode", 0)
	liv_tv_mat.set_shader_parameter("screen_aspect", LIV_TV_SIZE.x / LIV_TV_SIZE.y)
	var pw = src.get_shader_parameter("tv_power")
	liv_tv_mat.set_shader_parameter("tv_power", float(pw if pw != null else 1.0) if liv_tv_on else 0.0)
	_liv_glow.visible = liv_tv_on and float(pw if pw != null else 1.0) > 0.5


# ---------------------------------------------------------------- the balcony: round the corner, under the balcony above

func _build_balcony() -> void:
	var p := balcony
	var tile := _mat(Color(0.32, 0.22, 0.32), 0.8)
	var rail_m := _mat(Color(0.10, 0.08, 0.13), 0.35)
	rail_m.metallic = 0.6
	var under := _mat(Color(0.22, 0.14, 0.26), 0.9)
	var edge := _mat(Color(0.28, 0.20, 0.30), 0.85)
	var w0 := WEST_X - 0.05
	# floor slab: north strip and east strip
	_box(Vector3((w0 + BAL_E) / 2.0, -0.06, (BAL_N + NORTH_Z) / 2.0), Vector3(BAL_E - w0 + 0.05, 0.12, NORTH_Z - BAL_N), tile, p)
	_box(Vector3((EAST_X + BAL_E) / 2.0, -0.06, (NORTH_Z + FRONT_Z + 0.05) / 2.0), Vector3(BAL_E - EAST_X + 0.05, 0.12, FRONT_Z + 0.05 - NORTH_Z), tile, p)
	_box(Vector3((w0 + BAL_E) / 2.0, -0.2, BAL_N), Vector3(BAL_E - w0 + 0.1, 0.28, 0.1), edge, p)          # slab edges
	_box(Vector3(BAL_E, -0.2, (BAL_N + FRONT_Z) / 2.0), Vector3(0.1, 0.28, FRONT_Z - BAL_N + 0.1), edge, p)
	# railing: posts, a top rail and two thin rails (plain bars)
	var runs := [[Vector3(w0, 0, BAL_N), Vector3(BAL_E, 0, BAL_N)], [Vector3(BAL_E, 0, BAL_N), Vector3(BAL_E, 0, FRONT_Z + 0.05)]]
	for r in runs:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var mid := (a + b) / 2.0
		var along_x := absf(dir.x) > 0.5
		for y in [1.05, 0.62, 0.22]:
			var sz := Vector3(len, 0.05 if y > 1.0 else 0.025, 0.05 if y > 1.0 else 0.025)
			if not along_x:
				sz = Vector3(sz.z, sz.y, len)
			_box(Vector3(mid.x, y, mid.z), sz, rail_m, p)
		var n := int(ceil(len / 1.1))
		for i in n + 1:
			var pp := a + dir * (len * i / n)
			_box(Vector3(pp.x, 0.53, pp.z), Vector3(0.045, 1.06, 0.045), rail_m, p)
	# privacy screens at the two ends
	var screen_m := _mat(Color(0.26, 0.16, 0.30), 0.9)
	_box(Vector3(w0 + 0.03, 1.2, (BAL_N + NORTH_Z) / 2.0), Vector3(0.06, 2.4, NORTH_Z - BAL_N), screen_m, p)
	_box(Vector3((EAST_X + BAL_E) / 2.0, 1.2, FRONT_Z + 0.03), Vector3(BAL_E - EAST_X, 2.4, 0.06), screen_m, p)
	# the outside of the walls, round the windows and the door
	var clad := _mat(Color(0.24, 0.15, 0.29), 0.9)
	var wz := NORTH_Z - 0.06
	var holes: Array = [[main.WIN_X0, main.WIN_X1, main.WIN_Y0, main.WIN_Y1], [BAL_DOOR.x, BAL_DOOR.y, 0.0, BAL_DOOR_TOP]]
	for w in LIV_WIN:
		holes.append([w.x, w.y, WIN_LO, WIN_HI])
	_wall_x(w0, EAST_X + 0.07, wz - 0.01, wz + 0.005, holes, clad, p)
	_wall_z(NORTH_Z - 0.07, FRONT_Z + 0.05, EAST_X + 0.055, EAST_X + 0.07, [[EAST_WIN.x, EAST_WIN.y, WIN_LO, WIN_HI]], clad, p)
	# string lights strung along poles on the railing (nothing overhead: it's the top floor, the sky stays open)
	var bulb := _mat(Color(1.0, 0.78, 0.45), 0.4, 3.0)
	var pole_y := 2.25
	var poles: Array[Vector3] = []
	var nn := 9
	for i in nn + 1:
		poles.append(Vector3(lerpf(w0 + 0.1, BAL_E - 0.03, float(i) / nn), 0.0, BAL_N + 0.03))
	for i in range(1, 5):
		poles.append(Vector3(BAL_E - 0.03, 0.0, lerpf(BAL_N + 0.03, FRONT_Z - 0.1, float(i) / 4.0)))
	for pp in poles:
		_box(Vector3(pp.x, (1.05 + pole_y) / 2.0, pp.z), Vector3(0.03, pole_y - 1.05, 0.03), rail_m, p)
	for i in poles.size() - 1:
		var a: Vector3 = poles[i] + Vector3(0, pole_y, 0)
		var b: Vector3 = poles[i + 1] + Vector3(0, pole_y, 0)
		for k in 5:
			var t := (k + 0.5) / 5.0
			var q := a.lerp(b, t) - Vector3(0, 0.22 * sin(t * PI), 0)
			main._sphere(q, 0.03, bulb, Vector3.ONE, p, 8)
	_light(Vector3(1.0, 2.0, (BAL_N + NORTH_Z) / 2.0), main.WARM, 0.7, 5.5, p)
	_light(Vector3(10.7, 2.0, -3.2), main.WARM, 0.8, 4.5, p)
	if not Plat.low_power():
		_light(Vector3(-2.8, 2.0, (BAL_N + NORTH_Z) / 2.0), main.WARM, 0.5, 4.0, p)
		_light(Vector3(10.7, 2.0, 1.5), main.WARM, 0.5, 4.0, p)
	# a little table and two chairs in the corner, facing the city
	var wood := _mat(Color(0.36, 0.18, 0.20), 0.7)
	var cushion := _mat(Color(0.85, 0.40, 0.55), 0.95)
	var tbl := Vector3(11.1, 0.0, -3.75)          # tucked into the corner so you can still walk round to the east side
	main._cyl(tbl + Vector3(0, 0.72, 0), 0.32, 0.04, wood, p)
	main._cyl(tbl + Vector3(0, 0.36, 0), 0.03, 0.72, rail_m, p)
	main._cyl(tbl + Vector3(0, 0.015, 0), 0.2, 0.03, rail_m, p)
	var mugs := _mat(Color(0.95, 0.9, 0.85), 0.5)
	main._cyl(tbl + Vector3(0.1, 0.79, 0.05), 0.04, 0.1, mugs, p)
	_blockers["balcony"].append(Rect2(tbl.x - 0.4, tbl.z - 0.4, 0.8, 0.8))
	for cs in [[Vector3(10.35, 0.0, -3.85), -PI * 0.25 - 0.35], [Vector3(11.15, 0.0, -2.95), -PI * 0.25 + 0.35]]:
		var cp: Vector3 = cs[0]
		var c := Node3D.new()
		c.position = cp
		c.rotation.y = float(cs[1])               # local -z faces out over the railing, toward the north-east
		p.add_child(c)
		_box(Vector3(0, 0.44, 0), Vector3(0.46, 0.05, 0.46), wood, c)
		_box(Vector3(0, 0.49, 0), Vector3(0.42, 0.05, 0.42), cushion, c)
		_box(Vector3(0, 0.82, 0.21), Vector3(0.46, 0.7, 0.04), wood, c)
		for lx in [-0.2, 0.2]:
			for lz in [-0.2, 0.2]:
				_box(Vector3(lx, 0.21, lz), Vector3(0.035, 0.42, 0.035), rail_m, c)
		main.seat_nodes.append(c)
		main.seat_eye.append(1.18)
		main.seat_swivel.append(false)
		_blockers["balcony"].append(Rect2(cp.x - 0.3, cp.z - 0.3, 0.6, 0.6))
	# plants
	var pot := _mat(Color(0.55, 0.25, 0.20), 0.8)
	var leaf := _mat(Color(0.18, 0.45, 0.30), 0.8)
	for pp2 in [Vector3(-3.5, 0, -2.4), Vector3(4.6, 0, -2.4), Vector3(11.4, 0, 2.9), Vector3(7.4, 0, -2.4)]:
		main._cyl(pp2 + Vector3(0, 0.2, 0), 0.18, 0.4, pot, p)
		main._sphere(pp2 + Vector3(0, 0.62, 0), 0.26, leaf, Vector3(1.0, 1.3, 1.0), p, 10)
		_blockers["balcony"].append(Rect2(pp2.x - 0.3, pp2.z - 0.3, 0.6, 0.6))


# ---------------------------------------------------------------- game room: the CRT corner and the arcade, moved in

func _build_game() -> void:
	var p := game
	var wall := _mat(Color(0.16, 0.10, 0.26))
	var floor_m := _mat(Color(0.10, 0.07, 0.16), 0.9)
	var ceil_m := _mat(Color(0.12, 0.07, 0.18))
	var trim := _mat(Color(0.20, 0.07, 0.22), 0.7)
	var wood := _mat(Color(0.42, 0.17, 0.28), 0.65)
	var panel := _mat(Color(0.34, 0.12, 0.24), 0.65)
	var brass := _mat(Color(0.95, 0.75, 0.50), 0.3, 0.6)
	var x0 := WEST_X
	var z0 := HALL_S + 0.1
	var cx := (x0 + GAME_E) / 2.0
	var cz := (z0 + GAME_S) / 2.0
	_box(Vector3(cx, -0.05, cz), Vector3(GAME_E - x0 + 0.1, 0.1, GAME_S - z0 + 0.1), floor_m, p)
	_box(Vector3(cx, H + 0.05, cz), Vector3(GAME_E - x0 + 0.1, 0.1, GAME_S - z0 + 0.1), ceil_m, p)
	_box(Vector3(x0, H / 2.0, cz), Vector3(0.1, H, GAME_S - z0), wall, p)                                    # west
	_box(Vector3(GAME_E, H / 2.0, cz), Vector3(0.1, H, GAME_S - z0), wall, p)                                # east
	_box(Vector3(cx, H / 2.0, GAME_S), Vector3(GAME_E - x0 + 0.1, H, 0.1), wall, p)                          # south
	_wall_x(x0, GAME_E, z0, z0 + 0.04, [[GAME_DOOR - 0.47, GAME_DOOR + 0.47, 0.0, DOOR_TOP]], wall, p)      # north, its face of it
	# skirting
	_box(Vector3(cx, 0.05, GAME_S - 0.06), Vector3(GAME_E - x0, 0.1, 0.02), trim, p)
	# the door: swings into the game room as you walk up
	_door_frame(hallway, Vector3(GAME_DOOR, 0.0, HALL_S - 0.02), 0.0, 0.94, DOOR_TOP, trim)
	_door_frame(p, Vector3(GAME_DOOR, 0.0, z0 + 0.03), 0.0, 0.94, DOOR_TOP, trim)
	var gd := _door_slab(doors_root, Vector3(GAME_DOOR - 0.47, 0.0, HALL_S + 0.05), 0.0, 0.94, wood, panel, brass)
	_doors.append({"pivot": gd, "at": Vector2(GAME_DOOR, HALL_S + 0.05), "open": 0.0, "sign": -1.0, "links": ["hallway", "game"]})
	var plate := _mat(Color(0.12, 0.05, 0.16), 0.5)
	_box(Vector3(GAME_DOOR, 1.72, HALL_S - 0.005), Vector3(0.42, 0.13, 0.01), plate, doors_root)
	_label("GAME ROOM", Vector3(GAME_DOOR, 1.72, HALL_S - 0.012), PI, 34, Color(0.5, 0.95, 1.0), doors_root)
	# neon over the arcade: INSERT COIN
	var neon := Label3D.new()
	neon.text = "INSERT COIN"
	neon.font_size = 120
	neon.pixel_size = 0.0021
	neon.outline_size = 18
	neon.modulate = Color(1.0, 0.45, 0.85) * 2.2
	neon.outline_modulate = Color(0.55, 0.15, 0.6, 0.8)
	neon.position = Vector3(GAME_E - 0.07, 2.42, 6.45)
	neon.rotation.y = -PI / 2.0
	neon.shaded = false
	p.add_child(neon)
	# LED strips along the tops of the walls, pink and cyan
	var led_p := _mat(main.PINK, 0.5, 2.0)
	var led_c := _mat(Color(0.3, 0.9, 1.0), 0.5, 2.0)
	_box(Vector3(x0 + 0.07, H - 0.06, cz), Vector3(0.03, 0.03, GAME_S - z0 - 0.2), led_c, p)
	_box(Vector3(cx, H - 0.06, GAME_S - 0.07), Vector3(GAME_E - x0 - 0.2, 0.03, 0.03), led_p, p)
	_box(Vector3(GAME_E - 0.07, H - 0.06, cz), Vector3(0.03, 0.03, GAME_S - z0 - 0.2), led_c, p)
	_box(Vector3(cx, H - 0.06, z0 + 0.07), Vector3(GAME_E - x0 - 0.2, 0.03, 0.03), led_p, p)
	# a shelf of game boxes on the north wall (left of the door, as you come in it's behind you)
	var shelf_x := -3.0
	_box(Vector3(shelf_x, 1.55, z0 + 0.15), Vector3(1.3, 0.03, 0.26), wood, p)
	_box(Vector3(shelf_x, 1.05, z0 + 0.15), Vector3(1.3, 0.03, 0.26), wood, p)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for shelf_y in [1.07, 1.57]:
		var bx := shelf_x - 0.6
		while bx < shelf_x + 0.58:
			var bw := rng.randf_range(0.03, 0.05)
			var bh := rng.randf_range(0.17, 0.24)
			var col := Color.from_hsv(rng.randf(), rng.randf_range(0.45, 0.8), rng.randf_range(0.55, 0.9))
			_box(Vector3(bx + bw / 2.0, shelf_y + bh / 2.0, z0 + 0.16), Vector3(bw, bh, 0.17), _mat(col, 0.7), p)
			bx += bw + 0.006
	# a mini fridge with a few sodas on top, by the arcade
	var fridge_m := _mat(Color(0.85, 0.85, 0.9), 0.4)
	_box(Vector3(GAME_E - 0.3, 0.42, 7.6), Vector3(0.48, 0.84, 0.5), fridge_m, p)
	_box(Vector3(GAME_E - 0.555, 0.55, 7.6), Vector3(0.01, 0.4, 0.04), _mat(Color(0.3, 0.3, 0.35), 0.4), p)
	for k in 3:
		main._cyl(Vector3(GAME_E - 0.42 + k * 0.1, 0.9, 7.55 + (k % 2) * 0.08), 0.033, 0.12,
			_mat([Color(0.9, 0.2, 0.25), Color(0.2, 0.6, 0.95), Color(0.95, 0.8, 0.2)][k], 0.3), p)
	_blockers["game"].append(Rect2(GAME_E - 0.6, 7.3, 0.6, 0.6))
	# posters: a retro one on the west wall and one on the east
	for pp in [[Vector3(x0 + 0.06, 1.6, 6.6), PI / 2.0, Color(0.3, 0.75, 0.95)], [Vector3(GAME_E - 0.06, 1.6, 8.75), -PI / 2.0, Color(0.95, 0.5, 0.3)]]:
		var fr := Node3D.new()
		fr.position = pp[0]
		fr.rotation.y = float(pp[1])
		p.add_child(fr)
		_box(Vector3.ZERO, Vector3(0.62, 0.86, 0.02), _mat(Color(0.08, 0.05, 0.1), 0.5), fr)
		_box(Vector3(0, 0, 0.012), Vector3(0.56, 0.8, 0.005), _mat(pp[2], 0.8, 0.25), fr)
		_box(Vector3(0, 0.12, 0.016), Vector3(0.3, 0.3, 0.004), _mat(Color(1.0, 0.95, 0.6), 0.6, 0.6), fr)   # a big pixel sun
		for j in 4:
			_box(Vector3(0, -0.12 - j * 0.05, 0.016), Vector3(0.5 - j * 0.06, 0.012, 0.004), _mat(Color(0.2, 0.08, 0.25), 0.7), fr)
	# lights
	_light(Vector3(-1.6, 2.5, 7.4), Color(0.75, 0.45, 0.95), 0.6, 5.0, p)
	if not Plat.low_power():
		_light(Vector3(GAME_E - 0.5, 2.3, 6.45), Color(1.0, 0.45, 0.85), 0.6, 3.0, p)     # the neon's glow
	# the TV corner and the arcade, carried over from where they were built
	main.game_kit.reparent(p, false)
	main.game_kit.transform = Transform3D(Basis.IDENTITY, GAME_KIT_SHIFT)
	main.arcade_kit.reparent(p, false)
	main.arcade_kit.transform = Transform3D(Basis.IDENTITY, ARCADE_KIT_SHIFT)
	# the TV speakers' sound has to come from where they are now
	for i in main.kit_speakers:
		var sp: Dictionary = main.bank.speakers[i]
		for k in ["player", "tv", "con"]:
			var n: Node3D = sp[k]
			n.position += GAME_KIT_SHIFT


# ---------------------------------------------------------------- the study: the desk and PC, the bookshelf, a reading chair

func _build_study() -> void:
	var p := study
	var wall := _mat(Color(0.24, 0.13, 0.30))
	var floor_m := _mat(Color(0.28, 0.14, 0.14), 0.7)
	var ceil_m := _mat(Color(0.20, 0.10, 0.24))
	var trim := _mat(Color(0.20, 0.07, 0.22), 0.7)
	var wood := _mat(Color(0.42, 0.17, 0.28), 0.65)
	var panel := _mat(Color(0.34, 0.12, 0.24), 0.65)
	var brass := _mat(Color(0.95, 0.75, 0.50), 0.3, 0.6)
	var x0 := GAME_E + 0.05
	var x1 := STUDY_E - 0.05
	var z0 := HALL_S + 0.1
	var z1 := GAME_S - 0.05
	var cx := (x0 + x1) / 2.0
	var cz := (z0 + z1) / 2.0
	_box(Vector3(cx, -0.05, cz), Vector3(x1 - x0, 0.1, z1 - z0), floor_m, p)
	_box(Vector3(cx, H + 0.05, cz), Vector3(x1 - x0, 0.1, z1 - z0), ceil_m, p)
	_box(Vector3(x0 + 0.01, H / 2.0, cz), Vector3(0.02, H, z1 - z0), wall, p)                          # west (the game room behind)
	_box(Vector3(x1 - 0.01, H / 2.0, cz), Vector3(0.02, H, z1 - z0), wall, p)                          # east
	_box(Vector3(cx, H / 2.0, z1 + 0.04), Vector3(x1 - x0, H, 0.1), wall, p)                           # south
	_wall_x(x0, x1, z0, z0 + 0.04, [[STUDY_DOOR - 0.47, STUDY_DOOR + 0.47, 0.0, DOOR_TOP]], wall, p)   # north
	# wood floorboards (long strips, a slightly different shade each)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var bz := z0
	while bz < z1 - 0.01:
		var sh := rng.randf_range(-0.03, 0.03)
		_box(Vector3(cx, 0.001, bz + 0.09), Vector3(x1 - x0, 0.002, 0.17), _mat(Color(0.30 + sh, 0.15 + sh * 0.5, 0.14), 0.7), p)
		bz += 0.18
	# the door
	_door_frame(hallway, Vector3(STUDY_DOOR, 0.0, HALL_S - 0.02), 0.0, 0.94, DOOR_TOP, trim)
	_door_frame(p, Vector3(STUDY_DOOR, 0.0, z0 + 0.03), 0.0, 0.94, DOOR_TOP, trim)
	var sd := _door_slab(doors_root, Vector3(STUDY_DOOR - 0.47, 0.0, HALL_S + 0.05), 0.0, 0.94, wood, panel, brass)
	_doors.append({"pivot": sd, "at": Vector2(STUDY_DOOR, HALL_S + 0.05), "open": 0.0, "sign": -1.0, "links": ["hallway", "study"]})
	var plate := _mat(Color(0.12, 0.05, 0.16), 0.5)
	_box(Vector3(STUDY_DOOR, 1.72, HALL_S - 0.005), Vector3(0.42, 0.13, 0.01), plate, doors_root)
	_label("STUDY", Vector3(STUDY_DOOR, 1.72, HALL_S - 0.012), PI, 34, Color(1.0, 0.85, 0.6), doors_root)
	# a rug, a reading armchair with a lamp and a little table, a cork board over the desk
	var rug := _mat(Color(0.45, 0.20, 0.35), 0.95)
	_box(Vector3(2.9, 0.006, 7.6), Vector3(2.2, 0.012, 1.6), rug, p)
	_box(Vector3(2.9, 0.007, 7.6), Vector3(1.9, 0.012, 1.3), _mat(Color(0.55, 0.28, 0.40), 0.95), p)
	var ac := Node3D.new()
	ac.position = Vector3(3.85, 0.0, 7.0)
	ac.rotation.y = PI / 2.0 + 0.5               # turned toward the bookshelf and the room
	p.add_child(ac)
	var chair_m := _mat(Color(0.35, 0.50, 0.45), 0.95)
	var chair_dk := _mat(Color(0.26, 0.40, 0.36), 0.95)
	_box(Vector3(0, 0.24, 0.02), Vector3(0.8, 0.3, 0.8), chair_dk, ac)
	_box(Vector3(0, 0.44, -0.04), Vector3(0.56, 0.12, 0.62), chair_m, ac)
	_box(Vector3(0, 0.75, 0.36), Vector3(0.8, 0.72, 0.14), chair_dk, ac)
	for sx in [-0.34, 0.34]:
		_box(Vector3(sx, 0.5, 0.02), Vector3(0.14, 0.32, 0.8), chair_dk, ac)
	var seat := Node3D.new()
	seat.position = Vector3(0, 0, -0.05)
	ac.add_child(seat)
	main.seat_nodes.append(seat)
	main.seat_eye.append(1.12)
	main.seat_swivel.append(false)
	_blockers["study"].append(Rect2(3.4, 6.55, 0.95, 0.95))
	_box(Vector3(4.15, 0.28, 7.85), Vector3(0.4, 0.56, 0.4), wood, p)                            # side table
	_blockers["study"].append(Rect2(3.9, 7.6, 0.5, 0.5))
	var stack := [Color(0.85, 0.45, 0.55), Color(0.35, 0.55, 0.62), Color(0.95, 0.75, 0.45)]
	for k in 3:
		var bk := _box(Vector3(4.15, 0.58 + k * 0.035, 7.85), Vector3(0.24 - k * 0.02, 0.03, 0.17), _mat(stack[k], 0.8), p)
		bk.rotation.y = k * 0.3
	var lamp_m := _mat(Color(0.12, 0.08, 0.14), 0.5)
	main._cyl(Vector3(4.2, 0.02, 6.35), 0.15, 0.04, lamp_m, p)
	main._cyl(Vector3(4.2, 0.78, 6.35), 0.014, 1.5, lamp_m, p)
	main._cyl(Vector3(4.2, 1.58, 6.35), 0.19, 0.28, _mat(Color(1.0, 0.75, 0.55), 0.6, 1.3), p)
	_blockers["study"].append(Rect2(4.0, 6.15, 0.4, 0.4))
	var cork := _mat(Color(0.72, 0.52, 0.34), 0.95)
	_box(Vector3(1.45 + 0.0, 1.8, z1 - 0.02), Vector3(1.1, 0.7, 0.03), _mat(Color(0.25, 0.12, 0.10), 0.6), p)
	_box(Vector3(1.45, 1.8, z1 - 0.04), Vector3(1.0, 0.6, 0.01), cork, p)
	var notes := [Color(1.0, 0.9, 0.45), Color(0.6, 0.9, 1.0), Color(1.0, 0.6, 0.7), Color(0.75, 1.0, 0.6)]
	for k in 6:
		var nt := _box(Vector3(1.05 + (k % 3) * 0.32 + rng.randf_range(-0.05, 0.05), 1.92 - (k / 3) * 0.26, z1 - 0.047),
			Vector3(0.14, 0.12, 0.004), _mat(notes[k % 4], 0.8), p)
		nt.rotation.z = rng.randf_range(-0.2, 0.2)
	# a plant in the corner, and the lights
	var pot := _mat(Color(0.55, 0.25, 0.20), 0.8)
	var leaf := _mat(Color(0.18, 0.45, 0.30), 0.8)
	main._cyl(Vector3(4.25, 0.22, 9.95), 0.2, 0.44, pot, p)
	main._sphere(Vector3(4.25, 0.75, 9.95), 0.3, leaf, Vector3(1.0, 1.4, 1.0), p, 10)
	_blockers["study"].append(Rect2(3.95, 9.65, 0.6, 0.6))
	_light(Vector3(4.05, 1.5, 6.5), main.WARM, 0.9, 4.0, p)
	if not Plat.low_power():
		_light(Vector3(2.5, 2.5, 7.8), Color(0.75, 0.45, 0.85), 0.5, 5.0, p)
	# the desk, the PC, the shelf, carried over
	main.study_kit.reparent(p, false)
	main.study_kit.transform = STUDY_KIT_XF
	for i in main.study_speakers:
		var spk: Dictionary = main.bank.speakers[i]
		for k in ["player", "tv", "con"]:
			var n: Node3D = spk[k]
			n.position = STUDY_KIT_XF * n.position


# ---------------------------------------------------------------- the building around us (floors above and below)

func _build_exterior() -> void:
	var p := exterior
	var m: Material = main.city_mat
	var x0 := WEST_X - 0.1
	var x1 := EAST_X + 0.1
	var z0 := NORTH_Z - 0.1
	var z1 := HALL_S + 6.0
	var roof := _mat(Color(0.20, 0.13, 0.24), 0.9)
	_box(Vector3((x0 + x1) / 2.0, H + 0.2, (z0 + z1) / 2.0), Vector3(x1 - x0 + 0.2, 0.3, z1 - z0 + 0.2), roof, p)                   # the roof (top floor)
	_box(Vector3((x0 + x1) / 2.0, H + 0.5, z0 - 0.05), Vector3(x1 - x0 + 0.2, 0.35, 0.12), roof, p)                               # parapet
	_box(Vector3(x1 + 0.05, H + 0.5, (z0 + z1) / 2.0), Vector3(0.12, 0.35, z1 - z0 + 0.2), roof, p)
	_box(Vector3((x0 + x1) / 2.0, (-40.0 - 0.2) / 2.0, (z0 + z1) / 2.0), Vector3(x1 - x0, 40.0 - 0.2, z1 - z0), m, p)          # below
	var slab := _mat(Color(0.28, 0.20, 0.30), 0.85)
	var rail_m := _mat(Color(0.10, 0.08, 0.13), 0.4)
	for fy in [-9.0, -6.0, -3.0]:                             # the neighbours' balconies below
		_box(Vector3((x0 + BAL_E) / 2.0, fy, (BAL_N + NORTH_Z) / 2.0), Vector3(BAL_E - x0, 0.16, NORTH_Z - BAL_N + 0.1), slab, p)
		_box(Vector3((EAST_X + BAL_E) / 2.0, fy, (NORTH_Z + FRONT_Z) / 2.0), Vector3(BAL_E - EAST_X, 0.16, FRONT_Z - NORTH_Z), slab, p)
		_box(Vector3((x0 + BAL_E) / 2.0, fy + 1.05, BAL_N), Vector3(BAL_E - x0, 0.05, 0.05), rail_m, p)
		_box(Vector3(BAL_E, fy + 1.05, (BAL_N + FRONT_Z) / 2.0), Vector3(0.05, 0.05, FRONT_Z - BAL_N), rail_m, p)
	_box(Vector3((x0 + BAL_E) / 2.0, -0.2 - 0.2, (BAL_N + NORTH_Z) / 2.0), Vector3(BAL_E - x0, 0.2, NORTH_Z - BAL_N), slab, p)   # under ours
	# the street, far below
	var street := _mat(Color(0.06, 0.04, 0.08), 0.9)
	_box(Vector3(2.0, -30.0, -20.0), Vector3(160.0, 0.2, 160.0), street, p)
	var lamp := _mat(Color(1.0, 0.7, 0.4), 0.4, 3.0)
	for i in 12:
		main._sphere(Vector3(-22.0 + i * 4.5, -26.5, -9.0), 0.25, lamp, Vector3.ONE, p, 8)
	for i in 8:
		main._sphere(Vector3(16.0, -26.5, -6.0 + i * 4.5), 0.25, lamp, Vector3.ONE, p, 8)


# ---------------------------------------------------------------- where am I, what can I walk on

func room_at(x: float, z: float) -> String:
	if z >= NORTH_Z and z <= FRONT_Z and x >= WEST_X and x <= MID_X:
		return "bedroom"
	if z > FRONT_Z and z <= HALL_S and x >= WEST_X and x <= EAST_X:
		return "hallway"
	if z >= NORTH_Z and z <= FRONT_Z and x > MID_X and x <= EAST_X:
		return "living"
	if z > HALL_S and z <= GAME_S and x >= WEST_X and x <= GAME_E:
		return "game"
	if z > HALL_S and z <= GAME_S and x > GAME_E and x <= STUDY_E:
		return "study"
	if (z < NORTH_Z and z >= BAL_N - 0.2 and x >= WEST_X - 0.1 and x <= BAL_E + 0.2) \
			or (x > EAST_X and x <= BAL_E + 0.2 and z >= BAL_N - 0.2 and z <= FRONT_Z + 0.1):
		return "balcony"
	return ""


# outside the bedroom: may I stand here?
func walkable(x: float, z: float) -> bool:
	var pt := Vector2(x, z)
	var ok := false
	for r in [HALL_WALK, LIV_WALK, BAL_WALK_N, BAL_WALK_E, GAME_WALK, STUDY_WALK]:
		if (r as Rect2).has_point(pt):
			ok = true
			break
	if not ok:
		for r in DOORWAYS:
			if (r as Rect2).has_point(pt):
				return true
		return false
	var id := room_at(x, z)
	for b in _blockers.get(id, []):
		if (b as Rect2).has_point(pt):
			return false
	return true


# any space at all (for walking out of something you ended up inside)
func in_bounds(x: float, z: float) -> bool:
	var pt := Vector2(x, z)
	for r in [HALL_WALK, LIV_WALK, BAL_WALK_N, BAL_WALK_E, GAME_WALK, STUDY_WALK]:
		if (r as Rect2).has_point(pt):
			return true
	for r in DOORWAYS:
		if (r as Rect2).has_point(pt):
			return true
	return false


# the node to hang something on that stands at (x, z) (the bedroom if it's nowhere in particular)
func room_node_at(x: float, z: float) -> Node3D:
	return rooms.get(room_at(x, z), main.room)


# the room a node belongs to ("" = not in any: avatars, the hands...)
func room_of_node(n: Node) -> String:
	var key := n.get_instance_id()
	if _room_of.has(key):
		return _room_of[key]
	var id := ""
	var a := n
	while a != null:
		for rid in rooms:
			if rooms[rid] == a:
				id = rid
				break
		if id != "" or a == main:
			break
		a = a.get_parent()
	_room_of[key] = id
	return id


# the pointer only reaches things in the room I'm in
func can_reach(n: Node) -> bool:
	var id := room_of_node(n)
	return id == "" or id == current


# ---------------------------------------------------------------- per frame: doors, what's drawn

func _process(delta: float) -> void:
	if main == null or main.head == null:
		return
	var me: Vector3 = main.head.global_position
	var here := room_at(me.x, me.z)
	if here != "" and not _in_doorway(me.x, me.z):
		current = here
	elif here != "" and current == "":
		current = here
	# doors open for anybody walking up to them
	var people: Array = [Vector2(me.x, me.z)]
	if main.net_avatars != null:
		for a in main.net_avatars.avatars.values():
			if a.visible and a.head != null:
				var hp: Vector3 = a.head.global_position
				people.append(Vector2(hp.x, hp.z))
	for d in _doors:
		var near := false
		for pp in people:
			if (pp as Vector2).distance_to(d["at"]) < 1.3:
				near = true
				break
		var target := 1.0 if near else 0.0
		var o: float = move_toward(float(d["open"]), target, delta / 0.6)
		d["open"] = o
		(d["pivot"] as Node3D).rotation.y = float(d["sign"]) * 1.65 * smoothstep(0.0, 1.0, o)
	# what's drawn: the room I'm in, what it looks out on, and rooms behind an open door
	var seen := {current: true}
	for s in SEES.get(current, []):
		seen[s] = true
	for d in _doors:
		if float(d["open"]) > 0.02:
			var links: Array = d["links"]
			if current in links:
				for l in links:
					seen[l] = true
	if living.visible:
		_mirror_tv()
	if seen != _seen:
		_seen = seen
		for rid in rooms:
			(rooms[rid] as Node3D).visible = seen.has(rid)
	# friends in rooms I can't see aren't drawn either
	if main.net_avatars != null:
		for a in main.net_avatars.avatars.values():
			if a.head == null:
				continue
			var hp2: Vector3 = a.head.global_position
			var ar := room_at(hp2.x, hp2.z)
			var show := ar == "" or seen.has(ar)
			for part in [a.head, a.lh, a.rh, a.tag]:
				if part != null:
					part.visible = show


func _in_doorway(x: float, z: float) -> bool:
	for r in DOORWAYS:
		if (r as Rect2).has_point(Vector2(x, z)):
			return true
	return false


func on_balcony() -> bool:
	return current == "balcony"
