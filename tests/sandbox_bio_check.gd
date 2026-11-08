extends SceneTree
# The sandbox's second batch (DECISIONS 沙盒补全 Q277): the designer's virus
# page (target picked, applied, dropped with 投放病毒) and body page (多细胞
# on: a multicell species released). Shoots proofs/sandbox_virus.png,
# sandbox_body.png, sandbox_colony.png. Prints PASS / FAIL lines.
# Run: tools/run_test.sh tests/sandbox_bio_check.gd

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


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


func _run() -> void:
	await create_timer(1.5).timeout
	scene.iv.select("phage")
	_check(scene.mode != "phage", "没设计病毒时投放病毒会提示，不会进入投放")
	scene.open_designer()
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 20.0)
	var d: Control = scene.designer
	_check(d.tab_buttons.has("virus") and d.tab_buttons.has("body"), "沙盒设计器有病毒设计页和身体页")
	d.show_page("virus")
	await create_timer(1.0).timeout
	await _shot("sandbox_virus")
	d.virus_target = 0
	scene.sandbox_world.set_virus(d.virus_bench.virus.duplicate(), 0)
	_check(scene.sandbox_world.virus_host == 0, "病毒设计已应用（感染物种 0）")
	d.show_page("body")
	await create_timer(1.0).timeout
	d.multicell = true
	d._sync_multi()
	d._refresh()
	await create_timer(0.6).timeout
	await _shot("sandbox_body")
	_check((d._design().blocks as Array).size() >= 3, "多细胞开：设计带着身体方块")
	var n0: int = scene.colors.size()
	d.release()
	await _until(func() -> bool: return scene.designer == null, 10.0)
	scene._do_release(Vector2(1100, 1100))
	await create_timer(3.5).timeout
	_check(scene.colors.size() == n0 + 1, "投放了一个新物种")
	var st: Dictionary = scene.sim.get_colony_stats()
	_check(scene.sandbox_world.colony_on and int(st.get("alive", st.get("colonies", 1))) >= 0, "多细胞规则已交给内核")
	var pos: PackedVector2Array = scene.sim.get_positions(n0)
	_check(pos.size() > 0, "多细胞群体在皿里（%d 个）" % pos.size())
	scene.focus(Vector2(1100, 1100), 2.0)
	await create_timer(1.5).timeout
	await _shot("sandbox_colony")
	scene.iv.select("phage")
	_check(scene.mode == "phage", "设好病毒后可以投放")
	var ph0: int = scene.sim.get_phages(Rect2(0, 0, 2200, 2200), 1.0).size()
	scene.iv.place("phage", Vector2(1000, 900))
	await create_timer(0.5).timeout
	_check(scene.sim.get_phages(Rect2(0, 0, 2200, 2200), 1.0).size() > ph0, "投下了病毒")
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit()
