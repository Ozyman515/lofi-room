extends Node3D
## A TV of a room's own (the living room's flat screen, the theater's big screen). It has its own player (a VCR
## on a shelf nearby: point at the tape slot to pick a video) and its own sound, out of its own speakers, so each
## TV can play something different. While it has no tape of its own it shows whatever is on the game room's TV
## (that one is the TV shared with friends in a room), as a clean flat picture.
## Point at the screen while its own menus are up to use them; V / B / Y zooms in on it like any screen.

const VCR := preload("res://vcr.gd")
const ScreenUI := preload("res://screen_ui.gd")

var main: Node3D
var bus := ""
var size := Vector2.ONE
var vcr: Node3D
var ui: ScreenUI
var screen: MeshInstance3D
var own_mat: ShaderMaterial              # driven by its own player and menus
var mirror_mat: ShaderMaterial           # a copy of the game room TV's picture
var speakers: Array[int] = []            # speaker bank indices that play this TV
var showing_own := false
var _params: Array = []
var _glow: OmniLight3D
var _glow_energy := 1.0


# screen_xf: the screen's centre, local +z out of the picture; vcr_xf: where the player sits (its front is +z)
func build(m: Node3D, parent: Node3D, bus_name: String, screen_xf: Transform3D, screen_size: Vector2, vcr_xf: Transform3D,
		curve := 0.0) -> void:
	main = m
	bus = bus_name
	size = screen_size
	name = "RoomTV_" + bus_name
	parent.add_child(self)
	var holder := Node3D.new()
	holder.transform = screen_xf
	add_child(holder)
	var q := QuadMesh.new()
	q.size = screen_size
	own_mat = ShaderMaterial.new()
	own_mat.shader = load("res://shaders/crt.gdshader")
	own_mat.set_shader_parameter("crt_mode", 0)
	own_mat.set_shader_parameter("screen_aspect", screen_size.x / screen_size.y)
	mirror_mat = ShaderMaterial.new()
	mirror_mat.shader = own_mat.shader
	screen = MeshInstance3D.new()
	screen.mesh = q
	screen.material_override = mirror_mat
	screen.position = Vector3(0, 0, 0.002)
	holder.add_child(screen)
	ui = ScreenUI.new()
	ui.position = Vector3(0, 0, 0.002)
	holder.add_child(ui)
	ui.setup(own_mat, screen_size, Vector2i(1024, int(1024.0 * screen_size.y / screen_size.x)), curve)
	main.screens.append(ui)
	vcr = VCR.new()
	vcr.bus_name = bus_name
	vcr.transform = vcr_xf
	add_child(vcr)
	vcr.setup(own_mat, ui)
	own_mat.set_shader_parameter("crt_mode", 0)
	for b in vcr.buttons:
		b["guest_ok"] = true                  # (it's your own player: a friend's copy plays their own files)
		main.interactables.append(b)
	vcr.power_changed.connect(func(_on: bool) -> void: _route())
	_route()


# a light in front of the screen that glows while it's on
func add_glow(l: OmniLight3D) -> void:
	_glow = l
	_glow_energy = l.light_energy


func set_power(on: bool) -> void:
	if vcr.tv_on != on:
		vcr.toggle_tv()


func is_on() -> bool:
	return vcr.tv_on


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var v = vcr
	var own: bool = v.has_tape or v.state != v.State.IDLE
	if own != showing_own:
		showing_own = own
		screen.material_override = own_mat if own else mirror_mat
		_route()
	if not own:
		_mirror()
	if _glow != null:
		_glow.visible = v.tv_on
		_glow.light_energy = _glow_energy


func _mirror() -> void:
	var src: ShaderMaterial = main.tv_mat
	if src == null:
		return
	if _params.is_empty():
		for u in (src.shader as Shader).get_shader_uniform_list():
			var n := str(u["name"])
			if n != "crt_mode" and n != "screen_aspect" and n != "tv_power":
				_params.append(n)
	for n in _params:
		mirror_mat.set_shader_parameter(n, src.get_shader_parameter(n))
	mirror_mat.set_shader_parameter("crt_mode", 0)
	mirror_mat.set_shader_parameter("screen_aspect", size.x / size.y)
	var pw = src.get_shader_parameter("tv_power")
	mirror_mat.set_shader_parameter("tv_power", (float(pw) if pw != null else 1.0) if vcr.tv_on else 0.0)


# its speakers play its own tape, or the game room TV's sound while it's showing that
func _route() -> void:
	for i in speakers:
		main.bank.set_tv_bus(i, bus if showing_own else "TV")
