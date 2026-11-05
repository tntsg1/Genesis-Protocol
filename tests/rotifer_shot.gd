extends SceneTree
# 5-5 in play, the camera on the guardian: proofs/boss/r_close.png (its
# corona and the water it pulls), r_chew.png (something in its mouth), r_far.png.
# Run: tools/run_test.sh tests/rotifer_shot.gd

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/boss"))
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/boss/%s.png" % name))


func _boss() -> PackedFloat32Array:
	return scene.sim.get_rotifers(1.0)


func _follow(zoom: float, secs: float) -> void:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < end:
		var r := _boss()
		if r.size() >= 6:
			scene.focus(Vector2(r[0], r[1]) + Vector2.from_angle(r[2]) * 120.0, zoom)
		await process_frame


func _run() -> void:
	scene.start_level(Levels.by_id("5-5"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	await _follow(3.2, 2.0)
	await _shot("r_close")
	scene.set_speed(3.0)
	await _until(func() -> bool: return _boss().size() >= 6 and _boss()[4] > 0.2, 90.0)
	scene.set_speed(1.0)
	await _follow(3.2, 0.3)
	await _shot("r_chew")
	scene.focus(Vector2(1100, 1100), 0.62)
	await create_timer(0.5).timeout
	await _shot("r_far")
	quit()
