class_name CampaignSave
extends RefCounted
# Campaign progress: per level the best stars and attempts, research points
# and whether the briefing tutorial was seen. Tests (-s / --script) use their
# own file and never touch the player's save; the real save keeps a backup of
# the previous version.

const REAL_PATH := "user://campaign.json"
const TEST_PATH := "user://test_campaign.json"

static var data := {}
static var _loaded := false


static func path() -> String:
	var args := OS.get_cmdline_args()
	if "-s" in args or "--script" in args:
		return TEST_PATH
	# Developer mode plays on its own copy (scripts/dev_mode.gd).
	return DevMode.DEV_PATH if DevMode.active else REAL_PATH


static func load_save() -> void:
	_loaded = true
	data = {levels = {}, research = 0, seen_tutorial = {}}
	if FileAccess.file_exists(path()):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path()))
		if parsed is Dictionary:
			data.merge(parsed, true)


static func save() -> void:
	var p := path()
	if p == REAL_PATH and FileAccess.file_exists(p):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(p + ".bak"))
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


static func ensure() -> void:
	if not _loaded:
		load_save()


static func level(id: String) -> Dictionary:
	ensure()
	return data.levels.get(id, {})


static func stars(id: String) -> Array:
	return level(id).get("stars", [false, false, false])


# A level opens once the one before it has been completed.
static func unlocked(index: int) -> bool:
	if index <= 1 or DevMode.on(DevMode.unlock_all):
		return true
	var prev: Dictionary = Levels.ALL[index - 2]
	return bool(stars(prev.id)[0])


# Records an attempt; returns the research points it earned (new stars and a
# correct prediction).
static func record(id: String, got: Array, predicted_right: bool) -> int:
	ensure()
	var rec: Dictionary = data.levels.get(id, {stars = [false, false, false], attempts = 0, predictions_right = 0})
	var before: Array = rec.stars
	var earned := 0
	for k in 3:
		if got[k] and not before[k]:
			earned += 10
	if predicted_right:
		earned += 5
		rec.predictions_right = int(rec.get("predictions_right", 0)) + 1
	rec.stars = [before[0] or got[0], before[1] or got[1], before[2] or got[2]]
	rec.attempts = int(rec.get("attempts", 0)) + 1
	data.levels[id] = rec
	data.research = int(data.get("research", 0)) + earned
	save()
	return earned


static func add_research(n: int) -> void:
	ensure()
	data.research = int(data.get("research", 0)) + n
	save()


static func research() -> int:
	ensure()
	return int(data.get("research", 0))


static func tutorial_seen(id: String) -> bool:
	ensure()
	return bool(data.seen_tutorial.get(id, false))


static func mark_tutorial(id: String) -> void:
	ensure()
	data.seen_tutorial[id] = true
	clear_guide_at(id)
	save()


# Where a level's guide was left ({step = "design" / "run", n = lines already
# done}; {} = from the start): leaving to the menu and coming back carries on
# from there (2026-10-29: "下一次进来时，可以继续上次引导的教程过程").
static func guide_at(id: String) -> Dictionary:
	ensure()
	return data.get("guide_at", {}).get(id, {})


# The level's first go has been guided to its end: a level with a second part
# to its guide (tutorial.gd: design2 / run2) goes on to it next time.
static func guide_second(id: String) -> bool:
	ensure()
	return data.get("guide_second", {}).has(id)


static func set_guide_second(id: String) -> void:
	ensure()
	if not data.has("guide_second"):
		data.guide_second = {}
	data.guide_second[id] = true
	save()


static func set_guide_at(id: String, step: String, n: int) -> void:
	ensure()
	if not data.has("guide_at"):
		data.guide_at = {}
	var was: Dictionary = data.guide_at.get(id, {})
	if was.get("step", "") == step and int(was.get("n", -1)) == n:
		return
	data.guide_at[id] = {step = step, n = n}
	save()


static func clear_guide_at(id: String) -> void:
	ensure()
	if data.has("guide_at") and data.guide_at.has(id):
		data.guide_at.erase(id)
		save()


# Chapter 6 (DECISIONS Q213): the look the player gave a species role
# ("sulfur" 硫泉游丝, "dawn" 晨光丝 ...): later levels show their own
# species of that role with this name and colour (the numbers stay the level's).
static func set_look(role: String, look_name: String, color: Color) -> void:
	ensure()
	if not data.has("looks"):
		data.looks = {}
	data.looks[role] = {name = look_name, color = color.to_html()}
	save()


static func look(role: String) -> Dictionary:
	ensure()
	var l: Dictionary = data.get("looks", {}).get(role, {})
	return {} if l.is_empty() else {name = str(l.name), color = Color.html(str(l.color))}


# One-time scenes seen (chapter 6's landfall: "arrival_6").
static func seen(key: String) -> bool:
	ensure()
	return bool(data.get("seen", {}).get(key, false))


static func mark_seen(key: String) -> void:
	ensure()
	if not data.has("seen"):
		data.seen = {}
	data.seen[key] = true
	save()


# Tests start from a clean slate (their own file only).
static func reset_for_tests() -> void:
	if path() == TEST_PATH:
		data = {levels = {}, research = 0, seen_tutorial = {}}
		_loaded = true
		save()
