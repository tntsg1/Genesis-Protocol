extends SceneTree
# Probe for level 3-3 as the game sets it up: the designer's start deck and
# genes, the guided card in second place; each run on its own copies.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("3-3")
	var R := Rules
	var start: Array = [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE), R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
	var ins := func(c: Dictionary) -> Array:
		var d: Array = start.duplicate(true)
		d.insert(1, c)
		return d
	var plans := [["不分泌", start], ["引导：同伴≥4→分泌", ins.call(R.card(R.C_CROWD, 4.0, R.C_NONE, 0.0, R.A_SECRETE))],
		["同伴≥3→分泌", ins.call(R.card(R.C_CROWD, 3.0, R.C_NONE, 0.0, R.A_SECRETE))], ["一直分泌", ins.call(R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_SECRETE))]]
	# The designer's start genes for this level, then a few others.
	var sets := [["设计器默认 速2感2壳1繁3代3", [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0]], ["速3繁4 代3", [3.0, 2.0, 1.0, 1.0, 4.0, 3.0, 4.0, 3.0]], ["速2繁5代4", [2.0, 2.0, 1.0, 1.0, 5.0, 4.0, 4.0, 3.0]]]
	var seeds := 8
	var jobs := []
	for gs: Array in sets:
		for pl: Array in plans:
			var d := LevelEval.design_from_genes(gs[1], (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, [], "3-3")
			for k in seeds:
				jobs.append([l.duplicate(true), d.duplicate(true), 1000 + k * 7919])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for gs: Array in sets:
		print("== ", gs[0], " used ", LevelEval.design_from_genes(gs[1], [], Color.WHITE, 12.0, true, [], "3-3").used)
		for pl: Array in plans:
			var al := []
			var w := 0
			for s in seeds:
				var ev: LevelEval = res[k]
				k += 1
				al.append(ev.alive)
				w += 1 if ev.stars()[0] else 0
			al.sort()
			print("  %s  胜 %d/%d  中位 %d（%d–%d）" % [pl[0], w, seeds, al[seeds / 2], al[0], al[-1]])
	quit()
