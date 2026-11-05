class_name Personas
extends RefCounted
# The rules page's simple mode (2026-10-29: "默认类似于选择题…想要更高定制
# 的话，可以选择高级模式"): pick a personality, then one 保守 <-> 激进
# slider. Each personality is a whole deck built from library pieces; the
# slider moves every threshold toward its cautious or its bold end. The card
# editor (advanced mode) opens from ADVANCED_OPENS and starts from whatever
# the simple mode made.

const ADVANCED_OPENS := "1-4"

# id, name, en, one line, diet (0 grazer / 1 predator / -1 either), opens
# (the level it is offered from: simple mode does not wait for the library's
# pieces, which are the advanced mode's).
# "standard" is the level's own deck (or the default for the diet).
const LIST := [
	# (tag: a short first line, in the user's own words, 2026-11-02.)
	{id = "standard", name = "标准", en = "STANDARD", diet = -1, opens = "1-1", tag = "默认行为。",
		line = "能量不足时寻找食物，积累足够能量后分裂。适合食物供应比较稳定的环境。"},
	{id = "breeder", name = "多产", en = "BREEDER", diet = 0, opens = "1-2", tag = "优先繁殖。",
		line = "只要能量足够就会分裂，种群增长比较快。不过，它们不会主动储存太多能量，遇到食物短缺时容易饿死。"},
	{id = "thrifty", name = "节俭", en = "THRIFTY", diet = 0, opens = "1-2", tag = "优先节省能量。",
		line = "平时尽量休息，发现食物后会主动进食。储存足够的能量后才会分裂。\n繁殖速度比较慢，但在食物稀少的环境里更容易存活。"},
	{id = "comfort", name = "恋温", en = "WARMTH SEEKER", diet = 0, opens = "1-4",
		line = "水温一不对就先去找舒适的水，其余照常。"},
	{id = "swarm", name = "抱团", en = "SWARM", diet = 0, opens = "1-5",
		line = "没事做时游向同伴，聚成一群：更容易一起找到食物。"},
	{id = "ambush", name = "伏击", en = "AMBUSHER", diet = 1, opens = "2-1",
		line = "饿了并发现猎物时才会追捕。平时停在原地等待，能量消耗很低。"},
	{id = "chaser", name = "追猎", en = "CHASER", diet = 1, opens = "2-1",
		line = "发现猎物就主动追捕，积累足够能量后分裂。种群增长较快，但需要更多食物。"},
]


static func by_id(id: String) -> Dictionary:
	for p: Dictionary in LIST:
		if p.id == id:
			return p
	return LIST[0]


static func advanced_open(level_id: String) -> bool:
	return level_id == "" or Rules._rank(level_id) >= Rules._rank(ADVANCED_OPENS) - 0.001


# The personalities this level can use: open by now, the diet fits and the
# organs their deck needs are installed.
static func available(level_id: String, diet: int, organs: Array) -> Array:
	var out := []
	for p: Dictionary in LIST:
		if int(p.diet) >= 0 and int(p.diet) != diet:
			continue
		if level_id != "" and Rules._rank(level_id) < Rules._rank(p.opens) - 0.001:
			continue
		if p.id == "standard" or _organs_ok(_raw(p.id), organs):
			out.append(p)
	return out


static func _organs_ok(deck: Array, organs: Array) -> bool:
	for cd: Dictionary in deck:
		for c: int in [cd.c1, cd.c2]:
			if c != Rules.C_NONE and not Organs.has_for("cond", c, organs):
				return false
		if not Organs.has_for("act", cd.act, organs):
			return false
	return true


# A personality's deck at the slider's middle.
static func _raw(id: String) -> Array:
	match id:
		"breeder":
			return [Rules.card(Rules.C_PREDATOR_NEAR, 60.0, Rules.C_NONE, 0.0, Rules.A_FLEE),
				Rules.card(Rules.C_ENERGY_ABOVE, 1.0, Rules.C_NONE, 0.0, Rules.A_DIVIDE),
				Rules.card(Rules.C_SEE_ALGAE, 0.0, Rules.C_NONE, 0.0, Rules.A_SEEK_ALGAE)]
		"thrifty":
			return [Rules.card(Rules.C_PREDATOR_NEAR, 90.0, Rules.C_NONE, 0.0, Rules.A_FLEE),
				Rules.card(Rules.C_ENERGY_ABOVE, 1.1, Rules.C_NONE, 0.0, Rules.A_DIVIDE),
				Rules.card(Rules.C_ENERGY_BELOW, 1.1, Rules.C_SEE_ALGAE, 0.0, Rules.A_SEEK_ALGAE),
				Rules.card(Rules.C_NONE, 0.0, Rules.C_NONE, 0.0, Rules.A_REST)]
		"comfort":
			return [Rules.card(Rules.C_PREDATOR_NEAR, 60.0, Rules.C_NONE, 0.0, Rules.A_FLEE),
				Rules.card(Rules.C_TEMP_BAD, 0.0, Rules.C_NONE, 0.0, Rules.A_SEEK_COMFORT),
				Rules.card(Rules.C_ENERGY_ABOVE, 1.0, Rules.C_NONE, 0.0, Rules.A_DIVIDE),
				Rules.card(Rules.C_ENERGY_BELOW, 1.0, Rules.C_SEE_ALGAE, 0.0, Rules.A_SEEK_ALGAE)]
		"swarm":
			return [Rules.card(Rules.C_PREDATOR_NEAR, 60.0, Rules.C_NONE, 0.0, Rules.A_FLEE),
				Rules.card(Rules.C_ENERGY_ABOVE, 1.1, Rules.C_NONE, 0.0, Rules.A_DIVIDE),
				Rules.card(Rules.C_ENERGY_BELOW, 1.0, Rules.C_SEE_ALGAE, 0.0, Rules.A_SEEK_ALGAE),
				Rules.card(Rules.C_NONE, 0.0, Rules.C_NONE, 0.0, Rules.A_FOLLOW)]
		"ambush":
			return [Rules.card(Rules.C_PREDATOR_NEAR, 60.0, Rules.C_NONE, 0.0, Rules.A_FLEE),
				Rules.card(Rules.C_ENERGY_BELOW, 1.0, Rules.C_SEE_PREY, 0.0, Rules.A_HUNT),
				Rules.card(Rules.C_ENERGY_ABOVE, 1.0, Rules.C_NONE, 0.0, Rules.A_DIVIDE),
				Rules.card(Rules.C_SEE_SHELL, 0.0, Rules.C_NONE, 0.0, Rules.A_SCAVENGE),
				Rules.card(Rules.C_NONE, 0.0, Rules.C_NONE, 0.0, Rules.A_REST)]
		"chaser":
			return [Rules.card(Rules.C_PREDATOR_NEAR, 60.0, Rules.C_NONE, 0.0, Rules.A_FLEE),
				Rules.card(Rules.C_SEE_PREY, 0.0, Rules.C_NONE, 0.0, Rules.A_HUNT),
				Rules.card(Rules.C_ENERGY_ABOVE, 1.0, Rules.C_NONE, 0.0, Rules.A_DIVIDE),
				Rules.card(Rules.C_SEE_SHELL, 0.0, Rules.C_NONE, 0.0, Rules.A_SCAVENGE)]
	return []


# The deck for personality `id` at slider `bold` (0 保守 … 0.5 as built … 1
# 激进). `base` is the level's own deck (the standard personality).
static func build(id: String, base: Array, bold: float) -> Array:
	var d: Array = base.duplicate(true) if id == "standard" else _raw(id)
	return tune(d, bold)


# Each threshold toward its cautious (bold 0) or its bold (bold 1) end; at
# 0.5 the deck is unchanged. Unknown pairs stay as they are.
static func tune(deck: Array, bold: float) -> Array:
	var out := deck.duplicate(true)
	for cd: Dictionary in out:
		for s in [1, 2]:
			var c: int = cd["c%d" % s]
			var ends := _ends(c, int(cd.act))
			if ends.is_empty() or cd.get("n%d" % s, false):
				continue
			var t: float = cd["t%d" % s]
			var v: float = lerpf(t, ends[0], (0.5 - bold) * 2.0) if bold < 0.5 else lerpf(t, ends[1], (bold - 0.5) * 2.0)
			var spec: Array = Rules.CONDS[c]
			cd["t%d" % s] = clampf(snappedf(v, spec[5]), spec[2], spec[3])
	# A hunter only gains energy by hunting: if it stops chasing below the
	# divide line it never divides (the cautious end died out in 2-1).
	var line := 0.0
	for cd: Dictionary in out:
		if cd.act == Rules.A_DIVIDE and cd.c1 == Rules.C_ENERGY_ABOVE:
			line = maxf(line, float(cd.t1))
	# The same for a grazer: one that stops feeding below the divide line
	# never divides either (节俭 ate to 80% and waited for 130%: 1-2 died out,
	# user 2026-10-30).
	for cd: Dictionary in out:
		if cd.act == Rules.A_HUNT or cd.act == Rules.A_SEEK_ALGAE:
			for s in [1, 2]:
				if cd["c%d" % s] == Rules.C_ENERGY_BELOW and not cd.get("n%d" % s, false):
					cd["t%d" % s] = maxf(float(cd["t%d" % s]), line)
	return out


# [cautious end, bold end] for a condition on a card with this action.
static func _ends(c: int, act: int) -> Array:
	match c:
		Rules.C_ENERGY_ABOVE:
			if act == Rules.A_DIVIDE:
				return [1.5, 1.0] # keep a reserve <-> divide the moment it can
			if act == Rules.A_REST:
				return [0.9, 1.5] # rest early <-> keep eating
		Rules.C_ENERGY_BELOW:
			if act == Rules.A_HUNT:
				return [0.9, 1.4] # (a chase costs: a hunter that waits for 70% starves)
			if act in [Rules.A_SEEK_ALGAE, Rules.A_SCAVENGE]:
				return [0.7, 1.4] # eat only when hungry <-> eat whenever
			if act == Rules.A_REST:
				return [0.9, 0.3] # lie low early <-> only when nearly empty
		Rules.C_PREDATOR_NEAR:
			return [150.0, 30.0] # flee at first sight <-> only up close
		Rules.C_PREY_NEAR:
			return [40.0, 150.0]
		Rules.C_PREY_SMALL:
			return [0.4, 0.85]
		Rules.C_CROWD:
			return [6.0, 2.0]
	return []


# What the slider does right now, in plain words (the lines under it):
# where it sits, then one bullet per threshold it moved.
static func summary(deck: Array, bold := 0.5) -> String:
	var parts := ["当前设置：%s" % ("保守" if bold < 0.45 else ("激进" if bold > 0.55 else "适中"))]
	for cd: Dictionary in deck:
		if int(cd.get("st", 0)) != Rules.S_FORAGE:
			continue
		if cd.act == Rules.A_DIVIDE and cd.c1 == Rules.C_ENERGY_ABOVE:
			parts.append("•  能量达到 %s 后尝试分裂。" % Rules.threshold_text(cd.c1, cd.t1))
		elif cd.act == Rules.A_FLEE and cd.c1 == Rules.C_PREDATOR_NEAR:
			parts.append("•  猎手进入 %s 内时逃跑。" % Rules.threshold_text(cd.c1, cd.t1))
		elif cd.act == Rules.A_SEEK_ALGAE and Rules.C_ENERGY_BELOW in [cd.c1, cd.c2]:
			parts.append("•  能量低于 %s 时寻找食物。" % Rules.threshold_text(Rules.C_ENERGY_BELOW, cd.t1 if cd.c1 == Rules.C_ENERGY_BELOW else cd.t2))
		elif cd.act == Rules.A_HUNT and cd.c1 == Rules.C_PREY_NEAR:
			parts.append("•  猎物进入 %s 内时追击。" % Rules.threshold_text(cd.c1, cd.t1))
	return "\n".join(parts)
