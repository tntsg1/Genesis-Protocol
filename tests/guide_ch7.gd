extends SceneTree
# Chapter 7's guides walked through by doing what each step asks (through
# the designer's own functions), checking every wait is met and the guide
# reaches the release. Prints one line per step and "PASS"/"FAIL".
# Run: tools/run_test.sh tests/guide_ch7.gd

var scene: Node2D
var fails := 0


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


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


# Does what a step waits for.
func _do(w: String) -> void:
	var d: Control = scene.designer
	match w:
		"organ:memory", "organ:spore":
			d._set_organs([w.substr(6)])
		"organs75":
			d._set_organs(["memory", "spore"])
		"home_cards", "boss_cards":
			var e: Control = d.deck_editor
			for act in [Rules.A_REMEMBER, Rules.A_RETURN]:
				var k: int = e.add_card(Rules.C_TEMP_BAD, act)
				if k < 0:
					e.deck.remove_at(e.deck.size() - 1)
					k = e.add_card(Rules.C_TEMP_BAD, act)
				if act == Rules.A_REMEMBER:
					e.deck[k].n1 = true
				print("    加卡 ", k, " / ", e.deck.size())
			if w == "boss_cards":
				e.add_state(Rules.S_SPORE)
		"spore_state":
			d.deck_editor.add_state(Rules.S_SPORE)
		"life_up":
			d.life = 1.4
		"page:rules":
			d.show_page("rules")
		"fert4":
			d._set_genes([d.genes[0], d.genes[1], d.genes[2], d.genes[3], 4.0, d.genes[5], d.genes[6], d.genes[7]])
		"slot:1":
			d._switch_slot(1)
		"mode:advanced":
			d.show_page("rules")
			await create_timer(0.4).timeout
			d.set_rules_mode("advanced")
		"avoid_o2_card":
			var k: int = d.deck_editor.add_card(Rules.C_O2_ABOVE, Rules.A_AVOID_O2)
			d.deck_editor.set_threshold(k, 0, 0.06, true)
		"avoid_first":
			var e: Control = d.deck_editor
			for k in e.deck.size():
				if e.deck[k].act == Rules.A_AVOID_O2:
					e.move_card(k, 0)
					break
		"resp_aero":
			d._set_resp(Resp.AEROBIC)


func _walk(id: String) -> void:
	print("== ", id)
	scene.start_level(Levels.by_id(id))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var tut: Node = scene.level_runner.tutorial
	_check(tut != null, "引导出现")
	if tut == null:
		return
	var seen := {}
	for n in 14:
		await create_timer(0.7).timeout
		var cur: Dictionary = tut.cur
		var text := str(cur.get("text", "")).left(24)
		if seen.has(text) and not cur.has("wait"):
			pass
		seen[text] = true
		var w := str(cur.get("wait", ""))
		print("  步骤：", text.replace("\n", " "), "　等：", w)
		if w == "release":
			_check(true, "走到投放")
			return
		if w != "":
			if not tut._met(w):
				await _do(w)
			var ok := await _until(func() -> bool: return tut._met(w), 3.0)
			_check(ok, "等待满足：" + w)
			await _until(func() -> bool: return tut.cur.get("text", "") != cur.get("text", ""), 4.0)
		else:
			tut._next() if tut.has_method("_next") else tut.next.pressed.emit()
	_check(false, "没有走到投放")


func _run() -> void:
	for id in ["7-1", "7-2", "7-3", "7-4", "7-5"]:
		await _walk(id)
		if scene.designer:
			scene.designer.close()
			await _until(func() -> bool: return scene.designer == null, 10.0)
		await create_timer(0.5).timeout
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit()
