extends SceneTree
# Does a level play the same live as headless? Plays level 1-1 in the scene
# three times with one design (speed 4, sense 1, fertility 2) and prints the
# outcome next to headless runs of the same design.
# Run: tools/run_test.sh tests/level_live_check.gd

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	CampaignSave.mark_tutorial("1-1")
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
	var l: Dictionary = Levels.ALL[0]
	var genes := [4.0, 1.0, 1.0, 1.0, 2.0, 3.0, 3.0, 2.5]
	var dd := LevelEval.design_from_genes(genes, Rules.default_deck(0))
	for s in 3:
		var ev := LevelEval.simulate(l, dd, 777 + s)
		print("HEADLESS first_in %.0f zone_peak %d alive %d" % [ev.first_in, ev.zone_peak, ev.alive])
	for run in 3:
		scene.start_level(l)
		await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
		var d: Control = scene.designer
		for k_v in [[0, 4.0], [1, 1.0], [4, 2.0]]:
			d.gene_sliders[k_v[0]].changed.emit(k_v[1])
		d.release()
		await _until(func() -> bool: return scene.level_runner.phase == "predict")
		scene.level_runner.card._pick(0)
		scene.level_runner.card._confirm()
		await _until(func() -> bool: return scene.level_runner.phase == "run")
		print("LIVE released: genes %s" % str(scene.level_runner.design.genes))
		scene.set_speed(8.0)
		await _until(func() -> bool: return scene.level_runner.phase == "done", 200.0)
		var ev: LevelEval = scene.level_runner.eval
		print("LIVE first_in %.0f zone_peak %d alive %d" % [ev.first_in, ev.zone_peak, ev.alive])
		scene.level_runner.report.queue_free()
		scene.level_runner.exit_level()
		await _until(func() -> bool: return scene.level_runner == null)
		scene.campaign.close()
	quit()
