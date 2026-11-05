class_name Organs
extends RefCounted
# Organs (DECISIONS 第十三/十四轮): discrete parts in a few organ slots, apart
# from the gene budget. Each opens in a campaign level, may change the body
# (diet, size) and decides which rule pieces the species can use: no
# cnidocysts, no hunting. Slots: chapter 2 has 2, chapter 3 has 3, chapter 4
# has 4 (a level's organ_slots); chapter 1 has none.
#   id, name, en, opens (level id), desc, needs {cond: [...], act: [...]}
#   body: what it changes in the species' parameters
#   pair: organs of the same pair exclude each other (pick one)

const LIST := [
	{id = "cnido", name = "刺丝囊", en = "CNIDOCYST", opens = "2-1",
		desc = "利用刺细胞攻击并捕食其他细胞。安装后，生命的体型会变大，寿命也会延长。它只能捕食比自己小的细胞，不能再吃藻团。",
		needs = {cond = [Rules.C_SEE_PREY, Rules.C_PREY_NEAR, Rules.C_PREY_SMALL, Rules.C_SEE_SHELL], act = [Rules.A_HUNT, Rules.A_SCAVENGE]},
		body = {diet = 1, radius = 7.0, lifespan = 150.0}, pair = "diet"},
	{id = "silica", name = "硅质壳", en = "SILICA SHELL", opens = "2-2", pair = "armour",
		desc = "硅质外壳能挡掉约三分之二的攻击伤害，但会增加重量，速度降低 10%。", needs = {}, body = {bite_taken = 0.35, speed_mult = 0.9}},
	{id = "spines", name = "棘刺", en = "SPINES", opens = "2-2", pair = "armour",
		desc = "捕食者咬到尖刺时会受伤，同时损失能量。", needs = {}, body = {spines = 1.0}},
	{id = "granules", name = "储能颗粒", en = "STORAGE GRANULES", opens = "2-5",
		desc = "日常能耗降低 20%，没食物时能多撑一会儿。不过，分裂需要多积累 20% 的能量。", needs = {}, body = {store = 1.0}},
	{id = "flagellum", name = "鞭毛", en = "FLAGELLUM", opens = "2-4", pair = "motor",
		desc = "最高游速 +30%，转向速度 -30%。适合快速逃跑。", needs = {},
		body = {motor_speed = 1.3, turn_mult = 0.7, move_cost = 1.0}},
	{id = "cilia", name = "纤毛", en = "CILIA", opens = "2-4", pair = "motor",
		desc = "转向速度翻倍，游动耗能减半。停着不动时也能省些能量。", needs = {},
		body = {motor_speed = 1.0, turn_mult = 2.0, move_cost = 0.5, rest_cost = 0.5}},
	{id = "gland", name = "信号腺", en = "SIGNAL GLAND", opens = "3-1",
		desc = "能向水里释放信号 A、B。", needs = {act = [Rules.A_EMIT_A, Rules.A_EMIT_B]}, body = {}},
	{id = "chemo_rec", name = "化学感受器", en = "CHEMORECEPTOR", opens = "3-1",
		desc = "能闻到水里的信号：知道浓不浓，也能顺着气味游过去。", needs = {cond = [Rules.C_SIGNAL_A, Rules.C_SIGNAL_B], act = [Rules.A_SEEK_SIG_A, Rules.A_SEEK_SIG_B]}, body = {}},
	{id = "recog", name = "识别蛋白", en = "RECOGNITION PROTEIN", opens = "3-2",
		desc = "膜上的标记：能认出同伴，看得出它们处在什么状态。", needs = {cond = [Rules.C_PEER_STATE]}, body = {}},
	{id = "memory", name = "记忆泡", en = "MEMORY VESICLE", opens = "7-1",
		desc = "能记住一个地方和一个数。", needs = {}, body = {}},
	{id = "crispr", name = "记忆片段", en = "MEMORY FRAGMENT", opens = "4-2",
		desc = "被扎中时有一点机会把病毒的 DNA 剪碎，活下来，并留下一段当记忆。有记忆的细胞和它的后代，再被扎也不怕。", needs = {cond = [Rules.C_IMMUNE]}, body = {crispr = 0.12}},
	# Chapter 6 (DECISIONS Q211 / Q206 / Q220): the way a species eats. With
	# the cnidocyst they make one pair: one way of eating per species.
	{id = "sulfase", name = "硫化酶", en = "SULFIDE ENZYME", opens = "6-1", pair = "diet",
		desc = "分解热泉冒出的硫化物来获得能量（原型：硫细菌）。装上后不再吃藻团，待在热泉附近就能持续获得能量，离得越远越少。",
		needs = {}, body = {diet = 2}},
	{id = "photo", name = "光合膜", en = "PHOTOSYNTHETIC MEMBRANE", opens = "6-2", pair = "diet",
		desc = "在光里制造养分并放出氧气（原型：蓝细菌）。装上后不再进食，只靠光获得能量，越亮越多；游速降低 40%。",
		needs = {}, body = {diet = 3, speed_mult = 0.6}},
]


static func by_id(id: String) -> Dictionary:
	for o: Dictionary in LIST:
		if o.id == id:
			return o
	return {}


static func open_in(o: Dictionary, level_id: String) -> bool:
	return level_id == "" or Rules._rank(o.opens) <= Rules._rank(level_id) + 0.001


# The organ a piece needs, or "" (chapter 1's pieces need none).
static func needed_for(kind: String, id: int) -> String:
	for o: Dictionary in LIST:
		if (o.needs.get(kind, []) as Array).has(id):
			return o.id
	return ""


static func has_for(kind: String, id: int, organs: Array) -> bool:
	var need := needed_for(kind, id)
	return need == "" or organs.has(need)


# Species parameters with the organs' body changes applied.
static func apply(params: Dictionary, organs: Array) -> Dictionary:
	var p := params.duplicate()
	for id: String in organs:
		p.merge(by_id(id).get("body", {}), true)
	p.organs = organs.duplicate()
	p.organ_mask = mask(organs)
	return p


# An organ's place in LIST: its bit in the mask the cells are drawn with
# (organism.gdshader) and its sequence on the DNA (genome_stage.gdshader).
static func index_of(id: String) -> int:
	for k in LIST.size():
		if LIST[k].id == id:
			return k
	return -1


static func mask(organs: Array) -> int:
	var m := 0
	for id: String in organs:
		var k := index_of(id)
		if k >= 0:
			m |= 1 << k
	return m
