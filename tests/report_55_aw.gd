extends SceneTree
# The last level's report, won: the goal on one line, the stars and 研究点
# clear of the divider, and a way on to the ending (继续 · 观看结局).
# proofs/report55.png; prints whether that button is there and what it does.
# Run: tools/run_test.sh tests/report_55_aw.gd

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
	scene.start_level(Levels.by_id("5-5"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	await create_timer(1.0).timeout
	lr.eval.goal_met = true
	lr.finish()
	await create_timer(4.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/report55.png"))
	var found := false
	for n in lr.report.find_children("*", "", true, false):
		if n is Widgets.Pill and (n as Widgets.Pill).text.begins_with("继续"):
			found = true
	print("REPORT55 ending button: %s" % found)
	# Enter goes on to the ending.
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	lr.report._unhandled_input(ev)
	await create_timer(0.5).timeout
	var ending := false
	for k in scene.get_children():
		if k.get_script() == preload("res://scripts/ui/ending.gd"):
			ending = true
	print("REPORT55 enter plays the ending: %s" % ending)
	quit()
