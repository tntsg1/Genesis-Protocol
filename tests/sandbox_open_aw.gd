extends SceneTree
# The sandbox is everything open (2026-10-30): the designer there has four
# organ slots with every organ installable; a cnidocyst makes a predator and
# it reaches the dish. Saves proofs/sandbox_*.png.
# Run: tools/run_test.sh tests/sandbox_open_aw.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/sandbox_%s.png" % name))


func _run() -> void:
	await create_timer(2.0).timeout
	check(scene.level_runner == null, "in the sandbox")
	scene.open_designer()
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "the designer opens")
	var d: Control = scene.designer
	check(d.organ_bay != null and d.organ_slots() == 4, "four organ slots")
	var closed: Array = []
	for id: String in d.organ_bay.chips:
		if d.organ_bay.chips[id].modulate.a < 0.9:
			closed.append(id)
	check(closed.is_empty(), "every organ open (closed: %s)" % str(closed))
	d.organ_bay.chips.cnido.pressed.emit()
	d.organ_bay.chips.flagellum.pressed.emit()
	check(d.organs.has("cnido") and d.deck_editor.diet == 1, "a cnidocyst makes a predator")
	# No budget in the sandbox: every gene at its top still releases.
	d._set_genes([5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0])
	await create_timer(0.3).timeout
	check(not d.go.disabled and d.budget_label.text.contains("不限"), "every gene at 5: still released, the budget says 不限 (%s)" % d.budget_label.text)
	await create_timer(1.2).timeout
	await _shot("genome")
	d.show_page("rules")
	d.set_rules_mode("advanced")
	await create_timer(1.0).timeout
	check(d.deck_editor.deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_HUNT), "its rules hunt")
	check(d.state_bar != null and d.state_bar.visible, "states can be added")
	await _shot("rules")
	var n0: int = scene.colors.size()
	d.release()
	# The sandbox then asks where: a click in the dish (here, its centre).
	await _until(func() -> bool: return scene.designer == null, 15.0)
	await create_timer(0.5).timeout
	scene._do_release(scene.DISH_CENTER)
	check(await _until(func() -> bool: return scene.colors.size() > n0, 40.0), "released into the dish")
	if scene.colors.size() > n0:
		check(scene.species_diet[n0] == 1, "as a predator (diet %d)" % scene.species_diet[n0])
	# The tools: free, no cooldown, the points say 不限.
	var iv: Node = scene.iv
	iv.points = 0.0
	var all_ready := true
	for k in 5:
		for kind: String in ["nutrient", "heat"]:
			all_ready = all_ready and iv.ready_to_use(kind)
			iv.place(kind, scene.DISH_CENTER + Vector2(40 * k, 0))
	check(all_ready and iv.ready_to_use("nutrient") and iv.ready_to_use("membrane") and iv.ready_to_use("current"), "tools used back to back with no points: always ready")
	await create_timer(0.5).timeout
	check(scene.hud_root.tools.points_label.text == "不限", "the points read 不限 (%s)" % scene.hud_root.tools.points_label.text)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/sandbox_tools.png"))
	print("DONE fails=%d" % fails)
	quit()
