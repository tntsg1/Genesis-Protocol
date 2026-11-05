extends SceneTree
# Probe for 4-4 in real conditions: does the shape of the virus and the time
# it is dropped decide the level? Early the rival is thin; later it is thick.
# Env P_N (rival count), P_MAX (rival limit), P_SHOT (particles per drop).
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("4-4").duplicate(true)
	if OS.get_environment("P_N") != "":
		l.world.species[0].spawn[0][1] = int(OS.get_environment("P_N"))
	if OS.get_environment("P_MAX") != "":
		l.goal.rival_max = int(OS.get_environment("P_MAX"))
	var shot := int(OS.get_environment("P_SHOT")) if OS.get_environment("P_SHOT") != "" else 60
	var d0: Dictionary = l.start_design
	var plans := [["结晶型 开局", {burst = 2, speed = 2, shell = 5, stick = 3}, [30.0, 42.0], []],
		["结晶型 60 秒", {burst = 2, speed = 2, shell = 5, stick = 3}, [60.0, 72.0], []],
		["均衡 中段", {burst = 3, speed = 3, shell = 3, stick = 3}, [120.0, 132.0], []],
		["爆发型 开局", {burst = 5, speed = 4, shell = 1, stick = 2}, [30.0, 42.0], []],
		["爆发型 中段", {burst = 5, speed = 4, shell = 1, stick = 2}, [120.0, 132.0], []],
		["潜伏 开局 + 200 秒升温", {burst = 3, speed = 3, shell = 3, stick = 3, temperate = true}, [40.0, 52.0], [200.0, 212.0, 224.0]],
		["潜伏 不升温", {burst = 3, speed = 3, shell = 3, stick = 3, temperate = true}, [40.0, 52.0], []]]
	var seeds := int(OS.get_environment("P_SEEDS")) if OS.get_environment("P_SEEDS") != "" else 12
	# (Fresh seeds each run: a fixed set can flatter a level. 4-5 read 90% on one, 67% on new ones.)
	var seed0 := randi() % 900000
	var jobs := []
	var rows := []
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, [], "4-4")
		d.virus = pl[1]
		d.plan = []
		for at: float in pl[2]:
			d.plan.append({at = at, kind = "phage", n = shot})
		for at: float in pl[3]:
			d.plan.append({at = at, kind = "heat_rival"})
		rows.append(pl[0])
		for k in seeds:
			jobs.append([l.duplicate(true), d.duplicate(true), seed0 + k * 5519])
	var none := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, [], "4-4")
	none.virus = {burst = 3, speed = 3, shell = 3, stick = 3}
	rows.append("不投放")
	for k in seeds:
		jobs.append([l.duplicate(true), none.duplicate(true), seed0 + k * 5519])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for r: String in rows:
		var al := []
		var ri := []
		var w := 0
		for s in seeds:
			var ev: LevelEval = res[k]
			k += 1
			al.append(ev.alive)
			ri.append(ev.rival_alive)
			w += 1 if ev.stars()[0] else 0
		al.sort()
		ri.sort()
		print("%s  胜 %d/%d  你 %d（%d–%d）  对手 %d（%d–%d）" % [r, w, seeds, al[seeds / 2], al[0], al[-1], ri[seeds / 2], ri[0], ri[-1]])
	quit()
