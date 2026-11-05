extends SceneTree
# Chapter 6 level bot: a level (P_LEVEL, e.g. 6-1) played headless with a few
# designs, P_SEEDS seeds each, in parallel. Prints the goal / challenge rate
# and the run's numbers. P_SET picks a design set.
func _env(key: String, d: float) -> float:
	return float(OS.get_environment(key)) if OS.get_environment(key) != "" else d


func _design(l: Dictionary, genes: Array, deck: Array, organs: Array, resp := -1, color := Color(0.5, 0.8, 0.9), life := 1.0) -> Dictionary:
	var d := LevelEval.design_from_genes(genes, deck, color, float(l.get("temp_fixed", 12.0)), true, organs, l.id)
	d.params.life = life
	d.params.lifespan = float(d.params.lifespan) * life
	d.params.slow_divide = 1.0 + 0.4 * (life - 1.0) if life >= 1.0 else 1.0 - 0.4 * (1.0 - life)
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
	for k in ["sulfide", "diffuse", "emit", "harm", "tox", "decay", "start", "graze", "need", "use", "graze_rest", "refuge"]:
		var e := OS.get_environment("P_O2_" + k.to_upper())
		if e != "":
			l.world.oxygen[k] = float(e)
	for k in ["need", "grow", "shrink", "drain", "slow", "use", "radius", "top"]:
		var e := OS.get_environment("P_NET_" + k.to_upper())
		if e != "" and l.has("net"):
			l.net[k] = float(e)
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
		"6-5":
			var aero := Rules.default_deck(0)
			var seek := [R.card(R.C_O2_ABOVE, 0.08, R.C_NONE, 0.0, R.A_SEEK_O2)] + aero
			for g in [[[2.0, 2.0, 1, 1, 3.0, 3.0, 3, 3], aero, "默认"], [[2.0, 2.0, 1, 1, 4.0, 3.0, 3, 3], aero, "繁殖4"], [[2.0, 2.0, 1, 1, 4.0, 3.0, 3, 3], seek, "繁殖4+找氧"]]:
				plans.append([g[2], _design(l, g[0], g[1], [], 2)])
			var iron := []
			for at_t in range(20, 340, int(_env("P_IRON_EVERY", 12))):
				iron.append({at = float(at_t), kind = "iron"})
			var dz := _design(l, [2.0, 2.0, 1, 1, 4.0, 3.0, 3, 3], aero, [], 2)
			dz.plan = iron
			plans.append(["繁殖4+一直撒铁粉", dz])
		"7-1":
			var home: Array = (LevelsCh7.HOME_DECK as Array).duplicate(true)
			for g in [[2.0, 2.0, 1, 1, 3.0, 3.0, 4, 3], [3.0, 2.0, 1, 1, 3.0, 3.0, 4, 3]]:
				plans.append(["默认卡 %s" % str(g.slice(0, 6)), _design(l, g, base, ["memory"])])
				plans.append(["记忆卡 %s" % str(g.slice(0, 6)), _design(l, g, home, ["memory"])])
		"7-2", "7-5":
			var sp_cards := [R.card(R.C_NIGHT, 0.0, R.C_NONE, 0.0, R.A_TO_SPORE)] + base
			var wake := R.card(R.C_DAY, 0.0, R.C_NONE, 0.0, R.A_TO_FORAGE)
			wake.st = R.S_SPORE
			sp_cards.append(wake)
			var org := ["spore"] if id == "7-2" else ["spore", "memory"]
			plans.append(["不用芽孢", _design(l, [2.0, 2.0, 1, 1, 3.0, 3.0, 4, 3], base, org)])
			plans.append(["芽孢卡", _design(l, [2.0, 2.0, 1, 1, 3.0, 3.0, 4, 3], sp_cards, org)])
			if id == "7-5":
				var both: Array = (LevelsCh7.HOME_DECK as Array).duplicate(true)
				both.remove_at(1) # (the flee card: room for the spore pair in 6 slots)
				both.insert(0, R.card(R.C_NIGHT, 0.0, R.C_NONE, 0.0, R.A_TO_SPORE))
				both.append(wake)
				plans.append(["记忆+芽孢", _design(l, [2.0, 2.0, 1, 1, 3.0, 3.0, 5, 3], both, org)])
		"7-3":
			for lf in [0.6, 1.0, 1.6]:
				for g in [[2.0, 2.0, 1, 1, 2.0, 4.0, 3, 3], [2.0, 2.0, 1, 1, 4.0, 3.0, 3, 3]]:
					plans.append(["寿命 %.1f %s" % [lf, str(g.slice(0, 6))], _design(l, g, base, [], -1, Color(0.5, 0.8, 0.9), lf)])
		"7-4":
			var roam := [base[0], base[1], base[2]]
			plans.append(["默认", _design(l, [2.0, 2.0, 1, 1, 3.0, 3.0, 3, 3], base, [])])
			plans.append(["不休息", _design(l, [2.0, 2.0, 1, 1, 3.0, 3.0, 3, 3], roam, [])])
			plans.append(["快 不休息", _design(l, [3.0, 3.0, 1, 1, 2.0, 2.0, 3, 3], roam, [])])
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
			var gs: int = ev.sp2 if id == "6-4" else ev.sp
			if sim and gs >= 0 and id in ["6-4", "6-5"]:
				var st2: Dictionary = sim.get_stats().species[gs]
				diag += " 采集者死因 饿%d 被吃%d 老%d 氧%d 生%d" % [int(st2.starved), int(st2.eaten), int(st2.aged), int(st2.o2), int(st2.births)]
			if id.begins_with("7-") and sim:
				var stc: Dictionary = sim.get_stats().species[ev.sp]
				diag += " 饿%d 冻%d 被吃%d 老%d 生%d" % [int(stc.starved), int(stc.temp), int(stc.eaten), int(stc.aged), int(stc.births)]
				if id == "7-2":
					diag += " 夜%d" % ev.dawns
				if id == "7-4":
					diag += " 季%s" % str(ev.season_counts)
				if id == "7-5":
					diag += " 虫%.0f%%%s 过%d" % [float(ev.helio.get("energy_frac", 0.0)) * 100.0, "死" if ev.helio.get("dead", false) else "", ev.passed]
			if l.has("net"):
				diag += " 网%.0f%%(峰%.0f%%) 达成%ds 吃%d" % [ev.net_cov * 100, ev.net_cov_peak * 100, int(ev.net_done), ev.net_caught]
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
