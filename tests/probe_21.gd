extends SceneTree
# Probe: level 6 (2-1). Hunt cards: any prey / small prey only / near prey.
# Prints the predators alive at the end and the first kill, per deck.

func _initialize() -> void:
	var l := Levels.by_id("2-1")
	var R := Rules
	var D := func(c2: int, t2: float, ambush: bool) -> Array:
		var d := [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE),
			R.card(R.C_ENERGY_BELOW, 1.0, c2, t2, R.A_HUNT)]
		d.append(R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_REST) if ambush else R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST))
		return d
	var decks := {全追游荡 = D.call(R.C_SEE_PREY, 0.0, false), 全追埋伏 = D.call(R.C_SEE_PREY, 0.0, true),
		近追埋伏 = D.call(R.C_PREY_NEAR, 90.0, true), 挑小埋伏 = D.call(R.C_PREY_SMALL, 0.7, true)}
	var sets := [[3.0, 2.0, 1.0, 3.0, 2.0, 3.0, 3.0, 2.5], [4.0, 2.0, 1.0, 3.0, 2.0, 3.0, 3.0, 2.5], [3.0, 3.0, 1.0, 4.0, 2.0, 2.0, 3.0, 2.5], [5.0, 1.0, 1.0, 2.0, 3.0, 3.0, 3.0, 2.5], [2.0, 2.0, 1.0, 3.0, 3.0, 4.0, 3.0, 2.5]]
	var jobs := []
	for g in sets:
		for dn: String in decks:
			for s in 4:
				jobs.append([g, dn, s])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		var j: Array = jobs[k]
		var d := LevelEval.design_from_genes(j[0], decks[j[1]], Color(0.9, 0.4, 0.5), 12.0, true, ["cnido"], "2-1")
		var ev := LevelEval.simulate(l, d, 1000 + j[2] * 7919)
		res[k] = "%d/%d" % [ev.alive, ev.peak]
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for g in sets:
		var line := "genes %s:" % str(g)
		for dn: String in decks:
			line += "  [%s] %s" % [dn, str(res.slice(k, k + 4))]
			k += 4
		print(line)
	quit()
