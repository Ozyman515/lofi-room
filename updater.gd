extends Node
## Checks GitHub for a newer version of the room and installs only the files that changed.
## update.json (published with every release) lists each updatable file with its SHA-256; anything that differs
## from what is on disk is downloaded, verified and copied over. Carts, ROMs, saves and settings are never touched.

signal changed

var base := "https://raw.githubusercontent.com/Ozyman515/lofi-room/main/"
const SKIP_PREFIXES := ["carts/", ".godot/", ".git/", "addons/godot-vlc/bin/", "tools/"]

var state := "idle"            # idle, checking, current, available, downloading, done, error
var message := ""
var local_version := 0
var remote_version := 0
var _manifest := {}
var _todo: Array = []          # relative paths to download
var _stage_dir := "user://update_stage"
var _http: HTTPRequest
var _total := 0
var _toast: Label


func _ready() -> void:
	local_version = _read_version()
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_toast = Label.new()
	_toast.visible = false
	_toast.position = Vector2(16, 12)
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_toast.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.2))
	_toast.add_theme_constant_override("outline_size", 6)
	layer.add_child(_toast)
	get_tree().create_timer(4.0).timeout.connect(check)


func _root() -> String:
	return ProjectSettings.globalize_path("res://")


func _read_version() -> int:
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	return int(f.get_as_text().strip_edges()) if f != null else 0


func _state(s: String, m: String) -> void:
	state = s
	message = m
	changed.emit()


func _ok_path(p: String) -> bool:
	if p == "" or p.begins_with("/") or p.contains("..") or p.contains("\\") or p.contains(":"):
		return false
	if p == "project.godot" or p.ends_with(".import") or p.ends_with(".uid"):
		return false
	for s in SKIP_PREFIXES:
		if p.begins_with(s):
			return false
	return true


func busy() -> bool:
	return state == "checking" or state == "downloading"


# Look for a newer version (called at start-up and from the Settings window).
func check() -> void:
	if busy():
		return
	_state("checking", "Checking for updates...")
	_http.download_file = ""
	if _http.request_completed.is_connected(_on_check_done):
		_http.request_completed.disconnect(_on_check_done)
	_http.request_completed.connect(_on_check_done, CONNECT_ONE_SHOT)
	var err := _http.request(base + "update.json?t=%d" % int(Time.get_unix_time_from_system()))
	if err != OK:
		_state("error", "Could not reach the update server.")


func _on_check_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_state("error", "Could not check for updates (offline?).")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not data.has("files"):
		_state("error", "The update list looks wrong. Try again later.")
		return
	_manifest = data["files"]
	remote_version = int(data.get("version", 0))
	_todo.clear()
	var root := _root()
	for p in _manifest:
		var path := str(p)
		if not _ok_path(path):
			continue
		var abs := root.path_join(path)
		if not FileAccess.file_exists(abs) or FileAccess.get_sha256(abs) != str(_manifest[p]["sha"]):
			_todo.append(path)
	_total = _todo.size()
	if _todo.is_empty():
		_state("current", "You are up to date (version %d)." % local_version)
	else:
		_state("available", "Update available: version %d (%d files)." % [remote_version, _total])
		_toast.text = "Update available: version %d.  Open the PC > Settings to install it." % remote_version
		_toast.visible = true
		get_tree().create_timer(14.0).timeout.connect(func() -> void: _toast.visible = false)


# Download everything that changed, check each file, then copy it into place.
func install() -> void:
	if state != "available" or _todo.is_empty():
		return
	_toast.visible = false
	_state("downloading", "Downloading 0 / %d ..." % _total)
	DirAccess.make_dir_recursive_absolute(_stage_dir)
	var staged: Array = []
	for path in _todo.duplicate():
		var dest: String = _stage_dir.path_join(path.replace("/", "__"))
		_http.download_file = dest
		var err := _http.request(base + path.uri_encode().replace("%2F", "/"))
		if err != OK:
			return _fail("Download failed: " + path)
		var res: Array = await _http.request_completed
		if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
			return _fail("Download failed: " + path)
		if FileAccess.get_sha256(dest) != str(_manifest[path]["sha"]):
			return _fail("A downloaded file did not check out: " + path)
		staged.append(path)
		_state("downloading", "Downloading %d / %d ..." % [staged.size(), _total])
	_http.download_file = ""
	var root := _root()
	for path in staged:
		var dest_abs: String = root.path_join(path)
		DirAccess.make_dir_recursive_absolute(dest_abs.get_base_dir())
		var src: String = ProjectSettings.globalize_path(_stage_dir.path_join(path.replace("/", "__")))
		if DirAccess.copy_absolute(src, dest_abs) != OK:
			return _fail("Could not write " + path + " (is it open?)")
		DirAccess.remove_absolute(src)
	_todo.clear()
	local_version = _read_version()
	_state("done", "Updated to version %d. Close and reopen the room to use it." % remote_version)


func _fail(m: String) -> void:
	_http.download_file = ""
	_state("error", m)
