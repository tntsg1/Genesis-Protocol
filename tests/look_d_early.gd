extends SceneTree
# Exposure check at the start of a run (few cells, open water under the
# lamp), the view a player first sees, plain and with a species picked out.
# Saves proofs/lookd_early_<n>.png.
# Run: tools/run_test.sh tests/look_d_early.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/lookd_early_%s.png" % name))


func _wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await process_frame


func _run() -> void:
	scene.advance(20.0)
	scene.focus(scene.DISH_CENTER + Vector2(120, -60), 2.1)
	await _wait(2.6)
	await _shot("plain")
	scene.focus_species = 4
	await _wait(0.8)
	await _shot("focus")
	quit()
