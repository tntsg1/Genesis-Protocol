extends SceneTree
# Level 24's guardian close up: corona open, drawn in after the irritant, and
# open again once it runs out. proofs/guardian/corona_{open,in,again}.png.
# Run: tools/run_test.sh tests/corona_shot_aw.gd

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, frames := 3600) -> void:
	var n := 0
	while not cond.call() and n < frames:
		await process_frame
		n += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/guardian/%s.png" % name))


func _head() -> Vector2:
	var rot: PackedFloat32Array = scene.sim.get_rotifers(1.0)
	return Vector2(rot[0], rot[1]) + Vector2.from_angle(rot[2]) * 88.0


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/guardian"))
	scene.start_level(Levels.by_id("5-5"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.hud_root.visible = false
	await _until(func() -> bool: return false, 60)
	scene.focus(_head(), 4.5)
	await _until(func() -> bool: return false, 40)
	await _shot("corona_open")
	scene.iv.points = 120.0
	scene.iv.select("current")
	scene.iv.place("irritant", _head())
	print("CORONA retract %s" % scene.sim.get_rotifer_retract())
	await _until(func() -> bool: return false, 50)
	scene.focus(_head(), 4.5)
	await _until(func() -> bool: return false, 10)
	await _shot("corona_in")
	await _until(func() -> bool: return scene.sim.get_rotifer_retract()[0] <= 0.0, 900)
	await _until(func() -> bool: return false, 25)
	scene.focus(_head(), 4.5)
	await _until(func() -> bool: return false, 5)
	await _shot("corona_again")
	quit()
