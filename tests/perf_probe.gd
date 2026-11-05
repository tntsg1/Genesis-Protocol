extends SceneTree
# Quick frame-time probe for shader work: group view, a close-up and the
# designer open (sim paused). Run: tools/run_test.sh tests/perf_probe.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _measure(label: String, seconds := 3.0) -> void:
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
	print("%-14s avg %5.2f ms  p99 %5.2f ms" % [label, avg, times[int(times.size() * 0.99)]])


func _run() -> void:
	var lk := OS.get_environment("PROBE_LOOK")
	if lk == "off":
		scene.set_look2(false)
	elif lk == "noglow":
		scene.world_env.glow_enabled = false
	elif lk == "glowonly":
		scene.set_look2(false)
		scene.world_env.glow_enabled = true
	scene.advance(float(OS.get_environment("PROBE_T")) if OS.get_environment("PROBE_T") != "" else 40.0)
	scene.focus(scene.DISH_CENTER, 1.4)
	await _measure("group")
	var pts: PackedVector2Array = scene.sim.get_positions(0)
	scene.focus(pts[0], 9.0)
	await _measure("micro")
	scene.focus(scene.DISH_CENTER, 1.0)
	scene.open_designer()
	while scene.designer == null or scene.designer.busy:
		await process_frame
	await _measure("designer")
	quit()
