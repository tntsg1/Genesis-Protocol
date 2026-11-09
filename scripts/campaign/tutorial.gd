extends CanvasLayer
# Guided first run of a level (DECISIONS M4 Q7): the AI narrates each step
# in a card and rings the control to use next. Skippable at any time
# ("跳过引导"); it comes back until the level is passed, carrying on from the
# step it was left at (CampaignSave.guide_at).
# 2026-10-29 ("引导弄得更明显一点…只有一个小框，很容易忽略"): a doing step
# lays a pale veil over everything but its target, rings it with a glow and a
# ripple, and the card docks beside the target with a leader line and a step
# count; each new step chimes.

var host: Node2D
var runner: Node
var card: GlassPanel
var text_label: Label
var ring: Control
var target: Control
var step := ""
var skipped := false
var next: Widgets.Pill
var skip_step: Widgets.Pill
var todo_label: Label
var cur: Dictionary = {} # the step on screen: {text, ring, wait, at}
var done_t := -1.0 # > 0: the wait was met, moving on shortly
var had_designer := false # the designer opens a moment after the level
var wait_base := 0 # host.steps_taken when a "steps:N" step began
var veil: ColorRect # the pale veil with a hole over the target
var veil_a := 0.0
var count_label: Label # "第 2 / 5 步"
var resumed := false # this run picked up where the last one stopped

# A step is a line to read ("知道了" goes on), or {text, ring, wait, at, goal}:
# ring = the control to circle, wait = the thing the player does that moves
# the guide on by itself (no button), at = level seconds before it shows,
# goal = the exact target, shown small under the text (the text says why).
const STEPS := {
	"1-1": {
		design = ["这里可以调整生命的基因。\n\n本关只开放速度、感知和繁殖。提高基因等级需要消耗预算。如果想拿到低预算星，就得控制好点数。",
			{text = "光照区在培养皿的另一边。细胞游得太慢，可能还没找到食物就饿死了。\n\n先把速度提高到 3 级。", ring = "speed", wait = "speed3", goal = "把右侧的「速度」滑块拖到 3 级。", why = "速度 3 起，路上饿死之前就能游到光照区。"},
			{text = "基因调整好了。现在点击右下角的「投放到培养皿」，开始实验。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["右上角显示本关目标和剩余时间。\n\n按 {pause} 可以暂停或继续模拟，按 {faster} / {slower} 可以调整模拟速度。",
			{text = "右下角“干预工具”里的“营养投放 {nutrient}”可以撒些食物，引它们过去；消耗的“生物质点”数量就显示在那里。你的生物越多，生物质点攒得越快。", ring = "dock:nutrient"}],
	},
	"1-2": {
		design = [{text = "这里的食物很少，每隔 60 秒才会出现一批。\n\n这关可以调整代谢等级。代谢越高，细胞消耗的能量越少，也就能撑得更久。\n\n先把代谢调到 4 级以上，速度保持在 2 级或以下。", ring = "metab", wait = "metab4", goal = "代谢达到 4 级以上，速度不超过 2 级。", why = "代谢调整完成。现在细胞消耗的能量更少了，应该能撑到下一批食物出现。"},
			{text = "接下来设置细胞的行为。\n\n点击上方的「行为规则」，看看怎么让细胞自己寻找食物、休息和繁殖。", ring = "tab:rules", wait = "page:rules", goal = "点击「行为规则」。"},
			{text = "这里可以直接选择一套行为预设，不需要自己编写规则。\n\n每套预设都有对应的规则卡。细胞每秒都会从上往下检查规则，找到第一条满足条件、且能够执行的规则，然后按照它行动。", ring = "card:0", goal = "查看规则卡，了解细胞如何决定下一步行动。"},
			{text = "这里的食物不多，建议试试「节俭」预设。\n\n细胞平时会尽量休息，减少能量消耗。找到食物后也会多储存一些能量，再进行分裂。\n\n这样繁殖会慢一些，但更容易撑过食物短缺期。", ring = "persona:thrifty", goal = "可以选择「节俭」预设，也可以保留当前设置。"},
			{text = "设置完成后，返回「基因组」，点击右下角的「投放到培养皿」，开始实验。", ring = "go", wait = "release", goal = "返回基因组，投放设计好的生命。"}],
		run = [{text = "单击一只你的生物，再按 {track}（底部“跟随 {track}”）：镜头会跟住它，右边弹出它的扫描卡。", wait = "scan"},
			{text = "扫描卡最下面亮着的那张，就是它此刻在做的事。想细看：暂停（{pause}）后点“单步 ▸”。", ring = "scan:pause"},
			{text = "这关还能用隔离膜：点右下角“隔离膜 {membrane}”，在皿中央营养涌出的地方按住拖一道，把营养圈给你的生物。", ring = "dock:membrane", wait = "used:membrane", goal = "放一道隔离膜", why = "膜挡住了外面的生物，涌出来的营养先归你。结果第 5 分钟才算，等的时候按 {faster} 加速。"}],
	},
	"1-3": {
		design = ["这片藻床不会再长。想一想：如果它们一吃饱就生、一直生下去，藻床会怎样？",
			{text = "点上方“行为规则”。", ring = "tab:rules", wait = "page:rules"},
			{text = "左边的“性子”决定它们多敢花能量：越激进，一攒够能量就生。把它往“保守”拖，让它们吃得更饱才分裂。", ring = "divide", wait = "divide", goal = "“性子”往保守拖（分裂线到 125% 以上）", why = "现在要攒到 1.25 倍以上的能量才分裂：生得少，每只都更饱，藻床撑得更久。右边第 1 张卡也跟着变了。"},
			{text = "再回“基因组”：食物就在脚下，游得快只会白白耗能。把速度降下来。", ring = "speed", wait = "speed", goal = "速度降到最低", why = "不游就几乎不耗能，藻就在嘴边。"},
			{text = "点“投放到培养皿”。", ring = "go", wait = "release"}],
		run = ["盯住右上角的数量：涨得太快就是生多了，后面会一起挨饿。结果要到第 5 分钟才算，按 {faster} 可以加速到 8×。"],
	},
	"1-4": {
		design = ["这批样本有个毛病：吃饱了就休息，从来不分裂。第 2 分钟起水还会变冷。",
			{text = "点上方“行为规则”看看为什么。", ring = "tab:rules", wait = "page:rules"},
			{text = "这关起可以逐张改规则了：点“高级编辑”。", ring = "mode_adv", wait = "mode:advanced"},
			{text = "“休息”排在“分裂”上面：一吃饱就先休息，分裂永远轮不到。按住“分裂”卡右边的 ⋮⋮ 往上拖。", ring = "divide_card", wait = "divide_first", goal = "“分裂”排到“休息”上面", why = "现在一吃饱先分裂；没够分裂的能量时，才轮到休息。"},
			{text = "顺序就是优先级。另外别关右下角的“自然变异”：寒潮里活下来的，靠的是耐冷的突变体。", ring = "mutate"},
			{text = "点“投放到培养皿”。", ring = "go", wait = "release"}],
		run = ["寒潮第 2 分钟到。等的时候可以按 {faster} 加速。",
			{at = 125.0, text = "寒潮来了。规则里那张“温度不适 → 游向舒适区”会让它们自己找暖水；你再帮一把：点右下角“干预工具”里的“局部升温 {heat}”，在生物最多的地方点一下（可选）。", ring = "dock:heat"}],
	},
	"1-5": {
		design = ["冰晶游丝已经占着 3 片藻场。比的是谁先到、谁生得多。",
			{text = "这关没有捕食者，外壳没用；拼的是游得快、生得多。", ring = "race_genes", wait = "race_genes", goal = "外壳调到最低，速度和繁殖各调到 4 级以上", why = "外壳省下的点数，全给了抢地盘最要紧的速度和繁殖。"},
			{text = "这关开放了新性格“抱团”：没事做时游向同伴、聚成一群。投放后一道洋流，就能把整群一起送到藻场。（可选）", ring = "persona:swarm"},
			{text = "点“投放到培养皿”。", ring = "go", wait = "release"}],
		run = [{text = "马上：点右下角的“洋流引导 {current}”（或按 {current}），在你的生物旁按住，朝最近的藻场拖出去，把它们送过去。", ring = "dock:current", wait = "used:current"},
			"地图上标着 A、B、C 三片藻场和比分（你 : 对手）。最后 30 秒里两片占优就赢。"],
	},
	"2-1": {
		design = ["这次你要设计一只捕食者。猎物发现你后会逃跑，得想办法追上它们。",
			{text = "先在左下角的「器官槽」里装上「刺丝囊」。这是捕食器官，没有它就无法捕食其他细胞。", ring = "organ:cnido", wait = "organ:cnido", goal = "安装「刺丝囊」。"},
			{text = "装上刺丝囊后，你的生命就只能以其他细胞为食了。系统也会自动切换到捕食者的行为规则。\n\n点击「行为规则」，看看它会怎么捕食。", ring = "tab:rules", wait = "page:rules", goal = "打开「行为规则」。"},
			# adv = the same step for a player already in the card editor.
			{text = "捕食者有两种性格：\n追猎：发现猎物就追，适合快速捕食和繁殖。\n伏击：只有饿了才追捕猎物，其余时间留在原地等待，节省能量。\n\n这片水域的猎物很多，先试试「伏击」。", ring = "persona:ambush", wait = "ambush", goal = "选择「伏击」性格。", why = "已切换为伏击。没有猎物可追时，捕食者会留在原地休息，减少能量消耗。",
				adv = {text = "找到最后一张「能量低于 60% → 休息」规则卡。\n\n点击条件右边的 ×，把条件改成「总是」。这样没有其他规则可以执行时，捕食者就会停下来休息。", ring = "rest_card", goal = "将最后一张规则卡改为「总是 → 休息」。"}},
			{text = "注意最后一张「总是 → 休息」规则。\n\n细胞会从上往下检查规则。只有前面的规则都不满足时，才会执行这一条。\n\n这样，没有猎物可追时，它就会停下来等待，不会一直游动浪费能量。", ring = "rest_card"},
			{text = "设置完成了。点击「投放到培养皿」，看看它能抓到多少猎物。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["培养皿里有好几种生物，可能不太容易分清。\n\n点击左上角物种列表中你的物种（默认名以「设计物种」开头），就能高亮显示所有同类。再点一次可以取消高亮。",
			"点击一只捕食者，再按 {track} 跟随它。\n\n观察它什么时候开始追猎，什么时候停下来埋伏。"],
	},
	"2-2": {
		design = ["这次你要扮演猎物。培养皿里有 30 只刺猎菌，它们游得比普通细胞快，发现猎物就会追上去攻击。\n\n先给你的细胞做好防护。",
			{text = "先到左下角的器官槽，装一个防御器官。\n\n硅质壳可以减少受到的伤害，棘刺则能伤到攻击你的捕食者。\n\n两种都能用，选一个试试。", ring = "armour", wait = "armour", goal = "安装一种防御器官。"},
			{text = "光靠防御还不够。刺猎菌游得很快，速度太低就很难逃脱。\n\n把速度提高到 3 级以上。", ring = "speed", wait = "speed3", goal = "速度达到 3 级或以上。", why = "速度调整好了。现在细胞有机会甩开刺猎菌了。"},
			{text = "接下来设置逃跑规则。\n\n打开「行为规则」，把左边的「受到攻击」拖到第一张逃跑规则卡上，作为第二个条件。", ring = "flee_card", wait = "flee_attacked", goal = "为逃跑规则添加「受到攻击」条件。"},
			{text = "点击两个条件之间的「且」，把它改成「或」。\n\n这样只要发现捕食者靠近，或者已经受到攻击，细胞就会逃跑。", ring = "flee_join", wait = "flee_or", goal = "将逃跑规则的条件连接方式改成「或」。"},
			{text = "设置好了。现在点击「投放到培养皿」，看看它们能活下来多少。\n\n还有一个功能：点击条件左侧的小圆钮，可以给条件加上「不」，让规则在条件不成立时触发。之后也可以试试。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["点一只自己的细胞，再按 {track} 跟随它。\n\n等刺猎菌靠近时，看看细胞会不会逃跑。对应的规则卡也会亮起来。"],
	},
	"2-3": {
		design = ["这次要设计两个物种。\n\nA 是猎物，吃藻类；B 是捕食者，吃 A。\n\n记住，只要其中一个物种灭绝，实验就会失败。",
			{text = "先调整猎物 A。\n\n猎物游得太快，捕食者可能一直追不上，最后饿死。\n\n先把 A 的速度调低一点。", ring = "prey_genes", wait = "prey_genes", goal = "将 A 的速度降到最低。", why = "猎物速度已降低，捕食者更容易追上它们了。"},
			{text = "点击顶部的「B · 捕食者」，切换到捕食者设计。\n\n刺丝囊已经装好了，行为规则也沿用了上一关的「追捕 + 埋伏」。你可以直接修改。", ring = "slot:1", wait = "slot:1"},
			{text = "这次还开放了「休眠」状态。\n\n捕食者找不到食物时，可以先休眠一段时间，少消耗一些能量。\n\n打开「行为规则」，进入「高级编辑」，点击上方状态栏里的「+」，添加「休眠」。\n\n添加后，进入和退出休眠的规则会自动接好，你可以再修改。", ring = "state_map", wait = "sleep_state", goal = "添加「休眠」状态。"},
			{text = "两个物种都设置好了。\n\n点击「投放到培养皿」，A 和 B 会一起投放。\n\n接下来观察两边的数量，看看能不能都活到第 6 分钟。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["右上角能看到猎物和捕食者各有多少只。\n\n如果猎物快被吃光了，可以按 {membrane} 放置隔离膜，给它们留一块安全的地方。"],
	},
	"2-4": {
		design = ["伏刺藏在藻场里，等猎物靠近就会突然冲出来。等看见它开始追了再逃，通常已经晚了。\n\n这关会用到新的「警戒」状态。进入警戒后，细胞速度提高 25%，感知范围增加 30%，但会消耗更多能量。",
			{text = "伏刺的速度有 5 级，你的细胞目前只有 2 级，得先把速度提上去。\n\n预算不够的话，可以把繁殖降一级。繁殖会慢一点，但后代出生时能带更多能量。", ring = "speed_fert", wait = "speed4", goal = "速度调到 4 级，繁殖降到 2 级。这样刚好用掉 12 点预算。", why = "速度调好了。进入警戒后，细胞才有机会甩开伏刺。"},
			{text = "器官槽里新增了两种运动器官，只能选一种。\n鞭毛：冲得快，但转弯比较慢。\n纤毛：转向灵活，能耗也低一些。\n\n这关建议用鞭毛。伏刺冲得很快，细胞得有足够的速度才能逃开。", ring = "motor"},
			{text = "接下来设置警戒规则。", ring = "tab:rules", wait = "page:rules", goal = "点击上方的「行为规则」。"},
			{text = "打开「高级编辑」，这里可以自己修改每个状态下的行为。", ring = "mode_adv", wait = "mode:advanced", goal = "点击「高级编辑」。"},
			{text = "先添加「警戒」状态。", ring = "state_map", wait = "alert_state", goal = "点击状态图中的「+」，添加「警戒」。", why = "已添加警戒状态，并自动设置了两条规则：\n猎手靠近 → 逃离\n警戒超过 20 秒 → 返回觅食"},
			{text = "现在回到「觅食」，把第一张规则卡的「逃离」改成「进入警戒」。\n\n这样细胞发现猎手后，就会先切换到警戒状态，再加速逃跑。", ring = "to_alert_card", wait = "to_alert", src = "进入警戒", goal = "将觅食状态的第一张规则改为「猎手靠近 → 进入警戒」。", why = "设置好了。发现猎手时，细胞会进入警戒状态。"},
			{text = "现在这条规则的触发距离只有 60 µm，但伏刺在 110 µm 外就会开始冲刺。\n\n把距离调远一些，让细胞早点发现危险。", ring = "to_alert_slider", wait = "alert_far", goal = "将触发距离调到 80 µm 左右。感知 2 级的探测上限约为 78 µm。想看得更远，还需要提高感知等级。", why = "触发距离调好了，细胞会更早进入警戒。"},
			{text = "警戒状态很耗能，一直保持警戒，很容易饿死。\n\n点击上方的「警戒」圆圈，找到「在本状态超过 20 秒」这条规则，把时间缩短一些。", ring = "calm_card", wait = "calm", goal = "将警戒持续时间从 20 秒调到 10 秒左右。", why = "现在警戒 10 秒后，细胞就会返回觅食，减少不必要的能量消耗。"},
			{text = "设置完成了，点击「投放到培养皿」开始实验。\n\n提醒一下，如果开启了自然变异，后代的行为规则可能发生小幅变化。例如，有些细胞的警戒距离会变短。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["看右上角的目标：至少留下 150 只细胞，被吃掉的不能超过 120 只。\n\n点击一只细胞，按 {track} 跟随。看看它遇到伏刺时会不会进入警戒，逃脱后能不能继续觅食。"],
	},
	"2-5": {
		design = ["第二章最后一关。这次只有一只巨噬者，但它的体型是普通细胞的 4 倍，碰到猎物就能直接吞掉，吃饱后还会分裂。\n\n有两种通关方法：躲开它，让它饿死；或者在第 4 分钟时，把种群养到 500 只。\n\n这关会用到新的「繁殖期」状态。",
			{text = "巨噬者的速度是 3 级，你的细胞目前只有 2 级。先把速度提高一点。\n\n这关还解锁了「储能颗粒」，装上后平时更省能量，但分裂也需要攒更多能量。这次要快速繁殖，可以先不装。", ring = "speed", wait = "speed4", goal = "将速度提高到 4 级，总预算控制在 14 点以内。", why = "速度够了。只要及时发现巨噬者，就有机会逃掉。"},
			{text = "接下来调整行为规则。\n\n点击上方的「行为规则」，再打开「高级编辑」。", ring = "mode_adv", wait = "mode:advanced", goal = "打开「高级编辑」。"},
			{text = "巨噬者在 138 µm 外就能发现你的细胞，但现在要等它靠近到 60 µm，细胞才会逃跑。这个距离太近了。\n\n把第一张规则卡的距离调远一点。", ring = "flee_slider", wait = "flee_far", goal = "将逃跑距离调到 80 µm 以上。注意：感知 2 级实际上只能看到约 78 µm，想更早发现巨噬者，还得提高感知等级。", why = "逃跑距离调好了，细胞会尽早躲开巨噬者。"},
			{text = "现在来设置繁殖。\n\n在上方状态图中点击「+」，添加「繁殖期」。", ring = "state_map", wait = "breed_state", goal = "添加「繁殖期」状态。", why = "已添加繁殖期，并自动生成 4 条规则：逃跑、分裂、寻找藻类，以及 40 秒后返回觅食。"},
			{text = "点击「觅食」返回原来的规则。\n\n找到「能量高于 100% → 分裂」，把右边的「分裂」换成「进入繁殖期」。\n\n这样细胞吃饱后，就会先进入繁殖期。", ring = "to_breed_card", wait = "to_breed", src = "进入繁殖期", goal = "将规则改为「能量高于 100% → 进入繁殖期」。", why = "设置好了。繁殖期内，细胞积累到 60% 能量就能分裂，分裂冷却时间也缩短了一半。"},
			{text = "设置完成了。\n\n点击「投放到培养皿」，开始实验。\n\n记得观察巨噬者的位置，尽量别让细胞聚在它附近。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["右上角可以查看巨噬者的数量和剩余能量。\n\n能量耗尽，它就会饿死。如果它开始分裂，说明它吃得太多了。尽量让细胞离它远一点。"],
	},
	# Chapter 6 (first drafts; the user rewrites the copy).
	"6-1": {
		design = ["播种舱已经落在海底。这里没有光，也没有氧气，只有海床上的热泉冒着硫化物。

这次要设计一种能靠热泉活下来的生命。",
			{text = "在左下角的器官槽里装上「硫化酶」。装上后，细胞不再吃藻团，而是分解热泉冒出的硫化物获得能量。", ring = "organ:sulfase", wait = "organ:sulfase", goal = "安装「硫化酶」。", why = "装好了。现在「游向藻团」这张卡会让细胞游向热泉。"},
			{text = "热泉边的能量足够，游得快只是白白耗能。把能量花在繁殖上：把「繁殖」提高到 4 级。", ring = "fert", wait = "fert4", goal = "繁殖达到 4 级。", why = "繁殖快了，热泉口能更快住满。"},
			{text = "设置好了。点击「投放到培养皿」，播种舱会把它们放在中间的热泉口。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["右上角能看到三个热泉口各有多少只你的生命。

左右两个热泉口离得比较远。按 {current} 用洋流把一部分细胞送过去，附加挑战要三个热泉口都住满。"],
	},
	"6-2": {
		design = ["海床上方的浅水里有阳光照进来。这次要设计一种会晒光的生命。

它们越多，水里的氧气就越多。",
			{text = "在器官槽里装上「光合膜」。装上后，细胞不再进食，只靠光获得能量，同时往水里放出氧气。", ring = "organ:photo", wait = "organ:photo", goal = "安装「光合膜」。", why = "装好了。现在「游向藻团」这张卡会让细胞游向更亮的地方。"},
			{text = "光足够的时候，多分裂才能多放氧。把「繁殖」提高到 4 级。", ring = "fert", wait = "fert4", goal = "繁殖达到 4 级。"},
			{text = "设置好了。点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["画面里淡淡的青色和小气泡就是氧气。

按 {analysis} 进入分析视图，再按 {env_layer} 切到「氧气」图层，可以看清哪里有氧、哪里没有。"],
	},
	"6-3": {
		design = ["氧气越来越浓，对硫泉游丝来说却是毒。

这关要同时设计两种生命：A 晨光丝负责把氧气推高，B 硫泉游丝要躲进没有氧气的地方。",
			{text = "点击顶部的「B · 硫泉游丝」，切换过去。", ring = "slot:1", wait = "slot:1"},
			{text = "打开「行为规则」，进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced", goal = "打开「高级编辑」。"},
			{text = "点规则列表下面的「+ 添加规则」，最下面会多出一张空卡。

把左边的「氧气高于」拖到空卡「如果」后面的格子，再把左边的「避开氧气」拖到「那么」后面的格子。条件左边的小圆钮是「不」，这里不要点它。", ring = "add", wait = "avoid_o2_card", src = "避开氧气", goal = "新卡：氧气高于 X → 避开氧气（不带「不」）。", why = "卡加好了。但它排在「总是 → 休息」下面，规则从上往下检查，现在还轮不到它。"},
			{text = "按住这张卡最右边的 ⋮⋮，把它拖到第一张的位置，让躲避比吃东西、休息都优先。", ring = "avoid_handle", wait = "avoid_first", goal = "把「避开氧气」这张卡拖到第一张。", why = "设置好了。硫泉游丝一碰到有氧的水，就会往氧气最少的地方游；热泉附近的硫化物会吸掉氧气，那里就是它们的避难所。"},
			{text = "两个物种都设置好了。点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = [{text = "有硫泉游丝被困在有氧的水里时，按 {phage} 在它们身边撒铁粉：40 秒内那里的氧气会被吸掉。", ring = "dock:iron", wait = "used:iron"}],
	},
	"6-4": {
		design = ["这关要建一条三级食物链：A 生产者晒光，B 采集者吃生产者，C 捕食者吃采集者。

任何一个物种灭绝，实验都会结束。",
			{text = "点击顶部的「B · 采集者」。", ring = "slot:1", wait = "slot:1"},
			{text = "底部新开放了「呼吸」按钮：厌氧、好氧、兼性三选一。

采集者已经设成「好氧」：水里有氧气，有氧时同样的食物能得到约 3 倍能量。如果换成「厌氧」，氧气超过 8% 的水会让它中毒。", ring = "resp"},
			{text = "采集者繁殖太快，会把生产者吃光，然后自己饿死。三个物种的数量要互相牵制。

设置好后，点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["右上角能看到三个物种各有多少只。

如果生产者被吃得太快，可以按 {membrane} 放隔离膜，给它们留一块安全的地方。"],
	},
	"6-5": {
		design = ["海床中央的熔岩滤食兽正在织网。它要靠氧气呼吸：氧气少于 4% 的地方，伪足就会缩回去。

这次设计一种好氧的采集者，帮你把水里的氧气压下去。",
			{text = "采集者吃晨光丝。晨光丝少了，放出的氧气就少了。把「繁殖」提高到 4 级，让采集者多起来。", ring = "fert", wait = "fert4", goal = "繁殖达到 4 级。"},
			{text = "设置好了。点击「投放到培养皿」，采集者会放在上方晨光丝最多的地方。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = [{text = "光靠采集者压不住氧气。按 {phage} 选「撒铁粉」，在网的边缘点一下：40 秒内那里的氧气会被吸掉，伪足就会后退。

按 {analysis} 再按 {env_layer}，能看到哪里的氧气最浓。", ring = "dock:iron", wait = "used:iron"},
			"右上角能看到网的覆盖面积。压到 12% 以下以后，还要再坚持 30 秒。"],
	},
	"7-1": {
		design = ["第二颗星球的冰下很冷，只有左边那块被冰墙围着的暖水区能让细胞分裂，暖水区只有朝右的一扇门。

这关要教你的生命记住回家的路。",
			{text = "在器官槽里装上「记忆泡」。", ring = "organ:memory", wait = "organ:memory", goal = "安装「记忆泡」。"},
			{text = "打开「行为规则」，进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced", goal = "打开「高级编辑」。"},
			{text = "点规则列表下面的「+ 添加规则」，最下面会多出一张空卡。\n\n把左边的「温度不适」拖到空卡「如果」后面的格子，再点它左边的小圆钮，加上「不」；然后把左边的「记住这里」拖到「那么」后面的格子。\n\n这张卡的意思：不冷的时候（在暖水区里），记住这个地方。", ring = "add", wait = "card:remember", src = "记住这里", goal = "新卡：不 温度不适 → 记住这里"},
			{text = "再点一次「+ 添加规则」。\n\n这张卡要两个条件：把「能量高于」拖到「如果」后面，把「温度不适」拖到「且 第二个条件」的格子（这里不加「不」）；再把「回到记忆点」拖到「那么」后面。\n\n意思是：在外面吃饱了、又冷，就回家分裂。", ring = "add", wait = "card:ret", src = "回到记忆点", goal = "新卡：能量高于 100% 且 温度不适 → 回到记忆点"},
			{text = "规则从上往下检查，吃东西的卡会先把这一拍用掉。按住这张卡最右边的 ⋮⋮，把它拖到「游向藻团」那张卡的上面。两张新卡都要拖上去。", ring = "handle:REMEMBER", wait = "before_eat:REMEMBER,RETURN", goal = "「记住这里」和「回到记忆点」都排在「游向藻团」上面", why = "设置好了。吃饱的细胞会沿着冰墙绕回暖水区，后代也记得这个地方。"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["点一只在外面吃饱的细胞，按 {track} 跟随，看它怎么绕过冰墙回家。"],
	},
	"7-2": {
		design = ["这颗星球的长夜很冷，水会冻到 -20°C，普通细胞熬不过去。

这关要学会把自己封进芽孢。",
			{text = "在器官槽里装上「芽孢外壳」。", ring = "organ:spore", wait = "organ:spore", goal = "安装「芽孢外壳」。"},
			{text = "打开「行为规则」，进入「高级编辑」，点击状态图里的「+」，添加「芽孢」状态。

它会自动配好两张卡：觅食里「天黑了 → 进入芽孢」，芽孢里「天亮了 → 进入觅食」。", ring = "state_map", wait = "spore_state", goal = "添加「芽孢」状态。"},
			{text = "形成芽孢要约 8 秒，这时最怕冷。天黑那一刻才开始形成，会冻死一些。

点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = [{text = "长夜快来时，按 {heat} 撒盐，在细胞最多的地方撒一片：那里 60 秒不结冰，正在形成芽孢的细胞就不会冻死。", ring = "dock:brine", wait = "used:brine"}],
	},
	"7-3": {
		design = ["冰下食物很少，但很稳定。这里比的不是谁生得快，而是谁活得稳。",
			{text = "「繁殖」下面新开了「寿命」滑条。把它往右拖到 1.4 左右：活得更久，分裂少一点。", ring = "life", wait = "life_up", goal = "寿命调到 ×1.3 以上。"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["看看种群曲线：寿命短的细胞会先冲高，再一起老死。"],
	},
	"7-4": {
		design = ["雪藻带会随季节移动。每个季节结束时，当季的雪藻带里要有足够多的细胞。",
			{text = "细胞没看见食物时要多游动才找得到新的雪藻带。打开「行为规则」，看看最后一张「能量高于 100% → 休息」：吃饱就停下，季节一变就落后了。可以把它删掉。", ring = "tab:rules", wait = "page:rules", goal = "打开「行为规则」。"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["季节快变时，右上角会提醒新雪藻带的位置。按 {current} 用洋流把细胞往那边推一把。"],
	},
	"7-5": {
		design = ["太阳虫守在暖水区门外。它靠粘住细胞维生，长夜里冷得更耗能。

两条路：别喂它，让它饿死；或者把细胞送到右边的雪藻腔。",
			{text = "这关有两个器官槽：装上「记忆泡」和「芽孢外壳」。", ring = "organ:spore", wait = "organs75", goal = "同时安装「记忆泡」和「芽孢外壳」。"},
			{text = "打开「行为规则」，进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced", goal = "打开「高级编辑」。"},
			{text = "点规则列表下面的「+ 添加规则」，最下面会多出一张空卡。\n\n把「温度不适」拖到「如果」后面，点它左边的小圆钮加上「不」；把「记住这里」拖到「那么」后面。", ring = "add", wait = "card:remember", src = "记住这里", goal = "新卡：不 温度不适 → 记住这里"},
			{text = "再点一次「+ 添加规则」：「如果」拖入「能量高于」，「且 第二个条件」拖入「温度不适」（不加「不」），「那么」拖入「回到记忆点」。", ring = "add", wait = "card:ret", src = "回到记忆点", goal = "新卡：能量高于 100% 且 温度不适 → 回到记忆点"},
			{text = "规则从上往下检查，吃东西的卡会先把这一拍用掉。按住这张卡最右边的 ⋮⋮，把它拖到「游向藻团」那张卡的上面。两张新卡都要拖上去。", ring = "handle:REMEMBER", wait = "before_eat:REMEMBER,RETURN", goal = "两张记忆卡都排在「游向藻团」上面"},
			{text = "点击上方状态图里虚线圈的「+」，添加「芽孢」状态：长夜里变成芽孢，太阳虫就抓不到它们。", ring = "state_map", wait = "spore_state", goal = "添加「芽孢」状态。", why = "少在门外乱逛、长夜里变成芽孢，它就抓不到东西。"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["太阳虫周围那一圈是它的轴足能碰到的范围。它换地方时会把轴足收回来，这时最安全。"],
	},
	"8-1": {
		design = ["这片沼泽分层：上面有光有氧，越往下氧越少、硫化氢越浓。

这关设计两种生命：A 分解者吃空壳，把养分还给水；B 住在最深的泥里，吃硫化氢。",
			{text = "A 已经装好「分解酶」：它不吃藻团，只吃空壳。「游向藻团」这张卡会让它游向空壳。

它用氧呼吸，进了下面的硫化氢会中毒。打开「行为规则」，进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced", goal = "打开「高级编辑」。"},
			{text = "点规则列表下面的「+ 添加规则」，最下面会多出一张空卡。\n\n把左边的「氧气高于」拖到「如果」后面，点它左边的小圆钮加上「不」，把滑块拖到 30% 左右；再把左边的「游向氧气」拖到「那么」后面。\n\n意思是：氧气不到 30% 时（游得太深了），往上游。", ring = "add", wait = "card:up", src = "游向氧气", goal = "新卡：不 氧气高于 X → 游向氧气"},
			{text = "规则从上往下检查，吃东西的卡会先把这一拍用掉。按住这张卡最右边的 ⋮⋮，把它拖到「游向藻团」那张卡的上面。", ring = "handle:SEEK_O2", wait = "before_eat:SEEK_O2", goal = "「游向氧气」排在「游向藻团」上面"},
			{text = "点击顶部的「B · 泥层生物」。它装着硫化酶，是厌氧的，会投在最深处。", ring = "slot:1", wait = "slot:1"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["空壳堆得深的地方，按 {phage} 搅动泥层：30 秒内氧气被带下去，分解者就能下去吃。"],
	},
	"8-2": {
		design = ["你的生命是厌氧的：氧气会毒害它。上层漂着紫光游丝，它特别会用氧。

把它吞进去不消化，它就住在你的细胞里帮你用氧。",
			{text = "先在左下角的器官槽里装上「吞噬泡」：有了它，细胞才能把紫光游丝整个吞进去。", ring = "organ:phago", wait = "organ:phago", goal = "安装「吞噬泡」。"},
			{text = "打开「行为规则」，进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced", goal = "打开「高级编辑」。"},
			{text = "点规则列表下面的「+ 添加规则」，最下面会多出一张空卡。\n\n把左边的「带着共生菌」拖到「如果」后面，点它左边的小圆钮加上「不」；再把「吞下不消化」拖到「那么」后面。\n\n意思是：还没吞到共生菌的细胞，去找紫光游丝吞下。吞到以后，后代也都带着它。", ring = "add", wait = "card:swallow", src = "吞下不消化", goal = "新卡：不 带着共生菌 → 吞下不消化"},
			{text = "规则从上往下检查，吃东西的卡会先把这一拍用掉。按住这张卡最右边的 ⋮⋮，把它拖到「游向藻团」那张卡的上面。", ring = "handle:SWALLOW", wait = "before_eat:SWALLOW", goal = "「吞下不消化」排在「游向藻团」上面"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["点一只细胞看看：带着共生菌的，细胞里有几个紫色小点。"],
	},
	"8-3": {
		design = ["抢食游丝繁殖很快，把藻场占满了。你的生命装着「毒素腺」：放出毒云，伤别的物种，不伤自己。",
			{text = "先在左下角的器官槽里装上「毒素腺」：有了它，规则库里的「分泌毒素甲 / 乙」才能用。", ring = "organ:toxin", wait = "organ:toxin", goal = "安装「毒素腺」。"},
			{text = "打开「行为规则」，进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced", goal = "打开「高级编辑」。"},
			{text = "点规则列表下面的「+ 添加规则」，最下面会多出一张空卡。\n\n把「别的物种在」拖到「如果」后面，再把「分泌毒素甲」拖到「那么」后面。", ring = "add", wait = "card:toxA", src = "分泌毒素甲", goal = "新卡：别的物种在 X → 分泌毒素甲"},
			{text = "再点一次「+ 添加规则」：「如果」拖入「别的物种在」，「且 第二个条件」拖入「年龄超过」（滑块拖到 50%），「那么」拖入「分泌毒素乙」。\n\n年轻的放甲、年长的放乙，两种毒素一起用，对手很难耐药。", ring = "add", wait = "card:toxB", src = "分泌毒素乙", goal = "新卡：别的物种在 且 年龄超过 50% → 分泌毒素乙"},
			{text = "放毒不占动作，但要排在吃东西的卡上面才会被检查到。按住这张卡最右边的 ⋮⋮，把它拖到「游向藻团」那张卡的上面。两张毒素卡都要拖上去，「毒素乙」那张放在「毒素甲」上面。", ring = "handle:TOXIN_B", wait = "before_eat:TOXIN_B,TOXIN_A", goal = "两张毒素卡都排在「游向藻团」上面"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["点一只抢食游丝，能看到它对两种毒素各耐药多少。"],
	},
	"8-4": {
		design = ["沼泽上空时常下酸雨，酸从水面往下渗。",
			{text = "基因组页右边的「耐温」那一行，水温滑条下面多了一条「耐酸」滑条。把它拖到 50% 左右：酸伤少一半，平时多耗一点能量。", ring = "acid", wait = "acid_up", goal = "耐酸调到 40% 以上。"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["右上角会倒数下一场酸雨。雨来之前，也可以用洋流把细胞往深处推一把。"],
	},
	"8-5": {
		design = ["黏菌从中央朝六个藻场伸管道。碰到管道的细胞会被吞掉，连上的藻场它就吸干。",
			{text = "这关有两个器官槽：装上「毒素腺」。毒云能烧断管道。", ring = "organ:toxin", wait = "organ:toxin", goal = "安装「毒素腺」。"},
			{text = "打开「行为规则」，进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced", goal = "打开「高级编辑」。"},
			{text = "点规则列表下面的「+ 添加规则」，最下面会多出一张空卡。\n\n把「别的物种在」拖到「如果」后面（滑块调到 50 µm），再把「分泌毒素甲」拖到「那么」后面。黏菌的管道也算“别的物种”，细胞靠近管道就会放毒。", ring = "add", wait = "card:toxA", src = "分泌毒素甲", goal = "新卡：别的物种在 X → 分泌毒素甲"},
			{text = "规则从上往下检查，吃东西的卡会先把这一拍用掉。按住这张卡最右边的 ⋮⋮，把它拖到「游向藻团」那张卡的上面。", ring = "handle:TOXIN_A", wait = "before_eat:TOXIN_A", goal = "毒素卡排在「游向藻团」上面"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release", goal = "点击「投放到培养皿」。"}],
		run = ["藻场外圈的进度环满了，那个藻场就归你。先占还没被管道连上的。按 {membrane} 放隔离膜能挡住一条管道。"],
	},
	"3-1": {
		design = ["暗水里视野很短，暗噬靠近时，往往只有离它最近的细胞能看见。试着让发现危险的细胞发出信号，提醒周围的同伴。",
			{text = "暗噬游得比初始细胞快。先提高速度；预算不够的话，把繁殖降一级。", ring = "speed_fert", wait = "speed4", goal = "速度 → 4，繁殖 → 2（一共 12 点，正好守住低预算线）", why = "速度提高后，细胞更有机会逃脱暗噬。"},
			{text = "在器官槽里装上「信号腺」和「化学感受器」，分别用来释放和接收信号。", ring = "signal_organs", wait = "signal_organs", goal = "两个都装上（正好占满器官槽）", why = "两个器官配合，细胞就能互相传递信号。"},
			{text = "打开「行为规则」，再进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced"},
			{text = "把左侧的「释放信号 A」拖到第一张卡的「逃离」上。发现猎手的细胞会一边逃跑，一边发出信号。", ring = "flee_card", wait = "shout", goal = "第 1 张变成“猎手靠近 → 释放信号 A”", why = "发现猎手的细胞会释放信号，同时逃离。"},
			{text = "点击「+ 添加规则」。新卡会插在第一张下方。", ring = "add", wait = "newcard", pick = Rules.A_EMIT_A, goal = "多出一张新卡（在第 2 张）"},
			{text = "如果新卡不在第二位，按住右侧的 ⋮⋮，把它拖到第一张下方。", ring = "blank_handle", wait = "blank_2nd", goal = "新卡排在第 2 张"},
			{text = "把左侧的「信号 A 浓」拖到新卡的条件格，也就是「如果」后面。空卡填好之前，下面的规则会暂时变灰。", ring = "card2_cond", wait = "c2_signal", goal = "第 2 张的条件是“信号 A 浓”"},
			{text = "再把「逃离」拖到动作格，也就是「那么」后面。这样收到信号的细胞就会逃跑。", ring = "card2_act", wait = "smell_flee", goal = "第 2 张是“信号 A 浓 → 逃离”，在“游向藻团”上面", why = "规则从上往下检查。逃跑排在觅食前面，细胞收到警报时会优先逃跑。"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release"}],
		run = ["留意右上角的种群数量和被吞数量。暗噬出现时，看看附近的细胞能否及时收到警报。"],
	},
	"3-2": {
		design = ["急梭游得很快，但每吃掉一只细胞，都要停下来消化 6 秒。试着让细胞一起繁殖，让更多后代有机会活下来。",
			{text = "在器官槽里装上「识别蛋白」，细胞才能识别同伴所处的状态。", ring = "organ:recog", wait = "organ:recog", goal = "装上识别蛋白", why = "现在你的生命能看出：身边的同伴是在觅食、警戒，还是在繁殖期。"},
			{text = "打开「行为规则」，再进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced"},
			{text = "在上方状态图中点击「+」，添加「繁殖期」。这个状态自带四张规则卡。", ring = "state_map", wait = "breed_state", goal = "状态图里多出“繁殖期”"},
			{text = "点击「觅食」返回，把「进入繁殖期」拖到「能量高于 100% → 分裂」的动作格上。", ring = "to_breed_card", wait = "to_breed", goal = "觅食里变成“能量高于 100% → 进入繁殖期”", why = "能量充足的细胞会进入繁殖期。接下来让附近的同伴也跟上。"},
			{text = "规则卡已经满了。点击最后一张「能量高于 100% → 休息」右侧的 ×，腾出位置。它与上方规则的条件相同，排在后面不会被执行。", ring = "rest_card", wait = "no_rest", goal = "觅食里不再有“休息”卡"},
			{text = "点击「+ 添加规则」，新卡会插在第一张下方。", ring = "add", wait = "newcard_forage", pick = Rules.A_FLEE, goal = "多出一张新卡（在第 2 张）"},
			{text = "如果新卡不在第二位，按住右侧的 ⋮⋮，把它拖到第一张下方。", ring = "blank_handle", wait = "blank_2nd", goal = "新卡排在第 2 张"},
			{text = "把「看见同伴在」拖到新卡的条件格。旁边的滑块用于选择同伴的状态，默认是繁殖期。", ring = "card2_cond", wait = "c2_peer", goal = "第 2 张的条件是“看见繁殖期中的同伴”"},
			{text = "把「进入繁殖期」拖到新卡的动作格。", ring = "card2_act", wait = "sync", goal = "第 2 张是“看见繁殖期中的同伴 → 进入繁殖期”", why = "细胞看到繁殖期的同伴后也会进入繁殖期，有助于让后代集中出生。"},
			{text = "点击「投放到培养皿」。自然变异开启时，后代的规则可能发生变化，可以在事件栏查看。", ring = "go", wait = "release"}],
		run = ["留意右上角的种群数量和被吃掉的数量，看看细胞是否会成批繁殖。"],
	},
	"3-4": {
		design = ["这次继续使用 3-1 的警报方案。先投放细胞，观察它们遇到暗噬时的反应。",
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release"}],
		run = [{text = "附近没有猎手，细胞为什么也在逃跑？点击左上角物种列表中的「回声菌群」，再点选其中一只并按 {track} 跟随。", wait = "scan_rival", goal = "跟随一只回声菌群，看右边的扫描卡"},
			"扫描卡上写着「总是 → 释放信号 A」。回声菌群持续释放信号，让你的细胞误以为附近有危险。等本次实验结束后，点击「改方案再试」。"],
		# From the next go on: the fix, one drag a step (2026-10-31: the guide
		# ended after the scan and the player was left with nothing).
		design2 = ["回声菌群一直在释放信号 A。换用它不释放的信号 B，就能避开干扰。",
			{text = "打开「行为规则」，再进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced"},
			{text = "把「释放信号 B」拖到第一张卡的动作格，替换「释放信号 A」。", ring = "emit_a_act", wait = "shout_b", goal = "第 1 张变成“猎手靠近 → 释放信号 B”"},
			{text = "把「信号 B 浓」拖到第二张卡的条件格，替换「信号 A 浓」。", ring = "smell_a_cond", wait = "smell_b", goal = "第 2 张变成“信号 B 浓 → 逃离”", why = "信号 B 的默认门槛是 0.5。细胞会响应足够强的信号 B，回声菌群的信号 A 不再触发这条规则。"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release"}],
		run2 = ["观察细胞是否还会无故逃跑。第 5 分钟时，种群需要达到 100 只，且数量超过回声菌群。"],
	},
	"3-3": {
		design = ["这里的藻类外壳坚硬，细胞直接吃只能吸收四成。消化酶可以分解藻壳，但单只细胞分泌的量不够。试着让它们聚在一起时再分泌。",
			{text = "藻场离投放点有一段距离。把速度调到 3、繁殖调到 4，帮助细胞抵达藻场并增加数量。", ring = "speed_fert", wait = "speed3fert4", goal = "速度 → 3，繁殖 → 4（一共 13 点，正好守住低预算线）", why = "细胞更容易抵达藻场，并繁殖出足够多的同伴。"},
			{text = "打开「行为规则」，再进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced"},
			{text = "点击「+ 添加规则」，新卡会插在第一张下方。", ring = "add", wait = "newcard_forage", pick = Rules.A_DIVIDE, goal = "多出一张新卡（在第 2 张）"},
			{text = "如果新卡不在第二位，按住右侧的 ⋮⋮，把它拖到第一张下方。", ring = "blank_handle", wait = "blank_2nd", goal = "新卡排在第 2 张"},
			{text = "把「同伴很多」拖到新卡的条件格，再将滑块调到 4，表示 60 µm 内至少有 4 个同伴。", ring = "card2_cond", wait = "c2_crowd", goal = "第 2 张的条件是“同伴 ≥ 4”"},
			{text = "把「分泌消化酶」拖到新卡的动作格。", ring = "card2_act", wait = "quorum", goal = "第 2 张是“同伴 ≥ 4 → 分泌消化酶”", why = "附近同伴足够多时，细胞会一起分泌酶；落单时则不会消耗能量分泌。分泌期间仍能移动和进食。"},
			{text = "点击「投放到培养皿」。自然变异开启时，后代的规则可能发生变化。", ring = "go", wait = "release"}],
		run = ["留意右上角的种群数量，观察藻场上聚集的细胞和落单细胞有什么不同。"],
	},
	"4-1": {
		design = ["病毒在细胞密集的地方更容易传播。这次给细胞加一条规则，让它们在同伴过多时散开。",
			{text = "打开「行为规则」，再进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced"},
			{text = "点击「+ 添加规则」，新卡会插在第一张下方。", ring = "add", wait = "newcard_forage", pick = Rules.A_DIVIDE, goal = "多出一张新卡（在第 2 张）"},
			{text = "如果新卡不在第二位，按住右侧的 ⋮⋮，把它拖到第一张下方。", ring = "blank_handle", wait = "blank_2nd", goal = "新卡排在第 2 张"},
			{text = "把「同伴很多」拖到新卡的条件格。", ring = "card2_cond", wait = "c2_crowd_any", goal = "第 2 张的条件是“同伴很多”"},
			{text = "把「远离同伴」拖到新卡的动作格。", ring = "card2_act", wait = "disperse", goal = "第 2 张是“同伴很多 → 远离同伴”", why = "这条规则排在「游向藻团」上方。滑块门槛越低，细胞越早散开，但也更难聚在一起进食。"},
			{text = "点击「投放到培养皿」。第一只被病毒感染的细胞会被标记，放大后可以观察它的变化。", ring = "go", wait = "release"}],
		run = ["被感染的细胞会逐渐变红，最终裂解。留意右上角的种群数量和裂解数量；放大后也可以点击发红的细胞观察。"],
	},
	"5-2": {
		design = ["这次要设计的是由多个细胞组成的身体。不同的方块各有职责：鞭毛块负责游动，生殖块负责繁殖。",
			"水流迎面而来，身后还有喷口。初始身体里有两块鞭毛被包在内部，前方的生殖块也缺少遮挡，需要调整位置。",
			{text = "把前排标有「没遮挡」的生殖块拖到一块标有「被包住」的鞭毛块上，两块会交换位置。", ring = "body_board", wait = "body_walled_1", goal = "只剩一块“被包住”"},
			{text = "再把另一块「没遮挡」的生殖块，与剩下的「被包住」的鞭毛块交换。", ring = "body_board", wait = "body_ok", goal = "没有“被包住”，也没有“没遮挡”", why = "鞭毛位于外缘才能提供推力；生殖块移到内部后，也能受到前方方块的遮挡。右侧水槽会展示试游效果。"},
			"身体的形状也会影响行动：宽一些能吃到更多食物，细一些则游得更快。可以先试试当前的形状。",
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release"}],
		run = ["细线显示水流方向。身体吃饱后会孕育子体；放大画面，可以观察生殖块的变化。子体离开后，亲体会留下空壳。",
			"目标在上游。群体增加后，可以用右下角的洋流引导，朝上游拖动，把它们送过去。"],
	},
	"5-3": {
		design = ["初始身体沿用了上一关的布局。这次巨噬者会啃食外缘，第 2 分钟起还会有一分钟的食物短缺。",
			"身体最多容纳 12 块。要增加甲和储能块，就得替换现有方块：代价是游动或繁殖能力下降。",
			{text = "从方块列表中拖出甲块，分别替换身体最后一列上下两个角的鞭毛块。", ring = "tile:7", wait = "body_armor", goal = "外缘有 2 块甲"},
			{text = "再把储能块拖到身体正中间的生殖块上，替换它。", ring = "tile:8", wait = "body_store", goal = "有 1 个储能块", why = "后角的甲可以抵挡来自后方和侧面的攻击。储能块放在内部，能储存多余能量，供食物短缺时使用。"},
			"可以查看右侧仪表，了解身体各项能力。",
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release"}],
		run = ["紫红色的大细胞是巨噬者。甲块能抵挡啃咬；没有甲保护的方块更容易受伤。",
			{at = 105.0, text = "食物短缺快开始了。放大画面，可以观察储能块里的油滴随储备消耗而缩小。"}],
	},
	"5-4": {
		design = ["这次巨噬者会咬伤身体的方块。受伤的方块暂时无法工作，需要一段时间恢复。",
			"这关没有食物短缺。可以把中间的储能块换回生殖块，增加每代的后代数量。",
			{text = "把生殖块拖到正中间的储能块上，替换它。", ring = "tile:6", wait = "body_germ3", goal = "有 3 个生殖块"},
			"新解锁的再生块能加快受伤方块的恢复。只要身体里有一块完好的再生块，全身受伤方块的恢复速度就会提高。",
			{text = "把再生块拖到最上排第二格的鞭毛块上，让它紧挨左上角的甲块。", ring = "tile:9", wait = "body_regen", goal = "有 1 个再生块", why = "再生块受伤后会暂时失效。把它放在甲块旁边，有助于减少它受到的攻击。"},
			"身体断开后，包含至少 3 块的部分有机会长回完整身体，形成新的群体。",
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release"}],
		run = ["受伤的方块会变暗、破碎，伤口上会出现白色的再生芽。放大画面可以看得更清楚。"],
	},
	"5-5": {
		design = ["这关的对手是轮虫。它会用头上的纤毛冠吸水，把附近的群体吸进嘴里。初始身体外缘有两块甲。",
			"外缘有至少 4 块完好甲块的群体会被轮虫吐出来，但软块仍会受伤，一块甲也会开裂。",
			"本关可以使用「刺激头冠 {current}」。点中轮虫头部后，它会暂时收起头冠，无法吸水和吞食。",
			{text = "把甲块拖到身体最后一列中间的生殖块上，让这一列三格都是甲。", ring = "tile:7", wait = "body_armor3", goal = "外缘有 3 块甲"},
			{text = "生殖块少了一块。把生殖块拖到最下排第二格的鞭毛块上。", ring = "tile:6", wait = "body_germ2", goal = "有 2 个生殖块", why = "现在身体有两个生殖块。"},
			{text = "再把甲块拖到最上排第二格的鞭毛块上。", ring = "tile:7", wait = "body_armor4", goal = "外缘有 4 块甲", why = "第四块甲会降低游动能力，但能让甲完好的群体被轮虫吐出。轮虫捕食失败也会消耗能量。"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release"}],
		run = ["右上角显示轮虫的能量。观察它吞下群体后是否会吐出来。",
			{at = 25.0, text = "被吐出的群体会标记「裂甲」；甲恢复之前再次被吞，可能被嚼碎。轮虫要吸回受伤群体时，按 {current} 并点击它的头部，让它暂时收起头冠。它快饿死时会暴走，留意使用时机。", ring = "dock:irritant", wait = "used:irritant"}],
	},
	"5-1": {
		design = ["附近的藻场快被吃光了，对岸还有食物，但中间隔着喷口热带，单只细胞过不去。",
			"初始规则已经能通过信号让细胞靠拢。现在还需要设置它们什么时候聚合。",
			{text = "打开「行为规则」，再进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced"},
			{text = "第二张卡的条件已经设好：能量低、附近同伴够多。把「聚合」拖到这张卡的动作格。", ring = "card2_act", wait = "aggregate_card", goal = "第 2 张是“能量低于 40% 且 同伴很多 → 聚合”", why = "细胞饥饿且附近同伴足够多时才会聚合。聚合后不再进食，也不会变老。"},
			{text = "点击「投放到培养皿」。", ring = "go", wait = "release"}],
		run = ["细胞会先在附近进食。藻场耗尽后，观察饥饿的细胞是否聚合并向对岸移动。"],
	},
	"4-5": {
		design = ["巨毒囊会被进食中的细胞误吞，在细胞内增殖，最终撑破细胞并释放更多病毒。",
			"这次可以设计噬毒体。它不会伤害细胞，可以附着在水中的巨毒囊上，也能进入被感染的细胞，夺取病毒工厂。",
			{text = "在左侧分配 12 点并选择工作方式。基因组和行为规则也可以调整；设置好后点击「投放到培养皿」。", ring = "go", wait = "release"}],
		run = ["你的细胞是蓝色，紫色的大颗粒是巨毒囊。点击右下角「投放病毒」或按 5，再点击培养皿投放噬毒体。"],
	},
	"4-4": {
		design = ["这次要设计病毒，对付正在藻场繁殖的绒游丝。你有 12 点可以分配。",
			{text = "在左侧调整四项属性，右侧可以查看病毒的外观。完成后点击「投放到培养皿」。", ring = "go", wait = "release"}],
		run = ["你的细胞是蓝色，绒游丝是橙黄色。点击右下角「投放病毒」或按 5，再选择投放的位置和时机。"],
	},
	"4-3": {
		design = ["你的细胞基因中藏着潜伏针，唤醒后会释放攻击绒游丝的病毒。试着让年老的细胞执行这条规则。",
			{text = "打开「行为规则」，再进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced"},
			{text = "点击「+ 添加规则」，新卡会插在第一张下方。", ring = "add", wait = "newcard_forage", pick = Rules.A_DIVIDE, goal = "多出一张新卡（在第 2 张）"},
			{text = "如果新卡不在第二位，按住右侧的 ⋮⋮，把它拖到第一张下方。", ring = "blank_handle", wait = "blank_2nd", goal = "新卡排在第 2 张"},
			{text = "把「年龄超过」拖到新卡的条件格。默认的 70% 表示细胞已度过寿命的七成。", ring = "card2_cond", wait = "c2_age", goal = "第 2 张的条件是“年龄超过”"},
			{text = "把「唤醒潜伏针」拖到新卡的动作格。", ring = "card2_act", wait = "wake_card", goal = "第 2 张是“年龄超过 70% → 唤醒潜伏针”", why = "这条规则排在「游向藻团」前面。达到年龄门槛的细胞会释放 30 个攻击绒游丝的病毒，年轻细胞可以继续进食和繁殖。"},
			{text = "点击「投放到培养皿」。第一只唤醒潜伏针的细胞会被标记，放大后可以观察。", ring = "go", wait = "release"}],
		run = ["橙黄色的细胞是绒游丝。放大画面，细胞核上紫色的 DNA 就是潜伏针。右上角显示双方的数量。"],
	},
	"4-2": {
		design = ["这关沿用上一关的散开规则。获得免疫记忆的细胞可以继续留在藻场，其他细胞则保持距离。",
			{text = "在左下角器官槽中装上「记忆片段」。细胞被病毒攻击时，有机会清除病毒并留下免疫记忆。", ring = "organ:crispr", wait = "organ:crispr"},
			{text = "打开「行为规则」，再进入「高级编辑」。", ring = "mode_adv", wait = "mode:advanced"},
			{text = "把「有免疫记忆」拖到第二张卡的第二个条件格，也就是「同伴很多」的右侧。", ring = "card2_cond2", wait = "c2_immune", goal = "第 2 张多一个条件“有免疫记忆”"},
			{text = "点击「有免疫记忆」前面的「不」，让这条规则只作用于没有记忆的细胞。", ring = "card2_neg2", wait = "memory_card", goal = "第 2 张是“同伴很多 且 不 有免疫记忆 → 远离同伴”", why = "没有记忆的细胞会继续散开；有记忆的细胞可以留在藻场进食、繁殖，并将记忆传给后代。"},
			{text = "点击「投放到培养皿」。第一只清除病毒的细胞会被标记，放大后可以观察。", ring = "go", wait = "release"}],
		run = ["青绿色表示细胞获得了免疫记忆。第 4 分钟会迎来大规模爆发，看看此前能有多少细胞获得记忆。",
			{at = 225.0, text = "大规模爆发快开始了，留意有免疫记忆的细胞能否存活。"}],
	},
}


func _ready() -> void:
	layer = 30
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = VEIL
	veil.material = vm
	veil.visible = false
	root.add_child(veil)
	ring = Ring.new()
	root.add_child(ring)
	card = GlassPanel.new(Vector4(22, 16, 22, 16))
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.offset_left = -400
	card.offset_right = 400
	card.offset_top = 96
	card.offset_bottom = 230
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.body.add_child(v)
	var head := Ui.caption("「创生协议」", "GUIDE · %s" % runner.level.id)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	count_label = Ui.label("", 12, Ui.ACCENT, Ui.mono("Medium"))
	head.add_child(count_label)
	v.add_child(head)
	text_label = Ui.label("", 16, Ui.INK, Ui.sans(500))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size.x = 750
	v.add_child(text_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var skip := Widgets.Pill.new("跳过引导", 0, Ui.sans(500))
	skip.custom_minimum_size = Vector2(100, 30)
	skip.pressed.connect(_skip)
	row.add_child(skip)
	# A doing step can be passed over on its own (the player stays in charge).
	skip_step = Widgets.Pill.new("跳过这一步", 0, Ui.sans(500))
	skip_step.custom_minimum_size = Vector2(110, 30)
	skip_step.pressed.connect(_next)
	row.add_child(skip_step)
	# A recommended-value step: all of them at once (DECISIONS 推荐数值).
	apply_rec = Widgets.Pill.new("一键套用推荐数值", 0, Ui.sans(600))
	apply_rec.custom_minimum_size = Vector2(150, 30)
	apply_rec.visible = false
	apply_rec.pressed.connect(_apply_rec)
	row.add_child(apply_rec)
	next = Widgets.Pill.new("知道了", 0, Ui.sans(600))
	next.custom_minimum_size = Vector2(90, 30)
	next.active = true
	next.pressed.connect(_next)
	row.add_child(next)
	v.add_child(row)
	todo_label = Ui.label("完成当前操作后，自动进入下一步。", 13, Ui.ACCENT, Ui.sans(600))
	todo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	todo_label.custom_minimum_size.x = 750
	v.add_child(todo_label)
	v.move_child(todo_label, v.get_child_count() - 2)
	card.visible = false
	_show("design")


var lines: Array = []
var apply_rec: Widgets.Pill
var auto_done: Array = [] # steps passed over because the design already had them (said on the next one shown)


func _show(key: String) -> void:
	if skipped:
		return
	step = key
	lines = _lines(key).duplicate()
	# Carry on where the last visit stopped: the lines already done stay done
	# (a run that got past the designer skips the designer's lines too).
	var at := CampaignSave.guide_at(runner.level.id)
	if not at.is_empty():
		var n := 0
		if at.step == key:
			n = int(at.n)
		elif key == "design" and at.step == "run":
			n = lines.size()
		if n > 0:
			resumed = true
			lines = lines.slice(mini(n, lines.size()))
	# 跟着引导再试一次 (or the guide asked for again): before the release, the
	# recommended values, one gene a step (DECISIONS 推荐数值).
	if key == "design" and runner.want_guide and not Recommend.for_level(runner.level.id).is_empty():
		var at_go := lines.size()
		for k in lines.size():
			if lines[k] is Dictionary and str(lines[k].get("wait", "")) == "release":
				at_go = k
		lines.insert(at_go, {rec = true})
	_next()


# A step's field; a step with `adv` swaps in its own fields while the rules
# page is in the card editor (the advanced mode).
func _v(k: String, def: Variant = null) -> Variant:
	var d: Control = host.designer
	if cur.has("adv") and d and d.rules_mode == "advanced" and cur.adv.has(k):
		return cur.adv[k]
	return cur.get(k, def)


func _total() -> int:
	return _lines(step).size()


# The level's lines for this go: past its first go, a second part if it has one.
func _lines(key: String) -> Array:
	var id: String = runner.level.id
	var all: Dictionary = STEPS.get(id, {})
	if all.has(key + "2") and (int(CampaignSave.level(id).get("attempts", 0)) >= 1 or CampaignSave.guide_second(id)):
		return all[key + "2"]
	return all.get(key, [])


func _next() -> void:
	done_t = -1.0
	if lines.is_empty():
		card.visible = false
		cur = {}
		target = null
		if step == "run":
			# Seen to its end. Left there, a way back in would skip the whole
			# guide ("再也没出现过"): the next visit starts it again, from the
			# level's second part if it has one.
			CampaignSave.clear_guide_at(runner.level.id)
			if STEPS.get(runner.level.id, {}).has("design2"):
				CampaignSave.set_guide_second(runner.level.id)
		return
	var l: Variant = lines.pop_front()
	if l is Dictionary and l.has("rec"):
		var steps := _rec_steps()
		for k in range(steps.size() - 1, -1, -1):
			lines.push_front(steps[k])
		_next()
		return
	cur = l if l is Dictionary else {text = l}
	var at := _total() - lines.size() # this line's number, from 1
	CampaignSave.set_guide_at(runner.level.id, step, at - 1)
	# Already done (the player got there first): straight on.
	if cur.has("wait") and _met(cur.wait):
		if str(cur.wait) != "release" and not cur.has("rec_step"):
			auto_done.append(str(cur.get("goal", cur.get("text", ""))).trim_suffix("。"))
		_next()
		return
	# A step may pre-select a card (by its action), so “+ 添加规则” puts the
	# new card right under it (review: “先选中再添加” was a step too many).
	if cur.has("pick") and host.designer:
		var de: Control = host.designer.deck_editor
		var pk: int = de.deck.find_custom(func(c: Dictionary) -> bool: return c.act == int(cur.pick))
		if pk >= 0:
			de.selected = pk
			host.designer.keep_pick = true
			de.queue_redraw()
	count_label.text = ("继续上次引导　" if resumed else "") + "第 %d / %d 步" % [at, _total()]
	resumed = false
	# (Steps the design already met: say so, not "设置好了" out of nowhere.)
	var said := Keys.fill(str(_v("text", "")))
	if not auto_done.is_empty():
		said = "这几步你的方案里已经有了：%s。\n\n" % "；".join(auto_done) + said
		auto_done.clear()
	_say(said)
	apply_rec.visible = cur.has("rec_step")
	if cur.has("rec_step"):
		var kind := str(cur.get("rec_kind", "genes"))
		apply_rec.text = {body = "一键套用推荐身体", virus = "一键套用推荐病毒"}.get(kind, "一键套用推荐数值")
		apply_rec.tooltip_text = "将所有物种的基因调整为推荐数值。" if kind == "genes" and Recommend.slots(Recommend.for_level(runner.level.id)) > 1 else ""
	if host.designer and host.designer.body_bench:
		host.designer.body_bench.rec_marks = (cur.get("marks", []) as Array).duplicate()
	wait_base = host.steps_taken
	var waits: bool = cur.has("wait")
	next.visible = not waits
	skip_step.visible = waits
	todo_label.visible = waits or cur.has("goal")
	todo_label.text = _todo()
	if not _due():
		card.visible = false
		return
	# Every new step re-plays the card's entrance with a soft chime, so a
	# change of step is seen even while the eyes are on the target.
	card.visible = true
	card.appear(0.0, true)
	Audio.sfx("holo_tick", -8.0)


# The card's text, its height set from the wrapped lines (an autowrapped
# Label in a container reported one line and the rest was cut off).
func _say(t: String) -> void:
	text_label.text = t
	var f: Font = text_label.get_theme_font("font")
	var w := text_label.custom_minimum_size.x
	var h := f.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, w, 16, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND).y
	text_label.custom_minimum_size.y = ceilf(h) + 4.0
	_fit_todo()
	card.reset_size()


# The goal line wraps too (same autowrap trouble as the text).
var _todo_fit := ""


func _fit_todo() -> void:
	_todo_fit = todo_label.text + str(todo_label.custom_minimum_size.x)
	var f: Font = todo_label.get_theme_font("font")
	var h := f.get_multiline_string_size(todo_label.text, HORIZONTAL_ALIGNMENT_LEFT, todo_label.custom_minimum_size.x, 13, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND).y
	todo_label.custom_minimum_size.y = ceilf(h) + 2.0
	card.reset_size()


# The small line under a doing step: its exact target when it has one.
func _todo() -> String:
	var gl: Variant = _v("goal")
	return "操作提示：%s" % gl if gl != null else "完成当前操作后，自动进入下一步。"


# A timed step waits for its moment in the level.
func _due() -> bool:
	if step == "design" and host.designer == null:
		return false
	if not cur.has("at"):
		return true
	return runner.phase == "run" and host.sim.get_time() - runner.t0 >= float(cur.at)


# Has the player done what the step asks?
func _met(w: String) -> bool:
	var d: Control = host.designer
	match w:
		"release":
			return false # the designer closes; its lines go with it
		"divide":
			if d == null:
				return false
			for c: Dictionary in d.deck_editor.deck:
				if c.act == Rules.A_DIVIDE and c.c1 == Rules.C_ENERGY_ABOVE and float(c.t1) >= 1.25:
					return true
			return false
		"speed":
			return d != null and float(d.genes[0]) <= 1.0
		"metab4":
			return d != null and float(d.genes[5]) >= 4.0
		"temp":
			return d != null and d.temp_opt <= 5.0
		"inspect":
			return host.selected >= 0
		"speed3fert4":
			return d != null and float(d.genes[0]) >= 3.0 and float(d.genes[4]) >= 4.0
		"speed3":
			return d != null and float(d.genes[0]) >= 3.0
		"speed4":
			return d != null and float(d.genes[0]) >= 4.0
		"sleep_state":
			return d != null and d.deck_editor.states_used().has(Rules.S_SLEEP)
		"nap_card":
			# On whichever species: the predator's deck may be the one not on show.
			if d == null:
				return false
			var decks: Array = [d.deck_editor.deck]
			for k in d.sp_slots.size():
				if k != d.cur_slot and d.sp_slots[k] is Dictionary:
					decks.append(d.sp_slots[k].get("deck", []))
			return decks.any(func(dk: Array) -> bool: return dk.any(func(c: Dictionary) -> bool: return c.act == Rules.A_TO_SLEEP))
		"prey_genes":
			return d != null and d.cur_slot == 0 and float(d.genes[0]) <= 1.0
		"race_genes":
			return d != null and float(d.genes[2]) <= 1.0 and float(d.genes[0]) >= 4.0 and float(d.genes[4]) >= 4.0
		"armour":
			return d != null and (d.organs.has("silica") or d.organs.has("spines"))
		"flee_attacked":
			return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
				return c.act == Rules.A_FLEE and _has(c, Rules.C_ATTACKED))
		"flee_or":
			return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
				return c.act == Rules.A_FLEE and c.get("any", false) and _has(c, Rules.C_ATTACKED))
		"hunt_card":
			return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
				return c.act == Rules.A_HUNT and (_has(c, Rules.C_SEE_PREY) or _has(c, Rules.C_PREY_NEAR) or _has(c, Rules.C_PREY_SMALL)))
		"ambush":
			return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
				return c.act == Rules.A_REST and c.c1 == Rules.C_NONE and c.c2 == Rules.C_NONE)
		"scan":
			return host.selected >= 0 and host.hud_root.scan_panel.visible and host.hud_root.tier == host.hud_root.TIER_MICRO
		"divide_first":
			# (Deleting the rest card also frees divide.)
			var dv := _card_of(Rules.A_DIVIDE)
			var rs := _card_of(Rules.A_REST)
			return d != null and dv >= 0 and (rs < 0 or dv < rs)
		"paused":
			return host.paused
		"newcard":
			return d != null and d.deck_editor.deck.size() > d.start_deck().size()
		"no_rest":
			return d != null and not d.deck_editor.deck.any(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_REST)
		"newcard_forage":
			# (A state's own cards don't count: only a card added to foraging.)
			# (Counting fails once a card was deleted first: a fresh blank one shows it.)
			return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE and c.c1 == Rules.C_NONE and c.c2 == Rules.C_NONE and c.act == Rules.A_WANDER)
		"newcond":
			return _new_card(func(c: Dictionary) -> bool: return c.c1 != Rules.C_NONE) >= 0
		"and":
			return _new_card(func(c: Dictionary) -> bool: return c.c2 != Rules.C_NONE) >= 0
	# Level 14 (the echo): a rival under the lens, then the alarm moved to B.
	if w == "scan_rival":
		if host.selected < 0 or not (host.hud_root.scan_panel.visible and host.hud_root.tier == host.hud_root.TIER_MICRO):
			return false
		return int(host.sim.get_agent(host.selected).get("species", -1)) == int(runner.level.goal.get("rival", -1))
	if w == "shout_b":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_EMIT_B and _has(c, Rules.C_PREDATOR_NEAR))
	if w == "smell_b":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_FLEE and ((c.c1 == Rules.C_SIGNAL_B and not c.get("n1", false)) or (c.c2 == Rules.C_SIGNAL_B and not c.get("n2", false))))
	# A new card's place and its two drags, one at a time (2026-10-30: "这个
	# 引导也要监督玩家有没有完成"; "分开来描述"). The new card sits second in
	# foraging; until then the blank one is the card to move.
	if w == "blank_2nd":
		var bk := _blank_card()
		return d != null and (bk < 0 or _forage_rank(bk) == 1)
	# Level 16 (the memory): the away card second, for those without it.
	# Level 17 (the phage as a weapon).
	if w == "c2_age":
		var k2 := _forage_card(1)
		return d != null and k2 >= 0 and _has(d.deck_editor.deck[k2], Rules.C_AGE_ABOVE)
	if w == "body_walled_1":
		return d != null and d.body_bench != null and int(Colony.stats(d.body_bench.cells).walled) <= 1
	# Level 22: armour on the rim, a store put in.
	if w == "body_armor":
		if d == null or d.body_bench == null:
			return false
		var ba: Dictionary = Colony.stats(d.body_bench.cells)
		return int(ba.armor) - int(ba.armor_walled) >= 2
	# Level 24: three armour on the rim, then four.
	if w == "body_armor3" or w == "body_armor4":
		if d == null or d.body_bench == null:
			return false
		var b3: Dictionary = Colony.stats(d.body_bench.cells)
		return int(b3.armor) - int(b3.armor_walled) >= (3 if w == "body_armor3" else 4)
	if w == "body_germ2":
		return d != null and d.body_bench != null and int(Colony.stats(d.body_bench.cells).germ) >= 2
	if w == "body_germ3":
		return d != null and d.body_bench != null and int(Colony.stats(d.body_bench.cells).germ) >= 3
	if w == "body_regen":
		return d != null and d.body_bench != null and int(Colony.stats(d.body_bench.cells).regen) >= 1
	if w == "body_store":
		return d != null and d.body_bench != null and int(Colony.stats(d.body_bench.cells).store) >= 1
	if w == "body_ok":
		if d == null or d.body_bench == null:
			return false
		var bs: Dictionary = Colony.stats(d.body_bench.cells)
		return int(bs.walled) == 0 and int(bs.unsafe) == 0
	if w == "aggregate_card":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_AGGREGATE)
	if w == "wake_card":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_INDUCE and _has(c, Rules.C_AGE_ABOVE))
	if w == "c2_immune":
		var k2 := _forage_card(1)
		return d != null and k2 >= 0 and Rules.C_IMMUNE in [d.deck_editor.deck[k2].c1, d.deck_editor.deck[k2].c2]
	if w == "memory_card":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_DISPERSE and ((c.c1 == Rules.C_IMMUNE and c.get("n1", false)) or (c.c2 == Rules.C_IMMUNE and c.get("n2", false))))
	if w == "c2_crowd_any":
		var k2 := _forage_card(1)
		if d == null or k2 < 0:
			return false
		var c: Dictionary = d.deck_editor.deck[k2]
		return (c.c1 == Rules.C_CROWD and not c.get("n1", false)) or (c.c2 == Rules.C_CROWD and not c.get("n2", false))
	# Level 15 (spreading out).
	if w == "disperse":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_DISPERSE and ((c.c1 == Rules.C_CROWD and not c.get("n1", false)) or (c.c2 == Rules.C_CROWD and not c.get("n2", false))))
	if w in ["c2_signal", "c2_peer", "c2_crowd"]:
		var k2 := _forage_card(1)
		if d == null or k2 < 0:
			return false
		var c: Dictionary = d.deck_editor.deck[k2]
		var want: int = {c2_signal = Rules.C_SIGNAL_A, c2_peer = Rules.C_PEER_STATE, c2_crowd = Rules.C_CROWD}[w]
		for s in [1, 2]:
			if c["c%d" % s] == want and not c.get("n%d" % s, false) and (w != "c2_crowd" or float(c["t%d" % s]) >= 4.0):
				return true
		return false
	# Level 9 (on alert).
	if w == "alert_state":
		return d != null and d.deck_editor.states_used().has(Rules.S_ALERT)
	if w == "to_alert":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_TO_ALERT and _has(c, Rules.C_PREDATOR_NEAR))
	if w == "alert_far":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_TO_ALERT and c.c1 == Rules.C_PREDATOR_NEAR and float(c.t1) >= 75.0)
	# Level 11 (alarm calls).
	if w == "signal_organs":
		return d != null and d.organs.has("gland") and d.organs.has("chemo_rec")
	if w == "shout":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_EMIT_A and _has(c, Rules.C_PREDATOR_NEAR))
	if w == "smell_flee":
		if d == null:
			return false
		var sf := -1
		var sa := -1
		for k in d.deck_editor.deck.size():
			var c: Dictionary = d.deck_editor.deck[k]
			if int(c.get("st", 0)) != Rules.S_FORAGE:
				continue
			if sf < 0 and c.act == Rules.A_FLEE and ((c.c1 == Rules.C_SIGNAL_A and not c.get("n1", false)) or (c.c2 == Rules.C_SIGNAL_A and not c.get("n2", false))):
				sf = k
			if sa < 0 and c.act == Rules.A_SEEK_ALGAE:
				sa = k
		return sf >= 0 and (sa < 0 or sf < sa)
	# Level 13 (quorum).
	if w == "quorum":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_SECRETE and ((c.c1 == Rules.C_CROWD and float(c.t1) >= 4.0 and not c.get("n1", false)) or (c.c2 == Rules.C_CROWD and float(c.t2) >= 4.0 and not c.get("n2", false))))
	# Level 12 (breeding together).
	if w == "sync":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_TO_BREED and ((c.c1 == Rules.C_PEER_STATE and roundi(c.t1) == Rules.S_BREED and not c.get("n1", false)) or (c.c2 == Rules.C_PEER_STATE and roundi(c.t2) == Rules.S_BREED and not c.get("n2", false))))
	if w == "flee_far":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_FLEE and c.c1 == Rules.C_PREDATOR_NEAR and float(c.t1) >= 75.0)
	if w == "breed_state":
		return d != null and d.deck_editor.states_used().has(Rules.S_BREED)
	if w == "to_breed":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_TO_BREED and _has(c, Rules.C_ENERGY_ABOVE))
	if w == "calm":
		return d != null and d.deck_editor.deck.any(func(c: Dictionary) -> bool:
			return int(c.get("st", 0)) == Rules.S_ALERT and c.act == Rules.A_TO_FORAGE and c.c1 == Rules.C_STATE_TIME and float(c.t1) <= 14.0)
	# Chapter 6.
	# Chapter 7/8 cards, one at a time (2026-11-07: precise steps), and their
	# place above the eating card.
	if w.begins_with("vtrait:"):
		var vp := w.split(":")
		return d != null and d.virus_bench != null and int(d.virus_bench.virus.get(vp[1], -1)) == int(vp[2])
	if w.begins_with("vmode:"):
		return d != null and d.virus_bench != null and bool(d.virus_bench.virus.get("temperate", false)) == (w.substr(6) == "true")
	if w == "body_rec":
		return d != null and d.body_bench != null and Recommend.body_diffs(Recommend.for_level(runner.level.id), d.body_bench.cells).is_empty()
	if w.begins_with("gene:"):
		var gp := w.split(":")
		return d != null and absf(float(d.genes[int(gp[1])]) - float(gp[2])) < 0.01
	if w.begins_with("card:"):
		var want: Array = {
			remember = [Rules.A_REMEMBER, Rules.C_TEMP_BAD, true],
			ret = [Rules.A_RETURN, Rules.C_TEMP_BAD, false],
			up = [Rules.A_SEEK_O2, Rules.C_O2_ABOVE, true],
			swallow = [Rules.A_SWALLOW, Rules.C_SYMB, true],
			toxA = [Rules.A_TOXIN_A, Rules.C_RIVAL_NEAR, false],
			toxB = [Rules.A_TOXIN_B, Rules.C_RIVAL_NEAR, false],
		}.get(w.substr(5), [])
		return not want.is_empty() and _any_card(func(c: Dictionary) -> bool: return c.act == int(want[0]) and _has(c, int(want[1]), bool(want[2])))
	if w.begins_with("before_eat:"):
		return d != null and Array(w.substr(11).split(",")).all(func(n: String) -> bool: return _before_eat(int(ACT_NAMES.get(n, -1))))
	if w == "up_card":
		return _any_card(func(c: Dictionary) -> bool: return c.act == Rules.A_SEEK_O2 and _has(c, Rules.C_O2_ABOVE, true))
	if w == "swallow_card":
		return _any_card(func(c: Dictionary) -> bool: return c.act == Rules.A_SWALLOW and _has(c, Rules.C_SYMB, true))
	if w == "toxin_cards":
		return _any_card(func(c: Dictionary) -> bool: return c.act == Rules.A_TOXIN_A and _has(c, Rules.C_RIVAL_NEAR)) and _any_card(func(c: Dictionary) -> bool: return c.act == Rules.A_TOXIN_B and _has(c, Rules.C_RIVAL_NEAR))
	if w == "toxin_card":
		return _any_card(func(c: Dictionary) -> bool: return (c.act == Rules.A_TOXIN_A or c.act == Rules.A_TOXIN_B) and _has(c, Rules.C_RIVAL_NEAR))
	if w == "acid_up":
		return d != null and d.acid_tol >= 0.4
	if w == "home_cards":
		return _any_card(func(c: Dictionary) -> bool: return c.act == Rules.A_REMEMBER and _has(c, Rules.C_TEMP_BAD, true)) and _any_card(func(c: Dictionary) -> bool: return c.act == Rules.A_RETURN and _has(c, Rules.C_TEMP_BAD))
	if w == "spore_state":
		return d != null and d.deck_editor.states_used().has(Rules.S_SPORE)
	if w == "life_up":
		return d != null and d.life >= 1.3
	if w == "organs75":
		return d != null and d.organs.has("memory") and d.organs.has("spore")
	if w == "boss_cards":
		return _met("home_cards") and _met("spore_state")
	if w == "fert4":
		return d != null and float(d.genes[4]) >= 4.0
	if w == "avoid_o2_card":
		return _any_card(func(c: Dictionary) -> bool: return c.act == Rules.A_AVOID_O2 and _has(c, Rules.C_O2_ABOVE))
	if w == "avoid_first":
		return d != null and _forage_card(0) >= 0 and d.deck_editor.deck[_forage_card(0)].act == Rules.A_AVOID_O2
	if w == "resp_aero":
		return d != null and d.cur_slot == 1 and d.resp == Resp.AEROBIC
	if w.begins_with("steps:"):
		return host.steps_taken - wait_base >= int(w.substr(6))
	if w.begins_with("slot:"):
		return d != null and d.cur_slot == int(w.substr(5))
	if w.begins_with("organ:"):
		return d != null and d.organs.has(w.substr(6))
	if w.begins_with("page:"):
		return d != null and d.page == w.substr(5)
	if w.begins_with("mode:"):
		return d != null and d.rules_mode == w.substr(5)
	if w.begins_with("used:"):
		return int(host.iv.used.get(w.substr(5), 0)) > 0
	if w.begins_with("used2:"):
		return int(host.iv.used.get(w.substr(6), 0)) > 1
	return false


# Actions by name, for the guide's step data (handle:X, before_eat:X).
const ACT_NAMES := {REMEMBER = Rules.A_REMEMBER, RETURN = Rules.A_RETURN, SEEK_O2 = Rules.A_SEEK_O2, SWALLOW = Rules.A_SWALLOW, TOXIN_A = Rules.A_TOXIN_A, TOXIN_B = Rules.A_TOXIN_B, AVOID_O2 = Rules.A_AVOID_O2}


# A foraging card with action `act` above the first card that eats (or fires
# always): the deck reaches it.
func _before_eat(act: int) -> bool:
	var d: Control = host.designer
	if d == null or act < 0:
		return false
	var mine := -1
	var eat := -1
	for k in d.deck_editor.deck.size():
		var c: Dictionary = d.deck_editor.deck[k]
		if int(c.get("st", 0)) != Rules.S_FORAGE:
			continue
		if mine < 0 and c.act == act:
			mine = k
		if eat < 0 and (c.act == Rules.A_SEEK_ALGAE or (c.c1 == Rules.C_NONE and c.c2 == Rules.C_NONE and c.act != act)):
			eat = k
	return mine >= 0 and (eat < 0 or mine < eat)


# The recommended values as steps, one per gene that differs now.
func _rec_steps() -> Array:
	var d: Control = host.designer
	var l: Dictionary = runner.level
	var r := Recommend.for_level(l.id)
	if d == null or r.is_empty():
		return []
	var out := []
	# The body first (5-2 … 5-5): the cells that differ, marked on the board.
	if r.has("blocks") and d.body_bench:
		var bd := Recommend.body_diffs(r, d.body_bench.cells)
		if bd.is_empty():
			out.append({text = "当前身体布局已经符合推荐设置，不需要再调整身体布局。"})
		else:
			var rows := []
			var marks := []
			for e: Array in bd:
				rows.append("· 第 %d 行第 %d 格：将 %s 替换成 %s" % [int(e[0]), int(e[1]), Recommend.block_name(int(e[2])), Recommend.block_name(int(e[3]))])
				marks.append(e[4])
			out.append({text = "推荐身体布局：需要修改的位置已经在身体编辑界面中标记出来了。\n\n%s\n\n你可以点击「一键套用推荐身体」，直接完成所有修改，也可以按照标记的位置逐个调整。" % "\n\n".join(rows),
				ring = "rec_body", wait = "body_rec", goal = "身体布局和推荐一致", rec_step = true, rec_kind = "body", marks = marks})
	# The virus (4-4, 4-5): its way of working, then its points, lowered ones first.
	if r.has("virus") and d.virus_bench:
		var vb: Control = d.virus_bench
		var vhead := ("推荐噬毒体：%s\n\n" if vb.virophage else "推荐病毒：%s\n\n") % Recommend.virus_text(r)
		var want_t := bool(r.virus.get("temperate", false))
		if bool(vb.virus.get("temperate", false)) != want_t:
			var mname := "先潜伏" if want_t else "马上裂解"
			out.append({text = vhead + "先把类型改成「%s」。" % mname, ring = "vmode:%s" % str(want_t), wait = "vmode:%s" % str(want_t),
				goal = "类型改成「%s」" % mname, rec_step = true, rec_kind = "virus"})
			vhead = ""
		for e: Array in Recommend.virus_diffs(r, vb.virus):
			var vname: String = Recommend.TRAIT_NAMES[e[0]]
			out.append({text = vhead + ("先把" if vhead != "" else "把") + "「%s」调到 %d 级，现在是 %d 级。" % [vname, int(e[2]), int(e[1])], ring = "vtrait:%s" % e[0],
				wait = "vtrait:%s:%d" % [e[0], int(e[2])], goal = "「%s」调到 %d 级" % [vname, int(e[2])], rec_step = true, rec_kind = "virus"})
			vhead = ""
	# The genes, species by species (a tab to switch to first when it is not open).
	var n := Recommend.slots(r)
	var head := ("身体布局调整完成后，继续按照推荐数值调整基因等级。\n\n" if r.has("blocks") else "") + ("推荐数值\n%s\n\n" % Recommend.all_text(l) if n > 1 else "推荐数值：%s\n\n" % Recommend.text(l))
	var on := int(d.cur_slot)
	var any_genes := false
	for s in n:
		var now: Array = d.genes if s == on else (d.sp_slots[s].genes if s < d.sp_slots.size() else [])
		if now.is_empty():
			continue
		var df := Recommend.diffs(l, now, s)
		if df.is_empty():
			continue
		any_genes = true
		if s != on:
			var lab: String = str(l.species[s].get("label", ""))
			out.append({text = head + "点击上方的「%s」，继续调整%s的基因。" % [Recommend.slot_name(l, s), lab], ring = "slot:%d" % s, wait = "slot:%d" % s,
				goal = "切换到「%s」" % Recommend.slot_name(l, s), rec_step = true, rec_kind = "genes"})
			head = ""
			on = s
		for e: Array in df:
			var gname: String = Recommend.GENE_NAMES[int(e[0])]
			out.append({text = head + "将「%s」调至 %s 级（当前 %s 级）。" % [gname, Recommend._lv(float(e[2])), Recommend._lv(float(e[1]))], ring = "gene:%d" % int(e[0]),
				wait = "gene:%d:%s" % [int(e[0]), str(float(e[2]))], goal = "「%s」调到 %s 级" % [gname, Recommend._lv(float(e[2]))], rec_step = true, rec_kind = "genes"})
			head = ""
	if not any_genes and out.is_empty():
		out.append({text = "所有基因已调好，可以开始模拟了。"})
	# When to drop the virus: the last word before the release.
	if r.has("virus"):
		if str(l.id) == "4-4":
			out.append({text = "等到 %s 再投第一团病毒，找绒游丝最多的地方投，过 %d 秒再换个位置投第二团。\n\n太早投的话，绒游丝数量还不够，病毒很难传开。左边的诊断卡会在投放时间到了以后提醒你。" % [Recommend.clock(Recommend.first_drop(r)), Recommend.drop_gap(r)]})
		else:
			out.append({text = "开局 %d 秒内，往自己的细胞最多的地方投两团噬毒体。\n\n噬毒体潜伏在细胞里以后，可以随着细胞分裂传给后代。这样等巨毒囊被吞进去时，就更容易接触到噬毒体。" % Recommend.drops_within(r)})
	return out


# 一键套用: every recommended value of the step's kind at once (genes of
# every species, the virus, or the body; the player stays in charge).
func _apply_rec() -> void:
	var d: Control = host.designer
	var l: Dictionary = runner.level
	var r := Recommend.for_level(l.id)
	if d == null or r.is_empty():
		return
	var kind := str(cur.get("rec_kind", "genes"))
	match kind:
		"body":
			if d.body_bench:
				d.body_bench._commit((r.blocks as Array).duplicate(true))
		"virus":
			var vb: Control = d.virus_bench
			if vb:
				for k: String in Recommend.TRAITS:
					vb.set_trait(k, 1)
				for k: String in Recommend.TRAITS:
					vb.set_trait(k, int(r.virus[k]))
				if bool(vb.virus.get("temperate", false)) != bool(r.virus.get("temperate", false)):
					vb._set_mode(bool(r.virus.get("temperate", false)))
		_:
			for s in Recommend.slots(r):
				var want := Recommend.slot_genes(r, s)
				if s == int(d.cur_slot):
					var g: Array = d.genes.duplicate()
					for k: int in l.get("genes_open", range(8)):
						g[k] = float(want[k])
					d._set_genes(g)
				elif s < d.sp_slots.size():
					var g2: Array = (d.sp_slots[s].genes as Array).duplicate()
					for k: int in l.get("genes_open", range(8)):
						g2[k] = float(want[k])
					d.sp_slots[s].genes = g2
			if d.page != "genome":
				d.show_page("genome")
	# The remaining steps of that kind are met now: past them.
	while not lines.is_empty() and lines[0] is Dictionary and lines[0].has("rec_step") and str(lines[0].get("rec_kind", "genes")) == kind:
		lines.pop_front()
	_next()


# Card `c` has condition `cond`, negated (不) or not as `neg` says.
static func _has(c: Dictionary, cond: int, neg := false) -> bool:
	return (c.c1 == cond and bool(c.get("n1", false)) == neg) or (c.c2 == cond and bool(c.get("n2", false)) == neg)


func _any_card(test: Callable) -> bool:
	var d: Control = host.designer
	return d != null and d.deck_editor.deck.any(test)


# The foraging cards in order: the deck index of the n-th (from 0), or -1.
func _forage_card(n: int) -> int:
	var d: Control = host.designer
	if d == null:
		return -1
	var r := 0
	for k in d.deck_editor.deck.size():
		if int(d.deck_editor.deck[k].get("st", 0)) == Rules.S_FORAGE:
			if r == n:
				return k
			r += 1
	return -1


func _forage_rank(k: int) -> int:
	for r in 64:
		var j := _forage_card(r)
		if j < 0:
			return -1
		if j == k:
			return r
	return -1


# The blank new card in foraging (总是 → 漫游), or -1.
func _blank_card() -> int:
	var d: Control = host.designer
	if d == null:
		return -1
	for k in d.deck_editor.deck.size():
		var c: Dictionary = d.deck_editor.deck[k]
		if int(c.get("st", 0)) == Rules.S_FORAGE and c.c1 == Rules.C_NONE and c.c2 == Rules.C_NONE and c.act == Rules.A_WANDER:
			return k
	return -1


# A part of a card on screen (its view's hit rect), or empty.
func _card_part(k: int, part: String) -> Rect2:
	var d: Control = host.designer
	if d == null or k < 0:
		return Rect2()
	for v: Control in d.deck_editor.views:
		if v.index == k and v.hits.has(part):
			var r: Rect2 = v.hits[part]
			return Rect2(v.get_global_transform() * r.position, r.size)
	return Rect2()


# Index of the first card with this action in the designer's deck, or -1.
func _card_of(act: int) -> int:
	var d: Control = host.designer
	if d == null:
		return -1
	for k in d.deck_editor.deck.size():
		if d.deck_editor.deck[k].act == act:
			return k
	return -1


# The first card in the deck that is not one the level started with and
# passes `test`, or -1.
func _new_card(test: Callable) -> int:
	var d: Control = host.designer
	if d == null:
		return -1
	var old: Array = d.start_deck().map(func(c: Dictionary) -> String: return Rules.card_text(c))
	# (An edited old card also reads as new: the selected one, just added, first.)
	var sel: int = d.deck_editor.selected
	if sel >= 0 and sel < d.deck_editor.deck.size() and not old.has(Rules.card_text(d.deck_editor.deck[sel])) and test.call(d.deck_editor.deck[sel]):
		return sel
	for k in d.deck_editor.deck.size():
		var c: Dictionary = d.deck_editor.deck[k]
		if not old.has(Rules.card_text(c)) and test.call(c):
			return k
	return -1


func _skip() -> void:
	skipped = true
	cur = {}
	card.visible = false
	veil.visible = false
	target = null
	CampaignSave.mark_tutorial(runner.level.id)


func on_released() -> void:
	_show("run")


func _process(delta: float) -> void:
	# The designer's lines belong to the designer: they go with it.
	if host.designer:
		had_designer = true
	if step == "design" and had_designer and host.designer == null and not cur.is_empty():
		card.visible = false
		lines.clear()
		cur = {}
	_place_card()
	if skipped or cur.is_empty():
		ring.rect = Rect2()
		ring.src = Rect2()
		ring.queue_redraw()
		_veil(Rect2(), Rect2(), delta)
		return
	# A timed step shows when its moment comes.
	if not card.visible and _due() and cur.has("text"):
		card.visible = true
		card.appear()
	# Done: say so, then go on.
	if done_t < 0.0 and cur.has("wait") and card.visible and _met(cur.wait):
		# Done: say why it works (the step only gave the direction).
		done_t = 0.7
		todo_label.text = "✓ 已完成"
		if cur.has("why"):
			# Long enough to read: about 9 characters a second.
			var why := "✓ " + Keys.fill(cur.why)
			done_t = clampf(1.2 + why.length() / 9.0, 3.0, 9.0)
			_say(why)
		Audio.sfx("ui_confirm")
	if done_t >= 0.0:
		done_t -= delta
		if done_t < 0.0:
			_next()
	# The player switched modes mid-step: the step's other wording.
	if cur.has("adv") and done_t < 0.0 and card.visible:
		var want := Keys.fill(str(_v("text", "")))
		if text_label.text != want:
			_say(want)
			todo_label.text = _todo()
	# Ring the control the step is about (and the piece to drag there).
	var r := Rect2()
	var src := Rect2()
	if card.visible:
		r = _ring_rect(str(_v("ring", "")))
		src = _src_rect() if r.size != Vector2.ZERO else Rect2()
	ring.rect = r
	ring.src = src
	ring.queue_redraw()
	# A doing step veils the rest of the screen (clicks still go through).
	var doing: bool = cur.has("wait") and done_t < 0.0
	_veil(r if doing else Rect2(), src if doing else Rect2(), delta)
	# (Again: a step that just changed moves the card this frame, not next.)
	_place_card()


func _place_card() -> void:
	# With a target the card docks right beside it (under it, else over it)
	# and a leader line joins them; without one it keeps its old place: the
	# clear band under the DNA in the designer, the lower deck area on the
	# rules page, the top over the dish.
	var vs := card.get_viewport_rect().size
	var vw := vs.x
	var rr := _ring_rect(str(_v("ring", ""))) if not cur.is_empty() else Rect2()
	var rules_page: bool = host.designer != null and host.designer.page == "rules"
	var w := 640.0 if rr.size != Vector2.ZERO else (760.0 if rules_page else 800.0)
	# The width first: it sets how many lines the text wraps to, so the height.
	if text_label.custom_minimum_size.x != w - 50.0:
		text_label.custom_minimum_size.x = w - 50.0
		todo_label.custom_minimum_size.x = w - 50.0
		_say(text_label.text)
	if _todo_fit != todo_label.text + str(todo_label.custom_minimum_size.x):
		_fit_todo()
	var ch := maxf(134.0, card.get_combined_minimum_size().y)
	var top := 690.0 if host.designer else 96.0
	var cx := 0.0
	if rules_page:
		top = 948.0 - 40.0 - ch
		cx = (428.0 + 1896.0) * 0.5 - vw * 0.5
	if rr.size != Vector2.ZERO:
		var below := rr.end.y + 30.0
		var above := rr.position.y - 30.0 - ch
		top = below if below + ch < vs.y - 24.0 else (above if above > 24.0 else top)
		var left := clampf(rr.get_center().x - w * 0.5, 24.0, vw - 24.0 - w)
		cx = left + w * 0.5 - vw * 0.5
		if Rect2(left, top, w, ch).intersects(rr.grow(8.0)):
			# No room above or below: beside it.
			top = clampf(rr.get_center().y - ch * 0.5, 24.0, vs.y - 24.0 - ch)
			left = rr.position.x - 30.0 - w if rr.position.x - 30.0 - w > 24.0 else rr.end.x + 30.0
			cx = left + w * 0.5 - vw * 0.5
		# On the rules page the card would sit over the rule cards the player
		# is reading (under a mode switch, a personality, or one card of
		# several): it goes to the clear space under them instead, the leader
		# line still reaching up to the target.
		var deck_r := _deck_rect() if rules_page else Rect2()
		if rules_page and rr.end.x < 420.0:
			# A target in the left column (a personality, the temper slider):
			# the card goes right of it, in the deck panel's clear space, so
			# it covers neither the column nor the rule cards.
			var floor_y := deck_r.end.y + 34.0 if deck_r.size != Vector2.ZERO else 110.0
			top = clampf(rr.get_center().y - ch * 0.5, floor_y, 948.0 - 16.0 - ch)
			left = 452.0
			cx = left + w * 0.5 - vw * 0.5
		elif deck_r.size != Vector2.ZERO and Rect2(left, top, w, ch).intersects(deck_r):
			var under := deck_r.end.y + 34.0
			if under + ch < 948.0 - 16.0:
				top = under
				left = clampf(rr.get_center().x - w * 0.5, 452.0, 1872.0 - w)
				cx = left + w * 0.5 - vw * 0.5
		# On the body page the card covered the very tiles it asked for (it
		# docked under the one ringed, over the next ones): it sits over the
		# gene strip under the scope instead, clear of the tiles, the scope
		# and the readout, the leader line still reaching the target.
		var bb: Control = host.designer.body_bench if host.designer and host.designer.page == "body" and host.designer.get("body_bench") else null
		if bb and bb.strand and bb.strand.is_visible_in_tree():
			var sr: Rect2 = bb.strand.get_global_rect()
			left = clampf(sr.get_center().x - w * 0.5, 24.0, vw - 24.0 - w)
			top = clampf(sr.position.y, 24.0, vs.y - 24.0 - ch)
			cx = left + w * 0.5 - vw * 0.5
		# Last: never over the target, the rule cards or "+ 添加规则" (3-1
		# review: the card sat on the button it asked for). Try the other
		# sides in turn; the first clear one wins.
		var avoid: Array[Rect2] = [rr.grow(8.0)]
		if deck_r.size != Vector2.ZERO:
			avoid.append(deck_r)
		if rules_page and host.designer.add_button.is_visible_in_tree():
			avoid.append(host.designer.add_button.get_global_rect().grow(4.0))
		var clear := func(l: float, t: float) -> bool:
			var r := Rect2(l, t, w, ch)
			if l < 24.0 or t < 24.0 or r.end.x > vw - 24.0 or r.end.y > vs.y - 24.0:
				return false
			return not avoid.any(func(o: Rect2) -> bool: return r.intersects(o))
		if not clear.call(left, top):
			var mid_x := clampf(rr.get_center().x - w * 0.5, 24.0, vw - 24.0 - w)
			var mid_y := clampf(rr.get_center().y - ch * 0.5, 24.0, vs.y - 24.0 - ch)
			var cands: Array[Vector2] = [Vector2(mid_x, rr.position.y - 30.0 - ch), Vector2(rr.position.x - 30.0 - w, mid_y), Vector2(rr.end.x + 30.0, mid_y), Vector2(mid_x, rr.end.y + 30.0)]
			if deck_r.size != Vector2.ZERO:
				# Under the cards but to one side of the centred "+ 添加规则".
				cands.append(Vector2(deck_r.position.x, deck_r.end.y + 34.0))
				cands.append(Vector2(deck_r.end.x - w, deck_r.end.y + 34.0))
				# Or squeezed between the cards and the button.
				if rules_page and host.designer.add_button.is_visible_in_tree():
					cands.append(Vector2(mid_x, host.designer.add_button.get_global_rect().position.y - 6.0 - ch))
			for c: Vector2 in cands:
				if clear.call(c.x, c.y):
					left = c.x
					top = c.y
					cx = left + w * 0.5 - vw * 0.5
					break
	ring.card_rect = Rect2(vw * 0.5 + cx - w * 0.5, top, w, ch) if card.visible else Rect2()
	if card.offset_top != top or card.offset_left != cx - w * 0.5 or card.offset_bottom != top + ch:
		card.offset_top = top
		card.offset_bottom = top + ch
		card.offset_left = cx - w * 0.5
		card.offset_right = cx + w * 0.5


# The rule cards on show (inside the deck panel), as one rect.
func _deck_rect() -> Rect2:
	var d: Control = host.designer
	var out := Rect2()
	var panel := Rect2(428.0, 92.0, 1468.0, 856.0)
	for k in d.deck_editor.deck.size():
		var cr: Rect2 = d.deck_editor.card_rect(k)
		if cr.size == Vector2.ZERO or not panel.intersects(cr):
			continue
		cr = cr.intersection(panel)
		out = cr if out.size == Vector2.ZERO else out.merge(cr)
	return out


# A step that drags a piece out of the library ("把左边的“进入警戒”拖到…",
# or src = the piece's name) lights the piece as well as where it goes.
var src_re := RegEx.create_from_string("左边的[“「]([^”」]+)[”」]")


func _src_rect() -> Rect2:
	var d: Control = host.designer
	if d == null or d.page != "rules" or d.rules_mode != "advanced" or not cur.has("wait") or done_t >= 0.0:
		return Rect2()
	var piece := str(_v("src", ""))
	if piece == "":
		var m := src_re.search(str(_v("text", "")))
		if m == null:
			return Rect2()
		piece = m.get_string(1)
	for b: Control in d.piece_chips:
		if b.text == piece and b.is_visible_in_tree():
			return b.get_global_rect()
	return Rect2()


func _veil(hole: Rect2, hole2: Rect2, delta: float) -> void:
	var want := 1.0 if hole.size != Vector2.ZERO else 0.0
	veil_a = move_toward(veil_a, want, delta / 0.35)
	veil.visible = veil_a > 0.001
	if not veil.visible:
		return
	var m := veil.material as ShaderMaterial
	m.set_shader_parameter("size", veil.size)
	m.set_shader_parameter("alpha", veil_a)
	if hole.size != Vector2.ZERO:
		var g := hole.grow(10.0)
		m.set_shader_parameter("hole", Vector4(g.position.x, g.position.y, g.size.x, g.size.y))
		var g2 := hole2.grow(8.0) if hole2.size != Vector2.ZERO else Rect2()
		m.set_shader_parameter("hole2", Vector4(g2.position.x, g2.position.y, g2.size.x, g2.size.y))


# Ring keys that need the card editor (the rules page's advanced mode).
const EDIT_KEYS := ["add", "newcard", "blank_handle", "card2_cond", "card2_cond2", "card2_neg2", "card2_act", "emit_a_act", "smell_a_cond", "state_map", "hunt_pieces", "flee_join", "algae_card", "rest_card", "flee_card", "hunt_card", "divide_card", "comfort", "flee_slider", "to_breed_card"]


func _ring_rect(key: String) -> Rect2:
	var d: Control = host.designer
	var c: Control = null
	if d and d.page == "rules" and d.rules_mode == "simple" and key in EDIT_KEYS and (key == "add" or cur.has("wait")):
		return d.mode_adv.get_global_rect() if d.mode_adv.is_visible_in_tree() else Rect2()
	if key == "mode_adv" and d:
		c = d.mode_adv if d.page == "rules" else d.tab_buttons["rules"]
	# A gene's row (the recommended values).
	if key.begins_with("vtrait:") and d:
		if d.page != "virus" or d.virus_bench == null:
			c = d.tab_buttons.get("virus")
		else:
			var ps: Array = d.virus_bench.pips.get(key.substr(7), [])
			if not ps.is_empty():
				return (ps[0] as Control).get_global_rect().merge((ps[ps.size() - 1] as Control).get_global_rect()).grow(4.0)
	if key.begins_with("vmode:") and d:
		if d.page != "virus" or d.virus_bench == null:
			c = d.tab_buttons.get("virus")
		else:
			c = d.virus_bench.mode_latent if key.substr(6) == "true" else d.virus_bench.mode_lytic
	if key == "rec_body" and d:
		c = d.tab_buttons.get("body") if d.page != "body" or d.body_bench == null else d.body_bench.scope
	if key.begins_with("gene:") and d:
		c = d.tab_buttons["genome"] if d.page != "genome" else d.gene_rows[int(key.substr(5))]
	# The ⋮⋮ handle of the card with action X (chapters 7, 8).
	if key.begins_with("handle:") and d:
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		else:
			return _card_part(_card_of(int(ACT_NAMES.get(key.substr(7), -1))), "handle").grow(4.0)
	if key.begins_with("persona:") and d:
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		elif d.rules_mode == "advanced":
			c = d.mode_simple # the personalities are the other mode
		else:
			c = d.persona_picker.cards.get(key.substr(8))
	match key:
		"go":
			c = d.go if d else null
		"body_board":
			# (The scope, not the board: the board is zoomed past its edges.)
			c = d.body_bench.scope if d and d.body_bench else null
		"tile:6", "tile:7", "tile:8", "tile:9":
			c = d.body_bench.tiles.get(int(key.substr(5))) if d and d.body_bench else null
		"mutate":
			c = d.mutate_pill if d else null
		"resp":
			c = d.resp_pill if d else null
		"acid":
			if d == null:
				return Rect2()
			c = d.tab_buttons["genome"] if d.page != "genome" else d.acid_slider
		"life":
			if d == null:
				return Rect2()
			c = d.tab_buttons["genome"] if d.page != "genome" else d.life_slider
		"fert":
			if d == null:
				return Rect2()
			c = d.tab_buttons["genome"] if d.page != "genome" else d.gene_rows[4]
		"avoid_handle":
			if d == null:
				return Rect2()
			if d.page != "rules":
				c = d.tab_buttons["rules"]
			else:
				return _card_part(_card_of(Rules.A_AVOID_O2), "handle").grow(4.0)
		"temp":
			c = d.temp_slider if d else null
		"divide":
			if d == null:
				return Rect2()
			if d.page != "rules":
				c = d.tab_buttons["rules"]
			elif d.rules_mode == "simple":
				c = d.persona_picker.slider
			else:
				return d.deck_editor.slider_rect(Rules.A_DIVIDE)
		"speed":
			if d == null:
				return Rect2()
			c = d.tab_buttons["genome"] if d.page != "genome" else d.gene_rows[0]
		"speed_fert":
			if d == null:
				return Rect2()
			if d.page == "genome":
				return d.gene_rows[0].get_global_rect().merge(d.gene_rows[4].get_global_rect())
			c = d.tab_buttons["genome"]
		"metab":
			if d == null:
				return Rect2()
			c = d.tab_buttons["genome"] if d.page != "genome" else d.gene_rows[5]
	if key == "add" and d:
		c = d.add_button if d.page == "rules" else d.tab_buttons["rules"]
	if key in ["emit_a_act", "smell_a_cond"] and d:
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		elif key == "emit_a_act":
			return _card_part(_card_of(Rules.A_EMIT_A), "z_act")
		else:
			var kf: int = d.deck_editor.deck.find_custom(func(cd: Dictionary) -> bool: return cd.act == Rules.A_FLEE and Rules.C_SIGNAL_A in [cd.c1, cd.c2])
			return _card_part(kf, "z_g1")
	if key in ["blank_handle", "card2_cond", "card2_cond2", "card2_neg2", "card2_act"] and d:
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		elif d.deck_editor.cur_state != Rules.S_FORAGE:
			c = d.state_bar
		elif key == "blank_handle":
			return _card_part(_blank_card(), "handle").grow(4.0)
		else:
			return _card_part(_forage_card(1), {card2_cond = "z_g1", card2_cond2 = "z_g2", card2_neg2 = "neg2", card2_act = "z_act"}[key])
	if key == "newcard" and d:
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		else:
			var k := _new_card(func(_c: Dictionary) -> bool: return true)
			return d.deck_editor.card_rect(k) if k >= 0 else Rect2()
	if key == "state_map" and d:
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		elif d.state_bar:
			c = d.state_bar
	if key.begins_with("slot:") and d and int(key.substr(5)) < d.slot_tabs.size():
		c = d.slot_tabs[int(key.substr(5))]
	if key == "prey_genes" and d:
		if d.page != "genome":
			c = d.tab_buttons["genome"]
		else:
			return d.gene_rows[0].get_global_rect().merge(d.gene_rows[4].get_global_rect())
	if key == "race_genes" and d:
		if d.page != "genome":
			c = d.tab_buttons["genome"]
		else:
			return d.gene_rows[0].get_global_rect().merge(d.gene_rows[4].get_global_rect())
	if key == "armour" and d and d.organ_bay:
		if d.page != "genome":
			c = d.tab_buttons["genome"]
		else:
			return d.organ_bay.chips.silica.get_global_rect().merge(d.organ_bay.chips.spines.get_global_rect())
	if key.begins_with("organ:") and d and d.organ_bay:
		if d.page != "genome":
			c = d.tab_buttons["genome"]
		else:
			c = d.organ_bay.chips.get(key.substr(6))
	if key == "hunt_pieces" and d:
		# The piece still to place: "看见猎物" first, then "追捕".
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		else:
			var seen: bool = d.deck_editor.deck.any(func(cd: Dictionary) -> bool: return Rules.C_SEE_PREY in [cd.c1, cd.c2])
			var want := "追捕" if seen else "看见猎物"
			for b: Control in d.piece_chips:
				if b.text == want:
					c = b
	# Level 9: the motor pair; the forage flee card / alert's way back, or the
	# state map when the other state is on show.
	if key == "motor" and d and d.organ_bay and d.page == "genome":
		return d.organ_bay.chips.flagellum.get_global_rect().merge(d.organ_bay.chips.cilia.get_global_rect())
	if key in ["to_alert_card", "calm_card", "to_alert_slider"] and d:
		var want := Rules.S_ALERT if key == "calm_card" else Rules.S_FORAGE
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		elif d.deck_editor.cur_state != want:
			c = d.state_bar
		elif key == "calm_card":
			return d.deck_editor.slider_rect(Rules.A_TO_FORAGE)
		elif key == "to_alert_slider":
			return d.deck_editor.slider_rect(Rules.A_TO_ALERT)
		else:
			return d.deck_editor.card_rect(_card_of(Rules.A_FLEE))
	if key == "signal_organs" and d and d.organ_bay:
		if d.page != "genome":
			c = d.tab_buttons["genome"]
		else:
			return d.organ_bay.chips.gland.get_global_rect().merge(d.organ_bay.chips.chemo_rec.get_global_rect())
	if key in ["flee_slider", "to_breed_card"] and d:
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		elif d.deck_editor.cur_state != Rules.S_FORAGE:
			c = d.state_bar
		elif key == "flee_slider":
			return d.deck_editor.slider_rect(Rules.A_FLEE)
		else:
			return d.deck_editor.card_rect(_card_of(Rules.A_DIVIDE))
	if key == "flee_join" and d:
		# The flee card; once it has a second condition, its 且 switch.
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		else:
			var k := _card_of(Rules.A_FLEE)
			if k >= 0 and d.deck_editor.deck[k].c2 != Rules.C_NONE and k < d.deck_editor.views.size() and d.deck_editor.views[k].hits.has("join"):
				var v: Control = d.deck_editor.views[k]
				var jr: Rect2 = v.hits.join
				return Rect2(v.get_global_transform() * jr.position, jr.size)
			return d.deck_editor.card_rect(k) if k >= 0 else Rect2()
	for pair: Array in [["algae_card", Rules.A_SEEK_ALGAE], ["rest_card", Rules.A_REST], ["flee_card", Rules.A_FLEE], ["hunt_card", Rules.A_HUNT]]:
		if key == pair[0] and d:
			if d.page != "rules":
				c = d.tab_buttons["rules"]
			else:
				var k := _card_of(pair[1])
				if k < 0:
					k = _card_of(Rules.A_HUNT)
				return d.deck_editor.card_rect(k)
	if key == "divide_card" and d:
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		else:
			return d.deck_editor.card_rect(_card_of(Rules.A_DIVIDE))
	if key == "comfort" and d:
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		else:
			return d.deck_editor.card_rect(_card_of(Rules.A_SEEK_COMFORT))
	if key.begins_with("card:") and d:
		if d.page != "rules":
			c = d.tab_buttons["rules"]
		else:
			return d.deck_editor.card_rect(int(key.substr(5)))
	if key.begins_with("scan:") and host.hud_root.scan.has(key.substr(5)):
		c = host.hud_root.scan[key.substr(5)]
	if key.begins_with("tab:") and d:
		c = d.tab_buttons.get(key.substr(4))
	if key.begins_with("dock:") and host.hud_root.dock_buttons.has(key.substr(5)):
		c = host.hud_root.dock_buttons[key.substr(5)]
	return c.get_global_rect() if c and c.is_visible_in_tree() else Rect2()


# The veil: pale frosted white everywhere but a rounded hole over the target,
# whose rim glows faintly in the accent.
const VEIL := preload("res://shaders/guide_veil.gdshader")


class Ring extends Control:
	var rect := Rect2()
	var src := Rect2() # the piece to drag to `rect`, when the step drags one
	var card_rect := Rect2() # the guide card, for the leader line
	var t := 0.0

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		t += delta

	func _draw() -> void:
		if rect.size == Vector2.ZERO:
			return
		var g := 6.0 + 3.0 * sin(t * 4.0)
		var r := rect.grow(g)
		var rad := int(minf(r.size.y * 0.5, 18.0))
		# A soft glow under the line, the line, then a ripple running outward.
		for k in 3:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_border_width_all(2 + k * 3)
			sb.border_color = Color(Ui.ACCENT, 0.1 - k * 0.03)
			sb.set_corner_radius_all(rad + k * 2)
			sb.anti_aliasing = true
			draw_style_box(sb, r.grow(1.0 + k * 2.0))
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_border_width_all(3)
		sb.border_color = Color(Ui.ACCENT, 0.95)
		sb.set_corner_radius_all(rad)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var u := fmod(t, 1.6) / 1.6
		var rip := StyleBoxFlat.new()
		rip.draw_center = false
		rip.set_border_width_all(2)
		rip.border_color = Color(Ui.ACCENT, 0.55 * (1.0 - u))
		rip.set_corner_radius_all(rad + int(18.0 * u))
		rip.anti_aliasing = true
		draw_style_box(rip, r.grow(18.0 * u))
		# The leader: from the card's nearest edge to the ring, with a dot.
		if card_rect.size != Vector2.ZERO and not card_rect.intersects(r):
			var a := Vector2(clampf(r.get_center().x, card_rect.position.x + 24.0, card_rect.end.x - 24.0), card_rect.position.y if card_rect.position.y > r.end.y else card_rect.end.y)
			if card_rect.position.y <= r.end.y and card_rect.end.y >= r.position.y:
				a = Vector2(card_rect.end.x if card_rect.end.x < r.position.x else card_rect.position.x, clampf(r.get_center().y, card_rect.position.y + 20.0, card_rect.end.y - 20.0))
			var b := Vector2(clampf(a.x, r.position.x, r.end.x), clampf(a.y, r.position.y, r.end.y))
			draw_line(a, b, Color(Ui.ACCENT, 0.8), 1.5, true)
			draw_circle(a, 3.5, Ui.ACCENT)
			draw_circle(b, 3.0, Ui.ACCENT)
		if src.size != Vector2.ZERO:
			_draw_source(r)

	# The piece to pick up: its own ring, and a dashed arc from it to the
	# target with a bead running along it (the way to drag it).
	func _draw_source(target: Rect2) -> void:
		var s := src.grow(4.0 + 2.0 * sin(t * 4.0 + 1.0))
		var rad := int(minf(s.size.y * 0.5, 14.0))
		for k in 2:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_border_width_all(2 + k * 3)
			sb.border_color = Color(Ui.ACCENT, 0.9 if k == 0 else 0.1)
			sb.set_corner_radius_all(rad + k * 2)
			sb.anti_aliasing = true
			draw_style_box(sb, s.grow(k * 2.0))
		var right: bool = s.get_center().x < target.position.x
		var a := Vector2(s.end.x, s.get_center().y) if right else s.get_center()
		var b := Vector2(target.position.x, target.get_center().y) if right else target.get_center()
		var lift := clampf(a.distance_to(b) * 0.18, 30.0, 120.0)
		var c := (a + b) * 0.5 - Vector2(0.0, lift)
		var pts := PackedVector2Array()
		for k in 49:
			var u := k / 48.0
			pts.append(a.lerp(c, u).lerp(c.lerp(b, u), u))
		for k in range(0, 48, 2):
			draw_line(pts[k], pts[k + 1], Color(Ui.ACCENT, 0.7), 1.6, true)
		var bu := fmod(t * 0.55, 1.0)
		var bead := a.lerp(c, bu).lerp(c.lerp(b, bu), bu)
		draw_circle(bead, 4.0, Color(Ui.ACCENT, 0.9 * (1.0 - bu * 0.6)))
		var dir := (pts[48] - pts[45]).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([b, b - dir * 11.0 + nrm * 5.5, b - dir * 11.0 - nrm * 5.5]), Color(Ui.ACCENT, 0.85))
