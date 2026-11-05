extends SceneTree
# Chapter 6 level bot: a level (P_LEVEL, e.g. 6-1) played headless with a few
# designs, P_SEEDS seeds each, in parallel. Prints the goal / challenge rate
# and the run's numbers. P_SET picks a design set.
func _env(key: String, d: float) -> float:
	return float(OS.get_environment(key)) if OS.get_environment(key) != "" else d


func _design(l: Dictionary, genes: Array, deck: Array, organs: Array, resp := -1, color := Color(0.5, 0.8, 0.9)) -> Dictionary:
	var d := LevelEval.design_from_genes(genes, deck, color, 12.0, true, organs, l.id)
	d.params.resp = resp if resp >= 0 else int(l.get("resp", 0))
	d.params.name = "设计"
	if l.get("resp_open", false):
		d.used += Resp.cost(d.params.resp)
	return d


func _slot(l: Dictionary, k: int, genes := [], deck := [], resp := -1) -> Dictionary:
	var spec: Dictionary = l.species[k]
	var organs: Array = spec.get("organs", [])
	var g: Array = genes if not genes.is_empty() else spec.get("genes", [2.0, 2.0, 1.0, 1.0, 2.5, 3.0, 3.0, 3.0])
	var dk: Array = deck if not deck.is_empty() else spec.get("deck", Rules.default_deck(1 if organs.has("cnido") else 0))
	var r: int = resp if resp >= 0 else int(spec.get("resp", l.get("resp", 0)))
	var d := _design(l, g, dk, organs, r)
	return d


func _initialize() -> void:
	var id := OS.get_environment("P_LEVEL") if OS.get_environment("P_LEVEL") != "" else "6-1"
	var l: Dictionary = Levels.by_id(id).duplicate(true)
	for k in ["sulfide", "diffuse", "emit", "harm", "tox", "decay", "start", "graze", "need", "use"]:
		var e := OS.get_environment("P_O2_" + k.to_upper())
		if e != "":
			l.world.oxygen[k] = float(e)
	if OS.get_environment("P_BAND") != "":
		l.world.light_band = [330.0, float(OS.get_environment("P_BAND")), 0.6]
	var R := Rules
	var plans := []
	var base := Rules.default_deck(0)
	var avoid := [R.card(R.C_O2_ABOVE, _env("P_AVOID", 0.06), R.C_NONE, 0.0, R.A_AVOID_O2)] + base
	match id:
		"6-1":
			for g in [[2.0, 2.0, 1, 1, 2.5, 3.0, 3, 3], [1.0, 2.0, 1, 1, 3.0, 3.0, 3, 3], [1.0, 1.0, 1, 1, 3.5, 3.5, 3, 3], [3.0, 3.0, 1, 1, 2.0, 2.0, 3, 3]]:
				plans.append(["基因 %s" % str(g.slice(0, 6)), _design(l, g, base, ["sulfase"])])
		"6-2":
			for g in [[2.0, 2.0, 1, 1, 2.5, 3.0, 3, 3], [1.0, 2.0, 1, 1, 3.5, 3.0, 3, 3], [1.0, 1.0, 1, 1, 4.0, 3.5, 3, 3], [2.0, 1.0, 1, 1, 3.0, 4.0, 3, 3]]:
				plans.append(["基因 %s" % str(g.slice(0, 6)), _design(l, g, base, ["photo"])])
		"6-3":
			for b in [["不改", []], ["加避氧卡", avoid]]:
				var a := _slot(l, 0)
				a.extra = [_slot(l, 1, [], b[1]).params]
				plans.append(["硫泉：%s" % b[0], a])
		"6-4":
			for r in [[2, 2], [1, 2], [3, 3]]:
				var a := _slot(l, 0)
				a.extra = [_slot(l, 1, [], [], r[0]).params, _slot(l, 2, [], [], r[1]).params]
				plans.append(["B/C 呼吸 %s" % str(r), a])
	var seeds := int(_env("P_SEEDS", 8))
	var seed0 := randi() % 900000
	for p: Array in plans:
		var res := []
		res.resize(seeds)
		var task := WorkerThreadPool.add_group_task(func(k: int) -> void:
			var ev := LevelEval.simulate(l.duplicate(true), (p[1] as Dictionary).duplicate(true), seed0 + k)
			var sim: SimCore = ev._sim
			var diag := ""
			if sim and ev.sp2 >= 0:
				var st: Dictionary = sim.get_stats().species[ev.sp2]
				var v := Vector2(1100, 1930)
				diag = " 计%d 氧死%d 饿%d 老%d 泉心%.0f%% 泉边%.0f%% 中层%.0f%% 上层%.0f%%" % [ev.o2_dead, int(st.o2), int(st.starved), int(st.aged), sim.get_o2_at(v) * 100, sim.get_o2_at(v + Vector2(0, -200)) * 100, sim.get_o2_at(Vector2(1100, 1200)) * 100, sim.get_o2_at(Vector2(1100, 500)) * 100]
			res[k] = [ev.stars(), ev.alive, ev.alive2, ev.alive3, ev.o2_mean, ev.held.duplicate(), ev.extinct, ev.t, diag], seeds)
		WorkerThreadPool.wait_for_group_task_completion(task)
		var g := 0
		var c := 0
		var line := ""
		for r: Array in res:
			g += 1 if r[0][0] else 0
			c += 1 if r[0][1] else 0
			line += "
   [%d/%d/%d 氧%.0f%%%s%s]" % [r[1], r[2], r[3], r[4] * 100.0, (" 泉" + str(r[5])) if not (r[5] as Array).is_empty() else "", (" 灭%ds" % int(r[7]) if r[6] else "") + r[8]]
		print("%s %-28s 目标 %d/%d 挑战 %d/%d %s" % [id, p[0], g, seeds, c, seeds, line])
	quit()
