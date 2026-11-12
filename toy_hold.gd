extends Node
## Picking up a figure (King Gaboon, Banira, Jogari, the Visitor) to look at it. It glides up in front of you and
## stays there until you put it back: turn it any way you like, bring it closer or push it away, and make it do its
## show (the roar). One of these per figure. While one is held, main.held_toy points at it and the input goes here:
##   desktop: move the mouse (or the arrow keys) to turn it, wheel or + / - to zoom, R or right click to roar,
##            E, G or left click to put it back
##   gamepad: right stick turns, LB / RB zoom, A or RT roars, B or X puts it back
##   VR:      it sits in the hand that picked it up (turn your wrist, bring it closer); trigger roars, grip puts it back

var main: Node3D
var toy: Node3D
var face := Vector3.RIGHT          # the figure's own front (+x for the monsters, +z for the Visitor)
var hold := 2.8                    # how long its show lasts
var show_cb := Callable()          # show_cb.call(t, k): t seconds into the show (-1 = rest pose), k 0..1 how strongly
var done_cb := Callable()          # back on the stand
var roar_cb := Callable()          # the show has just started (the easter eggs count these)

var holding := false
var hand := 2                      # 0 / 1 the VR hand holding it, 2 desktop or gamepad
var show_t := -1.0                 # seconds into the show (-1 = not showing)
var t := -1.0                      # kept for older callers: >= 0 while it is off the stand
var _returning := false
var _home := Transform3D()         # its place on the stand (in its parent)
var _scale := Vector3.ONE
var _center := Vector3.ZERO        # the middle of the figure in its own (unscaled) frame: it turns about this point
var _turn := Basis()               # how you've turned it (desktop / gamepad), relative to facing you
var _dist := 0.42                  # how far in front of your eyes
var _in_hand := Basis()            # VR: its turn relative to the controller

const DIST_MIN := 0.16
const DIST_MAX := 0.9


func setup(m: Node3D, figure: Node3D, front: Vector3, seconds: float, show: Callable, done: Callable, on_roar := Callable()) -> void:
	main = m
	toy = figure
	face = front
	hold = seconds
	show_cb = show
	done_cb = done
	roar_cb = on_roar
	set_process(false)


func busy() -> bool:
	return holding or _returning


func pick() -> bool:
	if busy() or toy == null or main.head == null:
		return false
	if main.get("held_toy") != null and main.held_toy != self:
		main.held_toy.put_back()                      # one figure at a time
	_home = toy.transform
	_scale = toy.global_transform.basis.get_scale()
	_center = _find_center()
	hand = main.hover_hand if main.hover_hand == 0 or main.hover_hand == 1 else 2
	_turn = Basis()
	_dist = 0.42
	show_t = -1.0
	holding = true
	_returning = false
	t = 0.0
	main.held_toy = self
	main.toy_hint_t = 8.0
	if hand != 2:
		var c := _hand_node()
		if c != null:
			_in_hand = c.global_transform.basis.orthonormalized().inverse() * _facing_you()
	set_process(true)
	return true


func put_back() -> void:
	if not holding:
		return
	holding = false
	_returning = true
	if main.get("held_toy") == self:
		main.held_toy = null


func roar() -> void:
	if not holding or show_t >= 0.0:
		return
	show_t = 0.0
	if roar_cb.is_valid():
		roar_cb.call()


# desktop / gamepad: turn it (radians across and up / down, in screen terms)
func turn(dx: float, dy: float) -> void:
	if not holding or main.head == null:
		return
	var right: Vector3 = main.head.global_transform.basis.x
	_turn = (Basis(Vector3.UP, dx) * Basis(right.normalized(), dy) * _turn).orthonormalized()


# + brings it closer, - pushes it away
func zoom(steps: float) -> void:
	_dist = clampf(_dist * pow(0.88, steps), DIST_MIN, DIST_MAX)


func _process(delta: float) -> void:
	if not holding and not _returning:
		set_process(false)
		return
	t += delta
	var k := 1.0 - exp(-10.0 * delta)
	var parent := toy.get_parent() as Node3D
	if holding:
		_glide(_held_target(), k)
	else:
		var home := parent.global_transform * _home
		_glide(home, 1.0 - exp(-8.0 * delta))
		if toy.global_position.distance_to(home.origin) < 0.004:
			toy.transform = _home
			_returning = false
			t = -1.0
			set_process(false)
			if show_t >= 0.0 and show_cb.is_valid():
				show_cb.call(-1.0, 0.0)              # (rest pose)
			show_t = -1.0
			if done_cb.is_valid():
				done_cb.call()
			return
	if show_t >= 0.0:
		show_t += delta
		if show_t >= hold:
			show_t = -1.0
			if show_cb.is_valid():
				show_cb.call(-1.0, 0.0)
		elif show_cb.is_valid():
			show_cb.call(show_t, clampf(show_t / 0.3, 0.0, 1.0) * clampf((hold - show_t) / 0.4, 0.0, 1.0))


# the figure turned to face you, its front toward your eyes
func _facing_you() -> Basis:
	var hx: Transform3D = main.head.global_transform
	var fwd := -hx.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var to_you := -fwd
	if face == Vector3.RIGHT:
		return Basis(to_you, Vector3.UP, to_you.cross(Vector3.UP))
	return Basis(Vector3.UP.cross(to_you), Vector3.UP, to_you)


func _held_target() -> Transform3D:
	var b: Basis
	var mid: Vector3
	var c := _hand_node() if hand != 2 else null
	if c != null:
		b = c.global_transform.basis.orthonormalized() * _in_hand
		mid = c.global_position - c.global_transform.basis.z * 0.09 + c.global_transform.basis.y * 0.03
	else:
		var hx: Transform3D = main.head.global_transform
		b = _turn * _facing_you()
		mid = hx.origin - hx.basis.z * _dist
	b = b.scaled(_scale)
	return Transform3D(b, mid - b * _center)       # (so it turns about its middle, not its feet)


func _hand_node() -> Node3D:
	if hand == 0:
		return main.left_hand
	if hand == 1:
		return main.right_hand
	return null


# the middle of the figure's meshes, in the figure's own unscaled frame
func _find_center() -> Vector3:
	var inv := toy.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in toy.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = inv * m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return Vector3.ZERO if first else box.get_center()


func _glide(target: Transform3D, k: float) -> void:
	var cur := toy.global_transform
	var q := cur.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), k)
	toy.global_transform = Transform3D(Basis(q).scaled(target.basis.get_scale()), cur.origin.lerp(target.origin, k))
