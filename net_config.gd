extends RefCounted
## Multiplayer settings. The server address is one setting: [net] server in user://lofi_room.cfg,
## or the environment variable LOFI_SERVER (handy for testing against a local server).

const SETTINGS_FILE := "user://lofi_room.cfg"
const DEFAULT_SERVER := "ws://127.0.0.1:8787"     # replace with the real wss:// address once the server is deployed
const STUN := "stun:stun.cloudflare.com:3478"
const MAX_PLAYERS := 4


static func server_url() -> String:
	var env := OS.get_environment("LOFI_SERVER")
	if env != "":
		return env
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_FILE) == OK:
		return str(cf.get_value("net", "server", DEFAULT_SERVER))
	return DEFAULT_SERVER


static func player_name() -> String:
	var env := OS.get_environment("LOFI_NAME")
	if env != "":
		return env
	var cf := ConfigFile.new()
	cf.load(SETTINGS_FILE)
	var n := str(cf.get_value("net", "name", ""))
	if n == "":
		n = "Guest-%04d" % (randi() % 10000)
		cf.set_value("net", "name", n)
		cf.save(SETTINGS_FILE)
	return n


static func ice_servers() -> Array:
	var servers: Array = [{"urls": [STUN]}]
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_FILE) == OK and str(cf.get_value("net", "turn_url", "")) != "":
		servers.append({"urls": [str(cf.get_value("net", "turn_url"))],
			"username": str(cf.get_value("net", "turn_user", "")),
			"credential": str(cf.get_value("net", "turn_pass", ""))})
	return servers


# Both sides must run the same build; the server compares these strings.
static func build_version() -> String:
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	if f == null:
		return "dev"
	return f.get_as_text().strip_edges()
