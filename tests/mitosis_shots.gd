extends SceneTree
# Watching a division through the loupe: the lens locks on, closes in, the
# dish slows to a quarter, and the DNA inside unzips, is copied and ridden
# out to the two new nuclei. Synthetic input only. Saves proofs/mitosis_*.png
# and a contact sheet of the lens.
# Run: tools/run_test.sh tests/mitosis_shots.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/mitosis_%s.png" % name))


func _move(screen: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = screen
	ev.global_position = screen
	ev.relative = Vector2(3, 1)
	Input.parse_input_event(ev)


# The id of a cell that has just started dividing, near the dish's middle.
func _fresh_division() -> int:
	# (Birth events fire when the child steps out, so watch some cells.)
	var sim: SimCore = scene.sim
	var ids := []
	for sp in 3:
		for p: Vector2 in sim.get_positions(sp):
			if p.distance_to(scene.DISH_CENTER) < 600.0 and ids.size() < 160:
				var id := sim.find_agent(p, 2.0)
				if id >= 0:
					ids.append(id)
	for tries in 900:
		scene.advance(scene.TICK)
		for id in ids:
			var d: float = float(sim.get_agent(id).get("dividing", -1.0))
			if d >= 0.0 and d < 0.05:
				return id
	return -1


func _run() -> void:
	scene.advance(40.0)
	var id := _fresh_division()
	print("dividing cell ", id)
	if id < 0:
		quit(1)
		return
	# Held still while the camera flies in and the lens opens over it.
	scene.paused = true
	var p: Vector2 = scene.sim.get_agent(id).position
	scene.focus(p, 3.2)
	for i in 90:
		await process_frame
	var mid: Vector2 = scene.get_viewport().get_canvas_transform() * (scene.sim.get_agent(id).position as Vector2)
	_move(mid)
	scene.magnifier.sticky = true
	for i in 30:
		await process_frame
	print("split at start ", scene.sim.get_agent(id).get("dividing"))
	scene.paused = false
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < 11000:
		await process_frame
		var info: Dictionary = scene.sim.get_agent(id)
		if not info.is_empty():
			_move(scene.get_viewport().get_canvas_transform() * (info.position as Vector2))
		if (Time.get_ticks_msec() - t0) > n * 650:
			await _shot("%02d" % n)
			print("t %.1f watch %d split %.2f observe %.2f power %.1f" % [(Time.get_ticks_msec() - t0) / 1000.0, scene.magnifier.watch_id, scene.magnifier.watch_split, scene.observe, scene.magnifier.power()])
			n += 1
	quit()
