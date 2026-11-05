extends SceneTree
# Frame cost of 5-2 under load: a crowd of bodies, seen whole and seen close.
# Run: tools/run_test.sh tests/perf_colony.gd

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


func _measure(label: String) -> void:
	await create_timer(0.8).timeout
	var ms := []
	var last := Time.get_ticks_usec()
	for k in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		ms.append((now - last) / 1000.0)
		last = now
	ms.sort()
	print("%s: 群体 %d  95%% %.1f ms  最差 %.1f ms  绘制 %d" % [label, scene.sim.get_colony_stats().bodies, ms[int(ms.size() * 0.95)], ms[-1], RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])


func _run() -> void:
	scene.start_level(Levels.by_id("5-2"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	await create_timer(0.5).timeout
	d.body_bench.move(Vector2i(7, 4), Vector2i(6, 4))
	d.body_bench.move(Vector2i(7, 5), Vector2i(5, 4))
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	# A heavy moment on purpose: well past what a normal run reaches on screen.
	scene.sim.spawn(lr.sp_index, Vector2(1100, 1100), 174, 500.0)
	await _measure("普通视图起手")
	scene.focus(Vector2(1100, 1100), 0.62)
	await _measure("全皿")
	scene.focus(Vector2(1100, 1100), 3.0)
	await _measure("放大 ×3")
	scene.focus(Vector2(1100, 1100), 6.0)
	await _measure("放大 ×6")
	# Close on bodies with embryos in them (the most a germ block draws).
	var g: PackedFloat32Array = scene.sim.get_colonies()
	var carrying := 0
	for k in range(0, g.size(), 6):
		if g[k + 5] > 0.5:
			carrying += 1
			if carrying == 1:
				scene.focus(Vector2(g[k + 1], g[k + 2]), 18.0)
	print("怀子的群体 ", carrying)
	await _measure("放大 ×18 对着胚胎")
	quit()
