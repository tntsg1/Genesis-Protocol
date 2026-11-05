extends SceneTree
# Probe for 4-1: does spreading out decide the phage level? Start deck, then
# the same deck with "crowd >= N -> away from peers" on top, for a few N.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("4-1").duplicate(true)
	for key in ["rain", "life", "yield", "burst", "stick", "diffuse"]:
		var v := OS.get_environment("P_" + key.to_upper())
		if v != "":
			l.phage[key] = float(v) if key != "yield" else int(v)
	var R := Rules
	var genes := [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0]
	var base := [
		{c1 = R.C_ENERGY_ABOVE, t1 = 1.0, c2 = R.C_NONE, t2 = 0.0, act = R.A_DIVIDE},
		{c1 = R.C_SEE_ALGAE, t1 = 0.0, c2 = R.C_NONE, t2 = 0.0, act = R.A_SEEK_ALGAE},
		{c1 = R.C_NONE, t1 = 0.0, c2 = R.C_NONE, t2 = 0.0, act = R.A_REST},
	]
	var plans := [["不散开", base]]
	for n: float in [2.0, 3.0, 5.0]:
		var d: Array = base.duplicate(true)
		d.insert(1, {c1 = R.C_CROWD, t1 = n, c2 = R.C_NONE, t2 = 0.0, act = R.A_DISPERSE})
		plans.append(["同伴 ≥ %d 远离" % int(n), d])
	var seeds := int(OS.get_environment("P_SEEDS")) if OS.get_environment("P_SEEDS") != "" else 8
	# (Fresh seeds each run: a fixed set can flatter a level. 4-5 read 90% on one, 67% on new ones.)
	var seed0 := randi() % 900000
	var jobs := []
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(genes, (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, false, [], "4-1")
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
		var w := 0
		var ext := 0
		var pk := []
		for s in seeds:
			var ev: LevelEval = res[k]
			k += 1
			al.append(ev.alive)
			ly.append(ev.lysed)
			pk.append(ev.peak)
			w += 1 if ev.stars()[0] else 0
			ext += 1 if ev.extinct else 0
		al.sort()
		ly.sort()
		pk.sort()
		print("%s  胜 %d/%d  灭绝 %d  末尾中位 %d（%d–%d）  峰值 %d  裂解中位 %d（%d–%d）" % [pl[0], w, seeds, ext, al[seeds / 2], al[0], al[-1], pk[seeds / 2], ly[seeds / 2], ly[0], ly[-1]])
	quit()
