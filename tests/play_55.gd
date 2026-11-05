extends SceneTree
# Plays 5-5 for real, through the game itself: the guide's third armour,
# released, then 8x to the end. With SHOTS=1 takes pictures for proofs/boss/
# along the way. Env RUNS, FIX (0 = leave the body as it is).
# Run: tools/run_test.sh tests/play_55.gd

var scene: Node2D
var dir := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/boss")
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


# The body of a colony a hunter is closest to (for a look at the biting).
func _bitten() -> Vector2:
	var hs: PackedVector2Array = scene.sim.get_positions(0)
	var cs: PackedFloat32Array = scene.sim.get_colonies()
	var best := Vector2(1100, 1100)
	var bd := 1e12
	for h: Vector2 in hs:
		for k in range(0, cs.size(), 6):
			var p := Vector2(cs[k + 1], cs[k + 2])
			if p.distance_squared_to(h) < bd:
				bd = p.distance_squared_to(h)
				best = (p + h) * 0.5
	return best


func _play(fix: bool, shots: bool) -> Array:
	scene.start_level(Levels.by_id("5-5"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	await create_timer(0.5).timeout
	var b: Control = scene.designer.body_bench
	if fix:
		# The guide: armour on the two back corners, a store for the back germ.
		var lo := Vector2i(100, 100)
		for c: Array in b.cells:
			lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
		b.place(lo + Vector2i(0, 1), Colony.ARMOR)
		b.place(lo + Vector2i(1, 2), Colony.GERM)
		await create_timer(1.2).timeout
		if shots:
			await _shot("a_bench")
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	if lr.tutorial:
		lr.tutorial._skip()
	if shots:
		await create_timer(2.0).timeout
		await _shot("b_start")
		scene.set_speed(3.0)
		await _until(func() -> bool: return scene.sim.get_rotifers(1.0).size() >= 6 and scene.sim.get_rotifers(1.0)[4] > 0.3, 90.0)
		scene.set_speed(1.0)
		var r: PackedFloat32Array = scene.sim.get_rotifers(1.0)
		scene.focus(Vector2(r[0], r[1]) + Vector2.from_angle(r[2]) * 100.0, 3.0)
		await create_timer(0.3).timeout
		await _shot("c_swallow")
		scene.set_speed(8.0)
		await _until(func() -> bool: return lr.eval.t > 150.0, 60.0)
		scene.set_speed(1.0)
		var cs: PackedFloat32Array = scene.sim.get_colonies()
		if cs.size() >= 6:
			scene.focus(Vector2(cs[1], cs[2]), 9.0)
		await create_timer(0.6).timeout
		await _shot("d_famine")
		scene.focus(Vector2(1100, 1100), 0.62)
		await create_timer(0.6).timeout
		await _shot("e_far")
	scene.set_speed(8.0)
	await _until(func() -> bool: return is_instance_valid(lr.report), 150.0)
	if shots:
		await create_timer(7.0).timeout
		await _shot("f_report")
	var ev: LevelEval = lr.eval
	return [ev.goal_met, ev.challenge_met(), ev.alive, ev.peak, ev.colony_stats]


func _run() -> void:
	var shots := OS.get_environment("SHOTS") == "1"
	var fix := OS.get_environment("FIX") != "0"
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 1
	var wins := 0
	for k in runs:
		var r: Array = await _play(fix, shots and k == 0)
		wins += 1 if r[0] else 0
		print("5-5 %s: 过关 %s 挑战 %s 终 %d 峰 %d %s" % ["引导" if fix else "不改", r[0], r[1], r[2], r[3], r[4]])
		scene.level_runner.exit_level()
		await _until(func() -> bool: return scene.level_runner == null)
	print("5-5 %s: 过关 %d/%d" % ["引导" if fix else "不改", wins, runs])
	quit()
