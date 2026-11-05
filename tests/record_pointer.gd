extends SceneTree
# Recording of the microscope pointer (a simulated cursor; the real mouse is
# never touched): gliding over the water (faint ripples), locking onto a
# swimming cell (tag), hopping to another, clicks on the water, selecting a
# cell, sweeping across a crowd.
# Run: tools/run_test.sh tests/record_pointer.gd --write-movie <out.avi> --fixed-fps 60

var scene: Node2D
var cur := Vector2(200, 700)


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _frames(s: float) -> int:
	return int(s * 60.0)


func _screen_of(world: Vector2) -> Vector2:
	return scene.get_viewport().get_canvas_transform() * world


func _put(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.relative = p - cur
	cur = p
	Input.parse_input_event(ev)


func _button(down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = cur
	ev.global_position = cur
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	Input.parse_input_event(ev)


func _click() -> void:
	_button(true)
	for i in 4:
		await process_frame
	_button(false)


# Glide the cursor to a point (or a moving target given as a Callable).
func _glide(to: Variant, s: float) -> void:
	var from := cur
	var n := _frames(s)
	for i in n:
		var k := float(i + 1) / n
		k = k * k * (3.0 - 2.0 * k)
		var target: Vector2 = to.call() if to is Callable else to
		_put(from.lerp(target, k) + Vector2(0, sin(k * PI) * -40.0))
		await process_frame


func _hold(to: Callable, s: float) -> void:
	for i in _frames(s):
		_put(cur.lerp(to.call(), 0.25))
		await process_frame


func _cell_near(screen: Vector2, skip := -1) -> int:
	var w: Vector2 = scene.get_viewport().get_canvas_transform().affine_inverse() * screen
	var best := -1
	var bd := INF
	for r in 6:
		var id: int = scene.sim.find_agent(w + Vector2.from_angle(r * 1.1) * r * 30.0, 30.0 + r * 20.0)
		if id >= 0 and id != skip:
			var d := (scene.sim.get_agent(id).position as Vector2).distance_to(w)
			if d < bd:
				bd = d
				best = id
	return best


func _track(id: int) -> Callable:
	return func() -> Vector2:
		var a: Dictionary = scene.sim.get_agent(id)
		return _screen_of(a.position) + Vector2(3, 2) if not a.is_empty() else cur


func _run() -> void:
	scene.advance(60.0)
	scene.focus(scene.DISH_CENTER + Vector2(-260, 140), 2.2)
	for i in 30:
		await process_frame
	_put(cur)
	# Over the water: ripples trail the hand.
	await _glide(Vector2(760, 420), 1.4)
	await _glide(Vector2(560, 620), 0.9)
	# Lock onto a swimming cell, hold on as it swims.
	var a := _cell_near(Vector2(960, 540))
	await _glide(_track(a), 0.8)
	await _hold(_track(a), 1.8)
	# Hop to another.
	var b := _cell_near(_screen_of(scene.sim.get_agent(a).position) + Vector2(220, -60), a)
	if b >= 0:
		await _glide(_track(b), 0.6)
		await _hold(_track(b), 1.4)
	# Clicks on open water.
	await _glide(Vector2(700, 760), 0.7)
	await _click()
	for i in _frames(0.9):
		await process_frame
	await _glide(Vector2(880, 700), 0.4)
	await _click()
	for i in _frames(1.4):
		await process_frame
	# Select a cell: the camera dives after it.
	var c := _cell_near(Vector2(1000, 520))
	await _glide(_track(c), 0.7)
	await _hold(_track(c), 0.4)
	await _click()
	for i in _frames(2.6):
		await process_frame
	await _glide(Vector2(1300, 380), 0.8)
	for i in _frames(0.8):
		await process_frame
	# Back out, sweep across a crowd.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	scene.focus(scene.DISH_CENTER + Vector2(-60, 60), 1.4)
	for i in _frames(1.0):
		await process_frame
	await _glide(Vector2(1500, 520), 2.4)
	for i in _frames(0.6):
		await process_frame
	quit()
