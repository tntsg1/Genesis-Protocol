extends SceneTree
# Probe for level 3-1 (alarm calls): plans x seeds in parallel.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("3-1")
	var R := Rules
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 8
	var smell := float(OS.get_environment("SMELL")) if OS.get_environment("SMELL") != "" else 0.1
	var calm := float(OS.get_environment("CALM")) if OS.get_environment("CALM") != "" else 10.0
	var st := func(c: Dictionary, s: int) -> Dictionary:
		c.st = s
		return c
	var plain := Rules.default_deck(0)
	var alert: Array = Rules.default_deck(0)
	alert[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_TO_ALERT)
	alert += [st.call(R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE), R.S_ALERT), st.call(R.card(R.C_STATE_TIME, calm, R.C_NONE, 0.0, R.A_TO_FORAGE), R.S_ALERT)]
	var shout: Array = Rules.default_deck(0)
	shout[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_EMIT_A)
	var alarm: Array = Rules.default_deck(0)
	alarm[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_EMIT_A)
	alarm.insert(1, R.card(R.C_SIGNAL_A, smell, R.C_NONE, 0.0, R.A_TO_ALERT))
	alarm += [st.call(R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_EMIT_A), R.S_ALERT), st.call(R.card(R.C_STATE_TIME, calm, R.C_NONE, 0.0, R.A_TO_FORAGE), R.S_ALERT)]
	var runs: Array = Rules.default_deck(0)
	runs[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_EMIT_A)
	runs.insert(1, R.card(R.C_SIGNAL_A, smell, R.C_NONE, 0.0, R.A_FLEE))
	var bottom: Array = Rules.default_deck(0)
	bottom[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_EMIT_A)
	bottom.append(R.card(R.C_SIGNAL_A, smell, R.C_NONE, 0.0, R.A_FLEE))
	var g2 := [2.0, 1.0, 1.0, 1.0, 3.0, 3.0, 5.0, 3.0]
	var g4 := [4.0, 1.0, 1.0, 1.0, 2.0, 3.0, 5.0, 3.0]
	var sig := ["gland", "chemo_rec"]
	var plans := [["原样", plain, [], g2], ["警戒+鞭毛", alert, ["flagellum"], g2], ["只喊", shout, sig, g2], ["喊+闻到就逃", runs, sig, g2],
		["警戒+鞭毛 速4", alert, ["flagellum"], g4], ["喊+闻到就逃 速4", runs, sig, g4], ["喊+闻到就逃(放最下) 速4", bottom, sig, g4]]
	var jobs := []
	for pl: Array in plans:
		var dz := LevelEval.design_from_genes(pl[3], (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, pl[2], "3-1")
		for k in seeds:
			jobs.append([l.duplicate(true), dz.duplicate(true), 1000 + k * 7919, dz.used])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	var task := WorkerThreadPool.add_group_task(job, jobs.size(), -1, true)
	WorkerThreadPool.wait_for_group_task_completion(task)
	for p in plans.size():
		var w := 0
		var ch := 0
		var al := []
		var ea := 0
		for k in seeds:
			var ev: LevelEval = res[p * seeds + k]
			var s2: Array = ev.stars()
			w += 1 if s2[0] else 0
			ch += 1 if s2[1] else 0
			al.append(ev.alive)
			ea += ev.eaten
		al.sort()
		print("%s  used %d  胜 %d/%d  挑战 %d  存活中位 %d（%d–%d）  被吃 %d" % [plans[p][0], int(jobs[p * seeds][3]), w, seeds, ch, al[seeds / 2], al[0], al[-1], ea / seeds])
	quit()
