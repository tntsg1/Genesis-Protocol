extends SceneTree
# M0 look-and-performance capture: warms the dish up, measures real frame
# time at 1x, then saves four framed screenshots into proofs/.
# Run: tools/run_test.sh tests/m0_shots.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _run() -> void:
	scene.advance(45.0)
	for i in 30:
		await process_frame
	# Real-time performance at 1x over the whole dish.
	scene.focus(Vector2(1100, 1100), 0.48)
	var frames := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 4_000_000:
		await process_frame
		frames += 1
	var fps := frames / (float(Time.get_ticks_usec() - t0) / 1e6)
	var st: Dictionary = scene.sim.get_stats()
	print("PERF 1x: %.1f fps with %d organisms (%d instances), sim %.2f ms/tick" % [
		fps, st.count, scene.sim.get_render_count(), scene.sim_usec / 1000.0])
	scene.speed = 8.0
	frames = 0
	t0 = Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 3_000_000:
		await process_frame
		frames += 1
	print("PERF 8x: %.1f fps" % (frames / (float(Time.get_ticks_usec() - t0) / 1e6)))
	scene.speed = 1.0

	await _shot("m0_overview", Vector2(1100, 1100), 0.48)
	await _shot("m0_colony", _densest(scene.sim.get_positions(0), 140.0), 2.6)
	await _shot("m0_predation", _hottest_predator(), 2.3)
	var beasts: PackedVector2Array = scene.sim.get_positions(3)
	if beasts.size() > 0:
		await _shot("m0_beast", beasts[0], 2.2)
	else:
		print("no beast alive for the beast shot")
	print("stats: ", scene.sim.get_stats())
	quit()


func _shot(name: String, pos: Vector2, zoom: float) -> void:
	scene.focus(pos, zoom)
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://proofs/dish_%s.png" % name.trim_prefix("m0_"))
	img.save_png(path)
	print("saved ", path)


func _densest(points: PackedVector2Array, cell: float) -> Vector2:
	var bins := {}
	var best := Vector2.ZERO
	var best_n := 0
	for p in points:
		var k := Vector2i(p / cell)
		bins[k] = bins.get(k, 0) + 1
		if bins[k] > best_n:
			best_n = bins[k]
			best = (Vector2(k) + Vector2(0.5, 0.5)) * cell
	return best


func _hottest_predator() -> Vector2:
	var prey: PackedVector2Array = scene.sim.get_positions(0)
	prey.append_array(scene.sim.get_positions(1))
	var best := Vector2(1100, 1100)
	var best_n := -1
	for p in scene.sim.get_positions(2):
		var n := 0
		for q in prey:
			if p.distance_squared_to(q) < 70.0 * 70.0:
				n += 1
		if n > best_n:
			best_n = n
			best = p
	return best
