extends SceneTree
# The chapter 3 boss's guide (3-4) has a second part: the first go ends on
# what the scan shows; the next go walks the alarm over to signal B, a drag a
# step. And a level left after its last run line starts its guide again
# instead of showing nothing. Saves proofs/echo_*.png.
# Run: tools/run_test.sh tests/echo_guide_aw.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/echo_%s.png" % name))


func _guide() -> Node:
	return scene.level_runner.tutorial if scene.level_runner else null


func _says(t: String) -> bool:
	var g := _guide()
	return g != null and g.card != null and g.card.visible and g.text_label.text.contains(t)


func _open() -> Control:
	scene.start_level(Levels.by_id("3-4"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	return scene.designer


func _leave() -> void:
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null, 15.0)
	scene.campaign.close()
	await create_timer(0.5).timeout


func _run() -> void:
	# First go.
	var d := await _open()
	check(await _until(func() -> bool: return _says("先投放"), 8.0), "first go: the intro")
	_guide()._next()
	check(await _until(func() -> bool: return _says("投放到培养皿"), 8.0), "... then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "released")
	check(await _until(func() -> bool: return _says("回声菌群") and _says("跟随"), 10.0), "run: asked to scan a rival")
	check(not _guide().next.visible, "... a doing step, it waits for that")
	await create_timer(1.0).timeout
	await _shot("scan_step")
	var sim: SimCore = scene.sim
	var rival: int = scene.level_runner.level.goal.rival
	var mine_p: PackedVector2Array = sim.get_positions(scene.level_runner.sp_index)
	scene.selected = sim.find_agent(mine_p[0], 3.0)
	scene.following = true
	scene.goal_zoom = 18.0
	await create_timer(2.0).timeout
	check(_says("回声菌群") and _says("跟随"), "scanning one of your own does not pass it")
	scene.selected = sim.find_agent(sim.get_positions(rival)[0], 3.0)
	check(await _until(func() -> bool: return _says("释放信号 A") and _says("改方案再试"), 12.0), "scanning a rival: what it shows, what comes next")
	await create_timer(1.0).timeout
	await _shot("scan_done")
	_guide()._next()
	await create_timer(0.3).timeout
	check(CampaignSave.guide_second("3-4") and CampaignSave.guide_at("3-4").is_empty(), "the first part seen to its end")
	# Left without finishing: the guide comes back, as its second part.
	await _leave()
	d = await _open()
	check(await _until(func() -> bool: return _says("上一盘看到了"), 8.0), "back in: the guide is there, its second part")
	await _shot("second_intro")
	_guide()._next()
	check(await _until(func() -> bool: return _says("高级编辑"), 8.0), "rules, advanced")
	d.show_page("rules")
	d.set_rules_mode("advanced")
	var g := _guide()
	check(await _until(func() -> bool: return _says("释放信号 B"), 8.0), "the shout step, alone")
	await create_timer(1.2).timeout
	var chip: Callable = func(t: String) -> Control: return d.piece_chips.filter(func(c: Control) -> bool: return c.text == t)[0]
	check(g.ring.rect.intersects(g._card_part(0, "z_act")) and g.ring.src.intersects((chip.call("释放信号 B") as Control).get_global_rect()), "its slot and the piece are lit")
	await _shot("shout_step")
	d.deck_editor.set_action(0, Rules.A_EMIT_B)
	check(await _until(func() -> bool: return _says("信号 B 浓"), 8.0), "the listen step, alone")
	await create_timer(1.2).timeout
	check(g.ring.rect.intersects(g._card_part(1, "z_g1")) and g.ring.src.intersects((chip.call("信号 B 浓") as Control).get_global_rect()), "its slot and the piece are lit")
	await _shot("listen_step")
	d.deck_editor.set_condition(1, 1, Rules.C_SIGNAL_B)
	check(is_equal_approx(float(d.deck_editor.deck[1].t1), 0.5), "the threshold comes up 0.5 (%.2f)" % float(d.deck_editor.deck[1].t1))
	check(await _until(func() -> bool: return _says("投放到培养皿"), 14.0), "then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "released")
	check(await _until(func() -> bool: return _says("≥ 100"), 10.0), "the second part's run line")
	print("DONE fails=%d" % fails)
	quit()
