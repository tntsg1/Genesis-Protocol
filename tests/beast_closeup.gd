extends SceneTree
# Close-up of a multicell giant (flagella, envelope, collisions).
# Run: tools/run_test.sh tests/beast_closeup.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _run() -> void:
	scene.advance(60.0)
	scene.hud_root.visible = false
	var beasts: PackedVector2Array = scene.sim.get_positions(3)
	for k in 2:
		scene.focus(beasts[k], 3.0)
		for i in 40:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/beast_closeup_%d.png" % k))
	quit()
