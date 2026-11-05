extends SceneTree
# Level 23: a long body bitten in two, for real through the game: the first
# split is announced and marked where it happened; proofs/regrow/split.png.
# Run: tools/run_test.sh tests/split_notice.gd

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/regrow"))
	scene.start_level(Levels.by_id("5-4"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	var bench: Control = scene.designer.body_bench
	# One long row: germ, flagellum, ..., the regeneration block in it.
	var line := "GFGFGFRFFFFF"
	var kinds := {"F": Colony.FLAG, "G": Colony.GERM, "R": Colony.REGEN}
	var cells := []
	for i in line.length():
		cells.append([i, 0, kinds[line[i]]])
	bench._commit(cells)
	print("body: ", Colony.stats(bench.cells).n, " blocks")
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 20.0)
	var lr: Node = scene.level_runner
	if lr.tutorial:
		lr.tutorial._skip()
	scene.set_speed(8.0)
	var seen := await _until(func() -> bool: return lr.fired.has("split_first"), 120.0)
	print("first split announced: ", seen, "  at ", lr.eval.colony_stats.get("split_at"))
	if seen:
		scene.set_speed(1.0)
		scene.focus(lr.eval.colony_stats.split_at, 3.0)
		await _until(func() -> bool: return false, 1.2)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/regrow/split.png"))
	quit()
