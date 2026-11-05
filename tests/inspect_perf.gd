extends SceneTree
# Frame-time probe for the stutter the player feels on picking a cell and on
# F (follow): 2 s idle, 2 s after picking a cell (zoomed in: the life scan,
# the callouts), 2 s after F. Prints the worst frames and how many went over
# 20 ms in each phase.
# Run: tools/run_test.sh tests/inspect_perf.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _frames(label: String, seconds: float) -> void:
	var times := []
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var t := Time.get_ticks_usec()
	while Time.get_ticks_msec() < end:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - t) / 1000.0)
		t = now
	var worst := times.duplicate()
	worst.sort()
	worst.reverse()
	var over := times.filter(func(v: float) -> bool: return v > 20.0).size()
	var avg := 0.0
	for v: float in times:
		avg += v
	print("%-8s frames %3d  avg %5.1f ms  worst %s  >20ms: %d" % [label, times.size(), avg / maxf(times.size(), 1),
		str(worst.slice(0, 5).map(func(v: float) -> String: return "%.0f" % v)), over])
	print("         first 12: %s" % str(times.slice(0, 12).map(func(v: float) -> String: return "%.0f" % v)))


func _run() -> void:
	await create_timer(4.0).timeout
	scene.goal_zoom = 1.5
	await create_timer(2.0).timeout
	await _frames("idle", 1.5)
	# Selected at group zoom: no life scan yet.
	scene.selected = scene.sim.find_agent(scene.cam.position, 300.0)
	await _frames("sel-grp", 1.5)
	# Zoom in: the tier turns micro, the life scan comes up.
	scene.goal_zoom = 2.6
	await _frames("micro", 2.0)
	scene.toggle_track()
	await _frames("follow", 2.0)
	scene._deselect()
	await _frames("after", 1.0)
	scene.selected = scene.sim.find_agent(scene.cam.position, 300.0)
	await _frames("select2", 1.5)
	quit()
