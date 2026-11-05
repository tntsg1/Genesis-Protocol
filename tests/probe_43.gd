extends SceneTree
# Probe for 4-3 in real conditions (mutation on, the real opening deck): does
# the phage carried in the genes decide the fight with the rival, and which
# way of waking it works? Env P_RATE, P_N (rival count), P_FERT (rival fertility).
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("4-3").duplicate(true)
	if OS.get_environment("P_RATE") != "":
		l.prophage = float(OS.get_environment("P_RATE"))
	if OS.get_environment("P_STICK") != "":
		l.phage.stick = float(OS.get_environment("P_STICK"))
	if OS.get_environment("P_N") != "":
		l.world.species[0].spawn[0][1] = int(OS.get_environment("P_N"))
	if OS.get_environment("P_FERT") != "":
		l.world.species[0].params.fertility = float(OS.get_environment("P_FERT"))
	var R := Rules
	var genes := [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0]
	var base: Array = [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE), R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
	var plans := [["原样", base]]
	for pl: Array in [["第2张 70%（引导）", 1, 0.7], ["第2张 75%", 1, 0.75], ["第2张 60%", 1, 0.6], ["第1张 70%", 0, 0.7], ["第2张 90%", 1, 0.9]]:
		var d: Array = base.duplicate(true)
		d.insert(pl[1], R.card(R.C_AGE_ABOVE, pl[2], R.C_NONE, 0.0, R.A_INDUCE))
		plans.append([pl[0], d])
	var seeds := int(OS.get_environment("P_SEEDS")) if OS.get_environment("P_SEEDS") != "" else 8
	# (Fresh seeds each run: a fixed set can flatter a level. 4-5 read 90% on one, 67% on new ones.)
	var seed0 := randi() % 900000
	var jobs := []
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(genes, (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, [], "4-3")
		if pl.size() > 2:
			d.plan = [{at = 60.0, kind = "heat"}, {at = 120.0, kind = "heat"}, {at = 180.0, kind = "heat"}, {at = 240.0, kind = "heat"}]
		for k in seeds:
			jobs.append([l.duplicate(true), d.duplicate(true), seed0 + k * 4441])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for pl: Array in plans:
		var al := []
		var ri := []
		var ly := []
		var w := 0
		var dead := 0
		for s in seeds:
			var ev: LevelEval = res[k]
			k += 1
			al.append(ev.alive)
			ri.append(ev.rival_alive)
			ly.append(ev.lysed)
			w += 1 if ev.stars()[0] else 0
			dead += 1 if ev.rival_dead >= 0.0 else 0
		al.sort()
		ri.sort()
		ly.sort()
		print("%s  胜 %d/%d 灭对手 %d  你中位 %d（%d–%d）  对手中位 %d（%d–%d）  你被撑破 %d" % [pl[0], w, seeds, dead, al[seeds / 2], al[0], al[-1], ri[seeds / 2], ri[0], ri[-1], ly[seeds / 2]])
	quit()
