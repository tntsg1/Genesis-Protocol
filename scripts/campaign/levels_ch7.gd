class_name LevelsCh7
extends RefCounted
# Chapter 7 · 寒夜篇 (design/第七章_寒夜篇方案.md, DECISIONS Q228–Q241):
# planet two, a frozen sea. Ice walls (nothing crosses or sees through),
# the long night, spores, the life slider, the moving bloom, a heliozoan.
# Levels 30–34. The copy is a first draft for the user to rewrite.

const SHIP_AI := {name = "创生协议", title = "播种飞船 · 主控 AI"}
const SNOW := Color(0.96, 0.55, 0.6) # snow algae, "watermelon snow"

# The maze of 7-1 and 7-5: four ice walls across the dish, the gap in each
# at the other end from the last (a long winding way from left to right).
const MAZE := [
	[Vector2(650, 60), Vector2(650, 1440)], [Vector2(650, 1640), Vector2(650, 2140)],
	[Vector2(950, 0), Vector2(950, 420)], [Vector2(950, 620), Vector2(950, 2200)],
	[Vector2(1250, 0), Vector2(1250, 1480)], [Vector2(1250, 1680), Vector2(1250, 2200)],
	[Vector2(1550, 0), Vector2(1550, 980)], [Vector2(1550, 1180), Vector2(1550, 2200)],
]
# 7-1's smaller maze: two walls, the gap at the bottom, then at the top.
const MAZE_SMALL := [
	[Vector2(760, 60), Vector2(760, 1500)], [Vector2(760, 1700), Vector2(760, 2140)],
	[Vector2(1160, 60), Vector2(1160, 600)], [Vector2(1160, 800), Vector2(1160, 2140)],
]
# The warm pocket walled round in ice, one door facing east (7-1, 7-5).
const ENCLOSURE := [
	[Vector2(568, 1220), Vector2(480, 1308)], [Vector2(480, 1308), Vector2(360, 1340)],
	[Vector2(360, 1340), Vector2(240, 1308)], [Vector2(240, 1308), Vector2(152, 1220)],
	[Vector2(152, 1220), Vector2(120, 1100)], [Vector2(120, 1100), Vector2(152, 980)],
	[Vector2(152, 980), Vector2(240, 892)], [Vector2(240, 892), Vector2(360, 860)],
	[Vector2(360, 860), Vector2(480, 892)], [Vector2(480, 892), Vector2(568, 980)],
]
const DOOR := Vector2(610, 1100)
# 7-5: the pocket, and one more wall between it and the far chamber.
const BOSS_ICE := ENCLOSURE + [[Vector2(1250, 0), Vector2(1250, 1000)], [Vector2(1250, 1200), Vector2(1250, 2200)]]
const NURSERY := {center = Vector2(360, 1100), radius = 240.0}
const FOOD_CHAMBER := {center = Vector2(1840, 1100), radius = 270.0}
const ICE_SEA := {
	name = "星球二 · 冰封海",
	code = "P2-00",
	base = {temp = 0.0, acid = 0.02, radiation = 0.05},
	zones = [
		{key = "nursery", name = "暖水区", en = "WARM POCKET", center = Vector2(360, 1100), radius = 300.0, temp = 14.0, acid = 0.02, radiation = 0.05, light = 0.05, vent = 0.0, tint = Color(1.0, 0.7, 0.45)},
	],
}
const OPEN_ICE := {
	name = "星球二 · 冰封海",
	code = "P2-01",
	base = {temp = 6.0, acid = 0.02, radiation = 0.05},
	zones = [],
}
const COLD_SEA := {
	name = "星球二 · 冰封海",
	code = "P2-02",
	base = {temp = 2.0, acid = 0.02, radiation = 0.05},
	zones = [],
}
# A memory deck the guides teach (7-1): remember the warm pocket, divide
# there, go back to it full.
const HOME_DECK := [
	{c1 = Rules.C_TEMP_BAD, t1 = 0.0, n1 = true, c2 = Rules.C_NONE, t2 = 0.0, act = Rules.A_REMEMBER},
	{c1 = Rules.C_PREDATOR_NEAR, t1 = 60.0, c2 = Rules.C_NONE, t2 = 0.0, act = Rules.A_FLEE},
	{c1 = Rules.C_ENERGY_ABOVE, t1 = 1.0, c2 = Rules.C_NONE, t2 = 0.0, act = Rules.A_DIVIDE},
	{c1 = Rules.C_ENERGY_ABOVE, t1 = 1.0, c2 = Rules.C_TEMP_BAD, t2 = 0.0, act = Rules.A_RETURN},
	{c1 = Rules.C_ENERGY_BELOW, t1 = 1.0, c2 = Rules.C_SEE_ALGAE, t2 = 0.0, act = Rules.A_SEEK_ALGAE},
]

const LEVELS := [
	{
		id = "7-1", index = 30, name = "冰缝", en = "THE ICE MAZE", depth = 0.4,
		director = SHIP_AI,
		teach = "记忆泡：记住一个地方，再回去",
		arrival2 = true,
		brief = "第二颗星球的海面结着厚冰。冰下的水很冷，只有一小块暖水区能让细胞分裂。\n\n暖水区被冰墙围着，只有一扇门，里面不长雪藻。细胞要出门找吃的，吃饱了再回来分裂。外面的冰水很大，没有记忆，很难找回那扇门。\n\n给你的生命装上「记忆泡」：在暖水区「记住这里」，吃饱以后「回到记忆点」。后代也记得这个地方。",
		ai_log = "研究日志 0030：冰封海到了。冰缝像迷宫一样，细胞看不见冰墙另一边。\n\n地球上的细菌也有一种很短的“记忆”：它们会比较刚才和现在的环境，决定往哪里游。",
		world = {
			name = "星球二 · 冰封海",
			layout = ICE_SEA,
			lights = [[Vector2(1100, 1100), 1000.0, 0.4], [Vector2(820, 1100), 260.0, 0.8]],
			algae_cap = 700,
			algae_seed = [450, 22.0],
			algae_dark = 0.0,
			walls = ENCLOSURE,
			divide_min_temp = 8.0,
			species = [],
		},
		release = {at = Vector2(360, 1100), count = 20},
		lifespan = 400.0,
		time_limit = 360.0,
		budget = 12, star_budget = 9,
		genes_open = [0, 1, 4, 5],
		fixed = {2: 1.0, 3: 1.0, 6: 4.0, 7: 3.0},
		temp_fixed = 12.0,
		organ_slots = 1,
		require_organs = ["memory"],
		pages_open = ["genome", "rules", "library", "handbook"],
		interventions = ["nutrient", "membrane", "current"],
		goal = {kind = "alive_end", n = 100, text = "第 6 分钟时，种群至少有 100 只。"},
		challenge = {kind = "count_by", from = 0.0, by = 240.0, n = 50, text = "第 4 分钟之前，种群达到 50 只。"},
		threats = ["新器官：记忆泡\n「记住这里」把现在的位置存下来（只记一个地方），不占用这一拍；「回到记忆点」游回去，被冰挡住时沿着冰壁绕。分裂出来的后代也记得。", "\n太冷不能分裂\n冰下的水只有 0°C，细胞在这里不能分裂。只有左边的暖水区（14°C）可以。", "\n冰墙\n冰墙挡路，也挡视线：细胞看不见冰墙另一边的雪藻。"],
		hints = ["细胞是不是吃饱了却回不到暖水区？", "是不是一直在暖水区附近转，找不到雪藻？"],
		tips = ["第一张卡：「不 温度不适 → 记住这里」。细胞在暖水区里就会记住那里。", "加一张：「能量高于 100% 且 温度不适 → 回到记忆点」，吃饱就回去分裂。", "按 4 用洋流把第一批细胞往迷宫里送一段。"],
		tutorial = true,
	},
	{
		id = "7-2", index = 31, name = "长夜与芽孢", en = "THE LONG NIGHT", depth = 0.8,
		director = SHIP_AI,
		teach = "芽孢：熬过长夜",
		brief = "这颗星球转得很慢，长夜一来，光就没了，水会冻到冰点以下。普通细胞熬不过一个长夜。\n\n给你的生命装上「芽孢外壳」。天黑前把自己封进芽孢，不吃不动、冻不死；天亮再发芽。\n\n形成芽孢和发芽都要时间：太晚形成会冻死，太早又白白浪费了白天。",
		ai_log = "研究日志 0031：长夜来了。\n\n地球上的枯草芽孢杆菌遇到坏环境，会把自己变成芽孢。芽孢能在土里睡上几百年，等条件好了再醒过来。",
		world = {
			name = "星球二 · 冰封海",
			layout = OPEN_ICE,
			lights = [[Vector2(1100, 1100), 760.0, 0.6]],
			algae_cap = 500,
			algae_seed = [320, 22.0],
			algae_dark = 0.0,
			walls = [[Vector2(700, 600), Vector2(1000, 520)], [Vector2(1300, 1600), Vector2(1600, 1500)]],
			night_phase = true,
			species = [],
		},
		events = [{kind = "cycle", day = 70.0, night = 45.0, cold = -20.0, warm = 6.0, offset = 0.0}],
		release = {at = Vector2(1100, 1100), count = 30},
		time_limit = 360.0,
		budget = 12, star_budget = 9,
		genes_open = [0, 1, 4, 5],
		fixed = {2: 1.0, 3: 1.0, 6: 4.0, 7: 3.0},
		temp_fixed = 12.0,
		organ_slots = 1,
		require_organs = ["spore"],
		pages_open = ["genome", "rules", "library", "handbook"],
		interventions = ["nutrient", "membrane", "brine", "current"],
		goal = {kind = "nights", nights = 3, n = 60, text = "熬过 3 个长夜：第三次天亮时，种群至少有 60 只。"},
		challenge = {kind = "never_frozen", n = 80, text = "被冻死的细胞不超过 80 只。"},
		threats = ["新器官：芽孢外壳\n能把自己封进芽孢。形成要约 8 秒（这时最脆弱），之后不耗能、不怕冷、不会被吃；离开芽孢时要先发芽约 8 秒。", "\n新状态：芽孢\n在高级编辑里添加「芽孢」状态，会自动配好两张卡：觅食里「天黑了 → 进入芽孢」，芽孢里「天亮了 → 进入觅食」。", "\n长夜\n每 115 秒里有 45 秒是长夜：全暗，水温降到 -20°C，普通细胞几十秒就会冻死。右上角会倒数下一次天黑和天亮。", "\n新工具：撒盐（按 3）\n在一片水里撒盐，60 秒内那里不结冰。原型是海冰里的盐水通道。"],
		hints = ["长夜里冻死的多吗？芽孢要在天黑之前就开始形成。", "白天是不是长得太慢？天亮后要先发芽 8 秒。"],
		tips = ["添加「芽孢」状态，它会自动配好「天黑了 → 进入芽孢」和「天亮了 → 进入觅食」。", "想更稳：在觅食里把「天黑了」换成更早的信号，比如「能量高于 80%」时就先回芽孢……或者在长夜前撒盐。", "繁殖调高，白天多生一些，熬夜的芽孢就多。"],
		tutorial = true,
	},
	{
		id = "7-3", index = 32, name = "慢生活", en = "THE SLOW LIFE", depth = 1.3,
		director = SHIP_AI,
		teach = "寿命：长寿少生，还是短命多生",
		brief = "冰下的水一直很冷，雪藻长得极慢，食物少，但很稳定。\n\n这里已经住着冰晶游丝：它们活得很久，分裂得很慢。\n\n新开放了「寿命」：寿命越长，活得越久，但分裂需要的能量越多；寿命越短，分裂越便宜。",
		ai_log = "研究日志 0032：在极冷的海水里，有些细菌几天才分裂一次，却能活得很久。\n\n快速繁殖在这里不一定是好事。",
		world = {
			name = "星球二 · 冰封海",
			layout = COLD_SEA,
			lights = [[Vector2(1100, 1100), 760.0, 0.45]],
			algae_cap = 420,
			algae_seed = [260, 22.0],
			algae_dark = 0.0,
			algae_rates = [0.8, 0.6],
			species = [
				{label = "冰晶游丝", params = {name = "冰晶游丝", color = Color(0.72, 0.86, 0.98), diet = 0, radius = 5.5, speed = 1.6, vision = 2.4,
					armor = 1.0, attack = 1.0, fertility = 1.8, efficiency = 3.6, neural = 3.0, lifespan = 240.0, cohesion = 0.3,
					temp_opt = 2.0, temp_tol = 3.0}, spawn = [[Vector2(1100, 1100), 30, 600.0]]},
			],
		},
		release = {at = Vector2(1100, 1100), count = 20},
		lifespan = 150.0,
		time_limit = 420.0,
		budget = 12, star_budget = 9,
		genes_open = [0, 1, 4, 5],
		fixed = {2: 1.0, 3: 1.0, 6: 3.0, 7: 3.0},
		temp_fixed = 4.0,
		life_open = true,
		organ_slots = 1,
		pages_open = ["genome", "rules", "library", "handbook"],
		interventions = ["nutrient", "membrane", "current"],
		goal = {kind = "alive_end", n = 40, text = "第 7 分钟时，种群至少有 40 只。"},
		challenge = {kind = "floor_after", from = 120.0, n = 20, text = "第 2 分钟以后，种群一直不少于 20 只。"},
		threats = ["新开放：寿命\n基因组页「繁殖」下面多了一条「寿命」：×0.5 到 ×2。寿命越长活得越久，分裂需要的能量也越多；寿命越短，分裂越便宜。", "\n食物很少\n雪藻长得极慢，吃光了要很久才长回来。", "\n冰晶游丝\n它们活得很久、分裂得很慢，和你抢同一种食物。"],
		hints = ["是不是先长得很快，然后把雪藻吃光，一起饿死了？", "细胞是不是还没分裂几次就老死了？"],
		tips = ["这里食物少：繁殖别太高，寿命调长一些，让每个细胞活得久一点。", "代谢调高，平时更省能量。"],
		tutorial = true,
	},
	{
		id = "7-4", index = 33, name = "迁徙", en = "MIGRATION", depth = 1.9,
		director = SHIP_AI,
		teach = "跟着季节搬家",
		brief = "冰面上的裂缝随季节移动，阳光透进来的地方也跟着变。雪藻只在有光的地方长。\n\n每个季节结束时，要有足够多的细胞待在当季的雪藻带里。",
		ai_log = "研究日志 0033：地球上的浮游生物也会随季节迁移，跟着食物走。",
		world = {
			name = "星球二 · 冰封海",
			layout = OPEN_ICE,
			lights = [],
			algae_cap = 500,
			algae_seed = [0, 22.0],
			algae_dark = 0.0,
			algae_rates = [1.0, 3.0],
			species = [],
		},
		events = [{kind = "seasons", list = [
			{at = 0.0, pos = Vector2(480, 1100), radius = 300.0, power = 0.9, seconds = 115.0, n = 60},
			{at = 110.0, pos = Vector2(1100, 600), radius = 300.0, power = 0.9, seconds = 115.0, n = 60},
			{at = 220.0, pos = Vector2(1720, 1150), radius = 300.0, power = 0.9, seconds = 120.0, n = 60},
		]}],
		release = {at = Vector2(480, 1100), count = 30},
		time_limit = 335.0,
		budget = 12, star_budget = 9,
		genes_open = [0, 1, 4, 5],
		fixed = {2: 1.0, 3: 1.0, 6: 3.0, 7: 3.0},
		temp_fixed = 6.0,
		organ_slots = 1,
		pages_open = ["genome", "rules", "library", "handbook"],
		interventions = ["nutrient", "membrane", "current"],
		goal = {kind = "seasons", n = 40, ends = [[108.0, Vector2(480, 1100), 320.0], [218.0, Vector2(1100, 600), 320.0], [330.0, Vector2(1720, 1150), 320.0]],
			text = "三个季节结束时，当季的雪藻带里都至少有 40 只。"},
		challenge = {kind = "alive_end", n = 120, text = "实验结束时，种群至少有 120 只。"},
		threats = ["季节\n每个季节约 110 秒。季节一变，雪藻就会在别处长出来，旧的会慢慢烂掉。右上角会显示还剩多少秒、当季雪藻带里有多少只。", "\n跟着食物走\n细胞只看得见附近的东西。离开吃光的地方，四处游走，才能找到新的雪藻带。"],
		hints = ["季节变了，细胞是不是还待在旧地方？", "是不是在路上饿死了？"],
		tips = ["没看见雪藻时，让细胞多游动（别一直休息），才会找到新的雪藻带。", "季节快变时，按 4 用洋流把它们往新的方向推一把。"],
		tutorial = true,
	},
	{
		id = "7-5", index = 34, name = "冰下潜猎者", en = "THE SUN ANIMALCULE", depth = 2.6,
		director = SHIP_AI,
		teach = "Boss：太阳虫",
		brief = "冰缝深处藏着一只巨大的太阳虫。它的身体是个圆球，伸出几十根细长的轴足，在冰缝的交叉口埋伏。碰到轴足的细胞会被粘住，顺着轴足拖进身体。\n\n它隔一段时间会换个地方埋伏。长夜里它也要消耗能量，抓不到东西就会饿死。\n\n两种办法都算赢：让它饿死，或者把足够多的细胞送到它把守的冰缝另一头。",
		ai_log = "研究日志 0034：地球上的太阳虫也是这样捕食的：轴足一碰到猎物，就把它粘住送进身体。",
		world = {
			name = "星球二 · 冰封海",
			layout = ICE_SEA,
			lights = [[Vector2(1100, 1100), 1000.0, 0.35], [Vector2(820, 1100), 260.0, 0.75], [Vector2(1840, 1100), 280.0, 0.85]],
			algae_cap = 600,
			algae_seed = [360, 22.0],
			algae_dark = 0.0,
			walls = BOSS_ICE,
			divide_min_temp = 8.0,
			night_phase = true,
			species = [],
		},
		helio = {spots = [Vector2(980, 1100), Vector2(1000, 760), Vector2(1000, 1440)], energy = 0.9, full = 1600.0, burn = 3.0, reach = 120.0, body = 34.0, catch_rate = 0.9, move_every = 50.0},
		events = [{kind = "cycle", day = 80.0, night = 40.0, cold = -20.0, warm = 0.0, offset = 0.0}],
		release = {at = Vector2(360, 1100), count = 30},
		lifespan = 400.0,
		time_limit = 420.0,
		budget = 15, star_budget = 12,
		genes_open = [0, 1, 4, 5],
		fixed = {2: 1.0, 3: 1.0, 6: 5.0, 7: 3.0},
		temp_fixed = 12.0,
		organ_slots = 2,
		pages_open = ["genome", "rules", "library", "handbook"],
		interventions = ["nutrient", "membrane", "brine", "current"],
		goal = {kind = "helio", zone = FOOD_CHAMBER, n = 30, text = "让太阳虫饿死，或者把至少 30 只细胞送进右边的雪藻腔。"},
		challenge = {kind = "helio_by", seconds = 300.0, text = "在第 5 分钟之前完成。"},
		threats = ["太阳虫\n它的轴足能伸到 120 µm 远，但穿不过冰墙。碰到轴足的细胞会被粘住拖进身体。它换地方的时候会把轴足收回来，这时最安全。", "\n长夜\n每 120 秒里有 40 秒是长夜。芽孢不会被太阳虫粘住，长夜里它照样消耗能量。", "\n两个器官槽\n可以同时装记忆泡和芽孢外壳。"],
		hints = ["细胞是不是成群被粘住了？看看太阳虫埋伏在哪里，绕开它。", "长夜里冻死的多吗？"],
		tips = ["在暖水区「记住这里」，吃饱「回到记忆点」：少在迷宫里乱逛，就少碰到它。", "装芽孢外壳，长夜里变成芽孢：太阳虫抓不到，饿得更快。", "它换地方时轴足会收回来，用洋流把细胞趁这时推过去。"],
		tutorial = true,
	},
]
