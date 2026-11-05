extends SceneTree
# Which colour space a canvas item's COLOR is in (for night_remap): a grey
# 0.62 square through the remap at night = 1, read back.
# Run: tools/run_test.sh tests/night_space_aw.gd


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	var cl := CanvasLayer.new()
	cl.layer = 20
	root.add_child(cl)
	for k in 2:
		var r := ColorRect.new()
		r.color = Color(0.62, 0.62, 0.62)
		r.position = Vector2(100 + 300 * k, 100)
		r.size = Vector2(200, 200)
		if k == 1:
			var m := ShaderMaterial.new()
			m.shader = preload("res://shaders/night_remap.gdshader")
			r.material = m
		cl.add_child(r)
	RenderingServer.global_shader_parameter_set("night", 1.0)
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	print("SPACE plain %s  remapped %s" % [img.get_pixel(200, 200), img.get_pixel(500, 200)])
	quit()
