extends SceneTree
# Campaign demo for a recording (movie writer, fixed 60 fps): the menu, the
# ice-shell level page, level 1's commission, the designer under the level's
# rules with the guide, the prediction, the release and the run (a nutrient
# drop on the way), the stars, the report and a control experiment.
# Run: tools/run_test.sh tests/record_campaign.gd --write-movie <out.avi> --fixed-fps 60 -- --menu

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _until(cond: Callable, limit := 30.0) -> void:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _run() -> void:
	await _wait(2.0)
	scene.menu._set_focus(0)
	await _wait(0.6)
	scene.menu._activate(0)
	await _wait(2.2)
	scene.campaign._select(1)
	await _wait(1.0)
	scene.campaign._select(0)
	await _wait(1.6)
	scene.campaign._start()
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	await _wait(2.2)
	var tut: Node = scene.level_runner.tutorial
	if tut:
		tut._next()
	await _wait(1.6)
	var d: Control = scene.designer
	for k_v in [[0, 3.0], [0, 4.0], [1, 1.0], [4, 2.0]]:
		d.gene_sliders[k_v[0]].changed.emit(k_v[1])
		d.gene_sliders[k_v[0]].value = k_v[1]
		await _wait(0.5)
	await _wait(1.0)
	if tut:
		tut._next()
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "predict")
	await _wait(1.0)
	scene.level_runner.card._pick(1)
	await _wait(0.8)
	scene.level_runner.card._confirm()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	await _wait(2.0)
	if tut:
		tut._next()
	scene.set_speed(3.0)
	await _wait(2.0)
	# A nutrient drop on the way.
	var mid: Vector2 = Levels.ALL[0].release.at.lerp(Levels.LIGHT_ZONE.center, 0.45)
	scene.fly_to(mid, 0.8, 1.2)
	await _wait(1.3)
	scene.iv.select("nutrient")
	await _wait(0.5)
	scene.iv.place("nutrient", mid)
	scene.set_mode("")
	if tut:
		tut._skip()
	await _wait(2.0)
	scene.fly_to(Levels.LIGHT_ZONE.center, 0.7, 1.6)
	scene.set_speed(8.0)
	await _until(func() -> bool: return scene.level_runner.phase == "done", 120.0)
	await _wait(4.5)
	var rep: Control = scene.level_runner.report
	rep._run_control(0)
	await _until(func() -> bool: return rep.control_task < 0 and not rep.bars.results.is_empty(), 60.0)
	await _wait(3.0)
	quit()
