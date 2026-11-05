class_name Resp
extends RefCounted
# Chapter 6 respiration (DECISIONS Q205 / Q219 / Q221): a three-way switch on
# the genome page, open from 6-4; before that a level fixes it (anaerobic).
# Ids match SimCore Species.resp: 0 none (oxygen means nothing), 1 anaerobic,
# 2 aerobic, 3 facultative.

enum { NONE, ANAEROBIC, AEROBIC, FACULTATIVE }

# [name, en, what it does, budget points]
const LIST := [
	["无", "NONE", "", 0],
	["厌氧", "ANAEROBIC", "不用氧气。氧气浓度超过 8% 的水会让它持续掉能量，越浓掉得越快。", 0],
	["好氧", "AEROBIC", "用氧气分解食物：氧气充足时，同样的食物得到的能量约为厌氧的 3 倍（现实里大约多 15 倍，这里为了平衡做成 3 倍）；缺氧时只有一半左右。呼吸会消耗水里的氧气。", 0],
	["兼性", "FACULTATIVE", "两种呼吸都会：不怕氧气，有氧时能量约为厌氧的 2.2 倍，缺氧时也能将就。要多花 2 点基因预算。", 2],
]
const OPENS := "6-4"


static func cost(resp: int) -> int:
	return int(LIST[clampi(resp, 0, 3)][3])


static func name_of(resp: int) -> String:
	return LIST[clampi(resp, 0, 3)][0]


# The switch's next setting (厌氧 → 好氧 → 兼性 → 厌氧).
static func next(resp: int) -> int:
	return [ANAEROBIC, AEROBIC, FACULTATIVE, ANAEROBIC][clampi(resp, 0, 3)]
