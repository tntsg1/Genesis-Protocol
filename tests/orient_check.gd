extends SceneTree
# Orientation check: one organism drawn large with a known heading (pointing
# down-right, 45°). Its front (eye, mandibles) must point down-right and its
# tail up-left. Saves proofs/orient_check.png.
# Run: tools/run_test.sh tests/orient_check.gd

func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	_run.call_deferred()


func _run() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.95, 0.97, 0.98)
	bg.size = Vector2(1920, 1080)
	root.add_child(bg)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = 1
	var inst := MultiMeshInstance2D.new()
	inst.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/organism.gdshader")
	inst.material = mat
	root.add_child(inst)
	var heading := PI * 0.25 # down-right on screen (y down)
	# genes: fast (flagellum behind), sharp vision (eye in front)
	var genes := 12 | (12 << 4)
	mm.set_instance_transform_2d(0, Transform2D(0.0, Vector2(700, 700), 0.0, Vector2(960, 540)))
	mm.set_instance_color(0, Color(0.42, 0.8, 0.88, 0.6))
	mm.set_instance_custom_data(0, Color(heading + 8.0 * 3.0, 0.8, float(genes), 0.0 + 16.0 * 8.0 + 256.0 * 15.0))
	for o in [1.0]:
		for i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.crop(1920, 1080)
		img.save_png(ProjectSettings.globalize_path("res://proofs/orient_check.png"))
	quit()
