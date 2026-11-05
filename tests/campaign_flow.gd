extends SceneTree
# The campaign path end to end, as a player takes it: menu -> 战役 -> the
# level page -> level 1 -> designer (level rules) -> release -> the level runs
# to its end -> report (stars, facts) -> side-by-side control experiment ->
# -> next level. Screens are saved to proofs/campaign_*.png.
# Run: tools/run_test.sh tests/campaign_flow.gd -- --menu

var scene: Node2D
var fails := 0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/campaign_%s.png" % name))


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _until(cond: Callable, limit := 20.0) -> bool:
	# Real time, not frames: the frame rate is whatever the settings say.
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _run() -> void:
	await _wait(1.5)
	scene.menu._activate(0)
	await _wait(0.8)
	check(scene.campaign.visible, "战役 opens the level page")
	await _shot("page")
	scene.campaign._select(1)
	await _wait(0.5)
	await _shot("page_locked")
	scene.campaign._select(0)
	await _wait(0.3)
	scene.campaign._start()
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 12.0), "the level opens the designer")
	var d: Control = scene.designer
	check(d.budget_max == 14.0, "the designer has the level's budget (%s)" % d.budget_max)
	check(d.gene_sliders[2].locked and not d.gene_sliders[0].locked, "locked genes are locked, open ones are not")
	await _wait(1.0)
	await _shot("designer")
	# Speed 4, sense 1, fertility 2: a design the bot found reliable.
	for k_v in [[0, 4.0], [1, 1.0], [4, 2.0]]:
		d.gene_sliders[k_v[0]].changed.emit(k_v[1])
		d.gene_sliders[k_v[0]].value = k_v[1]
	await _wait(0.4)
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 8.0), "the design is released straight away and the clock starts")
	await _wait(2.0)
	await _shot("run")
	scene.set_speed(8.0)
	check(await _until(func() -> bool: return scene.level_runner.phase == "done", 120.0), "the level runs to its end")
	await _wait(1.0)
	await _shot("result_moment")
	await _wait(2.6)
	await _shot("report")
	var rep: Control = scene.level_runner.report
	check(rep != null and rep.gene_pills.size() == 3, "the report offers the open genes for a control experiment")
	check(CampaignSave.stars("1-1")[0], "level 1 is recorded as completed")
	check(CampaignSave.unlocked(2), "level 2 is open now")
	# Side-by-side control experiment: fertility +1.
	rep._pick(4, 1.0)
	rep._compare()
	check(await _until(func() -> bool: return scene.level_runner.bench != null, 3.0), "the control bench opens")
	var bench: Control = scene.level_runner.bench
	check(not rep.visible, "the report waits hidden behind the bench")
	await _wait(2.5)
	await _shot("bench_running")
	bench._set_speed(8.0)
	check(await _until(func() -> bool: return bench.done, 90.0), "both dishes run to the end")
	await _wait(1.0)
	await _shot("bench_result")
	check(bench._verdict().contains("繁殖"), "the result is put in one sentence (%s)" % bench._verdict())
	bench._leave("back")
	check(await _until(func() -> bool: return rep.visible and scene.level_runner.bench == null, 3.0), "back to the report")
	# Retry with the changed design straight from a second bench.
	rep._pick(4, 1.0)
	rep._compare()
	await _until(func() -> bool: return scene.level_runner.bench != null, 3.0)
	scene.level_runner.bench._end() # stop early: shows the result
	await _wait(0.4)
	scene.level_runner.bench._leave("retry_variant")
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 12.0), "the changed design goes back to the designer")
	await _wait(0.6)
	check(_reports_visible() == 0, "the old report is gone (%d visible)" % _reports_visible())
	check(scene.level_runner.tutorial == null, "the guide does not come back on a retry")
	check(float(scene.designer.genes[4]) == 3.0, "the change is on the bench (fertility %.0f)" % scene.designer.genes[4])
	scene.designer.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 8.0), "the retry runs")
	await _wait(1.5)
	check(_reports_visible() == 0 and scene.level_runner.report == null, "no report while the retry runs")
	scene.set_speed(8.0)
	check(await _until(func() -> bool: return scene.level_runner.phase == "done", 120.0), "the retry runs to its end")
	await _wait(3.0)
	rep = scene.level_runner.report
	check(_reports_visible() == 1, "exactly one report after the retry")
	rep.action.emit("next", null)
	check(await _until(func() -> bool: return scene.level_runner.level.id == "1-2" and scene.designer != null, 12.0), "next goes on to level 2")
	await _wait(1.2)
	await _shot("level2_designer")
	scene.designer.close()
	await _until(func() -> bool: return scene.designer == null, 6.0)
	scene.level_runner.exit_level()
	check(await _until(func() -> bool: return scene.campaign.visible and scene.level_runner == null, 6.0), "leaving a level returns to the level page")
	await _wait(0.8)
	await _shot("page_after")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)


func _reports_visible() -> int:
	var n := 0
	for c in scene.ui_layer.get_children():
		if c.get_script() == preload("res://scripts/ui/level_report.gd") and c.visible and c.modulate.a > 0.05:
			n += 1
	return n
