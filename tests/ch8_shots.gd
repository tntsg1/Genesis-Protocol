extends SceneTree
# Chapter 8 through the game itself: a level (LEVEL, default 6-2) opened,
# the designer (organs installed as the level needs), released, run a while
# at 8x, with pictures in proofs/ch8/: the designer, the dish early and late,
# the analysis view (X), the report. Env LEVEL, RUN (seconds of sim at 8x).
# Run: tools/run_test.sh tests/ch8_shots.gd

var scene: Node2D
var dir := ""
var tag := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/ch8")
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [dir, tag, name])
	print("shot ", tag, "_", name)


func _run() -> void:
	var id := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "8-1"
	tag = id.replace("-", "")
	var l: Dictionary = Levels.by_id(id)
	scene.start_level(l)
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	await create_timer(0.6).timeout
	var d: Control = scene.designer
	var need: Array = l.get("require_organs", [])
	if not need.is_empty():
		d._set_organs(need)
		await create_timer(0.6).timeout
	var e: Control = d.deck_editor
	match id:
		"8-2":
			var k: int = e.add_card(Rules.C_SYMB, Rules.A_SWALLOW)
			e.deck[k].n1 = true
			e.move_card(k, 0)
		"8-3", "8-5":
			if id == "8-5":
				d._set_organs(["toxin"])
				await create_timer(0.4).timeout
			e.add_card(Rules.C_RIVAL_NEAR, Rules.A_TOXIN_A)
			e.move_card(e.deck.size() - 1, 0)
			if id == "8-3":
				var k2: int = e.add_card(Rules.C_RIVAL_NEAR, Rules.A_TOXIN_B)
				e.deck[k2].c2 = Rules.C_AGE_ABOVE
				e.deck[k2].t2 = 0.5
				e.move_card(k2, 0)
	await _shot("a_designer")
	print("go_hint: ", d.go_hint.text)
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	if lr.tutorial:
		lr.tutorial._skip()
	await create_timer(2.5).timeout
	await _shot("b_start")
	scene.set_speed(8.0)
	var run := float(OS.get_environment("RUN")) if OS.get_environment("RUN") != "" else 120.0
	var t0: float = scene.sim.get_time()
	await _until(func() -> bool: return scene.sim.get_time() - t0 >= run or lr.phase == "done", 120.0)
	scene.set_speed(1.0)
	await create_timer(0.8).timeout
	await _shot("c_later")
	print("objective: ", scene.hud_root.get("objective_text") if scene.hud_root.get("objective_text") != null else "")
	var focus := {"8-1": Vector2(1100, 1300), "8-2": Vector2(1100, 800), "8-3": Vector2(1100, 600), "8-4": Vector2(1100, 500), "8-5": Vector2(1100, 1100)}
	scene.focus(focus.get(id, Vector2(1100, 1100)), float(OS.get_environment("ZOOM")) if OS.get_environment("ZOOM") != "" else (1.2 if id != "8-5" else 0.5))
	await create_timer(3.0).timeout
	await _shot("d_close")
	quit()
