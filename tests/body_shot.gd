extends SceneTree
# The body page of 5-2: as first seen (a), a moment after a swap (b), a
# refused removal (c), the page coming up again (d) and settled (e):
# proofs/body_a..e.png.
# Run: tools/run_test.sh tests/body_shot.gd

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
	scene.start_level(Levels.by_id("5-2"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	# The guide's first doing step, its ring round the scope (proofs/body_guide).
	var g: Node = scene.level_runner.tutorial
	if g:
		g._next()
		g._next()
		await create_timer(1.6).timeout
		await _shot("body_guide")
		g._skip()
	await create_timer(1.2).timeout
	await _shot("body_a")
	var b: Control = scene.designer.body_bench
	b.board.hover = Vector2i(9, 4)
	b.move(Vector2i(7, 4), Vector2i(6, 4))
	await create_timer(0.2).timeout
	await _shot("body_b")
	# A block out (it shrinks away), then one refused: it would not touch the body.
	await create_timer(1.0).timeout
	b.remove(Vector2i(4, 3))
	await create_timer(0.7).timeout
	b.place(Vector2i(1, 1), 1)
	await create_timer(0.1).timeout
	await _shot("body_c")
	# The page coming up again.
	scene.designer.show_page("genome")
	await create_timer(0.3).timeout
	scene.designer.show_page("body")
	await create_timer(0.38).timeout
	await _shot("body_d")
	await create_timer(1.5).timeout
	b.board.hover = Vector2i(5, 5)
	b.board.queue_redraw()
	await create_timer(0.1).timeout
	await _shot("body_e")
	quit()
