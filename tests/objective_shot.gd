extends SceneTree
# Levels 22-23 in play with their objective bars (hunters, next wave, famine,
# stores, regrowth): the guide's body released, run fast to O_T seconds
# (default 130), then a shot to proofs/colony_bar_<id>.png.
# Env O_LEVEL (5-3). Run: tools/run_test.sh tests/objective_shot.gd

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, frames := 3600) -> void:
	var n := 0
	while not cond.call() and n < frames:
		await process_frame
		n += 1


func _run() -> void:
	var lid := OS.get_environment("O_LEVEL") if OS.get_environment("O_LEVEL") != "" else "5-3"
	var at := float(OS.get_environment("O_T")) if OS.get_environment("O_T") != "" else 130.0
	scene.start_level(Levels.by_id(lid))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	var pc: GDScript = preload("res://tests/play_ch5.gd")
	var rows: Array = pc.GUIDES[lid]
	var bench: Control = scene.designer.body_bench
	var kinds := {"F": Colony.FLAG, "G": Colony.GERM, "A": Colony.ARMOR, "S": Colony.STORE, "R": Colony.REGEN}
	var lo := Vector2i(100, 100)
	for c: Array in bench.cells:
		lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
	for j in rows.size():
		for i in (rows[j] as String).length():
			if int(Colony.type_at(bench.cells, lo.x + i, lo.y + j)) != int(kinds[rows[j][i]]):
				bench.place(lo + Vector2i(i, j), kinds[rows[j][i]])
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.set_speed(8.0)
	await _until(func() -> bool: return scene.level_runner.eval.t >= at, 6000)
	scene.set_speed(1.0)
	await _until(func() -> bool: return false, 30)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/colony_bar_%s.png" % lid))
	print("objective shot: ", scene.level_runner.env_text() if scene.level_runner.has_method("env_text") else "done")
	quit()
