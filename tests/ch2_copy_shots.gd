extends SceneTree
# Chapter 2 user copy, 2026-11-04 (shared texts, 2-2, 2-3): the 2-2 run line,
# the organ-pair toast, the release hints, the objective bar, the report's
# new facts and titles, and the 2-3 guide with its sleep step.
# Saves proofs/ch2c_*.png.
# Run: tools/run_test.sh tests/ch2_copy_shots.gd

var scene: Node2D
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


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


func _shot(name: String, wait := 1.2) -> void:
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/ch2c_%s.png" % name))


func _says(bit: String) -> bool:
	var g: Node = scene.level_runner.tutorial
	return g != null and g.card.visible and g.text_label.text.contains(bit)


func _find(n: Node, bit: String) -> Node:
	if (n is Label or n is Button) and n.visible and n.text.contains(bit):
		return n
	for c in n.get_children():
		var f := _find(c, bit)
		if f:
			return f
	return null


func _run() -> void:
	# --- 2-2 ---
	scene.start_level(Levels.by_id("2-2"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	g._skip()
	d.organ_bay.chips.silica.pressed.emit()
	d.organ_bay.chips.spines.pressed.emit()
	check(await _until(func() -> bool: return _find(d, "只能二选一") != null, 3.0), "2-2: the pair toast says only one of the two")
	await _shot("pair", 0.2)
	for kv in [[0, 5.0], [4, 5.0]]:
		d.gene_sliders[kv[0]].value = kv[1]
		d.gene_sliders[kv[0]].changed.emit(kv[1])
	check(await _until(func() -> bool: return d.go_hint.text.contains("基因预算超出"), 3.0), "2-2: over budget (%s)" % d.go_hint.text)
	await _shot("over", 0.3)
	for kv in [[0, 3.0], [4, 2.0]]:
		d.gene_sliders[kv[0]].value = kv[1]
		d.gene_sliders[kv[0]].changed.emit(kv[1])
	check(await _until(func() -> bool: return d.go_hint.text.contains("低预算"), 3.0), "2-2: star budget hint (%s)" % d.go_hint.text)
	await _shot("star", 0.3)
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	scene.set_speed(8.0)
	await create_timer(3.0).timeout
	scene.set_speed(1.0)
	var lr: Node = scene.level_runner
	lr._update_objective(scene.sim.get_time() - lr.t0)
	check(_find(scene.hud_root, "剩余时间：") != null, "2-2: the clock says 剩余时间")
	await _shot("run", 0.5)
	lr.eval.extinct = true
	lr.finish()
	await _until(func() -> bool: return is_instance_valid(lr.report), 10.0)
	await create_timer(2.0).timeout
	check(_find(lr.report, "实验失败 · 可以这样调整") != null, "2-2 report: first title")
	check(_find(lr.report, "初始投放：") != null and _find(lr.report, "累计分裂：") != null, "2-2 report: the new facts")
	await _shot("report", 5.0)
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()
	# --- 2-3 ---
	scene.start_level(Levels.by_id("2-3"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	d = scene.designer
	g = scene.level_runner.tutorial
	check(await _until(func() -> bool: return _says("这次要设计两个物种")), "2-3 step 1")
	await _shot("23_1")
	g._next()
	check(await _until(func() -> bool: return _says("先调整猎物 A") and g.todo_label.text == "操作提示：将 A 的速度降到最低。"), "2-3 step 2 (%s)" % g.todo_label.text)
	await _shot("23_2")
	d.gene_sliders[0].value = 1.0
	d.gene_sliders[0].changed.emit(1.0)
	check(await _until(func() -> bool: return _says("✓ 猎物速度已降低") and g.todo_label.text == "✓ 已完成"), "2-3 step 2 done")
	check(await _until(func() -> bool: return _says("切换到捕食者设计"), 10.0), "2-3 step 3")
	await _shot("23_3")
	d.slot_tabs[1].pressed.emit()
	check(await _until(func() -> bool: return _says("添加「休眠」")), "2-3 step 4")
	d.show_page("rules")
	await _shot("23_4")
	d.deck_editor.add_state(Rules.S_SLEEP)
	check(await _until(func() -> bool: return _says("两个物种都设置好了"), 8.0), "2-3 step 5")
	await _shot("23_5")
	print("DONE fails=%d" % fails)
	quit()
