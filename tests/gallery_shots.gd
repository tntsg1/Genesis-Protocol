extends SceneTree
# Gene gallery capture: six archetypes, one close-up each plus a group shot.
# Run: tools/run_test.sh tests/gallery_shots.gd -- --gallery

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _run() -> void:
	scene.advance(1.0)
	await _shot("gallery_all", scene.DISH_CENTER, 2.6)
	for i in scene.ARCHETYPES.size():
		var pts: PackedVector2Array = scene.sim.get_positions(i)
		if pts.size() > 0:
			await _shot("gallery_%d" % i, pts[0], 7.0)
	quit()


func _shot(name: String, pos: Vector2, zoom: float) -> void:
	scene.focus(pos, zoom)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))
