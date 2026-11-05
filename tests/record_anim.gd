extends SceneTree
# Scripted animation demo for a recording (movie writer, fixed 60 fps): the
# dish at macro (outlines and colours only), a zoom through the group tier
# into the microscope, one cell dividing at 0.3x from start to finish,
# a hunter on the chase, back out, then the view filter: species, population
# heat, normal.
# Run: tools/run_test.sh tests/record_anim.gd --write-movie <out.avi> --fixed-fps 60

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _fly(pos: Vector2, zoom: float, s: float) -> void:
	await scene.fly_to(pos, zoom, s).finished


# Keep the camera gliding after one organism (no selection reticle).
func _follow(id: int, zoom: float, s: float, until := Callable()) -> bool:
	var t := 0.0
	while t < s:
		var a: Dictionary = scene.sim.get_agent(id)
		if a.is_empty():
			return false
		var ahead: Vector2 = Vector2.from_angle(a.heading) * float(a.radius) * 0.9 * clampf(float(a.dividing) * 2.0, 0.0, 1.0)
		scene.goal_pos = a.position + ahead
		scene.goal_zoom = zoom
		if until.is_valid() and until.call(a):
			return true
		await process_frame
		t += 1.0 / 60.0
	return false


# A grazer near `at` that has just begun to divide.
func _starting(at: Vector2) -> int:
	for s in [0, 1, 5, 6, 7]:
		for p: Vector2 in scene.sim.get_positions(s):
			if p.distance_to(at) > 700.0:
				continue
			var a: Dictionary = scene.sim.get_agent(scene.sim.find_agent(p, 1.0))
			if not a.is_empty() and a.dividing >= 0.0 and a.dividing < 0.05:
				return a.id
	return -1


func _hunter() -> int:
	for s in 8:
		for p: Vector2 in scene.sim.get_positions(s):
			var a: Dictionary = scene.sim.get_agent(scene.sim.find_agent(p, 1.0))
			if not a.is_empty() and a.action == 3:
				return a.id
	return -1


func _run() -> void:
	scene.advance(60.0)
	scene.focus(scene.DISH_CENTER, 0.47)
	scene.hud_root.reveal()
	await _wait(2.2)
	# Through the tiers: outlines, then organs, then the microscope.
	var spot: Vector2 = scene.DISH_CENTER + Vector2(-260, 140)
	await _fly(spot, 2.0, 2.6)
	await _wait(1.4)
	# The signature moment: a ripe cell, followed until it divides, slowed.
	var id := -1
	for k in 600:
		id = _starting(scene.cam.position)
		if id >= 0:
			break
		await process_frame
	if id < 0:
		push_warning("no division caught")
	else:
		scene.set_speed(0.3)
		var a: Dictionary = scene.sim.get_agent(id)
		await _fly(a.position, 9.0, 0.8)
		await _follow(id, 9.0, 12.0, func(b: Dictionary) -> bool: return b.dividing < 0.0)
		await _follow(id, 9.0, 1.2)
		scene.set_speed(1.0)
	await _fly(scene.cam.position, 3.0, 1.2)
	var h := _hunter()
	if h >= 0:
		await _follow(h, 5.0, 3.5)
	await _fly(scene.DISH_CENTER, 0.47, 2.6)
	await _wait(0.8)
	for m in [1, 2, 0]:
		scene.set_view_mode(m)
		await _wait(2.8 if m > 0 else 1.2)
	quit()
