extends SceneTree
# Plays 5-2 for real, through the game itself: the guide's two swaps, at 8x
# speed to the end. With SHOTS=1 takes pictures for proofs/colony/ first; with
# SHOTS=only stops there. Env RUNS.
# Run: tools/run_test.sh tests/play_52.gd

var scene: Node2D
var dir := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/colony")
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


func _start(fix: bool, shots := false) -> Node:
	scene.start_level(Levels.by_id("5-2"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	await create_timer(0.8).timeout
	if shots:
		await _shot("c_bench_start")
	if fix:
		# Start: germs at (7,4), (7,5) and (4,4); walled flagella at (5,4), (6,4).
		d.body_bench.move(Vector2i(7, 4), Vector2i(6, 4))
		d.body_bench.move(Vector2i(7, 5), Vector2i(5, 4))
		await create_timer(0.3).timeout
		if shots:
			await _shot("c_bench_fixed")
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	return scene.level_runner


func _body(carrying: bool) -> Dictionary:
	var b: PackedFloat32Array = scene.sim.get_colonies()
	for k in range(0, b.size(), 6):
		if not carrying or b[k + 5] > 0.5:
			return {id = int(b[k]), pos = Vector2(b[k + 1], b[k + 2]), share = b[k + 4]}
	return {}


func _pictures() -> void:
	var lr: Node = await _start(true, true)
	await create_timer(1.5).timeout
	await _shot("c_start_far")
	var g := _body(false)
	scene.focus(g.pos, 5.0)
	await create_timer(1.2).timeout
	await _shot("c_close")
	scene.set_speed(3.0)
	await _until(func() -> bool: return not _body(true).is_empty(), 60.0)
	scene.set_speed(1.0)
	g = _body(true)
	await create_timer(0.5).timeout
	scene.focus(_body(true).pos, 6.0)
	await create_timer(9.0).timeout
	scene.focus(_body(true).pos, 6.0)
	await create_timer(0.8).timeout
	await _shot("c_embryo")
	await _until(func() -> bool: return _body(true).get("share", 0.0) > 0.86, 20.0)
	scene.focus(_body(true).pos, 6.0)
	await create_timer(0.6).timeout
	await _shot("c_turning")
	var mark := int(scene.sim.get_colony_stats().born)
	var at := Vector2.ZERO
	while int(scene.sim.get_colony_stats().born) == mark and Time.get_ticks_msec() < 600000:
		var b := _body(true)
		if not b.is_empty():
			at = b.pos
		await process_frame
		if lr.eval.t > 120.0:
			break
	scene.focus(at, 5.0)
	await create_timer(1.0).timeout
	await _shot("c_hatch")
	await create_timer(4.0).timeout
	await _shot("c_shell")
	scene.focus(Vector2(1100, 1100), 0.62)
	scene.set_speed(8.0)
	await _until(func() -> bool: return lr.eval.t > 170.0, 60.0)
	scene.set_speed(1.0)
	await create_timer(0.8).timeout
	await _shot("c_far")
	print("生 ", scene.sim.get_colony_stats())
	scene.set_speed(8.0)
	await _until(func() -> bool: return is_instance_valid(lr.report), 90.0)
	await create_timer(7.0).timeout
	await _shot("c_report")
	print("pictures: 上游 ", lr.eval.zone_now, " 星 ", lr.eval.stars())
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
	for pl: Array in [["引导", true], ["不改", false]]:
		for r in (runs if pl[1] else 2):
			var lr: Node = await _start(pl[1])
			scene.set_speed(8.0)
			await _until(func() -> bool: return is_instance_valid(lr.report), 120.0)
			print("%s #%d: t %.0f 胜 %s 星 %s 上游 %d 你 %d %s" % [pl[0], r, lr.eval.t, lr.eval.stars()[0], lr.eval.stars(), lr.eval.zone_now, lr.eval.alive, str(lr.eval.colony_stats)])
			if not pl[1] and r == 0:
				await create_timer(7.0).timeout
				await _shot("c_fail")
			lr.exit_level()
			await _until(func() -> bool: return scene.level_runner == null, 10.0)
			await create_timer(0.5).timeout
	quit()
