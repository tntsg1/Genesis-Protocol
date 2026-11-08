extends SceneTree
# Level 6 (2-1, 第一口): the organ bay and the guide that builds a predator.
#   organs: cnido is open (新), the rest grey; hunting pieces need it; the
#   release waits for it; installing it makes a predator (bigger, no algae)
#   guide: organ -> rules page -> 伏击 (or × the rest card in the editor) -> its rest card -> release
#   run: predators hunt (a prey is eaten), the campaign page shows level 6
# Run: tools/run_test.sh tests/ch2_check.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/ch2_%s.png" % name))


func _says(bit: String) -> bool:
	var g: Node = scene.level_runner.tutorial
	return g != null and g.card.visible and g.text_label.text.contains(bit)


# Level 7 (2-2): the prey. Armour pair, 或 on the flee card, 不 switches,
# the cnidocyst refused.
func _level7() -> void:
	scene.start_level(Levels.by_id("2-2"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "2-2: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	var bay: Control = d.organ_bay
	check(bay.chips.silica.modulate.a > 0.9 and bay.chips.spines.modulate.a > 0.9 and bay.chips.granules.modulate.a < 0.5, "2-2: the two armours are open, storage granules (later) grey")
	check(d.deck_editor.logic, "2-2: the 不 / 或 switches are on")
	bay.chips.cnido.pressed.emit()
	check(d.go.disabled and d.go_hint.text.contains("猎物"), "2-2: a cnidocyst is refused here (%s)" % d.go_hint.text)
	bay.remove(0)
	check(not d.go.disabled, "2-2: taken out: release open again")
	await _until(func() -> bool: return _says("猎物"))
	g._next()
	check(await _until(func() -> bool: return _says("防御器官")), "2-2: the armour step")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(bay.chips.silica.get_global_rect()) and g.ring.rect.intersects(bay.chips.spines.get_global_rect()), "2-2: both armours are ringed")
	bay.chips.silica.pressed.emit()
	bay.chips.spines.pressed.emit()
	check(d.organs == ["spines"], "2-2: one armour replaces the other (%s)" % str(d.organs))
	check(await _until(func() -> bool: return _says("把速度提高到 3 级以上")), "2-2: on to speed")
	d.gene_sliders[0].value = 3.0
	d.gene_sliders[0].changed.emit(3.0)
	check(await _until(func() -> bool: return _says("受到攻击")), "2-2: speed 3: the 或 step")
	d.show_page("rules")
	await create_timer(0.6).timeout
	if d.rules_mode == "simple":
		# Editing a card needs the card editor: the guide rings its switch.
		check(g.ring.rect.intersects(d.mode_adv.get_global_rect()), "2-2: in simple mode the guide points at 高级编辑")
		d.set_rules_mode("advanced")
		await create_timer(0.3).timeout
	await create_timer(0.4).timeout
	var att: Control = d.piece_chips.filter(func(b: Control) -> bool: return b.text == "受到攻击")[0]
	check(g.ring.src.intersects(att.get_global_rect()), "2-2: the piece to drag (受到攻击) is lit too")
	await _shot("drag_src")
	d.deck_editor.set_condition(0, 2, Rules.C_ATTACKED)
	await create_timer(0.3).timeout
	var v: Control = d.deck_editor.views[0]
	check(v.hits.has("join") and v.hits.has("neg1"), "2-2: the card shows its 且 and 不 switches")
	v._gui_input(_click(v.hits.join.get_center()))
	check(d.deck_editor.deck[0].get("any", false), "2-2: clicking 且 makes it 或")
	check(Rules.card_text(d.deck_editor.deck[0]).contains(" 或 "), "2-2: the card reads 或 (%s)" % Rules.card_text(d.deck_editor.deck[0]))
	v = d.deck_editor.views[1]
	await create_timer(0.2).timeout
	v._gui_input(_click(v.hits.neg1.get_center()))
	check(d.deck_editor.deck[1].get("n1", false), "2-2: clicking 不 negates a condition")
	await create_timer(0.3).timeout
	await _shot("logic")
	v._gui_input(_click(v.hits.neg1.get_center()))
	check(not d.deck_editor.deck[1].get("n1", false), "2-2: ... and again turns it back")
	check(await _until(func() -> bool: return _says("投放")), "2-2: the 或 card done: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "2-2: released, the clock runs")
	var deck: Array = scene.sim.get_species_deck(scene.level_runner.sp_index)
	check(deck.size() > 0 and bool(deck[0].get("any", false)), "2-2: the 或 card reaches the simulation")
	scene.set_speed(8.0)
	await create_timer(4.0).timeout
	scene.set_speed(1.0)
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)


# Level 8 (2-3): two species (A prey, B predator), the state map, release
# of both.
# Level 9 (2-4): on alert. The motor pair, an alert state that comes with its
# flee card and way back, the forage flee card turned to "-> alert", the
# calm-down shortened; the goal counts the eaten.
func _level9() -> void:
	scene.start_level(Levels.by_id("2-4"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "2-4: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	var bay: Control = d.organ_bay
	check(bay.chips.flagellum.modulate.a > 0.9 and bay.chips.cilia.modulate.a > 0.9 and bay.chips.granules.modulate.a < 0.5, "2-4: flagellum and cilia open, storage granules still grey")
	check(not d.deck_editor.deck.is_empty() and d.deck_editor.deck[0].act == Rules.A_FLEE, "2-4: hunters about: the deck keeps its flee card")
	await _until(func() -> bool: return _says("警戒"))
	g._next()
	check(await _until(func() -> bool: return _says("伏刺的速度有 5 级")), "2-4: first the speed step (genes %s)" % str(d.genes))
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(d.gene_rows[0].get_global_rect()) and g.ring.rect.intersects(d.gene_rows[4].get_global_rect()), "2-4: speed and fertility are ringed")
	var gg: Array = d.genes.duplicate()
	gg[0] = 4.0
	gg[4] = 2.0
	d._set_genes(gg)
	check(await _until(func() -> bool: return _says("甩开伏刺"), 6.0), "2-4: speed 4: done, with its why")
	var used := 0.0
	for v: float in d.genes:
		used += v - 1.0
	check(used <= float(Levels.by_id("2-4").star_budget), "2-4: speed 4 + fertility 2 keeps the low-budget line (%.1f)" % used)
	check(await _until(func() -> bool: return _says("鞭毛")), "2-4: the motor organs (optional)")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(bay.chips.flagellum.get_global_rect()) and g.ring.rect.intersects(bay.chips.cilia.get_global_rect()), "2-4: both motor organs are ringed")
	bay.chips.flagellum.pressed.emit()
	bay.chips.cilia.pressed.emit()
	check(d.organs == ["cilia"], "2-4: one motor organ replaces the other (%s)" % str(d.organs))
	bay.chips.flagellum.pressed.emit()
	g._next()
	check(await _until(func() -> bool: return _says("设置警戒规则")), "2-4: on to the rules page")
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("先添加「警戒」状态")), "2-4: the alert-state step")
	await create_timer(0.4).timeout
	d.deck_editor.add_state(Rules.S_ALERT)
	var al: Array = d.deck_editor.deck.filter(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_ALERT)
	check(al.size() == 2 and al[0].act == Rules.A_FLEE and al[1].act == Rules.A_TO_FORAGE, "2-4: alert comes with its flee card and way back")
	check(await _until(func() -> bool: return _says("自动设置了两条规则")), "2-4: done: it says what came with it")
	check(await _until(func() -> bool: return _says("进入警戒"), 12.0), "2-4: then the way in")
	d.deck_editor.set_state(Rules.S_FORAGE)
	await create_timer(0.4).timeout
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO and g.ring.rect.size.y < 200.0, 3.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(0)), "2-4: the forage flee card is ringed")
	d.deck_editor.set_action(0, Rules.A_TO_ALERT)
	check(await _until(func() -> bool: return _says("110 µm"), 12.0), "2-4: then how far off to notice")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO and g.ring.rect.size.y < 80.0, 3.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(0)), "2-4: the way-in card's distance slider is ringed")
	await _shot("alert_far", 3.0)
	d.deck_editor.set_threshold(0, 1, 80.0, true)
	check(await _until(func() -> bool: return _says("把时间缩短一些"), 12.0), "2-4: then the calm-down")
	d.deck_editor.set_state(Rules.S_ALERT)
	await create_timer(0.4).timeout
	var back: int = d.deck_editor.deck.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_TO_FORAGE)
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO and g.ring.rect.size.y < 80.0, 3.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(back)), "2-4: the calm-down slider is ringed")
	await _shot("alert")
	d.deck_editor.set_threshold(back, 1, 10.0, true)
	check(await _until(func() -> bool: return _says("投放"), 12.0), "2-4: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "2-4: released, the clock runs")
	var deck: Array = scene.sim.get_species_deck(scene.level_runner.sp_index)
	check(deck.any(func(c: Dictionary) -> bool: return int(c.st) == Rules.S_ALERT and c.act == Rules.A_FLEE), "2-4: the alert state reaches the simulation")
	scene.set_speed(8.0)
	await create_timer(5.0).timeout
	scene.set_speed(1.0)
	var lr: Node = scene.level_runner
	lr._update_objective(scene.sim.get_time() - lr.t0)
	check(scene.hud_root.env["objective"][1].text.contains("被捕食"), "2-4: the objective counts the eaten (%s)" % scene.hud_root.env["objective"][1].text)
	await _shot("alert_run")
	lr.eval.extinct = true
	lr.finish()
	await _until(func() -> bool: return is_instance_valid(lr.report), 10.0)
	await create_timer(1.5).timeout
	await _shot("alert_report", 6.0)
	check(_find_report_text(lr.report, "被伏刺吃掉"), "2-4: the report says how many were eaten")
	check(not _find_report_text(lr.report, "速度只有") and not _find_report_text(lr.report, "还没进入警戒") and not _find_report_text(lr.report, "超过视野"), "2-4: the guided plan failing: no hint blames it (no alert / speed / sight)")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()


func _find_report_text(n: Node, bit: String) -> bool:
	if n is Label and (n as Label).text.contains(bit):
		return true
	for c in n.get_children():
		if _find_report_text(c, bit):
			return true
	return false


# Level 10 (2-5): the devourer. Speed, flee far, the breeding state with its
# cards, the way in from foraging; the objective counts the devourers; a
# starved devourer ends the run and the report closes the chapter.
func _level10() -> void:
	scene.start_level(Levels.by_id("2-5"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "2-5: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	var bay: Control = d.organ_bay
	check(bay.chips.granules.modulate.a > 0.9, "2-5: storage granules open")
	g._next()
	check(await _until(func() -> bool: return _says("巨噬者的速度")), "2-5: the speed step")
	var gg: Array = d.genes.duplicate()
	gg[0] = 4.0
	d._set_genes(gg)
	var used := 0.0
	for v: float in d.genes:
		used += v - 1.0
	check(used <= float(Levels.by_id("2-5").star_budget), "2-5: speed 4 keeps the low-budget line (%.1f)" % used)
	check(await _until(func() -> bool: return _says("高级编辑") or _says("138 µm"), 8.0), "2-5: on to the rules page, advanced, in one step")
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("138 µm"), 8.0), "2-5: the flee-distance step")
	await _until(func() -> bool: return g.ring.rect.intersects(d.deck_editor.card_rect(0)), 4.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(0)), "2-5: the flee slider is ringed (ring %s card %s page %s state %d)" % [g.ring.rect, d.deck_editor.card_rect(0), d.page, d.deck_editor.cur_state])
	d.deck_editor.set_threshold(0, 1, 80.0, true)
	check(await _until(func() -> bool: return _says("添加「繁殖期」"), 12.0), "2-5: the breeding-state step")
	check(d.state_bar._shown(Rules.S_BREED) if d.state_bar.has_method("_shown") else true, "2-5: breeding shows in the state map")
	d.deck_editor.add_state(Rules.S_BREED)
	var br: Array = d.deck_editor.deck.filter(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_BREED)
	check(br.size() == 4 and br[0].act == Rules.A_FLEE and br[1].act == Rules.A_DIVIDE and br[3].act == Rules.A_TO_FORAGE, "2-5: breeding comes with flee, divide, graze and its way back (%d)" % br.size())
	check(await _until(func() -> bool: return _says("进入繁殖期"), 12.0), "2-5: then the way in")
	d.deck_editor.set_state(Rules.S_FORAGE)
	await create_timer(0.4).timeout
	var dv: int = d.deck_editor.deck.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_DIVIDE)
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO and g.ring.rect.size.y < 200.0, 3.0)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(dv)), "2-5: the forage divide card is ringed")
	await _shot("breed")
	d.deck_editor.set_action(dv, Rules.A_TO_BREED)
	check(await _until(func() -> bool: return _says("投放"), 12.0), "2-5: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "2-5: released, the clock runs")
	var lr: Node = scene.level_runner
	var deck: Array = scene.sim.get_species_deck(lr.sp_index)
	check(deck.any(func(c: Dictionary) -> bool: return int(c.st) == Rules.S_FORAGE and c.act == Rules.A_TO_BREED), "2-5: the way into breeding reaches the simulation")
	check(lr.boss_seen == 1, "2-5: the devourer was shown (%d)" % lr.boss_seen)
	scene.set_speed(8.0)
	await create_timer(4.0).timeout
	scene.set_speed(1.0)
	lr._update_objective(scene.sim.get_time() - lr.t0)
	check(scene.hud_root.env["objective"][1].text.contains("巨噬者"), "2-5: the objective counts the devourers (%s)" % scene.hud_root.env["objective"][1].text)
	await _shot("boss_run")
	var bp: PackedVector2Array = scene.sim.get_positions(0)
	if not bp.is_empty():
		scene.focus(bp[0], 1.4)
		await _shot("boss_close", 1.5)
	# Starve it by hand: the run ends a few seconds later, the chapter closes.
	lr.eval.boss_dead = scene.sim.get_time() - lr.t0
	lr.eval.goal_met = true
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 12.0), "2-5: a starved devourer ends the run")
	await create_timer(1.5).timeout
	await _shot("boss_report", 6.0)
	check(_find_report_text(lr.report, "饿死了"), "2-5: the report says when it starved")
	check(_find_report_text(lr.report, "第二章 · 捕食篇 完成") and _find_report_text(lr.report, "第三章"), "2-5: the report closes chapter two and points at chapter three")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()


func _level8() -> void:
	scene.start_level(Levels.by_id("2-3"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "2-3: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	check(d.slot_tabs.size() == 2 and d.cur_slot == 0, "2-3: two species tabs, A first")
	check(d.state_bar != null and d.state_bar.is_visible_in_tree() == false, "2-3: a state map on the rules page")
	await _until(func() -> bool: return _says("两个物种"))
	g._next()
	check(await _until(func() -> bool: return _says("猎物 A")), "2-3: the prey-genes step")
	for kv in [[0, 1.0]]:
		d.gene_sliders[kv[0]].value = kv[1]
		d.gene_sliders[kv[0]].changed.emit(kv[1])
	check(await _until(func() -> bool: return _says("B · 捕食者")), "2-3: on to the predator tab")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(d.slot_tabs[1].get_global_rect()), "2-3: the B tab is ringed")
	d.slot_tabs[1].pressed.emit()
	check(d.cur_slot == 1 and d.organs.has("cnido") and d.deck_editor.diet == 1, "2-3: B is a predator with a cnidocyst")
	check(d.deck_editor.deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_HUNT), "2-3: B starts with the hunt card")
	check(await _until(func() -> bool: return _says("休眠")), "2-3: the sleep-state step")
	d.show_page("rules")
	await create_timer(0.6).timeout
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(d.state_bar.get_global_rect()), "2-3: the state map is ringed")
	d.deck_editor.add_state(Rules.S_SLEEP)
	check(d.deck_editor.states_used() == [0, 3] and d.deck_editor.cur_state == Rules.S_SLEEP, "2-3: a sleep state added, its cards on show")
	var naps: Array = d.deck_editor.deck.filter(func(c: Dictionary) -> bool: return c.act == Rules.A_TO_SLEEP)
	check(naps.size() == 1 and int(naps[0].get("st", 0)) == Rules.S_FORAGE and naps[0].get("n1", false), "2-3: adding sleep also adds the way in (forage: no prey + 15 s -> sleep)")
	check(not g.next.visible and g.todo_label.text.begins_with("✓") or await _until(func() -> bool: return _says("两个物种都设置好了"), 8.0), "2-3: adding sleep meets the state step (2026-11-04: a doing step now)")
	d.deck_editor.set_state(Rules.S_FORAGE)
	await create_timer(0.6).timeout
	await _shot("states")
	d.slot_tabs[0].pressed.emit()
	check(d.cur_slot == 0 and d.organs.is_empty() and float(d.genes[0]) <= 1.0, "2-3: back to A: its own genes kept")
	check(await _until(func() -> bool: return _says("投放"), 8.0), "2-3: then release (the nap-card step is already met)")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "2-3: released, the clock runs")
	var ev: LevelEval = scene.level_runner.eval
	check(ev.sp2 >= 0 and scene.sim.get_positions(ev.sp2).size() == 8, "2-3: the predators are out too (%d)" % (scene.sim.get_positions(ev.sp2).size() if ev.sp2 >= 0 else -1))
	var deck2: Array = scene.sim.get_species_deck(ev.sp2)
	check(deck2.any(func(c: Dictionary) -> bool: return int(c.st) == Rules.S_SLEEP), "2-3: the sleep state reaches the simulation")
	check(ev.uses_state, "2-3: the challenge sees the predator using sleep")
	scene.set_speed(8.0)
	await create_timer(4.0).timeout
	scene.set_speed(1.0)
	await _shot("two")
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()


func _click(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	return e


func _chip(d: Control, text: String) -> Control:
	for b: Control in d.piece_chips:
		if b.text == text:
			return b
	return null


func _run() -> void:
	scene.start_level(Levels.by_id("2-1"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "2-1: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	var bay: Control = d.organ_bay
	check(bay != null and bay.slots == 2, "2-1: an organ bay with 2 slots")
	check(bay.chips.cnido.modulate.a > 0.9 and bay.chips.silica.modulate.a < 0.5, "2-1: cnidocyst is open, the silica shell (2-2) is grey")
	check(_chip(d, "追捕").locked and _chip(d, "看见猎物").locked, "2-1: hunting pieces are locked without a cnidocyst")
	check(_chip(d, "追捕").tooltip_text.contains("刺丝囊"), "2-1: ... and say which organ they need")
	check(d.go.disabled and d.go_hint.text.contains("刺丝囊"), "2-1: the release waits for the cnidocyst (%s)" % d.go_hint.text)
	await _until(func() -> bool: return _says("捕食者"))
	g._next()
	check(await _until(func() -> bool: return _says("器官槽")), "2-1: the guide asks for the cnidocyst")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO)
	check(g.ring.rect.intersects(bay.chips.cnido.get_global_rect()), "2-1: the cnidocyst chip is ringed")
	await _shot("organs")
	bay.chips.cnido.pressed.emit()
	check(d.organs == ["cnido"] and d.deck_editor.diet == 1, "2-1: installed: a predator")
	check(not _chip(d, "追捕").locked and not _chip(d, "猎物在").locked, "2-1: hunting pieces unlocked")
	check(_chip(d, "猎物在").fresh and _chip(d, "追捕").fresh, "2-1: the pieces new here say 新")
	bay.chips.silica.pressed.emit()
	check(d.organs == ["cnido"], "2-1: a grey organ cannot be installed")
	check(await _until(func() -> bool: return _says("行为规则")), "2-1: on to the rules page")
	d.show_page("rules")
	var dk: Array = d.deck_editor.deck
	check(not dk.any(func(c: Dictionary) -> bool: return c.act == Rules.A_SEEK_ALGAE) and dk.any(func(c: Dictionary) -> bool: return c.act == Rules.A_HUNT and Rules.C_SEE_PREY in [c.c1, c.c2]), "2-1: the untouched deck became the predator's (see prey -> hunt)")
	d.set_rules_mode("simple")
	check(await _until(func() -> bool: return _says("伏击")), "2-1: the personality step (伏击)")
	await _until(func() -> bool: return g.ring.rect.size != Vector2.ZERO, 3.0)
	check(g.ring.rect.intersects(d.persona_picker.cards.ambush.get_global_rect()), "2-1: the 伏击 card is ringed")
	# From the card editor the same step is the old one: × the rest card.
	d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("×")), "2-1: in the card editor the step says ×")
	await create_timer(0.4).timeout
	var rk: int = d.deck_editor.deck.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_REST)
	check(g.ring.rect.intersects(d.deck_editor.card_rect(rk)), "2-1: ... and rings the rest card")
	d.set_rules_mode("simple")
	check(await _until(func() -> bool: return _says("伏击")), "2-1: back to the personalities: back to 伏击")
	d._pick_persona("ambush")
	check(await _until(func() -> bool: return _says("留在原地休息") and _says("✓")), "2-1: picked: why the ambush works")
	check(await _until(func() -> bool: return _says("总是 → 休息"), 12.0), "2-1: then its rest card is explained")
	g._next()
	check(await _until(func() -> bool: return _says("投放")), "2-1: then release")
	await _shot("rules")
	check(not d.go.disabled, "2-1: the release is open now")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "2-1: released, the clock runs")
	var sp: int = scene.level_runner.sp_index
	var a: Dictionary = scene.sim.get_agent(scene.sim.find_agent(scene.sim.get_positions(sp)[0], 2.0))
	check(int(a.get("diet", -1)) == 1 or float(a.get("radius", 0.0)) >= 6.9, "2-1: the released cells are predators (radius %.1f)" % float(a.get("radius", 0.0)))
	scene.set_speed(8.0)
	var ev: LevelEval = scene.level_runner.eval
	check(await _until(func() -> bool: return ev.first_kill >= 0.0, 30.0), "2-1: a prey is eaten (%.0f s)" % ev.first_kill)
	await create_timer(1.0).timeout
	scene.set_speed(1.0)
	scene.focus(scene.sim.get_positions(sp)[0], 2.5)
	await _shot("hunt")
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()
	await _level7()
	await _level8()
	await _level9()
	await _level10()
	await create_timer(1.0).timeout
	check(Levels.ALL.size() >= 6 and Levels.ALL[5].id == "2-1", "the campaign lists level 6")
	check(not CampaignSave.unlocked(6), "level 6 is locked until level 5 is done")
	CampaignSave.record("1-5", [true, false, false], false)
	check(CampaignSave.unlocked(6), "level 6 opens after level 5")
	check(not CampaignSave.unlocked(7), "level 7 waits for level 6")
	scene.campaign._select(5)
	await create_timer(1.5).timeout
	check(scene.campaign.chapter_label.text.contains("第二章"), "the page heading follows the chapter (%s)" % scene.campaign.chapter_label.text)
	await _shot("campaign")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
