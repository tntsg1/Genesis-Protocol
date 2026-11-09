class_name Recommend
extends RefCounted
# Recommended values per level (DECISIONS 推荐数值, Q283–Q285): the design
# that passed most for tests/recommend_bot.gd, starting from the one the
# guide teaches. data/recommend.json: {id: {genes, wins, seeds, extra?,
# virus?, drops?, drop_kind?, blocks?}}: `genes` the first species' (or the
# only one's), `extra` the other species' in slot order, `virus` the virus
# bench's points and `drops` when to drop it, `blocks` the body.
# Used by the guide's "跟着引导再试一次" (a step per change, and 一键套用),
# by the report from the second miss on and by the coach's drop reminders.
# The words are the user's (design/卡关帮助补齐_稿子.md); nothing a player
# reads says how it was found.

const PATH := "res://data/recommend.json"
const GENE_NAMES := ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]
const TRAIT_NAMES := {burst = "爆发", speed = "复制", shell = "外壳", stick = "附着"}
const TRAITS := ["burst", "speed", "shell", "stick"]
const BLOCK_NAMES := {1: "鞭毛块", 6: "生殖块", 7: "甲块", 8: "储能块", 9: "再生块"}

static var _data := {}
static var _loaded := false


static func for_level(id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(PATH):
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if j is Dictionary:
				_data = j
	var r: Dictionary = _data.get(id, {})
	# (Worth recommending only if it passes at all.)
	return r if not r.is_empty() and int(r.get("wins", 0)) > 0 else {}


# Species slot k's recommended genes ([] if none).
static func slot_genes(r: Dictionary, k: int) -> Array:
	if r.is_empty():
		return []
	if k == 0:
		return r.genes
	var ex: Array = r.get("extra", [])
	return ex[k - 1] if k - 1 < ex.size() else []


static func slots(r: Dictionary) -> int:
	return 1 + (r.get("extra", []) as Array).size()


# The open genes where `genes` differs from slot k's recommendation: [[k, now, want]].
static func diffs(l: Dictionary, genes: Array, slot := 0) -> Array:
	var want := slot_genes(for_level(str(l.get("id", ""))), slot)
	var out := []
	for k: int in l.get("genes_open", range(8)):
		if k < want.size() and k < genes.size() and absf(float(genes[k]) - float(want[k])) > 0.01:
			out.append([k, float(genes[k]), float(want[k])])
	return out


# "速度 3 · 繁殖 4 · 代谢 3" for the open genes of slot k (sep " · "), or with
# another separator ("速度 3、繁殖 4").
static func text(l: Dictionary, slot := 0, sep := " · ") -> String:
	var want := slot_genes(for_level(str(l.get("id", ""))), slot)
	if want.is_empty():
		return ""
	var parts := []
	for k: int in l.get("genes_open", range(8)):
		if k < want.size():
			parts.append("%s %s" % [GENE_NAMES[k], _lv(float(want[k]))])
	return sep.join(parts)


# The species tab's name: "B · 捕食者".
static func slot_name(l: Dictionary, k: int) -> String:
	var specs: Array = l.get("species", [])
	return "%s · %s" % ["ABC"[mini(k, 2)], str(specs[k].get("label", "")) if k < specs.size() else ""]


# "A · 猎物：速度 1 · 繁殖 4\n\nB · 捕食者：…" (several species), or the one line.
static func all_text(l: Dictionary) -> String:
	var r := for_level(str(l.get("id", "")))
	if slots(r) <= 1:
		return text(l)
	var parts := []
	for k in slots(r):
		parts.append("%s：%s" % [slot_name(l, k), text(l, k)])
	return "\n\n".join(parts)


# The report's line: "试试这套基因：A · 猎物速度 1、繁殖 4；B · 捕食者速度 3、繁殖 2。"
static func report_text(l: Dictionary) -> String:
	var r := for_level(str(l.get("id", "")))
	if r.is_empty():
		return ""
	if r.has("virus") and str(l.id) == "4-4":
		return "推荐病毒：%s。等到 %s 投第一团，过 %d 秒再投第二团。" % [virus_text(r), clock(first_drop(r)), drop_gap(r)]
	if r.has("virus"):
		return "推荐：基因 %s；噬毒体 %s；开局 %d 秒内向自己的细胞投两团。" % [text(l), virus_text(r), drops_within(r)]
	if r.has("blocks"):
		return "推荐身体和基因：%s；%s。规则卡保留原来的设置。" % [body_text(r.blocks), _levels_text(l)]
	if slots(r) > 1:
		var parts := []
		for k in slots(r):
			parts.append(slot_name(l, k) + text(l, k, "、"))
		return "试试这套基因：%s。" % "；".join(parts)
	return "试试这套基因：%s。" % text(l, 0, "、")


# "感知等级 3，代谢等级 3"
static func _levels_text(l: Dictionary) -> String:
	var want := slot_genes(for_level(str(l.get("id", ""))), 0)
	var parts := []
	for k: int in l.get("genes_open", range(8)):
		if k < want.size():
			parts.append("%s等级 %s" % [GENE_NAMES[k], _lv(float(want[k]))])
	return "，".join(parts)


# "马上裂解 · 爆发 2 · 复制 2 · 外壳 5 · 附着 3"
static func virus_text(r: Dictionary) -> String:
	var v: Dictionary = r.get("virus", {})
	if v.is_empty():
		return ""
	var parts := ["先潜伏" if bool(v.get("temperate", false)) else "马上裂解"]
	for k: String in TRAITS:
		parts.append("%s %d" % [TRAIT_NAMES[k], int(v.get(k, 3))])
	return " · ".join(parts)


# The virus bench's points against the recommendation: [[key, now, want]],
# lowered ones first (the 12 points would not let a raise in before).
static func virus_diffs(r: Dictionary, now: Dictionary) -> Array:
	var v: Dictionary = r.get("virus", {})
	var down := []
	var up := []
	for k: String in TRAITS:
		if v.has(k) and int(now.get(k, 3)) != int(v[k]):
			(down if int(v[k]) < int(now.get(k, 3)) else up).append([k, int(now.get(k, 3)), int(v[k])])
	return down + up


static func virus_same(r: Dictionary, now: Dictionary) -> bool:
	var v: Dictionary = r.get("virus", {})
	return not v.is_empty() and virus_diffs(r, now).is_empty() and bool(v.get("temperate", false)) == bool(now.get("temperate", false))


static func first_drop(r: Dictionary) -> float:
	var d: Array = r.get("drops", [])
	return float(d[0]) if not d.is_empty() else 0.0


static func second_drop(r: Dictionary) -> float:
	var d: Array = r.get("drops", [])
	return float(d[1]) if d.size() > 1 else -1.0


static func drop_gap(r: Dictionary) -> int:
	return roundi(second_drop(r) - first_drop(r))


# "开局 N 秒内" for two drops: the second's time, up to the next 5 s.
static func drops_within(r: Dictionary) -> int:
	return int(ceilf(maxf(second_drop(r), first_drop(r)) / 5.0) * 5.0)


static func clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# The body's cells where `now` differs from the recommendation, rows and
# columns counted from the top left of both together (from 1):
# [[row, col, had, wants]], 0 for no block.
static func body_diffs(r: Dictionary, now: Array) -> Array:
	var want: Array = r.get("blocks", [])
	if want.is_empty():
		return []
	var at := {}
	for c: Array in now:
		at[Vector2i(int(c[0]), int(c[1]))] = [int(c[2]), 0]
	for c: Array in want:
		var p := Vector2i(int(c[0]), int(c[1]))
		var e: Array = at.get(p, [0, 0])
		e[1] = int(c[2])
		at[p] = e
	var lo := Vector2i(1 << 20, 1 << 20)
	for p: Vector2i in at:
		lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
	var out := []
	for p: Vector2i in at:
		var e: Array = at[p]
		if int(e[0]) != int(e[1]):
			out.append([p.y - lo.y + 1, p.x - lo.x + 1, int(e[0]), int(e[1]), p])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return out


static func block_name(kind: int) -> String:
	return BLOCK_NAMES.get(kind, "空") if kind != 0 else "空"


# "身体共 12 个模块，其中鞭毛块 6 个、生殖块 3 个、甲块 3 个"
static func body_text(blocks: Array) -> String:
	var n := {}
	for c: Array in blocks:
		n[int(c[2])] = int(n.get(int(c[2]), 0)) + 1
	var parts := []
	for kd: int in [1, 6, 7, 8, 9]:
		if n.has(kd):
			parts.append("%s %d 个" % [BLOCK_NAMES[kd], int(n[kd])])
	return "身体共 %d 个模块，其中%s" % [blocks.size(), "、".join(parts)]


static func _lv(v: float) -> String:
	return str(int(v)) if absf(v - roundf(v)) < 0.01 else "%.1f" % v
