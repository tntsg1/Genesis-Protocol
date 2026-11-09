class_name Recommend
extends RefCounted
# Recommended values per level (DECISIONS 推荐数值): the gene set that passed
# most for the level bot (tests/recommend_bot.gd), starting from the design
# the guide teaches. data/recommend.json: {id: {genes, wins, seeds}}.
# Used by the guide's "跟着引导再试一次" (one step per gene, and 一键套用) and
# by the report from the second miss on.

const PATH := "res://data/recommend.json"
const GENE_NAMES := ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]

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


# The open genes where `genes` differs from the recommendation: [[k, now, want]].
static func diffs(l: Dictionary, genes: Array) -> Array:
	var r := for_level(str(l.get("id", "")))
	var out := []
	if r.is_empty():
		return out
	var want: Array = r.genes
	for k: int in l.get("genes_open", range(8)):
		if k < want.size() and k < genes.size() and absf(float(genes[k]) - float(want[k])) > 0.01:
			out.append([k, float(genes[k]), float(want[k])])
	return out


# "速度 3 · 繁殖 4 · 代谢 3" for the open genes.
static func text(l: Dictionary) -> String:
	var r := for_level(str(l.get("id", "")))
	if r.is_empty():
		return ""
	var parts := []
	for k: int in l.get("genes_open", range(8)):
		if k < (r.genes as Array).size():
			parts.append("%s %s" % [GENE_NAMES[k], _lv(float(r.genes[k]))])
	return " · ".join(parts)


static func _lv(v: float) -> String:
	return str(int(v)) if absf(v - roundf(v)) < 0.01 else "%.1f" % v
