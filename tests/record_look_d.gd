extends SceneTree
# Recording of the fifth round (精修 D; a simulated cursor, the real mouse is
# never touched): the lens over the dish, the HUD answering the hand
# (species rows fold out and pick their species out in the dish, a hovered
# cell lights its row, an event row draws its leader line, panels lean
# toward the cursor) and the magnifier (hold Alt, Alt + wheel).
# Over panels the game shows the OS arrow, which a recording does not
# capture, so this test draws a stand-in arrow there.
# Run: tools/run_test.sh tests/record_look_d.gd --write-movie <out.avi> --fixed-fps 60

var scene: Node2D
var cur := Vector2(960, 600)
var arrow: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	var layer := CanvasLayer.new()
	layer.layer = 100
	arrow = Node2D.new()
	arrow.draw.connect(_draw_arrow)
	layer.add_child(arrow)
	root.add_child(layer)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if arrow:
		arrow.queue_redraw()
	return false


func _draw_arrow() -> void:
	if scene == null or scene.pointer.shown:
		return
	var p := cur
	var pts := PackedVector2Array([p, p + Vector2(0, 17), p + Vector2(4.5, 13), p + Vector2(8, 20), p + Vector2(10.5, 19), p + Vector2(7, 12), p + Vector2(12.5, 12)])
	arrow.draw_colored_polygon(pts, Color.WHITE)
	pts.append(p)
	arrow.draw_polyline(pts, Color(0.1, 0.15, 0.2), 1.2, true)


func _frames(s: float) -> int:
	return int(s * 60.0)


func _idle(s: float) -> void:
	for i in _frames(s):
		await process_frame


func _put(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.relative = p - cur
	cur = p
	Input.parse_input_event(ev)


func _glide(to: Vector2, s: float) -> void:
	var from := cur
	var n := _frames(s)
	for i in n:
		var k := float(i + 1) / n
		k = k * k * (3.0 - 2.0 * k)
		_put(from.lerp(to, k))
		await process_frame


func _click() -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = cur
		ev.global_position = cur
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		Input.parse_input_event(ev)
		for i in 5:
			await process_frame


func _hold(k: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = down
	ev.alt_pressed = down and k == KEY_ALT
	Input.parse_input_event(ev)
	await process_frame


func _wheel(up: bool) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = cur
		ev.global_position = cur
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = down
		ev.alt_pressed = true
		Input.parse_input_event(ev)
	await process_frame


func _key(k: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = down
		Input.parse_input_event(ev)
		await process_frame


func _centre_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _nearest(i: int, to: Vector2) -> Vector2:
	var best := Vector2.INF
	for p: Vector2 in scene.sim.get_positions(i):
		if p.distance_to(to) < best.distance_to(to):
			best = p
	return best


func _screen(world: Vector2) -> Vector2:
	return scene.get_viewport().get_canvas_transform() * world


func _run() -> void:
	scene.advance(60.0)
	scene.focus(scene.DISH_CENTER + Vector2(-200, 120), 1.3)
	var hud: Control = scene.hud_root
	hud.conceal()
	await _idle(0.8)
	hud.reveal()
	await _idle(2.2)
	# Over the dish: lock onto a cell, its species' row lights up.
	var c0 := _nearest(0, scene.cam.position + Vector2(-120, -60))
	await _glide(_screen(c0), 1.1)
	await _idle(1.2)
	# Along the species rows: each folds out, the dish picks it out.
	var rows: Array = hud.species_rows
	for i in [0, 1, 5, 3]:
		await _glide(_centre_of(rows[i][3]) + Vector2(30, -6), 0.45)
		await _idle(1.15)
	# Click a row: the camera flies to that species.
	await _click()
	await _idle(1.6)
	# The magnifier: hold Alt over the dish, sweep, Alt + wheel.
	scene.paused = false
	var g := _nearest(3, scene.cam.position)
	await _glide(_screen(g) + Vector2(-140, 40), 0.8)
	await _hold(KEY_ALT, true)
	await _idle(0.6)
	await _glide(_screen(g) + Vector2(20, -10), 1.3)
	for i in 4:
		await _wheel(true)
		await _idle(0.18)
	await _idle(0.8)
	await _glide(_screen(g) + Vector2(160, 60), 1.1)
	await _hold(KEY_ALT, false)
	await _idle(0.5)
	# An event row: its leader line runs to the place.
	var near: Vector2 = _nearest(1, scene.cam.position + Vector2(180, 90))
	hud._event("琥珀 种群繁荣，达到 320", Ui.GOOD, near, false, {species = 1})
	await _idle(0.6)
	await _glide(_centre_of(hud.events_box.get_child(0)), 0.9)
	await _idle(1.8)
	# Panels lean toward the hand.
	var envp: Control = hud.panels["environment"]
	await _glide(envp.get_global_rect().position + Vector2(30, 60), 1.0)
	await _glide(envp.get_global_rect().position + Vector2(envp.size.x - 30, envp.size.y - 60), 1.2)
	await _glide(Vector2(1100, 600), 0.9)
	await _idle(0.6)
	quit()
