extends SceneTree
# Probe for level 3-2 (shield of many): plans x seeds in parallel.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("3-2")
	if OS.get_environment("DIGEST") != "":
		l = l.duplicate(true)
		l.world.species[0].params.digest = float(OS.get_environment("DIGEST"))
	var R := Rules
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 8
	var st := func(c: Dictionary, s: int) -> Dictionary:
		c.st = s
		return c
	var plain := Rules.default_deck(0)
	var swarm: Array = Personas.build("swarm", [], 0.5)
	var alert: Array = Rules.default_deck(0)
	alert[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_TO_ALERT)
	alert += [st.call(R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE), R.S_ALERT), st.call(R.card(R.C_STATE_TIME, 10.0, R.C_NONE, 0.0, R.A_TO_FORAGE), R.S_ALERT)]
	var shield: Array = alert.duplicate(true)
	shield.insert(1, R.card(R.C_PEER_STATE, float(R.S_ALERT), R.C_NONE, 0.0, R.A_FOLLOW))
	# Alert means "close ranks": in alert, follow the others instead of fleeing.
	var huddle: Array = Rules.default_deck(0)
	huddle[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_TO_ALERT)
	huddle.insert(1, R.card(R.C_PEER_STATE, float(R.S_ALERT), R.C_NONE, 0.0, R.A_FOLLOW))
	huddle += [st.call(R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_FOLLOW), R.S_ALERT), st.call(R.card(R.C_STATE_TIME, 10.0, R.C_NONE, 0.0, R.A_TO_FORAGE), R.S_ALERT)]
	# Close ranks but keep eating: alert = graze, else gather, back after 10 s.
	var huddle2: Array = Rules.default_deck(0)
	huddle2[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_TO_ALERT)
	huddle2.insert(1, R.card(R.C_PEER_STATE, float(R.S_ALERT), R.C_NONE, 0.0, R.A_FOLLOW))
	huddle2 += [st.call(R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.S_ALERT), st.call(R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_FOLLOW), R.S_ALERT),
		st.call(R.card(R.C_STATE_TIME, 10.0, R.C_NONE, 0.0, R.A_TO_FORAGE), R.S_ALERT)]
	# Join only while not already among enough peers; in a group, live normally.
	var join := R.card(R.C_PEER_STATE, float(R.S_ALERT), R.C_CROWD, 3.0, R.A_FOLLOW)
	join.n2 = true
	var lone := R.card(R.C_CROWD, 3.0, R.C_NONE, 0.0, R.A_FOLLOW)
	lone.n1 = true
	var herdA: Array = Rules.default_deck(0)
	herdA[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_TO_ALERT)
	herdA.insert(1, join)
	herdA += [st.call(lone.duplicate(), R.S_ALERT), st.call(R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.S_ALERT),
		st.call(R.card(R.C_STATE_TIME, 10.0, R.C_NONE, 0.0, R.A_TO_FORAGE), R.S_ALERT)]
	var herdB: Array = Rules.default_deck(0)
	herdB[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_TO_ALERT)
	herdB.insert(1, join.duplicate())
	herdB += [st.call(R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_FOLLOW), R.S_ALERT), st.call(R.card(R.C_STATE_TIME, 10.0, R.C_NONE, 0.0, R.A_TO_FORAGE), R.S_ALERT)]
	var g := [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 5.0, 3.0]
	var g4 := [4.0, 2.0, 1.0, 1.0, 2.0, 3.0, 5.0, 3.0]
	var rec := ["recog"]
	var plans := [["原样", plain, [], g], ["抱团性格", swarm, [], g], ["警戒逃", alert, [], g], ["警戒逃+看见警戒跟随", shield, rec, g],
		["警戒边吃边靠+看见警戒跟随", huddle2, rec, g], ["警戒抱团+看见警戒跟随", huddle, rec, g], ["警戒抱团(不识别)", huddle.filter(func(c: Dictionary) -> bool: return c.c1 != R.C_PEER_STATE), [], g],
		["警戒逃 速4", alert, [], g4], ["A 少人才靠+警戒里边吃", herdA, rec, g], ["B 少人才靠+警戒里抱团", herdB, rec, g], ["A 速4", herdA, rec, g4]]
	var jobs := []
	for pl: Array in plans:
		var dz := LevelEval.design_from_genes(pl[3], (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, pl[2], "3-2")
		for k in seeds:
			jobs.append([l.duplicate(true), dz.duplicate(true), 1000 + k * 7919])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	var task := WorkerThreadPool.add_group_task(job, jobs.size(), -1, true)
	WorkerThreadPool.wait_for_group_task_completion(task)
	for p in plans.size():
		var w := 0
		var al := []
		var ea := 0
		for k in seeds:
			var ev: LevelEval = res[p * seeds + k]
			w += 1 if ev.stars()[0] else 0
			al.append(ev.alive)
			ea += ev.eaten
		al.sort()
		print("%s  胜 %d/%d  存活中位 %d（%d–%d）  被吃 %d" % [plans[p][0], w, seeds, al[seeds / 2], al[0], al[-1], ea / seeds])
	quit()
