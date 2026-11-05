extends SceneTree
# The intervention tool tray (lower right) and the new keys: the tray at
# rest, a tool picked with its key (1-4), short of points, the heat tool
# flipped to cold; - / = step the speed; Tab opens and closes the designer.
# Saves proofs/tools_*.png.
# Run: tools/run_test.sh tests/tool_tray_shots.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/tools_%s.png" % name))


func _key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _ok(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		fails += 1


func _run() -> void:
	await _frames(150)
	await _shot("rest")
	await _key(KEY_1)
	await _frames(10)
	_ok(scene.mode == "nutrient", "1 picks nutrients")
	await _key(KEY_3)
	await _frames(5)
	_ok(scene.mode == "heat", "3 picks heat")
	await _key(KEY_3)
	await _frames(10)
	_ok(scene.iv.cold, "3 again flips to cold")
	await _shot("heat_cold")
	await _key(KEY_ESCAPE)
	scene.iv.points = 20.0
	await _frames(20)
	await _shot("short")
	scene.iv.points = 200.0
	var s0: float = scene.speed
	await _key(KEY_EQUAL)
	_ok(scene.speed > s0, "= speeds up")
	await _key(KEY_MINUS)
	await _key(KEY_MINUS)
	_ok(scene.speed < s0, "- slows down")
	await _key(KEY_X)
	await _frames(5)
	_ok(scene.analyzing, "X: analysis")
	await _key(KEY_X)
	await _key(KEY_TAB)
	await _frames(20)
	_ok(scene.designer != null, "Tab opens the designer")
	var d: Control = scene.designer
	while d != null and d.busy:
		await process_frame
	await _frames(10)
	await _key(KEY_TAB)
	await _frames(200)
	_ok(scene.designer == null, "Tab closes it again")
	print("tool_tray_shots: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(fails)
