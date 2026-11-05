extends SceneTree
# Sixth round (精修 E): the lab (the microscope stage outside the dish, the
# projected instrument grid inside) and the livelier pointer (the scan
# field with coordinates and data tags, the wake stirring water and cells,
# motes). Synthetic mouse events only. Saves proofs/looke_<n>.png.
# Run: tools/run_test.sh tests/look_e_shots.gd

var scene: Node2D
var cur := Vector2(960, 540)


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/looke_%s.png" % name))
	print("shot ", name)


func _wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await process_frame


func _put(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.relative = p - cur
	cur = p
	Input.parse_input_event(ev)


func _sweep(to: Vector2, s: float) -> void:
	var from := cur
	var t0 := Time.get_ticks_msec()
	while true:
		var k := clampf((Time.get_ticks_msec() - t0) / (s * 1000.0), 0.0, 1.0)
		_put(from.lerp(to, k * k * (3.0 - 2.0 * k)))
		await process_frame
		if k >= 1.0:
			break


func _run() -> void:
	scene.advance(60.0)
	# The whole dish on its stage.
	scene.focus(scene.DISH_CENTER, 0.42)
	_put(Vector2(1700, 980))
	await _wait(2.4)
	await _shot("stage")
	# Close on a clip and the label.
	scene.focus(scene.DISH_CENTER + Vector2(-1000, 1150), 1.0)
	await _wait(1.6)
	await _shot("label")
	# Group view: the grid, the scan field and its tags.
	scene.focus(scene.DISH_CENTER + Vector2(-200, 120), 1.3)
	await _wait(1.6)
	_put(Vector2(900, 520))
	await _wait(0.6)
	await _shot("field")
	# Stir: a quick sweep, shot mid-wake.
	await _sweep(Vector2(1300, 640), 0.35)
	await _sweep(Vector2(800, 700), 0.3)
	await _shot("wake")
	await _wait(0.5)
	await _shot("wake_after")
	quit()
