extends SceneTree
# Probe for level 1-2: the thrifty personality (old / new, slider ends) vs the
# breeder, with the guide's genes (metabolism 4).
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("1-2")
	var seeds := 8
	var g := [2.0, 2.0, 1.0, 1.0, 3.0, 4.0, 3.0, 3.0]
	var plans := []
	for b: float in [0.0, 0.5, 1.0]:
		plans.append(["节俭 bold %.1f" % b, Personas.build("thrifty", [], b)])
	plans.append(["繁衍 bold 0.5", Personas.build("breeder", [], 0.5)])
	var jobs := []
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(g, (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, [], "1-2")
		for k in seeds:
			jobs.append([l.duplicate(true), d.duplicate(true), 1000 + k * 7919])
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
		for k in seeds:
			var ev: LevelEval = res[p * seeds + k]
			var st: Array = ev.stars()
			w += 1 if st[0] else 0
			ch += 1 if st[1] else 0
			al.append(ev.alive)
		al.sort()
		var deck_txt := ", ".join((plans[p][1] as Array).map(func(c: Dictionary) -> String: return Rules.card_text(c)))
		print("%s  胜 %d/%d  挑战 %d  存活中位 %d（%d–%d）  卡组：%s" % [plans[p][0], w, seeds, ch, al[seeds / 2], al[0], al[-1], deck_txt])
	quit()
