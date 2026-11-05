extends SceneTree
# Seventh round (主页): hover previews (campaign pins on the ice water, the
# sandbox's scan field across the dish, the stage's scales, the lamp dimming),
# the pointer on the menu's dish, then 沙盒 chosen: the lock-on burst, the
# dissolve along the scan front, the dive racking focus, FOCUS LOCK.
# Synthetic mouse only. Saves proofs/menu_<n>.png.
# Run: tools/run_test.sh tests/menu_fx_shots.gd -- --menu

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/menu_%s.png" % name))
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


func _click(p: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = p
		ev.global_position = p
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		Input.parse_input_event(ev)
		await process_frame


func _run() -> void:
	await _wait(2.5)
	var items: Array = scene.menu.items
	var names := ["campaign", "sandbox", "settings_hover", "quit"]
	for i in 4:
		_put(items[i].get_global_rect().get_center())
		await _wait(1.8 if i < 3 else 1.2)
		print("preview ", scene.menu_preview)
		await _shot("hover_" + names[i])
	# The dish on the right answers the pointer.
	_put(Vector2(1380, 520))
	await _wait(0.8)
	print("pointer shown in menu: ", scene.pointer.shown)
	await _shot("dish_hand")
	# Choose 沙盒.
	var at: Vector2 = items[1].get_global_rect().get_center()
	_put(at)
	await _wait(0.4)
	await _click(at)
	await _wait(0.08)
	await _shot("lock")
	await _wait(0.33)
	await _shot("dissolve")
	await _wait(0.6)
	await _shot("dive")
	await _wait(1.5)
	await _shot("focus_lock")
	await _wait(1.2)
	await _shot("arrived")
	quit()
