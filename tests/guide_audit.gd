extends SceneTree
# Every level's guide, design part, walked as a player following it would
# (2026-11-07, the user: "引导出问题了……要拖到哪里……你都查一下"). For each
# step: does the ring find its target on screen; doing what the step says
# (through the designer's own functions), does the step count as done; at the
# release, is any card left that can never fire (the deck editor's own
# warnings). One line per finding; the report also goes to
# proofs/guide_audit.txt. Env LEVELS="6-3,8-1" limits it.
# Run: tools/run_test.sh tests/guide_audit.gd

var scene: Node2D
var problems: Array = []
var lines: Array = []
var designs := {} # level id -> the design the guide ends on


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	Levels.force_guides = true
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


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _bad(id: String, s: String) -> void:
	_say("  !! " + s)
	problems.append("%s: %s" % [id, s])


# --- doing what a step asks --------------------------------------------------------

func _forage(n: int) -> int:
	var e: Control = scene.designer.deck_editor
	var r := 0
	for k in e.deck.size():
		if int(e.deck[k].get("st", 0)) == Rules.S_FORAGE:
			if r == n:
				return k
			r += 1
	return -1


func _card(act: int, st := -1, cond := -1) -> int:
	var e: Control = scene.designer.deck_editor
	for k in e.deck.size():
		var c: Dictionary = e.deck[k]
		if c.act == act and (st < 0 or int(c.get("st", 0)) == st) and (cond < 0 or cond in [c.c1, c.c2]):
			return k
	return -1


func _blank() -> int:
	var e: Control = scene.designer.deck_editor
	for k in e.deck.size():
		var c: Dictionary = e.deck[k]
		if c.c1 == Rules.C_NONE and c.c2 == Rules.C_NONE and c.act == Rules.A_WANDER:
			return k
	return -1


func _gene(k: int, v: float) -> void:
	var d: Control = scene.designer
	var g: Array = d.genes.duplicate()
	g[k] = v
	d._set_genes(g)


func _organ(id: String) -> void:
	var d: Control = scene.designer
	var o: Array = d.organs.duplicate()
	if not o.has(id):
		o.append(id)
	d._set_organs(o.slice(maxi(0, o.size() - maxi(1, d.organ_slots())), o.size()))


# A state added the way a player does: a click on its circle in the map.
func _click_state(st: int) -> void:
	var d: Control = scene.designer
	if d.page != "rules":
		d.show_page("rules")
		await create_timer(0.4).timeout
	if d.rules_mode != "advanced":
		d.set_rules_mode("advanced")
		await create_timer(0.3).timeout
	var bar: Control = d.state_bar
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = bar._center(st)
	bar._gui_input(e)


func _press_add() -> void:
	scene.designer.add_button.pressed.emit()


func _do(w: String) -> bool:
	var d: Control = scene.designer
	var e: Control = d.deck_editor
	var bench: Control = d.body_bench
	match w:
		"page:rules":
			d.show_page("rules")
		"mode:advanced":
			d.show_page("rules")
			await create_timer(0.3).timeout
			d.set_rules_mode("advanced")
		"speed":
			_gene(0, 1.0)
		"speed3":
			_gene(0, 3.0)
		"speed4":
			_gene(0, 4.0)
		"fert4":
			_gene(4, 4.0)
		"metab4":
			_gene(5, 4.0)
		"speed3fert4":
			_gene(0, 3.0)
			_gene(4, 4.0)
		"prey_genes":
			_gene(0, 2.0)
		"race_genes":
			_gene(2, 1.0)
			_gene(0, 4.0)
			_gene(4, 4.0)
		"temp":
			d._set_temp_opt(0.0)
		"armour":
			_organ("silica")
		"signal_organs":
			_organ("gland")
			_organ("chemo_rec")
		"organs75":
			d._set_organs(["memory", "spore"])
		"sleep_state":
			await _click_state(Rules.S_SLEEP)
		"alert_state":
			await _click_state(Rules.S_ALERT)
		"breed_state":
			await _click_state(Rules.S_BREED)
		"spore_state":
			await _click_state(Rules.S_SPORE)
		"divide":
			var k := _card(Rules.A_DIVIDE)
			if d.rules_mode == "simple":
				d._set_bold(0.0, true)
			if k >= 0 and float(e.deck[k].t1) < 1.25:
				e.set_threshold(k, 1, 1.3, true)
		"divide_first":
			var dv := _card(Rules.A_DIVIDE)
			var rs := _card(Rules.A_REST)
			if dv >= 0 and rs >= 0 and dv > rs:
				e.move_card(dv, rs)
		"ambush":
			d._pick_persona("ambush")
		"flee_attacked":
			var k := _card(Rules.A_FLEE)
			e.set_condition(k, 2, Rules.C_ATTACKED)
		"flee_or":
			e.toggle_any(_card(Rules.A_FLEE))
		"flee_far", "alert_far":
			var k := _card(Rules.A_TO_ALERT if w == "alert_far" else Rules.A_FLEE, Rules.S_FORAGE)
			e.set_threshold(k, 1, 80.0, true)
		"to_alert":
			e.set_action(_card(Rules.A_FLEE, Rules.S_FORAGE, Rules.C_PREDATOR_NEAR), Rules.A_TO_ALERT)
		"calm":
			var k := _card(Rules.A_TO_FORAGE, Rules.S_ALERT, Rules.C_STATE_TIME)
			e.set_threshold(k, 1, 12.0, true)
		"to_breed":
			e.set_state(Rules.S_FORAGE)
			e.set_action(_card(Rules.A_DIVIDE, Rules.S_FORAGE, Rules.C_ENERGY_ABOVE), Rules.A_TO_BREED)
		"no_rest":
			e.remove_card(_card(Rules.A_REST, Rules.S_FORAGE))
		"newcard", "newcard_forage":
			e.set_state(Rules.S_FORAGE)
			_press_add()
		"blank_2nd":
			var bk := _blank()
			var target := _forage(1)
			if bk >= 0 and target >= 0 and bk != target:
				e.move_card(bk, target if target < bk else target)
		"c2_signal", "c2_peer", "c2_crowd", "c2_crowd_any", "c2_age", "c2_immune":
			var cond: int = {c2_signal = Rules.C_SIGNAL_A, c2_peer = Rules.C_PEER_STATE, c2_crowd = Rules.C_CROWD, c2_crowd_any = Rules.C_CROWD, c2_age = Rules.C_AGE_ABOVE, c2_immune = Rules.C_IMMUNE}[w]
			var k := _forage(1)
			e.set_condition(k, 2 if w == "c2_immune" else 1, cond)
			if w == "c2_crowd":
				e.set_threshold(k, 1, 4.0, true)
		"smell_flee", "sync", "quorum", "disperse", "wake_card", "aggregate_card":
			var act: int = {smell_flee = Rules.A_FLEE, sync = Rules.A_TO_BREED, quorum = Rules.A_SECRETE, disperse = Rules.A_DISPERSE, wake_card = Rules.A_INDUCE, aggregate_card = Rules.A_AGGREGATE}[w]
			e.set_action(_forage(1), act)
		"memory_card":
			e.toggle_neg(_forage(1), 2)
		"shout":
			e.set_action(_card(Rules.A_FLEE, Rules.S_FORAGE, Rules.C_PREDATOR_NEAR), Rules.A_EMIT_A)
		"shout_b":
			e.set_action(_card(Rules.A_EMIT_A, Rules.S_FORAGE), Rules.A_EMIT_B)
		"smell_b":
			var k := _card(Rules.A_FLEE, Rules.S_FORAGE, Rules.C_SIGNAL_A)
			e.set_condition(k, 1 if e.deck[k].c1 == Rules.C_SIGNAL_A else 2, Rules.C_SIGNAL_B)
		"avoid_o2_card":
			e.set_state(Rules.S_FORAGE)
			_press_add()
			var k := _blank()
			e.set_condition(k, 1, Rules.C_O2_ABOVE)
			e.set_action(k, Rules.A_AVOID_O2)
		"avoid_first":
			e.move_card(_card(Rules.A_AVOID_O2), _forage(0))
		"up_card":
			_press_add()
			var k := _blank()
			e.set_condition(k, 1, Rules.C_O2_ABOVE)
			e.set_threshold(k, 1, 0.3, true)
			e.toggle_neg(k, 1)
			e.set_action(k, Rules.A_SEEK_O2)
			e.move_card(k, _forage(0))
		"swallow_card":
			_press_add()
			var k := _blank()
			e.set_condition(k, 1, Rules.C_SYMB)
			e.toggle_neg(k, 1)
			e.set_action(k, Rules.A_SWALLOW)
			e.move_card(k, _forage(0))
		"toxin_cards", "toxin_card", "boss_cards", "home_cards":
			if w in ["home_cards", "boss_cards"]:
				_press_add()
				var k1 := _blank()
				e.set_condition(k1, 1, Rules.C_TEMP_BAD)
				e.toggle_neg(k1, 1)
				e.set_action(k1, Rules.A_REMEMBER)
				e.move_card(k1, _forage(0))
				_press_add()
				var k2 := _blank()
				e.set_condition(k2, 1, Rules.C_ENERGY_ABOVE)
				e.set_condition(k2, 2, Rules.C_TEMP_BAD)
				e.set_action(k2, Rules.A_RETURN)
				e.move_card(k2, _forage(1))
				if w == "boss_cards":
					await _click_state(Rules.S_SPORE)
			else:
				for act in ([Rules.A_TOXIN_B, Rules.A_TOXIN_A] if w == "toxin_cards" else [Rules.A_TOXIN_A]):
					_press_add()
					var k := _blank()
					e.set_condition(k, 1, Rules.C_RIVAL_NEAR)
					if act == Rules.A_TOXIN_B:
						e.set_condition(k, 2, Rules.C_AGE_ABOVE)
						e.set_threshold(k, 2, 0.5, true)
					e.set_action(k, act)
					e.move_card(k, _forage(0))
		"life_up":
			d.life = 1.4
		"acid_up":
			d.acid_tol = 0.5
		"resp_aero":
			d._set_resp(Resp.AEROBIC)
		"body_walled_1":
			bench.move(Vector2i(7, 4), Vector2i(6, 4))
		"body_ok":
			bench.move(Vector2i(7, 5), Vector2i(5, 4))
		"body_armor", "body_store", "body_germ3", "body_regen", "body_armor3", "body_germ2", "body_armor4":
			var lo := Vector2i(100, 100)
			for c: Array in bench.cells:
				lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
			match w:
				"body_armor":
					bench.place(lo, Colony.ARMOR)
					bench.place(lo + Vector2i(0, 2), Colony.ARMOR)
				"body_store":
					bench.place(lo + Vector2i(1, 1), Colony.STORE)
				"body_germ3":
					bench.place(lo + Vector2i(1, 1), Colony.GERM)
				"body_regen":
					bench.place(lo + Vector2i(1, 0), Colony.REGEN)
				"body_armor3":
					bench.place(lo + Vector2i(0, 1), Colony.ARMOR)
				"body_germ2":
					bench.place(lo + Vector2i(1, 2), Colony.GERM)
				"body_armor4":
					bench.place(lo + Vector2i(1, 0), Colony.ARMOR)
		_:
			if w.begins_with("card:"):
				var spec: Array = {remember = [Rules.C_TEMP_BAD, true, Rules.A_REMEMBER, -1], ret = [Rules.C_ENERGY_ABOVE, false, Rules.A_RETURN, Rules.C_TEMP_BAD],
					up = [Rules.C_O2_ABOVE, true, Rules.A_SEEK_O2, -1], swallow = [Rules.C_SYMB, true, Rules.A_SWALLOW, -1],
					toxA = [Rules.C_RIVAL_NEAR, false, Rules.A_TOXIN_A, -1], toxB = [Rules.C_RIVAL_NEAR, false, Rules.A_TOXIN_B, Rules.C_AGE_ABOVE]}[w.substr(5)]
				e.set_state(Rules.S_FORAGE)
				_press_add()
				var k := _blank()
				e.set_condition(k, 1, int(spec[0]))
				if spec[1]:
					e.toggle_neg(k, 1)
				if int(spec[3]) >= 0:
					e.set_condition(k, 2, int(spec[3]))
				e.set_action(k, int(spec[2]))
				return true
			if w.begins_with("before_eat:"):
				var names := w.substr(11).split(",")
				names.reverse()
				for n: String in names:
					var k := _card(int(scene.level_runner.tutorial.ACT_NAMES[n]), Rules.S_FORAGE)
					e.move_card(k, _forage(0))
				return true
			if w.begins_with("slot:"):
				d._switch_slot(int(w.substr(5)))
			elif w.begins_with("organ:"):
				_organ(w.substr(6))
			else:
				return false
	return true


# --- the walk --------------------------------------------------------------------

func _walk(l: Dictionary) -> void:
	var id: String = l.id
	_say("== %s %s" % [id, l.name])
	scene.start_level(l)
	if not await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0):
		_bad(id, "设计器没打开")
		return
	var tut: Node = scene.level_runner.tutorial
	if tut == null:
		_bad(id, "引导没出现")
		return
	var last := ""
	var same := 0
	for n in 40:
		await create_timer(0.35).timeout
		if not is_instance_valid(tut) or tut.cur.is_empty():
			_bad(id, "引导在投放前就结束了")
			return
		var cur: Dictionary = tut.cur
		var text := str(cur.get("text", "")).replace("\n", " ")
		if text == last:
			same += 1
			if same > 6:
				var dk: Array = scene.designer.deck_editor.deck.map(func(c: Dictionary) -> String: return Rules.card_text(c))
				_bad(id, "卡在这一步（done_t=%.1f 可见=%s 剩%d 跳过=%s 等「%s」，满足=%s，页=%s，卡=%s）：%s" % [tut.done_t, str(tut.card.visible), tut.lines.size(), str(tut.skipped), str(cur.get("wait", "")), str(tut._met(str(cur.get("wait", "")))) if cur.has("wait") else "-", scene.designer.page, str(dk), text.left(40)])
				return
		else:
			same = 0
		last = text
		var w := str(cur.get("wait", ""))
		if cur.has("ring") and str(cur.ring) != "go":
			var ring: String = cur.ring
			var ok := await _until(func() -> bool: return tut._ring_rect(ring).size != Vector2.ZERO, 2.0)
			if not ok:
				_bad(id, "圈不到「%s」：%s" % [ring, text.left(40)])
		if w == "release":
			_lint(id)
			_say("  走到投放")
			return
		if w == "":
			tut._next()
			continue
		if tut._met(w):
			await _advance(tut, text)
			continue
		var did: bool = await _do(w)
		if not did:
			_bad(id, "测试不会做「%s」，跳过：%s" % [w, text.left(40)])
			tut._next()
			continue
		if not await _until(func() -> bool: return tut._met(w), 3.0):
			_bad(id, "照做了也不算完成「%s」：%s" % [w, text.left(40)])
			tut._next()
		else:
			_say("  ok %s" % w)
			await _advance(tut, text)
	_bad(id, "走了 40 步还没到投放")


# A done step: the guide shows why for a few seconds, then moves on; read
# it at once (as a player clicking on would).
func _advance(tut: Node, text: String) -> void:
	await _until(func() -> bool: return tut.done_t >= 0.0 or str(tut.cur.get("text", "")).replace("
", " ") != text, 2.0)
	if tut.done_t > 0.05:
		tut.done_t = 0.05
	if not await _until(func() -> bool: return str(tut.cur.get("text", "")).replace("
", " ") != text, 2.0):
		tut._next()


# At the release: every card can fire (the deck editor's own warnings), in
# every species slot.
func _lint(id: String) -> void:
	var d: Control = scene.designer
	var e: Control = d.deck_editor
	# The guided design, for tests/recommend_bot.gd to start from.
	var g: Dictionary = d._design()
	designs[id] = {genes = g.genes, deck = g.deck, organs = g.organs, resp = g.resp, life = g.life, euk = g.get("euk", false), acid_tol = g.get("acid_tol", 0.0), temp_opt = g.temp_opt, slots = d.sp_slots.size(),
		blocks = g.get("blocks", [])}
	# Several species: every slot's design (the one on the bench as it is now).
	if d.sp_slots.size() > 1:
		var all: Array = d.sp_slots.duplicate(true)
		all[d.cur_slot] = g
		designs[id].slot_designs = all.map(func(s: Dictionary) -> Dictionary: return {genes = s.genes, deck = s.deck, organs = s.get("organs", []), resp = s.get("resp", 0),
			life = s.get("life", 1.0), euk = s.get("euk", false), acid_tol = s.get("acid_tol", 0.0), temp_opt = s.get("temp_opt", 12.0)})
	if d.get("virus_bench") and d.virus_bench:
		designs[id].virus = d.virus_bench.virus.duplicate()
	if d.go.disabled:
		_bad(id, "投放按钮点不了：%s" % d.go_hint.text)
	for k in e.deck.size():
		var wn: String = e.warning(k)
		if wn != "":
			_bad(id, "投放时第 %d 张卡有警告：%s（%s）" % [k + 1, wn, Rules.card_text(e.deck[k])])


func _run() -> void:
	var only := OS.get_environment("LEVELS").split(",", false)
	for l: Dictionary in Levels.ALL:
		if not l.get("tutorial", false) or (not only.is_empty() and not only.has(l.id)):
			continue
		await _walk(l)
		if scene.designer:
			scene.designer.close()
			await _until(func() -> bool: return scene.designer == null, 10.0)
		if scene.level_runner:
			scene.level_runner.exit_level()
			await _until(func() -> bool: return scene.level_runner == null, 10.0)
		await create_timer(0.3).timeout
	_say("\n%d 个问题" % problems.size())
	for p in problems:
		_say("- " + p)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://proofs/guide_audit.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines))
	# (Merged with what is there: a run over a few levels keeps the others.)
	var path := ProjectSettings.globalize_path("res://proofs/guide_designs.txt")
	var all := {}
	if FileAccess.file_exists(path):
		var old: Variant = str_to_var(FileAccess.get_file_as_string(path))
		if old is Dictionary:
			all = old
	all.merge(designs, true)
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	f2.store_string(var_to_str(all))
	quit()
