extends SceneTree
# Recording of the sixth round (精修 E; a simulated cursor, the real mouse
# is never touched): the dish on the microscope stage, the camera flying in
# over the projected grid, the scan field with its coordinates and data
# tags, the hand stirring the water (wake, eddies, motes), the magnifier.
# Run: tools/run_test.sh tests/record_look_e.gd --write-movie <out.avi> --fixed-fps 60

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
	scene.focus(scene.DISH_CENTER, 0.42)
	_put(Vector2(1500, 300))
	await _idle(2.2)
	# Fly in over the grid.
	scene.fly_to(scene.DISH_CENTER + Vector2(-200, 120), 1.3, 2.0)
	await _glide(Vector2(980, 560), 2.0)
	await _idle(0.6)
	# The scan field drifting over cells: coordinates, data tags.
	await _glide(Vector2(760, 460), 1.4)
	await _idle(0.5)
	await _glide(Vector2(1180, 620), 1.6)
	await _idle(0.5)
	# Stir the water: quick sweeps back and forth, then a loop.
	await _glide(Vector2(700, 700), 0.35)
	await _glide(Vector2(1250, 480), 0.35)
	await _glide(Vector2(820, 380), 0.3)
	for k in 40:
		var a := TAU * k / 40.0
		_put(Vector2(980, 560) + Vector2(cos(a), sin(a)) * 160.0)
		await process_frame
	await _idle(1.4)
	# The magnifier over the giant.
	var g := _nearest(3, scene.cam.position)
	await _glide(_screen(g) + Vector2(10, 0), 0.9)
	await _hold(KEY_ALT, true)
	await _idle(1.6)
	await _glide(_screen(g) + Vector2(150, 60), 1.0)
	await _hold(KEY_ALT, false)
	await _idle(0.6)
	quit()
