extends SceneTree
# Close-up detail demo for a recording (movie writer, fixed 60 fps): a cell
# swimming (body wave, flagellum), a crowd (bodies never sink into each
# other), a hunter engulfing its prey and digesting it, and a division.
# Run: tools/run_test.sh tests/record_detail.gd --write-movie <out.avi> --fixed-fps 60

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
	# 1. A swimmer close up: the stroke runs down the body into the tail.
	# The loneliest swimmer with a tail (fast species), out in open water.
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
		scene.focus(scene.sim.get_agent(swimmer).position, 9.0)
		await _follow(swimmer, 9.0, 4.5)
	# 2. A crowd: bodies touch and slide, never sink into each other.
	var crowd: Vector2 = scene.layout.zones[0].center
	await _fly(crowd, 4.0, 1.4)
	await _wait(3.0)
	# 3. A hunter: engulf, swallow, digest (slowed to half speed). Wait
	# (on the crowd) for one that has just closed on its prey.
	var ate := false
	for attempt in 4:
		var h := -1
		for k in 1200:
			h = _hunter(4)
			if h >= 0:
				break
			await process_frame
		if h < 0:
			break
		scene.set_speed(0.5)
		await _fly(scene.sim.get_agent(h).position, 7.0, 0.6)
		ate = await _follow(h, 7.0, 10.0, func(b: Dictionary) -> bool: return b.action == 7)
		if ate:
			await _follow(h, 8.0, 8.0)
			scene.set_speed(1.0)
			break
		scene.set_speed(1.0)
		await _fly(crowd, 4.0, 0.6)
	if not ate:
		push_warning("no meal caught")
	# 4. A division, slowed.
	await _fly(scene.DISH_CENTER + Vector2(-260, 140), 2.0, 1.2)
	var id := -1
	for k in 900:
		id = _starting(scene.cam.position)
		if id >= 0:
			break
		await process_frame
	if id >= 0:
		scene.set_speed(0.3)
		await _fly(scene.sim.get_agent(id).position, 9.0, 0.8)
		await _follow(id, 9.0, 12.0, func(b: Dictionary) -> bool: return b.dividing < 0.0)
		await _follow(id, 9.0, 1.5)
		scene.set_speed(1.0)
	quit()
