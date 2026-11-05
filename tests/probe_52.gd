extends SceneTree
# Probe for 5-2 in real conditions (mutation on, fresh seeds): which bodies
# reach the upstream field? Env P_SEEDS, P_STREAM, P_GRIT, P_N, P_GEST, P_PUSH,
# P_DRAG, P_BITE, P_E, P_LIFE.
func _env(key: String, d: float) -> float:
	return float(OS.get_environment(key)) if OS.get_environment(key) != "" else d


# Rows of a blueprint, front at the right, drawn as text: F flagellum, G germ, . gap.
static func _bp(rows: Array) -> Array:
	var out := []
	for j in rows.size():
		var r: String = rows[j]
		for i in r.length():
			if r[i] == "F":
				out.append([i, j, Colony.FLAG])
			elif r[i] == "G":
				out.append([i, j, Colony.GERM])
	return out


func _initialize() -> void:
	var l: Dictionary = Levels.by_id("5-2").duplicate(true)
	l.colony.stream = Vector2(-_env("P_STREAM", -l.colony.stream.x), 0.0)
	l.colony.grit = int(_env("P_GRIT", l.colony.grit))
	l.colony.gest = _env("P_GEST", l.colony.gest)
	l.lifespan = _env("P_LIFE", l.lifespan)
	l.goal.n = int(_env("P_N", l.goal.n))
	l.world.algae_cap = int(_env("P_ALG", l.world.algae_cap))
	l.world.algae_seed[0] = int(_env("P_SEED", l.world.algae_seed[0]))
	var tune := {push = _env("P_PUSH", Colony.TUNE.push), drag = _env("P_DRAG", Colony.TUNE.drag), keep = _env("P_KEEP", Colony.TUNE.keep), keep_w = _env("P_KEEPW", Colony.TUNE.keep_w), block_e = _env("P_E", Colony.TUNE.block_e), germ_e = _env("P_GE", Colony.TUNE.germ_e)}
	var d0: Dictionary = l.start_design
	var plans := [["开局不改", d0.blocks],
		["引导 3×4（3 生殖在中线）", _bp(["FFFF", "GGGF", "FFFF"])],
		["2 生殖 3×4", _bp(["FFFF", "FGGF", "FFFF"])],
		["4 生殖 3×4", _bp(["FFFF", "GGGF", "GFFF"])],
		["5 生殖 3×4", _bp(["FFFF", "GGGF", "GGFF"])],
		["全鞭毛 1 生殖", _bp(["FFFF", "FGFF", "FFFF"])],
		["2×6 条 3 生殖", _bp(["GFFFFF", "GGFFFF"])],
		["1×12 细条 3 生殖", _bp(["GGGFFFFFFFFF"])],
		["4×3 横宽 3 生殖", _bp(["FFF", "GGF", "GFF", "FFF"])],
		["2×4（8 块）2 生殖", _bp(["GFFF", "GFFF"])],
		["2×4（8 块）3 生殖", _bp(["GGFF", "GFFF"])],
		["3×3 缺角（8 块）2 生殖", _bp(["FFF", "GGF", "FF"])],
		["1×8 细条 2 生殖", _bp(["GGFFFFFF"])],
		["1×8 细条 3 生殖", _bp(["GGGFFFFF"])],
		["2×6 生殖在前", _bp(["FFFFFG", "FFFFGG"])],
		["生殖在前", _bp(["FFFG", "FFFG", "FFFG"])]]
	if OS.get_environment("P_SET") == "tools":
		var help := []
		var feed := []
		for at_t in range(20, 340, 30):
			help.append({at = float(at_t), kind = "current_own", velocity = Vector2(60, 0)})
		for at_t in range(30, 340, 15):
			feed.append({at = float(at_t), kind = "nutrient_at", pos = Vector2(1270, 1100)})
		plans = [plans[1], ["引导 + 洋流送上游", plans[1][1], help], ["引导 + 中途投营养", plans[1][1], feed]]
	if OS.get_environment("P_SET") == "core":
		plans = [plans[0], plans[1], plans[2], plans[3], plans[6], plans[7], plans[8], plans[9], plans[12], plans[14]]
	var seeds := int(_env("P_SEEDS", 8.0))
	var seed0 := randi() % 900000
	var jobs := []
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), d0.color, 12.0, true, [], "5-2")
		d.params.blocks = pl[1]
		d.params.tune = tune
		if pl.size() > 2:
			d.plan = pl[2]
		for k in seeds:
			jobs.append([l.duplicate(true), d.duplicate(true), seed0 + k * 6113])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2])
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for pl: Array in plans:
		var s: Dictionary = Colony.stats(pl[1], tune)
		var z := []
		var al := []
		var w := 0
		var ch := 0
		var ex := 0
		var born := 0
		var lost := 0
		var pk := 0
		var ztime := 0.0
		for q in seeds:
			var ev: LevelEval = res[k]
			k += 1
			z.append(ev.zone_peak)
			al.append(ev.alive)
			var st: Array = ev.stars()
			w += 1 if st[0] else 0
			ch += 1 if st[1] else 0
			ex += 1 if ev.extinct else 0
			born += int(ev.colony_stats.get("born", 0))
			lost += int(ev.colony_stats.get("lost", 0))
			pk += ev.peak
			ztime += ev.zone_by_t if ev.zone_by_t >= 0.0 else 360.0
		z.sort()
		al.sort()
		print("%-20s 速%4.1f 吃%.2f  胜 %d/%d 挑战 %d 灭 %d 上游峰 %d（%d–%d）终 %d 峰 %d 生 %d 砸 %d 达成 %.0f" % [pl[0], s.speed, s.keep, w, seeds, ch, ex, z[seeds / 2], z[0], z[-1], al[seeds / 2], pk / seeds, born / seeds, lost / seeds, ztime / seeds])
	quit()
