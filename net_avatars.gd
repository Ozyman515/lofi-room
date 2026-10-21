extends Node3D
## Other players as a floating head, two hands and a name tag.
## Everyone sends their own head + hands to the host ~20 times a second; the host sends each
## guest the latest poses of everybody else. Poses are in room coordinates (same room for all).

const Net := preload("res://net_session.gd")

const SEND_HZ := 20.0
const FLOATS_PER := 21           # head, left hand, right hand: position (3) + rotation quaternion (4) each
const RECORD := FLOATS_PER + 1   # + the player id

var net: Node
var main: Node3D
var avatars := {}                # id -> Avatar
var _poses := {}                 # id -> PackedFloat32Array (latest known)
var _t := 0.0
var _items := {}                 # id -> the slap interactable


class Avatar extends Node3D:
	var head: Node3D
	var lh: Node3D
	var rh: Node3D
	var tag: Label3D
	var target := PackedFloat32Array()
	var pad: Node3D                 # the controller in their hands, while they hold one

	func build(pname: String, col: Color) -> void:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.9
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.1, 0.04, 0.16)
		head = Node3D.new()
		add_child(head)
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.11
		sm.height = 0.22
		sm.radial_segments = 16
		sm.rings = 8
		s.mesh = sm
		s.material_override = m
		head_mat = m
		head.add_child(s)
		var visor := MeshInstance3D.new()      # dark band so you can tell which way they face (-z is forward)
		var vb := BoxMesh.new()
		vb.size = Vector3(0.17, 0.06, 0.05)
		visor.mesh = vb
		visor.material_override = dark
		visor.position = Vector3(0, 0.01, -0.09)
		head.add_child(visor)
		lh = _hand(m)
		rh = _hand(m)
		tag = Label3D.new()
		tag.text = pname
		tag.font_size = 48
		tag.pixel_size = 0.0007
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.modulate = Color(1, 0.95, 1)
		tag.outline_modulate = Color(0.2, 0.05, 0.3)
		tag.position = Vector3(0, 0.26, 0)
		head.add_child(tag)

	func _hand(m: Material) -> Node3D:
		var n := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		sm.radial_segments = 12
		sm.rings = 6
		n.mesh = sm
		n.material_override = m
		add_child(n)
		return n

	var head_mat: StandardMaterial3D
	var base_glow := 0.9

	func set_talking(level: float) -> void:
		if head_mat != null:
			head_mat.emission_energy_multiplier = base_glow + clampf(level * 12.0, 0.0, 2.5)

	func apply(delta: float, snap := false) -> void:
		if target.size() < FLOATS_PER:
			return
		var k := 1.0 if snap else 1.0 - exp(-16.0 * delta)
		_move(head, 0, k)
		_move(lh, 7, k)
		_move(rh, 14, k)

	func _move(n: Node3D, o: int, k: float) -> void:
		var p := Vector3(target[o], target[o + 1], target[o + 2])
		var q := Quaternion(target[o + 3], target[o + 4], target[o + 5], target[o + 6]).normalized()
		n.global_position = n.global_position.lerp(p, k)
		n.quaternion = n.quaternion.slerp(q, k)


func setup(session: Node, m: Node3D) -> void:
	net = session
	main = m
	net.roster_changed.connect(_sync_roster)
	net.state_changed.connect(_sync_roster)
	net.packet.connect(_on_packet)


func _sync_roster() -> void:
	for id in avatars.keys():
		if not net.roster.has(id) or id == net.my_id or not net.is_online():
			avatars[id].queue_free()
			avatars.erase(id)
			_poses.erase(id)
			if _items.has(id):
				main.interactables.erase(_items[id])
				_items.erase(id)
	if not net.is_online():
		return
	for id in net.roster:
		if id == net.my_id or avatars.has(id):
			continue
		var a := Avatar.new()
		add_child(a)
		a.build(str(net.roster[id].get("name", "?")), net.roster[id].get("color", Color(1, 0.5, 0.8)))
		avatars[id] = a
		a.visible = false
		# pointing at somebody who holds a controller offers a slap
		var pid: int = id
		var it := {"node": a.head, "half": Vector3(0.16, 0.16, 0.16), "guest_ok": true, "player": pid,
			"when": func() -> bool: return a.visible,
			"label": func() -> String: return main.player_label(pid),
			"cb": func() -> void:
				if main.net_game != null and main.net_game.holds_pad(pid):
					main.try_slap(pid)}
		main.interactables.append(it)
		_items[id] = it
	for id in avatars:
		avatars[id].tag.text = str(net.roster.get(id, {}).get("name", "?"))


func _process(delta: float) -> void:
	_rug_pads()
	for id in avatars:
		avatars[id].apply(delta)
		_show_pad(avatars[id], main.net_game != null and main.net_game.holds_controller(id))
		if main.net_voice != null:
			avatars[id].set_talking(float(main.net_voice.levels.get(id, 0.0)) if main.net_voice.is_speaking(id) else 0.0)
	if net == null or not net.is_online():
		return
	_t += delta
	if _t < 1.0 / SEND_HZ:
		return
	_t = 0.0
	var mine := _my_pose()
	if net.is_host():
		_poses[1] = mine
		for gid in net.peer_ids():
			var out := PackedFloat32Array()
			for id in _poses:
				if id != gid:
					out.append(float(id))
					out.append_array(_poses[id])
			if out.size() > 0:
				net.send_to(gid, Net.K_POSE, out.to_byte_array(), false)
	else:
		net.send_to(1, Net.K_POSE, mine.to_byte_array(), false)


var _hidden_pads := {}           # rug pad index -> true while I hide it because somebody else holds it


func _rug_pads() -> void:
	var taken: Dictionary = main.net_game.pads_taken_by_others() if main.net_game != null and net != null and net.is_online() else {}
	for i in main.pad_nodes.size():
		if taken.has(i) and i != main.held_pad_idx:
			if main.pad_nodes[i].visible:
				main.pad_nodes[i].visible = false
				_hidden_pads[i] = true
		elif _hidden_pads.has(i):
			_hidden_pads.erase(i)
			if i != main.held_pad_idx:
				main.pad_nodes[i].visible = true


# a held controller sits between their hands, facing the way their head faces, tilted up like you'd hold it
func _show_pad(a: Avatar, held: bool) -> void:
	if held and a.pad == null:
		a.pad = Node3D.new()
		main._pad_meshes(a.pad)
		a.add_child(a.pad)
	elif not held and a.pad != null:
		a.pad.queue_free()
		a.pad = null
	if a.pad == null or not a.visible:
		return
	var yaw := Basis(Vector3.UP, a.head.global_transform.basis.get_euler().y)
	var mid := (a.lh.global_position + a.rh.global_position) * 0.5
	a.pad.global_transform = Transform3D(yaw * Basis(Vector3.RIGHT, 0.6), mid + yaw * Vector3(0, 0.02, -0.04))


func _my_pose() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var hx: Transform3D = main.head.global_transform
	_push(out, hx)
	if main.xr_active:
		_push(out, main.left_hand.global_transform)
		_push(out, main.right_hand.global_transform)
	else:
		# no controllers on the desktop: hands rest in front of the body
		var yaw := Basis(Vector3.UP, hx.basis.get_euler().y)
		for sx in [-0.22, 0.22]:
			_push(out, Transform3D(yaw, hx.origin + yaw * Vector3(sx, -0.4, -0.3)))
	return out


func _push(out: PackedFloat32Array, t: Transform3D) -> void:
	var q := t.basis.get_rotation_quaternion()
	out.append_array(PackedFloat32Array([t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w]))


func _on_packet(from: int, kind: int, payload: PackedByteArray) -> void:
	if kind != Net.K_POSE or payload.size() % 4 != 0:
		return
	var f := payload.to_float32_array()
	if net.is_host():
		if f.size() == FLOATS_PER and net.roster.has(from):
			_store(from, f)
	else:
		if from != 1 or f.size() % RECORD != 0:
			return
		var i := 0
		while i < f.size():
			_store(int(f[i]), f.slice(i + 1, i + RECORD))
			i += RECORD


func _store(id: int, f: PackedFloat32Array) -> void:
	for v in f:
		if is_nan(v) or is_inf(v) or absf(v) > 1000.0:
			return
	_poses[id] = f
	if avatars.has(id):
		var a = avatars[id]
		var first: bool = a.target.size() == 0
		a.target = f
		if first:
			a.visible = true
			a.apply(0.0, true)
