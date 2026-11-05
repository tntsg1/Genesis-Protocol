extends SceneTree
# View filter: the whole dish and a closer region in each of the three views
# (normal, species, population heat), with the HUD and its tier gauge.
# Run: tools/run_test.sh tests/filter_shots.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	scene.advance(90.0)
	for m in 3:
		scene.set_view_mode(m)
		scene.focus(scene.DISH_CENTER, 0.48)
		await _wait(1.0)
		await _shot("filter_%d_dish" % m)
		scene.focus(scene.DISH_CENTER + Vector2(-250, 150), 1.6)
		await _wait(0.8)
		await _shot("filter_%d_group" % m)
	scene.set_view_mode(0)
	quit()
