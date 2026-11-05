extends SceneTree
# Giant close-up as a short strip of frames (every 0.2 s) to check that the
# envelope and the modules sway together. Run: tools/run_test.sh tests/beast_wave.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _run() -> void:
	scene.advance(30.0)
	scene.hud_root.visible = false
	var beasts: PackedVector2Array = scene.sim.get_positions(3)
	var strip := Image.create(4 * 480, 480, false, Image.FORMAT_RGBA8)
	var found: int = scene.sim.find_agent(beasts[0], 30.0)
	scene._select_at(beasts[0])
	scene.following = true
	scene.focus(beasts[0], 2.6)
	for k in 4:
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8) # HDR 2D viewports read back as half floats
		var c := img.get_size() / 2
		strip.blit_rect(img, Rect2i(c - Vector2i(240, 240), Vector2i(480, 480)), Vector2i(k * 480, 0))
	strip.save_png(ProjectSettings.globalize_path("res://proofs/beast_wave_strip.png"))
	print("saved strip, agent ", found)
	quit()
