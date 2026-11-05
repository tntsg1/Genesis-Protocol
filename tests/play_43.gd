extends SceneTree
# Plays 4-3 for real, through the game itself: default genes, mutation on,
# each plan a couple of times at 8x speed to the end. The first guided run
# also takes close-ups of a woken cell for proofs/latent/.
# Run: tools/run_test.sh tests/play_43.gd

var scene: Node2D
var runs := 2
var dir := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/latent")
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])


func _run() -> void:
	if OS.get_environment("SHOTS") != "":
		await _closeups()
	# [name, age threshold (0 = no card)]
	var plans := [["年龄 70%（引导）", 0.7], ["不改", 0.0], ["年龄 90%", 0.9]]
	if OS.get_environment("GUIDE") != "":
		plans = [plans[0]]
		runs = 5
	if OS.get_environment("GUIDE") == "none":
		plans = [["不改", 0.0]]
		runs = 3
	for pl: Array in plans:
		for r in runs:
			var lr: Node = await _start(float(pl[1]))
			scene.set_speed(8.0)
			await _until(func() -> bool: return is_instance_valid(lr.report), 240.0)
			var st: Array = lr.eval.stars()
			print("%s #%d: t %.0f 胜 %s 星 %s 你 %d 对手 %d 你牺牲 %d 对手撑破 %d" % [pl[0], r, lr.eval.t, st[0], st, lr.eval.alive, lr.eval.rival_alive, lr.eval.lysed, lr.eval.rival_lysed])
			lr.exit_level()
			await _until(func() -> bool: return scene.level_runner == null, 10.0)
			await create_timer(0.5).timeout
	quit()


func _start(age: float, guide := false) -> Node:
	scene.start_level(Levels.by_id("4-3"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	if scene.level_runner.tutorial and not guide:
		scene.level_runner.tutorial._skip()
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	await create_timer(0.4).timeout
	if age > 0.0:
		d.deck_editor.selected = 0
		var at: int = d.deck_editor.add_card()
		d.deck_editor.set_condition(at, 1, Rules.C_AGE_ABOVE)
		if not is_equal_approx(age, 0.7): # (the default: the guide leaves the slider alone)
			d.deck_editor.set_threshold(at, 1, age, true)
		d.deck_editor.set_action(at, Rules.A_INDUCE)
		print("card ", Rules.card_text(d.deck_editor.deck[at]), " t1 ", d.deck_editor.deck[at].t1)
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	return scene.level_runner


func _closeups() -> void:
	var lr: Node = await _start(0.7, true)
	scene.set_speed(3.0)
	await _until(func() -> bool: return lr.fired.has("phage_seen"), 60.0)
	var id: int = lr.tagged_id
	scene.selected = id
	scene.gone_timer = 0.0
	scene.following = true
	scene.goal_zoom = 16.0
	for m: float in [2.6, 3.6, 4.6, 8.0, 15.0, 21.0, 23.6]:
		await _until(func() -> bool:
			var info: Dictionary = scene.sim.get_agent(id)
			return info.is_empty() or float(info.infected) >= m, 30.0)
		await _shot("w_%04.1f" % m)
	await _until(func() -> bool: return scene.sim.get_agent(id).is_empty(), 6.0)
	await create_timer(0.7).timeout
	await _shot("w_burst")
	await create_timer(1.4).timeout
	await _shot("w_burst2")
	await create_timer(5.0).timeout
	scene.set_speed(8.0)
	await _until(func() -> bool: return lr.eval.t >= 150.0, 40.0)
	scene.set_speed(1.0)
	await create_timer(0.5).timeout
	await _shot("w_mid")
	scene.set_speed(8.0)
	await _until(func() -> bool: return is_instance_valid(lr.report), 60.0)
	await create_timer(7.0).timeout
	await _shot("w_report")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null, 10.0)
	await create_timer(0.5).timeout
