extends SceneTree
# The level briefing (scripts/ui/briefing.gd): past chapter 1, a card with the
# goal and the level's features comes before the designer; not on a retry,
# not in chapter 1; the designer's 本关要点 shows the same. Shoots
# proofs/briefing_1.png, briefing_2.png, briefing_points.png.
# Run: tools/run_test.sh tests/briefing_check.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	Levels.force_briefing = true
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


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


func _run() -> void:
	scene.start_level(Levels.by_id("8-3"))
	var ok := await _until(func() -> bool: return scene.level_runner.briefing != null, 15.0)
	_check(ok and scene.designer == null, "8-3：设计器之前先出简报")
	await create_timer(1.0).timeout
	await _shot("briefing_1")
	var b: Node = scene.level_runner.briefing
	b.next_b.pressed.emit()
	await create_timer(0.6).timeout
	await _shot("briefing_2")
	b.next_b.pressed.emit()
	_check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 15.0), "开始设计：设计器打开")
	scene.designer.toggle_points()
	await create_timer(0.8).timeout
	await _shot("briefing_points")
	_check(scene.designer.points_panel != null, "设计器里的「本关要点」")
	scene.designer.toggle_points()
	var last: Dictionary = scene.designer._design()
	scene.designer.close()
	await _until(func() -> bool: return scene.designer == null, 10.0)
	# A retry (a last design): straight to the designer.
	var lr: Node = scene.level_runner
	lr.start(lr.level, last)
	await create_timer(2.0).timeout
	_check(lr.briefing == null, "重试不再弹简报")
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit()
