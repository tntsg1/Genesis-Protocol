extends SceneTree
# Recording of chapter 1 levels 3-5: the level page, level 3's rule page,
# level 4's designer (temperature locked, the mutation switch) and its cold
# front, level 5's rival and patch score.
# Run: tools/run_test.sh tests/record_ch1.gd --write-movie <out.avi> --fixed-fps 30 -- --menu

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	for id in ["1-1", "1-2", "1-3", "1-4", "1-5"]:
		CampaignSave.mark_tutorial(id)
	for id in ["1-1", "1-2", "1-3", "1-4"]:
		CampaignSave.record(id, [true, false, false], false)
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _idle(s: float) -> void:
	for i in int(s * 30.0):
		await process_frame


func _until(cond: Callable, limit := 30.0) -> void:
	var n := 0
	while not cond.call() and n < int(limit * 30.0):
		await process_frame
		n += 1


func _run() -> void:
	await _idle(1.5)
	scene.open_campaign()
	await _idle(1.5)
	for i in [2, 3, 4]:
		scene.campaign._select(i)
		await _idle(1.8)
	# Level 3: the rule page.
	scene.start_level(Levels.by_id("1-3"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	await _idle(1.0)
	scene.designer.show_page("rules")
	await _idle(2.5)
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	scene.set_speed(8.0)
	await _idle(4.0)
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()
	# Level 4: locked temperature, mutation switch, the cold front.
	scene.start_level(Levels.by_id("1-4"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	# The sample sleeps when full: divide goes above rest, as the guide teaches.
	var dk: Array = scene.designer.deck_editor.deck
	scene.designer.deck_editor.move_card(dk.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_DIVIDE),
		dk.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_REST))
	await _idle(2.5)
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	scene.set_speed(8.0)
	await _until(func() -> bool: return scene.sim.get_time() - scene.level_runner.t0 > 108.0, 60.0)
	scene.set_speed(3.0)
	await _idle(6.0)
	scene.set_speed(8.0)
	await _idle(3.0)
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()
	# Level 5: the rival and the patch score.
	scene.start_level(Levels.by_id("1-5"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	scene.designer._set_temp_opt(3.0)
	await _idle(1.5)
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	scene.focus(Vector2(1100, 1150), 0.6)
	scene.set_speed(8.0)
	await _idle(7.0)
	quit()
