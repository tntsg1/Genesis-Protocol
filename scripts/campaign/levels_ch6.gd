class_name LevelsCh6
extends RefCounted
# Chapter 6 · 播种篇 (design/第六章_播种篇方案.md, DECISIONS Q198–Q227): the
# first planet, a seabed seen side on. Light from above (from 6-2), three
# hot springs at the bottom whose sulfide feeds chemosynthetic life and soaks
# up oxygen (so the deep water round them stays anoxic: the refuge), and the
# oxygen field. Levels 25–29. The copy here is a first draft for the user to
# rewrite (feedback: user copy is final).

# The seabed: three hot springs along the bottom.
const SEABED := {
	name = "星球一 · 热泉海床",
	code = "P1-00",
	base = {temp = 12.0, acid = 0.02, radiation = 0.05},
	zones = [
		{key = "s1", name = "热泉口", en = "HOT SPRING", center = Vector2(400, 1480), radius = 230.0, temp = 22.0, acid = 0.02, radiation = 0.05, light = 1.0, vent = 0.0, chem = 1.0, tint = Color(1.0, 0.58, 0.3)},
		{key = "s2", name = "热泉口", en = "HOT SPRING", center = Vector2(1100, 1930), radius = 230.0, temp = 22.0, acid = 0.02, radiation = 0.05, light = 1.0, vent = 0.0, chem = 1.0, tint = Color(1.0, 0.58, 0.3)},
		{key = "s3", name = "热泉口", en = "HOT SPRING", center = Vector2(1800, 1480), radius = 230.0, temp = 22.0, acid = 0.02, radiation = 0.05, light = 1.0, vent = 0.0, chem = 1.0, tint = Color(1.0, 0.58, 0.3)},
	],
}
const SPRINGS := [Vector2(400, 1480), Vector2(1100, 1930), Vector2(1800, 1480)]
const LIGHT_BAND := [330.0, 1000.0, 0.6] # full light above y 330, none below 1000
const OXYGEN := {on = true, start = 0.0, emit = 0.02, harm = 16.0, decay = 0.0015, sulfide = 0.05}
const SHIP_AI := {name = "创生协议", title = "播种飞船 · 主控 AI"}
const SULFUR_COLOR := Color(0.93, 0.62, 0.3)
const DAWN_COLOR := Color(0.42, 0.8, 0.5)

# 硫泉游丝 as a level places it (DECISIONS Q213: the player's look, these numbers).
const SULFUR := {name = "硫泉游丝", color = SULFUR_COLOR, diet = 2, radius = 5.5, speed = 1.8, vision = 2.0, armor = 1.0,
	attack = 1.0, fertility = 2.6, efficiency = 3.0, neural = 3.0, lifespan = 120.0, cohesion = 0.3, temp_opt = 22.0, temp_tol = 3.0,
	resp = 1, reseed = false, organ_mask = 0}
# 晨光丝 as a level places it.
const DAWN := {name = "晨光丝", color = DAWN_COLOR, diet = 3, radius = 5.0, speed = 1.6, vision = 2.0, armor = 1.0,
	attack = 1.0, fertility = 2.8, efficiency = 3.0, neural = 3.0, lifespan = 120.0, cohesion = 0.2, temp_opt = 12.0, temp_tol = 3.0,
	speed_mult = 0.6, resp = 0}


# 硫泉游丝 already living at the three springs (25 / 15 at each).
const SULFUR_AT_SPRINGS := {label = "硫泉游丝", role = "sulfur", params = SULFUR,
	spawn = [[Vector2(400, 1480), 25, 90.0], [Vector2(1100, 1930), 25, 90.0], [Vector2(1800, 1480), 25, 90.0]]}
const SULFUR_FEW := {label = "硫泉游丝", role = "sulfur", params = SULFUR,
	spawn = [[Vector2(400, 1480), 15, 80.0], [Vector2(1100, 1930), 15, 80.0], [Vector2(1800, 1480), 15, 80.0]]}


const LEVELS := [
	{
		id = "6-1", index = 25, name = "着陆", en = "LANDFALL", depth = 1.2,
		director = SHIP_AI,
		teach = "化能合成：硫化酶与热泉",
		role = "sulfur",
		brief = "播种舱已经落在这颗星球的海底。这里没有阳光，水里也没有氧气，唯一的能量来自海床上的热泉。\n\n热泉冒出的硫化物可以被分解来获得能量。给你的生命装上「硫化酶」，让它们靠热泉活下来。\n\n离热泉越远，能拿到的能量越少。挤在同一个热泉口的细胞太多，也会互相抢。",
		ai_log = "研究日志 0025：播种舱着陆成功。这片海底一片漆黑，没有光，也没有氧气。\n\n地球上最早的生命，可能就是在这样的热泉边出现的。先让第一批生命在这里扎下根。",
		world = {
			name = "星球一 · 热泉海床",
			layout = SEABED,
			lights = [],
			algae_cap = 0,
			algae_seed = [0, 22.0],
			oxygen = OXYGEN,
			species = [],
		},
		release = {at = Vector2(1100, 1880), count = 14},
		resp = 1,
		lifespan = 130.0,
		time_limit = 300.0,
		budget = 12, star_budget = 9,
		genes_open = [0, 1, 4, 5],
		fixed = {2: 1.0, 3: 1.0, 6: 3.0, 7: 3.0},
		organ_slots = 1,
		require_organs = ["sulfase"],
		pages_open = ["genome", "rules", "library", "handbook"],
		interventions = ["membrane", "heat", "current"],
		goal = {kind = "alive_end", n = 60, text = "第 5 分钟时，种群至少有 60 只。"},
		challenge = {kind = "zones_held", zones = SPRINGS, radius = 260.0, n = 10, text = "第 5 分钟时，三个热泉口各有至少 10 只你的生命。"},
		threats = ["新器官：硫化酶\n装上后，生命不再吃藻团，而是分解热泉冒出的硫化物来获得能量。待在热泉口附近能量最多，离得越远越少。\n原型是地球深海热泉边的硫细菌，它们不靠阳光也能生活。", "\n热泉口\n海床上有三个热泉口。挤在同一个热泉口的细胞越多，每只分到的能量越少。", "\n离开热泉\n离开热泉的细胞拿不到能量，很快会饿死。"],
		hints = ["细胞是不是游离热泉太远，饿死在半路？", "同一个热泉口挤太多，每只分到的能量就少了。"],
		tips = ["装上「硫化酶」后，「游向藻团」这张卡会让细胞游向热泉。", "速度不用太高：热泉附近能量足够，游得快只是白白耗能。", "用洋流把一部分细胞送到另外两个热泉口。"],
		tutorial = true,
	},
	{
		id = "6-2", index = 26, name = "第一缕氧", en = "FIRST BREATH", depth = 2.0,
		director = SHIP_AI,
		teach = "光合作用：光合膜与氧气",
		role = "dawn",
		brief = "海床上方的浅水里有阳光照进来。这次你要设计一种会晒光的生命：给它装上「光合膜」，它就能靠光制造养分。\n\n光合作用会放出氧气。它们长得越多，水里的氧气就越多。\n\n上一关种下的硫泉游丝还在热泉边生活。",
		ai_log = "研究日志 0026：浅水区的光照足够了。\n\n地球上第一批会放氧的生命叫蓝细菌。正是它们让地球的海洋和大气里有了氧气。我们来重演这一步。",
		world = {
			name = "星球一 · 热泉海床",
			layout = SEABED,
			lights = [],
			light_band = LIGHT_BAND,
			algae_cap = 0,
			algae_seed = [0, 22.0],
			oxygen = OXYGEN,
			species = [SULFUR_AT_SPRINGS],
		},
		release = {at = Vector2(1100, 420), count = 20},
		resp = 0,
		lifespan = 130.0,
		time_limit = 300.0,
		budget = 12, star_budget = 9,
		genes_open = [0, 1, 4, 5],
		fixed = {2: 1.0, 3: 1.0, 6: 3.0, 7: 3.0},
		organ_slots = 1,
		require_organs = ["photo"],
		pages_open = ["genome", "rules", "library", "handbook"],
		interventions = ["nutrient", "membrane", "heat", "current"],
		goal = {kind = "alive_end", n = 90, text = "第 5 分钟时，晨光丝至少有 90 只。"},
		challenge = {kind = "o2_end", frac = 0.05, text = "第 5 分钟时，水里的平均氧气达到 5%。"},
		threats = ["新器官：光合膜\n装上后，生命不再进食，只靠光获得能量，越亮越多。它会往水里放出氧气。\n光合膜让细胞游得更慢（-40%）。", "\n光从上方照下来\n海床上方的浅水最亮，越往下越暗，热泉附近完全没有光。", "\n氧气\n水里的氧气会慢慢扩散，也会慢慢消失。热泉冒出的硫化物会吸掉附近的氧气。画面上淡淡的青色就是氧气，按 X 进入分析视图可以看清浓度。"],
		hints = ["晨光丝是不是游到了暗处？没有光就没有能量。", "挤在一起的晨光丝会互相挡光，每只拿到的光就少了。"],
		tips = ["装上「光合膜」后，「游向藻团」这张卡会让细胞游向更亮的地方。", "繁殖调高一些：光足够的时候，多分裂就能多放氧。", "被挤到下面的细胞可以用洋流送回浅水。"],
		tutorial = true,
	},
	{
		id = "6-3", index = 27, name = "氧气灾难", en = "THE GREAT OXIDATION", depth = 2.8,
		director = SHIP_AI,
		teach = "氧气的毒性：避开氧气与避难所",
		brief = "晨光丝长得越来越多，水里的氧气也越来越浓。\n\n对硫泉游丝来说，氧气是毒。氧气浓度超过 8% 的水会让它们不断掉能量，越浓掉得越快。\n\n这一关你同时设计两种生命：晨光丝负责把氧气推高，硫泉游丝要想办法躲进没有氧气的地方。热泉附近的硫化物会吸掉氧气，那里是它们的避难所。\n\n要么救下它们，要么接受这场灭绝。",
		ai_log = "研究日志 0027：氧气浓度在上升，硫泉游丝开始成片死亡。\n\n地球上也发生过同样的事。大约 24 亿年前，蓝细菌放出的氧气毒死了大批厌氧生命。科学家把它叫作「大氧化事件」。",
		world = {
			name = "星球一 · 热泉海床",
			layout = SEABED,
			lights = [],
			light_band = LIGHT_BAND,
			algae_cap = 0,
			algae_seed = [0, 22.0],
			oxygen = {on = true, start = 0.12, emit = 0.02, harm = 16.0, decay = 0.0015, sulfide = 0.05},
			species = [],
		},
		release = {at = Vector2(1100, 420), count = 50},
		release_b = {at = Vector2(1100, 1250), count = 70},
		b_may_die = true,
		species = [
			{label = "晨光丝", name = "晨光丝", role = "dawn", organs = ["photo"], genes = [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 3.0, 3.0]},
			{label = "硫泉游丝", name = "硫泉游丝", role = "sulfur", organs = ["sulfase"], genes = [2.0, 2.0, 1.0, 1.0, 2.5, 3.0, 3.0, 3.0],
				deck = [
					{c1 = Rules.C_ENERGY_ABOVE, t1 = 1.0, c2 = Rules.C_NONE, t2 = 0.0, act = Rules.A_DIVIDE},
					{c1 = Rules.C_ENERGY_BELOW, t1 = 1.0, c2 = Rules.C_SEE_ALGAE, t2 = 0.0, act = Rules.A_SEEK_ALGAE},
					{c1 = Rules.C_NONE, t1 = 0.0, c2 = Rules.C_NONE, t2 = 0.0, act = Rules.A_REST},
				]},
		],
		resp = 1,
		lifespan = 130.0,
		time_limit = 360.0,
		budget = 14, star_budget = 11,
		genes_open = [0, 1, 4, 5],
		fixed = {2: 1.0, 3: 1.0, 6: 3.0, 7: 3.0},
		organ_slots = 1,
		pages_open = ["genome", "rules", "library", "handbook"],
		interventions = ["nutrient", "membrane", "current", "iron"],
		goal = {kind = "o2_end", frac = 0.15, text = "第 6 分钟时，水里的平均氧气达到 15%。"},
		challenge = {kind = "o2_deaths_max", n = 30, text = "被氧气毒死的硫泉游丝不超过 30 只，并且到第 6 分钟时它们还没有灭绝。"},
		threats = ["双物种设计\n点击顶部的「A · 晨光丝」或「B · 硫泉游丝」，分别调整它们。晨光丝越多，氧气涨得越快；硫泉游丝也就越危险。", "\n氧气是毒\n硫泉游丝不用氧气。氧气浓度超过 8% 的水会让它们不断掉能量，越浓掉得越快。", "\n新规则：氧气高于 X、避开氧气、游向氧气\n「避开氧气」会让细胞游向附近氧气最少的水。热泉附近的硫化物会吸掉氧气，那里一直是无氧的。", "\n新工具：撒铁粉（按 5）\n在一片水里撒铁粉，40 秒内把那里的氧气吸掉，造出一块临时的无氧水。原型是远古海洋里的铁：地球上最早的氧气先被海水里的铁吸收，沉成了条带状铁矿。", "\n注意：晨光丝灭绝，实验直接结束。硫泉游丝灭绝不会结束实验，只是拿不到附加挑战的星。"],
		hints = ["氧气没涨上去？看看晨光丝是不是太少，或者挤在一起互相挡光。", "硫泉游丝是不是还在有氧的水里游？"],
		tips = ["硫泉游丝：在第一张加「氧气高于 5% → 避开氧气」，让它们一闻到氧气就往深处躲。", "晨光丝：繁殖调高，让它们在浅水里铺开。", "硫泉游丝被困在有氧的水里时，在它们身边撒铁粉，给它们争取时间。"],
		tutorial = true,
	},
	{
		id = "6-4", index = 28, name = "呼吸", en = "BREATH", depth = 3.6,
		director = SHIP_AI,
		teach = "有氧呼吸：三级食物链",
		brief = "氧气已经遍布浅水。会用氧气的生命，吃同样一口食物，能得到多得多的能量。\n\n这一关你要同时设计三种生命：会晒光的生产者、吃生产者的采集者，以及吃采集者的捕食者。\n\n基因组页新开放了「呼吸方式」开关：厌氧、好氧、兼性三选一。",
		ai_log = "研究日志 0028：氧气不再只是毒药。\n\n地球上的生命后来学会了用氧气分解食物，得到的能量多了十几倍。有了这些能量，更复杂的食物链才建立起来。",
		world = {
			name = "星球一 · 热泉海床",
			layout = SEABED,
			lights = [],
			light_band = LIGHT_BAND,
			algae_cap = 0,
			algae_seed = [0, 22.0],
			oxygen = {on = true, start = 0.08, emit = 0.02, harm = 16.0, decay = 0.0015, sulfide = 0.05, graze = 2.0},
			species = [SULFUR_FEW],
		},
		release = {at = Vector2(1100, 400), count = 80},
		release_b = {at = Vector2(900, 560), count = 40},
		release_c = {at = Vector2(1300, 620), count = 4},
		species = [
			{label = "生产者", name = "晨光丝", role = "dawn", organs = ["photo"], genes = [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 3.0, 3.0]},
			{label = "采集者", name = "采集者 B", role = "grazer", resp = 2, genes = [2.0, 2.5, 1.0, 1.0, 3.0, 3.0, 3.0, 3.0]},
			{label = "捕食者", name = "捕食者 C", role = "hunter", organs = ["cnido"], resp = 2, genes = [2.0, 2.5, 1.0, 2.0, 1.5, 3.0, 3.0, 3.0],
				deck = [
					{c1 = Rules.C_ENERGY_ABOVE, t1 = 1.0, c2 = Rules.C_NONE, t2 = 0.0, act = Rules.A_DIVIDE},
					{c1 = Rules.C_ENERGY_BELOW, t1 = 1.0, c2 = Rules.C_SEE_PREY, t2 = 0.0, act = Rules.A_HUNT},
					{c1 = Rules.C_ENERGY_ABOVE, t1 = 0.6, c2 = Rules.C_NONE, t2 = 0.0, act = Rules.A_REST},
				]},
		],
		resp = 2,
		resp_open = true,
		lifespan = 130.0,
		time_limit = 360.0,
		budget = 16, star_budget = 12,
		genes_open = [0, 1, 3, 4, 5],
		fixed = {2: 1.0, 6: 3.0, 7: 3.0},
		organ_slots = 1,
		pages_open = ["genome", "rules", "library", "handbook"],
		interventions = ["nutrient", "membrane", "current", "iron"],
		goal = {kind = "coexist3", n = 60, n2 = 20, n3 = 6, text = "坚持到第 6 分钟，同时保证：\n生产者至少有 60 只。\n采集者至少有 20 只。\n捕食者至少有 6 只。"},
		challenge = {kind = "o2_end", frac = 0.06, text = "第 6 分钟时，水里的平均氧气保持在 6% 以上。"},
		threats = ["三物种设计\n点击顶部的 A、B、C 分别设计生产者、采集者和捕食者。任何一个物种灭绝，实验都会结束。", "\n新开放：呼吸方式\n基因组页底部的「呼吸」按钮可以切换。\n厌氧：不用氧气，但氧气超过 8% 会中毒。\n好氧：氧气充足时，同样的食物得到约 3 倍能量（现实里大约多 15 倍，这里为了平衡做成 3 倍），缺氧时只有一半左右。\n兼性：两种都会，各差一点，要多花 2 点预算。", "\n采集者吃生产者\n采集者会游向附近的生产者，慢慢把它吃掉。采集者太多，生产者会被吃光。", "\n好氧呼吸会消耗氧气\n好氧生命越多，水里的氧气消耗得越快。"],
		hints = ["哪个物种先灭绝了？看看种群曲线。", "采集者太多，会把生产者吃光；捕食者太多，会把采集者吃光。"],
		tips = ["生产者：繁殖调高，让它们铺满浅水。", "采集者：用好氧呼吸，繁殖不要太高。", "捕食者：保留「总是 → 休息」，没有猎物时少耗能量。"],
		tutorial = true,
	},
	{
		id = "6-5", index = 29, name = "熔岩滤食兽", en = "THE LAVA SIEVE", depth = 4.4,
		director = SHIP_AI,
		teach = "Boss：有孔虫伪足网",
		open = false,
		brief = "海床上出现了一张会慢慢扩大的黏网。",
		ai_log = "研究日志 0029：",
		world = {name = "星球一 · 热泉海床", layout = SEABED, lights = [], light_band = LIGHT_BAND, algae_cap = 0, algae_seed = [0, 22.0], oxygen = OXYGEN, species = []},
		release = {at = Vector2(1100, 500), count = 30},
		time_limit = 360.0,
		budget = 16, star_budget = 12,
		genes_open = [0, 1, 4, 5],
		fixed = {2: 1.0, 3: 1.0, 6: 3.0, 7: 3.0},
		organ_slots = 1,
		pages_open = ["genome", "rules", "library", "handbook"],
		interventions = ["nutrient", "membrane", "current", "iron"],
		goal = {kind = "alive_end", n = 1, text = "（还在做）"},
		challenge = {kind = "alive_end", n = 1, text = "（还在做）"},
		threats = [],
		hints = [],
		tips = [],
	},
]
