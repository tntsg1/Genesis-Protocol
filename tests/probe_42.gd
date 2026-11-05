extends SceneTree
# Probe for 4-2 in real conditions (mutation on, the real opening deck): does
# "the ones with the memory need not hide" decide the level? Env P_CRISPR,
# P_N (storm), P_RAIN, P_GOAL.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("4-2").duplicate(true)
	if OS.get_environment("P_N") != "":
		l.events[0].n = int(OS.get_environment("P_N"))
	if OS.get_environment("P_RAIN") != "":
		l.phage.rain = float(OS.get_environment("P_RAIN"))
	if OS.get_environment("P_GOAL") != "":
		l.goal.n = int(OS.get_environment("P_GOAL"))
	var crispr := float(OS.get_environment("P_CRISPR")) if OS.get_environment("P_CRISPR") != "" else 0.06
	var R := Rules
	var genes := [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0]
	var base: Array = [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE), R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
	var all: Array = base.duplicate(true)
	all.insert(1, R.card(R.C_CROWD, 2.0, R.C_NONE, 0.0, R.A_DISPERSE))
	var only: Array = base.duplicate(true)
	var c: Dictionary = R.card(R.C_CROWD, 2.0, R.C_IMMUNE, 0.0, R.A_DISPERSE)
	c.n2 = true
	only.insert(1, c)
	var breed: Array = only.duplicate(true)
	breed.insert(1, R.card(R.C_IMMUNE, 0.0, R.C_NONE, 0.0, R.A_TO_BREED))
	var plans := [["没器官 全员散开", all, []], ["有器官 不散开", base, ["crispr"]], ["有器官 全员散开", all, ["crispr"]], ["有器官 没记忆的散开", only, ["crispr"]], ["有器官 没记忆散开+有记忆繁殖期", breed, ["crispr"]]]
	var seeds := int(OS.get_environment("P_SEEDS")) if OS.get_environment("P_SEEDS") != "" else 8
	# (Fresh seeds each run: a fixed set can flatter a level. 4-5 read 90% on one, 67% on new ones.)
	var seed0 := randi() % 900000
	var jobs := []
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(genes, (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, pl[2], "4-2")
		if not (pl[2] as Array).is_empty():
			d.params.crispr = crispr
		for k in seeds:
			jobs.append([l.duplicate(true), d.duplicate(true), seed0 + k * 7919])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for pl: Array in plans:
		var al := []
		var ly := []
		var im := []
		var w := 0
		var ch := 0
		var pre := []
		for s in seeds:
			var ev: LevelEval = res[k]
			k += 1
			al.append(ev.alive)
			ly.append(ev.lysed)
			im.append(ev.immune)
			w += 1 if ev.stars()[0] else 0
			ch += 1 if ev.stars()[1] else 0
			for p: Array in ev.curve:
				if float(p[0]) >= 238.0:
					pre.append(int(p[1]))
					break
		al.sort()
		ly.sort()
		im.sort()
		pre.sort()
		print("%s  胜 %d/%d 附加 %d  爆发前中位 %d  末尾中位 %d（%d–%d）  有记忆中位 %d  撑破中位 %d" % [pl[0], w, seeds, ch, pre[pre.size() / 2] if not pre.is_empty() else 0, al[seeds / 2], al[0], al[-1], im[seeds / 2], ly[seeds / 2]])
	quit()
