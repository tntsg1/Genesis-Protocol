extends SceneTree
# A picture of the tag on the first infected cell and the small marks on the
# others, in 4-1, at the camera's usual distance: proofs/tag.png.
# Run: tools/run_test.sh tests/tag_shot.gd

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
	scene.start_level(Levels.by_id("4-1"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	await create_timer(1.0).timeout
	var ps: PackedVector2Array = scene.sim.get_positions(lr.sp_index)
	scene.sim.add_phages(ps[0], 30.0, 400)
	await _until(func() -> bool: return lr.fired.has("phage_seen"), 15.0)
	await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/tag.png"))
	print("tagged ", lr.tagged_id, " following ", scene.following, " zoom ", scene.cam.zoom.x, " speed ", scene.speed)
	quit()
