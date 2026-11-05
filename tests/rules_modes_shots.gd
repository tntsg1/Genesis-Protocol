extends SceneTree
# The rules page's two modes (2026-10-29): simple (personalities + 保守 <->
# 激进) in 1-3, advanced (one-row cards, a drop frame on just the slot under
# a dragged piece, the insertion bar for a dragged card) in 1-4.
# Saves proofs/rules_*.png and prints checks.
# Run: tools/run_test.sh tests/rules_modes_shots.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/rules_%s.png" % name))


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _open(id: String) -> Control:
	scene.start_level(Levels.by_id(id))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	return scene.designer


func _run() -> void:
	DevMode.active = true
	DevMode.no_tutorial = true
	var d := await _open("1-3")
	d.show_page("rules")
	await _wait(0.8)
	check(d.rules_mode == "simple", "1-3 opens in simple mode")
	check(d.deck_editor.readonly and not d.add_button.visible, "simple: the deck is a read-only preview")
	check(d.persona_picker.visible and not d.lib_box.visible, "simple: personalities shown, library hidden")
	var ids: Array = d.persona_picker.cards.keys()
	print("personas 1-3: ", ids)
	check(ids.has("standard") and ids.has("thrifty") and not ids.has("comfort"), "1-3 offers standard/breeder/thrifty, not the 1-4 ones")
	d.set_rules_mode("advanced")
	check(d.rules_mode == "simple", "advanced is locked before 1-4")
	await _shot("simple")
	# The slider toward 保守 raises the divide line.
	d.persona_picker.slider._set_from(14.0, true)
	var div := -1.0
	for c: Dictionary in d.deck_editor.deck:
		if c.act == Rules.A_DIVIDE:
			div = c.t1
	check(div >= 1.45, "保守 end: divide at %.2f" % div)
	d.persona_picker.picked.emit("thrifty")
	await _wait(0.5)
	check(d.persona == "thrifty" and d.deck_editor.deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_REST and c.c1 == Rules.C_NONE), "picking 节俭 builds its deck (no flee card: no hunters here)")
	await _shot("thrifty")
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.designer == null, 10.0)
	await _wait(0.5)
	d = await _open("1-4")
	d.show_page("rules")
	await _wait(0.5)
	d.set_rules_mode("advanced")
	await _wait(0.6)
	check(d.rules_mode == "advanced" and d.lib_box.visible and not d.deck_editor.readonly, "1-4: advanced opens")
	await _shot("advanced")
	# A dragged condition over card 2's second slot: only that slot is framed.
	var v: Control = d.deck_editor.views[1]
	var z2: Rect2 = v.hits.z_g2
	var ok: bool = v._can_drop_data(z2.get_center(), {piece = "cond", id = Rules.C_CROWD})
	v.queue_redraw()
	check(ok and v.zone == "g2", "a piece over slot 2 frames slot 2 (%s)" % v.zone)
	check(d.deck_editor.views[0].zone == "", "other cards stay quiet")
	await _shot("drop_slot")
	v._drop_data(z2.get_center(), {piece = "cond", id = Rules.C_CROWD})
	check(d.deck_editor.deck[1].c2 == Rules.C_CROWD or d.deck_editor.deck[1].c1 == Rules.C_CROWD, "dropped into the card")
	# A card picked up by its handle: it follows the pointer, the others make
	# room, letting go sets it in the gap.
	var ed: Control = d.deck_editor
	var last: int = ed.deck.size() - 1
	var moved: Dictionary = ed.deck[last]
	var vl: Control = ed.views[last]
	ed.begin_lift(last, vl.position.y + vl.size.y * 0.5)
	check(ed.lift == last, "the handle picks the card up")
	ed.lift_y = 0.0
	ed.lift_pos = ed._gap_for(ed.lift_y + ed.card_height(last) * 0.5)
	ed.set_process(true)
	await create_timer(0.35).timeout
	check(ed.lift_pos == 0 and ed.views[0].position.y > ed.lift_y + 20.0, "carried to the top, card 1 slides down to make room (pos %d)" % ed.lift_pos)
	await _shot("drop_card")
	ed.end_lift()
	await create_timer(0.3).timeout
	check(ed.lift < 0 and ed.deck[0] == moved, "let go: the card is first now")
	print("DONE fails=%d" % fails)
	quit()
