extends SceneTree
# Fifth round cost: frame times (vsync off) with the lens layer off / on,
# with the magnifier open, and with a species picked out.
# Run: tools/run_test.sh tests/look_d_perf.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _measure(label: String, seconds := 3.0) -> void:
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
	var sorted := times.duplicate()
	sorted.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	print("%-14s avg %.2f ms  p99 %.2f  max %.2f" % [label, avg, sorted[int(sorted.size() * 0.99)], sorted[-1]])


func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene.advance(60.0)
	scene.focus(scene.DISH_CENTER + Vector2(-200, 120), 1.3)
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(900, 500)
	Input.parse_input_event(ev)
	await _measure("warm")
	scene.vignette.visible = false
	await _measure("lens off")
	scene.vignette.visible = true
	await _measure("lens on")
	scene.magnifier.sticky = true
	await _measure("magnifier")
	scene.magnifier.sticky = false
	scene.focus_species = 1
	await _measure("species focus")
	quit()
