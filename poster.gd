extends Node3D
## The poster on the right wall. Point at it to pick any picture from your Pictures folder (or anywhere else)
## and it hangs there instead; the frame reshapes to the picture's proportions. Until you pick one (or after
## "Room posters"), a random picture from res://posters/ hangs there, a new one each visit. The choice is kept
## in user://lofi_room.cfg. In a shared room a host can let guests see the host's poster (show_remote).
## Local frame: origin on the wall at the poster's centre, +z out into the room, +x across, +y up.

const ScreenUI := preload("res://screen_ui.gd")
const FileBrowser := preload("res://file_browser.gd")

const POSTER_DIR := "res://posters"          # the room's own posters (not imported: loaded as plain pictures)
const DEFAULT_SIZE := Vector2(0.54, 0.92)     # where the picker sits before anything is loaded
const MAX_H := 0.92                           # a picture is at most this tall...
const MAX_W := 1.0                            # ...and this wide (a landscape one goes wide, then shrinks)
const MARGIN := 0.04                          # frame border round the picture
const MAX_PX := 2048                          # big photos are scaled down to this on their long side
const EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]
const CFG := "user://lofi_room.cfg"

var frame: MeshInstance3D
var picture: MeshInstance3D
var ui: ScreenUI
var picking := false
var _mat: StandardMaterial3D
var _frame_mesh: BoxMesh
var _pic_mesh: QuadMesh
var _browser: FileBrowser
var _note: Label
var _ui_mesh: MeshInstance3D
var current_path := ""                        # "" = one of the room's posters
var current_image: Image                      # what's hanging now (for sharing with guests)
var revision := 0                             # goes up every time the picture changes
var remote_from := ""                         # the host's name while their poster is shown here
var _own: Array = []                          # [texture, size, image] of my own choice, while a host's is shown


func build(frame_mat: Material) -> void:
	_frame_mesh = BoxMesh.new()
	frame = MeshInstance3D.new()
	frame.mesh = _frame_mesh
	frame.material_override = frame_mat
	add_child(frame)
	_mat = StandardMaterial3D.new()
	_mat.disable_fog = true                      # fog is only for the city outside
	_mat.roughness = 1.0
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = 0.35
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_pic_mesh = QuadMesh.new()
	picture = MeshInstance3D.new()
	picture.mesh = _pic_mesh
	picture.material_override = _mat
	picture.position = Vector3(0, 0, 0.045)
	add_child(picture)
	_build_picker()
	var cf := ConfigFile.new()
	var saved := ""
	if cf.load(CFG) == OK:
		saved = str(cf.get_value("poster", "path", ""))
	if saved == "" or not _apply_file(saved, false):
		_apply_default()


# ---- the picture

# the room's own posters, one at random
static func room_posters() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(POSTER_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() in EXTS:
			out.append(POSTER_DIR.path_join(f))
	out.sort()
	return out


func _apply_default() -> void:
	var list := room_posters()
	list.shuffle()
	for path in list:
		if _apply_file(path, false):
			current_path = ""
			return
	# nothing usable: a plain board
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(0.25, 0.12, 0.3))
	_show_image(img)
	current_path = ""


func _apply_file(path: String, remember := true) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return false
	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 2:
		return false
	var long_side := maxi(w, h)
	if long_side > MAX_PX:
		var k := float(MAX_PX) / long_side
		img.resize(maxi(1, int(w * k)), maxi(1, int(h * k)), Image.INTERPOLATE_LANCZOS)
	_show_image(img)
	current_path = path
	if remember:
		_remember(path)
	return true


func _show_image(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	current_image = img.duplicate()
	var shown := img.duplicate() as Image
	shown.generate_mipmaps()
	var aspect := float(img.get_width()) / float(img.get_height())
	if remote_from != "":
		_own = [ImageTexture.create_from_image(shown), fit_size(aspect), current_image]
		return                                   # a host's poster is up: mine changes underneath it
	_set_texture(ImageTexture.create_from_image(shown), fit_size(aspect))
	revision += 1


# ---- a host's poster, shown to guests when the host allows it

func show_remote(img: Image, host_name: String) -> void:
	if remote_from == "":
		_own = [_mat.albedo_texture, _pic_mesh.size, current_image]
	remote_from = host_name
	var shown := img.duplicate() as Image
	if shown.get_format() != Image.FORMAT_RGBA8 and shown.get_format() != Image.FORMAT_RGB8:
		shown.convert(Image.FORMAT_RGBA8)
	shown.generate_mipmaps()
	_set_texture(ImageTexture.create_from_image(shown), fit_size(float(img.get_width()) / float(img.get_height())))
	close_picker()


func clear_remote() -> void:
	if remote_from == "":
		return
	remote_from = ""
	if _own.size() == 3:
		_set_texture(_own[0], _own[1])
		current_image = _own[2]
	_own = []


# the picture as JPEG for sending (at most 1024 px on its long side)
func shared_jpeg() -> PackedByteArray:
	if current_image == null:
		return PackedByteArray()
	var img := current_image.duplicate() as Image
	var long_side := maxi(img.get_width(), img.get_height())
	if long_side > 1024:
		var k := 1024.0 / long_side
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img.save_jpg_to_buffer(0.85)


# the picture's size on the wall for a width / height ratio
static func fit_size(aspect: float) -> Vector2:
	var h := MAX_H
	var w := h * aspect
	if w > MAX_W:
		w = MAX_W
		h = w / aspect
	return Vector2(w, h)


# ---- a poster that takes over for a while (Noir Night's), with whatever was there kept underneath

var _override_on := false
var _under: Array = []                        # [texture, size] to put back


func show_override(img: Image) -> void:
	if not _override_on:
		_under = [_mat.albedo_texture, _pic_mesh.size]
	_override_on = true
	var shown := img.duplicate() as Image
	if shown.get_format() != Image.FORMAT_RGBA8 and shown.get_format() != Image.FORMAT_RGB8:
		shown.convert(Image.FORMAT_RGBA8)
	shown.generate_mipmaps()
	_apply_tex(ImageTexture.create_from_image(shown), fit_size(float(img.get_width()) / float(img.get_height())))
	close_picker()


func clear_override() -> void:
	if not _override_on:
		return
	_override_on = false
	if _under.size() == 2:
		_apply_tex(_under[0], _under[1])
	_under = []


func _set_texture(tex: Texture2D, size: Vector2) -> void:
	if _override_on:
		_under = [tex, size]                       # changes wait underneath until the override ends
		return
	_apply_tex(tex, size)


func _apply_tex(tex: Texture2D, size: Vector2) -> void:
	_mat.albedo_texture = tex
	_mat.emission_texture = tex
	_pic_mesh.size = size
	_frame_mesh.size = Vector3(size.x + MARGIN * 2.0, size.y + MARGIN * 2.0, 0.03)
	frame.position = Vector3(0, 0, 0.015)
	if _ui_mesh != null:
		_place_picker(size)


func _remember(path: String) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("poster", "path", path)
	cf.save(CFG)


func use_original() -> void:
	_apply_default()
	_remember("")
	close_picker()


# ---- picking a picture (a panel that floats just in front of the poster)

func _build_picker() -> void:
	var size := Vector2(0.9, 0.62)
	var quad := QuadMesh.new()
	quad.size = size
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/screen.gdshader")
	_ui_mesh = MeshInstance3D.new()
	_ui_mesh.mesh = quad
	_ui_mesh.material_override = sm
	add_child(_ui_mesh)
	ui = ScreenUI.new()
	add_child(ui)
	ui.setup(sm, size, Vector2i(840, 580), 0.0)
	_place_picker(DEFAULT_SIZE)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.text = "POSTER  -  pick a picture"
	v.add_child(title)
	_note = Label.new()
	_note.text = "Any picture works; the frame takes its shape."
	v.add_child(_note)
	_browser = FileBrowser.new()
	_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_browser)
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	_browser.setup(PackedStringArray(EXTS), "pictures", [["Pictures", pics], ["Downloads", OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)], ["Desktop", OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)]], pics)
	_browser.file_chosen.connect(_on_chosen)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var orig := Button.new()
	orig.text = "Room posters (a random one)"
	orig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orig.pressed.connect(use_original)
	row.add_child(orig)
	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(close_picker)
	row.add_child(close)
	close_picker()


# the panel stands a little out from the wall, centred on the poster, so it never sinks into it
func _place_picker(_size: Vector2) -> void:
	_ui_mesh.position = Vector3(0, 0, 0.22)
	ui.position = _ui_mesh.position + Vector3(0, 0, 0.0005)


func open_picker() -> void:
	picking = true
	_ui_mesh.visible = true
	ui.enabled = true
	_note.text = "Any picture works; the frame takes its shape."
	_browser.navigate(_browser.current_dir)          # pick up pictures added since last time


func close_picker() -> void:
	picking = false
	_ui_mesh.visible = false
	ui.enabled = false
	ui.clear_hover()


func toggle_picker() -> void:
	if remote_from != "" or _override_on:
		return                                     # the host's poster: nothing to pick here
	if picking:
		close_picker()
	else:
		open_picker()


func _on_chosen(path: String) -> void:
	if _apply_file(path):
		close_picker()
	else:
		_note.text = "Couldn't open that picture. Try a PNG or JPG."


func label() -> String:
	if _override_on:
		return "THE CITY NEVER SLEEPS"
	if remote_from != "":
		return "%s'S POSTER" % remote_from.to_upper()
	if picking:
		return "POSTER  (close the picker)"
	return "POSTER  (pick a picture)"
