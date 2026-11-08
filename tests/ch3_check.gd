extends SceneTree
# Chapter 3. Level 11 (3-1, 化学之声): the alarm call. Speed, the two signal
# organs, the flee card turned into a shout, a new "smell -> flee" card above
# feeding; the guide rings each; the report's hints follow the design.
# Run: tools/run_test.sh tests/ch3_check.gd

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


func _shot(name: String, wait := 0.5) -> void:
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/ch3_%s.png" % name))


func _says(bit: String) -> bool:
	var g: Node = scene.level_runner.tutorial
	return g != null and g.card.visible and g.text_label.text.contains(bit)


func _find_text(n: Node, bit: String) -> bool:
	if n is Label and (n as Label).text.contains(bit):
		return true
	for c in n.get_children():
		if _find_text(c, bit):
			return true
	return false


func _level11() -> void:
	scene.start_level(Levels.by_id("3-1"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "3-1: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	var bay: Control = d.organ_bay
	check(bay.chips.gland.modulate.a > 0.9 and bay.chips.chemo_rec.modulate.a > 0.9, "3-1: the signal gland and chemoreceptor are open")
	check(not d.deck_editor.deck.is_empty() and d.deck_editor.deck[0].act == Rules.A_FLEE, "3-1: hunters about: the deck keeps its flee card")
	g._next()
	check(await _until(func() -> bool: return _says("先提高速度")), "3-1: the speed step")
	var gg: Array = d.genes.duplicate()
	gg[0] = 4.0
	gg[4] = 2.0
	d._set_genes(gg)
	var used := 0.0
	for v: float in d.genes:
		used += v - 1.0
	check(used <= float(Levels.by_id("3-1").star_budget), "3-1: speed 4 + fertility 2 keeps the low-budget line (%.1f)" % used)
	check(await _until(func() -> bool: return _says("信号腺"), 8.0), "3-1: the organs step")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(bay.chips.gland.get_global_rect()) and g.ring.rect.intersects(bay.chips.chemo_rec.get_global_rect()), "3-1: both signal organs are ringed")
	bay.chips.gland.pressed.emit()
	bay.chips.chemo_rec.pressed.emit()
	check(d.organs.has("gland") and d.organs.has("chemo_rec"), "3-1: both installed (%s)" % str(d.organs))
	check(await _until(func() -> bool: return _says("高级编辑") or _says("释放信号 A"), 8.0), "3-1: on to the rules page, advanced")
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("释放信号 A"), 8.0), "3-1: the shout step")
	await _until(func() -> bool: return g.ring.rect.intersects(d.deck_editor.card_rect(0)), 4.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(0)), "3-1: the flee card is ringed")
	d.deck_editor.set_action(0, Rules.A_EMIT_A)
	check(await _until(func() -> bool: return _says("添加规则"), 12.0), "3-1: then a new card")
	check(d.deck_editor.selected == 0, "3-1: the add step selects the shout card for you (%d)" % d.deck_editor.selected)
	var at: int = d.deck_editor.add_card()
	check(d.deck_editor.warning(2).contains("新卡还空着"), "3-1: under the blank new card the warning says it is temporary (%s)" % d.deck_editor.warning(2))
	check(at == 1, "3-1: the new card goes in under the selected first one (%d)" % at)
	check(await _until(func() -> bool: return _says("信号 A 浓"), 12.0), "3-1: then smell -> flee")
	await _until(func() -> bool: return g.ring.rect.intersects(d.deck_editor.card_rect(1)), 4.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(1)), "3-1: the new card is ringed")
	await _shot("alarm")
	d.deck_editor.set_condition(1, 1, Rules.C_SIGNAL_A)
	d.deck_editor.set_action(1, Rules.A_FLEE)
	check(await _until(func() -> bool: return _says("投放"), 12.0), "3-1: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "3-1: released, the clock runs")
	var lr: Node = scene.level_runner
	var deck: Array = scene.sim.get_species_deck(lr.sp_index)
	check(deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_EMIT_A) and deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_FLEE and Rules.C_SIGNAL_A in [c.c1, c.c2]), "3-1: shout and smell-flee reach the simulation")
	scene.set_speed(8.0)
	await create_timer(5.0).timeout
	scene.set_speed(1.0)
	await _shot("run")
	lr.eval.extinct = true
	lr.finish()
	await _until(func() -> bool: return is_instance_valid(lr.report), 10.0)
	await create_timer(1.5).timeout
	await _shot("report", 6.0)
	check(not _find_text(lr.report, "没告诉同伴") and not _find_text(lr.report, "没有一张卡让它跑") and not _find_text(lr.report, "跑得不比暗噬快") and not _find_text(lr.report, "会喊的器官") and _find_text(lr.report, "做得不错"), "3-1: the guided plan failing: no hint blames it")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()


# Level 12 (3-2, 一起生): breeding together. The recognition protein, the
# breeding state and its way in, a new "see a peer in breeding -> breed" card
# under the first; the guide rings each; the report's hints follow the design.
func _level12() -> void:
	scene.start_level(Levels.by_id("3-2"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "3-2: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	var bay: Control = d.organ_bay
	check(bay.chips.recog.modulate.a > 0.9, "3-2: the recognition protein is open")
	g._next()
	check(await _until(func() -> bool: return _says("识别蛋白")), "3-2: the organ step")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(bay.chips.recog.get_global_rect()), "3-2: the recognition protein is ringed")
	bay.chips.recog.pressed.emit()
	check(d.organs.has("recog"), "3-2: installed")
	check(await _until(func() -> bool: return _says("高级编辑") or _says("添加「繁殖期」"), 8.0), "3-2: on to the rules page, advanced")
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("添加「繁殖期」"), 8.0), "3-2: the breeding-state step")
	d.deck_editor.add_state(Rules.S_BREED)
	check(await _until(func() -> bool: return _says("「进入繁殖期」拖到"), 12.0), "3-2: then the way in")
	d.deck_editor.set_state(Rules.S_FORAGE)
	await create_timer(0.4).timeout
	var dv: int = d.deck_editor.deck.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_DIVIDE)
	d.deck_editor.set_action(dv, Rules.A_TO_BREED)
	check(await _until(func() -> bool: return _says("规则卡已经满了"), 12.0), "3-2: then make room")
	var rk: int = d.deck_editor.deck.find_custom(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_REST)
	await _until(func() -> bool: return g.ring.rect.intersects(d.deck_editor.card_rect(rk)), 4.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(rk)), "3-2: the rest card is ringed")
	d.deck_editor.remove_card(rk)
	await create_timer(0.6).timeout
	check(await _until(func() -> bool: return _says("添加规则"), 12.0), "3-2: then a new card")
	check(d.deck_editor.selected == 0, "3-2: the add step selects the first card for you (%d)" % d.deck_editor.selected)
	var at: int = d.deck_editor.add_card()
	check(at == 1, "3-2: the new card is the second (%d)" % at)
	check(await _until(func() -> bool: return _says("看见同伴在"), 12.0), "3-2: then see-a-peer -> breed")
	await _until(func() -> bool: return g.ring.rect.intersects(d.deck_editor.card_rect(1)), 4.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(1)), "3-2: the new card is ringed")
	d.deck_editor.set_condition(1, 1, Rules.C_PEER_STATE)
	check(roundi(d.deck_editor.deck[1].t1) == Rules.S_BREED, "3-2: the new condition reads 繁殖期 by default (%s)" % Rules.card_text(d.deck_editor.deck[1]))
	await _shot("sync")
	d.deck_editor.set_action(1, Rules.A_TO_BREED)
	check(await _until(func() -> bool: return _says("投放"), 12.0), "3-2: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "3-2: released, the clock runs")
	var lr: Node = scene.level_runner
	var deck: Array = scene.sim.get_species_deck(lr.sp_index)
	check(deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_TO_BREED and Rules.C_PEER_STATE in [c.c1, c.c2]), "3-2: the breed-together card reaches the simulation")
	scene.set_speed(8.0)
	await create_timer(5.0).timeout
	scene.set_speed(1.0)
	await _shot("sync_run")
	lr.eval.extinct = true
	lr.finish()
	await _until(func() -> bool: return is_instance_valid(lr.report), 10.0)
	await create_timer(1.5).timeout
	await _shot("sync_report", 6.0)
	check(not _find_text(lr.report, "认不出") and not _find_text(lr.report, "各生各的") and not _find_text(lr.report, "繁殖调低") and (_find_text(lr.report, "差一点") or _find_text(lr.report, "种群还差") or _find_text(lr.report, "路子对了")), "3-2: the guided plan failing: no hint blames it")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()


# Level 13 (3-3, 够多才动手): quorum. A new card "crowd >= 4 -> secrete"
# under the first; the guide rings it; the report's hints follow the design.
func _level13() -> void:
	scene.start_level(Levels.by_id("3-3"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "3-3: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	check(not d.deck_editor.deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_FLEE), "3-3: no hunters: no flee card")
	g._next()
	check(await _until(func() -> bool: return _says("速度调到 3"), 8.0), "3-3: the genes step")
	var gg: Array = d.genes.duplicate()
	gg[0] = 3.0
	gg[4] = 4.0
	d._set_genes(gg)
	var used := 0.0
	for v: float in d.genes:
		used += v - 1.0
	check(used <= float(Levels.by_id("3-3").star_budget), "3-3: speed 3 + fertility 4 keeps the low-budget line (%.1f)" % used)
	check(await _until(func() -> bool: return _says("高级编辑") or _says("添加规则"), 8.0), "3-3: on to the rules page, advanced")
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("添加规则"), 8.0), "3-3: the new-card step")
	check(d.deck_editor.selected == 0, "3-3: the first card is selected for you (%d)" % d.deck_editor.selected)
	var at: int = d.deck_editor.add_card()
	check(at == 1, "3-3: the new card is the second (%d)" % at)
	check(await _until(func() -> bool: return _says("同伴很多"), 12.0), "3-3: then crowd -> secrete")
	await _until(func() -> bool: return g.ring.rect.intersects(d.deck_editor.card_rect(1)), 4.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(1)), "3-3: the new card is ringed")
	d.deck_editor.set_condition(1, 1, Rules.C_CROWD)
	d.deck_editor.set_threshold(1, 1, 4.0, true)
	await _shot("quorum")
	d.deck_editor.set_action(1, Rules.A_SECRETE)
	check(await _until(func() -> bool: return _says("投放"), 12.0), "3-3: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "3-3: released, the clock runs")
	var lr: Node = scene.level_runner
	var deck: Array = scene.sim.get_species_deck(lr.sp_index)
	check(deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_SECRETE and Rules.C_CROWD in [c.c1, c.c2]), "3-3: the quorum card reaches the simulation")
	scene.set_speed(8.0)
	await create_timer(5.0).timeout
	scene.set_speed(1.0)
	await _shot("quorum_run")
	lr.eval.extinct = true
	lr.finish()
	await _until(func() -> bool: return is_instance_valid(lr.report), 10.0)
	await create_timer(1.5).timeout
	await _shot("quorum_report", 6.0)
	check(not _find_text(lr.report, "自己啃硬藻") and not _find_text(lr.report, "落单的时候也在分泌") and not _find_text(lr.report, "就开始分泌") and (_find_text(lr.report, "种群还差") or _find_text(lr.report, "再试一次")), "3-3: the guided plan failing: no hint blames it")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()


# Chapter 3 boss (3-4, 回声菌群): it opens on level 11's alarm plan; one
# guided step moves the alarm to signal B; the objective counts both sides.
func _level14() -> void:
	scene.start_level(Levels.by_id("3-4"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "3-4: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	check(d.organs.has("gland") and d.organs.has("chemo_rec"), "3-4: it opens with level 11's organs (%s)" % str(d.organs))
	check(d.deck_editor.deck.size() >= 2 and d.deck_editor.deck[0].act == Rules.A_EMIT_A and d.deck_editor.deck[1].c1 == Rules.C_SIGNAL_A, "3-4: ... and its alarm on signal A")
	check(not Levels.by_id("3-4").brief.contains("信号 B") and not Levels.by_id("3-4").teach.contains("信号 B"), "3-4: the brief gives nothing away")
	g._next()
	check(await _until(func() -> bool: return _says("投放"), 8.0), "3-4: straight to the release")
	# First the player's own try: they trust signal A, and are fooled.
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "3-4: released, the clock runs")
	var lr: Node = scene.level_runner
	scene.set_speed(8.0)
	await create_timer(5.0).timeout
	scene.set_speed(1.0)
	lr._update_objective(scene.sim.get_time() - lr.t0)
	check(scene.hud_root.env["objective"][1].text.contains("回声菌群"), "3-4: the objective counts both sides (%s)" % scene.hud_root.env["objective"][1].text)
	await _shot("echo_run")
	lr.eval.extinct = true
	lr.finish()
	await _until(func() -> bool: return is_instance_valid(lr.report), 10.0)
	await create_timer(1.5).timeout
	await _shot("echo_report", 6.0)
	check(_find_text(lr.report, "假警报"), "3-4: fooled by signal A: the report says so")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()


func _run() -> void:
	await create_timer(1.0).timeout
	await _level11()
	await _level12()
	await _level13()
	await _level14()
	check(Levels.ALL.size() >= 11 and Levels.ALL[10].id == "3-1", "the campaign lists level 11")
	CampaignSave.record("2-5", [true, false, false], false)
	check(CampaignSave.unlocked(11), "level 11 opens after level 10")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
