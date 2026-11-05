extends SceneTree
# Look comparison: the same views with look 2 off and on (F9 in game).
# Saves proofs/look_<view>_<0|1>.png. Run: tools/run_test.sh tests/look_shots.gd

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


func _run() -> void:
	scene.advance(60.0)
	var views := [["dish", scene.DISH_CENTER, 0.48], ["group", scene.DISH_CENTER + Vector2(-260, 140), 1.6], ["micro", scene.sim.get_positions(0)[3], 6.0]]
	for v: Array in views:
		for on in [false, true]:
			scene.set_look2(on)
			scene.focus(v[1], v[2])
			await create_timer(0.8).timeout
			await _shot("look_%s_%d" % [v[0], 1 if on else 0])
	quit()
