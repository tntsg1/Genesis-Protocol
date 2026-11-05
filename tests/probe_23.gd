extends SceneTree
# Probe: level 8 (2-3). Prey fixed; predator decks: ambush only (the level's
# start) / with a sleep cycle / no ambush. Coexistence at 6 min.
func _initialize() -> void:
	var l := Levels.by_id("2-3")
	var R := Rules
	var base: Array = (l.species[1].deck as Array).duplicate(true)
	var sleepy := base.duplicate(true)
	var nap := R.card(R.C_SEE_PREY, 0.0, R.C_STATE_TIME, 15.0, R.A_TO_SLEEP)
	nap.n1 = true
	sleepy.insert(2, nap)
	var wake := R.card(R.C_STATE_TIME, 30.0, R.C_NONE, 0.0, R.A_TO_FORAGE)
	wake.st = R.S_SLEEP
	sleepy.append(wake)
	var roam := base.duplicate(true)
	roam.remove_at(2)
	var decks := {埋伏 = base, 休眠 = sleepy, 游荡 = roam}
	var prey_sets := [[2.0, 2.0, 1.0, 1.0, 4.0, 3.0, 3.0, 2.5], [1.0, 2.0, 1.0, 1.0, 4.0, 4.0, 3.0, 2.5]]
	var pred_genes := [3.0, 2.0, 1.0, 3.0, 2.0, 3.0, 3.0, 2.5]
	var jobs := []
	for pg in prey_sets:
		for dn: String in decks:
			for s in 5:
				jobs.append([pg, dn, s])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		var j: Array = jobs[k]
		var d := LevelEval.design_from_genes(j[0], R.default_deck(0), Color(0.4, 0.8, 0.9), 12.0, true, [], "2-3")
		var pb := LevelEval.design_from_genes(pred_genes, (decks[j[1]] as Array).duplicate(true), Color(0.9, 0.4, 0.5), 12.0, true, ["cnido"], "2-3")
		d.extra = [pb.params]
		var ev := LevelEval.simulate(l, d, 1000 + j[2] * 7919)
		var st: Dictionary = ev._sim.get_stats().species[ev.sp2]
		res[k] = "%s%d/%d 生%d饿%d老%d峰%d" % ["胜" if ev.stars()[0] else "", ev.alive, ev.alive2, st.births, st.starved, st.aged, ev.peak2]
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for pg in prey_sets:
		var line := "prey %s:" % str(pg)
		for dn: String in decks:
			line += "  [%s] %s" % [dn, str(res.slice(k, k + 5))]
			k += 5
		print(line)
	quit()
