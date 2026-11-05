extends SceneTree
# Recording: a division watched through the loupe (lens locks on, closes in,
# quarter speed; DNA unzipped, copied and pulled into the two new nuclei).
# Frame-counted so it works under --write-movie.
# Run: tools/run_test.sh tests/record_mitosis.gd --write-movie <out.avi> --fixed-fps 60

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _move(screen: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = screen
	ev.global_position = screen
	ev.relative = Vector2(3, 1)
	Input.parse_input_event(ev)


func _fresh_division() -> int:
	var sim: SimCore = scene.sim
	var ids := []
	for sp in 3:
		for p: Vector2 in sim.get_positions(sp):
			if p.distance_to(scene.DISH_CENTER) < 600.0 and ids.size() < 160:
				var id := sim.find_agent(p, 2.0)
				if id >= 0:
					ids.append(id)
	for tries in 900:
		scene.advance(scene.TICK)
		for id in ids:
			var d: float = float(sim.get_agent(id).get("dividing", -1.0))
			if d >= 0.0 and d < 0.05:
				return id
	return -1


func _frames(n: int, id: int) -> void:
	for i in n:
		await process_frame
		var info: Dictionary = scene.sim.get_agent(id)
		if not info.is_empty():
			_move(scene.get_viewport().get_canvas_transform() * (info.position as Vector2))


func _run() -> void:
	scene.advance(40.0)
	var id := _fresh_division()
	if id < 0:
		quit(1)
		return
	scene.paused = true
	scene.focus(scene.sim.get_agent(id).position, 3.2)
	await _frames(100, id)
	scene.paused = false
	scene.magnifier.sticky = true
	await _frames(660, id)
	scene.magnifier.sticky = false
	await _frames(60, id)
	quit()
