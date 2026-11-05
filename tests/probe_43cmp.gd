extends SceneTree
# Why the real game and the bot disagree on 4-3: the design as the game makes
# it, against the bot's, key by key, then that same real design run headless.
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


func _run() -> void:
	for r in 5:
		await _one(r)
	quit()


func _one(r: int) -> void:
	var l: Dictionary = Levels.by_id("4-3")
	scene.start_level(l)
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	await create_timer(0.4).timeout
	d.deck_editor.selected = 0
	var at: int = d.deck_editor.add_card()
	d.deck_editor.set_condition(at, 1, Rules.C_AGE_ABOVE)
	d.deck_editor.set_action(at, Rules.A_INDUCE)
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	scene.set_speed(8.0)
	print("run ", r, " keep ", scene.sim.get_agent(scene.sim.find_agent(scene.sim.get_positions(lr.sp_index)[0], 8.0)).keys().size(), " rp ", lr.host.release_params.get("keep_act"), " ", lr.host.release_params.get("prophage"), " seed? ", scene.seed)
	var mark := 80.0
	while lr.eval.t < 240.0 and not is_instance_valid(lr.report):
		await process_frame
		if lr.eval.t >= mark:
			mark += 80.0
			var st: Dictionary = scene.sim.get_stats().species[lr.sp_index]
			var ps: PackedVector2Array = scene.sim.get_positions(lr.sp_index)
			var old := 0
			var woke := 0
			var firing := {}
			var ages := []
			for p: Vector2 in ps:
				var a: Dictionary = scene.sim.get_agent(scene.sim.find_agent(p, 1.0))
				if a.is_empty():
					continue
				var f := float(a.age) / float(a.lifespan)
				ages.append(f)
				if f > 0.7:
					old += 1
					if float(a.infected) >= 0.0:
						woke += 1
					else:
						firing[str(a.get("fired", "?"))] = int(firing.get(str(a.get("fired", "?")), 0)) + 1
			ages.sort()
			print(" t%3d 你 %d 对手 %d 老死 %d 饿死 %d 撑破 %d 老细胞 %d 已醒 %d 未醒的卡 %s 年龄中位 %.2f 寿命 %.0f" % [lr.eval.t, st.alive, lr.eval.rival_alive, st.aged, st.starved, st.phage, old, woke, firing, ages[ages.size() / 2] if not ages.is_empty() else 0.0, 0.0])
	await _until(func() -> bool: return is_instance_valid(lr.report), 60.0)
	print(" 结果 ", lr.eval.stars()[0], " 你 ", lr.eval.alive, " 对手 ", lr.eval.rival_alive, " 撑破 ", lr.eval.lysed, " 老死 ", scene.sim.get_stats().species[lr.sp_index].aged)
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null, 10.0)
	await create_timer(0.5).timeout
