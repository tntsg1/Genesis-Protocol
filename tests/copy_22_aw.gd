extends SceneTree
# The user's plain-words copy for the 2-2 guide (2026-11-02): steps 1, 2, the
# speed step met (its 完成 line), step 4 on the rules page and step 6:
# proofs/copy22_a..e.png.
# Run: tools/run_test.sh tests/copy_22_aw.gd

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
	scene.start_level(Levels.by_id("2-2"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var g: Node = scene.level_runner.tutorial
	var d: Control = scene.designer
	await create_timer(2.5).timeout
	await _shot("copy22_a")
	g._next()
	await create_timer(3.0).timeout
	await _shot("copy22_b")
	g._next()
	await create_timer(0.5).timeout
	# Speed up to 3: the step is met and says why.
	d.genes[0] = 3.0
	await create_timer(2.5).timeout
	await _shot("copy22_c")
	await _until(func() -> bool: return g.count_label.text.contains("第 4"), 12.0)
	d.show_page("rules")
	await create_timer(3.0).timeout
	await _shot("copy22_d")
	g._next()
	g._next()
	d.show_page("genome")
	await create_timer(3.5).timeout
	await _shot("copy22_e")
	quit()
