extends Node
## Picking up a figure (like the King Gaboon one): it glides up in front of you, a little low, turned to face you,
## does its little show in your hand, then glides back onto its stand. One of these per figure.

var main: Node3D
var toy: Node3D
var face := Vector3.RIGHT          # the figure's own front (+x for the monsters, +z for the Visitor)
var hold := 2.8                    # seconds in your hand
var show_cb := Callable()          # show_cb.call(t, k): t seconds since picked up, k 0..1 how far it's up in front of you
var done_cb := Callable()          # back on the stand
var t := -1.0
var _home := Transform3D()         # its place on the stand (in its parent)
var _scale := Vector3.ONE


func setup(m: Node3D, figure: Node3D, front: Vector3, seconds: float, show: Callable, done: Callable) -> void:
	main = m
	toy = figure
	face = front
	hold = seconds
	show_cb = show
	done_cb = done
	set_process(false)


func busy() -> bool:
	return t >= 0.0


func pick() -> bool:
	if t >= 0.0 or toy == null or main.head == null:
		return false
	_home = toy.transform
	_scale = toy.global_transform.basis.get_scale()
	t = 0.0
	set_process(true)
	return true


func _process(delta: float) -> void:
	if t < 0.0:
		set_process(false)
		return
	t += delta
	var k := 1.0 - exp(-8.0 * delta)
	var parent := toy.get_parent() as Node3D
	if t < hold:
		var hx: Transform3D = main.head.global_transform
		var fwd := -hx.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var to_you := -fwd
		var b: Basis
		if face == Vector3.RIGHT:
			b = Basis(to_you, Vector3.UP, to_you.cross(Vector3.UP))
		else:
			b = Basis(Vector3.UP.cross(to_you), Vector3.UP, to_you)
		_glide(Transform3D(b.scaled(_scale), hx.origin + fwd * 0.42 + Vector3(0, -0.16, 0)), k)
	else:
		var home := parent.global_transform * _home
		_glide(home, k)
		if toy.global_position.distance_to(home.origin) < 0.004:
			toy.transform = _home
			t = -1.0
			set_process(false)
			if show_cb.is_valid():
				show_cb.call(-1.0, 0.0)                  # (rest pose)
			if done_cb.is_valid():
				done_cb.call()
			return
	if show_cb.is_valid():
		show_cb.call(t, clampf(t / 0.5, 0.0, 1.0) * clampf((hold - t) / 0.4, 0.0, 1.0))


func _glide(target: Transform3D, k: float) -> void:
	var cur := toy.global_transform
	var q := cur.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), k)
	toy.global_transform = Transform3D(Basis(q).scaled(target.basis.get_scale()), cur.origin.lerp(target.origin, k))
