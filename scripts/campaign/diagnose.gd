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
	return {t = t, alive = ev.alive, births = int(s.births), starved = int(s.starved), eaten = int(s.eaten),
		aged = int(s.aged), temp = int(s.temp), acid = int(s.acid), o2 = int(s.o2), phage = int(s.phage)}


# What went wrong between `a` and `b` (two snapshots), as [{id, title, text}]
# in order of weight; `l` the level, `sim`/`ev` for the level's own checks,
# `resp` how the player's species breathes.
static func read(l: Dictionary, sim: SimCore, ev: LevelEval, a: Dictionary, b: Dictionary, resp := -1) -> Array:
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
	# The level's own problems (chapter 8).
	out.append_array(_level_reads(l, sim, ev))
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
