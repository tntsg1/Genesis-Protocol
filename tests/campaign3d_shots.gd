extends SceneTree
# Ninth round (战役页 3D 模型): the block building behind the scan curtain,
# settled, a station change, a drag turning it, 进入实验's dive down the
# shaft and the lens into the level. Synthetic mouse and keys only. Saves
# proofs/c3d_<n>.png and prints the frame time while the page is up.
# Run: tools/run_test.sh tests/campaign3d_shots.gd -- --menu

var scene: Node2D
var cur := Vector2(960, 540)


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/c3d_%s.png" % name))
	print("shot ", name)


func _wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await process_frame


func _put(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.relative = p - cur
	cur = p
	Input.parse_input_event(ev)


func _button(p: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = p
	ev.global_position = p
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	Input.parse_input_event(ev)


func _click(p: Vector2) -> void:
	_put(p)
	await process_frame
	_button(p, true)
	await process_frame
	_button(p, false)
	await process_frame


func _key(k: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = down
		Input.parse_input_event(ev)
		await process_frame


func _run() -> void:
	await _wait(2.5)
	await _click(scene.menu.items[0].get_global_rect().get_center())
	await _wait(0.55)
	await _shot("build_a")
	await _wait(0.4)
	await _shot("build_b")
	await _wait(0.4)
	await _shot("build_c")
	await _wait(1.6)
	await _shot("settled")
	# Frame time with the page up.
	var t0 := Time.get_ticks_usec()
	for i in 60:
		await process_frame
	print("frame ms ", (Time.get_ticks_usec() - t0) / 60000.0)
	var m: Control = scene.campaign.section
	await _click(m.get_global_transform() * m.station_pos(3))
	await _wait(0.9)
	await _shot("station4")
	# Drag to turn it.
	var from := m.get_global_transform() * Vector2(150, 300)
	_put(from)
	await process_frame
	_button(from, true)
	for k in 20:
		_put(from + Vector2(-8.0 * k, 2.0 * k))
		await process_frame
	_button(cur, false)
	await _wait(0.3)
	await _shot("dragged")
	_put(Vector2(1500, 900))
	await _click(m.get_global_transform() * m.station_pos(0))
	await _wait(1.2)
	await _key(KEY_ENTER)
	await _wait(0.35)
	await _shot("dive_a")
	await _wait(0.35)
	await _shot("dive_b")
	await _wait(0.35)
	await _shot("lens")
	await _wait(2.4)
	await _shot("level")
	quit()
