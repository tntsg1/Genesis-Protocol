extends SceneTree
# Bug 2026-11-05 "撒铁粉好像也出bug了": picked by its key (5) and placed by a
# real click on the dish, the iron dust must land (an "iron" intervention,
# points spent, the guide's "used:iron"). Prints PASS / FAIL.
# Run: tools/run_test.sh tests/iron_click_check.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	fails += 0 if ok else 1


func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.pressed = down
		root.push_input(e)
		await process_frame


func _click(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	root.push_input(m)
	await process_frame
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		root.push_input(e)
		await process_frame


func _run() -> void:
	scene.start_level(Levels.by_id("6-3"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	await create_timer(0.5).timeout
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	await create_timer(1.5).timeout
	scene.iv.points = 200.0
	await _key(Keys.code("phage"))
	await create_timer(0.3).timeout
	_check(scene.mode == "iron", "按 %s 选中撒铁粉（mode=%s）" % [Keys.name_of(Keys.code("phage")), scene.mode])
	var p0: float = scene.iv.points
	await _click(scene.get_viewport().get_visible_rect().size * 0.5)
	await create_timer(0.3).timeout
	var irons: Array = scene.sim.get_interventions().filter(func(d: Dictionary) -> bool: return d.kind == "iron")
	_check(irons.size() == 1, "点培养皿撒下一片铁粉")
	_check(scene.iv.points < p0, "扣了生物质点")
	_check(int(scene.iv.used.get("iron", 0)) == 1, "引导能看到用过一次（used:iron）")
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit()
