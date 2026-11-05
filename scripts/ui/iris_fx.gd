extends Control
# A frozen frame over the world (eighth round, the transitions). The level
# swaps underneath while this holds the last picture still:
#   open(at)   a lens opens at `at` and grows until it swallows the screen
#              (shaders/iris.gdshader); through it the new dish racks focus
#   veil()     no opening: the picture only fades (back from a level, under
#              the campaign page's curtain)
# Frees itself when done.

var mat: ShaderMaterial


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/iris.gdshader")
	material = mat


# Grabs what is on screen now (the last frame drawn).
func shoot(vp: Viewport) -> void:
	var img := vp.get_texture().get_image()
	img.generate_mipmaps()
	mat.set_shader_parameter("snap", ImageTexture.create_from_image(img))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


func _param(v: float, key: String) -> void:
	mat.set_shader_parameter(key, v)


func open(at: Vector2, seconds := 1.05) -> void:
	mat.set_shader_parameter("view", size)
	mat.set_shader_parameter("centre", at)
	var far := 0.0
	for c in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		far = maxf(far, at.distance_to(c))
	var t := create_tween()
	# A beat as a pinhole, then it tears open.
	t.tween_method(_param.bind("radius"), 0.0, 22.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_method(_param.bind("radius"), 22.0, far * 1.15, seconds).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.parallel().tween_method(_param.bind("push"), 0.0, 1.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


func veil(seconds := 1.0) -> void:
	mat.set_shader_parameter("view", size)
	mat.set_shader_parameter("radius", -1.0)
	var t := create_tween()
	t.tween_method(_param.bind("alpha"), 1.0, 0.0, seconds).set_trans(Tween.TRANS_SINE).set_delay(0.25)
	t.tween_callback(queue_free)
