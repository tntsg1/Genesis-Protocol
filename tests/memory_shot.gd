extends SceneTree
# Close-up frames of a cell beating a phage in 4-2, and a real run of the
# guided plan. Shots go to proofs/memory/. Run: tools/run_test.sh tests/memory_shot.gd

var scene: Node2D
var dir := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/memory")
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])


func _run() -> void:
	scene.start_level(Levels.by_id("4-2"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	d.organ_bay.install("crispr")
	d.deck_editor.set_condition(1, 2, Rules.C_IMMUNE)
	d.deck_editor.toggle_neg(1, 2)
	print("deck ", d.deck_editor.deck.map(func(c: Dictionary) -> String: return Rules.card_text(c)))
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	await create_timer(5.0).timeout
	var ps: PackedVector2Array = scene.sim.get_positions(lr.sp_index)
	scene.sim.add_phages(ps[0], 50.0, 200)
	await _until(func() -> bool: return lr.fired.has("memory_seen"), 40.0)
	var id: int = lr.tagged_id
	scene.selected = id
	scene.gone_timer = 0.0
	scene.following = true
	scene.goal_zoom = 16.0
	print("following ", id, " ", scene.following)
	# (The close-up runs at 0.6x.)
	var at := 0.0
	for m: float in [1.0, 2.0, 3.4, 4.6, 5.6, 6.8, 7.6]:
		await create_timer((m - at) / 0.6).timeout
		at = m
		await _shot("m_%04.1f" % m)
	await _until(func() -> bool: return lr.eval.immune >= 1, 6.0)
	await create_timer(0.8).timeout
	await _shot("m_done")
	await create_timer(4.0).timeout
	scene.set_speed(8.0)
	await _until(func() -> bool: return lr.eval.t >= 200.0, 40.0)
	scene.set_speed(1.0)
	await _shot("m_before")
	scene.set_speed(8.0)
	await _until(func() -> bool: return lr.eval.t >= 250.0, 20.0)
	scene.set_speed(1.0)
	await _shot("m_storm")
	scene.set_speed(8.0)
	await _until(func() -> bool: return is_instance_valid(lr.report), 30.0)
	await create_timer(7.0).timeout
	await _shot("m_report")
	print("end: 星 ", lr.eval.stars(), " 种群 ", lr.eval.alive, " 有记忆 ", lr.eval.immune, " 撑破 ", lr.eval.lysed)
	quit()
