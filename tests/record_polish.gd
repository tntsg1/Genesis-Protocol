extends SceneTree
# Polish check for a recording (movie writer, fixed 60 fps): a lone swimmer
# close up, turning (the cilia swing it round, no snapping), a busy region
# with the new restrained effects (mutation reticles), and a nutrient drop.
# Run: tools/run_test.sh tests/record_polish.gd --write-movie <out.avi> --fixed-fps 60

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


# A 猎手 doing `action` (3 hunting, 4 biting).
func _hunter(action := 3) -> int:
	for s in [2]:
		for p: Vector2 in scene.sim.get_positions(s):
			var a: Dictionary = scene.sim.get_agent(scene.sim.find_agent(p, 1.0))
			if not a.is_empty() and a.action == action:
				return a.id
	return -1


func _run() -> void:
	scene.advance(60.0)
	scene.focus(scene.DISH_CENTER, 0.47)
	scene.hud_root.reveal()
	scene.set_observe(true)
	await _wait(0.3)
	# 1. A lone swimmer close up, followed while it wanders and turns.
	var swimmer := -1
	var all_pts := PackedVector2Array()
	for s in 8:
		all_pts.append_array(scene.sim.get_positions(s))
	var best := 0.0
	for s in [0, 7, 5]:
		var ps: PackedVector2Array = scene.sim.get_positions(s)
		for k in mini(ps.size(), 60):
			var near := INF
			for q in all_pts:
				var dd := q.distance_to(ps[k])
				if dd > 0.5:
					near = minf(near, dd)
			if near > best:
				best = near
				swimmer = scene.sim.find_agent(ps[k], 20.0)
	if swimmer >= 0:
		scene.focus(scene.sim.get_agent(swimmer).position, 8.0)
		await _follow(swimmer, 8.0, 7.0)
	# 2. A busy region at group zoom: mutation reticles, nothing gaudy.
	await _fly(scene.DISH_CENTER + Vector2(-260, 140), 2.2, 1.4)
	await _wait(4.0)
	# 3. A nutrient drop in open water.
	var at: Vector2 = scene.cam.position + Vector2(120, -60)
	scene.sim.add_nutrient(at, 45.0, 150.0)
	scene.fx.nutrient_splash(at)
	await _wait(3.5)
	quit()
