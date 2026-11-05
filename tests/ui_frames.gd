extends SceneTree
# UI style frames: the ecosystem HUD at group zoom, then the micro life scan.
# Run: tools/run_test.sh tests/ui_frames.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _run() -> void:
	scene.advance(80.0)
	scene.focus(Vector2(900, 1000), 1.15)
	# Let the HUD sample a few seconds of live data and play its entrance.
	for i in 300:
		await process_frame
	await _shot("ui_frame_hud")
	var pts: PackedVector2Array = scene.sim.get_positions(0)
	var target := pts[pts.size() / 3]
	scene.focus(target, 4.2)
	scene._select_at(target)
	scene.following = true
	for i in 90:
		await process_frame
	await _shot("ui_frame_scan")
	scene._deselect()
	scene.focus(Vector2(1100, 1100), 0.9)
	scene.open_designer()
	await create_timer(3.0).timeout
	await _shot("ui_frame_designer")
	quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))
	print("saved ", name)
