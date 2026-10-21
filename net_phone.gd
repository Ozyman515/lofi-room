extends Node3D
## The phone on the wall: "chill with buddy bois". Its screen is the whole multiplayer interface
## (host a room, join with a code, who is here, kick, leave). VR has no keyboard, so the code is
## typed on an on-screen letter grid.

const ScreenUI := preload("res://screen_ui.gd")
const Cfg := preload("res://net_config.gd")

const SCREEN_M := Vector2(0.23, 0.445)
const SCREEN_PX := Vector2i(300, 580)
const LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var net: Node
var ui: ScreenUI
var case_node: Node3D
var _page := "home"          # home | join
var _entry := ""
var _content: VBoxContainer
var _code_label: Label
var _note := ""


func build(session: Node, add_interactable: Callable) -> void:
	net = session
	# case + a little hanging plate behind it
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.13, 0.06, 0.2)
	body.roughness = 0.4
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.3, 0.12, 0.34)
	plate.roughness = 0.7
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color(1.0, 0.45, 0.8)
	rim.emission_enabled = true
	rim.emission = Color(1.0, 0.45, 0.8)
	rim.emission_energy_multiplier = 1.6
	case_node = _box(Vector3(0, 0, 0.0), Vector3(0.27, 0.5, 0.03), body)
	_box(Vector3(0, 0, 0.012), Vector3(0.31, 0.54, 0.008), plate)
	_box(Vector3(0, 0.252, -0.0155), Vector3(0.1, 0.006, 0.004), rim)      # glowing speaker slit above the screen
	var quad := QuadMesh.new()
	quad.size = SCREEN_M
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/screen.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = sm
	mi.position = Vector3(0, -0.005, -0.0155)
	mi.rotation.y = PI
	add_child(mi)
	ui = ScreenUI.new()
	ui.position = Vector3(0, -0.005, -0.0156)
	ui.rotation.y = PI
	add_child(ui)
	ui.setup(sm, SCREEN_M, SCREEN_PX, 0.0)
	_build_ui()
	net.state_changed.connect(_render)
	net.roster_changed.connect(_render)
	_render()
	add_interactable.call({"node": case_node, "half": Vector3(0.14, 0.26, 0.012), "when": func() -> bool: return visible,
		"label": func() -> String: return "CHILL WITH BUDDY BOIS", "cb": func() -> void: pass, "guest_ok": true})


func _box(pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	b.mesh = bm
	b.material_override = m
	b.position = pos
	add_child(b)
	return b


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.04, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.root.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = 16
	col.offset_bottom = -14
	col.add_theme_constant_override("separation", 10)
	ui.root.add_child(col)
	var title := Label.new()
	title.text = "chill with\nbuddy bois"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.85))
	col.add_child(title)
	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	col.add_child(_content)


func _label(text: String, size := 22, color := Color(0.95, 0.9, 1.0), parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	(parent if parent != null else _content).add_child(l)
	return l


func _button(text: String, cb: Callable, size := 26, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 52)
	b.pressed.connect(cb)
	(parent if parent != null else _content).add_child(b)
	return b


func _render() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_code_label = null
	match net.state:
		net.State.OFFLINE:
			if _page == "join":
				_render_join()
			else:
				_render_home()
		net.State.CONNECTING, net.State.JOINING:
			_label(net.status, 24)
			_button("CANCEL", func() -> void: net.leave())
		net.State.HOSTING:
			_label("ROOM CODE", 20, Color(0.7, 0.6, 0.9))
			_label(net.code, 50, Color(1.0, 0.95, 0.5))
			_label("Tell your buddy bois this code.", 18, Color(0.7, 0.6, 0.9))
			_render_players(true)
			_button("CLOSE ROOM", func() -> void: net.leave())
		net.State.JOINED:
			_label("In %s's room" % str(net.roster.get(1, {}).get("name", "the")), 24)
			if net.host_away:
				_label("Host is away...", 20, Color(1.0, 0.8, 0.5))
			_render_players(false)
			_button("LEAVE", func() -> void: net.leave())


func _render_home() -> void:
	if net.status != "":
		_label(net.status, 20, Color(1.0, 0.7, 0.6))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(sp)
	_button("HOST A ROOM", func() -> void:
		net.status = ""
		net.host_room())
	_button("JOIN A ROOM", func() -> void:
		net.status = ""
		_entry = ""
		_page = "join"
		_render())
	_label("Friends can play with you in this room.", 16, Color(0.7, 0.6, 0.9))


func _render_join() -> void:
	_code_label = _label(_shown_code(), 40, Color(1.0, 0.95, 0.5))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)
	for ch in LETTERS:
		var b := Button.new()
		b.text = ch
		b.custom_minimum_size = Vector2(36, 36)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_type.bind(ch))
		_slim(b)
		grid.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_content.add_child(row)
	for spec in [["DEL", func() -> void: _entry = _entry.left(maxi(0, _entry.length() - 1)); _refresh_code()],
			["BACK", func() -> void: _page = "home"; _render()]]:
		var b := _button(spec[0], spec[1], 22, row)
		b.custom_minimum_size.y = 44
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var go := _button("JOIN", func() -> void:
		if _entry.length() == 6:
			net.status = ""
			net.join_room(_entry), 30)
	go.name = "Go"
	go.custom_minimum_size.y = 46
	if net.status != "":
		_label(net.status, 18, Color(1.0, 0.7, 0.6))


func _shown_code() -> String:
	var s := _entry
	while s.length() < 6:
		s += "_"
	return " ".join(s.split(""))


func _type(ch: String) -> void:
	if _entry.length() < 6:
		_entry += ch
		_refresh_code()


func _refresh_code() -> void:
	if _code_label != null:
		_code_label.text = _shown_code()


func _render_players(can_kick: bool) -> void:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	_content.add_child(box)
	for id in net.roster:
		var row := HBoxContainer.new()
		box.add_child(row)
		var n := Label.new()
		n.text = ("%s%s" % [net.roster[id]["name"], "  (host)" if id == 1 else ""])
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.add_theme_font_size_override("font_size", 22)
		n.add_theme_color_override("font_color", net.roster[id].get("color", Color.WHITE))
		row.add_child(n)
		if can_kick and id != 1:
			var k := Button.new()
			k.text = "KICK"
			k.add_theme_font_size_override("font_size", 18)
			k.pressed.connect(func() -> void: net.kick(id))
			row.add_child(k)


# the theme's buttons have wide padding; letter keys need to fit seven across
func _slim(b: Button) -> void:
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = (ui.root.theme.get_stylebox(st, "Button") as StyleBoxFlat).duplicate()
		sb.content_margin_left = 1.0
		sb.content_margin_right = 1.0
		b.add_theme_stylebox_override(st, sb)
