extends SceneTree
# Probe for 4-5 in real conditions (mutation on, the opening deck): does a
# virophage decide the level, and do both of its forms work? Env P_YIELD,
# P_BURST, P_LIFE, P_SWALLOW, P_START, P_N (cells), P_MAX (giants), P_SHOT.
func _env(key: String, d: float) -> float:
	return float(OS.get_environment(key)) if OS.get_environment(key) != "" else d


func _initialize() -> void:
	var l: Dictionary = Levels.by_id("4-5").duplicate(true)
	l.giant["yield"] = int(_env("P_YIELD", float(l.giant["yield"])))
	l.giant.burst = _env("P_BURST", l.giant.burst)
	l.giant.life = _env("P_LIFE", l.giant.life)
	l.giant.swallow = _env("P_SWALLOW", l.giant.swallow)
	l.giant.start = int(_env("P_START", l.giant.start))
	l.goal.n = int(_env("P_N", l.goal.n))
	l.goal.giant_max = int(_env("P_MAX", l.goal.giant_max))
	for e: Dictionary in l.get("events", []):
		e.n = int(float(e.n) * _env("P_WAVE", 1.0))
		e.at = float(e.at) * _env("P_WHEN", 1.0)
	var shot := int(_env("P_SHOT", 80.0))
	var d0: Dictionary = l.start_design
	var mid := {burst = 3, speed = 3, shell = 3, stick = 3}
	var fast := {burst = 2, speed = 5, shell = 2, stick = 3}
	var lf := {burst = 3, speed = 5, shell = 3, stick = 1}
	var ls := {burst = 1, speed = 5, shell = 3, stick = 3}
	var long := {burst = 2, speed = 2, shell = 5, stick = 3}
	var three := [["drop_giants", 30.0], ["drop_giants", 60.0], ["drop_giants", 90.0]]
	var six := three + [["drop_giants", 120.0], ["drop_giants", 150.0], ["drop_giants", 180.0]]
	var late := [["drop_giants", 150.0], ["drop_giants", 170.0], ["drop_giants", 190.0]]
	var plans := [["不投放", mid, []],
		["裂解 均衡 ×3", mid, three],
		["裂解 快 ×3", ls, three],
		["裂解 快 ×6", ls, six],
		["裂解 快多 ×6", lf, six],
		["裂解 长寿 ×6", long, six],
		["裂解 快 晚×3", ls, late],
		["潜伏 均衡 ×1", mid.merged({temperate = true}), [["drop_own", 10.0]]],
		["潜伏 快 ×1", fast.merged({temperate = true}), [["drop_own", 10.0]]],
		["潜伏 快 中×1", fast.merged({temperate = true}), [["drop_own", 40.0]]],
		["潜伏 快 晚×2", fast.merged({temperate = true}), [["drop_own", 100.0], ["drop_own", 120.0]]],
		["潜伏 重爆发 ×1", {burst = 4, speed = 5, shell = 1, stick = 2, temperate = true}, [["drop_own", 10.0]]],
		["潜伏 中速4 ×1", {burst = 3, speed = 4, shell = 2, stick = 3, temperate = true}, [["drop_own", 10.0]]]]
	if OS.get_environment("P_SET") == "2":
		var heavy := {burst = 4, speed = 5, shell = 1, stick = 2, temperate = true}
		var top := {burst = 5, speed = 5, shell = 1, stick = 1, temperate = true}
		plans = [["潜伏 重爆发 ×3", heavy, [["drop_own", 10.0], ["drop_own", 30.0], ["drop_own", 60.0]]],
			["潜伏 满爆发 ×1", top, [["drop_own", 10.0]]],
			["潜伏 满爆发 ×4", top, [["drop_own", 10.0], ["drop_own", 25.0], ["drop_own", 45.0], ["drop_own", 70.0]]],
			["裂解 满爆发 ×9", {burst = 5, speed = 5, shell = 1, stick = 1}, three + six + [["drop_giants", 200.0], ["drop_giants", 220.0], ["drop_giants", 240.0]]]]
	if OS.get_environment("P_SET") == "4":
		plans = [["不投放", mid, []],
			["裂解 均衡 ×3", mid, three],
			["裂解 快多 ×3", lf, three],
			["裂解 快多 ×6", lf, six],
			["潜伏 均衡 第10秒", mid.merged({temperate = true}), [["drop_own", 10.0]]],
			["潜伏 快 第10秒", fast.merged({temperate = true}), [["drop_own", 10.0]]],
			["潜伏 快 第10+30秒", fast.merged({temperate = true}), [["drop_own", 10.0], ["drop_own", 30.0]]],
			["潜伏 中速4 第10秒", {burst = 3, speed = 4, shell = 2, stick = 3, temperate = true}, [["drop_own", 10.0]]],
			["潜伏 快 第40秒", fast.merged({temperate = true}), [["drop_own", 40.0]]]]
	if OS.get_environment("P_SET") == "5":
		var w3 := [["drop_giants", 25.0], ["drop_giants", 40.0], ["drop_wave", 50.0, 0], ["drop_giants", 75.0], ["drop_wave", 100.0, 1], ["drop_giants", 125.0], ["drop_wave", 145.0, 2], ["drop_giants", 170.0]]
		var w2 := [["drop_giants", 25.0], ["drop_giants", 45.0], ["drop_wave", 50.0, 0], ["drop_wave", 100.0, 1], ["drop_wave", 145.0, 2]]
		plans = [["不投放", mid, []],
			["裂解 快多 蹲点×8", lf, w3],
			["裂解 均衡 蹲点×8", mid, w3],
			["裂解 快多 蹲点×5", lf, w2],
			["裂解 快多 无蹲点×10", lf, [["drop_giants", 30.0], ["drop_giants", 51.0], ["drop_giants", 72.0], ["drop_giants", 93.0], ["drop_giants", 114.0], ["drop_giants", 135.0], ["drop_giants", 156.0], ["drop_giants", 177.0], ["drop_giants", 198.0], ["drop_giants", 219.0]]],
			["潜伏 快 第10秒", fast.merged({temperate = true}), [["drop_own", 10.0]]],
			["潜伏 快 第10+30秒", fast.merged({temperate = true}), [["drop_own", 10.0], ["drop_own", 30.0]]],
			["潜伏 均衡 第10秒", mid.merged({temperate = true}), [["drop_own", 10.0]]],
			["潜伏 快 第40秒", fast.merged({temperate = true}), [["drop_own", 40.0]]]]
	if OS.get_environment("P_SET") == "6":
		var one := [["drop_own", 10.0]]
		var two := [["drop_own", 10.0], ["drop_own", 30.0]]
		plans = [["爆4 速5 壳1 附2 ×1", {burst = 4, speed = 5, shell = 1, stick = 2, temperate = true}, one],
			["爆4 速5 壳1 附2 ×2", {burst = 4, speed = 5, shell = 1, stick = 2, temperate = true}, two],
			["爆3 速5 壳1 附3 ×1", {burst = 3, speed = 5, shell = 1, stick = 3, temperate = true}, one],
			["爆3 速5 壳1 附3 ×2", {burst = 3, speed = 5, shell = 1, stick = 3, temperate = true}, two],
			["爆2 速5 壳2 附3 ×2", fast.merged({temperate = true}), two],
			["爆5 速5 壳1 附1 ×2", {burst = 5, speed = 5, shell = 1, stick = 1, temperate = true}, two]]
	if OS.get_environment("P_SET") == "7":
		plans = [["爆4 速5 壳1 附2 两次", {burst = 4, speed = 5, shell = 1, stick = 2, temperate = true}, [["drop_own", 10.0], ["drop_own", 30.0]]]]
	if OS.get_environment("P_SET") == "3":
		var hunt := [["drop_own", 10.0]]
		for at in range(120, 270, 20):
			hunt.append(["drop_giants", float(at)])
		var ten := []
		for at in range(30, 240, 21):
			ten.append(["drop_giants", float(at)])
		var hunt2 := [["drop_own", 10.0], ["drop_own", 30.0]]
		for at in range(195, 285, 15):
			hunt2.append(["drop_giants", float(at)])
		plans = [["裂解 快多 ×10", lf, ten],
			["裂解 重爆发 ×10", {burst = 4, speed = 5, shell = 1, stick = 2}, ten],
			["潜伏 快 两接种 + 末尾追杀", fast.merged({temperate = true}), hunt2],
			["潜伏 快 + 追杀", fast.merged({temperate = true}), hunt],
			["潜伏 重爆发 + 追杀", {burst = 4, speed = 5, shell = 1, stick = 2, temperate = true}, hunt],
			["潜伏 附着高 + 追杀", {burst = 1, speed = 5, shell = 2, stick = 4, temperate = true}, hunt]]
	var seeds := int(_env("P_SEEDS", 8.0))
	# (Fresh seeds each run: the fixed 9100 set read 27/30 at the 200 line where
	# new ones read 20/30, and real play 6/10.)
	var seed0 := randi() % 900000
	var jobs := []
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, [], "4-5")
		d.virus = pl[1]
		d.plan = []
		for s: Array in pl[2]:
			d.plan.append({at = s[1], kind = s[0], n = shot, wave = s[2] if s.size() > 2 else 0})
		for k in seeds:
			jobs.append([l.duplicate(true), d.duplicate(true), int(_env("P_BASE", float(seed0))) + k * 4421])
	if OS.get_environment("P_SET") == "2":
		var eat := (d0.deck as Array).duplicate(true)
		eat[1].t1 = 0.5
		var spread := (d0.deck as Array).duplicate(true)
		spread.insert(1, {c1 = Rules.C_CROWD, t1 = 2.0, c2 = Rules.C_NONE, t2 = 0.0, act = Rules.A_DISPERSE})
		var dg := [[d0.genes, spread, ["crispr"], "只靠 记忆+散开"], [d0.genes, eat, [], "只靠 半饱才吃"], [[2.0, 1.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0], eat, ["crispr"], "只靠 瞎+半饱+记忆"], [d0.genes, spread, [], "只靠 散开"]]
		for o: Array in dg:
			var d := LevelEval.design_from_genes(o[0], (o[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, o[2], "4-5")
			d.virus = mid
			d.plan = []
			plans.append([o[3], mid, []])
			for k in seeds:
				jobs.append([l.duplicate(true), d.duplicate(true), 9100 + k * 4421])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for pl: Array in plans:
		var al := []
		var gi := []
		var pk := []
		var w := 0
		var z := 0
		var lys := 0
		var car := 0
		var tiers := [150, 200, 250, 300, 350, 400]
		var tier := {}
		for s in seeds:
			var ev: LevelEval = res[k]
			k += 1
			al.append(ev.alive)
			gi.append(ev.giants)
			pk.append(ev.giant_peak)
			w += 1 if ev.stars()[0] else 0
			for m in tiers:
				tier[m] = int(tier.get(m, 0)) + (1 if ev.giants <= m and ev.alive >= int(l.goal.n) else 0)
			z += 1 if ev.giants_zero >= 0.0 else 0
			lys += ev.lysed
			car += int(ev.giant_stats.get("carriers", 0))
		al.sort()
		gi.sort()
		pk.sort()
		if OS.get_environment("P_SET") == "7":
			print("全部结果 ", gi)
		print("%s  胜 %d/%d  清零 %d  你 %d（%d–%d）  巨毒囊 %d（%d–%d）峰 %d  撑破 %d  带潜伏 %d  线 %s" % [pl[0], w, seeds, z, al[seeds / 2], al[0], al[-1], gi[seeds / 2], gi[0], gi[-1], pk[seeds / 2], lys / seeds, car / seeds, str(tier)])
	quit()
