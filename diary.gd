extends RefCounted
## The diary: what you read and played, and when. Kept in user://diary.cfg; book bookmarks live in
## user://reader.cfg (book.gd writes those). Everything here is a static helper over those two files.

const DIARY := "user://diary.cfg"
const READER := "user://reader.cfg"


# ---- play sessions: the console/arcade reports a game starting and stopping

static func game_started(system: String, game: String) -> void:
	var cf := ConfigFile.new()
	cf.load(DIARY)
	cf.set_value("playing", "system", system)
	cf.set_value("playing", "game", game)
	cf.set_value("playing", "since", int(Time.get_unix_time_from_system()))
	cf.save(DIARY)


static func game_stopped() -> void:
	var cf := ConfigFile.new()
	if cf.load(DIARY) != OK or not cf.has_section("playing"):
		return
	var game := str(cf.get_value("playing", "game", ""))
	var system := str(cf.get_value("playing", "system", ""))
	var since := int(cf.get_value("playing", "since", 0))
	cf.erase_section("playing")
	var now := int(Time.get_unix_time_from_system())
	var secs := maxi(0, now - since)
	if game != "" and secs >= 20:
		var key := (system + "/" + game).md5_text()
		cf.set_value("games", key, {"game": game, "system": system, "last": now,
			"total": int(cf.get_value("games", key, {}).get("total", 0)) + secs, "sessions": int(cf.get_value("games", key, {}).get("sessions", 0)) + 1,
			"last_len": secs})
	cf.save(DIARY)


# a game that was running when the room closed without saying goodbye counts up to then
static func close_open_session() -> void:
	game_stopped()


# ---- the cats: how often each one has been petted

static func cat_petted(which: String) -> void:
	var cf := ConfigFile.new()
	cf.load(DIARY)
	var c: Dictionary = cf.get_value("cats", which, {})
	var now := int(Time.get_unix_time_from_system())
	cf.set_value("cats", which, {"pets": int(c.get("pets", 0)) + 1, "last": now, "first": int(c.get("first", now))})
	cf.save(DIARY)


# ---- what the diary shows

# [{"kind": "game"|"book", "title", "detail", "when": unix, "sort": unix, "path"?: String}]
static func entries() -> Array:
	var out: Array = []
	var cf := ConfigFile.new()
	if cf.load(DIARY) == OK and cf.has_section("games"):
		for k in cf.get_section_keys("games"):
			var g: Dictionary = cf.get_value("games", k, {})
			out.append({"kind": "game", "title": str(g.get("game", "?")), "system": str(g.get("system", "")),
				"detail": "played %s in all, last time %s" % [fmt_len(int(g.get("total", 0))), fmt_len(int(g.get("last_len", 0)))],
				"when": int(g.get("last", 0)), "sort": int(g.get("last", 0))})
	if cf.has_section("cats"):
		for k in cf.get_section_keys("cats"):
			var c: Dictionary = cf.get_value("cats", k, {})
			var n := int(c.get("pets", 0))
			out.append({"kind": "cat", "title": "The tuxedo cat" if k == "tux" else "The calico",
				"detail": "petted %d time%s" % [n, "" if n == 1 else "s"], "when": int(c.get("last", 0)), "sort": int(c.get("last", 0))})
	var rc := ConfigFile.new()
	if rc.load(READER) == OK and rc.has_section("bookmarks"):
		for k in rc.get_section_keys("bookmarks"):
			if str(rc.get_value("titles", k, "")).begins_with("remote:"):
				continue                         # a friend's book, not yours to reopen
			var page := int(rc.get_value("bookmarks", k, 0))
			var pages := int(rc.get_value("pages", k, 0))
			var when := int(rc.get_value("when", k, 0))
			var name := str(rc.get_value("names", k, rc.get_value("titles", k, "?")))
			if name.contains("/") or name.contains("\\"):
				name = name.get_file().get_basename()
			var mark := int(rc.get_value("marks", k, -1))
			var detail := "page %d" % (page + 1)
			if pages > 0:
				detail += " of %d" % pages
			if mark >= 0:
				detail += ",  bookmark on p. %d" % (mark + 1)
			out.append({"kind": "book", "title": name, "detail": detail, "when": when, "sort": when, "path": str(rc.get_value("titles", k, ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["sort"]) > int(b["sort"]))
	return out


static func fmt_len(secs: int) -> String:
	if secs < 60:
		return "%d s" % secs
	if secs < 3600:
		return "%d min" % (secs / 60)
	var h := secs / 3600
	var m := (secs % 3600) / 60
	return "%d h %02d min" % [h, m] if m > 0 else "%d h" % h


static func fmt_when(unix: int) -> String:
	if unix <= 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var today := Time.get_datetime_dict_from_system()
	if d["year"] == today["year"] and d["month"] == today["month"] and d["day"] == today["day"]:
		return "today %02d:%02d" % [d["hour"], d["minute"]]
	return "%s %d %d" % [months[int(d["month"]) - 1], d["day"], d["year"]]
