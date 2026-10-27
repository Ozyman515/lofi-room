extends RefCounted
## Motion for King Gaboon from Quaternius's CC0 Animated Robot (squat, long arms): kaiju/anim/robot_anims.res holds
## each animation at 30 fps in Gaboon's rig frame (authored facing +z, +y up, L side at +x). The robot stands in a
## T-pose while Gaboon's arms hang, so limbs come as the way each bone points (upper arm, forearm), and Gaboon's
## shoulder and elbow are turned to point the same way; torso and head as turns.

const DATA := "res://kaiju/anim/robot_anims.res"
# Gaboon's arms at rest, as authored (gaboon_model.gd): shoulder -> elbow, elbow -> wrist, for the L side (R mirrors x)
const UP_REST := Vector3(0.3, -1.25, 0.4)
const LO_REST := Vector3(-0.1, -1.3, 0.4)

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
	for k in ["torso", "head"]:
		var a: PackedFloat32Array = d[k]
		out[k] = Quaternion(a[i * 4], a[i * 4 + 1], a[i * 4 + 2], a[i * 4 + 3]).slerp(Quaternion(a[j * 4], a[j * 4 + 1], a[j * 4 + 2], a[j * 4 + 3]), u)
	for k in ["upL", "upR", "loL", "loR", "thL", "thR", "shL", "shR"]:
		var a: PackedFloat32Array = d[k]
		out[k] = Vector3(a[i * 3], a[i * 3 + 1], a[i * 3 + 2]).lerp(Vector3(a[j * 3], a[j * 3 + 1], a[j * 3 + 2]), u).normalized()
	var lf: PackedFloat32Array = d["lift"]
	out["lift"] = lerpf(lf[i], lf[j], u)
	return out


# the shoulder and elbow turns that point Gaboon's arm (i: 0 = L, 1 = R) along the pose's upper arm and forearm;
# body_q is how his body is turned right now (the directions are upright, in the rig's frame)
static func arm(pose: Dictionary, i: int, body_q: Quaternion) -> Array:
	var sx := 1.0 if i == 0 else -1.0
	var side := "L" if i == 0 else "R"
	var up_rest := Vector3(UP_REST.x * sx, UP_REST.y, UP_REST.z).normalized()
	var lo_rest := Vector3(LO_REST.x * sx, LO_REST.y, LO_REST.z).normalized()
	var up: Vector3 = body_q.inverse() * (pose["up" + side] as Vector3)
	var qa := Quaternion(up_rest, up.normalized())
	var lo: Vector3 = (body_q * qa).inverse() * (pose["lo" + side] as Vector3)
	var qe := Quaternion(lo_rest, lo.normalized())
	return [qa, qe]
