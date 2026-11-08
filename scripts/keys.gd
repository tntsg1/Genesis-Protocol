class_name Keys
extends RefCounted
# Rebindable hotkeys (DECISIONS M4 Q5: "设置里可改键"). Defaults below; the
# player's choices live in the settings file (tests use their own file, so a
# test never changes the player's keys). Esc, F1, arrows and WASD stay fixed.

# Layout (2026-10-29, the user's pick): the four hands-on tools on 1-4, time
# on Space / - / =, Tab opens and closes the life designer (the "backpack").
const ACTIONS := [
	["nutrient", "营养投放", KEY_1],
	["membrane", "隔离膜", KEY_2],
	["heat", "局部升降温", KEY_3],
	["current", "洋流引导", KEY_4],
	["phage", "投放病毒", KEY_5],
	# (Sandbox, DECISIONS 沙盒补全 Q276: every tool its own key; in a level
	# these four take another tool's slot and key.)
	["iron", "撒铁粉（沙盒）", KEY_6],
	["brine", "撒盐（沙盒）", KEY_7],
	["stir", "搅动泥层（沙盒）", KEY_8],
	["irritant", "刺激头冠（沙盒）", KEY_9],
	["world", "地形编辑（沙盒）", KEY_G],
	["pause", "暂停 / 继续", KEY_SPACE],
	["slower", "减速（¼× / 1× / 3× / 8×）", KEY_MINUS],
	["faster", "加速", KEY_EQUAL],
	["step", "单步（暂停时前进一拍）", KEY_PERIOD],
	["designer", "生命设计器（再按一次返回）", KEY_TAB],
	["track", "跟随", KEY_F],
	["observe", "观察模式", KEY_V],
	["analysis", "分析模式", KEY_X],
	["env_layer", "环境图层", KEY_T],
	["filter", "视图滤镜", KEY_C],
	["report", "生态报告", KEY_R],
	["lens", "放大镜（按住 Alt 临时）", KEY_Z],
	["night", "黑夜模式", KEY_N],
]

# Keys that stay put (camera, menus): cannot be bound to an action.
const FIXED := [KEY_ESCAPE, KEY_F1, KEY_F11, KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E,
	KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER]

# Bump when the default layout changes: older saved keys are dropped once.
const LAYOUT := 2

static var map := {}
static var _loaded := false


static func path() -> String:
	var args := OS.get_cmdline_args()
	return "user://test_settings.cfg" if ("-s" in args or "--script" in args) else "user://settings.cfg"


static func load_keys() -> void:
	_loaded = true
	map.clear()
	for a: Array in ACTIONS:
		map[a[0]] = a[2]
	var cf := ConfigFile.new()
	if cf.load(path()) == OK and int(cf.get_value("keys", "_layout", 1)) == LAYOUT:
		for a: Array in ACTIONS:
			map[a[0]] = int(cf.get_value("keys", a[0], a[2]))


static func save_keys() -> void:
	var cf := ConfigFile.new()
	cf.load(path())
	if cf.has_section("keys"):
		cf.erase_section("keys") # actions that no longer exist go too
	for id: String in map:
		cf.set_value("keys", id, map[id])
	cf.set_value("keys", "_layout", LAYOUT)
	cf.save(path())


static func code(id: String) -> int:
	if not _loaded:
		load_keys()
	return int(map.get(id, 0))


# The action a pressed key triggers, or "".
static func action_of(keycode: int) -> String:
	if not _loaded:
		load_keys()
	for id: String in map:
		if int(map[id]) == keycode:
			return id
	return ""


# Binds `keycode` to `id`; an action that had it takes the old key (swap).
# Returns the swapped action's id, or "".
static func bind(id: String, keycode: int) -> String:
	if not _loaded:
		load_keys()
	var other := action_of(keycode)
	var old: int = map[id]
	map[id] = keycode
	if other != "" and other != id:
		map[other] = old
	save_keys()
	return other if other != id else ""


static func reset() -> void:
	map.clear()
	for a: Array in ACTIONS:
		map[a[0]] = a[2]
	save_keys()


# Text with "{action}" put in as that action's current key ("{track}" -> "F").
static func fill(t: String) -> String:
	for a: Array in ACTIONS:
		if t.contains("{%s}" % a[0]):
			t = t.replace("{%s}" % a[0], name_of(code(a[0])))
	return t


static func name_of(keycode: int) -> String:
	# Punctuation reads as the key cap, not its name ("Period").
	var caps := {KEY_PERIOD: ".", KEY_COMMA: ",", KEY_SLASH: "/", KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'",
		KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]", KEY_MINUS: "-", KEY_EQUAL: "=", KEY_BACKSLASH: "\\", KEY_QUOTELEFT: "`"}
	return caps.get(keycode, OS.get_keycode_string(keycode))


static func label(id: String) -> String:
	for a: Array in ACTIONS:
		if a[0] == id:
			return a[1]
	return id
