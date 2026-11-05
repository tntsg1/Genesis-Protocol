extends SceneTree
# The body page of 5-4: the guide pointing at the germ tile (a), the
# body with the germ and regeneration blocks put in (b): proofs/body54_a..b.png.
# Run: tools/run_test.sh tests/body_shot_54.gd

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


func _run() -> void:
	scene.start_level(Levels.by_id("5-4"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var tut: Node = scene.level_runner.tutorial
	# Through the two talking cards to the first step.
	for k in 2:
		await create_timer(0.6).timeout
		if tut and tut.has_method("_next"):
			tut._next()
	await create_timer(1.2).timeout
	await _shot("body54_a")
	var b: Control = scene.designer.body_bench
	var lo := Vector2i(100, 100)
	for c: Array in b.cells:
		lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
	b.place(lo + Vector2i(1, 1), Colony.GERM) # (the store back to a germ block)
	b.place(lo + Vector2i(1, 0), Colony.REGEN) # (beside the top back armour corner)
	await create_timer(1.6).timeout
	await _shot("body54_b")
	quit()
