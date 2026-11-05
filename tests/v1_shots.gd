extends SceneTree
# V1 capture: main menu, the fly-in, the HUD, the macro view and a close
# look at life-event effects. Run: tools/run_test.sh tests/v1_shots.gd -- --menu

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _run() -> void:
	scene.advance(40.0)
	await _wait(150)
	await _shot("v1_menu")
	scene.start_experiment()
	await _wait(55)
	await _shot("v1_flyin")
	await _wait(180)
	await _shot("v1_hud")
	scene.goal_pos = scene.DISH_CENTER
	scene.goal_zoom = 0.46
	await _wait(150)
	await _shot("v1_macro")
	# Close look at a busy spot: divisions, grazing motes, predation.
	var pts: PackedVector2Array = scene.sim.get_positions(2)
	var spot: Vector2 = pts[0] if pts.size() > 0 else scene.DISH_CENTER
	scene.focus(spot, 2.4)
	scene.set_speed(3.0)
	await _wait(100)
	await _shot("v1_fx")
	scene.fx.nutrient_splash(spot + Vector2(80, 40))
	await _wait(14)
	await _shot("v1_splash")
	print("fps ", Engine.get_frames_per_second())
	quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))
	print("saved ", name)
