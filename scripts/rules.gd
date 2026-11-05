class_name Rules
extends RefCounted
# Behaviour-card vocabulary (GDD 3.2). Ids match SimCore's Cond / Act enums;
# a card is {c1, t1, c2, t2, act} with c = 0 meaning "no condition".

enum { C_NONE, C_ENERGY_BELOW, C_ENERGY_ABOVE, C_SEE_ALGAE, C_PREDATOR_NEAR, C_SEE_PREY, C_CROWD, C_ATTACKED, C_AGE_ABOVE, C_SEE_SHELL, C_TEMP_BAD, C_SIGNAL_A, C_SIGNAL_B, C_PREY_NEAR, C_PREY_SMALL, C_STATE_TIME, C_PEER_STATE, C_IMMUNE, C_O2_ABOVE, C_FAR_MEM, C_NIGHT, C_DAY }
enum { A_SEEK_ALGAE, A_FLEE, A_HUNT, A_FOLLOW, A_REST, A_DIVIDE, A_WANDER, A_SCAVENGE, A_EMIT_A, A_EMIT_B, A_SEEK_COMFORT, A_TO_FORAGE, A_TO_ALERT, A_TO_BREED, A_TO_SLEEP, A_SEEK_SIG_A, A_SEEK_SIG_B, A_SECRETE, A_DISPERSE, A_INDUCE, A_AGGREGATE, A_AVOID_O2, A_SEEK_O2, A_REMEMBER, A_RETURN, A_TO_SPORE }
# Gene-expression states (DECISIONS 第十一轮): each has its own cards.
enum { S_FORAGE, S_ALERT, S_BREED, S_SLEEP, S_SPORE }
# [name, en, what it does to the body, opens]
const STATES := [
	["觅食", "FORAGE", "平常的样子：没有加成", ""],
	["警戒", "ALERT", "游速 +25%，感知范围 +30%，能量消耗 ×1.4。", "2-4"],
	["繁殖期", "BREED", "能量达到 60% 就能分裂，分裂冷却时间减半。不过，能量消耗增加 30%，新生细胞的初始能量也会减少。", "2-5"],
	["休眠", "SLEEP", "进入休眠后，细胞几乎不动，能量消耗降到平时的四分之一，衰老速度也会减慢。", "2-3"],
	["芽孢", "SPORE", "先花约 8 秒形成芽孢（这时最脆弱）。之后不耗能、不衰老、不怕冷也不怕热，也不会被吃。离开芽孢时要先发芽约 8 秒，才能再动。", "7-2"],
]

# [name, threshold kind, min, max, default, step, help]
const CONDS := [
	["无条件", "", 0, 0, 0, 0, "总是成立"],
	["能量低于", "energy", 0.05, 1.5, 0.6, 0.05, "储能占分裂所需能量的比例低于 X（100% = 刚好够分裂）"],
	["能量高于", "energy", 0.05, 1.5, 1.0, 0.05, "储能占分裂所需能量的比例高于 X"],
	["看见藻团", "", 0, 0, 0, 0, "视野里有藻团（只有采集者会去找）"],
	["猎手靠近", "distance", 15, 200, 60, 5, "有能吃掉自己的生物进入 X µm 以内"],
	["看见猎物", "", 0, 0, 0, 0, "视野内有比自己小、可以捕食的生物。仅捕食者可用。"],
	["同伴很多", "count", 1, 12, 3, 1, "60 µm 内至少有 X 个同类"],
	["受到攻击", "", 0, 0, 0, 0, "最近 2 秒内被攻击过。"],
	["年龄超过", "age", 0.05, 1.0, 0.7, 0.05, "已活过寿命的 X"],
	["看见空壳", "", 0, 0, 0, 0, "视野内有死亡生物留下的空壳。仅捕食者可用。"],
	["温度不适", "", 0, 0, 0, 0, "所在水温超出自己的耐温范围"],
	["信号 A 浓", "signal", 0.05, 3.0, 0.1, 0.05, "所在位置的信号 A 浓度高于 X。和“逃离”放在一张卡上时，看不见猎手也会背着气味逃（警报）"],
	["信号 B 浓", "signal", 0.05, 3.0, 0.5, 0.05, "所在位置的信号 B 浓度高于 X。和“逃离”放在一张卡上时，看不见猎手也会背着气味逃"],
	["猎物在", "distance", 15, 200, 80, 5, "有猎物进入 X µm 范围。与「追捕」搭配时，只追范围内的猎物。"],
	["猎物小于", "ratio", 0.3, 0.9, 0.6, 0.05, "视野内有体型小于自身 X 的猎物。与「追捕」搭配时，只追符合条件的猎物。"],
	["在本状态超过", "seconds", 1, 90, 20, 1, "进入当前状态后，已经过了 X 秒。每次切换状态都会重新计时。"],
	["看见同伴在", "state", 0, 3, 2, 1, "视野里有处于 X 状态的同伴（要识别蛋白）。和“跟随同伴”放在一张卡上时，就游向那只同伴"],
	["有免疫记忆", "", 0, 0, 0, 0, "这只细胞身上存着裂囊针的一段 DNA（要记忆片段）。可以加“不”，写给还没有记忆的细胞"],
	["氧气高于", "o2", 0.02, 0.6, 0.08, 0.01, "所在位置的氧气浓度高于 X。"],
	["离记忆点超过", "distance", 20, 600, 150, 10, "离自己记住的地方超过 X µm。还没记住任何地方时不成立（要记忆泡）。"],
	["天黑了", "", 0, 0, 0, 0, "长夜开始了：没有光，水会结冰。"],
	["天亮了", "", 0, 0, 0, 0, "白天：有光，水温正常。"],
]
# [name, help]
const ACTS := [
	["游向藻团", "游到视野里最好的藻团并进食；看不见藻团时这张卡跳过"],
	["逃离", "背向最近的猎手全速游开；没有猎手时跳过。和“信号 A/B 浓”放在一张卡上时，看不见猎手也会背着气味逃（警报）"],
	["追捕", "追上最近的猎物并攻击。正在消化食物时不会执行。"],
	["跟随同伴", "游向同伴的中心；附近没有同伴时跳过"],
	["休息", "慢游，代谢降到 60%"],
	["分裂", "能量够造一个新身体、冷却结束时分成两个；否则跳过"],
	["漫游", "随意游动探索"],
	["食腐", "游向最近的空壳并进食。没有发现空壳时不会执行。"],
	["释放信号 A", "释放信号 A（每秒耗一点能量）；看见猎手时边逃边喊，看得见藻团时边吃边喊；信号会扩散、几秒内消退、随水漂"],
	["释放信号 B", "边慢游边释放信号 B（每秒耗一点能量）"],
	["游向舒适区", "游向视野里更接近自己最适温度的水；温度合适、或四周一样冷热时跳过"],
	["进入觅食", "切换到「觅食」状态，执行该状态下的行为规则。如果已经在觅食，就跳过这条规则。"],
	["进入警戒", "切换到「警戒」状态。跑得更快，看得更远，但更耗能。"],
	["进入繁殖期", "切换到「繁殖期」状态。分裂更快，所需能量更少，但平时更耗能。"],
	["进入休眠", "切换到「休眠」状态。细胞会停止大部分活动，减少能量消耗。"],
	["游向信号 A", "顺着信号 A 的气味游到最浓的地方（要化学感受器，240 µm 内都闻得到）；闻不到、或已经在最浓处时跳过"],
	["游向信号 B", "顺着信号 B 的气味游到最浓的地方；闻不到、或已经在最浓处时跳过"],
	["分泌消化酶", "往水里放消化酶（耗能不少），同时顺带放出一点信号 A；看得见藻团时照样边游过去边吃。酶散得很快：一只放的太稀，一群一起放，硬藻才吃得透"],
	["远离同伴", "朝同伴少的方向游开；身边 60 µm 内没有同伴时跳过"],
	["唤醒潜伏针", "叫醒藏在这只细胞基因里的潜伏针：二十来秒后细胞被撑破，放出 30 个病毒，只会扎别的物种。没有潜伏针时跳过"],
	["聚合", "和身边的同伴聚成一个整体：不再进食，也不会变老，朝光爬；爬到藻场边长成子实体，约两成细胞牺牲成柄，其余变成孢子。已经在目标藻场上时这张卡跳过。"],
	["避开氧气", "游向附近氧气最少的水。已经在无氧的水里时跳过。"],
	["游向氧气", "游向附近氧气最多的水。四周都没有更多氧气时跳过。"],
	["记住这里", "把现在的位置记下来（只记一个地方，新的会覆盖旧的），不占用这一拍，下面的卡照常检查。分裂出来的后代也记得（要记忆泡）。"],
	["回到记忆点", "游回记住的地方；被冰挡住时沿着冰壁绕。还没记住任何地方、或已经在那里时跳过（要记忆泡）。"],
	["进入芽孢", "切换到「芽孢」状态：先花约 8 秒形成芽孢，形成后不耗能、不怕冷、不会被吃（要芽孢外壳）。"],
]
const SLOTS := [3, 4, 5, 6, 8]
# Where each library piece opens in the campaign (DECISIONS 第十轮 Q7/Q11):
# a level id ("1-4") or a whole chapter ("2"). The sandbox has them all.
const COND_OPENS := ["", "1-3", "1-3", "1-3", "1-3", "2-1", "1-5", "2-2", "1-5", "2", "1-4", "3-1", "3-4", "2-1", "2-1", "2-3", "3-2", "4-2", "6-3", "7-1", "7-2", "7-2"]
const ACT_OPENS := ["1-3", "1-3", "2-1", "1-5", "1-3", "1-3", "1-3", "2", "3-1", "3-4", "1-4", "2-3", "2-4", "2-5", "2-3", "3-1", "3-4", "3-3", "4-1", "4-3", "5-1", "6-3", "6-4", "7-1", "7-1", "7-2"]


# “不” on a condition and “或” between two open from level 7 (DECISIONS Q21).
const LOGIC_OPENS := "2-2"


static func logic_open(level_id: String) -> bool:
	return level_id == "" or _rank(level_id) >= _rank(LOGIC_OPENS) - 0.001


static func _rank(at: String) -> float:
	var p := at.split("-")
	return float(p[0]) + (float(p[1]) * 0.01 if p.size() > 1 else 0.0)


static func opens_at(kind: String, id: int) -> String:
	return COND_OPENS[id] if kind == "cond" else ACT_OPENS[id]


# Bit masks of the pieces mutation may use in a level ("" = the sandbox: all):
# open there, and the organ it needs installed (scripts/organs.gd).
static func masks(level_id: String, organs: Array) -> Dictionary:
	if level_id == "":
		return {cond_mask = 0xFFFFFFFF, act_mask = 0xFFFFFFFF, logic = true}
	var cm := 0
	var am := 0
	for c in range(1, CONDS.size()):
		if piece_open("cond", c, level_id) and Organs.has_for("cond", c, organs):
			cm |= 1 << c
	for a in ACTS.size():
		if piece_open("act", a, level_id) and Organs.has_for("act", a, organs):
			am |= 1 << a
	return {cond_mask = cm, act_mask = am, logic = logic_open(level_id)}


# Is a piece usable in this level ("" = the sandbox)?
static func piece_open(kind: String, id: int, level_id: String) -> bool:
	return level_id == "" or _rank(opens_at(kind, id)) <= _rank(level_id) + 0.001


# Does the piece open in exactly this level (marked 新 there)?
static func piece_new(kind: String, id: int, level_id: String) -> bool:
	# (1-3 opens the whole library at once: nothing there is "newer".)
	return level_id != "" and level_id != "1-3" and opens_at(kind, id) == level_id


static func opens_text(kind: String, id: int) -> String:
	var at := opens_at(kind, id)
	if at.contains("-"):
		return "第 %s 关解锁" % at
	return "第%s章解锁" % ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"][clampi(int(at), 0, 10)]


static func card(c1: int, t1: float, c2: int, t2: float, act: int) -> Dictionary:
	return {c1 = c1, t1 = t1, c2 = c2, t2 = t2, act = act}


static func slots(neural: float) -> int:
	return SLOTS[clampi(roundi(neural), 1, 5) - 1]


# How many states a species can use (DECISIONS 第十一轮 Q20: the neural gene).
static func max_states(neural: float) -> int:
	return [1, 1, 2, 3, 5][clampi(roundi(neural), 1, 5) - 1]


static func state_open(st: int, level_id: String) -> bool:
	return STATES[st][3] == "" or level_id == "" or _rank(STATES[st][3]) <= _rank(level_id) + 0.001


# The state a "进入 X" action goes to, or -1.
static func target_state(act: int) -> int:
	if act == A_TO_SPORE:
		return S_SPORE
	return act - A_TO_FORAGE if act >= A_TO_FORAGE and act <= A_TO_SLEEP else -1


# The instincts every species had before decks existed (same as SimCore).
static func default_deck(diet: int) -> Array:
	var d := [card(C_PREDATOR_NEAR, 60.0, C_NONE, 0.0, A_FLEE)]
	if diet == 1:
		d.append(card(C_ENERGY_BELOW, 1.0, C_SEE_PREY, 0.0, A_HUNT))
		d.append(card(C_ENERGY_ABOVE, 1.0, C_NONE, 0.0, A_DIVIDE))
		d.append(card(C_ENERGY_BELOW, 1.0, C_SEE_SHELL, 0.0, A_SCAVENGE))
		d.append(card(C_ENERGY_BELOW, 0.6, C_NONE, 0.0, A_REST)) # lurk
	else:
		d.append(card(C_ENERGY_ABOVE, 1.0, C_NONE, 0.0, A_DIVIDE))
		d.append(card(C_ENERGY_BELOW, 1.0, C_SEE_ALGAE, 0.0, A_SEEK_ALGAE))
		d.append(card(C_ENERGY_ABOVE, 1.0, C_NONE, 0.0, A_REST))
	return d


static func has_threshold(c: int) -> bool:
	return CONDS[c][1] != ""


static func threshold_text(c: int, t: float) -> String:
	match CONDS[c][1]:
		"energy", "age": return "%d%%" % roundi(t * 100.0)
		"distance": return "%d µm" % roundi(t)
		"count": return "%d" % roundi(t)
		"signal": return "%.2f" % t
		"ratio": return "我的 %d%%" % roundi(t * 100.0)
		"seconds": return "%d 秒" % roundi(t)
		"state": return STATES[clampi(roundi(t), 0, 4)][0]
		"o2": return "%d%%" % roundi(t * 100.0)
	return ""


static func cond_text(c: int, t: float) -> String:
	if c == C_NONE:
		return ""
	match c:
		C_PREDATOR_NEAR: return "猎手进入 %s" % threshold_text(c, t)
		C_CROWD: return "同伴 ≥ %s" % threshold_text(c, t)
		C_PREY_NEAR: return "猎物在 %s 内" % threshold_text(c, t)
		C_PEER_STATE: return "看见%s中的同伴" % threshold_text(c, t)
	if has_threshold(c):
		return "%s %s" % [CONDS[c][0], threshold_text(c, t)]
	return CONDS[c][0]


static func card_text(cd: Dictionary) -> String:
	var parts := []
	for k in [1, 2]:
		var c: int = cd["c%d" % k]
		if c != C_NONE:
			parts.append("没有免疫记忆" if c == C_IMMUNE and cd.get("n%d" % k, false) else ("不 " if cd.get("n%d" % k, false) else "") + cond_text(c, cd["t%d" % k]))
	var cond := "总是" if parts.is_empty() else (" 或 " if cd.get("any", false) else " 且 ").join(parts)
	return "%s → %s" % [cond, ACTS[cd.act][0]]


# An earlier card with the same conditions whose action can always be done
# (rest, wander, signals) takes every tick this card could: its index, or -1.
static func _shadowed_by(deck: Array, k: int) -> int:
	var key := func(cd: Dictionary) -> Array:
		var a := [[cd.c1, snappedf(cd.t1, 0.001), cd.get("n1", false)], [cd.c2, snappedf(cd.t2, 0.001), cd.get("n2", false)]]
		a.sort()
		return a + [cd.get("any", false)]
	for j in k:
		if int(deck[j].get("st", 0)) != int(deck[k].get("st", 0)):
			continue
		if deck[j].act in [A_REST, A_WANDER, A_EMIT_A, A_EMIT_B] and key.call(deck[j]) == key.call(deck[k]):
			return j
	return -1


# Warnings the editor shows under a card (GDD 13: error prevention).
# Returns one message per card ("" when fine), for a given diet.
static func warnings(deck: Array, diet: int) -> Array:
	var out := []
	var blocked := {} # per state: an unconditional card above ends that state's list
	var used_states := {}
	for cd: Dictionary in deck:
		used_states[int(cd.get("st", 0))] = true
	for k in deck.size():
		var cd: Dictionary = deck[k]
		var st := int(cd.get("st", 0))
		var msg := ""
		var conds := [[cd.c1, cd.t1], [cd.c2, cd.t2]]
		var goes := target_state(cd.act)
		if blocked.get(st, false):
			msg = "上面那张新卡还空着：给它拖进条件，这张就会恢复" if blocked[st] is String else "上面有一张没有条件的卡，这张永远不会被检查到"
		elif goes == st:
			msg = "已经在“%s”状态里了，这张永远做不到" % STATES[st][0]
		elif goes >= 0 and not used_states.has(goes):
			msg = "“%s”状态里还没有卡：进去以后只会漫游，也出不来" % STATES[goes][0]
		elif diet != 1 and (cd.act == A_HUNT or cd.act == A_SCAVENGE):
			msg = "%s没有捕食器官，这个动作永远做不到" % ["采集者", "", "化能生命", "生产者"][clampi(diet, 0, 3)]
		elif diet == 1 and cd.act == A_SEEK_ALGAE:
			msg = "捕食者不吃藻团，这个动作永远做不到"
		elif diet != 1 and ([cd.c1, cd.c2].any(func(c: int) -> bool: return c in [C_SEE_PREY, C_SEE_SHELL, C_PREY_NEAR, C_PREY_SMALL])):
			msg = "%s不会寻找猎物或空壳，这个条件永远不成立" % ["采集者", "", "化能生命", "生产者"][clampi(diet, 0, 3)]
		elif cd.c1 != C_NONE and cd.c1 == cd.c2 and not has_threshold(cd.c1):
			msg = "两个条件重复了"
		elif _shadowed_by(deck, k) >= 0:
			msg = "上面第 %d 张条件一样、动作又总做得到，这张永远轮不到" % (_shadowed_by(deck, k) + 1)
		elif not (cd.get("n1", false) or cd.get("n2", false) or cd.get("any", false)):
			var lo := -INF
			var hi := INF
			for cc in conds:
				if cc[0] == C_ENERGY_ABOVE:
					lo = maxf(lo, cc[1])
				elif cc[0] == C_ENERGY_BELOW:
					hi = minf(hi, cc[1])
			if lo >= hi:
				msg = "能量不可能同时高于 %d%% 又低于 %d%%" % [roundi(lo * 100), roundi(hi * 100)]
		out.append(msg)
		# A card that always applies to an always-possible action ends the deck.
		# (A fresh blank card, “总是 → 漫游”, is one still being filled in.)
		if cd.c1 == C_NONE and cd.c2 == C_NONE and cd.act in [A_REST, A_WANDER]:
			blocked[st] = "new" if cd.act == A_WANDER else true
	return out
