extends SceneTree
# M3 views: the whole dish with its zones, each zone close up, and the
# analysis maps (temperature, acidity). Run: tools/run_test.sh tests/m3_shots.gd

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
	scene.focus(scene.DISH_CENTER, 0.48)
	await _wait(1.5)
	await _shot("m3_dish")
	for z: Dictionary in scene.layout.zones:
		scene.focus(z.center, 1.6)
		await _wait(1.0)
		await _shot("m3_zone_%s" % z.key)
	scene.focus(scene.DISH_CENTER, 0.48)
	scene.set_env_layer(1)
	await _wait(1.2)
	await _shot("m3_map_temp")
	scene.set_env_layer(2)
	await _wait(1.0)
	await _shot("m3_map_acid")
	quit()
