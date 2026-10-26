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
const LOCKED := []                          # hallway south wall: x, name (rooms still being done up)
const TH_DOOR := 7.0
const TH_X0 := 4.6                           # theater: west and east wall lines, south wall line
const TH_X1 := 9.65
const TH_S := 12.35
const TH_WALK := Rect2(4.9, 5.68, 4.5, 6.37)
const TH_MID := -0.45                        # (each row a good step lower than the one behind: heads clear the seats in front)
const TH_LOW := -0.9                        # the front of the theater is sunk below the hallway: the rows step down
const TH_ROWS := [[7.8, 0.0, [5.65, 6.45, 7.25, 8.05]], [9.0, TH_MID, [6.05, 6.85, 7.65, 8.45]], [10.2, TH_LOW, [5.65, 6.45, 7.25, 8.05]]]   # z, floor, seat x's (staggered)
const TH_SCREEN := Vector2(4.0, 2.25)
const STUDY_DOOR := 2.4
const STUDY_E := 4.6                         # study east wall line
const STUDY_WALK := Rect2(0.72, 5.68, 3.56, 4.37)
# the desk and the bookshelf were built in the bedroom's back-right corner; turned round, that corner is the study's
# front-left: the desk against the study's south wall, the bookshelf against its west wall
const SECRET := Vector2(3.4, 4.3)            # x span of the bookcase door in the study's south wall
const NOIR_WALK := Rect2(0.75, 10.65, 3.5, 2.7)
const NOIR_Z1 := 14.2
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
	Rect2(GAME_DOOR - 0.35, 4.95, 0.7, 0.85), Rect2(STUDY_DOOR - 0.35, 4.95, 0.7, 0.85), Rect2(TH_DOOR - 0.35, 4.95, 0.7, 0.85)]

var main: Node3D
var _bal_leaves: Array[Node3D] = []
var _bal_closed := false
var bal_shut := 0.0                    # 0 open .. 1 the balcony door closed
var _bal_gw := 0.9
var hallway: Node3D
var living: Node3D
var balcony: Node3D
var game: Node3D
var study: Node3D
var noir_room: Node3D
var theater: Node3D
var secret_until := 0                       # ms: the bookcase stays open until then (after the red book is pulled)
var _secret: Dictionary = {}
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
	"noir": [],
	"theater": [],
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
	noir_room = _root("NoirOffice")
	theater = _root("Theater")
	exterior = _root("Exterior")
	doors_root = _root("Doors")             # seen from both sides, so always drawn
	for id in ["hallway", "living", "balcony", "game", "study", "noir", "theater"]:
		_blockers[id] = []
	rooms["hallway"] = hallway
	rooms["living"] = living
	rooms["balcony"] = balcony
	rooms["game"] = game
	rooms["study"] = study
	rooms["noir"] = noir_room
	rooms["theater"] = theater
	_build_hallway()
	_build_living()
	_build_balcony()
	_build_game()
	_build_study()
	_build_noir_office()
	_build_theater()
	_build_exterior()
	_place_toys()
	main.bank.lp_finished.connect(_lp_next)
	# (deferred: the kits' speakers have to be in their rooms first)
	main.bank.assign_rooms.call_deferred(func(pos: Vector3) -> String: return room_at(pos.x, pos.z))


# the monster figures, spread round the apartment: Banira on the living room's TV console, King Gaboon on a little
# shelf in the game room by the door (play with both within 10 seconds and they fight), and Jogari, just for show,
# on top of the study's bookshelf where the other two used to stand
func _place_toys() -> void:
	if main.kaiju != null:
		main.kaiju.place_toy(living, Vector3(MID_X + 0.27, 0.5, LIV_TV.z - 0.75), 0.25)
	if main.gaboon != null:
		var wood := _mat(Color(0.30, 0.15, 0.18), 0.6)
		var gz := HALL_S + 0.1
		_box(Vector3(-0.6, 1.3, gz + 0.13), Vector3(0.42, 0.03, 0.26), wood, game)            # a little wall shelf
		for bx in [-0.75, -0.45]:
			_box(Vector3(bx, 1.22, gz + 0.06), Vector3(0.02, 0.14, 0.1), wood, game)            # its brackets
		main.gaboon.place_toy(game, Vector3(-0.6, 1.315, gz + 0.11), -PI / 2.0 + 0.3)
	# Jogari
	var jt: Node3D = load("res://black_kaiju_model.gd").build()
	var jpos := Vector3(2.32, 2.215, 0.55)
	jt.scale = Vector3.ONE * 0.2
	jt.position = jpos + Vector3(0, 0.01, 0)
	jt.rotation.y = PI + 0.3
	main.study_kit.add_child(jt)
	main._cyl(jpos + Vector3(0, 0.005, 0), 0.06, 0.01, _mat(Color(0.08, 0.07, 0.1), 0.4), main.study_kit)
	load("res://toy_card.gd").place(main.study_kit, jpos, PI + 0.3, "JOGARI", 0.08)
	var jh := Node3D.new()
	jh.position = jpos + Vector3(0, 0.08, 0)
	main.study_kit.add_child(jh)
	main.interactables.append({"node": jh, "half": Vector3(0.08, 0.09, 0.08), "guest_ok": true,
		"label": func() -> String: return "JOGARI", "cb": func() -> void:
			var tw := jt.create_tween()                  # a little wobble
			tw.tween_property(jt, "rotation:z", 0.2, 0.1)
			tw.tween_property(jt, "rotation:z", -0.2, 0.15)
			tw.tween_property(jt, "rotation:z", 0.0, 0.1)})


# t: 0 open (both leaves stacked to the right of the doorway) .. 1 closed (meeting across it)
func _bal_place(t: float) -> void:
	var e := t * t * (3.0 - 2.0 * t)
	for k in _bal_leaves.size():
		var open_x := BAL_DOOR.y + _bal_gw / 2.0 - 0.1
		var shut_x := BAL_DOOR.x + _bal_gw / 2.0 - 0.02 + k * (_bal_gw - 0.04)
		_bal_leaves[k].position = Vector3(lerpf(open_x, shut_x, e), 0.0, NORTH_Z + 0.07 + k * 0.05)


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
	_box(Vector3(width / 2.0, 1.06, 0.0), Vector3(width + 0.05, 2.12, 0.04), wood, pivot)     # (a little bigger than the hole: no gaps)
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
	_wall_x(x0, x1, HALL_S, HALL_S + 0.1, [[GAME_DOOR - 0.47, GAME_DOOR + 0.47, 0.0, DOOR_TOP], [STUDY_DOOR - 0.47, STUDY_DOOR + 0.47, 0.0, DOOR_TOP],
		[TH_DOOR - 0.47, TH_DOOR + 0.47, 0.0, DOOR_TOP]], wall, p)   # south: game room, study, theater
	_box(Vector3(WEST_X, H / 2.0, zc), Vector3(0.1, H, zl + 0.1), wall, p)                               # west (front door)
	_box(Vector3(EAST_X, H / 2.0, zc), Vector3(0.1, H, zl + 0.1), wall, p)                               # east end
	# baseboards
	_box(Vector3((x0 + x1) / 2.0, 0.05, HALL_S - 0.01), Vector3(x1 - x0, 0.1, 0.02), trim, p)
	# a runner down the middle
	_box(Vector3(2.6, 0.006, zc), Vector3(11.5, 0.012, 0.9), _mat(Color(0.55, 0.18, 0.36), 0.95), p)
	_box(Vector3(2.6, 0.007, zc), Vector3(11.2, 0.012, 0.7), _mat(Color(0.40, 0.12, 0.30), 0.95), p)
	# a speaker up on the wall between the study and theater doors, for music down the hallway
	main._make_speaker("Hallway speaker", Vector3(4.7, 2.2, HALL_S - 0.09), PI, 0.25, Vector3(0.18, 0.28, 0.16), 0.055, p)

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
	# two sliding glass leaves on their own tracks: open, they stack beside the doorway; closed, they meet across it
	# (and the weather and the street go quiet, like drawing the bedroom curtains)
	var gw := (BAL_DOOR.y - BAL_DOOR.x) / 2.0 + 0.04
	_box(Vector3((BAL_DOOR.x + BAL_DOOR.y) / 2.0 + 0.5, BAL_DOOR_TOP + 0.02, NORTH_Z + 0.11), Vector3(BAL_DOOR.y - BAL_DOOR.x + 1.2, 0.03, 0.1), trim, p)   # track
	for k in 2:
		var leaf := Node3D.new()
		p.add_child(leaf)
		_box(Vector3(0, BAL_DOOR_TOP / 2.0, 0), Vector3(gw, BAL_DOOR_TOP - 0.04, 0.02), glass, leaf)
		_box(Vector3(0, BAL_DOOR_TOP - 0.02, 0), Vector3(gw, 0.04, 0.04), trim, leaf)
		_box(Vector3(0, 0.02, 0), Vector3(gw, 0.04, 0.04), trim, leaf)
		for sx in [-1.0, 1.0]:
			_box(Vector3(sx * (gw / 2.0 - 0.02), BAL_DOOR_TOP / 2.0, 0), Vector3(0.04, BAL_DOOR_TOP, 0.04), trim, leaf)
		var handle := _box(Vector3(-gw / 2.0 + 0.08, 1.0, 0.035), Vector3(0.025, 0.25, 0.025), _mat(Color(0.75, 0.7, 0.6), 0.3, 0.0), leaf)
		_bal_leaves.append(leaf)
		main.interactables.append({"node": handle, "half": Vector3(0.08, 0.2, 0.08), "group": "lights",
			"label": func() -> String: return "OPEN THE BALCONY DOOR" if _bal_closed else "CLOSE THE BALCONY DOOR",
			"cb": func() -> void:
				_bal_closed = not _bal_closed
				main.shade_sync("bdoor", _bal_closed)})
	_bal_gw = gw
	_bal_place(0.0)
	_furnish_living(p)


# the 70" flat screen on the west wall, a couch facing it, a coffee table, an armchair by the east window, a record
# shelf, plants and lamps
const LIV_TV := Vector3(2.68, 1.6, 0.7)      # the screen's centre (on the west wall, facing east)
const LIV_TV_SIZE := Vector2(2.86, 1.61)     # a big one: about 130 inches across
const RoomTV := preload("res://room_tv.gd")
var liv_tv: Node3D                           # room_tv.gd: its own player, or the game room TV's picture
var th_tv: Node3D
var th_dark := false                         # the theater's house lights are off (in a shared room: the host's)
var _th_lights: Array = []                   # [OmniLight3D, energy]
var _th_glow: Array = []                     # [material, glow]
var _th_rocker: MeshInstance3D
var _liv_glow: OmniLight3D
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
	# the screen and its own player (a VCR on the console, below it)
	liv_tv = RoomTV.new()
	liv_tv.build(main, p, "TV_living", Transform3D(Basis(Vector3.UP, PI / 2.0), LIV_TV), LIV_TV_SIZE,
		Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(stand_x, 0.5, LIV_TV.z - 0.2)))
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
		"label": func() -> String: return "BIG TV  [%s]" % ("ON" if liv_tv.is_on() else "OFF"),
		"cb": func() -> void:
			if main._is_guest():
				main.net_room_tvs.request_power(0)          # the host's Big TV: the host switches it
			else:
				set_liv_tv(not liv_tv.is_on()),
		"hover": main._glow_hover(pw_m)})
	_label("TV", Vector3(stand_x + 0.178, 0.514, LIV_TV.z + 0.8), PI / 2.0, 24, Color(0.85, 0.8, 0.9), p).rotation.x = -PI / 2.0
	_liv_glow = _light(Vector3(LIV_TV.x + 0.8, LIV_TV.y - 0.2, LIV_TV.z), Color(0.45, 0.6, 1.0), 1.1, 5.0, p)
	liv_tv.add_glow(_liv_glow)
	# a little plant on the console beside the player
	main._cyl(Vector3(stand_x, 0.58, LIV_TV.z + 0.5), 0.06, 0.12, _mat(Color(0.85, 0.45, 0.55), 0.7), p)
	main._sphere(Vector3(stand_x, 0.69, LIV_TV.z + 0.5), 0.08, _mat(Color(0.18, 0.45, 0.30), 0.8), Vector3(1, 1.2, 1), p, 10)
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
	# the record player: point at it to put on the next record from the music folder (its own music, separate from the
	# PC, out of the speakers set to it); the platter turns while a record plays, STOP on the front stops it
	var tt_m := _mat(Color(0.12, 0.08, 0.14), 0.4)
	var tt := _box(Vector3(rx - 0.25, 0.94, rz), Vector3(0.45, 0.08, 0.36), tt_m, p)                    # turntable
	_lp_platter = Node3D.new()
	_lp_platter.position = Vector3(rx - 0.28, 0.985, rz)
	p.add_child(_lp_platter)
	main._cyl(Vector3.ZERO, 0.15, 0.01, _mat(Color(0.03, 0.03, 0.04), 0.3), _lp_platter)
	main._cyl(Vector3(0, 0.005, 0), 0.05, 0.01, _mat(Color(0.95, 0.45, 0.55), 0.6), _lp_platter)
	main._box(Vector3(0.03, 0.011, 0.0), Vector3(0.03, 0.002, 0.008), _mat(Color(1.0, 0.9, 0.8), 0.6), _lp_platter)   # a mark on the label, so you see it turn
	_lp_arm = Node3D.new()
	_lp_arm.position = Vector3(rx - 0.08, 1.0, rz + 0.12)
	p.add_child(_lp_arm)
	_box(Vector3(0, 0, -0.1), Vector3(0.02, 0.02, 0.2), metal, _lp_arm)                         # tone arm (pivots at the back corner)
	main.interactables.append({"node": tt, "half": Vector3(0.24, 0.07, 0.2), "guest_ok": true,
		"label": func() -> String:
			if _lp_spinning():
				return "NEXT RECORD  (now: %s)" % _lp_title.left(30)
			return "PUT ON A RECORD",
		"cb": lp_press, "hover": main._glow_hover(tt_m)})
	main.interactables.append({"node": _lp_arm, "half": Vector3(0.04, 0.04, 0.12), "guest_ok": true,
		"when": _lp_spinning, "label": func() -> String: return "LIFT THE NEEDLE  (stop the record)", "cb": lp_lift})
	var stop_m := _mat(Color(0.75, 0.12, 0.12), 0.5)                                            # a STOP button on the front
	var stop_b := _box(Vector3(rx - 0.03, 0.94, rz - 0.185), Vector3(0.06, 0.035, 0.015), stop_m, p)
	var stop_l := Label3D.new()
	stop_l.text = "STOP"
	stop_l.font_size = 24
	stop_l.pixel_size = 0.0006
	stop_l.position = Vector3(rx - 0.03, 0.94, rz - 0.194)
	stop_l.rotation.y = PI
	stop_l.modulate = Color(1, 0.95, 0.9)
	p.add_child(stop_l)
	main.interactables.append({"node": stop_b, "half": Vector3(0.05, 0.035, 0.03), "guest_ok": true,
		"label": func() -> String: return "STOP THE RECORD" if _lp_spinning() else "RECORD PLAYER  (stopped)",
		"cb": lp_lift, "hover": main._glow_hover(stop_m)})
	main._make_speaker("Record player speaker", Vector3(rx + 0.4, 1.02, rz), PI, 0.0, Vector3(0.22, 0.24, 0.2), 0.06, p)
	main.bank.set_mode(main.bank.speakers.size() - 1, "lp")
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
	main._make_speaker("Living room speaker L", Vector3(MID_X + 0.15, 1.45, LIV_TV.z - LIV_TV_SIZE.x / 2.0 - 0.38), PI / 2.0, 0.0, Vector3(0.18, 0.32, 0.16), 0.055, p)
	main._make_speaker("Living room speaker R", Vector3(MID_X + 0.15, 1.45, LIV_TV.z + LIV_TV_SIZE.x / 2.0 + 0.38), PI / 2.0, 0.0, Vector3(0.18, 0.32, 0.16), 0.055, p)
	main.bank.set_mode(main.bank.speakers.size() - 2, "tv")
	main.bank.set_mode(main.bank.speakers.size() - 1, "tv")
	liv_tv.speakers = [main.bank.speakers.size() - 2, main.bank.speakers.size() - 1] as Array[int]
	if main.pc != null:
		main.pc.refresh_speakers()


var _lp_platter: Node3D
var _lp_arm: Node3D

func _lp_spinning() -> bool:
	return main.bank != null and main.bank.lp_playing()


# the record player is its own music, separate from the PC: it goes through the songs in the music folder, one
# after another, out of the speakers set to it. (Everyone's copy plays their own; it isn't shared with friends.)
var _lp_files: Array[String] = []
var _lp_i := -1
var _lp_title := ""


func lp_press() -> void:
	_lp_next()


func _lp_next() -> void:
	var dir: String = main.pc.default_music_dir()
	var found: Array[String] = []
	var da := DirAccess.open(dir)
	if da != null:
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			if not da.current_is_dir() and main.pc.AUDIO_EXTS.has(f.get_extension().to_lower()):
				found.append(dir.path_join(f))
			f = da.get_next()
		da.list_dir_end()
	if found.is_empty():
		main.updater.show_toast("No records: put some songs in the music folder.", 4.0)
		return
	found.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	if found != _lp_files:
		_lp_files = found
		_lp_i = -1
	for tries in _lp_files.size():
		_lp_i = (_lp_i + 1) % _lp_files.size()
		var st: AudioStream = main.pc._load_audio(_lp_files[_lp_i])
		if st != null:
			_lp_title = _lp_files[_lp_i].get_file().get_basename()
			main.bank.lp_play(st)
			return


func lp_lift() -> void:
	main.bank.lp_stop()


func _lp_tick(delta: float) -> void:
	if _lp_platter == null:
		return
	var on := _lp_spinning()
	if on:
		_lp_platter.rotation.y -= delta * TAU * 33.3 / 60.0
	_lp_arm.rotation.y = lerp_angle(_lp_arm.rotation.y, 0.45 if on else 0.0, minf(1.0, delta * 3.0))


func set_liv_tv(on: bool) -> void:
	liv_tv.set_power(on)
	_liv_led.albedo_color = Color(0.2, 1.0, 0.4) if on else Color(0.3, 0.05, 0.05)
	_liv_led.emission = Color(0.2, 1.0, 0.4) if on else Color(0.6, 0.05, 0.05)
	_liv_led.emission_energy_multiplier = 3.0 if on else 0.5


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
	# speakers up under the eaves, over the windows, tipped down at the balcony
	var bs := Vector3(0.18, 0.2, 0.14)
	var bk := 0
	for bx in [-1.6, 3.85, 8.2]:
		bk += 1
		main._make_speaker("Balcony speaker %d" % bk, Vector3(bx, 2.66, wz - 0.09), PI, 0.35, bs, 0.045, p)
	main._make_speaker("Balcony speaker 4", Vector3(EAST_X + 0.15, 2.66, 0.6), PI / 2.0, 0.35, bs, 0.045, p)
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
	_box(Vector3(GAME_DOOR, 2.38, HALL_S - 0.005), Vector3(0.42, 0.13, 0.01), plate, hallway)
	_label("GAME ROOM", Vector3(GAME_DOOR, 2.38, HALL_S - 0.012), PI, 34, Color(0.5, 0.95, 1.0), hallway)
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
	_wall_x(x0, x1, z1 - 0.01, z1 + 0.09, [[SECRET.x, SECRET.y, 0.0, DOOR_TOP]], wall, p)                # south (behind the bookcase: a way through)
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
	_box(Vector3(STUDY_DOOR, 2.38, HALL_S - 0.005), Vector3(0.42, 0.13, 0.01), plate, hallway)
	_label("STUDY", Vector3(STUDY_DOOR, 2.38, HALL_S - 0.012), PI, 34, Color(1.0, 0.85, 0.6), hallway)
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
	main._cyl(Vector3(0.85, 0.22, 5.95), 0.2, 0.44, pot, p)
	main._sphere(Vector3(0.85, 0.75, 5.95), 0.3, leaf, Vector3(1.0, 1.4, 1.0), p, 10)
	_blockers["study"].append(Rect2(0.55, 5.65, 0.6, 0.6))
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


# ---------------------------------------------------------------- the noir office, behind the bookcase by the study desk

func _build_noir_office() -> void:
	var p := noir_room
	var wall := _mat(Color(0.20, 0.17, 0.16), 0.9)
	var wainscot := _mat(Color(0.22, 0.13, 0.10), 0.6)
	var floor_m := _mat(Color(0.16, 0.10, 0.08), 0.7)
	var ceil_m := _mat(Color(0.12, 0.11, 0.11))
	var x0 := 0.45
	var x1 := STUDY_E - 0.05
	var z0 := GAME_S + 0.05
	var z1 := NOIR_Z1
	var cx := (x0 + x1) / 2.0
	var cz := (z0 + z1) / 2.0
	_box(Vector3(cx, -0.05, cz), Vector3(x1 - x0 + 0.1, 0.1, z1 - z0 + 0.1), floor_m, p)
	_box(Vector3(cx, H + 0.05, cz), Vector3(x1 - x0 + 0.1, 0.1, z1 - z0 + 0.1), ceil_m, p)
	_box(Vector3(x0, H / 2.0, cz), Vector3(0.1, H, z1 - z0), wall, p)
	_box(Vector3(x1, H / 2.0, cz), Vector3(0.1, H, z1 - z0), wall, p)
	_wall_x(x0, x1, z1, z1 + 0.1, [[1.5, 3.3, 1.0, 2.4]], wall, p)                                        # south: the window
	_wall_x(x0, x1, z0, z0 + 0.04, [[SECRET.x, SECRET.y, 0.0, DOOR_TOP]], wall, p)                         # north: the way in
	# dark wood panelling up to the waist, and a picture rail
	for side in [[Vector3(x0 + 0.06, 0.5, cz), Vector3(0.02, 1.0, z1 - z0)], [Vector3(x1 - 0.06, 0.5, cz), Vector3(0.02, 1.0, z1 - z0)]]:
		_box(side[0], side[1], wainscot, p)
	_box(Vector3(cx, 1.0, z1 - 0.01), Vector3(x1 - x0, 0.03, 0.03), wainscot, p)
	# the floorboards
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var bz := z0
	while bz < z1 - 0.01:
		var sh := rng.randf_range(-0.02, 0.02)
		_box(Vector3(cx, 0.001, bz + 0.07), Vector3(x1 - x0, 0.002, 0.13), _mat(Color(0.17 + sh, 0.10 + sh * 0.5, 0.08), 0.7), p)
		bz += 0.14
	# the office's things (noir.gd built them; they live in here)
	if main.noir != null:
		main.noir.office.reparent(p, false)
		main.noir.office.transform = Transform3D.IDENTITY
		_blockers["noir"].append(Rect2(1.55, 12.15, 1.7, 0.95))     # desk
		_blockers["noir"].append(Rect2(0.5, 10.5, 0.65, 0.75))      # filing cabinet
		_blockers["noir"].append(Rect2(2.1, 11.1, 0.9, 0.95))       # the visitor's chair
		_blockers["noir"].append(Rect2(3.95, 13.6, 0.5, 0.6))       # coat rack
	# the bookcase door, on the study side
	var wood := _mat(Color(0.30, 0.12, 0.20), 0.7)
	var hinge := Vector3(SECRET.x, 0.0, GAME_S - 0.05)
	var frame := Node3D.new()
	frame.position = hinge
	doors_root.add_child(frame)
	var pivot := Node3D.new()
	frame.add_child(pivot)
	var w := SECRET.y - SECRET.x
	_box(Vector3(w / 2.0, 1.05, -0.15), Vector3(w, 2.1, 0.3), wood, pivot)
	var book_cols := [Color(0.85, 0.45, 0.55), Color(0.35, 0.55, 0.62), Color(0.75, 0.65, 0.50), Color(0.55, 0.30, 0.65), Color(0.25, 0.25, 0.45)]
	for k in 4:
		var sy := 0.25 + k * 0.48
		_box(Vector3(w / 2.0, sy - 0.015, -0.3), Vector3(w - 0.06, 0.03, 0.02), _mat(Color(0.22, 0.08, 0.15), 0.7), pivot)
		var bx := 0.06
		while bx < w - 0.08:
			var bw := rng.randf_range(0.03, 0.06)
			var bh := rng.randf_range(0.26, 0.38)
			_box(Vector3(bx + bw / 2.0, sy + bh / 2.0, -0.31), Vector3(bw, bh, 0.02), _mat(book_cols[rng.randi() % book_cols.size()], 0.8), pivot)
			bx += bw + 0.004
	# the red book: sticks out a little once the office has been found
	var red_m := _mat(Color(0.75, 0.08, 0.10), 0.6)
	var red := _box(Vector3(w * 0.62, 1.21 + 0.17, -0.33), Vector3(0.045, 0.34, 0.06), red_m, pivot)
	_secret = {"pivot": pivot, "open": 0.0, "red": red}
	main.interactables.append({"node": red, "half": Vector3(0.05, 0.18, 0.05), "guest_ok": true,
		"when": func() -> bool: return main.noir != null and main.noir.found,
		"label": func() -> String: return "THE BOOKCASE IS OPEN" if float(_secret["open"]) > 0.5 else "PULL THE RED BOOK",
		"cb": func() -> void: secret_pull(true),
		"hover": main._glow_hover(red_m)})
	# lights: the desk lamp is noir.gd's; a dim one so the corners aren't black
	if not Plat.low_power():
		_light(Vector3(2.5, 2.4, 11.2), Color(0.6, 0.55, 0.5), 0.25, 3.5, p)


# the red book was pulled (here, or by someone else in the room)
func secret_pull(tell: bool) -> void:
	secret_until = Time.get_ticks_msec() + 12000
	if not tell or main.net == null or not main.net.is_online():
		return
	if main.net.is_host():
		for id in main.net.peer_ids():
			main.net.send_var(id, 3, {"k": "noir_pull"})
	else:
		main.net.send_var(1, 3, {"k": "noir_pull"})


func secret_open() -> float:
	return float(_secret.get("open", 0.0))


# ---------------------------------------------------------------- the theater: a big screen, three staggered rows stepping down

func _build_theater() -> void:
	var p := theater
	var wall := _mat(Color(0.14, 0.06, 0.12))
	var carpet := _mat(Color(0.30, 0.06, 0.14), 0.95)
	var ceil_m := _mat(Color(0.08, 0.04, 0.08))
	var trim := _mat(Color(0.20, 0.07, 0.22), 0.7)
	var wood := _mat(Color(0.42, 0.17, 0.28), 0.65)
	var panel := _mat(Color(0.34, 0.12, 0.24), 0.65)
	var brass := _mat(Color(0.95, 0.75, 0.50), 0.3, 0.6)
	var velvet := _mat(Color(0.55, 0.05, 0.12), 0.95)
	var velvet_dk := _mat(Color(0.38, 0.03, 0.09), 0.95)
	var x0 := TH_X0 + 0.05
	var x1 := TH_X1 - 0.05
	var z0 := HALL_S + 0.1
	var z1 := TH_S
	var cx := (x0 + x1) / 2.0
	var lo := TH_LOW - 0.05
	# floor: the level back, then the steps down to the front
	var steps := [[z0, 8.4, 0.0], [8.4, 9.6, TH_MID], [9.6, z1, TH_LOW]]
	var prev := 0.0
	for st in steps:
		var y: float = st[2]
		_box(Vector3(cx, y - 0.05, (st[0] + st[1]) / 2.0), Vector3(x1 - x0, 0.1, st[1] - st[0]), carpet, p)
		if y < prev:                                    # the riser up to the step behind
			var rh := prev - y
			_box(Vector3(cx, y + rh / 2.0, st[0] + 0.005), Vector3(x1 - x0, rh, 0.01), _mat(Color(0.22, 0.05, 0.10), 0.9), p)
			var sl := _mat(Color(1.0, 0.7, 0.35), 0.5, 1.6)
			_th_glow.append([sl, 1.6])
			_box(Vector3(cx, prev - 0.005, st[0] - 0.01), Vector3(x1 - x0, 0.01, 0.025), sl, p)   # a light along the step edge
		prev = y
	_box(Vector3(cx, H + 0.05, (z0 + z1) / 2.0), Vector3(x1 - x0 + 0.1, 0.1, z1 - z0 + 0.1), ceil_m, p)
	_box(Vector3(x0, (H + lo) / 2.0, (z0 + z1) / 2.0), Vector3(0.1, H - lo, z1 - z0), wall, p)
	_box(Vector3(x1, (H + lo) / 2.0, (z0 + z1) / 2.0), Vector3(0.1, H - lo, z1 - z0), wall, p)
	_box(Vector3(cx, (H + lo) / 2.0, z1 + 0.05), Vector3(x1 - x0 + 0.1, H - lo, 0.1), wall, p)
	_wall_x(x0, x1, z0, z0 + 0.04, [[TH_DOOR - 0.47, TH_DOOR + 0.47, 0.0, DOOR_TOP]], wall, p)
	# soft panels on the side walls
	for k in 5:
		var pz := 6.3 + k * 1.2
		for side in [x0 + 0.06, x1 - 0.06]:
			_box(Vector3(side, 1.5, pz), Vector3(0.03, 1.6, 0.9), _mat(Color(0.22, 0.07, 0.16), 0.95), p)
	# the door
	_door_frame(hallway, Vector3(TH_DOOR, 0.0, HALL_S - 0.02), 0.0, 0.94, DOOR_TOP, trim)
	_door_frame(p, Vector3(TH_DOOR, 0.0, z0 + 0.03), 0.0, 0.94, DOOR_TOP, trim)
	var td := _door_slab(doors_root, Vector3(TH_DOOR - 0.47, 0.0, HALL_S + 0.05), 0.0, 0.94, wood, panel, brass)
	_doors.append({"pivot": td, "at": Vector2(TH_DOOR, HALL_S + 0.05), "open": 0.0, "sign": -1.0, "links": ["hallway", "theater"]})
	var plate := _mat(Color(0.12, 0.05, 0.16), 0.5)
	_box(Vector3(TH_DOOR, 2.38, HALL_S - 0.005), Vector3(0.46, 0.13, 0.01), plate, hallway)
	_label("THEATER", Vector3(TH_DOOR, 2.38, HALL_S - 0.012), PI, 34, Color(1.0, 0.6, 0.65), hallway)
	# the screen, on the south wall, with curtains either side
	var sy := TH_LOW + 0.75 + TH_SCREEN.y / 2.0
	var scr := Node3D.new()
	scr.position = Vector3(cx, sy, z1 - 0.02)
	scr.rotation.y = PI                          # faces north, toward the seats
	p.add_child(scr)
	_box(Vector3(0, 0, -0.012), Vector3(TH_SCREEN.x + 0.16, TH_SCREEN.y + 0.16, 0.02), _mat(Color(0.02, 0.02, 0.03), 0.9), scr)   # (local -z is toward the wall)
	# its own player: a VCR on a little stand at the back, by the door
	_box(Vector3(9.2, 0.36, 6.05), Vector3(0.5, 0.72, 0.95), wood, p)
	_blockers["theater"].append(Rect2(8.9, 5.55, 0.65, 1.0))
	th_tv = RoomTV.new()
	th_tv.build(main, p, "TV_theater", Transform3D(Basis(Vector3.UP, PI), Vector3(cx, sy, z1 - 0.02)), TH_SCREEN,
		Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(9.2, 0.72, 6.05)))
	for side in [-1.0, 1.0]:
		for k in 5:
			var cxk: float = side * (TH_SCREEN.x / 2.0 + 0.12 + k * 0.07)
			var fold := _box(Vector3(cx + cxk, (H + lo) / 2.0, z1 - 0.1 - (k % 2) * 0.03), Vector3(0.08, H - lo, 0.04), velvet if k % 2 == 0 else velvet_dk, p)
			fold.rotation.y = 0.0
	_box(Vector3(cx, H - 0.15, z1 - 0.1), Vector3(TH_SCREEN.x + 1.0, 0.3, 0.06), velvet_dk, p)                    # valance
	# two big speakers either side of the screen (they play the TV's sound)
	for side in [-1.0, 1.0]:
		main._make_speaker("Theater speaker " + ("L" if side < 0 else "R"), Vector3(cx + side * (TH_SCREEN.x / 2.0 + 0.15), TH_LOW + 0.55, z1 - 0.35),
			PI, 0.0, Vector3(0.4, 1.1, 0.4), 0.13, p)
		main.bank.set_mode(main.bank.speakers.size() - 1, "tv")
		th_tv.speakers.append(main.bank.speakers.size() - 1)
		_blockers["theater"].append(Rect2(cx + side * (TH_SCREEN.x / 2.0 + 0.15) - 0.3, z1 - 0.65, 0.6, 0.6))
	if main.pc != null:
		main.pc.refresh_speakers()
	# the seats: three rows of four, each row shifted half a seat from the one in front so nobody's head is in the way
	for row in TH_ROWS:
		var rz: float = row[0]
		var ry: float = row[1]
		var xs: Array = row[2]
		for sx in xs:
			var s := Node3D.new()
			s.position = Vector3(sx, ry, rz)
			s.rotation.y = PI                    # facing the screen (+z)
			p.add_child(s)
			_box(Vector3(0, 0.42, 0), Vector3(0.58, 0.12, 0.52), velvet, s)                   # seat cushion
			_box(Vector3(0, 0.78, 0.26), Vector3(0.58, 0.68, 0.12), velvet, s)                # back
			_box(Vector3(0, 0.2, 0.05), Vector3(0.5, 0.36, 0.4), velvet_dk, s)               # base
			for ax in [-0.33, 0.33]:
				_box(Vector3(ax, 0.62, 0.02), Vector3(0.08, 0.06, 0.5), _mat(Color(0.12, 0.06, 0.08), 0.5), s)   # armrests
				_box(Vector3(ax, 0.31, 0.02), Vector3(0.06, 0.62, 0.06), _mat(Color(0.12, 0.06, 0.08), 0.5), s)
			var cup: MeshInstance3D = main._cyl(Vector3(0.33, 0.66, -0.15), 0.035, 0.04, _mat(Color(0.12, 0.06, 0.08), 0.5), s)   # a cup holder
			cup.position.y = 0.655
			var seat := Node3D.new()
			seat.position = Vector3(0, 0, -0.05)
			s.add_child(seat)
			main.seat_nodes.append(seat)
			main.seat_eye.append(1.12)
			main.seat_swivel.append(false)
		_blockers["theater"].append(Rect2(5.2, rz - 0.3, 3.7, 0.62))
	# house lights: wall sconces in the gaps between the panels (a brass plate and a glass shade that throws its
	# light up the wall), and the warm light they give the room; a switch by the door turns them all off
	var sbrass := _mat(Color(0.75, 0.55, 0.3), 0.3)
	sbrass.metallic = 0.6
	var shade := _mat(Color(1.0, 0.72, 0.5), 0.5, 1.2)
	_th_glow.append([shade, 1.2])
	for k in 4:
		var lz := 6.9 + k * 1.2
		for sd in [-1.0, 1.0]:
			var wx: float = (x0 + 0.06) if sd < 0.0 else (x1 - 0.06)
			_box(Vector3(wx - sd * 0.0, 1.95, lz), Vector3(0.02, 0.26, 0.1), sbrass, p)                # back plate
			_box(Vector3(wx - sd * 0.07, 1.98, lz), Vector3(0.12, 0.16, 0.16), shade, p)             # the shade
			_box(Vector3(wx - sd * 0.035, 1.88, lz), Vector3(0.05, 0.02, 0.03), sbrass, p)            # its arm
	for sd in [-1.0, 1.0]:
		var wx2: float = (x0 + 0.5) if sd < 0.0 else (x1 - 0.5)
		_th_lights.append([_light(Vector3(wx2, 2.1, 7.5), main.WARM, 0.45, 4.0, p), 0.45])
		if not Plat.low_power():
			_th_lights.append([_light(Vector3(wx2, 1.8, 10.0), main.WARM, 0.35, 3.5, p), 0.35])
	th_tv.add_glow(_light(Vector3(cx, sy, z1 - 1.4), Color(0.6, 0.65, 1.0), 0.6, 5.5, p))
	# the light switch, inside the door on the right
	var swp := _mat(Color(0.85, 0.8, 0.75), 0.5)
	var sw := Node3D.new()
	sw.position = Vector3(TH_DOOR + 0.75, 1.2, z0 + 0.05)
	p.add_child(sw)
	_box(Vector3.ZERO, Vector3(0.09, 0.14, 0.012), swp, sw)
	_th_rocker = _box(Vector3(0, 0, 0.012), Vector3(0.03, 0.06, 0.016), _mat(Color(0.95, 0.92, 0.88), 0.4), sw)
	_th_rocker.rotation.x = 0.25
	main.interactables.append({"node": sw, "half": Vector3(0.06, 0.09, 0.04), "guest_ok": true,
		"label": func() -> String: return "HOUSE LIGHTS  [%s]" % ("OFF" if th_dark else "ON"),
		"cb": func() -> void: request_th_dark(not th_dark)})


# the switch: a guest asks the host (the host's theater); everyone else just flips it
func request_th_dark(on: bool) -> void:
	if main._is_guest():
		if not bool(main.guest_allow_seen.get("lights", false)):
			main._net_say("The host's lights: ask them to let guests use the lights.")
			return
		main.net.send_var(1, 3, {"k": "th_lights", "dark": on})
		return
	set_th_dark(on)


func set_th_dark(on: bool) -> void:
	th_dark = on
	for l in _th_lights:
		(l[0] as OmniLight3D).visible = not on
	for g in _th_glow:
		var m: StandardMaterial3D = g[0]
		m.emission_energy_multiplier = 0.0 if on else float(g[1])
		m.albedo_color.v = 0.25 if on else 1.0
	_th_rocker.rotation.x = -0.25 if on else 0.25


# the floor under (x, z): only the theater isn't flat
func floor_y(x: float, z: float) -> float:
	if room_at(x, z) != "theater":
		return 0.0
	if z < 8.4:
		return 0.0
	if z < 9.6:
		return TH_MID
	return TH_LOW


# ---------------------------------------------------------------- the building around us (floors above and below)

func _build_exterior() -> void:
	var p := exterior
	var m: Material = main.city_mat
	var x0 := WEST_X - 0.1
	var x1 := EAST_X + 0.1
	var z0 := NORTH_Z - 0.1
	var z1 := NOIR_Z1 + 0.5
	var roof := _mat(Color(0.20, 0.13, 0.24), 0.9)
	_box(Vector3((x0 + x1) / 2.0, H + 0.2, (z0 + z1) / 2.0), Vector3(x1 - x0 + 0.2, 0.3, z1 - z0 + 0.2), roof, p)                   # the roof (top floor)
	_box(Vector3((x0 + x1) / 2.0, H + 0.5, z0 - 0.05), Vector3(x1 - x0 + 0.2, 0.35, 0.12), roof, p)                               # parapet
	_box(Vector3(x1 + 0.05, H + 0.5, (z0 + z1) / 2.0), Vector3(0.12, 0.35, z1 - z0 + 0.2), roof, p)
	_box(Vector3((x0 + x1) / 2.0, (-40.0 - 1.2) / 2.0, (z0 + z1) / 2.0), Vector3(x1 - x0, 40.0 - 1.2, z1 - z0), m, p)          # below (the theater dips into it)
	var slab := _mat(Color(0.28, 0.20, 0.30), 0.85)
	var rail_m := _mat(Color(0.10, 0.08, 0.13), 0.4)
	for k in 9:                                               # the neighbours' balconies, all the way down
		var fy := -3.0 - k * 3.0
		_box(Vector3((x0 + BAL_E) / 2.0, fy, (BAL_N + NORTH_Z) / 2.0), Vector3(BAL_E - x0, 0.16, NORTH_Z - BAL_N + 0.1), slab, p)
		_box(Vector3((EAST_X + BAL_E) / 2.0, fy, (NORTH_Z + FRONT_Z) / 2.0), Vector3(BAL_E - EAST_X, 0.16, FRONT_Z - NORTH_Z), slab, p)
		_box(Vector3((x0 + BAL_E) / 2.0, fy + 1.05, BAL_N), Vector3(BAL_E - x0, 0.05, 0.05), rail_m, p)
		_box(Vector3(BAL_E, fy + 1.05, (BAL_N + FRONT_Z) / 2.0), Vector3(0.05, 0.05, FRONT_Z - BAL_N), rail_m, p)
	_box(Vector3((x0 + BAL_E) / 2.0, -0.2 - 0.2, (BAL_N + NORTH_Z) / 2.0), Vector3(BAL_E - x0, 0.2, NORTH_Z - BAL_N), slab, p)   # under ours
	_build_street()


# ---------------------------------------------------------------- the street, far below: roads, lamps, traffic, the low buildings across it
const GROUND := -30.0
var street: Node3D
var _cars: Array = []                # [node, axis ("x" or "z"), lane coordinate, speed, from, to]

func _build_street() -> void:
	street = Node3D.new()
	street.name = "Street"
	exterior.add_child(street)
	var p := street
	var asphalt := _mat(Color(0.10, 0.08, 0.12), 0.9)
	var walk := _mat(Color(0.22, 0.18, 0.24), 0.9)
	var line := _mat(Color(0.9, 0.8, 0.5), 0.6, 0.6)
	var g := GROUND
	_box(Vector3(2.0, g - 0.1, -20.0), Vector3(200.0, 0.2, 200.0), _mat(Color(0.07, 0.05, 0.09), 0.9), p)
	# the avenue along the north side, and the street down the east side
	_box(Vector3(0.0, g + 0.01, -8.5), Vector3(140.0, 0.02, 6.0), asphalt, p)
	_box(Vector3(17.0, g + 0.012, -10.0), Vector3(6.0, 0.02, 110.0), asphalt, p)
	_box(Vector3(0.0, g + 0.08, -5.0), Vector3(140.0, 0.16, 1.4), walk, p)
	_box(Vector3(0.0, g + 0.08, -12.0), Vector3(140.0, 0.16, 1.4), walk, p)
	_box(Vector3(13.6, g + 0.08, -10.0), Vector3(1.4, 0.16, 110.0), walk, p)
	_box(Vector3(20.4, g + 0.08, -10.0), Vector3(1.4, 0.16, 110.0), walk, p)
	for i in 28:
		_box(Vector3(-68.0 + i * 5.0, g + 0.025, -8.5), Vector3(2.4, 0.01, 0.12), line, p)
	for i in 22:
		_box(Vector3(17.0, g + 0.027, -62.0 + i * 5.0), Vector3(0.12, 0.01, 2.4), line, p)
	# streetlamps: a pole, an arm and a warm head, every 9 m
	var pole := _mat(Color(0.12, 0.10, 0.14), 0.5)
	var head := _mat(Color(1.0, 0.75, 0.45), 0.4, 3.5)
	var lamps: Array = []
	for i in 14:
		lamps.append([Vector3(-50.0 + i * 9.0, g, -5.6), 0.0])
	for i in 10:
		lamps.append([Vector3(13.9, g, -50.0 + i * 9.0), 1.0])
	for lp in lamps:
		var at: Vector3 = lp[0]
		_box(at + Vector3(0, 2.5, 0), Vector3(0.14, 5.0, 0.14), pole, p)
		var arm := Vector3(0, 0, -0.6) if float(lp[1]) == 0.0 else Vector3(0.6, 0, 0)
		_box(at + Vector3(0, 4.95, 0) + arm * 0.5, Vector3(0.1 + absf(arm.x), 0.08, 0.1 + absf(arm.z)), pole, p)
		_box(at + Vector3(0, 4.85, 0) + arm, Vector3(0.4, 0.12, 0.4), head, p)
	# low buildings across the east street, so looking down you see rooftops, not a hole
	var cm: Material = main.city_mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var roof_m := _mat(Color(0.16, 0.12, 0.20), 0.9)
	var unit := _mat(Color(0.35, 0.33, 0.38), 0.6)
	for b in [[27.0, -26.0, 10.0, 12.0], [27.0, -10.0, 10.0, 14.0], [27.0, 6.0, 10.0, 12.0], [38.5, -18.0, 9.0, 14.0], [38.5, 0.0, 9.0, 16.0],
			[27.0, 20.0, 10.0, 12.0]]:
		var top := g + rng.randf_range(12.0, 24.0)
		var c := Vector3(b[0], (g + top) / 2.0, b[1])
		_box(c, Vector3(b[2], top - g, b[3]), cm, p)
		_box(Vector3(c.x, top + 0.05, c.z), Vector3(b[2] - 0.3, 0.1, b[3] - 0.3), roof_m, p)
		for k in 3:                                      # rooftop air-con units and a water tank
			_box(Vector3(c.x + rng.randf_range(-b[2] * 0.3, b[2] * 0.3), top + 0.5, c.z + rng.randf_range(-b[3] * 0.3, b[3] * 0.3)), Vector3(1.4, 0.9, 1.0), unit, p)
		main._cyl(Vector3(c.x + b[2] * 0.25, top + 1.4, c.z - b[3] * 0.25), 1.0, 2.6, _mat(Color(0.28, 0.20, 0.18), 0.8), p)
	# traffic: a few cars with their lights on
	var body_cols := [Color(0.25, 0.25, 0.32), Color(0.55, 0.12, 0.16), Color(0.85, 0.85, 0.88), Color(0.12, 0.25, 0.45), Color(0.9, 0.75, 0.2)]
	var white := _mat(Color(1.0, 0.95, 0.85), 0.4, 4.0)
	var red := _mat(Color(1.0, 0.15, 0.1), 0.4, 3.0)
	for i in 10:
		var car := Node3D.new()
		p.add_child(car)
		_box(Vector3(0, 0.55, 0), Vector3(1.8, 0.7, 4.2), _mat(body_cols[i % body_cols.size()], 0.4), car)
		_box(Vector3(0, 1.05, 0.2), Vector3(1.6, 0.5, 2.2), _mat(Color(0.08, 0.08, 0.1), 0.2), car)
		for sx in [-0.6, 0.6]:
			_box(Vector3(sx, 0.6, -2.11), Vector3(0.35, 0.15, 0.03), white, car)      # headlights (front is -z)
			_box(Vector3(sx, 0.6, 2.11), Vector3(0.35, 0.15, 0.03), red, car)
		var on_avenue := i < 6
		var dir := 1.0 if i % 2 == 0 else -1.0
		var lane := (-8.5 + dir * 1.5) if on_avenue else (17.0 - dir * 1.5)
		var speed := rng.randf_range(8.0, 13.0) * dir
		var start := rng.randf_range(-60.0, 60.0)
		car.position = Vector3(start, g, lane) if on_avenue else Vector3(lane, g, start - 10.0)
		car.rotation.y = (-PI / 2.0 if dir > 0 else PI / 2.0) if on_avenue else (PI if dir > 0 else 0.0)
		_cars.append([car, "x" if on_avenue else "z", speed])


func _traffic(delta: float) -> void:
	for c in _cars:
		var n: Node3D = c[0]
		var v: float = c[2]
		if c[1] == "x":
			n.position.x += v * delta
			if n.position.x > 70.0: n.position.x = -70.0
			elif n.position.x < -70.0: n.position.x = 70.0
		else:
			n.position.z += v * delta
			if n.position.z > 40.0: n.position.z = -60.0
			elif n.position.z < -60.0: n.position.z = 40.0


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
	if z > GAME_S and z <= NOIR_Z1 and x >= GAME_E and x <= STUDY_E:
		return "noir"
	if z > HALL_S and z <= TH_S and x > TH_X0 and x <= TH_X1:
		return "theater"
	if (z < NORTH_Z and z >= BAL_N - 0.2 and x >= WEST_X - 0.1 and x <= BAL_E + 0.2) \
			or (x > EAST_X and x <= BAL_E + 0.2 and z >= BAL_N - 0.2 and z <= FRONT_Z + 0.1):
		return "balcony"
	return ""


# outside the bedroom: may I stand here?
func walkable(x: float, z: float) -> bool:
	var pt := Vector2(x, z)
	if bal_shut > 0.6 and Rect2(BAL_DOOR.x, NORTH_Z - 0.14, BAL_DOOR.y - BAL_DOOR.x, 0.28).has_point(pt):
		return false                                      # the balcony door is shut
	var ok := false
	for r in [HALL_WALK, LIV_WALK, BAL_WALK_N, BAL_WALK_E, GAME_WALK, STUDY_WALK, NOIR_WALK, TH_WALK]:
		if (r as Rect2).has_point(pt):
			ok = true
			break
	if not ok:
		for r in DOORWAYS:
			if (r as Rect2).has_point(pt):
				return true
		if Rect2(SECRET.x + 0.15, 9.95, SECRET.y - SECRET.x - 0.3, 0.75).has_point(pt):
			return secret_open() > 0.85                   # through the bookcase, when it's swung open
		return false
	var id := room_at(x, z)
	if id == "study" and Rect2(SECRET.x - 0.05, 9.9, SECRET.y - SECRET.x + 0.1, 0.5).has_point(pt) and secret_open() < 0.85:
		return false                                      # the bookcase itself
	if id == "study" and secret_open() > 0.05 and Rect2(SECRET.x - 0.2, 9.3, 0.4, 1.0).has_point(pt):
		return false                                      # the bookcase, swung out
	for b in _blockers.get(id, []):
		if (b as Rect2).has_point(pt):
			return false
	return true


# any space at all (for walking out of something you ended up inside)
func in_bounds(x: float, z: float) -> bool:
	var pt := Vector2(x, z)
	for r in [HALL_WALK, LIV_WALK, BAL_WALK_N, BAL_WALK_E, GAME_WALK, STUDY_WALK, NOIR_WALK, TH_WALK]:
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
	main.bank.listener_room = current
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
	# the balcony door slides
	var bw := move_toward(bal_shut, 1.0 if _bal_closed else 0.0, delta / 1.0)
	if bw != bal_shut:
		bal_shut = bw
		_bal_place(bw)
	# the bookcase: open after the red book is pulled, and while anybody is in the office or the way through
	if living.visible:
		_lp_tick(delta)
	if street != null and street.visible and (current == "balcony" or current == "living" or current == "bedroom"):
		_traffic(delta)
	if not _secret.is_empty():
		var want := Time.get_ticks_msec() < secret_until
		for pp in people:
			var rid := room_at((pp as Vector2).x, (pp as Vector2).y)
			if rid == "noir" or Rect2(SECRET.x, 9.9, SECRET.y - SECRET.x, 0.8).has_point(pp):
				if rid == "noir" or float(_secret["open"]) > 0.5:
					want = true
		var so: float = move_toward(float(_secret["open"]), 1.0 if want else 0.0, delta / 1.4)
		_secret["open"] = so
		(_secret["pivot"] as Node3D).rotation.y = 1.5 * smoothstep(0.0, 1.0, so)
	# what's drawn: the room I'm in, what it looks out on, and rooms behind an open door
	# (two steps out, so a room seen through a doorway shows the room beyond it too: no popping in)
	var nb := {}
	for r in SEES:
		nb[r] = (SEES[r] as Array).duplicate()
	for d in _doors:
		if float(d["open"]) > 0.02:
			var links: Array = d["links"]
			(nb[links[0]] as Array).append(links[1])
			(nb[links[1]] as Array).append(links[0])
	if not _secret.is_empty() and float(_secret["open"]) > 0.02:
		(nb["study"] as Array).append("noir")
		(nb["noir"] as Array).append("study")
	var seen := {current: true}
	var ring: Array = [current]
	for step in 2:
		var next: Array = []
		for r in ring:
			for o in nb.get(r, []):
				if not seen.has(o):
					seen[o] = true
					next.append(o)
		ring = next
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
			var show: bool = (ar == "" or seen.has(ar)) and not main.blocks_focus(hp2)     # (never in the way of a zoomed-in screen)
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
