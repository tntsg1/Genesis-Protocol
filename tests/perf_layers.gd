extends SceneTree
# Measures uncapped frame time with each render layer switched off in turn,
# at a close zoom (the worst case for fill rate).
# Run: tools/run_test.sh tests/perf_layers.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _measure(label: String) -> void:
	for i in 20:
		await process_frame
	var frames := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 1_500_000:
		await process_frame
		frames += 1
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("%-22s %6.2f ms  (%5.1f fps)" % [label, ms, 1000.0 / ms])


func _run() -> void:
	scene.advance(45.0)
	scene.paused = true
	for zoom in [0.8, 2.6]:
		scene.focus(Vector2(1000, 700), zoom)
		print("zoom ", zoom, "  instances ", scene.sim.get_render_count())
		await _measure("all")
		scene.medium.visible = false
		await _measure("no medium")
		scene.medium.visible = true
		scene.cells.visible = false
		await _measure("no cells")
		scene.cells.visible = true
	scene.paused = false
	await _measure("running 1x (%d)" % scene.sim.get_count())
	scene.sim.spawn(0, Vector2(1200, 750), 900, 700.0)
	scene.sim.spawn(1, Vector2(1800, 900), 400, 500.0)
	scene.sim.spawn(2, Vector2(1200, 750), 40, 600.0)
	scene.sim.spawn(3, Vector2(1200, 750), 30, 600.0)
	await _measure("running 1x (%d)" % scene.sim.get_count())
	print("  -> organisms %d, instances %d" % [scene.sim.get_count(), scene.sim.get_render_count()])
	scene.speed = 8.0
	await _measure("running 8x (%d)" % scene.sim.get_count())
	print("  sim ms/tick %.2f" % (scene.sim_usec / 1000.0))
	quit()
