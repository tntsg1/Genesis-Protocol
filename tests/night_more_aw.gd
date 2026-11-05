extends SceneTree
# Night mode over the screens tests/night_shots.gd leaves out: the settings
# panel, the guide over 1-1, the phage and giant levels, the slug, the vent
# guardian's body page and dish, the foraminiferan's net, a level report.
# proofs/night/m_*.png (as the screen shows them: converted to sRGB).
# Run: tools/run_test.sh tests/night_more_aw.gd -- --menu

var scene: Node2D
var dir := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	for l: Dictionary in Levels.ALL:
		CampaignSave.record(l.id, [true, false, false], false)
	NightMode.set_setting("on")
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/night")
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.linear_to_srgb()
	img.save_png("%s/m_%s.png" % [dir, name])
	print("shot ", name)


func _level(id: String, guide := false, body := false, run := true) -> void:
	scene.start_level(Levels.by_id(id))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial and not guide:
		scene.level_runner.tutorial._skip()
	if body:
		scene.designer.show_page("body")
	await create_timer(1.4).timeout
	await _shot(id + "_designer")
	if not run:
		return
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	var need: Array = Levels.by_id(id).get("require_organs", [])
	if not need.is_empty():
		scene.designer._set_organs(need)
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.set_speed(8.0)
	await create_timer(3.0).timeout
	scene.set_speed(1.0)
	await create_timer(0.8).timeout
	await _shot(id + "_dish")


func _run() -> void:
	await _until(func() -> bool: return scene.in_menu and scene.menu.shown, 20.0)
	await create_timer(1.0).timeout
	scene.menu._activate(2)
	await create_timer(1.6).timeout
	await _shot("settings")
	scene.menu._activate(2)
	await create_timer(0.6).timeout
	await _level("1-1", true, false, false)
	scene.level_runner.exit_level()
	await create_timer(1.0).timeout
	for id in ["4-1", "4-5", "5-1"]:
		await _level(id)
		scene.level_runner.exit_level()
		await create_timer(1.0).timeout
	await _level("5-5", false, true)
	scene.focus(scene.sim.get_rotifers(1.0).slice(0, 2) as PackedFloat32Array if false else Vector2(1100, 1100), 0.9)
	var lr: Node = scene.level_runner
	lr.eval.goal_met = true
	lr.finish()
	await create_timer(4.5).timeout
	await _shot("5-5_report")
	lr.exit_level()
	await create_timer(1.0).timeout
	await _level("6-5")
	NightMode.set_setting("auto")
	quit()
