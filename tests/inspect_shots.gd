extends SceneTree
# Inspection capture: select a grazer, follow it, drop nutrient nearby, and
# shoot the card, the selection ring, algae and shells.
# Run: tools/run_test.sh tests/inspect_shots.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _run() -> void:
	scene.advance(90.0)
	var pts: PackedVector2Array = scene.sim.get_positions(0)
	var target := pts[pts.size() / 2]
	scene.focus(target, 3.2)
	scene._select_at(target)
	scene.following = true
	scene.sim.add_nutrient(target + Vector2(60, 30), 45.0, 150.0)
	scene.fx.nutrient_splash(target + Vector2(60, 30))
	for i in 45:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/m1_inspect.png"))
	print("selected ", scene.selected, " card ", scene.card.visible, " algae ", scene.sim.get_algae_count(), " shells ", scene.sim.get_shell_count())
	quit()
