extends SceneTree
# Where the first step into the micro tier (a cell picked, zoomed in: the
# life scan comes up, the side panels dim) spends its 30-40 ms: the same cell
# twice, then a cell of another species, then the dim alone and the scan
# alone. Prints the worst frame of each.
# Run: tools/run_test.sh tests/micro_hitch_probe.gd [-- --menu | --part=show|motes|type|params|tiny | --bisect]

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


# Worst frame, and (less sensitive to other programs) the worst render CPU,
# render GPU and script process times of this viewport.
func _worst(label: String, seconds: float) -> void:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var worst := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var proc := 0.0
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var t := Time.get_ticks_usec()
	while Time.get_ticks_msec() < end:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - t) / 1000.0)
		t = now
		cpu = maxf(cpu, RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
		gpu = maxf(gpu, RenderingServer.viewport_get_measured_render_time_gpu(vp))
		proc = maxf(proc, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	print("%-12s worst %5.1f ms   render cpu %5.1f  gpu %5.1f  process %5.1f" % [label, worst, cpu, gpu, proc])


func _enter(id: int, label: String) -> void:
	scene.selected = id
	scene.goal_zoom = 2.6
	await _worst(label, 1.5)
	scene._deselect()
	scene.goal_zoom = 1.5
	await _worst("  (out)", 1.5)


func _run() -> void:
	if "--menu" in OS.get_cmdline_user_args():
		# The real way in: the menu first (the HUD prewarms behind it).
		await create_timer(4.0).timeout
		scene.start_experiment()
	await create_timer(4.0).timeout
	scene.goal_zoom = 1.5
	await create_timer(2.0).timeout
	await _worst("idle", 1.0)
	var a: int = scene.sim.find_agent(scene.cam.position, 300.0)
	var hud0: Control = scene.hud_root
	if "--calls" in OS.get_cmdline_user_args():
		# The tier change's script work, call by call, twice.
		var hud1: Control = scene.hud_root
		for round in 2:
			scene.selected = a
			scene.goal_zoom = 2.6
			scene.cam.zoom = Vector2(2.6, 2.6)
			var t0 := Time.get_ticks_usec()
			hud1._update_tier()
			var t1 := Time.get_ticks_usec()
			hud1._update_scan()
			var t2 := Time.get_ticks_usec()
			hud1.queue_redraw()
			await process_frame
			var t3 := Time.get_ticks_usec()
			await process_frame
			var t4 := Time.get_ticks_usec()
			print("round %d: _update_tier %.1f ms  _update_scan %.1f ms  next frame %.1f  then %.1f" % [round, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0])
			await _worst("  settle", 1.0)
			scene._deselect()
			scene.goal_zoom = 1.5
			scene.cam.zoom = Vector2(1.5, 1.5)
			await _worst("  out", 1.5)
		quit()
		return
	var part := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--part="):
			part = arg.substr(7)
	if part != "":
		# One piece of scan_panel.appear() alone, then the whole of it.
		var sp: Control = hud0.scan_panel
		scene.selected = a
		hud0._update_scan()
		await _worst("select grp", 0.6)
		match part:
			"show":
				sp.visible = true
			"tiny":
				# Drawn almost transparent for a few frames, then put away.
				sp.modulate.a = 0.003
				sp.visible = true
				for i in 4:
					await process_frame
				sp.visible = false
				sp.modulate.a = 1.0
				await _worst("tiny drawn", 0.5)
				sp.visible = true
			"motes":
				sp.visible = true
				sp._spawn_motes(8)
			"type":
				sp.visible = true
				Holo.type_in(sp.body)
			"params":
				sp.visible = true
				sp.mat.set_shader_parameter("trace", 0.3)
				sp.mat.set_shader_parameter("haze_in", 0.3)
				sp._set_appear(0.3)
		await _worst("part " + part, 1.0)
		sp.appear()
		await _worst("then appear", 1.0)
		quit()
		return
	if "--bisect" in OS.get_cmdline_user_args():
		var t0 := Time.get_ticks_usec()
		Audio.sfx("holo_on", -80.0)
		print("sfx call %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
		await _worst("after sfx", 0.6)
		scene.selected = a
		await _worst("select grp", 0.8)
		hud0.scan_panel.visible = true
		hud0._update_scan()
		hud0.scan_panel.appear()
		await _worst("scan appear", 1.0)
		for key in ["species", "events", "objective"]:
			hud0.panels[key].modulate.a = 0.35
		await _worst("dim first", 0.6)
		for key in ["species", "events", "objective"]:
			hud0.panels[key].modulate.a = 1.0
		hud0.scan_panel.visible = false
		scene._deselect()
		await _worst("reset", 0.8)
	await _enter(a, "enter A")
	await _enter(a, "enter A again")
	var sp_a: int = scene.sim.get_agent(a).species
	var b := -1
	for sp in 4:
		if sp == sp_a:
			continue
		var ps: PackedVector2Array = scene.sim.get_positions(sp)
		if ps.size() > 0:
			b = scene.sim.find_agent(ps[0], 10.0)
			break
	await _enter(b, "enter B")
	var hud: Control = scene.hud_root
	for key in ["species", "events", "objective"]:
		hud.panels[key].modulate.a = 0.35
	await _worst("dim only", 0.5)
	for key in ["species", "events", "objective"]:
		hud.panels[key].modulate.a = 1.0
	await _worst("undim", 0.5)
	quit()
