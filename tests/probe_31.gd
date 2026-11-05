extends SceneTree
# Probe for level 3-1: food calls. Plans x seeds in parallel, for one or more
# level variants (env CFGS: a JSON list of overrides, e.g.
# [{"lifespan":200,"world.algae_rates":[1,8],"blooms.power":2}]).
func _initialize() -> void:
	var base_l: Dictionary = Levels.by_id("3-1")
	var R := Rules
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 8
	var ce := float(OS.get_environment("CALL_E")) if OS.get_environment("CALL_E") != "" else 1.0
	var base := [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE), R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE),
		R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
	var call := R.card(R.C_SEE_ALGAE, 0.0, R.C_ENERGY_ABOVE, ce, R.A_EMIT_A)
	var listen := R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_SEEK_SIG_A)
	# Recruit only while the find is uncrowded; follow only when hungry.
	var crowd := int(OS.get_environment("CROWD")) if OS.get_environment("CROWD") != "" else 4
	var recruit := R.card(R.C_SEE_ALGAE, 0.0, R.C_CROWD, float(crowd), R.A_EMIT_A)
	recruit.n2 = true
	var hungry := R.card(R.C_ENERGY_BELOW, 1.0, R.C_NONE, 0.0, R.A_SEEK_SIG_A)
	var plans := [["原样", base, []], ["只喊", [base[0], call, base[1], base[2]], ["gland", "chemo_rec"]],
		["喊+听", [base[0], call, base[1], listen, base[2]], ["gland", "chemo_rec"]],
		["少人才喊+饿才听", [base[0], recruit, base[1], hungry, base[2]], ["gland", "chemo_rec"]]]
	var cfgs: Array = JSON.parse_string(OS.get_environment("CFGS")) if OS.get_environment("CFGS") != "" else [{}]
	var g := [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0]
	for cfg: Dictionary in cfgs:
		var l: Dictionary = base_l.duplicate(true)
		for k: String in cfg:
			if k == "home":
				l.world.lights = [[Vector2(1100, 1100), float(cfg[k][0]), float(cfg[k][1])]]
				continue
			var parts := k.split(".")
			var d: Dictionary = l
			for q in parts.size() - 1:
				d = d[parts[q]]
			d[parts[-1]] = cfg[k]
		print("== ", JSON.stringify(cfg))
		var jobs := []
		for pl: Array in plans:
			var dz := LevelEval.design_from_genes(g, (pl[1] as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, pl[2], "3-1")
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
			var ch := 0
			var al := []
			var got := 0
			var due := 0
			for k in seeds:
				var ev: LevelEval = res[p * seeds + k]
				var st: Array = ev.stars()
				w += 1 if st[0] else 0
				ch += 1 if st[1] else 0
				al.append(ev.alive)
				var bc := ev.blooms_counted()
				got += bc[0]
				due += bc[1]
			al.sort()
			print("  %s  胜 %d/%d  挑战 %d  存活中位 %d（%d–%d）  藻华赶到 %d/%d" % [plans[p][0], w, seeds, ch, al[seeds / 2], al[0], al[-1], got, due])
	quit()
