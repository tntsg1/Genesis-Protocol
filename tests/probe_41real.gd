extends SceneTree
# Why 4-1 keeps being lost: the real opening deck and default genes, mutation
# on as the designer starts it, each card plan; plus the end state of the
# decks (did the away card survive?). Env P_* as in probe_41.gd.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("4-1").duplicate(true)
	for key in ["rain", "life", "yield", "burst", "stick", "diffuse"]:
		var v := OS.get_environment("P_" + key.to_upper())
		if v != "":
			l.phage[key] = float(v) if key != "yield" else int(v)
	if OS.get_environment("P_LYSED") != "":
		l.goal.lysed = int(OS.get_environment("P_LYSED"))
	var R := Rules
	var genes := [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0]
	var base: Array = [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE), R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
	var plans := [["开局原样", base]]
	for n: float in [2.0, 3.0]:
		var d: Array = base.duplicate(true)
		d.insert(1, R.card(R.C_CROWD, n, R.C_NONE, 0.0, R.A_DISPERSE))
		plans.append(["第2张 同伴≥%d" % int(n), d])
	# Common player placements: at the top, at the bottom.
	var top: Array = base.duplicate(true)
	top.insert(0, R.card(R.C_CROWD, 3.0, R.C_NONE, 0.0, R.A_DISPERSE))
	plans.append(["第1张 同伴≥3", top])
	var bottom: Array = base.duplicate(true)
	bottom.append(R.card(R.C_CROWD, 3.0, R.C_NONE, 0.0, R.A_DISPERSE))
	plans.append(["最后 同伴≥3", bottom])
	var seeds := 8
	var jobs := []
	for mut: bool in [true, false]:
		for pl: Array in plans:
			var d := LevelEval.design_from_genes(genes, (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, mut, [], "4-1")
			for k in seeds:
				jobs.append([l.duplicate(true), d.duplicate(true), 5000 + k * 6113])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for mut: bool in [true, false]:
		print("== 自然变异 ", "开" if mut else "关")
		for pl: Array in plans:
			var al := []
			var ly := []
			var w := 0
			var sa := 0
			var ch := 0
			for s in seeds:
				var ev: LevelEval = res[k]
				k += 1
				al.append(ev.alive)
				ly.append(ev.lysed)
				w += 1 if ev.stars()[0] else 0
				ch += 1 if ev.stars()[1] else 0
				sa += 1 if ev.alive >= int(l.goal.n) else 0
			al.sort()
			ly.sort()
			print("%s  胜 %d/%d 附加 %d  种群达标 %d  末尾中位 %d（%d–%d）  撑破中位 %d（%d–%d）" % [pl[0], w, seeds, ch, sa, al[seeds / 2], al[0], al[-1], ly[seeds / 2], ly[0], ly[-1]])
	quit()
