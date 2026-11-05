extends SceneTree
# 2-1 (第一口) user copy, 2026-11-04: every guide step, the two run lines and
# the failed report (hints, then the how) on screen, one screenshot each.
# Saves proofs/g21_*.png.
# Run: tools/run_test.sh tests/guide_21_copy.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/g21_%s.png" % name))


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
	scene.start_level(Levels.by_id("2-1"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	check(await _until(func() -> bool: return _says("这次你要设计一只捕食者")), "step 1")
	await _shot("1")
	g._next()
	check(await _until(func() -> bool: return _says("这是捕食器官") and g.todo_label.text == "操作提示：安装「刺丝囊」。"), "step 2 + 操作提示 (%s)" % g.todo_label.text)
	await _shot("2")
	d.organ_bay.chips.cnido.pressed.emit()
	check(await _until(func() -> bool: return _says("看看它会怎么捕食")), "step 3")
	await _shot("3")
	d.show_page("rules")
	d.set_rules_mode("simple")
	check(await _until(func() -> bool: return _says("先试试「伏击」")), "step 4 (simple)")
	await _shot("4")
	d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("找到最后一张")), "step 4 (advanced)")
	await _shot("4adv")
	d.set_rules_mode("simple")
	await _until(func() -> bool: return _says("先试试「伏击」"))
	d._pick_persona("ambush")
	check(await _until(func() -> bool: return _says("✓ 已切换为伏击") and g.todo_label.text == "✓ 已完成"), "step 4 done (%s)" % g.todo_label.text)
	await _shot("4done", 0.6)
	check(await _until(func() -> bool: return _says("注意最后一张"), 12.0), "step 5")
	await _shot("5")
	g._next()
	check(await _until(func() -> bool: return _says("看看它能抓到多少猎物")), "step 6")
	await _shot("6")
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	check(await _until(func() -> bool: return _says("不太容易分清"), 10.0), "run 1")
	await _shot("run1")
	g._next()
	check(await _until(func() -> bool: return _says("停下来埋伏"), 10.0), "run 2")
	await _shot("run2")
	var lr: Node = scene.level_runner
	lr.eval.extinct = true
	lr.finish()
	await _until(func() -> bool: return is_instance_valid(lr.report), 10.0)
	await create_timer(2.0).timeout
	check(_find(lr.report, "实验失败 · 可以试试这些调整") != null, "report: first-miss title")
	check(_find(lr.report, "首次捕食用时") != null, "report: first kill row")
	await _shot("report1", 5.0)
	var how: Node = _find(lr.report, "查看具体做法")
	if how:
		how.pressed.emit()
	check(await _until(func() -> bool: return _find(lr.report, "实验失败 · 检查一下行为设置") != null), "report: the how, its title")
	await _shot("report2", 1.0)
	print("DONE fails=%d" % fails)
	quit()
