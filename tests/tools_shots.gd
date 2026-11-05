extends SceneTree
# Dock tools and the designer release flow. Drives the scene by calls (the
# mouse is never moved). Run: tools/run_test.sh tests/tools_shots.gd

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
	# Live history for the report: run at 8x for a while.
	scene.set_speed(8.0)
	await _wait(700)
	scene.set_speed(1.0)
	scene.focus(Vector2(900, 1050), 1.0)
	# Designer: an over-budget design cannot be released.
	scene.open_designer()
	var d: Control = scene.designer
	while d.busy:
		await process_frame
	await _wait(20)
	d.genes = [5.0, 4.0, 3.0, 3.0, 4.0, 3.0, 3.0, 4.0]
	d._refresh()
	await _wait(10)
	await _shot("tools_designer_over")
	d.genes = [3.0, 3.0, 2.0, 1.0, 4.0, 3.0, 3.0, 2.5]
	d._refresh()
	d.color = d.SWATCHES[2]
	d.release()
	while scene.designer != null:
		await process_frame
	await _wait(10)
	print("mode after release: ", scene.mode)
	await _shot("tools_release_mode")
	scene._do_release(Vector2(900, 1050))
	await create_timer(0.9).timeout
	await _shot("tools_release_capsule")
	await create_timer(scene.CAPSULE_OPEN - 0.9 + 0.25).timeout
	await _shot("tools_release_burst")
	await _wait(240)
	await _shot("tools_release_after")
	scene.set_observe(true)
	await _wait(40)
	await _shot("tools_observe")
	scene.set_observe(false)
	scene.toggle_track()
	await _wait(80)
	await _shot("tools_track")
	scene.toggle_track()
	scene._deselect()
	scene.focus(Vector2(1100, 1100), 0.9)
	scene.open_report()
	await _wait(90)
	await _shot("tools_report")
	print("species now ", scene.sim.get_stats().species.size(), " labels ", scene.labels)
	quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))
	print("saved ", name)
