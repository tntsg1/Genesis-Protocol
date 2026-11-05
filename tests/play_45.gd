extends SceneTree
# Plays 4-5 for real, through the game itself: a design on the bench, drops
# through the tool, at 8x speed to the end. With SHOTS=1 also takes pictures
# for proofs/giant/ first.
# Run: tools/run_test.sh tests/play_45.gd

var scene: Node2D
var runs := 2
var dir := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/giant")
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
	scene.start_level(Levels.by_id("4-5"))
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


func _own(lr: Node) -> Vector2:
	return LevelEval.rival_thick(scene.sim, lr.sp_index)


func _play(d: Control, shots: Array) -> Node:
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	scene.iv.points = 300.0
	scene.set_speed(8.0)
	for s: Array in shots:
		await _until(func() -> bool: return lr.eval.t >= float(s[1]), 120.0)
		scene.iv.place("phage", _own(lr) if s[0] == "own" else LevelEval.giant_thick(scene.sim))
	await _until(func() -> bool: return is_instance_valid(lr.report), 240.0)
	return lr


func _run() -> void:
	if OS.get_environment("SHOTS") != "":
		await _pictures()
		if OS.get_environment("SHOTS") == "only":
			quit()
			return
	var fast := {burst = 2, speed = 5, shell = 2, stick = 3, temperate = true}
	var lytic := {burst = 3, speed = 5, shell = 3, stick = 1}
	var mid := {burst = 3, speed = 3, shell = 3, stick = 3}
	var ten := []
	for at in range(30, 240, 21):
		ten.append(["giants", float(at)])
	var plans := [["潜伏 接种两次", fast, [["own", 10.0], ["own", 30.0]]],
		["裂解 ×10", lytic, ten]]
	if OS.get_environment("REST") != "":
		plans = [["潜伏 爆4 接种两次", {burst = 4, speed = 5, shell = 1, stick = 2, temperate = true}, [["own", 10.0], ["own", 30.0]]]]
		runs = 6
	for pl: Array in plans:
		for r in runs:
			var d: Control = await _bench(pl[1])
			var lr: Node = await _play(d, pl[2])
			var st: Array = lr.eval.stars()
			print("%s #%d: t %.0f 胜 %s 星 %s 巨毒囊 %d 峰 %d 你 %d 投放 %d 撑破 %d 带 %d" % [pl[0], r, lr.eval.t, st[0], st, lr.eval.giants, lr.eval.giant_peak, lr.eval.alive, lr.eval.shots, lr.eval.lysed, int(lr.eval.giant_stats.carriers)])
			lr.exit_level()
			await _until(func() -> bool: return scene.level_runner == null, 10.0)
			await create_timer(0.5).timeout
	quit()


# The cell on screen with a factory at that age.
func _factory(older: float, stolen := false) -> PackedFloat32Array:
	var c: PackedFloat32Array = scene.sim.get_infected(Rect2(0, 0, 2200, 2200), 0.0)
	for k in range(0, c.size(), 12):
		if c[k + 10] == 4.0 and c[k + 5] >= older and (not stolen or c[k + 11] >= 0.0):
			return c.slice(k, k + 12)
	return PackedFloat32Array()


func _follow(pos: Vector2) -> void:
	var id: int = scene.sim.find_agent(pos, 12.0)
	scene.selected = id
	scene.gone_timer = 0.0
	scene.following = true
	scene.goal_zoom = 16.0


func _pictures() -> void:
	var d: Control = await _bench({burst = 2, speed = 5, shell = 2, stick = 3, temperate = true})
	await create_timer(1.2).timeout
	await _shot("g_bench")
	d.show_page("genome")
	await create_timer(1.2).timeout
	await _shot("g_genome")
	d.show_page("virus")
	await create_timer(1.0).timeout
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	await create_timer(1.0).timeout
	await _shot("g_banner")
	await create_timer(3.6).timeout
	var gp: PackedVector2Array = scene.sim.get_giant_positions()
	await _shot("g_water")
	scene.focus(gp[0], 5.0)
	await create_timer(1.0).timeout
	await _shot("g_giant_5x")
	scene.focus(gp[0], 16.0)
	await create_timer(1.0).timeout
	await _shot("g_giant_16x")
	scene.focus(Vector2(1100, 1100), 1.0)
	scene.iv.points = 300.0
	scene.iv.place("phage", _own(lr))
	await create_timer(10.5).timeout
	scene.iv.place("phage", _own(lr))
	await _until(func() -> bool: return _factory(0.0).size() > 0, 40.0)
	var f := _factory(0.0)
	_follow(Vector2(f[0], f[1]))
	await create_timer(0.75).timeout
	await _shot("g_swallow")
	await create_timer(0.9).timeout
	await _shot("g_gate")
	await create_timer(7.0).timeout
	await _shot("g_factory")
	await create_timer(12.0).timeout
	await _shot("g_factory_late")
	scene.following = false
	scene.focus(Vector2(1100, 1100), 1.0)
	scene.set_speed(3.0)
	await _until(func() -> bool: return lr.eval.t >= 97.0, 40.0)
	scene.set_speed(1.0)
	await create_timer(0.8).timeout
	await _shot("g_wave")
	scene.set_speed(8.0)
	await _until(func() -> bool: return lr.eval.t >= 120.0, 60.0)
	scene.set_speed(1.0)
	await _until(func() -> bool: return _factory(0.0, true).size() > 0, 30.0)
	f = _factory(0.0, true)
	if not f.is_empty():
		_follow(Vector2(f[0], f[1]))
		await create_timer(2.0).timeout
		await _shot("g_stolen")
		await create_timer(6.0).timeout
		await _shot("g_stolen_late")
	scene.following = false
	scene.focus(Vector2(1100, 1100), 1.0)
	await create_timer(0.8).timeout
	await _shot("g_mid")
	scene.set_speed(8.0)
	await _until(func() -> bool: return is_instance_valid(lr.report), 90.0)
	await create_timer(7.0).timeout
	await _shot("g_report")
	print("pictures: 巨毒囊 ", lr.eval.giants, " 你 ", lr.eval.alive)
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null, 10.0)
	await create_timer(0.5).timeout
