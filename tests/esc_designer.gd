extends SceneTree
# A level's designer closed with Esc before the release (the player was left
# with nothing to do): can the player still get back in and release?
# Run: tools/run_test.sh tests/esc_designer.gd

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, frames := 600) -> bool:
	var n := 0
	while not cond.call() and n < frames:
		await process_frame
		n += 1
	return cond.call()


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	root.push_input(e)
	var u := e.duplicate()
	u.pressed = false
	root.push_input(u)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/esc"))
	scene.start_level(Levels.by_id("2-1"))
	print("designer opens: ", await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 1200))
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	_key(KEY_ESCAPE)
	print("closed by Esc: ", await _until(func() -> bool: return scene.designer == null, 600))
	await _until(func() -> bool: return false, 60)
	print("phase: ", scene.level_runner.phase, "  paused: ", scene.paused, "  hud shown: ", scene.hud_root.visible)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/esc/after_esc.png"))
	_key(KEY_ESCAPE)
	print("Esc opens the menu: ", await _until(func() -> bool: return is_instance_valid(scene.pause_menu), 120))
	await _until(func() -> bool: return false, 30)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/esc/menu.png"))
	scene.pause_menu._to_designer()
	print("the menu goes back in: ", await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 600))
	print("release button disabled: ", scene.designer.go.disabled, "  hint: ", scene.designer.go_hint.text)
	quit()
	quit()
