extends SceneTree
# Why the real game and the bot disagree on 4-5: the same design and drops,
# run headless and through the game, compared moment by moment.
# Run: tools/run_test.sh tests/cmp_45.gd

const MARKS := [10.0, 20.0, 30.0, 45.0, 60.0, 90.0, 120.0, 180.0, 240.0, 299.0]
const V := {burst = 4, speed = 5, shell = 1, stick = 2, temperate = true}
const DROPS := [10.0, 30.0]
var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _snap(sim: SimCore, ev: LevelEval) -> Dictionary:
	var gs: Dictionary = sim.get_giant_stats()
	var st: Dictionary = sim.get_stats()
	return {alive = ev.alive, carriers = int(gs.carriers), water = int(gs.water), factories = int(gs.factories), taken = int(gs.taken),
		hijacked = int(gs.hijacked), loaded = int(gs.loaded), phages = sim.get_phage_count(), algae = int(st.get("algae", 0))}


func _print(name: String, rows: Array) -> void:
	for k in MARKS.size():
		var sum := {}
		var n := 0
		for r: Array in rows:
			if k >= r.size():
				continue
			n += 1
			for key: String in r[k]:
				sum[key] = float(sum.get(key, 0.0)) + float(r[k][key])
		var line := "%s t=%3d n=%d" % [name, int(MARKS[k]), n]
		for key: String in ["alive", "carriers", "water", "factories", "taken", "hijacked", "loaded", "phages", "algae"]:
			line += "  %s %.0f" % [key, float(sum.get(key, 0.0)) / float(maxi(n, 1))]
		print(line)


func _headless(n: int) -> Array:
	var l: Dictionary = Levels.by_id("4-5")
	var d0: Dictionary = l.start_design
	var rows := []
	for s in n:
		var d := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, [], "4-5")
		d.virus = V
		d.plan = []
		for at: float in DROPS:
			d.plan.append({at = at, kind = "drop_own", n = 80})
		var run: Dictionary = LevelEval.prepare(l, d, 9100 + s * 4421, 8)
		var row := []
		var next := 0
		var obs := 0.0
		while run.t < 300.0:
			LevelEval.advance(run, 1.0 / 15.0)
			if next < MARKS.size() and run.t >= float(MARKS[next]):
				row.append(_snap(run.sim, run.eval))
				next += 1
		rows.append(row)
		print("模拟 #%d 巨毒囊 %d 你 %d" % [s, run.eval.giants, run.eval.alive])
	return rows


func _real(n: int) -> Array:
	var rows := []
	for s in n:
		scene.start_level(Levels.by_id("4-5"))
		await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
		var d: Control = scene.designer
		await _until(func() -> bool: return d.page == "virus", 5.0)
		if scene.level_runner.tutorial:
			scene.level_runner.tutorial._skip()
		var b: Control = d.virus_bench
		for k: String in ["burst", "speed", "shell", "stick"]:
			b.set_trait(k, 1)
		for k: String in ["burst", "speed", "shell", "stick"]:
			b.set_trait(k, int(V[k]))
		b._set_mode(true)
		if s == 0:
			var ref: Dictionary = Levels.by_id("4-5").start_design
			var bot := LevelEval.design_from_genes(ref.genes, (ref.deck as Array).duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, [], "4-5")
			d.release()
			await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
			for key: String in bot.params:
				if str(bot.params[key]) != str(scene.level_runner.design.params.get(key, "（无）")) and key != "color" and key != "name":
					print("参数不同 ", key, " 模拟 ", str(bot.params[key]).left(120), " 真实 ", str(scene.level_runner.design.params.get(key, "（无）")).left(120))
			for key: String in scene.level_runner.design.params:
				if not bot.params.has(key):
					print("只有真实有 ", key, " = ", str(scene.level_runner.design.params[key]).left(120))
		else:
			d.release()
			await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
		var lr: Node = scene.level_runner
		scene.iv.points = 300.0
		scene.set_speed(8.0)
		var row := []
		var next := 0
		var drops := DROPS.duplicate()
		while not is_instance_valid(lr.report) and next < MARKS.size():
			await process_frame
			if not drops.is_empty() and lr.eval.t >= float(drops[0]):
				drops.pop_front()
				scene.iv.place("phage", LevelEval.rival_thick(scene.sim, lr.sp_index))
			if lr.eval.t >= float(MARKS[next]):
				row.append(_snap(scene.sim, lr.eval))
				next += 1
		rows.append(row)
		print("真实 #%d 巨毒囊 %d 你 %d 拍数比 %.3f" % [s, lr.eval.giants, lr.eval.alive, scene.sim.get_time() / maxf(lr.eval.t, 1.0)])
		await _until(func() -> bool: return is_instance_valid(lr.report), 30.0)
		lr.exit_level()
		await _until(func() -> bool: return scene.level_runner == null, 10.0)
		await create_timer(0.5).timeout
	return rows


func _run() -> void:
	var a: Array = _headless(int(OS.get_environment("HN")) if OS.get_environment("HN") != "" else 6)
	_print("模拟", a)
	var b: Array = await _real(int(OS.get_environment("RN")) if OS.get_environment("RN") != "" else 5)
	_print("真实", b)
	quit()
