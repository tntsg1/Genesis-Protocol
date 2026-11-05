extends SceneTree
# 7-1 diagnosis: one run with the memory deck, every 20 s: how many, how many
# in the warm pocket, how full, how many remember a spot, algae left, births.

func _initialize() -> void:
	var lid := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "7-1"
	var l: Dictionary = Levels.by_id(lid).duplicate(true)
	var deck: Array = (LevelsCh7.HOME_DECK as Array).duplicate(true)
	if OS.get_environment("DECK") == "base":
		deck = Rules.default_deck(0)
	var organs := ["memory"]
	if l.has("events") and OS.get_environment("SPORE") != "":
		organs.append("spore")
		deck.insert(0, Rules.card(Rules.C_NIGHT, 0.0, Rules.C_NONE, 0.0, Rules.A_TO_SPORE))
		var wake := Rules.card(Rules.C_DAY, 0.0, Rules.C_NONE, 0.0, Rules.A_TO_FORAGE)
		wake.st = Rules.S_SPORE
		deck.append(wake)
	var d := LevelEval.design_from_genes([2.0, 2.0, 1, 1, 3.0, 3.0, 4, 3], deck, Color(0.5, 0.8, 0.9), 12.0, true, organs, lid)
	var run := LevelEval.prepare(l, d, 11, 4)
	var sim: SimCore = run.sim
	var ev: LevelEval = run.eval
	var next := 0.0
	while run.t < float(l.time_limit) and not ev.extinct:
		LevelEval.advance(run, 1.0 / 15.0)
		if run.t >= next:
			next += 20.0
			var pos: PackedVector2Array = sim.get_positions(ev.sp)
			var home := 0
			var mem := 0
			var full := 0
			var ef := 0.0
			var acts := {}
			for a in 600:
				var ag: Dictionary = sim.get_agent(a)
				if ag.is_empty() or int(ag.get("species", -1)) != ev.sp:
					continue
				var ac := int(ag.get("action", -1))
				acts[ac] = int(acts.get(ac, 0)) + 1
				ef += float(ag.get("energy_frac", 0.0))
				full += 1 if float(ag.get("energy_frac", 0.0)) >= 1.0 else 0
			for p in pos:
				home += 1 if p.distance_to(Vector2(360, 1100)) < 240.0 else 0
			var st: Dictionary = sim.get_stats()
			print(("夜 " if sim.get_night() else "昼 ") + "t=%3d 活 %3d 暖区 %3d 吃饱 %3d 平均能量 %.2f 藻 %3d 生 %3d 老死 %3d 饿死 %3d" % [int(run.t), pos.size(), home, full, ef / maxf(pos.size(), 1), int(st.algae), int(st.species[ev.sp].births), int(st.species[ev.sp].aged), int(st.species[ev.sp].starved)], " 动作", acts)
	quit()
