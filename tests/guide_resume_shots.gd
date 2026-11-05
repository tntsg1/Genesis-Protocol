extends SceneTree
# The louder guide and its resume (2026-10-29): 1-3 up to the temper step,
# a settled screenshot (veil, ring, docked card, step count), then leave to
# the menu and come back: the guide carries on at that step, not from the
# start. Saves proofs/guide_resume_*.png.
# Run: tools/run_test.sh tests/guide_resume_shots.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/guide_resume_%s.png" % name))


func _guide() -> Node:
	return scene.level_runner.tutorial if scene.level_runner else null


func _says(t: String) -> bool:
	var g := _guide()
	return g != null and g.card != null and g.card.visible and g.text_label.text.contains(t)


func _open(id: String) -> Control:
	scene.start_level(Levels.by_id(id))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	return scene.designer


func _run() -> void:
	var d := await _open("1-3")
	var g := _guide()
	await _until(func() -> bool: return _says("想一想"))
	g._next()
	await _until(func() -> bool: return _says("行为规则"))
	d.show_page("rules")
	check(await _until(func() -> bool: return _says("性子")), "the temper step")
	await create_timer(3.0).timeout
	check(g.veil.visible and g.count_label.text.contains("3 / 5"), "veiled, step 3 / 5 (%s)" % g.count_label.text)
	await _shot("step")
	# Leave for the menu, then come back.
	scene.level_runner.exit_level()
	await _until(func() -> bool: return scene.level_runner == null)
	scene.campaign.close()
	await create_timer(0.5).timeout
	check(CampaignSave.guide_at("1-3").get("n", -1) == 2, "the save remembers step 3 (%s)" % CampaignSave.guide_at("1-3"))
	d = await _open("1-3")
	g = _guide()
	check(await _until(func() -> bool: return _says("行为规则") or _says("性子"), 10.0), "back in 1-3: the guide carries on")
	check(not _says("想一想"), "it did not start over")
	check(g.count_label.text.contains("继续上次引导"), "it says it is carrying on (%s)" % g.count_label.text)
	await create_timer(2.5).timeout
	await _shot("back")
	print("DONE fails=%d" % fails)
	quit()
