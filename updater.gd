extends Node
const Plat := preload("res://platform.gd")
## Checks GitHub for a newer version of the room and installs only the files that changed.
## update.json (published with every release) lists each updatable file with its SHA-256; anything that differs
## from what is on disk is downloaded, verified and copied over. Carts, ROMs, saves and settings are never touched.
## update.json itself must carry a valid signature (update.json.sig) from the release key whose public half ships
## with the room as update_key.pub: a release nobody signed, or one tampered with on the way, is refused outright.

signal changed

var base := "https://raw.githubusercontent.com/Ozyman515/lofi-room/main/"
# .godot/imported (and the small .godot/*.cfg files) ARE updated: the exe build runs the loose project and needs them;
# the editor just regenerates identical ones. Only the editor's own caches stay out.
const SKIP_PREFIXES := ["carts/", ".godot/editor/", ".godot/shader_cache/", ".godot/exported/", ".git/", "addons/godot-vlc/bin/", "addons/webrtc/lib/", "server/", "tools/", "books/", "pack/"]

var state := "idle"            # idle, checking, current, available, downloading, done, error
var message := ""
var local_version := 0
var remote_version := 0
var _manifest := {}
var _todo: Array = []          # relative paths to download
var _remove: Array = []        # files a release says to delete (e.g. a song that changed format)
var _stage_dir := "user://update_stage"
var _http: HTTPRequest
var _pending_body := PackedByteArray()     # update.json, kept until its signature has been checked
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
	if p == "project.godot" or p == "update_key.pub" or p.ends_with(".uid"):
		return false                      # the signing key can only change with a fresh install
	# other platforms' binaries: a Windows copy never needs the Linux ones, and the other way round
	if OS.get_name() == "Windows" and (p.ends_with(".so") or p == "bin/retro_host_linux"):
		return false
	if OS.get_name() != "Windows" and (p.ends_with(".dll") or p.ends_with(".exe")):
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
	if not Plat.can_self_update():              # the headset app can't change its own files: updates arrive as a new install
		_state("current", "Updates on this headset come as a new install of the app.")
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
		_state("error", "Could not check for updates (result %d, http %d)." % [result, code])
		_log("check failed: result %d http %d" % [result, code])
		return
	# the signature travels separately; nothing is trusted until it checks out
	_pending_body = body
	if _http.request_completed.is_connected(_on_sig_done):
		_http.request_completed.disconnect(_on_sig_done)
	_http.request_completed.connect(_on_sig_done, CONNECT_ONE_SHOT)
	if _http.request(base + "update.json.sig?t=%d" % int(Time.get_unix_time_from_system())) != OK:
		_state("error", "Could not reach the update server.")


func _on_sig_done(result: int, code: int, _h: PackedStringArray, sig_body: PackedByteArray) -> void:
	var body := _pending_body
	_pending_body = PackedByteArray()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_state("error", "This update is not signed. Not installing it.")
		return
	if not _signature_ok(body, sig_body):
		_state("error", "This update's signature does not check out. Not installing it.")
		push_warning("update.json signature rejected")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not data.has("files"):
		_state("error", "The update list looks wrong. Try again later.")
		return
	_manifest = data["files"]
	remote_version = int(data.get("version", 0))
	_todo.clear()
	_remove.clear()
	for r in data.get("remove", []):
		if _ok_path(str(r)):
			_remove.append(str(r))
	if remote_version <= local_version:
		_total = 0
		_state("current", "You are up to date (version %d)." % local_version)       # never go back to an older list
		return
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
		show_toast("Update available: version %d.  Take a nap in the bed to install it and wake up in the new room (or use PC > Settings)." % remote_version, 14.0)


# RSA (PKCS#1 v1.5, SHA-256) over the exact bytes of update.json, against the public key that ships with the room
static func _signature_ok(body: PackedByteArray, sig_text: PackedByteArray) -> bool:
	var pub := CryptoKey.new()
	if pub.load("res://update_key.pub", true) != OK:
		return false
	var sig := Marshalls.base64_to_raw(sig_text.get_string_from_utf8().strip_edges())
	if sig.is_empty():
		return false
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	return Crypto.new().verify(HashingContext.HASH_SHA256, ctx.finish(), sig, pub)


func show_toast(msg: String, secs: float = 8.0) -> void:
	_toast.text = msg
	_toast.visible = true
	var tag := msg
	get_tree().create_timer(secs).timeout.connect(func() -> void:
		if _toast.text == tag:
			_toast.visible = false)


# Download everything that changed, check each file, then copy it into place.
func install() -> void:
	if not Plat.can_self_update():
		return
	if state != "available" or _todo.is_empty():
		return
	_toast.visible = false
	_state("downloading", "Downloading 0 / %d ..." % _total)
	DirAccess.make_dir_recursive_absolute(_stage_dir)
	var staged: Array = []
	for path in _todo.duplicate():
		var dest: String = _stage_dir.path_join(path.replace("/", "__"))
		var url: String = base + String(path).uri_encode().replace("%2F", "/")
		var want: String = str(_manifest[path]["sha"])
		var ok := false
		for attempt in 2:
			# the web cache can hand out an older copy for a few minutes, so ask for this exact file version
			var q: String = "?h=" + want.substr(0, 12) + ("" if attempt == 0 else "&t=%d" % Time.get_ticks_msec())
			_http.download_file = dest
			var err := _http.request(url + q)
			if err != OK:
				return _fail("Download failed: " + path)
			var res: Array = await _http.request_completed
			if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
				return _fail("Download failed: %s (result %d, http %d)" % [path, int(res[0]), int(res[1])])
			if FileAccess.get_sha256(dest) == want:
				ok = true
				break
		if not ok:
			return _fail("A downloaded file did not check out: " + path + " (the web cache may be behind - try again in a few minutes)")
		staged.append(path)
		_state("downloading", "Downloading %d / %d ..." % [staged.size(), _total])
	_http.download_file = ""
	var root := _root()
	for path in staged:
		var dest_abs: String = root.path_join(path)
		DirAccess.make_dir_recursive_absolute(dest_abs.get_base_dir())
		var src: String = ProjectSettings.globalize_path(_stage_dir.path_join(path.replace("/", "__")))
		var cerr := DirAccess.copy_absolute(src, dest_abs)
		if cerr != OK:
			return _fail("Could not write %s (error %d: is the folder read-only, or the file open?)" % [path, cerr])
		DirAccess.remove_absolute(src)
	for path in _remove:
		var gone: String = root.path_join(path)
		if FileAccess.file_exists(gone):
			DirAccess.remove_absolute(gone)
	_todo.clear()
	local_version = _read_version()
	_log("installed version %d (%d files)" % [remote_version, staged.size()])
	_state("done", "Updated to version %d. Take a nap in the bed to wake up in the new room (or close and reopen)." % remote_version)


func _fail(m: String) -> void:
	_http.download_file = ""
	_state("error", m)
	_log(m)


# user://updater.log keeps the last few outcomes, so a failing copy can be diagnosed from one file
func _log(m: String) -> void:
	var f := FileAccess.open("user://updater.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://updater.log") else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s  v%d  %s  root=%s" % [Time.get_datetime_string_from_system(), local_version, m, _root()])
	f.close()
