extends SceneTree
# Diagnostic teaching (DECISIONS 诊断式教学): past chapter 1 no guide comes
# by itself; a run with a problem shows the diagnosis card. Opens 2-1 (no
# guide expected) and 8-3 (a toxin-less design: the "not used toxin" card),
# shoots proofs/coach_83.png. Prints PASS / FAIL lines.
# Run: tools/run_test.sh tests/coach_check.gd

var scene: Node2D
var fails := 0


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


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _run() -> void:
	scene.start_level(Levels.by_id("2-1"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	await create_timer(1.0).timeout
	_check(scene.level_runner.tutorial == null, "2-1：引导不会自己弹出")
	scene.designer.close()
	await _until(func() -> bool: return scene.designer == null, 10.0)
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null, 10.0)
	scene.start_level(Levels.by_id("8-3"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	_check(scene.level_runner.tutorial == null, "8-3：引导不会自己弹出")
	scene.designer._set_organs(["toxin"])
	await create_timer(0.5).timeout
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	scene.set_speed(8.0)
	var shown := await _until(func() -> bool: return not (scene.hud_root.coach_list as Array).is_empty(), 60.0)
	scene.set_speed(1.0)
	_check(shown, "8-3：出现诊断卡片（%s）" % str((scene.hud_root.coach_list as Array).map(func(h: Dictionary) -> String: return h.title)))
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/coach_83.png"))
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit()
