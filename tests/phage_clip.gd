extends SceneTree
# A short clip of the level's own close-up, landing to burst and a few seconds
# after, to judge the motion (stills cannot). Run with --write-movie, see
# tools/run_test.sh for the off-screen window.

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, frames := 1800) -> void:
	var n := 0
	while not cond.call() and n < frames:
		await process_frame
		n += 1


func _run() -> void:
	var memory := OS.get_environment("CLIP") == "memory"
	scene.start_level(Levels.by_id("4-2" if memory else "4-1"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	if memory:
		scene.designer.organ_bay.install("crispr")
		scene.designer.deck_editor.set_condition(1, 2, Rules.C_IMMUNE)
		scene.designer.deck_editor.toggle_neg(1, 2)
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	await create_timer(5.0).timeout
	var ps: PackedVector2Array = scene.sim.get_positions(scene.level_runner.sp_index)
	scene.sim.add_phages(ps[0], 40.0, 400 if memory else 70)
	var lr: Node = scene.level_runner
	await _until(func() -> bool: return lr.fired.has("memory_seen" if memory else "phage_seen"))
	print("clip from ", Time.get_ticks_msec())
	if lr.tutorial:
		lr.tutorial._skip()
	var id: int = scene.selected
	if memory:
		await _until(func() -> bool: return lr.eval.lysed >= 1)
		await create_timer(4.0).timeout
		quit()
		return
	await _until(func() -> bool: return scene.sim.get_agent(id).is_empty())
	await create_timer(7.0).timeout
	quit()
