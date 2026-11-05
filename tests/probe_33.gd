extends SceneTree
# Probe (temporary): level 13 (3-3). The guided plan (crowd >= 4 -> secrete,
# second card) against no secreting, over a few gene sets and seeds.

func _initialize() -> void:
	var l := Levels.by_id("3-3")
	var R := Rules
	var base: Array = R.default_deck(0)
	var guided := base.duplicate(true)
	guided.insert(1, R.card(R.C_CROWD, 4.0, R.C_NONE, 0.0, R.A_SECRETE))
	var g3 := base.duplicate(true)
	g3.insert(1, R.card(R.C_CROWD, 3.0, R.C_NONE, 0.0, R.A_SECRETE))
	var always := base.duplicate(true)
	always.insert(1, R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_SECRETE))
	var decks := {none = base, guided4 = guided, guided3 = g3, always = always}
	print("base deck: ", base.map(func(c: Dictionary) -> String: return R.card_text(c)))
	# speed, vision, armor, attack, fertility, metabolism, neural, temp_tol
	var sets := [[3.0, 3.0, 3.0, 1.0, 3.0, 3.0, 4.0, 3.0], [2.0, 3.0, 1.0, 1.0, 4.0, 4.0, 4.0, 3.0], [1.0, 2.0, 1.0, 1.0, 5.0, 5.0, 4.0, 3.0], [3.0, 2.0, 1.0, 1.0, 4.0, 5.0, 4.0, 3.0]]
	var jobs := []
	for g in sets:
		for dn: String in decks:
			for s in 3:
				jobs.append([g, dn, s])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		var j: Array = jobs[k]
		var d := LevelEval.design_from_genes(j[0], decks[j[1]], Color(0.4, 0.8, 0.9), 12.0, true, [], "3-3")
		var ev := LevelEval.simulate(l, d, 1000 + j[2] * 7919)
		res[k] = "%d" % ev.alive
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for g in sets:
		var line := "genes %s:" % str(g)
		for dn: String in decks:
			line += "  [%s] %s" % [dn, str(res.slice(k, k + 3))]
			k += 3
		print(line)
	print("goal ", l.goal.n, " / challenge ", l.challenge.n)
	quit()
