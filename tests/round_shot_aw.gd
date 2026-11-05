extends SceneTree
# Round bodies in the dish (5-4), close up and with a hunter about, and the
# leftover check: on a second try, while the capsule opens, the last try's
# bodies must be gone. proofs/round_a..c.png; prints how many blocks the
# colony layer still draws during the release.
# Run: tools/run_test.sh tests/round_shot_aw.gd

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


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


func _layer() -> Node:
	for n in scene.find_children("*", "Node2D", true, false):
		if n.get_script() == preload("res://scripts/colony_layer.gd"):
			return n
	return null


func _release() -> void:
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	await create_timer(0.4).timeout
	scene.designer.release()


func _run() -> void:
	scene.start_level(Levels.by_id("5-4"))
	await _release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.set_speed(3.0)
	await create_timer(6.0).timeout
	scene.set_speed(1.0)
	var cs: PackedFloat32Array = scene.sim.get_colonies()
	scene.focus(Vector2(cs[1], cs[2]), 9.0)
	await create_timer(0.8).timeout
	await _shot("round_a")
	scene.focus(Vector2(cs[1], cs[2]), 4.0)
	await create_timer(0.8).timeout
	await _shot("round_b")
	# A second try: back to the designer, release again, look mid-release.
	scene.level_runner.retry() if scene.level_runner.has_method("retry") else scene.start_level(Levels.by_id("5-4"))
	await _release()
	await _until(func() -> bool: return scene.level_runner.phase == "release", 10.0)
	await create_timer(0.3).timeout
	var lay := _layer()
	print("ROUND release phase=%s blocks drawn=%d skins drawn=%d" % [scene.level_runner.phase,
		lay.blocks.multimesh.visible_instance_count, lay.skin.multimesh.visible_instance_count])
	await _shot("round_c")
	quit()
