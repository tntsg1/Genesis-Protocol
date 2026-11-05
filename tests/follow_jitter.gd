extends SceneTree
# Follow at high zoom (playtest: "放大跟随时一顿一顿"): the followed cell's
# spot on screen should stay put frame to frame, and the selection marks
# should sit on the cell as drawn. Prints how far the cell moves on screen
# per frame (should be ~0 once locked on) at 1x and 3x.
# Run: tools/run_test.sh tests/follow_jitter.gd

var scene: Node2D
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _measure(label: String, seconds: float) -> float:
	var jumps := []
	var prev := Vector2.INF
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		if scene.selected < 0:
			break
		var p: Vector2 = scene.get_viewport().get_canvas_transform() * scene.last_pos
		if prev.is_finite():
			jumps.append(p.distance_to(prev))
		prev = p
	jumps.sort()
	var worst: float = jumps.back() if jumps.size() > 0 else -1.0
	print("%-6s frames %d  cell moves on screen: median %.2f px  worst %.2f px" % [label, jumps.size(), jumps[jumps.size() / 2] if jumps.size() > 0 else -1.0, worst])
	return worst


func _run() -> void:
	await create_timer(4.0).timeout
	scene.selected = scene.sim.find_agent(scene.cam.position, 400.0)
	scene.toggle_track()
	scene.goal_zoom = 10.0
	await create_timer(3.0).timeout # caught up and zoomed in
	var w1 := await _measure("1x", 3.0)
	check(w1 >= 0.0 and w1 < 1.5, "1x: the followed cell holds still on screen (worst %.2f px a frame)" % w1)
	scene.set_speed(3.0)
	await create_timer(1.0).timeout
	var w3 := await _measure("3x", 3.0)
	check(w3 >= 0.0 and w3 < 1.5, "3x: the followed cell holds still on screen (worst %.2f px a frame)" % w3)
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
