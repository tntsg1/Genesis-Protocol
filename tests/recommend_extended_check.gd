extends SceneTree
# Run with tools/run_test.sh; HELP_CASE selects multispecies, virus, or body.
# Each invocation uses the test save and never moves the real cursor.

var scene: Node2D
var fails := 0

func _initialize() -> void:
	CampaignSave.reset_for_tests()
	Levels.force_guides = true
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func until(cond: Callable, limit := 30.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/recommend_extended_%s.png" % name))

func _run() -> void:
	var which := OS.get_environment("HELP_CASE")
	var id := {multispecies = "2-3", multi3 = "6-4", multi8 = "8-1", virus = "4-4", body = "5-2", body3 = "5-3", body4 = "5-4", body5 = "5-5"}.get(which, "") as String
	if id.is_empty():
		print("FAIL  unknown HELP_CASE")
		quit(1)
		return
	var l := Levels.by_id(id)
	if which.begins_with("body") and Recommend.for_level(id).is_empty():
		# A controlled fixture, separate from the measured recommendation file.
		var blocks: Array = l.start_design.blocks.duplicate(true)
		blocks[0][2] = 6 if int(blocks[0][2]) != 6 else 1
		Recommend._data[id] = {genes = (l.start_design.genes as Array).duplicate(), blocks = blocks, wins = 1, seeds = 1}
	scene.start_level(l)
	if not await until(func() -> bool: return scene.designer != null and not scene.designer.busy):
		print("FAIL  designer did not open")
		quit(1)
		return
	var d: Control = scene.designer
	scene.level_runner.replay_tutorial()
	var g: Node = scene.level_runner.tutorial
	if which in ["multispecies", "multi3", "multi8"]:
		var rec := Recommend.for_level(id)
		var a: Array = d.genes.duplicate()
		a[0] = 1.0 if float(rec.genes[0]) != 1.0 else 2.0
		d._set_genes(a)
		var b: Array = (d.sp_slots[1].genes as Array).duplicate()
		b[0] = 1.0 if float(rec.extra[0][0]) != 1.0 else 2.0
		d.sp_slots[1].genes = b
		if which == "multi3":
			var c: Array = (d.sp_slots[2].genes as Array).duplicate()
			c[0] = 1.0 if float(rec.extra[1][0]) != 1.0 else 2.0
			d.sp_slots[2].genes = c
		var steps: Array = g._rec_steps()
		var a_step := -1
		var b_tab := -1
		for i in steps.size():
			if a_step < 0 and str(steps[i].get("wait", "")).begins_with("gene:"): a_step = i
			if str(steps[i].get("wait", "")) == "slot:1": b_tab = i
		check(a_step >= 0 and b_tab > a_step, "先调整 A，再提示切换 B")
		if a_step >= 0:
			g.lines = steps.duplicate(true)
			g._next()
			await create_timer(1.0).timeout
			await shot(which)
			g._apply_rec()
		check(Recommend.diffs(l, d.genes, 0).is_empty(), "套用 A 物种推荐基因")
		check(Recommend.diffs(l, d.sp_slots[1].genes, 1).is_empty(), "套用 B 物种推荐基因")
		if which == "multi3":
			check(Recommend.diffs(l, d.sp_slots[2].genes, 2).is_empty(), "套用 C 物种推荐基因")
	elif which == "virus":
		var rec := Recommend.for_level(id)
		var vb: Control = d.virus_bench
		for k: String in Recommend.TRAITS: vb.set_trait(k, 3)
		var steps: Array = g._rec_steps()
		var vi := -1
		for i in steps.size():
			if steps[i].get("rec_kind", "") == "virus": vi = i; break
		check(vi >= 0 and str(steps[vi].get("wait", "")).begins_with("vtrait:"), "病毒数值进入调整步骤")
		if vi >= 0:
			g.cur = steps[vi]
			g.lines.clear()
			g._apply_rec()
		check(Recommend.virus_same(rec, vb.virus), "一键套用病毒数值")
		var runner: Node = scene.level_runner
		g._skip()
		d.release()
		check(await until(func() -> bool: return runner.phase == "run", 15.0), "投放后进入培养皿")
		check(Recommend.virus_same(rec, runner.design.virus), "实际投放保留推荐病毒")
		runner._drop_reminders(Recommend.first_drop(rec) - 1.0)
		check(scene.hud_root.coach_list.is_empty(), "投放时间前不提醒")
		scene.set_speed(8.0)
		check(await until(func() -> bool: return runner.eval.t >= Recommend.first_drop(rec), 45.0), "实际模拟到第一次投放时间")
		check(not scene.hud_root.coach_list.is_empty() and scene.hud_root.coach_list.back().title == "该投第一团病毒了", "到点提醒第一团")
		await create_timer(1.0).timeout
		await shot("virus")
		runner.eval.shots = 1
		runner.eval.shot_times = [Recommend.first_drop(rec)]
		runner._drop_reminders(Recommend.second_drop(rec))
		check(scene.hud_root.coach_list.back().title == "可以投第二团了", "到点提醒第二团")
		runner.coach_said.erase("drop2")
		runner.eval.shot_times = [Recommend.first_drop(rec) + 5.0]
		var before: int = scene.hud_root.coach_list.size()
		runner._drop_reminders(Recommend.second_drop(rec))
		check(scene.hud_root.coach_list.size() == before, "第一团投晚时，第二次提醒等待完整间隔")
		runner._drop_reminders(Recommend.second_drop(rec) + 5.0)
		check(scene.hud_root.coach_list.size() == before + 1, "第一团投晚后仍按间隔提醒")
	else:
		var rec := Recommend.for_level(id)
		var genes: Array = d.genes.duplicate()
		var k: int = int(l.genes_open[0])
		genes[k] = 1.0 if float(rec.genes[k]) != 1.0 else 2.0
		d._set_genes(genes)
		var steps: Array = g._rec_steps()
		var body_step := -1
		for i in steps.size():
			if steps[i].get("rec_kind", "") == "body": body_step = i; break
		check(body_step >= 0 and not steps[body_step].get("marks", []).is_empty(), "身体差异生成格子标记")
		if body_step >= 0:
			g.lines = steps.duplicate(true)
			g._next()
			await create_timer(1.0).timeout
			check(not d.body_bench.rec_marks.is_empty(), "当前引导步骤在身体板上标记")
			var card_rect: Rect2 = g.card.get_global_rect()
			check(not card_rect.intersects(d.body_bench.scope.get_global_rect()), "推荐卡不遮挡身体板")
			check(not card_rect.intersects(d.body_bench.strand.get_global_rect()), "推荐卡不遮挡基因条")
			check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(card_rect), "推荐卡完整显示在画面内")
			check(g.apply_rec.visible and card_rect.encloses(g.apply_rec.get_global_rect()), "一键套用按钮显示在卡片内")
			await shot(which)
			g.apply_rec.pressed.emit()
		check(Recommend.body_diffs(rec, d.body_bench.cells).is_empty(), "一键套用身体布局")
		check(str(g.cur.get("wait", "")).begins_with("gene:"), "套用身体后进入基因步骤")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
