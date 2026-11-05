extends SceneTree
# Level 10 (2-5) dish marks for the devourer (scripts/dish_marks.gd): its
# crown and energy bar, the arrow at the screen's edge while it is out of
# view, the red edges while it is near; and the rules page behind the
# designer without the pink smudge. Saves proofs/boss_*.png.
# Run: tools/run_test.sh tests/boss_marks_shots.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/boss_%s.png" % name))


func _run() -> void:
	scene.start_level(Levels.by_id("2-5"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	d.show_page("rules")
	await create_timer(1.5).timeout
	await _shot("rules")
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "released")
	var m: DishMarks = scene.dish_marks
	check(m.bosses.size() >= 1, "the devourer is found (%d)" % m.bosses.size())
	# (The level opens on a shot of the devourer: let it play.)
	await create_timer(5.0).timeout
	# Our cells at the top, the devourer out of view below: the edge arrow.
	scene.fly_to(Vector2(1100, 470), 2.6, 0.3)
	await create_timer(1.0).timeout
	var vs: Vector2 = root.get_visible_rect().size
	var to_screen: Transform2D = m.get_viewport().get_canvas_transform() * m.get_global_transform()
	var off := not Rect2(Vector2.ZERO, vs).has_point(to_screen * (m.bosses[0][0] as Vector2))
	check(off, "the devourer is out of view here")
	await _shot("arrow")
	check(m.bosses[0][1] >= 0.0, "its energy is read (%.2f)" % float(m.bosses[0][1]))
	# Wait for it to come near our cells.
	scene.set_speed(4.0)
	var near := await _until(func() -> bool: return m.near > 0.9, 25.0)
	scene.set_speed(1.0)
	check(near, "the edges warn while it is near")
	scene.fly_to(m.bosses[0][0], 1.6, 0.3)
	await create_timer(0.8).timeout
	await _shot("near")
	scene.fly_to(m.bosses[0][0], 3.0, 0.3)
	await create_timer(0.8).timeout
	await _shot("close")
	print("DONE fails=%d" % fails)
	quit()
