extends SceneTree
# Probe for 5-1 in real conditions (mutation on, fresh seeds): does gathering
# decide the level, and does its threshold matter? Env P_SEEDS, P_LOSS, P_POWER
# (home light), P_N (goal), P_SPEED.
func _env(key: String, d: float) -> float:
	return float(OS.get_environment(key)) if OS.get_environment(key) != "" else d


func _initialize() -> void:
	var l: Dictionary = Levels.by_id("5-1").duplicate(true)
	l.slug.loss = _env("P_LOSS", l.slug.loss)
	l.slug.speed = _env("P_SPEED", l.slug.speed)
	l.slug.gather = _env("P_GATHER", l.slug.gather)
	l.world.lights[0][2] = _env("P_POWER", l.world.lights[0][2])
	l.goal.n = int(_env("P_N", l.goal.n))
	var d0: Dictionary = l.start_design
	var deck: Array = d0.deck
	var at := func(n: float, hunger: float) -> Array:
		var dk := deck.duplicate(true)
		dk[1] = {c1 = Rules.C_ENERGY_BELOW, t1 = hunger, c2 = Rules.C_CROWD, t2 = n, act = Rules.A_AGGREGATE}
		return dk
	var no_signal: Array = at.call(5.0, 0.4)
	no_signal.remove_at(3)
	no_signal.remove_at(2)
	var fed: Array = at.call(5.0, 0.4)
	fed[1] = {c1 = Rules.C_CROWD, t1 = 5.0, c2 = Rules.C_NONE, t2 = 0.0, act = Rules.A_AGGREGATE}
	var plans := [["开局不改", deck, []],
		["引导：40% ≥5", at.call(5.0, 0.4), []],
		["40% ≥3", at.call(3.0, 0.4), []],
		["40% ≥8", at.call(8.0, 0.4), []],
		["40% ≥12", at.call(12.0, 0.4), []],
		["50% ≥5", at.call(5.0, 0.5), []],
		["60% ≥5", at.call(5.0, 0.6), []],
		["不饿也聚合", fed, []],
		["不放信号", no_signal, []],
		["省感知（低预算）", at.call(5.0, 0.4), [2.0, 1.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0]],
		["省繁殖（低预算）", at.call(5.0, 0.4), [2.0, 2.0, 1.0, 1.0, 2.0, 3.0, 4.0, 3.0]],
		["省速度（低预算）", at.call(5.0, 0.4), [1.0, 2.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0]]]
	if OS.get_environment("P_SET") == "heat":
		# As a player would: one warm spot on the home side of the gap, then
		# one in the far side of it, once a slug is on its way.
		var seam := [{at = 75.0, kind = "heat_at", pos = Vector2(800, 890)}, {at = 115.0, kind = "heat_at", pos = Vector2(1400, 890)}]
		var near := [{at = 75.0, kind = "heat_at", pos = Vector2(760, 1100)}]
		plans = [["不用升温", at.call(5.0, 0.4), []],
			["升温引向窄缝", at.call(5.0, 0.4), [], seam],
			["升温放在正前方", at.call(5.0, 0.4), [], near]]
	var seeds := int(_env("P_SEEDS", 10.0))
	var seed0 := randi() % 900000
	var jobs := []
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(pl[2] if not pl[2].is_empty() else d0.genes, (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, d0.organs, "5-1")
		if pl.size() > 3:
			d.plan = pl[3]
		for k in seeds:
			jobs.append([l.duplicate(true), d.duplicate(true), seed0 + k * 6113])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for pl: Array in plans:
		var z := []
		var al := []
		var w := 0
		var ch := 0
		var formed := 0
		var lost := 0
		var spored := 0
		var ex := 0
		var pk := 0
		for s in seeds:
			var ev: LevelEval = res[k]
			k += 1
			z.append(ev.zone_now)
			al.append(ev.alive)
			var st: Array = ev.stars()
			w += 1 if st[0] else 0
			ch += 1 if st[1] else 0
			ex += 1 if ev.extinct else 0
			formed += int(ev.slug_stats.get("formed", 0))
			lost += int(ev.slug_stats.get("lost", 0))
			spored += int(ev.slug_stats.get("spored", 0))
			pk += ev.peak
		z.sort()
		al.sort()
		print("%s  胜 %d/%d  挑战 %d  灭绝 %d  对岸 %d（%d–%d）  总数 %d  聚合体 %.1f  烧掉 %d  孢子 %d  峰 %d" % [pl[0], w, seeds, ch, ex, z[seeds / 2], z[0], z[-1], al[seeds / 2], float(formed) / seeds, lost / seeds, spored / seeds, pk / seeds])
	quit()
