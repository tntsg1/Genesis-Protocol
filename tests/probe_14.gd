extends SceneTree
# Probe: level 4, does moving "temp bad -> seek comfort" to the top matter
# (with and without warm spots)? Prints mean alive / cold share per variant.

func _initialize() -> void:
	var l := Levels.by_id("1-4")
	var gene_sets := [[2, 2, 1, 1, 2, 3, 3, 2.5], [1, 2, 1, 1, 3, 4, 3, 2.5], [2, 2, 1, 1, 3, 3, 3, 4.0], [1, 2, 1, 1, 2, 5, 3, 3.0], [3, 2, 1, 1, 4, 2, 3, 2.5]]
	var heat := []
	for t in [122.0, 140.0, 160.0, 185.0, 210.0, 235.0, 260.0, 285.0, 310.0, 335.0]:
		heat.append({at = t, kind = "heat"})
	var variants := []
	for pos in ["底", "无温卡"]:
		for h in [false, true]:
			variants.append([pos, h])
	var jobs := []
	for g in gene_sets:
		for v in variants:
			for s in 4:
				jobs.append([g, v, s])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		var j: Array = jobs[k]
		var deck := Rules.default_deck(0)
		var card := Rules.card(Rules.C_TEMP_BAD, 0.0, Rules.C_NONE, 0.0, Rules.A_SEEK_COMFORT)
		match j[1][0]:
			"底": deck.append(card)
			"无温卡": pass
			"休息上": deck.insert(3, card)
			"顶": deck.insert(0, card)
			"休息在分裂上":
				deck.append(card)
				var r: Dictionary = deck.pop_at(3)
				deck.insert(1, r)
		var d := LevelEval.design_from_genes(j[0], deck, Color(0.4, 0.8, 0.9), 12.0, true)
		d.plan = heat.duplicate() if j[1][1] else []
		var ev := LevelEval.simulate(l, d, 1000 + j[2] * 7919)
		res[k] = [ev.alive, ev.cold_share, ev.stars()]
	var task := WorkerThreadPool.add_group_task(job, jobs.size(), -1, true)
	WorkerThreadPool.wait_for_group_task_completion(task)
	var k := 0
	for g in gene_sets:
		var line := "genes %s:" % str(g)
		for v in variants:
			var a := []
			var wins := 0
			for s in 4:
				a.append(res[k][0])
				if res[k][0] >= 85:
					wins += 1
				k += 1
			line += "  [%s%s] %s" % [v[0], "+热" if v[1] else "", str(a)]
		print(line)
	quit()
