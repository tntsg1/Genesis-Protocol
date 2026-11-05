extends SceneTree
# Eighth round (转场): 设置's projector opening and closing, 战役 coming in
# behind the scan curtain, a station change wiping the card, Esc back to the
# menu, 进入实验's descent and lens into the level, and back from the level
# under the veil. Synthetic mouse and keys only. Saves proofs/transit_<n>.png
# and prints the frozen frame's colour against the live one (IrisFx).
# Run: tools/run_test.sh tests/transit_shots.gd -- --menu

var scene: Node2D
var cur := Vector2(960, 540)
var _since := 0.0


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://proofs/transit_%s.png" % name))
	print("shot ", name)
	return img


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
	_put(p)
	await process_frame
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = p
		ev.global_position = p
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
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


func _mean(img: Image, r: Rect2i) -> Color:
	var c := Color(0, 0, 0, 0)
	var n := 0
	for y in range(r.position.y, r.end.y, 6):
		for x in range(r.position.x, r.end.x, 6):
			c += img.get_pixel(x, y)
			n += 1
	return c / n


func _run() -> void:
	await _wait(2.5)
	var items: Array = scene.menu.items
	# 设置: the projector.
	await _click(items[2].get_global_rect().get_center())
	await _wait(0.1)
	await _shot("set_beam")
	await _wait(0.2)
	await _shot("set_sweep")
	await _wait(0.8)
	await _shot("set_open")
	await _click(items[2].get_global_rect().get_center())
	await _wait(0.2)
	await _shot("set_closing")
	await _wait(0.6)
	# 战役: the curtain.
	await _click(items[0].get_global_rect().get_center())
	for t in [0.45, 0.8, 1.15, 2.2]:
		await _wait(t - _since)
		_since = t
		await _shot("camp_%03d" % int(t * 100))
	# A station change.
	await _key(KEY_DOWN)
	await _wait(0.08)
	await _shot("swap_out")
	await _wait(0.22)
	await _shot("swap_in")
	await _wait(0.8)
	await _shot("swap_done")
	await _key(KEY_UP)
	await _wait(0.9)
	# Esc back to the menu, then 战役 again.
	await _key(KEY_ESCAPE)
	await _wait(0.3)
	await _shot("camp_close")
	await _wait(1.6)
	await _shot("menu_back")
	await _click(items[0].get_global_rect().get_center())
	await _wait(2.2)
	# 进入实验.
	var pre := await _shot("pre_enter")
	await _key(KEY_ENTER)
	await _wait(0.25)
	await _shot("descent")
	await _wait(0.27)
	var frozen := await _shot("iris_small")
	var probe := Rect2i(1200, 300, 300, 200)
	print("live ", _mean(pre, probe), "  frozen ", _mean(frozen, probe))
	await _wait(0.4)
	await _shot("iris_mid")
	await _wait(0.4)
	await _shot("iris_wide")
	await _wait(1.0)
	await _shot("focus_lock")
	await _wait(1.2)
	await _shot("designer")
	# Back from the level: the veil under the curtain.
	if scene.designer:
		scene.designer.queue_free()
		scene.designer = null
	await _wait(0.3)
	scene._on_level_exit()
	await _wait(0.35)
	await _shot("exit_veil")
	await _wait(1.6)
	await _shot("exit_camp")
	quit()
