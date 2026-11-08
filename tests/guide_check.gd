extends SceneTree
# The guided steps of chapter 1 (levels 2-5): each step rings the control it
# talks about and moves on by itself once the player has done it.
#   1-2: the read-only deck card by card; after release: pick a cell, pause,
#        single-step (the deck trace lights the card that runs)
#   1-3: rules tab -> divide slider (beside its condition) -> speed -> release
#   1-4: rest sits above divide (the sample never divides): drag divide up;
#        the warm-spot step waits for the cold front, then for a warm spot
#   1-5: the temperature step, the swarm personality (新 tags, the card off the deck),
#        then the current step after release
# Run: tools/run_test.sh tests/guide_check.gd

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


func _shot(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/guide_%s.png" % name))


func _click(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	return e


func _find_text(n: Node, bit: String) -> bool:
	if n is Label and (n as Label).text.contains(bit):
		return true
	for c in n.get_children():
		if _find_text(c, bit):
			return true
	return false


func _guide() -> Node:
	return scene.level_runner.tutorial


func _says(bit: String) -> bool:
	var g := _guide()
	return g != null and g.card.visible and g.text_label.text.contains(bit)


func _open(id: String) -> Control:
	scene.start_level(Levels.by_id(id))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	return scene.designer


func _run() -> void:
	# --- 1-2 --- read-only rules, then a cell's live deck
	var d := await _open("1-2")
	var g := _guide()
	await _until(func() -> bool: return _says("代谢"))
	g._next()
	check(await _until(func() -> bool: return _says("行为规则")), "1-2: the guide asks for the rules page")
	# (The ring still sits on the metabolism row for a frame.)
	await _until(func() -> bool: return g.ring.rect.intersects(d.tab_buttons["rules"].get_global_rect()), 2.0)
	check(g.ring.rect.intersects(d.tab_buttons["rules"].get_global_rect()), "1-2: the rules tab is ringed")
	d.show_page("rules")
	check(await _until(func() -> bool: return _says("从上往下")), "1-2: the rules page is open: how a deck runs")
	check(d.deck_editor.readonly and not d.add_button.visible, "1-2: the deck is read-only (no add button)")
	check(d.piece_chips.all(func(b: Control) -> bool: return b.locked), "1-2: every library piece is locked")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO and g.ring.rect.size.y < 200.0, 3.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(0)), "1-2: a card is ringed")
	check(not Rect2(g.card.get_global_rect()).intersects(g.ring.rect), "1-2: the guide card does not cover the ringed card (%s vs %s)" % [Rect2(g.card.get_global_rect()), g.ring.rect])
	var n0: int = d.deck_editor.deck.size()
	d.deck_editor.views[1]._gui_input(_click(Vector2(d.deck_editor.views[1].size.x - 47, 25)))
	check(d.deck_editor.deck.size() == n0, "1-2: clicking where the delete button would be does not delete")
	await _shot("12_readonly")
	g._next()
	check(await _until(func() -> bool: return _says("节俭")), "1-2: on to the 节俭 personality")
	check(g.ring.rect.intersects(d.persona_picker.cards.thrifty.get_global_rect()) or await _until(func() -> bool: return g.ring.rect.intersects(d.persona_picker.cards.thrifty.get_global_rect()), 2.0), "1-2: the 节俭 card is ringed")
	g._next()
	check(await _until(func() -> bool: return _says("投放")), "1-2: then release")
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	check(await _until(func() -> bool: return _says("单击"), 15.0), "1-2: after release: pick a cell")
	await create_timer(1.0).timeout
	var at: Vector2 = scene.sim.get_positions(scene.level_runner.sp_index)[0]
	scene._select_at(at)
	await create_timer(0.5).timeout
	check(_says("单击"), "1-2: a cell picked but not close yet: the guide still waits")
	scene.toggle_track()
	check(await _until(func() -> bool: return _says("单步")), "1-2: F follows and zooms in: the life scan is up")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(scene.hud_root.scan["pause"].get_global_rect()), "1-2: the pause button is ringed")
	scene.hud_root.scan["pause"].pressed.emit()
	var t0: float = scene.sim.get_time()
	for k in 5:
		scene.hud_root.scan["step"].pressed.emit()
		await process_frame
	check(absf(scene.sim.get_time() - t0 - 5.0 / 15.0) < 0.01, "1-2: five steps move the sim five ticks (%.3f s)" % (scene.sim.get_time() - t0))
	await create_timer(0.3).timeout
	await _shot("12_step")
	scene.paused = false
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()
	# --- 1-3 --- the divide slider
	d = await _open("1-3")
	g = _guide()
	check(g != null and await _until(func() -> bool: return _says("想一想")), "1-3: the guide opens with a question")
	check(g.next.visible, "1-3: a reading step has 知道了")
	check(not d.piece_chips.any(func(b: Control) -> bool: return b.fresh), "1-3: no 新 tags where the whole library opens at once")
	g._next()
	check(await _until(func() -> bool: return _says("行为规则")), "1-3: next it asks for the rules page")
	check(not g.next.visible and g.todo_label.visible, "1-3: a doing step has no 知道了, it goes on by itself")
	d.show_page("rules")
	check(await _until(func() -> bool: return _says("往“保守”拖")), "1-3: on to the temper slider")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO and g.ring.rect.size.y < 60.0, 3.0)
	check(d.rules_mode == "simple" and g.ring.rect.intersects(d.persona_picker.slider.get_global_rect()), "1-3: the temper slider is ringed (simple mode)")
	check(g.veil.visible, "1-3: a doing step veils the rest of the screen")
	check(not g.ring.card_rect.intersects(g.ring.rect), "1-3: the docked card does not cover the slider")
	await _shot("13_divide")
	d.persona_picker.slider._set_from(30.0, true)
	check(g.todo_label.text.contains("保守"), "1-3: a direction, not the number (%s)" % g.todo_label.text)
	check(await _until(func() -> bool: return g.todo_label.text.contains("✓")), "1-3: toward 保守 is acknowledged (✓)")
	check(await _until(func() -> bool: return _says("速度")), "1-3: then on to speed")
	d.show_page("genome")
	await create_timer(0.6).timeout
	check(g.ring.rect.intersects(d.gene_rows[0].get_global_rect()), "1-3: on the genome page it rings the speed gene")
	d.gene_sliders[0].value = 1.0
	d.gene_sliders[0].changed.emit(1.0)
	check(await _until(func() -> bool: return _says("投放")), "1-3: speed Lv 1 done: on to release")
	d.release()
	check(await _until(func() -> bool: return _says("右上角"), 15.0), "1-3: after release the run line shows")
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()
	# --- 1-4 --- card order
	d = await _open("1-4")
	g = _guide()
	await _until(func() -> bool: return _says("不分裂"))
	g._next()
	check(await _until(func() -> bool: return _says("行为规则")), "1-4: open the rules")
	d.show_page("rules")
	check(await _until(func() -> bool: return _says("高级编辑")), "1-4: the card editor opens here: switch to 高级编辑")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO, 2.0)
	check(g.ring.rect.intersects(d.mode_adv.get_global_rect()), "1-4: the 高级编辑 switch is ringed")
	d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("⋮⋮")), "1-4: the order step (drag divide above rest)")
	var dk: Array = d.deck_editor.deck
	var di := dk.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_DIVIDE)
	var ri := dk.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_REST)
	check(ri >= 0 and di == ri + 1, "1-4: the level's deck starts with rest just above divide (%d, %d)" % [ri, di])
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO and g.ring.rect.size.y < 200.0, 3.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(di)) and not g.ring.rect.intersects(d.deck_editor.card_rect(ri)), "1-4: the divide card is ringed")
	await _shot("14_order")
	d.deck_editor.move_card(di, ri)
	check(await _until(func() -> bool: return _says("自然变异")), "1-4: divide above rest: then the mutation note")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(d.mutate_pill.get_global_rect()), "1-4: the mutation switch is ringed")
	g._next()
	check(await _until(func() -> bool: return _says("投放")), "1-4: then release")
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	check(await _until(func() -> bool: return _says("加速")), "1-4: after release: the cold comes at 2:00, how to wait faster")
	g._next()
	check(await _until(func() -> bool: return not g.card.visible), "1-4: the warm-spot step waits, hidden, for the cold front")
	scene.set_speed(8.0)
	var runner: Node = scene.level_runner
	check(await _until(func() -> bool: return _says("寒潮来了"), 40.0), "1-4: it shows when the cold comes (t=%.0f s)" % (scene.sim.get_time() - runner.t0))
	scene.set_speed(1.0)
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(scene.hud_root.dock_buttons["heat"].get_global_rect()), "1-4: the warm-spot button is ringed")
	check(not Rect2(g.card.get_global_rect()).intersects(g.ring.rect), "1-4: the guide card does not cover the ringed button")
	await _shot("14_heat")
	scene.set_mode("heat")
	scene.iv.place("heat", Vector2(1100, 1100))
	check(g.next.visible, "1-4: the warm spot is a suggestion (a 知道了 step)")
	g._next()
	check(await _until(func() -> bool: return not g.card.visible), "1-4: 知道了 closes it")
	runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()
	# --- 1-5 --- temperature, genes, the swarm personality, currents
	d = await _open("1-5")
	g = _guide()
	g._next()
	check(await _until(func() -> bool: return _says("外壳没用")), "1-5: on to the genes")
	for kv in [[2, 1.0], [0, 4.0], [4, 4.0]]:
		d.gene_sliders[kv[0]].value = kv[1]
		d.gene_sliders[kv[0]].changed.emit(kv[1])
	check(await _until(func() -> bool: return _says("抱团")), "1-5: genes set: the swarm personality (new here)")
	check(g.next.visible, "1-5: it is optional (a 知道了 step)")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(d.tab_buttons["rules"].get_global_rect()), "1-5: off the rules page it rings the rules tab")
	d.show_page("rules")
	d.set_rules_mode("advanced")
	await create_timer(0.6).timeout
	check(g.ring.rect.intersects(d.mode_simple.get_global_rect()), "1-5: from the card editor it rings 性格预设")
	var off_cards := func() -> bool: return range(d.deck_editor.deck.size()).all(func(k: int) -> bool: return not Rect2(g.card.get_global_rect()).intersects(d.deck_editor.card_rect(k)))
	check(off_cards.call(), "1-5: ... and the guide keeps off the cards")
	var fresh: Array = d.piece_chips.filter(func(b: Control) -> bool: return b.fresh).map(func(b: Control) -> String: return b.text)
	check(fresh.has("同伴很多") and fresh.has("跟随同伴") and not fresh.has("能量高于"), "1-5: the pieces new here say 新 (%s)" % ", ".join(fresh))
	d.set_rules_mode("simple")
	await create_timer(0.6).timeout
	check(g.ring.rect.intersects(d.persona_picker.cards.swarm.get_global_rect()), "1-5: the swarm card is ringed")
	check(off_cards.call(), "1-5: the guide keeps off the cards")
	await _shot("15_swarm")
	d._pick_persona("swarm")
	check(d.deck_editor.deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_FOLLOW), "1-5: swarm: a follow card")
	g._next()
	check(await _until(func() -> bool: return _says("投放")), "1-5: then release")
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	check(await _until(func() -> bool: return _says("洋流"), 15.0), "1-5: the current step comes first, right after release")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(scene.hud_root.dock_buttons["current"].get_global_rect()), "1-5: the current button is ringed")
	scene.set_mode("current")
	scene.iv.begin_drag(Vector2(1000, 1100))
	scene.iv.update_drag(Vector2(1200, 1100))
	scene.iv.finish_drag()
	check(await _until(func() -> bool: return _says("A、B、C")), "1-5: one current: then the score line")
	await create_timer(2.0).timeout
	await _shot("15_patches")
	# Failed: the report says how to pass; the next try brings the guide again.
	var lr: Node = scene.level_runner
	lr.eval.extinct = true
	lr.call("_finish") if lr.has_method("_finish") else lr.call("finish")
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 10.0), "1-5: the level ends with a report")
	await create_timer(3.5).timeout
	check(_find_text(lr.report, "实验失败 · 调整建议") and _find_text(lr.report, "利用洋流"), "1-5: first failure: the report gives hints (a direction)")
	await _shot("15_tips")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()
	d = await _open("1-5")
	check(_guide() != null, "1-5: not passed yet: the guide is back on the next try")
	# Passed levels: no guide, but 重看引导 brings it.
	CampaignSave.record("1-5", [true, false, false], false)
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()
	d = await _open("1-5")
	check(_guide() == null, "1-5: passed: no guide by itself")
	scene.level_runner.replay_tutorial()
	check(await _until(func() -> bool: return _says("冰晶游丝")), "1-5: 重看引导 starts it again")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
