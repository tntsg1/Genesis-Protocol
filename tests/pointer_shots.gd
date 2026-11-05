extends SceneTree
# The microscope pointer: free, locked on a cell (tag), a click ripple, the
# selected cell, close up. Saves proofs/pointer_<n>.png.
# Run: tools/run_test.sh tests/pointer_shots.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/pointer_%s.png" % name))


func _wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await process_frame


func _move(screen: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = screen
	ev.global_position = screen
	ev.relative = Vector2(3, 1)
	Input.parse_input_event(ev)


func _button(screen: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = screen
	ev.global_position = screen
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	Input.parse_input_event(ev)


func _screen_of(world: Vector2) -> Vector2:
	return root.get_canvas_transform() * world if false else scene.get_viewport().get_canvas_transform() * world


func _run() -> void:
	scene.advance(60.0)
	scene.focus(scene.DISH_CENTER + Vector2(-260, 140), 1.8)
	await _wait(1.0)
	_move(Vector2(700, 300))
	await _wait(0.4)
	await _shot("free")
	# Lock onto the cell nearest the middle of the view.
	scene.paused = true
	var mid := scene.cam.position as Vector2
	var best := Vector2.INF
	for p: Vector2 in scene.sim.get_positions(0):
		if p.distance_to(mid) < best.distance_to(mid):
			best = p
	var sp := _screen_of(best)
	_move(sp + Vector2(2, 1))
	await _wait(0.6)
	print("hover id ", scene.pointer.hover_id, " shown ", scene.pointer.shown, " pos ", scene.pointer.pos, " sp ", sp, " mode ", scene.mode, " cine ", scene.cine, " find ", scene.sim.find_agent(best, 14.0 / scene.cam.zoom.x), " world ", scene.pointer._to_world(scene.pointer.pos), " best ", best)
	await _shot("hover")
	# Click on open water: ripple.
	var water := Vector2(1200, 640)
	_move(water)
	await _wait(0.1)
	_button(water, true)
	await _wait(0.05)
	_button(water, false)
	await _wait(0.35)
	await _shot("ripple_a")
	await _wait(0.5)
	await _shot("ripple_b")
	# Select the cell.
	sp = _screen_of(scene.sim.get_agent(scene.pointer.hover_id).position) if scene.pointer.hover_id >= 0 else sp
	_move(sp)
	await _wait(0.3)
	_button(sp, true)
	await _wait(0.05)
	_button(sp, false)
	await _wait(1.6)
	print("selected ", scene.selected)
	await _shot("selected")
	scene.paused = false
	# Close up: hover a cell at microscope zoom.
	scene._deselect()
	scene.focus(best, 6.0)
	await _wait(1.0)
	var near := Vector2.INF
	for p: Vector2 in scene.sim.get_positions(0):
		if p.distance_to(scene.cam.position) < near.distance_to(scene.cam.position):
			near = p
	_move(_screen_of(near) + Vector2(4, 0))
	await _wait(0.8)
	await _shot("micro")
	quit()
