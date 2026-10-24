extends Node3D
## Thumbs up / thumbs down for whatever's playing on the TV. Two buttons on the TV's control panel; press one
## and a big thumb pops up over the set (with your name, in a room) and the counts on the buttons go up.
## One vote each per video: press the same thumb again to take it back, the other one to change your mind.
## In a room the host keeps the count, so everybody sees the same numbers, and whoever put the tape in gets
## told who liked it. The count starts over when a different video goes on.

const Net := preload("res://net_session.gd")

const UP_COL := Color(0.45, 0.85, 0.55)
const DOWN_COL := Color(0.95, 0.45, 0.55)

var main: Node3D
var votes := {}                 # host / offline: player id -> 1 or -1
var tally := Vector2i.ZERO      # what the buttons show (x up, y down)
var mine := 0                   # my own vote on this video
var key := 0                    # which video the votes belong to (0 = nothing on)
var guest_keys := {}            # host side: guest id -> the video their tape is
var _last_vote := {}            # host side: id -> ms, so nobody can machine-gun it
var _up_label: Label3D
var _down_label: Label3D
var _up_m: StandardMaterial3D
var _down_m: StandardMaterial3D
var _sent_key := 0             # guest side: the video key I last told the host about


# builds the two buttons into the TV (parent = the TV root, local +z out of the screen) and returns their
# interactables
func build(m: Node3D, tv: Node3D, center: Vector3) -> Array:
	main = m
	tv.add_child(self)
	position = center
	var items: Array = []
	for i in 2:
		var up := i == 0
		var btn := Node3D.new()
		btn.position = Vector3(-0.055 if up else 0.055, 0.0, 0.0)
		add_child(btn)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.30, 0.26, 0.34)
		mat.roughness = 0.5
		var face := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.065, 0.02)
		face.mesh = bm
		face.material_override = mat
		btn.add_child(face)
		var icon := make_thumb(UP_COL if up else DOWN_COL, up)
		icon.scale = Vector3.ONE * 0.3
		icon.position = Vector3(-0.018, 0.0, 0.016)
		btn.add_child(icon)
		var lab := Label3D.new()
		lab.text = "0"
		lab.font_size = 40
		lab.pixel_size = 0.0007
		lab.outline_size = 0
		lab.modulate = Color(0.92, 0.88, 0.95)
		lab.position = Vector3(0.024, 0.0, 0.0115)
		btn.add_child(lab)
		if up:
			_up_label = lab
			_up_m = mat
		else:
			_down_label = lab
			_down_m = mat
		var v := 1 if up else -1
		items.append({"node": face, "half": Vector3(0.05, 0.04, 0.03), "guest_ok": true, "group": "tv",
			"when": is_open,
			"label": func() -> String:
				var n := tally.x if up else tally.y
				var what := "THUMBS UP" if up else "THUMBS DOWN"
				if mine == v:
					return "TAKE BACK YOUR %s  (%d)" % [what, n]
				return "%s FOR THIS VIDEO  (%d)" % [what, n],
			"cb": func() -> void: vote(v),
			"hover": func(on: bool) -> void:
				mat.emission_enabled = on
				mat.emission = UP_COL if up else DOWN_COL
				mat.emission_energy_multiplier = 0.5})
	_show()
	return items


# a chunky cartoon thumb: a rounded fist with a thumb sticking up (or down), and a cuff
static func make_thumb(col: Color, up: bool) -> Node3D:
	var root := Node3D.new()
	var skin := StandardMaterial3D.new()
	skin.albedo_color = col
	skin.roughness = 0.45
	skin.emission_enabled = true
	skin.emission = col
	skin.emission_energy_multiplier = 0.35
	var dark := StandardMaterial3D.new()
	dark.albedo_color = col.darkened(0.45)
	dark.roughness = 0.6
	var fist := MeshInstance3D.new()
	var fm := CapsuleMesh.new()
	fm.radius = 0.05
	fm.height = 0.13
	fm.radial_segments = 16
	fm.rings = 4
	fist.mesh = fm
	fist.rotation.z = PI / 2.0                 # lying sideways: the curled fingers
	fist.scale = Vector3(1.0, 1.0, 0.75)
	fist.material_override = skin
	root.add_child(fist)
	for j in 3:                                # the lines between the fingers
		var ln := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.006, 0.07, 0.004)
		ln.mesh = lb
		ln.position = Vector3(-0.025 + j * 0.025, -0.005, 0.037)
		ln.material_override = dark
		root.add_child(ln)
	var thumb := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.024
	tm.height = 0.1
	tm.radial_segments = 12
	tm.rings = 3
	thumb.mesh = tm
	thumb.position = Vector3(-0.035, 0.065, 0.0)
	thumb.rotation.z = 0.15
	thumb.material_override = skin
	root.add_child(thumb)
	var cuff := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.03, 0.085, 0.07)
	cuff.mesh = cm
	cuff.position = Vector3(0.083, 0.0, 0.0)
	cuff.material_override = dark
	root.add_child(cuff)
	if not up:
		root.rotation.z = PI
	return root


# something's on the TV to rate
func is_open() -> bool:
	return current_key() != 0


func _online() -> bool:
	return main.net != null and main.net.is_online()


# which video is on right now (as this player knows it); 0 when nothing is playing
func current_key() -> int:
	if _online() and not main.net.is_host():
		return key                             # the host says
	var ng = main.net_game
	if _online() and ng != null and ng.tv_source != 1:
		return int(guest_keys.get(ng.tv_source, 0)) if ng.tv_live else 0
	return _my_tape_key()


func _my_tape_key() -> int:
	var v = main.vcr
	if not v.tv_on or not v.has_tape or not (v.state == v.State.PLAYING or v.state == v.State.PAUSED):
		return 0
	var h := str(v._src).hash()
	return h if h != 0 else 1


func vote(v: int) -> void:
	if not is_open():
		return
	if _online() and not main.net.is_host():
		mine = 0 if mine == v else v           # (the host's count comes back in the room state)
		main.net.send_var(1, Net.K_EVENT, {"k": "tv_vote", "v": mine, "key": key})
		_show()
		return
	_host_vote(main.net.my_id if _online() else 1, 0 if int(votes.get(main.net.my_id if _online() else 1, 0)) == v else v)


# host / offline: somebody voted (v = 1, -1, or 0 to take it back)
func _host_vote(from: int, v: int) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_vote.get(from, -10000)) < 600:
		return
	_last_vote[from] = now
	var before := int(votes.get(from, 0))
	if v == 0:
		votes.erase(from)
	else:
		votes[from] = v
	_recount()
	if from == (main.net.my_id if _online() else 1):
		mine = v
	_show()
	if v == 0 or v == before:
		return
	var who := _name_of(from)
	pop(v, who)
	if _online():
		for id in main.net.peer_ids():
			main.net.send_var(id, Net.K_EVENT, {"k": "tv_voted", "v": v, "by": who, "id": from})
		var src: int = main.net_game.tv_source
		if src == main.net.my_id and from != src:
			_tell_owner(v, who)


func _name_of(id: int) -> String:
	if not _online():
		return ""
	return str(main.net.roster.get(id, {}).get("name", "Someone"))


func _tell_owner(v: int, who: String) -> void:
	main.updater.show_toast("%s gave your video a thumbs %s." % [who, "up" if v > 0 else "down"], 3.5)


func _recount() -> void:
	var t := Vector2i.ZERO
	for id in votes:
		if int(votes[id]) > 0:
			t.x += 1
		else:
			t.y += 1
	tally = t


# every frame: start over when the video changes; guests tell the host which video their tape is
func _process(_delta: float) -> void:
	if main == null:
		return
	if _online() and not main.net.is_host():
		var ng = main.net_game
		if ng != null and ng.tv_source == main.net.my_id:
			var mk := _my_tape_key()
			if mk != _sent_key:
				_sent_key = mk
				main.net.send_var(1, Net.K_EVENT, {"k": "tv_tape", "key": mk})
		else:
			_sent_key = 0
		return
	var k := current_key()
	if k != key:
		key = k
		votes.clear()
		mine = 0
		_recount()
		_show()


func _show() -> void:
	if _up_label == null:
		return
	_up_label.text = str(tally.x)
	_down_label.text = str(tally.y)
	var open := is_open()
	_up_label.modulate.a = 1.0 if open else 0.35
	_down_label.modulate.a = 1.0 if open else 0.35
	# your own pick stays lit
	for pair in [[_up_m, 1], [_down_m, -1]]:
		var m: StandardMaterial3D = pair[0]
		m.albedo_color = (UP_COL if pair[1] > 0 else DOWN_COL).darkened(0.35) if mine == pair[1] and open else Color(0.30, 0.26, 0.34)


# ---- the network side (net_game passes these along)

# host: what goes into the room state
func state() -> Array:
	return [key, tally.x, tally.y]


# guest: the host's room state
func apply_state(s) -> void:
	if not (s is Array) or s.size() < 3:
		return
	var k := int(s[0])
	if k != key:
		key = k
		mine = 0
	tally = Vector2i(maxi(0, int(s[1])), maxi(0, int(s[2])))
	_show()


# host: a guest's message
func on_guest_event(from: int, d: Dictionary) -> void:
	match str(d.get("k", "")):
		"tv_tape":
			guest_keys[from] = int(d.get("key", 0))
		"tv_vote":
			if int(d.get("key", 0)) != key or key == 0:
				return                         # voted on a video that's already gone
			var v := clampi(int(d.get("v", 0)), -1, 1)
			_host_vote(from, v)


# guest: the host says somebody voted
func on_voted(d: Dictionary) -> void:
	var v := clampi(int(d.get("v", 0)), -1, 1)
	if v == 0:
		return
	var who := str(d.get("by", "Someone")).left(24)
	if int(d.get("id", 0)) == main.net.my_id:
		who = "You"
	pop(v, who)
	var ng = main.net_game
	if ng != null and ng.tv_source == main.net.my_id and int(d.get("id", 0)) != main.net.my_id:
		_tell_owner(v, who)


# a big thumb floats up over the TV and fades
func pop(v: int, who: String) -> void:
	var holder := Node3D.new()
	get_parent().add_child(holder)
	holder.position = Vector3(randf_range(-0.35, 0.35), 1.2, 0.35)
	var t := make_thumb(UP_COL if v > 0 else DOWN_COL, v > 0)
	t.scale = Vector3.ONE * 1.4
	holder.add_child(t)
	var mats: Array = []
	for c in t.get_children():
		if c is MeshInstance3D:
			var mm: StandardMaterial3D = (c as MeshInstance3D).material_override.duplicate()
			mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			(c as MeshInstance3D).material_override = mm
			mats.append(mm)
	var lab: Label3D = null
	if who != "":
		lab = Label3D.new()
		lab.text = who
		lab.font_size = 56
		lab.pixel_size = 0.0012
		lab.outline_size = 10
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position = Vector3(0, -0.17, 0)
		holder.add_child(lab)
	holder.scale = Vector3.ONE * 0.3
	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "position:y", 1.6, 2.0).set_ease(Tween.EASE_OUT)
	tw.tween_property(t, "rotation:y", randf_range(-0.4, 0.4), 2.0)
	tw.tween_method(func(a: float) -> void:
		for mm in mats:
			(mm as StandardMaterial3D).albedo_color.a = a
		if lab != null:
			lab.modulate.a = a
			lab.outline_modulate.a = a, 1.0, 0.0, 0.7).set_delay(1.3)
	tw.chain().tween_callback(holder.queue_free)
