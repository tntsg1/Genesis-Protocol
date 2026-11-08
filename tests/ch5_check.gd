extends SceneTree
# Chapter 5. Level 20 (5-1, 饥饿的召集): the guide through the one new card,
# the gathering, the crawl, the fruiting body and the spores; no camera taken.
# Level 21 (5-2, 分工): what a blueprint comes to, the bench's rules, the guide
# through the two swaps, the embryos, the hatch and the shell.
# Run: tools/run_test.sh tests/ch5_check.gd

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


func _stage(want: int) -> Dictionary:
	for g: Dictionary in scene.sim.get_slugs():
		if int(g.stage) == want:
			return g
	return {}


func _run() -> void:
	check(Levels.by_id("5-1").index == 20, "5-1: it is level 20")
	CampaignSave.record("4-5", [true, false, false], false)
	scene.start_level(Levels.by_id("5-1"))
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "5-1: the designer opens")
	var d: Control = scene.designer
	var g: Node = scene.level_runner.tutorial
	check(g != null, "5-1: the guide is on")
	g._next()
	g._next()
	check(await _until(func() -> bool: return _says("高级编辑") or _says("聚合"), 8.0), "5-1: on to the rules")
	d.show_page("rules")
	if d.has_method("set_rules_mode"):
		d.set_rules_mode("advanced")
	check(await _until(func() -> bool: return _says("聚合"), 8.0), "5-1: the new-action step")
	check(d.deck_editor.deck.size() == 6, "5-1: six cards to start (%d)" % d.deck_editor.deck.size())
	d.deck_editor.set_action(1, Rules.A_AGGREGATE)
	check(await _until(func() -> bool: return _says("投放到培养皿"), 12.0), "5-1: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "5-1: released")
	var lr: Node = scene.level_runner
	scene.set_speed(8.0)
	check(await _until(func() -> bool: return lr.fired.has("slug_call"), 60.0), "5-1: cells start to gather")
	check(not scene.following and lr.tagged_id >= 0, "5-1: the centre is tagged, the camera stays")
	check(await _until(func() -> bool: return lr.fired.has("slug_go"), 60.0), "5-1: a slug sets off")
	check(await _until(func() -> bool: return lr.fired.has("slug_rise"), 90.0), "5-1: one arrives and rises")
	check(await _until(func() -> bool: return lr.fired.has("slug_fruit"), 30.0), "5-1: it fruits")
	check(await _until(func() -> bool: return int(lr.eval.slug_stats.stalk) >= 1, 5.0), "5-1: stalk cells gave themselves (%s)" % str(lr.eval.slug_stats))
	check(await _until(func() -> bool: return int(lr.eval.slug_stats.spored) >= 1, 5.0), "5-1: spores flew")
	check(await _until(func() -> bool: return lr.fired.has("slug_sprout"), 30.0), "5-1: a spore germinates on the far side")
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 100.0), "5-1: the report opens")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	await _level_21()
	await _level_22()
	await _level_23()
	await _level_24()
	print("ch5: %d failed" % fails)
	quit(1 if fails > 0 else 0)


# A body of the level's kind, in the level's water, for `seconds`.
func _swim(cells: Array, grit: int, seconds: float) -> Dictionary:
	var l: Dictionary = Levels.by_id("5-2").duplicate(true)
	l.colony.grit = grit
	var d0: Dictionary = l.start_design
	var d := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), d0.color, 12.0, false, [], "5-2")
	d.params.blocks = cells
	var run := LevelEval.prepare(l, d, 41, 1)
	var x0 := 0.0
	for p: Vector2 in (run.sim as SimCore).get_positions(run.eval.sp):
		x0 += p.x
	x0 /= 6.0
	while float(run.t) < seconds:
		LevelEval.advance(run, 1.0 / 15.0)
	var x1 := 0.0
	var ps: PackedVector2Array = (run.sim as SimCore).get_positions(run.eval.sp)
	for p: Vector2 in ps:
		x1 += p.x
	return {run = run, moved = x1 / maxi(ps.size(), 1) - x0}


func _level_21() -> void:
	var l: Dictionary = Levels.by_id("5-2")
	check(l.index == 21, "5-2: it is level 21")
	var flow: float = (l.colony.stream as Vector2).length()
	var a: Dictionary = Colony.stats(l.start_design.blocks)
	check(a.n == 12 and a.germ == 3, "5-2: twelve blocks to start, three germ")
	check(a.walled == 2 and a.rim == 7, "5-2: two flagella walled in do nothing (%d, %d)" % [a.walled, a.rim])
	check(a.unsafe == 2, "5-2: two germ blocks in the open (%d)" % a.unsafe)
	check(a.speed <= flow, "5-2: the start cannot beat the stream (%.0f, %.0f)" % [a.speed, flow])
	var fixed := [[0, 0, 1], [1, 0, 1], [2, 0, 1], [3, 0, 1], [0, 1, 6], [1, 1, 6], [2, 1, 6], [3, 1, 1], [0, 2, 1], [1, 2, 1], [2, 2, 1], [3, 2, 1]]
	var b: Dictionary = Colony.stats(fixed)
	check(b.walled == 0 and b.unsafe == 0 and b.speed > flow + 6.0, "5-2: the two swaps fix both (%.0f)" % b.speed)
	var wide: Dictionary = Colony.stats([[0, 0, 1], [0, 1, 1], [0, 2, 1], [0, 3, 6]])
	var long: Dictionary = Colony.stats([[0, 0, 1], [1, 0, 1], [2, 0, 1], [3, 0, 6]])
	check(wide.speed < long.speed and wide.keep > long.keep, "5-2: wide eats more and swims less")
	check(Colony.connected(fixed) and not Colony.connected([[0, 0, 1], [2, 0, 1], [3, 0, 6]]), "5-2: blocks must touch")
	var weak := _swim(l.start_design.blocks, 0, 40.0)
	var strong := _swim(fixed, 0, 40.0)
	check(weak.moved < 30.0, "5-2: the start is held back by the stream (%.0f)" % weak.moved)
	check(strong.moved > weak.moved + 30.0, "5-2: the fixed body gets further up (%.0f, %.0f)" % [strong.moved, weak.moved])
	# The grit stops at the first block: only those in the open lose young.
	var open: Array = [[0, 0, 1], [1, 0, 1], [2, 0, 1], [3, 0, 6], [0, 1, 1], [1, 1, 1], [2, 1, 1], [3, 1, 6]]
	var safe: Array = [[0, 0, 6], [1, 0, 1], [2, 0, 1], [3, 0, 1], [0, 1, 6], [1, 1, 1], [2, 1, 1], [3, 1, 1]]
	var hit := _swim(open, 900, 120.0)
	var kept := _swim(safe, 900, 120.0)
	var lost_open := int((hit.run.sim as SimCore).get_colony_stats().lost)
	var lost_safe := int((kept.run.sim as SimCore).get_colony_stats().lost)
	check(lost_open > 3 * lost_safe and lost_open >= 4, "5-2: grit finds the germ blocks in the open (%d, %d)" % [lost_open, lost_safe])
	# The bench.
	scene.start_level(l)
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "5-2: the designer opens")
	var d: Control = scene.designer
	check(await _until(func() -> bool: return d.page == "body", 3.0), "5-2: on the body page")
	var bench: Control = d.body_bench
	check(not d.genome.visible, "5-2: no chromosomes over the bench")
	check(Colony.stats(bench.cells).n == 12, "5-2: the start is on the bench")
	var before: Array = bench.cells.duplicate(true)
	check(not bench.remove(Vector2i(5, 4)) or Colony.connected(bench.cells), "5-2: a removal never leaves two pieces")
	bench.cells = before.duplicate(true)
	bench.undo_stack.clear()
	bench._refresh()
	check(not bench.place(Vector2i(0, 0), Colony.FLAG), "5-2: a block must touch the body")
	check(bench.toggle(Vector2i(4, 3)) and bench.toggle(Vector2i(4, 3)), "5-2: a click changes a block's kind")
	bench.undo()
	bench.undo()
	var line: Array = []
	for k in 8:
		line.append([k, 0, Colony.GERM if k < 2 else Colony.FLAG])
	var at: Array = bench._shifted(line)
	check(bench.board.inside(Vector2i(at[0][0], at[0][1])) and bench.board.inside(Vector2i(at[7][0], at[7][1])), "5-2: the strip the third star asks for fits")
	var twelve: Array = []
	for k in 12:
		twelve.append([k, 0, Colony.FLAG])
	var at2: Array = bench._shifted(twelve)
	check(bench.board.inside(Vector2i(at2[0][0], at2[0][1])) and bench.board.inside(Vector2i(at2[11][0], at2[11][1])), "5-2: and the longest body too")
	var g: Node = scene.level_runner.tutorial
	check(g != null, "5-2: the guide is on")
	g._next()
	g._next()
	check(await _until(func() -> bool: return _says("被包住"), 8.0), "5-2: the first swap is asked for")
	check(bench.move(Vector2i(7, 4), Vector2i(6, 4)), "5-2: a block swaps with another")
	check(await _until(func() -> bool: return _says("再换一次"), 8.0), "5-2: then the second")
	bench.undo()
	check(int(Colony.stats(bench.cells).walled) == 2, "5-2: undo puts it back")
	check(bench.move(Vector2i(7, 4), Vector2i(6, 4)), "5-2: and again")
	check(bench.move(Vector2i(7, 5), Vector2i(5, 4)), "5-2: the second swap")
	check(await _until(func() -> bool: return _says("形状也是取舍"), 12.0), "5-2: a word on shape")
	g._next()
	check(await _until(func() -> bool: return _says("投放到培养皿"), 12.0), "5-2: then release")
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "5-2: released")
	var lr: Node = scene.level_runner
	check(lr.eval.blocks_used == 12, "5-2: twelve blocks counted")
	var who: int = scene.sim.find_agent(l.release.at, 120.0)
	check(who >= 0 and not scene.sim.get_agent(who).is_empty(), "5-2: a body can be inspected")
	scene.set_speed(8.0)
	check(await _until(func() -> bool: return lr.fired.has("col_embryo"), 60.0), "5-2: the first embryos start")
	check(not scene.following and lr.tagged_id >= 0, "5-2: tagged, the camera stays")
	check(await _until(func() -> bool: return lr.fired.has("col_hatch"), 40.0), "5-2: they hatch")
	check(int(scene.sim.get_colony_stats().born) >= 2, "5-2: more than one young")
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 100.0), "5-2: the report opens")
	check(lr.eval.stars()[0], "5-2: the guide's plan wins (%d)" % lr.eval.zone_peak)
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)


# Level 22 (5-3, 外甲内储): armour on the rim, stores, the hunters, the famine;
# the bench offers the new blocks and the guide asks for them.
func _level_22() -> void:
	var l: Dictionary = Levels.by_id("5-3")
	check(l.index == 22, "5-3: it is level 22")
	var a: Dictionary = Colony.stats(l.start_design.blocks)
	check(a.armor == 0 and a.store == 0 and a.germ == 3, "5-3: the start has no armour or stores")
	var guide := [[0, 0, 7], [1, 0, 1], [2, 0, 1], [3, 0, 1], [0, 1, 6], [1, 1, 8], [2, 1, 6], [3, 1, 1], [0, 2, 7], [1, 2, 1], [2, 2, 1], [3, 2, 1]]
	var g: Dictionary = Colony.stats(guide)
	check(g.armor == 2 and g.armor_walled == 0 and g.store == 1 and g.germ == 2, "5-3: the guide's body (%s)" % str(g))
	check(Colony.stats([[0, 0, 1], [1, 0, 1], [2, 0, 1], [0, 1, 1], [1, 1, 7], [2, 1, 1], [0, 2, 1], [1, 2, 1], [2, 2, 6]]).armor_walled == 1, "5-3: armour walled in guards nothing")
	# The kernel: a run each way, the same seed.
	var d0: Dictionary = l.start_design
	var runs := []
	for cells: Array in [l.start_design.blocks, guide]:
		var d := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), d0.color, 12.0, false, [], "5-3")
		d.params.blocks = cells
		var run := LevelEval.prepare(l.duplicate(true), d, 77, 2)
		var stored := 0.0
		var hunters := 0
		while float(run.t) < 200.0:
			LevelEval.advance(run, 1.0 / 15.0)
			stored = maxf(stored, float(run.eval.colony_stats.get("stored", 0.0)))
			hunters = maxi(hunters, (run.sim as SimCore).get_positions(0).size())
		runs.append([run.eval.colony_stats, stored, hunters])
	check(int(runs[0][0].bites) > 0 and int(runs[0][0].blocked) == 0, "5-3: the hunter bites the bare rim (%s)" % str(runs[0][0]))
	check(int(runs[1][0].blocked) > 0, "5-3: armour takes some bites (%d of %d)" % [int(runs[1][0].blocked), int(runs[1][0].bites)])
	check(float(runs[1][1]) > 0.0 and float(runs[0][1]) == 0.0, "5-3: only a body with stores banks anything (%.0f)" % runs[1][1])
	check(int(runs[0][2]) >= 1, "5-3: the hunter is there")
	# The bench and the guide.
	CampaignSave.record("5-2", [true, false, false], false)
	scene.start_level(l)
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "5-3: the designer opens")
	var bench: Control = scene.designer.body_bench
	check(bench.kinds.size() == 4 and bench.tiles.has(Colony.ARMOR) and bench.tiles.has(Colony.STORE), "5-3: the bench offers armour and stores")
	var tut: Node = scene.level_runner.tutorial
	check(tut != null, "5-3: the guide is on")
	tut._next()
	tut._next()
	check(await _until(func() -> bool: return _says("甲块"), 8.0), "5-3: the armour is asked for")
	var lo := Vector2i(100, 100)
	for c: Array in bench.cells:
		lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
	check(bench.place(lo, Colony.ARMOR) and bench.place(lo + Vector2i(0, 2), Colony.ARMOR), "5-3: armour onto the back corners")
	check(await _until(func() -> bool: return _says("储能块"), 8.0), "5-3: then a store")
	check(bench.place(lo + Vector2i(1, 1), Colony.STORE), "5-3: a store for the middle germ block")
	check(bench.toggle(lo + Vector2i(1, 0)) and int(Colony.type_at(bench.cells, lo.x + 1, lo.y)) == Colony.GERM, "5-3: a click goes on to the next kind")
	bench.undo()
	check(await _until(func() -> bool: return _says("仪表"), 12.0), "5-3: a word on the readout")
	scene.designer.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "5-3: released")
	var lr: Node = scene.level_runner
	scene.set_speed(8.0)
	check(await _until(func() -> bool: return lr.fired.has("0_start"), 60.0), "5-3: the famine comes")
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 150.0), "5-3: the report opens")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)


# Level 23 (5-4, 断肢求生): bites break blocks, they grow back (faster beside a
# regeneration block), a body bitten in two grows two; the bench and the guide.
func _level_23() -> void:
	var l: Dictionary = Levels.by_id("5-4")
	check(l.index == 23, "5-4: it is level 23")
	var a: Dictionary = Colony.stats(l.start_design.blocks)
	check(a.regen == 0 and a.armor == 2 and a.store == 1, "5-4: the start is last level's guide")
	# (The guide: the store back to a germ block, a regeneration block beside
	# the top back armour corner.)
	var guide := [[0, 0, 7], [1, 0, 9], [2, 0, 1], [3, 0, 1], [0, 1, 6], [1, 1, 6], [2, 1, 6], [3, 1, 1], [0, 2, 7], [1, 2, 1], [2, 2, 1], [3, 2, 1]]
	var gs: Dictionary = Colony.stats(guide)
	check(gs.regen == 1 and gs.germ == 3 and gs.store == 0, "5-4: the guide's body (%s)" % str(gs))
	check(bool(l.colony.get("regen_all", false)), "5-4: a regeneration block heals the whole body")
	var d0: Dictionary = l.start_design
	var line := [[0, 0, 6], [1, 0, 1], [2, 0, 6], [3, 0, 1], [4, 0, 6], [5, 0, 1], [6, 0, 9], [7, 0, 1], [8, 0, 1], [9, 0, 1], [10, 0, 1], [11, 0, 1]]
	var out := []
	for cells: Array in [guide, line]:
		var d := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), d0.color, 12.0, false, [], "5-4")
		d.params.blocks = cells
		var run := LevelEval.prepare(l.duplicate(true), d, 91, 2)
		while float(run.t) < 240.0:
			LevelEval.advance(run, 1.0 / 15.0)
		out.append(run.eval.colony_stats)
	check(int(out[0].broken) > 0, "5-4: bites break blocks (%s)" % str(out[0]))
	check(int(out[0].healed) > 0, "5-4: broken blocks grow back by the regeneration block (%d)" % int(out[0].healed))
	check(int(out[1].splits) > 0 and int(out[1].whole) > 0, "5-4: a long body is bitten in two and both halves grow whole (%d, %d)" % [int(out[1].splits), int(out[1].whole)])
	CampaignSave.record("5-3", [true, false, false], false)
	scene.start_level(l)
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "5-4: the designer opens")
	var bench: Control = scene.designer.body_bench
	check(bench.tiles.has(Colony.REGEN), "5-4: the bench offers the regeneration block")
	var tut: Node = scene.level_runner.tutorial
	tut._next()
	tut._next()
	check(await _until(func() -> bool: return _says("生殖块拖到"), 8.0), "5-4: first the store back to a germ block")
	var lo := Vector2i(100, 100)
	for c: Array in bench.cells:
		lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
	check(bench.place(lo + Vector2i(1, 1), Colony.GERM), "5-4: a germ block for the middle store")
	check(await _until(func() -> bool: return _says("干细胞"), 8.0), "5-4: then the regeneration block is shown")
	tut._next()
	check(await _until(func() -> bool: return _says("再生块拖到"), 8.0), "5-4: the regeneration block is asked for")
	check(bench.place(lo + Vector2i(1, 0), Colony.REGEN), "5-4: it goes beside the top back armour corner")
	check(await _until(func() -> bool: return _says("两半"), 12.0), "5-4: a word on splitting")
	scene.designer.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "5-4: released")
	var lr: Node = scene.level_runner
	scene.set_speed(8.0)
	check(await _until(func() -> bool: return is_instance_valid(lr.report), 150.0), "5-4: the report opens")
	lr.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)


# Level 24 (5-5, 喷口守卫): the rotifer swallows, spits out what has armour
# enough (four on the rim), starves; the guide asks for four armour; winning
# plays the end.
func _level_24() -> void:
	var l: Dictionary = Levels.by_id("5-5")
	check(l.index == 24 and l.goal.kind == "boss", "5-5: it is level 24, a boss")
	var d0: Dictionary = l.start_design
	var four := [[0, 0, 7], [1, 0, 7], [2, 0, 1], [3, 0, 1], [0, 1, 7], [1, 1, 9], [2, 1, 6], [3, 1, 1], [0, 2, 7], [1, 2, 6], [2, 2, 1], [3, 2, 1]]
	var out := []
	for cells: Array in [d0.blocks, four]:
		var d := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), d0.color, 12.0, false, [], "5-5")
		d.params.blocks = cells
		var run := LevelEval.prepare(l.duplicate(true), d, 33, 2)
		while float(run.t) < 360.0:
			LevelEval.advance(run, 1.0 / 15.0)
		out.append([run.eval.colony_stats, run.eval.boss_dead])
	check(int(out[0][0].swallowed) > 0 and int(out[0][0].spat) == 0, "5-5: two armour gets eaten (%s)" % str(out[0][0]))
	check(int(out[1][0].spat) > 0, "5-5: four armour gets spat out (%d of %d)" % [int(out[1][0].spat), int(out[1][0].swallowed)])
	check(float(out[1][1]) >= 0.0, "5-5: and the guardian starves")
	CampaignSave.record("5-4", [true, false, false], false)
	scene.start_level(l)
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "5-5: the designer opens")
	var bench: Control = scene.designer.body_bench
	var tut: Node = scene.level_runner.tutorial
	tut._next()
	tut._next()
	check(await _until(func() -> bool: return _says("刺激头冠"), 8.0), "5-5: the irritant is named")
	tut._next()
	check(await _until(func() -> bool: return _says("最后一列中间"), 8.0), "5-5: a third armour is asked for")
	var lo := Vector2i(100, 100)
	for c: Array in bench.cells:
		lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
	check(bench.place(lo + Vector2i(0, 1), Colony.ARMOR), "5-5: armour for the back germ block")
	check(await _until(func() -> bool: return _says("生殖块少了一个"), 8.0), "5-5: then a germ block back")
	check(bench.place(lo + Vector2i(1, 2), Colony.GERM), "5-5: a germ block for a flagellum")
	check(await _until(func() -> bool: return _says("还差一块甲"), 8.0), "5-5: then a fourth armour")
	check(bench.place(lo + Vector2i(1, 0), Colony.ARMOR), "5-5: armour for the top flagellum")
	check(await _until(func() -> bool: return _says("投放到培养皿"), 8.0), "5-5: and then release")
	scene.designer.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "5-5: released")
	var lr: Node = scene.level_runner
	check(await _until(func() -> bool: return scene.rotifer_layer.visible, 5.0), "5-5: the guardian is drawn")
	# Won (as if): leaving plays the end, and it can be skipped.
	lr.eval.goal_met = true
	lr.exit_level()
	var ending: Node = null
	for k in scene.get_children():
		if k.get_script() == preload("res://scripts/ui/ending.gd"):
			ending = k
	check(ending != null, "5-5: winning plays the end of Europa")
	if ending:
		ending._end()
	await _until(func() -> bool: return scene.level_runner == null)
	check(scene.level_runner == null, "5-5: and after it, back to the campaign")

