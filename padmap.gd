extends RefCounted
## What each button of the game pad is bound to: for a gamepad, the keyboard and the VR controllers separately.
## A binding is stored as text: "b:1" gamepad button, "a:4:+" gamepad axis (triggers, sticks), "k:88" key (physical keycode),
## "v:R:ax_button" VR button on a hand, "s:L:u" VR thumbstick direction.

const ACTIONS := ["a", "b", "x", "y", "l", "r", "start", "select", "up", "down", "left", "right"]
const LABELS := {"a": "A", "b": "B", "x": "X", "y": "Y", "l": "L", "r": "R", "start": "START", "select": "SELECT",
	"up": "D-PAD UP", "down": "D-PAD DOWN", "left": "D-PAD LEFT", "right": "D-PAD RIGHT"}
# libretro joypad bits (same as emu.gd)
const BITS := {"b": 1, "y": 2, "select": 4, "start": 8, "up": 16, "down": 32, "left": 64, "right": 128, "a": 256, "x": 512, "l": 1024, "r": 2048}
const PAD_BUTTON_NAMES := {0: "BOTTOM BUTTON", 1: "RIGHT BUTTON", 2: "LEFT BUTTON", 3: "TOP BUTTON", 4: "BACK / SELECT", 5: "GUIDE",
	6: "START / MENU", 7: "LEFT STICK CLICK", 8: "RIGHT STICK CLICK", 9: "LEFT BUMPER", 10: "RIGHT BUMPER", 11: "D-PAD UP",
	12: "D-PAD DOWN", 13: "D-PAD LEFT", 14: "D-PAD RIGHT", 15: "EXTRA BUTTON", 16: "PADDLE 1", 17: "PADDLE 2", 18: "PADDLE 3",
	19: "PADDLE 4", 20: "TOUCHPAD"}
const VR_BUTTONS := ["ax_button", "by_button", "trigger_click", "menu_button", "primary_click"]
const VR_NAMES := {"ax_button": "A / X", "by_button": "B / Y", "trigger_click": "TRIGGER", "menu_button": "MENU", "primary_click": "STICK CLICK"}
const CFG := "user://lofi_room.cfg"

var layout := "position"                  # gamepad face buttons: "position" (bottom = B like the real console) or "label" (A is A)
var maps := {"pad": {}, "key": {}, "vr": {}}   # device -> action -> binding text
var _parsed := {"pad": {}, "key": {}, "vr": {}}


func _init() -> void:
	for d in ["pad", "key", "vr"]:
		maps[d] = defaults(d)
		_reparse(d)
	load_cfg()


# ---------------------------------------------------------------- defaults, saving

func defaults(dev: String) -> Dictionary:
	match dev:
		"pad":
			var a := "b:1"
			var b := "b:0"
			var x := "b:3"
			var y := "b:2"
			if layout == "label":
				a = "b:0"
				b = "b:1"
				x = "b:2"
				y = "b:3"
			return {"a": a, "b": b, "x": x, "y": y, "l": "b:9", "r": "b:10", "start": "b:6", "select": "b:4",
				"up": "b:11", "down": "b:12", "left": "b:13", "right": "b:14"}
		"key":
			return {"a": "k:%d" % KEY_X, "b": "k:%d" % KEY_Z, "x": "k:%d" % KEY_S, "y": "k:%d" % KEY_A, "l": "k:%d" % KEY_Q,
				"r": "k:%d" % KEY_W, "start": "k:%d" % KEY_ENTER, "select": "k:%d" % KEY_BACKSPACE,
				"up": "k:%d" % KEY_UP, "down": "k:%d" % KEY_DOWN, "left": "k:%d" % KEY_LEFT, "right": "k:%d" % KEY_RIGHT}
		_:
			return {"a": "v:R:ax_button", "b": "v:R:by_button", "x": "v:L:by_button", "y": "v:L:ax_button", "l": "v:L:trigger_click",
				"r": "v:R:trigger_click", "start": "v:L:menu_button", "select": "v:L:primary_click",
				"up": "s:L:u", "down": "s:L:d", "left": "s:L:l", "right": "s:L:r"}


func reset(dev: String) -> void:
	maps[dev] = defaults(dev)
	_reparse(dev)
	save_cfg()


func set_layout(l: String) -> void:
	layout = l
	var d := defaults("pad")
	for a in ["a", "b", "x", "y"]:
		maps["pad"][a] = d[a]
	_reparse("pad")
	save_cfg()


func load_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) != OK:
		return
	layout = str(cfg.get_value("pad_map", "layout", "position"))
	if layout != "label":
		layout = "position"
	for d in ["pad", "key", "vr"]:
		var def := defaults(d)
		for a in ACTIONS:
			var v := str(cfg.get_value("pad_" + d, a, def[a]))
			maps[d][a] = v if _parse(v).size() > 0 else def[a]
		_reparse(d)


func save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("pad_map", "layout", layout)
	for d in ["pad", "key", "vr"]:
		for a in ACTIONS:
			cfg.set_value("pad_" + d, a, maps[d][a])
	cfg.save(CFG)


func _reparse(dev: String) -> void:
	var p := {}
	for a in ACTIONS:
		p[a] = _parse(maps[dev][a])
	_parsed[dev] = p


func _parse(s: String) -> Array:
	var parts := s.split(":")
	if parts.size() < 2:
		return []
	match parts[0]:
		"k", "b":
			return [parts[0], int(parts[1])]
		"a":
			if parts.size() >= 3:
				return ["a", int(parts[1]), 1.0 if parts[2] == "+" else -1.0]
		"v", "s":
			if parts.size() >= 3 and (parts[1] == "L" or parts[1] == "R"):
				return [parts[0], parts[1], parts[2]]
	return []


# ---------------------------------------------------------------- reading the pad

func pad_device() -> int:
	var j := Input.get_connected_joypads()
	return int(j[0]) if not j.is_empty() else -1


func has_gamepad() -> bool:
	return pad_device() >= 0


func _down(p: Array, dev_id: int, lh: Node, rh: Node) -> bool:
	if p.is_empty():
		return false
	match p[0]:
		"k":
			return Input.is_physical_key_pressed(p[1])
		"b":
			return dev_id >= 0 and Input.is_joy_button_pressed(dev_id, p[1])
		"a":
			return dev_id >= 0 and Input.get_joy_axis(dev_id, p[1]) * float(p[2]) > 0.55
		"v":
			var h: Node = lh if p[1] == "L" else rh
			return h != null and h.is_button_pressed(p[2])
		"s":
			var hd: Node = lh if p[1] == "L" else rh
			if hd == null:
				return false
			var st: Vector2 = hd.get_vector2("primary")
			match p[2]:
				"u": return st.y > 0.6
				"d": return st.y < -0.6
				"l": return st.x < -0.6
				"r": return st.x > 0.6
	return false


# The current pad state as libretro bits. In VR the VR bindings count, on the desktop the keyboard and the gamepad do.
func mask(xr: bool, lh: Node, rh: Node) -> int:
	var m := 0
	var dev_id := pad_device()
	if xr:
		var pv: Dictionary = _parsed["vr"]
		for a in ACTIONS:
			if _down(pv[a], dev_id, lh, rh):
				m |= int(BITS[a])
	else:
		var pk: Dictionary = _parsed["key"]
		var pp: Dictionary = _parsed["pad"]
		for a in ACTIONS:
			if _down(pk[a], dev_id, lh, rh) or _down(pp[a], dev_id, lh, rh):
				m |= int(BITS[a])
		if dev_id >= 0:                                     # the left stick always works as a d-pad too
			var sx := Input.get_joy_axis(dev_id, JOY_AXIS_LEFT_X)
			var sy := Input.get_joy_axis(dev_id, JOY_AXIS_LEFT_Y)
			if sy < -0.5: m |= 16
			if sy > 0.5: m |= 32
			if sx < -0.5: m |= 64
			if sx > 0.5: m |= 128
	return m


# Fixed controls for the menus: they work whatever the bindings are, so a wrong binding can never lock you out.
# Returns libretro bits: d-pad / stick, any face button or START = A, BACK / stick click = SELECT.
func nav_mask(xr: bool, lh: Node, rh: Node) -> int:
	var m := 0
	if xr:
		var st: Vector2 = lh.get_vector2("primary") if lh != null else Vector2.ZERO
		if st.y > 0.6: m |= 16
		if st.y < -0.6: m |= 32
		if st.x < -0.6: m |= 64
		if st.x > 0.6: m |= 128
		for h in [lh, rh]:
			if h != null and (h.is_button_pressed("ax_button") or h.is_button_pressed("by_button") or h.is_button_pressed("menu_button")):
				m |= 256
			if h != null and h.is_button_pressed("primary_click"):
				m |= 4
		return m
	if Input.is_physical_key_pressed(KEY_UP): m |= 16
	if Input.is_physical_key_pressed(KEY_DOWN): m |= 32
	if Input.is_physical_key_pressed(KEY_LEFT): m |= 64
	if Input.is_physical_key_pressed(KEY_RIGHT): m |= 128
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER) or Input.is_physical_key_pressed(KEY_X) or Input.is_physical_key_pressed(KEY_Z):
		m |= 256
	if Input.is_physical_key_pressed(KEY_BACKSPACE) or Input.is_physical_key_pressed(KEY_TAB):
		m |= 4
	var d := pad_device()
	if d >= 0:
		for i in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			if Input.is_joy_button_pressed(d, i):
				m |= {JOY_BUTTON_DPAD_UP: 16, JOY_BUTTON_DPAD_DOWN: 32, JOY_BUTTON_DPAD_LEFT: 64, JOY_BUTTON_DPAD_RIGHT: 128}[i]
		var sx := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
		var sy := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
		if sy < -0.5: m |= 16
		if sy > 0.5: m |= 32
		if sx < -0.5: m |= 64
		if sx > 0.5: m |= 128
		# menus on a gamepad: d-pad / stick, START to confirm, BACK for controls. The face buttons are NOT hard-wired, so
		# only the player's own A binding (added in main.gd) confirms and B / X / Y never do.
		if Input.is_joy_button_pressed(d, JOY_BUTTON_START):
			m |= 256
		if Input.is_joy_button_pressed(d, JOY_BUTTON_BACK):
			m |= 4
	return m


# ---------------------------------------------------------------- listening for a new binding

# Everything that is held right now, as binding texts (used to ignore buttons that were already down).
func held(dev: String, lh: Node, rh: Node) -> Dictionary:
	var out := {}
	if dev == "pad":
		var d := pad_device()
		if d < 0:
			return out
		for i in 21:
			if Input.is_joy_button_pressed(d, i):
				out["b:%d" % i] = true
		for ax in 6:
			var v := Input.get_joy_axis(d, ax)
			if v > 0.6:
				out["a:%d:+" % ax] = true
			if v < -0.6 and ax < 4:
				out["a:%d:-" % ax] = true
	elif dev == "vr":
		for hn in ["L", "R"]:
			var h: Node = lh if hn == "L" else rh
			if h == null:
				continue
			for bn in VR_BUTTONS:
				if h.is_button_pressed(bn):
					out["v:%s:%s" % [hn, bn]] = true
			var st: Vector2 = h.get_vector2("primary")
			if st.y > 0.7: out["s:%s:u" % hn] = true
			if st.y < -0.7: out["s:%s:d" % hn] = true
			if st.x < -0.7: out["s:%s:l" % hn] = true
			if st.x > 0.7: out["s:%s:r" % hn] = true
	return out


# The first new press since `baseline`, or "".
func poll(dev: String, lh: Node, rh: Node, baseline: Dictionary) -> String:
	var now := held(dev, lh, rh)
	for k in baseline.keys():
		if not now.has(k):
			baseline.erase(k)                        # released: it may be pressed again
	for k in now.keys():
		if not baseline.has(k):
			return k
	return ""


func assign(dev: String, action: String, b: String) -> void:
	var old: String = maps[dev][action]
	for a in ACTIONS:
		if a != action and maps[dev][a] == b:
			maps[dev][a] = old                       # swap, so nothing ends up with two buttons the same
	maps[dev][action] = b
	_reparse(dev)
	save_cfg()


func name_of(b: String) -> String:
	var p := _parse(b)
	if p.is_empty():
		return "?"
	match p[0]:
		"k":
			return OS.get_keycode_string(p[1]).to_upper()
		"b":
			return str(PAD_BUTTON_NAMES.get(p[1], "BUTTON %d" % p[1]))
		"a":
			var ax: int = p[1]
			var plus: bool = p[2] > 0.0
			match ax:
				0: return "LEFT STICK " + ("RIGHT" if plus else "LEFT")
				1: return "LEFT STICK " + ("DOWN" if plus else "UP")
				2: return "RIGHT STICK " + ("RIGHT" if plus else "LEFT")
				3: return "RIGHT STICK " + ("DOWN" if plus else "UP")
				4: return "LEFT TRIGGER"
				5: return "RIGHT TRIGGER"
			return "AXIS %d" % ax
		"v":
			return ("LEFT " if p[1] == "L" else "RIGHT ") + str(VR_NAMES.get(p[2], p[2]))
		"s":
			var dirs := {"u": "UP", "d": "DOWN", "l": "LEFT", "r": "RIGHT"}
			return ("LEFT" if p[1] == "L" else "RIGHT") + " STICK " + str(dirs.get(p[2], "?"))
	return "?"
