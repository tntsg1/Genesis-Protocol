extends SceneTree
# The HUD: mid-materialise and settled. Saves proofs/hud_<n>.png.
# Run: tools/run_test.sh tests/hud_shots.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/hud_%s.png" % name))


func _wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await process_frame


func _run() -> void:
	scene.advance(60.0)
	scene.focus(scene.DISH_CENTER + Vector2(-200, 120), 1.3)
	await _wait(1.0)
	scene.hud_root.conceal()
	await _wait(0.5)
	scene.hud_root.reveal()
	await _wait(0.3)
	await _shot("mid")
	await _wait(2.0)
	await _shot("settled")
	quit()
