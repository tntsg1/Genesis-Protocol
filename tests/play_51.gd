extends SceneTree
# Plays 5-1 for real, through the game itself: the guide's one change, at 8x
# speed to the end. With SHOTS=1 takes pictures for proofs/slug/ first; with
# SHOTS=only stops there. Env RUNS.
# Run: tools/run_test.sh tests/play_51.gd

var scene: Node2D
var dir := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/slug")
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


func _start(card: int) -> Node:
	scene.start_level(Levels.by_id("5-1"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	await create_timer(0.4).timeout
	if card >= 0:
		d.deck_editor.set_action(1, card)
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	return scene.level_runner


func _stage(want: int) -> Dictionary:
	for g: Dictionary in scene.sim.get_slugs():
		if int(g.stage) == want:
			return g
	return {}


func _pictures() -> void:
	var lr: Node = await _start(Rules.A_AGGREGATE)
	await create_timer(2.0).timeout
	await _shot("s_start")
	scene.set_speed(8.0)
	await _until(func() -> bool: return not _stage(0).is_empty(), 90.0)
	scene.set_speed(1.0)
	var g: Dictionary = _stage(0)
	scene.focus(g.pos, 3.0)
	await create_timer(5.0).timeout
	await _shot("s_gather")
	await _until(func() -> bool: return not _stage(1).is_empty(), 60.0)
	await create_timer(4.0).timeout
	g = _stage(1)
	if not g.is_empty():
		scene.focus(g.pos, 3.0)
		await create_timer(1.0).timeout
		await _shot("s_crawl")
		scene.focus(Vector2(1100, 1100), 0.62)
		await create_timer(1.0).timeout
		await _shot("s_crawl_far")
	scene.set_speed(8.0)
	await _until(func() -> bool: return not _stage(2).is_empty(), 60.0)
	scene.set_speed(1.0)
	g = _stage(2)
	if not g.is_empty():
		scene.focus(g.base, 4.0)
		await create_timer(6.0).timeout
		await _shot("s_rise")
		await _until(func() -> bool: return not _stage(3).is_empty(), 14.0)
		await create_timer(1.5).timeout
		await _shot("s_spores")
		await create_timer(9.0).timeout
		await _shot("s_sprout")
	scene.focus(Vector2(1100, 1100), 0.62)
	scene.set_speed(8.0)
	await _until(func() -> bool: return is_instance_valid(lr.report), 90.0)
	await create_timer(7.0).timeout
	await _shot("s_report")
	print("pictures: 对岸 ", lr.eval.zone_now, " 星 ", lr.eval.stars())
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null, 10.0)
	await create_timer(0.5).timeout


func _run() -> void:
	if OS.get_environment("SHOTS") != "":
		await _pictures()
		if OS.get_environment("SHOTS") == "only":
			quit()
			return
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 4
	for pl: Array in [["引导", Rules.A_AGGREGATE], ["不改", -1]]:
		for r in (runs if int(pl[1]) >= 0 else 2):
			var lr: Node = await _start(int(pl[1]))
			scene.set_speed(8.0)
			await _until(func() -> bool: return is_instance_valid(lr.report), 120.0)
			print("%s #%d: t %.0f 胜 %s 星 %s 对岸 %d 你 %d %s" % [pl[0], r, lr.eval.t, lr.eval.stars()[0], lr.eval.stars(), lr.eval.zone_now, lr.eval.alive, str(lr.eval.slug_stats)])
			lr.exit_level()
			await _until(func() -> bool: return scene.level_runner == null, 10.0)
			await create_timer(0.5).timeout
	quit()
