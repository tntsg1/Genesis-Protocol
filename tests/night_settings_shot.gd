extends SceneTree
# The settings panel with the night mode row: proofs/night/settings.png.
# Run: tools/run_test.sh tests/night_settings_shot.gd -- --menu

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _run() -> void:
	var end := Time.get_ticks_msec() + 20000
	while not (scene.in_menu and scene.menu.shown) and Time.get_ticks_msec() < end:
		await process_frame
	await create_timer(1.0).timeout
	scene.menu._toggle_settings()
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/night/settings.png"))
	quit()
