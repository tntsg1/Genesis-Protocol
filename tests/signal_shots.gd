extends SceneTree
# Level 11 (3-1) signal marks (scripts/dish_marks.gd): the signal A haze under
# the cells, rings off a cell calling out, the three-arc mark on a cell running
# from a smell, the engulfers' bold ring; and the guide card off "+ 添加规则".
# Saves proofs/signal_*.png.
# Run: tools/run_test.sh tests/signal_shots.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/signal_%s.png" % name))


func _says(t: String) -> bool:
	var g: Node = scene.level_runner.tutorial if scene.level_runner else null
	return g != null and g.card != null and g.card.visible and g.text_label.text.contains(t)


func _run() -> void:
	scene.start_level(Levels.by_id("3-1"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	var gg: Array = d.genes.duplicate()
	gg[0] = 4.0
	gg[4] = 2.0
	d._set_genes(gg)
	d.organ_bay.chips.gland.pressed.emit()
	d.organ_bay.chips.chemo_rec.pressed.emit()
	d.show_page("rules")
	d.set_rules_mode("advanced")
	g._next()
	await _until(func() -> bool: return _says("释放信号 A"), 10.0)
	d.deck_editor.set_action(0, Rules.A_EMIT_A)
	# The add step: the card must leave "+ 添加规则" clear.
	check(await _until(func() -> bool: return _says("添加规则"), 12.0), "the add step")
	await create_timer(1.5).timeout
	check(not Rect2(g.card.get_global_rect()).intersects(d.add_button.get_global_rect()), "the guide card leaves + 添加规则 clear")
	await _shot("add_step")
	# Added under the wrong card (the second one selected): the guide asks
	# for it to be moved up first.
	d.deck_editor.selected = 1
	d.deck_editor.add_card()
	check(await _until(func() -> bool: return _says("第 2 张") and _says("⋮⋮"), 8.0), "a new card in the wrong place: move it up first")
	await create_timer(1.2).timeout
	var bk: int = g._blank_card()
	check(bk == 2 and g.ring.rect.intersects(g._card_part(bk, "handle")), "its handle is ringed (card %d)" % bk)
	await _shot("move_step")
	var ed: Control = d.deck_editor
	ed.begin_lift(bk, ed.views[bk].position.y + 10.0)
	ed.lift_pos = 1
	ed.end_lift()
	check(await _until(func() -> bool: return _says("条件格"), 8.0), "moved: now the condition, alone")
	await create_timer(1.2).timeout
	var cond_chip: Control = d.piece_chips.filter(func(c: Control) -> bool: return c.text == "信号 A 浓")[0]
	check(g.ring.rect.intersects(g._card_part(1, "z_g1")) and g.ring.src.intersects(cond_chip.get_global_rect()), "the condition slot and the 信号 A 浓 piece are lit")
	check(not Rect2(g.card.get_global_rect()).intersects(d.add_button.get_global_rect()), "... and the card keeps off + 添加规则")
	await _shot("fill_step")
	d.deck_editor.set_condition(1, 1, Rules.C_SIGNAL_A)
	check(await _until(func() -> bool: return _says("动作格"), 8.0), "then the action, alone")
	await create_timer(1.2).timeout
	var act_chip: Control = d.piece_chips.filter(func(c: Control) -> bool: return c.text == "逃离")[0]
	check(g.ring.rect.intersects(g._card_part(1, "z_act")) and g.ring.src.intersects(act_chip.get_global_rect()), "the action slot and the 逃离 piece are lit")
	await _shot("act_step")
	d.deck_editor.set_condition(1, 1, Rules.C_SIGNAL_A)
	d.deck_editor.set_action(1, Rules.A_FLEE)
	g._skip()
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "released")
	var m: DishMarks = scene.dish_marks
	# The whole dish in view, so every caller is in the marks.
	await create_timer(4.0).timeout
	scene.fly_to(Vector2(1100, 1100), 0.55, 0.3)
	await create_timer(0.6).timeout
	scene.set_speed(2.0)
	var caller := func() -> Vector2:
		for b in range(0, m.marks.size(), 6):
			if int(m.marks[b + 4]) == 10:
				return Vector2(m.marks[b], m.marks[b + 1])
		return Vector2.INF
	var seen := await _until(func() -> bool: return caller.call() != Vector2.INF, 120.0)
	check(seen, "a cell calls out")
	var spot: Vector2 = caller.call()
	scene.set_speed(0.15)
	if seen:
		scene.fly_to(spot, 1.5, 0.25)
	await create_timer(0.5).timeout
	check(m.fog.visible, "its call puts a haze in the water")
	await _shot("haze")
	var fled := 0
	for b in range(0, m.marks.size(), 6):
		if int(m.marks[b + 4]) == 5:
			fled += 1
	print("callers / fleeing in view: %d" % fled)
	print("DONE fails=%d" % fails)
	quit()
