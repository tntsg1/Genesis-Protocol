extends SceneTree
# Rebinding keys in settings: a new key works in the dish, a key already in
# use swaps, fixed keys are refused, defaults come back. Uses the test
# settings file only. Run: tools/run_test.sh tests/keys_check.gd -- --menu

var scene: Node2D
var fails := 0


func _initialize() -> void:
	Keys.reset()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	root.push_input(e)
	var u := InputEventKey.new()
	u.keycode = k
	u.pressed = false
	root.push_input(u)


func _run() -> void:
	await create_timer(1.2).timeout
	var menu: Control = scene.menu
	menu._toggle_settings()
	await create_timer(0.5).timeout
	menu.capturing = "nutrient"
	menu._capture(KEY_9)
	check(Keys.code("nutrient") == KEY_9, "营养投放 rebinds to 9")
	menu.capturing = "nutrient"
	menu._capture(KEY_6)
	check(Keys.code("nutrient") == KEY_6 and Keys.code("membrane") == KEY_9, "a key in use swaps (membrane now 9)")
	menu.capturing = "nutrient"
	menu._capture(KEY_W)
	check(Keys.code("nutrient") == KEY_6 and menu.capturing == "nutrient", "a fixed key (W) is refused")
	menu._capture(KEY_ESCAPE)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/keys_settings.png"))
	menu._toggle_settings()
	scene.start_experiment()
	await create_timer(3.0).timeout
	scene.iv.points = 200.0
	_key(KEY_6)
	await process_frame
	check(scene.mode == "nutrient", "the new key works in the dish (6 -> nutrient)")
	scene.set_mode("")
	check((scene.hud_root.dock_buttons["nutrient"] as Button).text.ends_with("6"), "the dock shows the new key")
	Keys.reset()
	check(Keys.code("nutrient") == KEY_5, "defaults come back")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
