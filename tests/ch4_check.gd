extends SceneTree
# Chapter 4. Level 15 (4-1, 看不见的敌人): the guide through "crowd >= 2 ->
# away from peers", the first infection shown close up, the burst and its
# count, the report's hints follow the design.
# Run: tools/run_test.sh tests/ch4_check.gd

var scene: Node2D
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	Levels.force_guides = true # (guides past chapter 1 come on request: here always)
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


func _says(bit: String) -> bool:
	var g: Node = scene.level_runner.tutorial
	return g != null and g.card.visible and g.text_label.text.contains(bit)


func _run() -> void:
	await _level15()
	await _level16()
	await _level17()
	await _level18()
	await _level19()
	print("ch4: %d failed" % fails)
	quit(1 if fails > 0 else 0)


func _level19() -> void:
	CampaignSave.record("4-4", [true, false, false], false)
	scene.start_level(Levels.by_id("4-5"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "4-5: the designer opens")
	var d: Control = scene.designer
	check(await _until(func() -> bool: return d.page == "virus", 5.0), "4-5: on the virus page")
	var vb: Control = d.virus_bench
	check(vb.virophage, "4-5: the bench makes a virophage")
	check(d.tab_buttons.genome.visible and d.tab_buttons.rules.visible, "4-5: the cell pages are open too")
	check(scene.level_runner.tutorial != null, "4-5: the guide is on")
	d.show_page("genome")
	check(d.page == "genome", "4-5: over to the genes")
	await process_frame
	check(d.genome.visible, "4-5: the genome shows on its page")
	d.show_page("virus")
	await process_frame
	check(not d.genome.visible, "4-5: and not on the virus page")
	vb.set_trait("speed", 1)
	vb.set_trait("burst", 2)
	vb.set_trait("shell", 1)
	vb.set_trait("speed", 5)
	vb.set_trait("stick", 3)
	vb._set_mode(true)
	check(int(vb.virus.speed) == 5 and vb.virus.temperate, "4-5: a temperate design (%s)" % str(vb.virus))
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "4-5: released")
	var lr: Node = scene.level_runner
	check(lr.design.has("virus") and lr.design.virus.temperate, "4-5: the design carries the virus")
	check(int(scene.sim.get_giant_stats().total) >= int(lr.level.giant.start) - 1, "4-5: the giants are in the water (%s)" % str(scene.sim.get_giant_stats()))
	var near := 1e9
	for p: Vector2 in scene.sim.get_giant_positions():
		near = minf(near, p.distance_to(lr.level.release.at))
	check(near > 150.0, "4-5: none right on the release (%d)" % int(near))
	scene.iv.points = 300.0
	scene.iv.place("phage", LevelEval.rival_thick(scene.sim, lr.sp_index))
	check(lr.eval.shots == 1, "4-5: a drop is counted")
	check(await _until(func() -> bool: return lr.fired.has("first_carrier"), 15.0), "4-5: it settles in a cell's genes")
	scene.set_speed(3.0)
	check(await _until(func() -> bool: return lr.fired.has("phage_seen"), 40.0), "4-5: a factory is noticed")
	var info: Dictionary = scene.sim.get_agent(lr.tagged_id)
	check(bool(info.get("factory", false)), "4-5: the cell tagged has a factory")
	check(not scene.following, "4-5: the camera stays where it was")
	check(await _until(func() -> bool: return lr.eval.lysed >= 1, 30.0), "4-5: a factory bursts")
	check(await _until(func() -> bool: return int(lr.eval.giant_stats.hijacked) >= 1, 40.0), "4-5: carriers fight back (%s)" % str(lr.eval.giant_stats))
	check(lr.eval.curve[-1][2] == maxi(lr.eval.giants, 0), "4-5: the chart follows the giants")
	lr.finish()
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 10.0), "4-5: the report opens")
	check(lr.report._has_control() == false, "4-5: no control experiment here")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)


func _level18() -> void:
	CampaignSave.record("4-3", [true, false, false], false)
	scene.start_level(Levels.by_id("4-4"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "4-4: the designer opens")
	var d: Control = scene.designer
	check(d.virus_bench != null, "4-4: the virus bench is there")
	check(await _until(func() -> bool: return d.page == "virus", 5.0), "4-4: on the virus page")
	var vb: Control = d.virus_bench
	check(vb.used() == 12, "4-4: starts with all the points spent (%d)" % vb.used())
	vb.set_trait("burst", 5)
	check(int(vb.virus.burst) == 3, "4-4: no points left: the trait does not go up")
	vb.set_trait("speed", 2)
	vb.set_trait("burst", 2)
	vb.set_trait("shell", 5)
	check(int(vb.virus.shell) == 5 and vb.used() <= 12, "4-4: points move between traits (%s)" % str(vb.virus))
	var g: Node = scene.level_runner.tutorial
	if g:
		g._skip()
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "4-4: released")
	var lr: Node = scene.level_runner
	check(lr.design.has("virus") and int(lr.design.virus.shell) == 5, "4-4: the design carries the virus")
	var at: Vector2 = LevelEval.rival_thick(scene.sim, 0)
	await create_timer(1.0).timeout
	scene.iv.place("phage", at)
	check(lr.eval.shots == 1 and lr.eval.shot_times.size() == 1, "4-4: a drop is counted")
	check(scene.sim.get_phage_count() >= 50, "4-4: the virus is in the water (%d)" % scene.sim.get_phage_count())
	lr.eval.extinct = true
	lr.finish()
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 10.0), "4-4: the report opens")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)


func _level17() -> void:
	CampaignSave.record("4-2", [true, false, false], false)
	scene.start_level(Levels.by_id("4-3"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "4-3: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	check(g != null, "4-3: the guide is on")
	g._next()
	check(await _until(func() -> bool: return _says("高级编辑") or _says("添加规则"), 8.0), "4-3: on to the rules")
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("添加规则"), 8.0), "4-3: the new-card step")
	var at: int = d.deck_editor.add_card()
	check(at == 1, "4-3: the new card is the second (%d)" % at)
	check(await _until(func() -> bool: return _says("年龄超过"), 12.0), "4-3: then the age condition")
	d.deck_editor.set_condition(1, 1, Rules.C_AGE_ABOVE)
	check(await _until(func() -> bool: return _says("唤醒潜伏针"), 12.0), "4-3: then the wake card")
	d.deck_editor.set_action(1, Rules.A_INDUCE)
	check(await _until(func() -> bool: return _says("投放到培养皿"), 15.0), "4-3: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "4-3: released")
	var lr: Node = scene.level_runner
	scene.set_speed(8.0)
	check(await _until(func() -> bool: return lr.fired.has("phage_seen"), 40.0), "4-3: a carried phage wakes, and is noticed")
	check(not scene.following and lr.tagged_id >= 0, "4-3: the cell is tagged, the camera stays")
	scene.set_speed(8.0)
	check(await _until(func() -> bool: return lr.eval.rival_lysed >= 1, 40.0), "4-3: the rival starts to burst (%d)" % lr.eval.rival_lysed)
	check(lr.eval.lysed >= 1, "4-3: the player's burst cell is counted (%d)" % lr.eval.lysed)
	lr.finish()
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 10.0), "4-3: the report opens")
	var hints: Array = lr.report._latent_hints()
	check(not hints.is_empty() and str(hints[0]).contains("方向是对的"), "4-3: the guided plan is not blamed (%s)" % str(hints))
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)


func _level16() -> void:
	scene.start_level(Levels.by_id("4-2"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "4-2: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	check(g != null, "4-2: the guide is on")
	check(d.deck_editor.deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_DISPERSE), "4-2: it starts from level 15's plan")
	g._next()
	check(await _until(func() -> bool: return _says("记忆片段"), 8.0), "4-2: the organ step")
	d.organ_bay.chips.crispr.pressed.emit()
	check(d.organs.has("crispr"), "4-2: the memory fragment goes in")
	check(await _until(func() -> bool: return _says("高级编辑") or _says("有免疫记忆"), 8.0), "4-2: on to the rules")
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("第二个条件格"), 8.0), "4-2: the second condition")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO, 3.0)
	check(g.ring.rect.size != Vector2.ZERO, "4-2: its slot is ringed")
	d.deck_editor.set_condition(1, 2, Rules.C_IMMUNE)
	check(await _until(func() -> bool: return _says("前面的“不”"), 8.0), "4-2: then the 不")
	await create_timer(0.5).timeout
	check(g.ring.rect.size != Vector2.ZERO, "4-2: the 不 is ringed")
	d.deck_editor.toggle_neg(1, 2)
	check(await _until(func() -> bool: return _says("投放到培养皿"), 15.0), "4-2: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "4-2: released")
	var lr: Node = scene.level_runner
	var ps: PackedVector2Array = scene.sim.get_positions(lr.sp_index)
	scene.sim.add_phages(ps[0], 50.0, 300)
	check(await _until(func() -> bool: return lr.fired.has("memory_seen"), 30.0), "4-2: a first memory is noticed")
	check(not scene.following and lr.tagged_id >= 0, "4-2: the cell is tagged, the camera stays")
	check(await _until(func() -> bool: return lr.eval.immune >= 1, 12.0), "4-2: the memory counts (%d)" % lr.eval.immune)
	await create_timer(1.0).timeout
	lr.eval.extinct = true
	lr.finish()
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 10.0), "4-2: the report opens")
	var hints: Array = lr.report._memory_hints()
	check(not hints.is_empty() and not str(hints[0]).contains("没有记忆片段") and not str(hints[0]).contains("也在躲"), "4-2: the guided plan is not blamed (%s)" % str(hints))
	check(not _report_says(lr.report, "第四章 · 噬体篇 完成"), "4-2: the chapter is not called finished")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)


func _report_says(n: Node, bit: String) -> bool:
	if n is Label and (n as Label).text.contains(bit):
		return true
	for c in n.get_children():
		if _report_says(c, bit):
			return true
	return false


func _level15() -> void:
	scene.start_level(Levels.by_id("4-1"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "4-1: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	check(g != null, "4-1: the guide is on")
	check(d.deck_editor.deck.size() >= 2 and not d.deck_editor.deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_FLEE), "4-1: no hunters: no flee card")
	g._next()
	check(await _until(func() -> bool: return _says("高级编辑") or _says("添加规则"), 8.0), "4-1: on to the rules page, advanced")
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("添加规则"), 8.0), "4-1: the new-card step")
	check(d.deck_editor.selected == 0, "4-1: the first card is selected for you (%d)" % d.deck_editor.selected)
	var at: int = d.deck_editor.add_card()
	check(at == 1, "4-1: the new card is the second (%d)" % at)
	check(await _until(func() -> bool: return _says("同伴很多"), 12.0), "4-1: then the crowd condition")
	d.deck_editor.set_condition(1, 1, Rules.C_CROWD)
	check(await _until(func() -> bool: return _says("远离同伴"), 8.0), "4-1: then the away-from-peers card")
	d.deck_editor.set_action(1, Rules.A_DISPERSE)
	check(await _until(func() -> bool: return _says("投放到培养皿"), 15.0), "4-1: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "4-1: released")
	var lr: Node = scene.level_runner
	check(scene.zoom_max > 20.0, "4-1: the camera can go in far enough to see a phage")
	# Don't wait for the rain: phages right on the cells.
	var ps: PackedVector2Array = scene.sim.get_positions(lr.sp_index)
	scene.sim.add_phages(ps[0], 20.0, 200)
	check(await _until(func() -> bool: return lr.fired.has("phage_seen"), 15.0), "4-1: the first infection is noticed")
	check(not scene.following and scene.selected < 0, "4-1: the camera and the selection stay the player's")
	check(scene.speed > 0.9, "4-1: the speed stays too (%.1f)" % scene.speed)
	check(lr.tagged_id >= 0 and scene.phage_layer.tags.size() >= 1, "4-1: the cell that was hit is tagged")
	scene.set_speed(3.0)
	check(scene.sim.get_infected(Rect2(0, 0, 2200, 2200), 0.0).size() >= 10, "4-1: an infected cell in the kernel")
	check(await _until(func() -> bool: return lr.eval.lysed >= 1, 30.0), "4-1: the first burst comes")
	await create_timer(0.3).timeout
	var st: Dictionary = scene.sim.get_stats().species[lr.sp_index]
	check(int(st.phage) >= 1, "4-1: the burst is counted (%d)" % int(st.phage))
	check(lr.eval.lysed >= 1 or await _until(func() -> bool: return lr.eval.lysed >= 1, 3.0), "4-1: and reaches the level's count")
	check(scene.sim.get_phage_count() > 0, "4-1: new phages in the water (%d)" % scene.sim.get_phage_count())
	var hud := str(scene.hud_root.objective_text()) if scene.hud_root.has_method("objective_text") else ""
	print("objective: ", hud)
	lr.eval.extinct = true
	lr.finish()
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 10.0), "4-1: the report opens")
	var hints: Array = lr.report._phage_hints()
	check(not hints.is_empty() and str(hints[0]).contains("方向是对的"), "4-1: with the card in, the report says the direction is right (%s)" % str(hints))
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	await create_timer(0.5).timeout
