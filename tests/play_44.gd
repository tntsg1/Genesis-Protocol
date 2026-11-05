extends SceneTree
# Plays 4-4 for real, through the game itself: a design on the bench, drops
# through the tool at the rival's thickest spot, at 8x speed to the end. With
# SHOTS=1 also takes pictures for proofs/virus/ first.
# Run: tools/run_test.sh tests/play_44.gd

var scene: Node2D
var runs := 2
var dir := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/virus")
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


func _bench(v: Dictionary) -> Control:
	scene.start_level(Levels.by_id("4-4"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	await _until(func() -> bool: return d.page == "virus", 5.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	var b: Control = d.virus_bench
	for k: String in ["burst", "speed", "shell", "stick"]:
		b.set_trait(k, 1)
	for k: String in ["burst", "speed", "shell", "stick"]:
		b.set_trait(k, int(v[k]))
	b._set_mode(bool(v.get("temperate", false)))
	return d


func _play(d: Control, times: Array) -> Node:
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	scene.iv.points = 300.0
	scene.set_speed(8.0)
	for at: float in times:
		await _until(func() -> bool: return lr.eval.t >= at, 120.0)
		scene.iv.place("phage", LevelEval.rival_thick(scene.sim, 0))
	await _until(func() -> bool: return is_instance_valid(lr.report), 240.0)
	return lr


func _run() -> void:
	if OS.get_environment("SHOTS") != "":
		await _pictures()
	var plans := [["结晶型 开局", {burst = 2, speed = 2, shell = 5, stick = 3}, [30.0, 42.0]],
		["均衡 中段", {burst = 3, speed = 3, shell = 3, stick = 3}, [120.0, 132.0]],
		["不投放", {burst = 3, speed = 3, shell = 3, stick = 3}, []]]
	if OS.get_environment("NOW") != "":
		plans = [["结晶 第60秒", {burst = 2, speed = 2, shell = 5, stick = 3}, [60.0, 72.0]],
			["结晶 第40秒", {burst = 2, speed = 2, shell = 5, stick = 3}, [40.0, 52.0]]]
		runs = 3
	for pl: Array in plans:
		for r in runs:
			var d: Control = await _bench(pl[1])
			var lr: Node = await _play(d, pl[2])
			var st: Array = lr.eval.stars()
			print("%s #%d: t %.0f 胜 %s 星 %s 对手 %d 你 %d 投放 %d 对手撑破 %d" % [pl[0], r, lr.eval.t, st[0], st, lr.eval.rival_alive, lr.eval.alive, lr.eval.shots, lr.eval.rival_lysed])
			lr.exit_level()
			await _until(func() -> bool: return scene.level_runner == null, 10.0)
			await create_timer(0.5).timeout
	quit()


func _pictures() -> void:
	var d: Control = await _bench({burst = 3, speed = 3, shell = 3, stick = 3})
	await create_timer(1.2).timeout
	await _shot("v_bench_mid")
	var b: Control = d.virus_bench
	b.set_trait("stick", 1)
	b.set_trait("speed", 1)
	b.set_trait("burst", 5)
	b.set_trait("shell", 1)
	await create_timer(0.6).timeout
	await _shot("v_bench_burst")
	b.set_trait("burst", 2)
	b.set_trait("shell", 5)
	b.set_trait("stick", 3)
	b.set_trait("speed", 2)
	await create_timer(0.6).timeout
	await _shot("v_bench_crystal")
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	await create_timer(4.0).timeout
	var at: Vector2 = LevelEval.rival_thick(scene.sim, 0)
	scene.iv.place("phage", at)
	scene.focus(at, 16.0)
	await create_timer(1.5).timeout
	await _shot("v_water")
	scene.focus(at, 1.0)
	scene.set_speed(8.0)
	await _until(func() -> bool: return lr.eval.t >= 170.0, 60.0)
	scene.set_speed(1.0)
	await create_timer(0.6).timeout
	await _shot("v_mid")
	scene.set_speed(8.0)
	await _until(func() -> bool: return is_instance_valid(lr.report), 60.0)
	await create_timer(7.0).timeout
	await _shot("v_report")
	print("pictures: 对手 ", lr.eval.rival_alive, " 你 ", lr.eval.alive)
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null, 10.0)
	await create_timer(0.5).timeout
