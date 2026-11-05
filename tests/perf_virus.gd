extends SceneTree
# Where the time goes with many viruses in the water: 4-2 with its storm's
# worth of phages, at three distances, and 4-5 late on. For each: the whole
# frame, the kernel's step, the layers' script, and draw calls.
# Run: tools/run_test.sh tests/perf_virus.gd

var scene: Node2D


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


func _start(id: String) -> Node:
	scene.start_level(Levels.by_id(id))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	return scene.level_runner


# Frames over `seconds` of wall clock, and the pieces measured on their own.
func _sample(name: String, seconds: float) -> void:
	var view: Rect2 = scene.get_viewport().get_visible_rect()
	var start := Time.get_ticks_usec()
	var frames := 0
	var worst := 0.0
	var last := start
	while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) / 1000.0)
		last = now
		frames += 1
	var ms := float(Time.get_ticks_usec() - start) / 1000.0 / float(maxi(frames, 1))
	var t0 := Time.get_ticks_usec()
	scene.sim.step(1.0 / 15.0)
	var step_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var r := Rect2(Vector2.ZERO, Vector2(2200, 2200))
	t0 = Time.get_ticks_usec()
	scene.sim.build_phage_buffer(r, 0.5, 4.0, 5000)
	var buf_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var cells: PackedFloat32Array = scene.sim.get_infected(r, 0.5)
	var inf_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	scene.phage_layer.tick(0.0, 0.5, scene.cam.get_canvas_transform().affine_inverse() * Rect2(view), PackedFloat32Array())
	var layer_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	scene.giant_layer.tick(0.0, 0.5, scene.cam.get_canvas_transform().affine_inverse() * Rect2(view))
	layer_ms += float(Time.get_ticks_usec() - t0) / 1000.0
	print("%s  帧 %.1f ms（最差 %.1f）%d 帧  内核一拍 %.1f  病毒缓冲 %.2f  感染表 %.2f  图层脚本 %.2f  绘制调用 %d  病毒 %d 感染 %d 细胞 %d" % [name, ms, worst, frames, step_ms, buf_ms, inf_ms, layer_ms,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), scene.sim.get_phage_count(), cells.size() / 12, scene.sim.get_positions(scene.level_runner.sp_index).size()])


# The moment that hurts: hundreds of cells infected together, all bursting at
# once. Frames are taken across the wave of bursts, at two distances.
func _storm() -> void:
	var specs := [[1.0, 1.0, "总览 1 倍速"], [3.0, 1.0, "放大 3 倍 1 倍速"], [1.0, 3.0, "总览 3 倍速"]]
	if OS.get_environment("STORM") == "shot":
		specs = [specs[1]]
	for spec: Array in specs:
		var lr: Node = await _start("4-1")
		scene.set_speed(8.0)
		await _until(func() -> bool: return lr.eval.t >= 130.0, 60.0)
		scene.set_speed(float(spec[1]))
		scene.focus(Vector2(1100, 1100), float(spec[0]))
		var st0: int = lr.eval.lysed
		scene.sim.set_phage({"stick": 0.6})
		scene.sim.add_phages(Vector2(1100, 1100), 900.0, 5000)
		var frames := PackedFloat32Array()
		var most := 0
		var last := Time.get_ticks_usec()
		var end := Time.get_ticks_usec() + int(38000000.0 / float(spec[1]))
		var shot := int(spec[0]) == 3
		while Time.get_ticks_usec() < end:
			await process_frame
			if shot and lr.eval.lysed - st0 >= 150:
				shot = false
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/burst_lod.png"))
			var now := Time.get_ticks_usec()
			frames.append(float(now - last) / 1000.0)
			last = now
			most = maxi(most, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		frames.sort()
		var n := frames.size()
		var total := 0.0
		for f: float in frames:
			total += f
		print("爆发潮 %s：细胞 %d，撑破 %d，平均 %.1f ms，95%% %.1f ms，最差 %.1f ms，最多绘制调用 %d" % [spec[2], lr.eval.alive, lr.eval.lysed - st0, total / n, frames[int(n * 0.95)], frames[-1], most])
		lr.exit_level()
		await _until(func() -> bool: return scene.level_runner == null, 10.0)
		await create_timer(0.5).timeout
	quit()


func _run() -> void:
	if OS.get_environment("STORM") != "":
		await _storm()
		return
	var lr: Node = await _start("4-1")
	scene.iv.points = 300.0
	scene.set_speed(3.0)
	await _until(func() -> bool: return lr.eval.t >= 70.0, 40.0)
	scene.set_speed(1.0)
	scene.focus(Vector2(1100, 1100), 1.0)
	await create_timer(0.8).timeout
	await _sample("平常 1 倍 无病毒潮", 2.0)
	scene.sim.add_phages(Vector2(1100, 1100), 1040.0, 3500)
	await create_timer(0.5).timeout
	await _sample("3500 病毒 总览", 2.0)
	scene.focus(Vector2(1100, 1100), 3.0)
	await create_timer(0.8).timeout
	await _sample("3500 病毒 放大 3 倍", 2.0)
	scene.focus(Vector2(1100, 1100), 8.0)
	await create_timer(0.8).timeout
	await _sample("3500 病毒 放大 8 倍", 2.0)
	scene.focus(Vector2(1100, 1100), 1.0)
	scene.sim.add_phages(Vector2(1100, 1100), 1040.0, 1500)
	await create_timer(0.8).timeout
	await _sample("5000 病毒 总览", 2.0)
	scene.set_speed(8.0)
	await create_timer(0.5).timeout
	await _sample("5000 病毒 总览 8 倍速", 2.0)
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null, 10.0)
	await create_timer(0.5).timeout
	# The worst the game gets: the late boss, a thousand cells, hundreds of
	# giants and factories, nobody fighting back.
	lr = await _start("4-5")
	scene.set_speed(8.0)
	await _until(func() -> bool: return lr.eval.t >= 200.0, 90.0)
	scene.focus(Vector2(1100, 1100), 1.0)
	await create_timer(0.5).timeout
	await _sample("后期 Boss 总览 8 倍速", 2.0)
	scene.set_speed(1.0)
	await create_timer(0.3).timeout
	await _sample("后期 Boss 总览 1 倍速", 2.0)
	scene.focus(Vector2(1100, 1100), 3.0)
	await create_timer(0.8).timeout
	await _sample("后期 Boss 放大 3 倍", 2.0)
	scene.focus(Vector2(1100, 1100), 8.0)
	await create_timer(0.8).timeout
	await _sample("后期 Boss 放大 8 倍", 2.0)
	print("巨毒囊 ", lr.eval.giant_stats)
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null, 10.0)
	await create_timer(0.5).timeout
	quit()
