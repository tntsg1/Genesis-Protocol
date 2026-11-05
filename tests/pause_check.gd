extends SceneTree
# The Esc menu over the dish (playtest 2026-10-29): 继续 / 设置 / 返回主菜单.
#   sandbox: Esc opens it and pauses; Esc again resumes as it was; 设置
#   shows the settings panel and Esc closes it; 返回主菜单 goes to the menu
#   level: Esc opens it (no more "press Esc twice"); 返回主菜单 leaves the
#   level for the main menu, not the level page
#   also: the music ducks while paused; the warm-spot preview is its own
# Run: tools/run_test.sh tests/pause_check.gd

var scene: Node2D
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
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


func _key(code: int) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = code
	Input.parse_input_event(up)
	await process_frame


func _shot(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/pause_%s.png" % name))


func _run() -> void:
	await create_timer(3.0).timeout
	# --- sandbox ---
	check(not scene.paused, "sandbox: running")
	await _key(KEY_ESCAPE)
	check(is_instance_valid(scene.pause_menu) and scene.paused, "sandbox: Esc opens the pause menu and pauses")
	check(await _until(func() -> bool: return Audio.get_instance()._ducked, 2.0), "sandbox: the music ducks while paused")
	await _shot("menu")
	await _key(KEY_ESCAPE)
	await create_timer(0.4).timeout
	check(not is_instance_valid(scene.pause_menu) and not scene.paused, "sandbox: Esc again resumes")
	check(await _until(func() -> bool: return not Audio.get_instance()._ducked, 2.0), "sandbox: the music comes back")
	scene.paused = true
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await create_timer(0.4).timeout
	check(scene.paused, "sandbox: paused before the menu stays paused after it")
	scene.paused = false
	await _key(KEY_ESCAPE)
	scene.pause_menu.buttons[1].pressed.emit()
	await create_timer(0.3).timeout
	check(scene.pause_menu.settings_open and scene.menu.settings.is_visible_in_tree(), "sandbox: 设置 shows the settings panel")
	await _shot("settings")
	await _key(KEY_ESCAPE)
	check(not scene.pause_menu.settings_open and scene.menu.settings.get_parent() != scene.pause_menu, "sandbox: Esc puts the settings back")
	scene.pause_menu.buttons[2].pressed.emit()
	check(await _until(func() -> bool: return scene.in_menu and scene.menu.shown, 5.0), "sandbox: 返回主菜单 goes to the main menu")
	await create_timer(1.0).timeout
	# --- warm-spot preview ---
	scene.menu.leave()
	await create_timer(1.0).timeout
	scene.start_experiment()
	await create_timer(2.0).timeout
	scene.set_mode("heat")
	await create_timer(0.3).timeout
	check(scene.mode == "heat", "the heat tool is picked")
	await _shot("heat_preview")
	scene.set_mode("")
	# --- level ---
	scene.start_level(Levels.by_id("1-1"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	scene.level_runner.tutorial._skip()
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	# (The camera's pull-back after release takes an Esc as "skip it".)
	await _until(func() -> bool: return not scene.cine, 6.0)
	await create_timer(0.5).timeout
	await _key(KEY_ESCAPE)
	check(is_instance_valid(scene.pause_menu) and scene.level_runner != null, "level: Esc opens the pause menu (the level stays)")
	var names: Array = scene.pause_menu.buttons.map(func(b: Control) -> String: return b.text.get_slice("    ", 0))
	check(names == ["继续", "重新开始本关", "设置", "返回关卡页", "返回主菜单"], "level: restart and level page in the menu (%s)" % ", ".join(names))
	await _shot("menu_level")
	scene.pause_menu.buttons[1].pressed.emit()
	check(await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0), "level: 重新开始本关 opens the designer again")
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	# (The camera's pull-back after release takes an Esc as "skip it".)
	await _until(func() -> bool: return not scene.cine, 6.0)
	await create_timer(0.5).timeout
	await _key(KEY_ESCAPE)
	scene.pause_menu.buttons[4].pressed.emit()
	check(await _until(func() -> bool: return scene.level_runner == null and scene.in_menu and scene.menu.shown, 8.0), "level: 返回主菜单 goes to the main menu")
	check(not scene.campaign.visible, "level: ... not to the level page")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
