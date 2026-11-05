extends SceneTree
# The user's plain-words copy for 1-2 (2026-11-02): the guide's first step on
# the genome page, its third and fourth on the rules page (personality cards,
# temper lines, slot count): proofs/copy12_a..c.png.
# Run: tools/run_test.sh tests/copy_12_aw.gd

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
	scene.start_level(Levels.by_id("1-2"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var g: Node = scene.level_runner.tutorial
	await create_timer(1.4).timeout
	await _shot("copy12_a")
	g._next()
	scene.designer.show_page("rules")
	await create_timer(3.5).timeout
	await _shot("copy12_b")
	g._next()
	await create_timer(1.2).timeout
	await _shot("copy12_c")
	quit()
