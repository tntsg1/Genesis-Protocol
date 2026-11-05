extends SceneTree
# Probe for the chapter 3 boss (3-4, the echo): the start plan (alarm on A),
# the alarm on B, no alarm; each run on its own copies.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("3-4")
	if OS.get_environment("N") != "":
		l = l.duplicate(true)
		l.world.species[0].spawn[0][1] = int(OS.get_environment("N"))
	var R := Rules
	var sd: Dictionary = l.start_design
	var on_a: Array = (sd.deck as Array).duplicate(true)
	var on_b: Array = on_a.duplicate(true)
	on_b[0].act = R.A_EMIT_B
	on_b[1].c1 = R.C_SIGNAL_B
	var quiet: Array = on_a.duplicate(true)
	quiet[0].act = R.A_FLEE
	quiet.remove_at(1)
	var on_b3: Array = on_b.duplicate(true)
	on_b3[1].t1 = 0.3
	var on_b6: Array = on_b.duplicate(true)
	on_b6[1].t1 = 0.6
	var plans := [["开局方案(警报A)", on_a, sd.organs], ["警报B 门槛0.6", on_b6, sd.organs], ["不用警报只逃", quiet, []]]
	var seeds := 8
	var jobs := []
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(sd.genes, (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, pl[2], "3-4")
		for k in seeds:
			jobs.append([l.duplicate(true), d.duplicate(true), 1000 + k * 7919])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for pl: Array in plans:
		var al := []
		var rv := []
		var w := 0
		var dead := 0
		for s in seeds:
			var ev: LevelEval = res[k]
			k += 1
			al.append(ev.alive)
			rv.append(ev.rival_alive)
			w += 1 if ev.stars()[0] else 0
			dead += 1 if ev.rival_dead >= 0.0 else 0
		al.sort()
		rv.sort()
		print("%s  胜 %d/%d  挤灭 %d  你中位 %d（%d–%d）  对手中位 %d" % [pl[0], w, seeds, dead, al[seeds / 2], al[0], al[-1], rv[seeds / 2]])
	quit()
