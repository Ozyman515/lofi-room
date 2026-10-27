extends RefCounted
## Motion for the two tyrannosaurs (Banira, and Jogari who shares its body plan), from the T-Rex in Quaternius's CC0
## Dinosaur Animated Pack: kaiju/anim/trex_anims.res holds each animation sampled at 30 fps, already turned into the
## monsters' frame (+x forward, +y up, L side at -z): body, head, arms and tail as rotations, the body's rise, and
## where each foot is (the pack walks by moving its feet; the legs follow). Here the legs are solved to reach those
## feet (two joints: hip and knee), so on the walk past the window the feet stay planted while the body moves on.
## Played slower and bigger than the pack has it, so it moves like something the size of a building.

const DATA := "res://kaiju/anim/trex_anims.res"
const UNIT := 15.2                    # the pack's units -> the model's (hip height 0.0294 there, 0.448 here)

static var _anims: Dictionary = {}
static var _loaded := false


static func ok() -> bool:
	if not _loaded:
		_loaded = true
		if ResourceLoader.exists(DATA):
			var r: Resource = load(DATA)
			if r != null and r.has_meta("anims"):
				_anims = r.get_meta("anims")
	return not _anims.is_empty()


static func length(anim: String) -> float:
	return float(_anims[anim]["len"]) if ok() and _anims.has(anim) else 1.0


# how far a foot travels backward while it's on the ground (pack units): one step of the walk
static func stance(anim: String) -> float:
	if not ok():
		return 1.0
	var f: PackedFloat32Array = _anims[anim]["footL"]
	var lo := 9.0
	var hi := -9.0
	for k in range(0, f.size(), 3):
		if f[k + 1] < 0.001:                   # on the ground
			lo = minf(lo, f[k])
			hi = maxf(hi, f[k])
	return maxf(hi - lo, 0.001)


# the pose at time t (looping): {"body", "head", "armL", "armR", "tail": Quaternion, "lift": float,
# "footL", "footR": Vector3 (pack units)}
static func sample(anim: String, t: float, loop := true) -> Dictionary:
	var d: Dictionary = _anims[anim]
	var fps: float = d["fps"]
	var n: int = (d["lift"] as PackedFloat32Array).size()
	var L: float = d["len"]
	t = fposmod(t, L) if loop else clampf(t, 0.0, L)
	var x := t * fps
	var i := mini(int(x), n - 1)
	var j := mini(i + 1, n - 1)
	var u := x - float(i)
	var out := {}
	for k in ["body", "head", "armL", "armR", "tail", "tail1", "tail2", "tail3", "tail4", "tail5"]:
		if not d.has(k):
			continue
		var a: PackedFloat32Array = d[k]
		var qa := Quaternion(a[i * 4], a[i * 4 + 1], a[i * 4 + 2], a[i * 4 + 3])
		var qb := Quaternion(a[j * 4], a[j * 4 + 1], a[j * 4 + 2], a[j * 4 + 3])
		out[k] = qa.slerp(qb, u)
	var lf: PackedFloat32Array = d["lift"]
	out["lift"] = lerpf(lf[i], lf[j], u)
	for k in ["footL", "footR"]:
		var f: PackedFloat32Array = d[k]
		out[k] = Vector3(f[i * 3], f[i * 3 + 1], f[i * 3 + 2]).lerp(Vector3(f[j * 3], f[j * 3 + 1], f[j * 3 + 2]), u)
	return out


# the tail's five joints (kaiju_model.gd's skeleton under the body, bones 1..5) from three poses blended like the
# rest of the body: idle, walk (by walk) and attack (by aw), each made bigger by its amp; extra adds a sway
# (radians about y, spread down the tail so the tip swings most) for the fight's tail whips and a walk's swing
static func pose_tail(skel: Skeleton3D, idle: Dictionary, walk: Dictionary, wk: float, atk: Dictionary, aw: float, wamp := 1.4, aamp := 1.3, extra := 0.0) -> void:
	if skel == null:
		return
	for i in 5:
		var k := "tail%d" % (i + 1)
		if not idle.has(k):
			return
		var q: Quaternion = (idle[k] as Quaternion).slerp(amp(walk[k], wamp), wk)
		if not atk.is_empty():
			q = q.slerp(amp(atk[k], aamp), aw)
		if extra != 0.0:
			q = q * Quaternion(Vector3.UP, extra * (0.12 + 0.07 * i))
		skel.set_bone_pose_rotation(i + 1, q)


# a rotation made bigger (k > 1) or smaller, about the same axis
static func amp(q: Quaternion, k: float) -> Quaternion:
	return Quaternion.IDENTITY.slerp(q, k) if k <= 1.0 else Quaternion(q.get_axis().normalized(), q.get_angle() * k) if q.get_angle() > 0.0001 else q


# the hip, knee and sole of a leg at rest, in the body's space (worked out once from the model's own pieces)
static func leg_rest(leg: Node3D) -> Array:
	if leg.has_meta("rex_rest"):
		return leg.get_meta("rex_rest")
	var knee := leg.get_node("Knee") as Node3D
	var hip := leg.position
	var kp := hip + knee.position
	var sole := kp + Vector3(0.0, -0.27, 0.0)
	for c in knee.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var a := (c as MeshInstance3D).mesh.get_aabb()
			sole = kp + Vector3(a.get_center().x * 0.3, a.position.y, 0.0)
			break
	var r := [hip, kp, sole]
	leg.set_meta("rex_rest", r)
	return r


# turn the hip and knee (about z, the leg's own swing) so the sole lands on target (the body's space)
static func reach(leg: Node3D, target: Vector3) -> void:
	var r := leg_rest(leg)
	var h: Vector3 = r[0]
	var k0: Vector3 = r[1]
	var f0: Vector3 = r[2]
	var u0 := Vector2(k0.x - h.x, k0.y - h.y)
	var v0 := Vector2(f0.x - k0.x, f0.y - k0.y)
	var a := u0.length()
	var b := v0.length()
	var dv := Vector2(target.x - h.x, target.y - h.y)
	var d := clampf(dv.length(), absf(a - b) + 0.001, a + b - 0.001)
	var bend := signf(Vector2(f0.x - h.x, f0.y - h.y).cross(u0))      # which way the knee points at rest
	if bend == 0.0:
		bend = 1.0
	var g := acos(clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0))
	var al := dv.angle() + bend * g
	var kp := Vector2(h.x, h.y) + Vector2.from_angle(al) * a
	var be := (Vector2(target.x, target.y) - kp).angle()
	var al0 := u0.angle()
	var be0 := v0.angle()
	leg.rotation = Vector3(0.0, 0.0, wrapf(al - al0, -PI, PI))
	(leg.get_node("Knee") as Node3D).rotation = Vector3(0.0, 0.0, wrapf((be - al) - (be0 - al0), -PI, PI))
