extends SceneTree
# Probe: level 8 (2-3) from the prey's side: does an alert state (hunter
# near -> alert: faster, sees further; calm 10 s -> forage) keep the prey
# from being eaten up by strong hunters? Predator: ambush deck.
func _initialize() -> void:
	var l := Levels.by_id("2-3")
	var R := Rules
	var pred: Array = (l.species[1].deck as Array).duplicate(true)
	var plain := R.default_deck(0)
	var alert := R.default_deck(0)
	alert.insert(1, R.card(R.C_PREDATOR_NEAR, 150.0, R.C_NONE, 0.0, R.A_TO_ALERT))
	for c: Dictionary in R.default_deck(0):
		var a := c.duplicate()
		a.st = R.S_ALERT
		if a.act == R.A_FLEE:
			a.t1 = 100.0
		alert.append(a)
	var calm := R.card(R.C_STATE_TIME, 10.0, R.C_PREDATOR_NEAR, 150.0, R.A_TO_FORAGE)
	calm.n2 = true
	calm.st = R.S_ALERT
	alert.insert(alert.size() - 4, calm)
	var preys := {原样 = plain, 警戒 = alert}
	var pred_sets := [[3.0, 2.0, 1.0, 3.0, 2.0, 3.0, 3.0, 2.5], [4.0, 3.0, 1.0, 4.0, 3.0, 2.0, 3.0, 2.5]]
	var prey_genes := [2.0, 2.0, 1.0, 1.0, 4.0, 3.0, 3.0, 2.5]
	var jobs := []
	for pg in pred_sets:
		for dn: String in preys:
			for s in 6:
				jobs.append([pg, dn, s])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		var j: Array = jobs[k]
		var d := LevelEval.design_from_genes(prey_genes, (preys[j[1]] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, [], "2-4")
		var pb := LevelEval.design_from_genes(j[0], pred.duplicate(true), Color(0.9, 0.4, 0.5), 12.0, true, ["cnido"], "2-4")
		d.extra = [pb.params]
		var ev := LevelEval.simulate(l, d, 1000 + j[2] * 7919)
		res[k] = "%s%d/%d 低%d" % ["胜" if ev.stars()[0] else "", ev.alive, ev.alive2, ev.min_after]
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for pg in pred_sets:
		var line := "pred %s:" % str(pg)
		for dn: String in preys:
			line += "  [%s] %s" % [dn, str(res.slice(k, k + 6))]
			k += 6
		print(line)
	quit()
