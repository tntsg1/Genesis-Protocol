extends SceneTree
# Chapter 1 levels 3-5 played live in the scene (default design, 8x): the
# designer follows each level's rules (rule page open on 1-3, temperature
# locked on 1-4, the mutation switch), the cold front comes on 1-4, the
# rival is in the dish and the patch score shows on 1-5, every run ends in
# a report. Run: tools/run_test.sh tests/ch1_live_check.gd

var scene: Node2D
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	for id in ["1-3", "1-4", "1-5"]:
		CampaignSave.mark_tutorial(id)
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, limit := 30.0) -> bool:
	# Real time, not frames: the frame rate is whatever the settings say.
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _run() -> void:
	for id in ["1-3", "1-4", "1-5"]:
		var l := Levels.by_id(id)
		scene.start_level(l)
		check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy), "%s: the designer opens" % id)
		var d: Control = scene.designer
		match id:
			"1-3":
				check(d.tab_buttons["rules"].modulate.a > 0.9, "1-3: the rule page is open")
				check(Rules.slots(d.genes[6]) == 4, "1-3: four card slots (%d)" % Rules.slots(d.genes[6]))
			"1-4":
				check(is_equal_approx(d.temp_opt, 12.0) and d.temp_slider.mouse_filter == Control.MOUSE_FILTER_IGNORE, "1-4: the preferred temperature is locked at 12 °C")
				check(d.mutate_pill != null and d.mutates, "1-4: natural mutation is on by default")
				# The sample sleeps when full (rest above divide): fix the order
				# as the guide has the player do, or it never divides.
				var dk: Array = d.deck_editor.deck
				var di := dk.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_DIVIDE)
				var ri := dk.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_REST)
				check(ri >= 0 and di > ri, "1-4: the sample's deck has rest above divide")
				d.deck_editor.move_card(di, ri)
			"1-5":
				d._set_temp_opt(3.0)
		d.release()
		check(await _until(func() -> bool: return scene.level_runner.phase == "run"), "%s: released, the clock runs" % id)
		var runner: Node = scene.level_runner
		if id == "1-3":
			check(float(scene.sim.get_agent(scene.sim.find_agent(l.release.at, 200.0)).get("lifespan", 0.0)) >= 280.0, "1-3: the level's long lives apply live")
		if id == "1-5":
			check(scene.labels.has("冰晶游丝"), "1-5: the rival is in the dish")
		scene.set_speed(8.0)
		if id == "1-4":
			await _until(func() -> bool: return scene.sim.get_time() - runner.t0 > 185.0, 90.0)
			var temp: float = scene.sim.get_env_at(Vector2(1100, 1100)).temp
			check(temp < -7.0, "1-4: the cold front has come (water %.1f °C)" % temp)
			check(runner.fired.has("0_start"), "1-4: the cold front was announced")
		if id == "1-5":
			await _until(func() -> bool: return scene.sim.get_time() - runner.t0 > 20.0, 30.0)
			check(scene.hud_root.panels.has("objective") and str(runner.eval.patch_counts) != "[]", "1-5: the patch score is kept (%s)" % str(runner.eval.patch_counts))
		check(await _until(func() -> bool: return runner.phase == "done", 120.0), "%s: the run ends" % id)
		check(runner.report != null, "%s: the report opens (stars %s)" % [id, str(runner.eval.stars())])
		runner.exit_level()
		await _until(func() -> bool: return scene.level_runner == null)
		scene.campaign.close()
		await _until(func() -> bool: return true)
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
