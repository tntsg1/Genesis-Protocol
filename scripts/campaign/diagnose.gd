class_name Diagnose
extends RefCounted
# Diagnostic teaching (DECISIONS 诊断式教学, Q270–Q274): no step-by-step guide
# past chapter 1; instead the run is watched, and when a typical problem
# shows in the numbers, a short card says what is happening and which piece
# or tool answers it. Each problem is said once a run. The report reuses the
# same reading for "what killed them this time". The words are a first
# draft for the user to rewrite.
#
# A snapshot is the player's species' counters (and a few of the world's)
# at one moment; rules compare now with WINDOW seconds ago.

const WINDOW := 30.0

# The player's numbers now, from the sim and the evaluator.
static func snapshot(sim: SimCore, ev: LevelEval, t: float) -> Dictionary:
	var per: Array = sim.get_stats().species
	var s: Dictionary = per[ev.sp]
	var all := []
	for e: Dictionary in per:
		all.append([int(e.alive), int(e.starved)])
	return {t = t, alive = ev.alive, births = int(s.births), starved = int(s.starved), eaten = int(s.eaten),
		aged = int(s.aged), temp = int(s.temp), acid = int(s.acid), o2 = int(s.o2), phage = int(s.phage),
		immune = int(s.get("immune", 0)), all = all, col = ev.colony_stats.duplicate(), slug = ev.slug_stats.duplicate(),
		helio_eaten = int(ev.helio.get("eaten", 0))}


# What went wrong between `a` and `b` (two snapshots), as [{id, title, text}]
# in order of weight; `l` the level, `sim`/`ev` for the level's own checks,
# `resp` how the player's species breathes.
static func read(l: Dictionary, sim: SimCore, ev: LevelEval, a: Dictionary, b: Dictionary, resp := -1, des := {}) -> Array:
	var out := []
	var span := maxf(1.0, float(b.t) - float(a.t))
	var alive := maxi(1, int(b.alive))
	var d := {}
	for k in ["births", "starved", "eaten", "aged", "temp", "acid", "o2", "phage"]:
		d[k] = int(b[k]) - int(a[k])
	var big := func(n: int) -> bool: return n >= maxi(6, int(0.15 * float(alive + n)))
	var mud: bool = l.world.has("mud")
	if resp < 0:
		resp = int(l.get("resp", 0))
	# The water's own dangers.
	if big.call(d.o2):
		if mud and resp != 1:
			out.append({id = "h2s", w = d.o2, title = "%d 只死在深层的硫化氢里" % d.o2,
				text = "越往下氧越少、硫化氢越浓，用氧的生命一进去就中毒。\n规则里加一张「不 氧气高于 X → 游向氧气」，让它们留在上层；或者用「搅动泥层」把那里冲淡一会儿。"})
		elif l.world.has("oxygen"):
			out.append({id = "o2", w = d.o2, title = "%d 只被氧气毒死" % d.o2,
				text = "你的生命是厌氧的：氧气对它是毒药。\n规则里加「氧气高于 X → 避开氧气」，或者换呼吸方式；撒铁粉能临时吸掉一片水里的氧。"})
		else:
			out.append({id = "tox", w = d.o2, title = "%d 只中毒死去" % d.o2,
				text = "水里有东西在毒害它们。看看事件日志里它们死在哪，带它们离开那片水。"})
	if big.call(d.temp):
		out.append({id = "temp", w = d.temp, title = "%d 只冻死或热死" % d.temp,
			text = "水温超出了它们的耐受范围。\n「温度不适 → 游向舒适区」能带它们去合适的水；也可以调最适水温、调宽耐温。" + ("\n长夜里冻死的，可以用芽孢熬过去。" if l.world.get("night_phase", false) else "")})
	if big.call(d.acid):
		out.append({id = "acid", w = d.acid, title = "%d 只被酸死" % d.acid,
			text = "酸在伤害它们。" + ("基因组页可以调「耐酸」；酸雨从水面往下渗得慢，下雨时也可以往深处躲。" if l.get("acid_open", false) else "离开酸的水，或者加厚外壳。")})
	if big.call(d.eaten):
		out.append({id = "eaten", w = d.eaten, title = "%d 只被吃掉" % d.eaten,
			text = "有东西在吃它们。\n把「猎手靠近 → 逃离」放到最上面；或者装护甲、加警戒状态，也可以抱团。"})
	if big.call(d.phage):
		out.append({id = "phage", w = d.phage, title = "%d 只被病毒撑破" % d.phage,
			text = "病毒在密集的地方传得最快。\n「同伴很多 → 远离同伴」让它们散开；有「记忆片段」的话，活下来的会记住病毒。"})
	if big.call(d.starved):
		out.append({id = "starve", w = d.starved, title = "%d 只饿死" % d.starved,
			text = "附近的食物不够它们吃。\n把「看见藻团 → 游向藻团」放得更靠前；调低繁殖，别一下生太多；用营养投放或洋流把它们引到食物多的地方。"})
	if d.births == 0 and float(b.t) >= 60.0 and int(b.alive) > 0 and int(b.alive) < 40 and span >= WINDOW - 1.0 and int(a.alive) > 0:
		out.append({id = "nobirth", w = 5, title = "30 秒里一只都没生出来",
			text = "它们能量攒不够，或者规则里的「分裂」排得太靠后、条件太严。\n看看「能量高于 X → 分裂」：X 是不是太高？"})
	if big.call(d.aged) and d.births < d.aged / 2:
		out.append({id = "aged", w = d.aged, title = "%d 只老死，新生的跟不上" % d.aged,
			text = "种群在变老：分裂得不够快。\n调高繁殖，或者把分裂卡往前放。"})
	# The level's own problems (chapters 1–8); one that sharpens a generic
	# reading takes its place.
	var own := _level_reads(l, sim, ev)
	own.append_array(_early_reads(l, sim, ev, a, b, d, big, des))
	for r: Dictionary in own:
		if r.has("replaces"):
			out = out.filter(func(x: Dictionary) -> bool: return x.id != r.replaces)
	out.append_array(own)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.w) > int(y.w))
	return out


static func _level_reads(l: Dictionary, sim: SimCore, ev: LevelEval) -> Array:
	var out := []
	match l.id:
		"8-2":
			if ev.t > 60.0 and ev.symb_now == 0:
				out.append({id = "nosymb", w = 50, title = "还没有细胞吞到紫光游丝",
					text = "吞噬泡只有用上才算数。\n规则最上面加「不 带着共生菌 → 吞下不消化」：没吞到的就去找紫光游丝。"})
		"8-3":
			var rm: Vector2 = sim.get_res_mean(int(l.goal.rival))
			if rm.x >= 0.55:
				out.append({id = "res_a", w = 60, title = "抢食游丝对毒素甲的耐药已到 %d%%" % roundi(rm.x * 100.0),
					text = "一直用同一种毒素，活下来的都是耐药的。\n换毒素乙用一阵：对甲耐药的，对乙不耐药。"})
			if rm.y >= 0.55:
				out.append({id = "res_b", w = 60, title = "抢食游丝对毒素乙的耐药已到 %d%%" % roundi(rm.y * 100.0),
					text = "该换回毒素甲了：不用的那种毒素，耐药会慢慢退去。"})
			if ev.t > 60.0 and not ev.tox_used[0] and not ev.tox_used[1]:
				out.append({id = "notox", w = 40, title = "还没有放过毒",
					text = "抢食游丝繁殖太快，光靠吃抢不过它们。\n加一张「别的物种在 60 µm → 分泌毒素甲」：放毒不占动作，细胞边吃边放。"})
		"8-5":
			var linked := int(ev.slime.get("linked", 0))
			var owned := int(ev.slime.get("owned", 0))
			if linked >= 3 and owned < 2:
				out.append({id = "slime", w = 55, title = "黏菌已经连上 %d 个藻场" % linked,
					text = "连上的藻场它会一直吸。\n在管道旁放毒能把它烧断，隔离膜能挡住它往前长；也要尽快占住还没连上的藻场。"})
	return out


# Chapters 1–7 (DECISIONS Q286, design/卡关帮助补齐_稿子.md): the levels whose
# own mechanism the generic readings miss. The words are the user's.
static func _early_reads(l: Dictionary, sim: SimCore, ev: LevelEval, a: Dictionary, b: Dictionary, d: Dictionary, big: Callable, des: Dictionary) -> Array:
	var out := []
	var t := float(b.t)
	var span := float(b.t) - float(a.t)
	var deck: Array = (des.get("params", {}) as Dictionary).get("deck", [])
	var has_act := func(act: int) -> bool: return deck.any(func(c: Dictionary) -> bool: return int(c.act) == act)
	var said := func(id: String, w: int, title: String, text: String, replaces := "") -> void:
		var r := {id = id, w = w, title = title, text = text}
		if replaces != "":
			r.replaces = replaces
		out.append(r)
	match str(l.id):
		"1-4":
			var rest := deck.find_custom(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == 0 and int(c.act) == Rules.A_REST)
			var div := deck.find_custom(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == 0 and int(c.act) == Rules.A_DIVIDE)
			if d.births == 0 and span >= WINDOW - 1.0 and int(b.alive) > 0 and rest >= 0 and (div < 0 or rest < div):
				said.call("rest_first", 70, "「休息」规则影响了细胞分裂", "细胞会从上往下检查规则，找到第一张符合条件的规则卡就会执行。如果「休息」排在「分裂」前面，细胞就算有足够的能量，也可能一直无法分裂。\n试着把「分裂」规则拖到「休息」上面，让细胞优先进行繁殖。", "nobirth")
		"1-5":
			if t >= 150.0 and ev.patches_won < 2:
				var lost := ev.patch_counts.filter(func(pc: Array) -> bool: return int(pc[1]) > int(pc[0])).size()
				if lost > 0:
					said.call("patches", 60, "冰晶游丝还占据着 %d 片藻场" % lost, "你的细胞分散在不同的藻场里，数量不够，很难和冰晶游丝竞争。\n可以先让细胞集中在中央光藻附近，等它们获得足够的能量并繁殖起来以后，再利用洋流把一批细胞送进同一片藻场。先占下一片，再考虑其他地方。")
		"2-1":
			if t >= 60.0 and ev.first_kill < 0.0:
				said.call("nokill", 60, "已经过了 60 秒，还没有捕获猎物", "浮游丝的移动速度比较快，甲游丝则有坚硬的外壳，可以先选择其中一种作为主要猎物，调整捕食方式。\n没有发现猎物的时候，可以让捕食者进入休息状态，减少不必要的能量消耗，避免还没抓到猎物就饿死了。")
		"2-3":
			var aa: Array = a.get("all", [])
			var ba: Array = b.get("all", [])
			if ev.sp < aa.size() and ev.sp < ba.size() and int(aa[ev.sp][0]) >= 20 and int(ba[ev.sp][0]) * 2 < int(aa[ev.sp][0]):
				said.call("prey_crash", 65, "猎物数量下降得太快了", "现在的捕食者可能太多了，猎物的繁殖速度跟不上消耗，继续这样下去，捕食者也会因为找不到食物而饿死。\n可以降低捕食者的繁殖等级，同时提高猎物的繁殖等级。如果需要暂时保护猎物，还可以按 2 放置隔离膜，阻挡捕食者一段时间。", "eaten")
			var s2 := int(ev.sp2)
			if s2 >= 0 and s2 < aa.size() and s2 < ba.size():
				var st2 := int(ba[s2][1]) - int(aa[s2][1])
				if st2 >= 3 and float(st2) > 0.3 * float(int(ba[s2][0]) + st2):
					said.call("hunter_starve", 60, "很多捕食者都饿死了", "猎物的移动速度可能太快了，捕食者一直追不上，反而消耗了大量能量。\n可以给捕食者增加一张「在本状态超过 X 秒 → 进入休眠」规则卡，让它们在一段时间后停止活动，减少能量消耗。也可以尝试降低猎物的速度等级，让捕食者更容易抓到猎物。")
		"2-4":
			if big.call(d.starved) and has_act.call(Rules.A_TO_ALERT):
				said.call("alert_starve", int(d.starved) + 1, "细胞在警戒时消耗了太多能量", "警戒状态下的能量消耗是平时的 1.4 倍，如果细胞一直保持警戒，就可能因为能量不足而饿死。\n试着增加一张「不 猎手靠近 → 进入觅食」规则卡。等附近没有猎手时，细胞就会重新寻找食物，避免一直消耗能量。", "starve")
		"2-5":
			if ev.boss_energy > 0.7:
				said.call("boss_full", 70, "巨噬者快要开始分裂了", "巨噬者获得足够的能量以后，就会分裂成两只，到时候需要应付的巨噬者会更多。\n可以把「猎手靠近 → 逃离」放到规则列表最上面，让细胞遇到危险时优先逃跑。等巨噬者离开以后，再通过「繁殖期」增加细胞数量，把损失的细胞补充回来。")
		"3-1":
			if big.call(d.eaten) and not has_act.call(Rules.A_EMIT_A):
				said.call("no_alarm", int(d.eaten) + 1, "暗噬靠近时，其他细胞没有收到警报", "深水里的感知距离比较短，等每个细胞自己发现暗噬时，可能已经来不及逃跑了。\n可以增加「猎手靠近 → 释放信号 A」，让发现暗噬的细胞向周围发送警报，再配合「信号 A 浓 → 逃离」，让附近的细胞提前逃跑。", "eaten")
		"3-2":
			if big.call(d.eaten):
				said.call("one_by_one", int(d.eaten) + 1, "细胞被急梭吃掉了不少", "急梭每吃掉一只细胞，都需要停下来消化 6 秒，可以利用这段时间增加细胞数量。\n试着增加「看见繁殖期中的同伴 → 进入繁殖期」规则，让附近的细胞一起进入繁殖期。只要繁殖速度足够快，就有机会补回被急梭吃掉的数量。", "eaten")
		"3-3":
			if big.call(d.starved):
				said.call("hard_algae", int(d.starved) + 1, "吃硬藻只能获得四成能量", "单个细胞分泌的消化酶很快就会扩散，能够分解的硬藻有限，细胞也就很难获得足够的能量。\n可以增加「同伴很多 ≥ X → 分泌消化酶」规则，让细胞等到附近有足够多的同伴时再分泌消化酶，提高分解硬藻的效率。", "starve")
		"3-4":
			if t >= 120.0 and ev.rival_alive > ev.alive:
				said.call("echo_more", 60, "回声菌群的数量已经超过你了", "回声菌群也会释放信号 A，你的细胞收到这些信号以后，可能会在没有危险的时候逃跑，浪费了原本可以用来觅食和繁殖的时间。\n可以把警报改成信号 B，分别设置「猎手靠近 → 释放信号 B」和「信号 B 浓 → 逃离」，然后删除原来的信号 A 规则卡，避免细胞受到回声菌群的信号干扰。")
		"4-2":
			if t >= 200.0 and t < 240.0 and int(b.alive) > 0 and float(b.get("immune", 0)) < 0.3 * float(b.alive):
				said.call("few_immune", 60, "有免疫记忆的细胞还不够多", "到了第 4 分钟，病毒会开始大规模爆发，没有免疫记忆的细胞很难存活下来。\n可以增加「有免疫记忆 → 进入繁殖期」规则，让已经获得免疫记忆的细胞优先繁殖。这些细胞已经能够抵抗裂囊针，所以也不需要继续躲避了。")
		"4-3":
			var rv := int(l.goal.get("rival", 0))
			var ba3: Array = b.get("all", [])
			if t >= 120.0 and rv < ba3.size() and int(ba3[rv][0]) > ev.alive:
				said.call("rival_more", 60, "绒游丝的数量已经超过你了", "有些细胞已经快要耗尽能量了，可以让它们在死亡之前发挥一点作用。\n试着增加「能量低于 X → 唤醒潜伏针」规则，让这些细胞提前唤醒体内的病毒。这样病毒就有机会在绒游丝之间继续传播。")
		"4-4":
			if ev.shots >= 1 and not ev.shot_times.is_empty() and t - float(ev.shot_times[0]) >= 30.0 and ev.rival_lysed < 10:
				said.call("drop_missed", 60, "病毒感染的绒游丝太少了", "你投放病毒的位置可能没有多少绒游丝，病毒还没有接触到足够的宿主，就已经在水中失效了。\n可以等绒游丝的数量增加以后，再选择它们最密集的位置投放病毒。也可以提高病毒的外壳等级，让病毒能够在水中存活更长时间。")
			var rv4 := int(l.goal.get("rival", 0))
			var ba4: Array = b.get("all", [])
			if t >= 90.0 and ev.shots == 0 and rv4 < ba4.size() and int(ba4[rv4][0]) > 100:
				said.call("no_drop", 55, "现在可以投放病毒了", "绒游丝的数量已经超过 100 只，现在可以开始投放病毒了。\n按下 5 键，选择绒游丝最密集的位置投放病毒，这样可以让病毒接触到更多宿主。")
		"4-5":
			if ev.giants > 200:
				said.call("giants_up", 60, "巨毒囊的数量已经超过 200 颗", "巨毒囊进入细胞以后会继续复制，如果不及时处理，后面就会出现更多巨毒囊。\n可以向自己的细胞投放潜伏型噬毒体，让噬毒体随着细胞分裂传给后代。细胞觅食的时候，也尽量避开巨毒囊比较密集的区域，减少吞入巨毒囊的机会。")
		"5-1":
			var sa: Dictionary = a.get("slug", {})
			var sb: Dictionary = b.get("slug", {})
			if t >= 120.0 and int(sb.get("formed", 0)) == 0:
				said.call("no_slug", 60, "细胞还没有成功聚合", "细胞需要在能量不足的时候开始聚合，如果一直没有形成聚合体，可以检查一下聚合规则。\n建议使用「能量低于 X 且 同伴很多 ≥ Y → 聚合」，其中能量阈值 X 不要超过 50%，同伴数量 Y 可以设置在 3 到 5 之间。\n还要保留释放信号 A 和游向信号 A 的规则，让附近的细胞能够聚集到一起。")
			if int(sb.get("broke", 0)) > int(sa.get("broke", 0)) or int(sb.get("lost", 0)) - int(sa.get("lost", 0)) >= 6:
				said.call("slug_broke", 55, "聚合体在热带区域解散了", "聚合体的规模可能太小了，进入热带区域以后就容易解散。\n可以先利用信号 A 让更多细胞聚集过来，等聚合体的规模足够大以后，再开始穿越热带区域。")
		"5-2", "5-3", "5-4":
			var ca: Dictionary = a.get("col", {})
			var cb: Dictionary = b.get("col", {})
			var dc := func(k: String) -> int: return int(cb.get(k, 0)) - int(ca.get(k, 0))
			if l.id == "5-2":
				if dc.call("burned") > 0:
					said.call("vent", 60, "细胞群体被水流冲进了喷口", "细胞群体的推力可能不够，无法抵抗喷口附近的水流。\n可以检查身体布局，把鞭毛块放在身体外侧。如果鞭毛块被其他模块完全包围，就无法发挥作用。\n实验运行的时候，还可以按住鼠标拖动来制造洋流，帮助细胞群体向上游移动。", "temp")
				if dc.call("lost") > 0:
					said.call("grit", 55, "砂砾击毁了部分子体", "砂砾撞到身体的第一个模块后就会停下来，如果生殖块放在外面，很容易直接受到撞击。\n可以把生殖块放在其他模块后面，让外面的模块先挡住砂砾，减少生殖块受到的伤害。")
			elif l.id == "5-3":
				var bites: int = dc.call("bites")
				var blocked: int = dc.call("blocked")
				if bites >= 6 and bites - blocked > blocked:
					said.call("soft_bites", 60, "身体外侧的软块经常受到攻击", "巨噬者会攻击最先接触到的身体模块，如果外侧放了太多软块，这些模块就很容易受到伤害。\n可以在身体外围多放一些甲块。这样巨噬者咬到甲块时，只会损失少量能量，里面的其他模块也能得到保护。", "eaten")
				var sv: int = dc.call("starved")
				if t >= 120.0 and t <= 200.0 and sv >= 2 and float(sv) > 0.3 * float(int(cb.get("bodies", 0)) + sv):
					said.call("famine", 60, "荒年期间，群体的能量储备不足", "从第 2 分钟开始，藻类会停止生长 1 分钟，这段时间里，群体很难获得足够的食物。\n可以在身体里增加几块储能块，并把它们放在生殖块前面。这样既能保护生殖块，也能利用之前储存的能量度过荒年。", "starve")
			else:
				if int(cb.get("broken", 0)) > 20 and int(cb.get("healed", 0)) * 2 < int(cb.get("broken", 0)):
					said.call("no_regen", 60, "被咬坏的身体模块恢复得太慢了", "如果身体里没有再生块，每个损坏的模块需要 3 分钟才能重新长出来，恢复速度可能跟不上受到攻击的速度。\n可以在身体内部增加一个再生块，尽量放在不容易被攻击的位置，让受损的模块更快恢复。")
		"5-5":
			if int(sim.get_rotifer_stats().get("eaten", 0)) > 5:
				said.call("swallowed", 60, "多个群体被轮虫吞下了", "如果身体外围有至少 4 块完好的甲块，轮虫就无法咬碎群体，会把吞进去的群体吐出来。\n如果已经有群体被吞下，可以使用「刺激头冠」，点击轮虫的头部。轮虫会收起头冠大约 6 秒，同时把嘴里的群体吐出来。")
		"6-1":
			if big.call(d.starved):
				said.call("far_vent", int(d.starved) + 1, "细胞离热泉太远，能量不足", "硫化酶只能在热泉附近获得能量，细胞距离热泉越远，获得的能量就越少。\n建议不要把速度等级调得太高，避免细胞游得太远而饿死。你还可以按住鼠标拖动来制造洋流，把一部分细胞送到另外两个热泉口。这样细胞就不会全部挤在同一个地方，每只细胞也能分到更多能量。", "starve")
		"6-2":
			if big.call(d.starved):
				said.call("dark", int(d.starved) + 1, "晨光丝在光照不足的地方饿死了", "光线从上方照下来，水越深，光照就越弱，热泉附近已经完全没有光照。晨光丝聚集得太密集也会互相遮挡，可以利用洋流把一部分晨光丝送到其他光照充足的位置。", "starve")
		"6-3":
			if t >= 180.0 and ev.o2_mean < 0.06:
				said.call("o2_slow", 60, "氧气浓度增长得太慢了", "晨光丝的数量可能还不够，也可能聚集得太密集，影响了光照。可以提高晨光丝的繁殖等级，让它们在有光照的地方分散生长。")
		"6-4":
			var aa6: Array = a.get("all", [])
			var ba6: Array = b.get("all", [])
			var slots := [ev.sp, ev.sp2, ev.sp3]
			for k in slots.size():
				var s6 := int(slots[k])
				if s6 >= 0 and s6 < aa6.size() and s6 < ba6.size() and int(aa6[s6][0]) >= 10 and int(ba6[s6][0]) * 2 < int(aa6[s6][0]):
					var lab: String = str((l.species[k] as Dictionary).get("label", "")) if k < (l.species as Array).size() else ""
					said.call("crash_%d" % k, 65, "%s快要灭绝了" % lab, "可能是捕食它们的生物太多，也可能是它们的食物快被吃光了。可以查看种群数量曲线，找到数量最先快速增长的物种，再适当降低它们的繁殖等级。")
					break
		"7-1":
			if big.call(d.starved) and not has_act.call(Rules.A_RETURN):
				said.call("no_return", int(d.starved) + 1, "吃饱以后没有返回暖水区", "冰层下面的温度太低，细胞无法正常分裂。可以先在暖水区设置「记住这里」，等细胞进食以后，再通过「回到记忆点」返回暖水区进行分裂。", "starve")
		"7-4":
			var ends: Array = l.goal.get("ends", [])
			for k in range(1, ends.size()):
				var start := float(ends[k - 1][0])
				if t >= start + 20.0 and t < start + 40.0:
					var zone := {center = ends[k][1], radius = float(ends[k][2])}
					if LevelEval.count_in(sim, ev.sp, zone) < 10:
						said.call("season_%d" % k, 60, "季节已经变了，细胞还留在原来的地方", "换季以后，原来的雪藻会慢慢腐烂，继续留在那里就很难找到食物。可以添加「不 看见藻团 → 漫游」这条规则，让细胞在找不到藻团时主动寻找新的雪藻带。")
		"7-5":
			var he := int(b.get("helio_eaten", 0)) - int(a.get("helio_eaten", 0))
			if big.call(he):
				said.call("helio", he + 1, "大量细胞被太阳虫抓住了", "太阳虫的轴足最长可以伸出 120 µm，不过无法穿过冰墙。可以让细胞沿着冰墙移动，或者等太阳虫收回轴足、准备移动位置的时候再通过。", "eaten")
	return out


# For the report: the run's deaths by cause, biggest first: [[name, n], ...].
static func causes(sim: SimCore, sp: int) -> Array:
	var s: Dictionary = sim.get_stats().species[sp]
	var names := {starved = "饿死", eaten = "被吃掉", aged = "老死", temp = "冻死或热死", acid = "被酸死", o2 = "中毒", phage = "被病毒撑破"}
	var out := []
	for k in names:
		if int(s.get(k, 0)) > 0:
			out.append([names[k], int(s[k]), k])
	out.sort_custom(func(x: Array, y: Array) -> bool: return int(x[1]) > int(y[1]))
	return out
