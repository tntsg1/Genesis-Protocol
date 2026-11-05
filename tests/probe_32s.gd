extends SceneTree
# Probe for level 3-2 (synchronised breeding): plans x seeds in parallel.
# env N = hunters, SPEED, DIGEST.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("3-2").duplicate(true)
	var hp: Dictionary = l.world.species[0].params
	if OS.get_environment("N") != "":
		l.world.species[0].spawn[0][1] = int(OS.get_environment("N"))
	if OS.get_environment("DIGEST") != "":
		hp.digest = float(OS.get_environment("DIGEST"))
	var R := Rules
	var seeds := 8
	var st := func(c: Dictionary, s: int) -> Dictionary:
		c.st = s
		return c
	var breed_cards := func() -> Array:
		return [st.call(R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE), R.S_BREED), st.call(R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE), R.S_BREED),
			st.call(R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.S_BREED), st.call(R.card(R.C_STATE_TIME, 40.0, R.C_NONE, 0.0, R.A_TO_FORAGE), R.S_BREED)]
	var plain := Rules.default_deck(0)
	var solo: Array = Rules.default_deck(0)
	solo[1] = R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_TO_BREED)
	solo += breed_cards.call()
	var sync: Array = solo.duplicate(true)
	sync.insert(1, R.card(R.C_PEER_STATE, float(R.S_BREED), R.C_NONE, 0.0, R.A_TO_BREED))
	var sync0: Array = sync.duplicate(true)
	sync0.remove_at(sync0.find_custom(func(c: Dictionary) -> bool: return c.act == R.A_REST and int(c.get("st", 0)) == R.S_FORAGE))
	var sync90: Array = sync0.duplicate(true)
	for c: Dictionary in sync90:
		if c.act == R.A_TO_FORAGE:
			c.t1 = 90.0
	var syncstay: Array = sync0.filter(func(c: Dictionary) -> bool: return c.act != R.A_TO_FORAGE)
	var g := [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 5.0, 3.0]
	var g4 := [4.0, 2.0, 1.0, 1.0, 2.0, 3.0, 5.0, 3.0]
	var plans := [["原样", plain, [], g], ["自己繁殖期", solo, [], g], ["同步繁殖期", sync, ["recog"], g], ["同步(删休息,40s回)", sync0, ["recog"], g], ["同步(删休息,90s回)", sync90, ["recog"], g], ["同步(删休息,不回)", syncstay, ["recog"], g],
		["原样 速4", plain, [], g4], ["自己繁殖期 速4", solo, [], g4], ["同步繁殖期 速4", sync, ["recog"], g4]]
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
