extends SceneTree
# Recommended values in the guide (DECISIONS 推荐数值), on 6-5 as the user
# met it: the guide asked for again, a step the design already meets is said
# to be there already (not "设置好了" out of nowhere); then the recommended
# genes, a step each; 一键套用 sets them all and moves on to the release.
# Needs data/recommend.json (tests/recommend_bot.gd). Shoots
# proofs/recommend_steps.png. Prints PASS / FAIL lines.
# Run: tools/run_test.sh tests/recommend_check.gd

var scene: Node2D
var fails := 0


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


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _run() -> void:
	var rec := Recommend.for_level("6-5")
	_check(not rec.is_empty(), "6-5 有推荐数值（%s）" % str(rec))
	scene.start_level(Levels.by_id("6-5"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	# The player's design: fertility already 4 (the guide's only step), the
	# rest off the recommendation.
	var g: Array = d.genes.duplicate()
	g[4] = 4.0
	g[0] = 3.0
	d._set_genes(g)
	scene.level_runner.replay_tutorial() # (跟着引导再试一次 / 查看引导: the guide asked for)
	var tut: Node = scene.level_runner.tutorial
	await create_timer(1.2).timeout
	tut._next() # (the opening card: 知道了)
	await create_timer(1.0).timeout
	var text: String = tut.text_label.text
	_check(text.contains("你的方案里已经有了"), "已满足的步骤说明“方案里已经有了”：%s" % text.left(60))
	_check(tut.cur.has("rec_step"), "接着是推荐数值的一步：%s" % str(tut.cur.get("text", "")).left(60))
	_check(tut.apply_rec.visible, "引导卡上有「一键套用推荐数值」")
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/recommend_steps.png"))
	tut.apply_rec.pressed.emit()
	await create_timer(0.8).timeout
	_check(Recommend.diffs(Levels.by_id("6-5"), d.genes).is_empty(), "套用后基因等于推荐数值 %s" % str(d.genes))
	_check(str(tut.cur.get("wait", "")) == "release", "套用后直接到投放这一步")
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit()
