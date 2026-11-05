extends SceneTree
# Probe: what the main menu looks like a few seconds in (tour shot 00).
var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _run() -> void:
	for t in [2, 4, 7]:
		await create_timer(2.0 if t == 2 else float(t) - (2.0 if t == 4 else 4.0)).timeout
		await RenderingServer.frame_post_draw
		print("t=%d in_menu=%s menu_shown=%s campaign_visible=%s" % [t, scene.in_menu, scene.menu.shown, scene.campaign.visible])
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/probe_menu_%d.png" % t))
	quit()
