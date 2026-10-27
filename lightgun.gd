extends Node
## The light gun (Pistol 6 from Quaternius's CC0 Ultimate Gun Pack), resting on top of the disc console. Pick it up
## and it plays the console's own light-gun games: NES Zapper, SNES Super Scope, Genesis Menacer, PlayStation GunCon
## (emu.gd plugs the core's gun into the right port). Aim at the TV and pull the trigger: where it points on the
## glass is where the game thinks you shot. Point off the screen and pull to reload.
##   PC: aim with the middle of the view (the dot), left click shoots, right click reloads, Enter is the gun's A
##       button (START on the GunCon), Backspace its B; E puts it down. The pad keys still work for the menus.
##   VR: it sits in the hand you picked it up with; trigger shoots, A/X is the gun's A, B/Y its B, grip puts it down.
## Every shot kicks it up and back, and it clicks.

const Emu := preload("res://emu.gd")
const MESH := "res://models/lightgun_mesh.res"
const REST := Vector3(0.0, 0.0, 0.0)              # (set from the disc console in build)

var main: Node3D
var held := false
var hand := -1                     # VR: which controller has it (0 left, 1 right); -1 on the desktop
var gun: Node3D                    # the model (on its rest, or in your hand / view)
var _rest_parent: Node3D
var _rest_xf := Transform3D()
var _kick := 0.0
var _trigger := false
var _reload := false
var _aux := 0                      # bit 0 = A, bit 1 = B
var _click: AudioStreamPlayer
var _hit: Node3D


func build(m: Node3D) -> void:
	main = m
	gun = Node3D.new()
	gun.name = "LightGun"
	var mi := MeshInstance3D.new()
	mi.name = "Model"
	mi.mesh = load(MESH) if ResourceLoader.exists(MESH) else null
	gun.add_child(mi)
	# lying on its side on top of the disc console, the muzzle toward the TV side
	var con: Node3D = main.ps_kit.console
	_rest_parent = con
	_rest_xf = Transform3D(Basis(Vector3.UP, -PI / 2.0 + 0.25) * Basis(Vector3.FORWARD, PI / 2.0), Vector3(0.0, main.ps_kit.CON_H + 0.016, -0.02))
	con.add_child(gun)
	gun.transform = _rest_xf
	_hit = Node3D.new()
	_hit.position = Vector3(0.0, main.ps_kit.CON_H + 0.03, -0.02)
	con.add_child(_hit)
	main.interactables.append({"node": _hit, "half": Vector3(0.11, 0.04, 0.08), "egg_lock": true, "group": "games",
		"label": func() -> String: return "PICK UP THE LIGHT GUN",
		"when": func() -> bool: return not held and not main.game_mode,
		"cb": pick_up})
	_click = AudioStreamPlayer.new()
	_click.stream = _make_click()
	_click.volume_db = -10.0
	_click.bus = "Room" if AudioServer.get_bus_index("Room") >= 0 else "Master"
	add_child(_click)


func pick_up() -> void:
	if held or main.game_mode:
		return
	held = true
	_kick = 0.0
	if main.xr_active:
		hand = main.hover_hand
		var h: Node3D = main.left_hand if hand == 0 else main.right_hand
		gun.reparent(h, false)
		gun.transform = Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0.0, 0.02, 0.02))   # (the controller's grip angle)
	else:
		hand = -1
		gun.reparent(main.desktop_cam, false)
		main._draw_on_top(gun)
		gun.transform = Transform3D(Basis(Vector3.UP, 0.08), Vector3(0.14, -0.13, -0.34))
	if main.emu != null:
		main.emu.set_pad(true)
		main.emu.set_gun(true)


func put_down() -> void:
	if not held:
		return
	held = false
	_trigger = false
	_reload = false
	_aux = 0
	gun.reparent(_rest_parent, false)
	gun.transform = _rest_xf
	var mi := gun.get_node("Model") as MeshInstance3D
	mi.material_override = null                   # (back from drawn-on-top)
	if main.emu != null:
		main.emu.set_gun(false)
		main.emu.set_pad(false)
		main.emu.set_buttons(0)


# the trigger: shoots (and kicks), or picks the highlighted game in the menu
func trigger(down: bool) -> void:
	if not held:
		return
	if down and not _trigger:
		_kick = 1.0
		_click.pitch_scale = randf_range(0.95, 1.05)
		_click.play()
	_trigger = down


func reload(down: bool) -> void:
	if held:
		_reload = down
		if down:
			_kick = 0.5


func aux(which: int, down: bool) -> void:
	if not held:
		return
	var bit := 1 << which
	_aux = (_aux | bit) if down else (_aux & ~bit)


# where it points on the TV picture: Vector2 in -1..1 (x right, y down), or null off the screen
func _aim() -> Variant:
	var ui = main.tv_screen_ui
	if ui == null:
		return null
	var o: Vector3
	var d: Vector3
	if hand >= 0:
		o = gun.global_position
		d = -gun.global_transform.basis.z
	else:
		o = main.desktop_cam.global_position
		d = -main.desktop_cam.global_transform.basis.z
	var xf: Transform3D = ui.global_transform
	var n := xf.basis.z.normalized()
	var den := d.dot(n)
	if absf(den) < 0.0001:
		return null
	var t := (xf.origin - o).dot(n) / den
	if t < 0.0 or t > 15.0:
		return null
	var l := xf.affine_inverse() * (o + d * t)
	var half: Vector2 = ui.screen_size * 0.5
	var u := l.x / half.x
	var v := -l.y / half.y
	if absf(u) > 1.0 or absf(v) > 1.0:
		return null
	return Vector2(u, v)


func _process(delta: float) -> void:
	if not held:
		return
	# the kick: up and back, then it settles
	_kick = maxf(0.0, _kick - delta * 6.0)
	var k := _kick * _kick
	var mi := gun.get_node("Model") as Node3D
	mi.rotation.x = 0.45 * k
	mi.position = Vector3(0.0, 0.01 * k, 0.035 * k)
	var e = main.emu
	if e == null:
		return
	var aim = _aim()
	var off := aim == null
	var p: Vector2 = Vector2.ZERO if off else aim
	var b := (1 if _trigger else 0) | (2 if off else 0) | (4 if _reload else 0) | (8 if (_aux & 1) else 0) | (16 if (_aux & 2) else 0)
	e.gun_aim(p, b)
	# the menus: the pad keys / stick as usual, and the trigger picks
	var lh: Node = main.left_hand if main.xr_active else null
	var rh: Node = main.right_hand if main.xr_active else null
	var mask: int = main.padmap.mask(main.xr_active, lh, rh) | main.padmap.nav_mask(main.xr_active, lh, rh)
	if e.state != Emu.State.RUNNING and _trigger:
		mask |= Emu.B_A
	e.set_buttons(mask)


static func _make_click() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.09)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 70.0)
		var v := (rng.randf_range(-1.0, 1.0) * 0.6 + sin(t * TAU * 1900.0) * 0.4) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
