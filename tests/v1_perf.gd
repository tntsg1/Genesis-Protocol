extends SceneTree
# V1 frame-time check, uncapped (vsync off): average and worst frames over
# 4 s in each situation the player sees. Hitches show up as the 99th
# percentile / max, not the average.
# Run: tools/run_test.sh tests/v1_perf.gd -- --menu

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _measure(label: String, seconds := 4.0) -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 20:
		await process_frame
	var times := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	var t0 := last
	while Time.get_ticks_usec() - t0 < seconds * 1e6:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	print("%-26s avg %5.2f ms (%4.0f fps)  p99 %5.2f ms  max %5.2f ms  organisms %d" % [
		label, avg, 1000.0 / avg, times[int(times.size() * 0.99)], times[times.size() - 1], scene.sim.get_count()])


func _run() -> void:
	scene.advance(40.0)
	await _measure("menu")
	scene.start_experiment()
	await _measure("fly-in + HUD reveal", 2.6)
	await _measure("group 1x")
	scene.set_speed(8.0)
	await _measure("group 8x")
	scene.set_speed(1.0)
	scene.goal_zoom = 0.46
	scene.goal_pos = scene.DISH_CENTER
	await _measure("macro")
	scene.set_view_mode(1)
	await _measure("macro species view")
	scene.set_view_mode(2)
	await _measure("macro population heat")
	scene.set_speed(8.0)
	await _measure("population heat 8x")
	scene.set_speed(1.0)
	scene.set_view_mode(0)
	var pts: PackedVector2Array = scene.sim.get_positions(0)
	scene.focus(pts[0], 9.0)
	scene._select_at(pts[0])
	scene.following = true
	await _measure("micro life scan")
	scene._deselect()
	scene.following = false
	scene.focus(scene.DISH_CENTER, 1.4)
	scene.set_analysis(true)
	await _measure("analysis 1.4x")
	scene.focus(scene.DISH_CENTER, 0.46)
	await _measure("analysis macro")
	scene.set_speed(8.0)
	await _measure("analysis macro 8x")
	scene.set_speed(1.0)
	scene.set_analysis(false)
	scene.focus(scene.DISH_CENTER, 1.0)
	scene.open_designer()
	await _measure("designer dive-in", 2.5)
	await _measure("designer open")
	scene.designer.close()
	await _measure("designer pull-out", 2.2)
	quit()
