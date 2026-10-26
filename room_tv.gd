extends Node3D
## A TV of a room's own (the living room's Big TV, the Theater Screen). It has its own player (a VCR on a shelf
## nearby: point at the tape slot to pick a video) and its own sound bus, played by the speakers in its room that
## are set to it, so each TV is separate and can play something different.
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
var speakers: Array[int] = []            # speaker bank indices in its room (they're set to it by default)
var _glow: Light3D
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
	screen = MeshInstance3D.new()
	screen.mesh = q
	screen.material_override = own_mat
	screen.position = Vector3(0, 0, 0.002)
	holder.add_child(screen)
	ui = ScreenUI.new()
	ui.position = Vector3(0, 0, 0.002)
	holder.add_child(ui)
	ui.setup(own_mat, screen_size, Vector2i(int(768.0 * screen_size.x / screen_size.y), 768), curve)   # (the same text size as the old TV's)
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


# a light in front of the screen that glows while it's on
func add_glow(l: Light3D) -> void:
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
	if _glow != null:
		_glow.visible = vcr.tv_on
		_glow.light_energy = _glow_energy
