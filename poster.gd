extends Node3D
## The poster on the right wall. Point at it to pick any picture from your Pictures folder (or anywhere else)
## and it hangs there instead; the frame reshapes to the picture's proportions. "Original poster" puts the
## 90s anime poster back. The choice is kept in user://lofi_room.cfg.
## Local frame: origin on the wall at the poster's centre, +z out into the room, +x across, +y up.

const ScreenUI := preload("res://screen_ui.gd")
const FileBrowser := preload("res://file_browser.gd")

const DEFAULT_TEX := "res://textures/poster.png"
const DEFAULT_SIZE := Vector2(0.54, 0.92)     # the original poster's picture, metres
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
var current_path := ""                        # "" = the original poster


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

func _apply_default() -> void:
	var tex: Texture2D = load(DEFAULT_TEX)
	_set_texture(tex, DEFAULT_SIZE)
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
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	_set_texture(ImageTexture.create_from_image(img), fit_size(float(w) / float(h)))
	current_path = path
	if remember:
		_remember(path)
	return true


# the picture's size on the wall for a width / height ratio
static func fit_size(aspect: float) -> Vector2:
	var h := MAX_H
	var w := h * aspect
	if w > MAX_W:
		w = MAX_W
		h = w / aspect
	return Vector2(w, h)


func _set_texture(tex: Texture2D, size: Vector2) -> void:
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
	orig.text = "Original poster"
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
	if picking:
		return "POSTER  (close the picker)"
	return "POSTER  (pick a picture)"
