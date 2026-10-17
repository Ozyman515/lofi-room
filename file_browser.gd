extends VBoxContainer
## Folder/file picker for the in-room UIs. Click a folder to open it, click a file to choose it.

signal file_chosen(path: String)

const CFG := "user://lofi_room.cfg"

var extensions: PackedStringArray = PackedStringArray()
var settings_key := "browser"
var current_dir := ""
var _path_label: Label
var _list: ItemList
var _entries: Array = []     # [{"path": String, "dir": bool}]


func setup(exts: PackedStringArray, key: String, shortcuts: Array, start_dir: String) -> void:
	extensions = exts
	settings_key = key
	add_theme_constant_override("separation", 8)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var up := Button.new()
	up.text = "Up"
	up.pressed.connect(_go_up)
	bar.add_child(up)
	for s in shortcuts:
		if str(s[1]) == "":
			continue
		var b := Button.new()
		b.text = str(s[0])
		b.pressed.connect(navigate.bind(str(s[1])))
		bar.add_child(b)
	var drives := Button.new()
	drives.text = "Drives"
	drives.pressed.connect(navigate.bind(""))
	bar.add_child(drives)

	_path_label = Label.new()
	_path_label.clip_text = true
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_path_label)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_clicked.connect(_on_item_clicked)
	add_child(_list)

	var cfg := ConfigFile.new()
	var dir := start_dir
	if cfg.load(CFG) == OK:
		dir = str(cfg.get_value("dirs", settings_key, start_dir))
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = start_dir
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = OS.get_environment("USERPROFILE") if OS.has_environment("USERPROFILE") else OS.get_environment("HOME")
	navigate(dir)


func files_in_dir() -> Array[String]:
	var out: Array[String] = []
	for e in _entries:
		if not bool(e["dir"]):
			out.append(str(e["path"]))
	return out


func navigate(path: String) -> void:
	if path == "":
		_list.clear()
		_entries.clear()
		current_dir = ""
		_path_label.text = "Drives"
		var n := DirAccess.get_drive_count()
		if n == 0:
			_add_entry("/", "[ / ]", true)
		for i in n:
			var d := DirAccess.get_drive_name(i)
			_add_entry(d + "/", "[ " + d + " ]", true)
		return

	var da := DirAccess.open(path)
	if da == null:
		_path_label.text = "Can't open " + path
		return
	var dirs: Array[String] = []
	var files: Array[String] = []
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not fname.begins_with("."):
			if da.current_is_dir():
				dirs.append(fname)
			elif extensions.has(fname.get_extension().to_lower()):
				files.append(fname)
		fname = da.get_next()
	da.list_dir_end()
	dirs.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	files.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)

	_list.clear()
	_entries.clear()
	current_dir = path.simplify_path()
	_path_label.text = current_dir
	_add_entry(_parent_of(current_dir), "[ .. ]", true)
	for d in dirs:
		_add_entry(current_dir.path_join(d), "[ " + d + " ]", true)
	for f in files:
		_add_entry(current_dir.path_join(f), f, false)
	_save_dir()


func _parent_of(path: String) -> String:
	if path == "" or path == "/" or path.ends_with(":/"):
		return ""
	var p := path.get_base_dir()
	if p == path:
		return ""
	return p


func _go_up() -> void:
	navigate(_parent_of(current_dir))


func _add_entry(path: String, label: String, is_dir: bool) -> void:
	_entries.append({"path": path, "dir": is_dir})
	_list.add_item(label)


func _on_item_clicked(index: int, _pos: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT or index < 0 or index >= _entries.size():
		return
	var e: Dictionary = _entries[index]
	if bool(e["dir"]):
		navigate(str(e["path"]))
	else:
		file_chosen.emit(str(e["path"]))


func _save_dir() -> void:
	if current_dir == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("dirs", settings_key, current_dir)
	cfg.save(CFG)
