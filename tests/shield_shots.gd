extends SceneTree
# Level 12 (3-2) shields (scripts/dish_marks.gd): a tight group of the
# player's cells outlined, a hunter at it flicking its aim. The cells get the
# 抱团 personality so they bunch up. Saves proofs/shield_*.png.
# Run: tools/run_test.sh tests/shield_shots.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/shield_%s.png" % name))


func _run() -> void:
	scene.start_level(Levels.by_id("3-2"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	d.show_page("rules")
	d.set_rules_mode("simple")
	d._pick_persona("swarm")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "released")
	var m: DishMarks = scene.dish_marks
	await create_timer(3.0).timeout
	scene.fly_to(Vector2(1100, 1100), 1.0, 0.3)
	await create_timer(1.0).timeout
	# A group with a hunter near: some cell of ours with a herder within 120 µm.
	var mine: Array = m._mine()
	var find := func() -> Vector2:
		var ours := PackedVector2Array()
		var hunters := PackedVector2Array()
		for b in range(0, m.marks.size(), 6):
			var p := Vector2(m.marks[b], m.marks[b + 1])
			if int(m.marks[b + 2]) in mine:
				ours.append(p)
			else:
				hunters.append(p)
		for h in hunters:
			var close := 0
			for q in ours:
				if q.distance_to(h) < 110.0:
					close += 1
			if close >= 5:
				return h
		return Vector2.INF
	scene.set_speed(2.0)
	var got := await _until(func() -> bool: return find.call() != Vector2.INF, 40.0)
	check(got, "a hunter comes at a group of ours")
	var at: Vector2 = find.call()
	scene.set_speed(0.2)
	if got:
		scene.fly_to(at, 2.2, 0.25)
	await create_timer(0.7).timeout
	print("herd %s diet %s mine %s marks %d" % [scene.species_herd, scene.species_diet, str(m._mine()), m.marks.size() / 6])
	await _shot("close")
	scene.fly_to(at if got else Vector2(1100, 1100), 1.0, 0.25)
	await create_timer(0.6).timeout
	await _shot("wide")
	print("DONE fails=%d" % fails)
	quit()
