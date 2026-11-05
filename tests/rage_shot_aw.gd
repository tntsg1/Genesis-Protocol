extends SceneTree
# Level 24's guardian in its frenzy and starving, close up: a 5-5 with its burn
# raised so it runs down fast. proofs/guardian/rage_{calm,on,dying,dead}.png.
# Run: tools/run_test.sh tests/rage_shot_aw.gd

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


func _at() -> Vector2:
	var rot: PackedFloat32Array = scene.sim.get_rotifers(1.0)
	return Vector2(rot[0], rot[1]) if rot.size() > 0 else scene.rotifer_layer.husks[0].at


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/guardian"))
	var l: Dictionary = Levels.by_id("5-5").duplicate(true)
	l.world.species[0].params.burn = float(l.world.species[0].params.burn) * 6.0
	scene.start_level(l)
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.hud_root.visible = false
	await create_timer(5.0).timeout
	scene.focus(_at(), 2.6)
	await create_timer(1.0).timeout
	await _shot("rage_calm")
	scene.set_speed(3.0)
	await _until(func() -> bool: return scene.sim.get_rot_rage() > 1.0, 6000)
	scene.set_speed(1.0)
	print("RAGE at %.1f s, rage %.1f" % [scene.sim.get_time(), scene.sim.get_rot_rage()])
	await _until(func() -> bool: return false, 90)
	scene.focus(_at(), 2.6)
	await _until(func() -> bool: return false, 20)
	await _shot("rage_on")
	scene.set_speed(3.0)
	await _until(func() -> bool: return scene.sim.get_rotifers(1.0).size() == 0, 6000)
	scene.set_speed(1.0)
	print("STARVED at %.1f s, husks %d" % [scene.sim.get_time(), scene.rotifer_layer.husks.size()])
	scene.focus(_at(), 2.6)
	await create_timer(0.9).timeout
	await _shot("rage_dying")
	await create_timer(2.2).timeout
	await _shot("rage_dead")
	quit()
