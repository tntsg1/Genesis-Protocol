extends SceneTree
# Probe: level 7 (2-2). Which card decides survival: the 或 flee card
# (hunter near OR bitten -> flee), the 不 regroup card (NOT many mates ->
# follow mates), both; with no armour / silica shell / spines.
# Prints alive at the end / eaten, per deck and organ.

func _initialize() -> void:
	var l := Levels.by_id("2-2")
	var R := Rules
	var flee := R.card(R.C_PREDATOR_NEAR, 60.0, R.C_NONE, 0.0, R.A_FLEE)
	var flee_or := R.card(R.C_PREDATOR_NEAR, 60.0, R.C_ATTACKED, 0.0, R.A_FLEE)
	flee_or.any = true
	var regroup := R.card(R.C_CROWD, 3.0, R.C_NONE, 0.0, R.A_FOLLOW)
	regroup.n1 = true
	var rest := [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE),
		R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE),
		R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
	var flee120 := R.card(R.C_PREDATOR_NEAR, 120.0, R.C_NONE, 0.0, R.A_FLEE)
	var huddle := R.card(R.C_CROWD, 3.0, R.C_PREDATOR_NEAR, 150.0, R.A_FOLLOW)
	huddle.n1 = true
	var careful := R.card(R.C_ENERGY_BELOW, 1.0, R.C_PREDATOR_NEAR, 150.0, R.A_SEEK_ALGAE)
	careful.n2 = true
	var decks := {原样 = [flee] + rest, 或 = [flee_or] + rest, E远逃 = [flee120] + rest,
		H落单归队 = [flee, huddle] + rest, I有猎手不吃 = [flee, rest[0], careful, rest[2]]}
	var organ_sets := {无 = [], 壳 = ["silica"]}
	var genes := [3.0, 2.0, 2.0, 1.0, 3.0, 3.0, 3.0, 2.5]
	var jobs := []
	for dn: String in decks:
		for on: String in organ_sets:
			for s in 5:
				jobs.append([dn, on, s])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		var j: Array = jobs[k]
		var d := LevelEval.design_from_genes(genes, decks[j[0]].duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, organ_sets[j[1]], "2-2")
		var ev := LevelEval.simulate(l, d, 1000 + j[2] * 7919)
		res[k] = "%d/%d" % [ev.alive, ev.eaten]
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for dn: String in decks:
		var line := "%s:" % dn
		for on: String in organ_sets:
			line += "  [%s] %s" % [on, str(res.slice(k, k + 5))]
			k += 5
		print(line)
	quit()
