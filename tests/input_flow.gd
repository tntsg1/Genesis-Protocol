extends SceneTree
# The real player path: main menu -> 开始实验 -> move the view with every
# input. Events are pushed into the viewport (the OS mouse is never moved).
# Run: tools/run_test.sh tests/input_flow.gd -- --menu

var scene: Node2D
var fails := 0
var _last := Vector2.ZERO


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _btn(at: Vector2, idx: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = pressed
	e.position = at
	e.global_position = at
	e.button_mask = (1 << (idx - 1)) if pressed else 0
	root.push_input(e)


func _move(at: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = at - _last
	_last = at
	e.position = at
	e.global_position = at
	e.button_mask = mask
	root.push_input(e)


func drag(idx: MouseButton, from: Vector2, to: Vector2) -> void:
	scene.focus(scene.DISH_CENTER, 1.0)
	await process_frame
	_move(from, 0)
	await process_frame
	_btn(from, idx, true)
	await process_frame
	for k in range(1, 21):
		_move(from.lerp(to, k / 20.0), 1 << (idx - 1))
		await process_frame
	_btn(to, idx, false)
	await create_timer(0.6).timeout


func key(code: Key, secs: float) -> void:
	scene.focus(scene.DISH_CENTER, 1.0)
	await process_frame
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await create_timer(secs).timeout
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await create_timer(0.5).timeout


func _run() -> void:
	await create_timer(1.5).timeout
	scene.start_experiment()
	await create_timer(3.5).timeout
	print("in_menu ", scene.in_menu, " cine ", scene.cine, " hovered ", root.gui_get_hovered_control())
	var c0: Vector2 = scene.DISH_CENTER
	await drag(MOUSE_BUTTON_LEFT, Vector2(1000, 600), Vector2(800, 600))
	var dx: float = scene.cam.position.x - c0.x
	check(dx > 50.0, "left drag pans (%.0f)" % dx)
	c0 = scene.DISH_CENTER
	await drag(MOUSE_BUTTON_RIGHT, Vector2(1000, 600), Vector2(800, 600))
	dx = scene.cam.position.x - c0.x
	check(dx > 50.0, "right drag pans (%.0f)" % dx)
	c0 = scene.DISH_CENTER
	await drag(MOUSE_BUTTON_MIDDLE, Vector2(1000, 600), Vector2(800, 600))
	dx = scene.cam.position.x - c0.x
	check(dx > 50.0, "middle drag pans (%.0f)" % dx)
	c0 = scene.DISH_CENTER
	await key(KEY_D, 0.5)
	dx = scene.cam.position.x - c0.x
	check(dx > 50.0, "D pans right (%.0f)" % dx)
	c0 = scene.DISH_CENTER
	await key(KEY_LEFT, 0.5)
	dx = scene.cam.position.x - c0.x
	check(dx < -50.0, "Left arrow pans left (%.0f)" % dx)
	# A click on a cell selects it; a right click drops nutrient.
	scene.focus(scene.DISH_CENTER, 1.0)
	await create_timer(0.3).timeout
	var pts: PackedVector2Array = scene.sim.get_positions(0)
	var cell := pts[0]
	scene.focus(cell, 2.0)
	await create_timer(0.2).timeout
	var screen: Vector2 = root.get_canvas_transform() * scene.sim.get_agent(scene.sim.find_agent(cell, 30.0)).position
	_move(screen, 0)
	_btn(screen, MOUSE_BUTTON_LEFT, true)
	await process_frame
	_btn(screen, MOUSE_BUTTON_LEFT, false)
	await create_timer(0.3).timeout
	check(scene.selected >= 0, "left click on a cell selects it")
	scene._deselect()
	var before: int = scene.sim.get_algae_count()
	var e_before: float = scene.sim.energy_audit().input
	_btn(Vector2(900, 500), MOUSE_BUTTON_RIGHT, true)
	await process_frame
	_btn(Vector2(900, 500), MOUSE_BUTTON_RIGHT, false)
	await create_timer(0.3).timeout
	check(scene.sim.energy_audit().input > e_before, "right click drops nutrient")
	# Minimap click jumps the camera.
	var map: Control = scene.hud_root.minimap
	var mp: Vector2 = map.get_global_rect().position + map.size * Vector2(0.5, 0.25)
	_move(mp, 0)
	_btn(mp, MOUSE_BUTTON_LEFT, true)
	await process_frame
	_btn(mp, MOUSE_BUTTON_LEFT, false)
	await create_timer(1.0).timeout
	var want: Vector2 = scene.hud_root._map_to_world(map.size * Vector2(0.5, 0.25))
	check(scene.cam.position.distance_to(want) < 40.0, "clicking the minimap jumps the camera (%.0f off)" % scene.cam.position.distance_to(want))
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
