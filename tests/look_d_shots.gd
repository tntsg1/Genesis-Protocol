extends SceneTree
# Fifth round (精修 D): the lens over the dish, the lens under the panels,
# the HUD answering the hand (species row folds out and picks its species
# out in the dish, a hovered cell lights its row, an event row draws a
# leader to its place, panels lean toward the cursor) and the magnifier.
# Synthetic mouse / key events only; the real pointer is never touched.
# Saves proofs/lookd_<n>.png.
# Run: tools/run_test.sh tests/look_d_shots.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/lookd_%s.png" % name))
	print("shot ", name)


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


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _screen_of(world: Vector2) -> Vector2:
	return scene.get_viewport().get_canvas_transform() * world


func _run() -> void:
	scene.advance(60.0)
	scene.focus(scene.DISH_CENTER + Vector2(-200, 120), 1.3)
	await _wait(2.4)
	_move(Vector2(960, 560))
	await _wait(0.4)
	await _shot("settled")
	# Species row: fold out + pick the species out in the dish.
	var hud: Control = scene.hud_root
	var row: Control = hud.species_rows[1][3]
	var rp: Vector2 = row.get_global_rect().get_center() + Vector2(40, 0)
	_move(rp)
	await _wait(0.8)
	print("mouse ", hud.get_global_mouse_position(), " row ", row.get_global_rect(), " vis ", hud.panels["species"].visible, " a ", hud.panels["species"].modulate.a, " rev ", hud.revealed)
	print("hover row ", hud.hover_row, " focus ", scene.focus_species, " amt ", scene.focus_amt)
	await _shot("species_row")
	# A cell: its row lights.
	scene.paused = true
	var mid := scene.cam.position as Vector2
	var best := Vector2.INF
	for p: Vector2 in scene.sim.get_positions(0):
		if p.distance_to(mid) < best.distance_to(mid):
			best = p
	_move(_screen_of(best) + Vector2(2, 1))
	await _wait(0.7)
	await _shot("cell_link")
	# Magnifier: hold Alt over the cell, then over the giant.
	_key(KEY_ALT, true)
	await _wait(0.6)
	await _shot("lens")
	var giants: PackedVector2Array = scene.sim.get_positions(3)
	if giants.size() > 0:
		var g := giants[0]
		for q in giants:
			if q.distance_to(mid) < g.distance_to(mid):
				g = q
		_move(_screen_of(g) + Vector2(30, 10))
		await _wait(0.5)
		await _shot("lens_giant")
	_key(KEY_ALT, false)
	await _wait(0.4)
	scene.paused = false
	# Event row: leader line.
	hud._event("测试事件：琥珀 种群繁荣", Ui.GOOD, best, false, {})
	await _wait(0.6)
	var ev_row: Control = hud.events_box.get_child(0)
	_move(ev_row.get_global_rect().get_center())
	await _wait(0.8)
	await _shot("event_link")
	# Lean: cursor at the right edge of the environment panel.
	var envp: Control = hud.panels["environment"]
	_move(envp.get_global_rect().position + Vector2(envp.size.x - 10, 40))
	await _wait(0.6)
	await _shot("lean")
	quit()
