extends SceneTree
# Checks the real report button and retry path using an isolated test save.
var scene: Node2D
var fails := 0

func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok: fails += 1

func until(cond: Callable, limit := 30.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000)
	while not cond.call() and Time.get_ticks_msec() < end: await process_frame
	return cond.call()

func find_button(node: Node, label: String) -> Button:
	if node is Button and node.text == label: return node
	for child in node.get_children():
		var found := find_button(child, label)
		if found: return found
	return null

func _run() -> void:
	var id := OS.get_environment("REPORT_LEVEL")
	if id.is_empty(): id = "2-3"
	CampaignSave.data.levels[id] = {stars = [false, false, false], attempts = 2, predictions_right = 0}
	check(CampaignSave.failures(id) == 2, "旧存档未通过时保留已知失败次数")
	CampaignSave.data.levels[id] = {stars = [true, false, false], attempts = 5, predictions_right = 0}
	check(CampaignSave.failures(id) == 0, "旧存档已通过时不猜测失败次数")
	CampaignSave.reset_for_tests()
	var l := Levels.by_id(id)
	# A successful attempt must not count as a failure.
	CampaignSave.record(id, [true, false, false], false)
	scene.start_level(l)
	check(await until(func() -> bool: return scene.designer != null and not scene.designer.busy), "设计器打开")
	scene.designer.release()
	var runner: Node = scene.level_runner
	check(await until(func() -> bool: return runner.phase == "run"), "进入实验")
	runner.finish()
	check(CampaignSave.failures(id) == 1, "一次成功加一次失败，只有一次失败")
	check(find_button(runner.report, "用推荐数值再试一次") == null, "未满两次失败不显示推荐按钮")
	runner._on_report_action("retry", {})
	check(await until(func() -> bool: return scene.designer != null and not scene.designer.busy), "重试进入设计器")
	scene.designer.release()
	check(await until(func() -> bool: return runner.phase == "run"), "重试进入实验")
	runner.finish()
	var button := find_button(runner.report, "用推荐数值再试一次")
	check(CampaignSave.failures(id) == 2 and button != null, "第二次失败后出现推荐按钮")
	if button:
		check(not button.tooltip_text.contains("机器人"), "提示文字不含测算措辞")
		button.pressed.emit()
		check(await until(func() -> bool: return scene.designer != null and not scene.designer.busy), "点击推荐按钮重新打开设计器")
		var d: Control = scene.designer
		check(Recommend.diffs(l, d.genes, 0).is_empty(), "重试套用 A 的基因")
		if id in ["2-3", "6-4", "8-1"]:
			check(Recommend.diffs(l, d.sp_slots[1].genes, 1).is_empty(), "重试套用 B 的基因")
			if id == "6-4":
				check(Recommend.diffs(l, d.sp_slots[2].genes, 2).is_empty(), "重试套用 C 的基因")
		elif id == "4-4":
			check(Recommend.virus_same(Recommend.for_level(id), d.virus_bench.virus), "重试套用病毒")
		elif id == "5-2":
			check(Recommend.body_diffs(Recommend.for_level(id), d.body_bench.cells).is_empty(), "重试套用身体布局")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
