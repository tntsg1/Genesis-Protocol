extends SceneTree
# The interventions as they look in the dish: a membrane, a warm and a cold
# spot, a current, and the heat tool's reach under the cursor. Saves
# proofs/iv_*.png.
# Run: tools/run_test.sh tests/iv_visual_shots.gd

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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/iv_%s.png" % name))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _drag(kind: String, a: Vector2, b: Vector2) -> void:
	scene.set_mode(kind)
	scene.iv.drag_from = a
	scene.iv.drag_to = b
	scene.iv.finish_drag()


func _run() -> void:
	await _frames(60)
	var c: Vector2 = scene.DISH_CENTER + Vector2(-150, 60)
	scene.focus(c, 1.25)
	DevMode.active = true
	DevMode.free_iv = true
	await _frames(60)
	_drag("membrane", c + Vector2(-260, -160), c + Vector2(-40, -260))
	scene.iv.place("heat", c + Vector2(200, -60))
	scene.iv.cold = true
	scene.iv.place("heat", c + Vector2(-220, 200))
	scene.iv.cold = false
	_drag("current", c + Vector2(40, 180), c + Vector2(260, 120))
	scene.iv.place("nutrient", c)
	scene.set_mode("")
	await _frames(40)
	await _shot("placed")
	# The heat tool in hand: its reach under the pointer.
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(1100, 400)
	ev.global_position = ev.position
	ev.relative = Vector2(2, 1)
	Input.parse_input_event(ev)
	scene.set_mode("heat")
	await _frames(20)
	await _shot("heat_reach")
	quit()
