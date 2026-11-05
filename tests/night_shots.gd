extends SceneTree
# Night mode (scripts/night_mode.gd) over the game's screens:
# proofs/night/*.png (menu, levels page, designer, dish in 6-2 and in a
# chapter 2 level, the analysis view). Run: tools/run_test.sh tests/night_shots.gd -- --menu

var scene: Node2D
var dir := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	for l: Dictionary in Levels.ALL:
		CampaignSave.record(l.id, [true, false, false], false)
	NightMode.set_setting(OS.get_environment("NIGHT") if OS.get_environment("NIGHT") != "" else "on")
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
	# (The viewport holds linear colour under hdr_2d: as the screen shows it.)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.linear_to_srgb()
	img.save_png("%s/%s.png" % [dir, name])
	print("shot ", name)


func _level(id: String, tag: String) -> void:
	scene.start_level(Levels.by_id(id))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	await create_timer(0.8).timeout
	await _shot(tag + "_designer")
	var need: Array = Levels.by_id(id).get("require_organs", [])
	if not need.is_empty():
		scene.designer._set_organs(need)
		await create_timer(0.3).timeout
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.set_speed(8.0)
	await create_timer(4.0).timeout
	scene.set_speed(1.0)
	await create_timer(0.8).timeout
	await _shot(tag + "_dish")


func _run() -> void:
	await _until(func() -> bool: return scene.in_menu and scene.menu.shown, 20.0)
	await create_timer(1.5).timeout
	await _shot("a_menu" + ("_" + OS.get_environment("NIGHT") if OS.get_environment("NIGHT") != "" else ""))
	if OS.get_environment("ONLY_MENU") != "":
		NightMode.set_setting("auto")
		quit()
		return
	scene.open_campaign()
	await create_timer(2.5).timeout
	await _shot("b_levels")
	await _level("6-2", "c62")
	scene.set_env_layer(4)
	scene.focus(Vector2(1100, 1100), 0.45)
	await create_timer(2.0).timeout
	await _shot("d62_oxygen")
	scene.set_analysis(false)
	scene.level_runner.exit_level()
	await create_timer(1.0).timeout
	await _level("2-1", "e21")
	NightMode.set_setting("auto")
	quit()
