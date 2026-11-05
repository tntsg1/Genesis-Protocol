extends SceneTree
# Interventions do what they say: a membrane is never crossed, a warm spot
# warms the water, a current carries organisms along, points are spent and
# an unaffordable one is refused. Saves proofs/iv_*.png.
# Run: tools/run_test.sh tests/interventions_check.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/iv_%s.png" % name))


func _side(p: Vector2, a: Vector2, b: Vector2) -> float:
	return signf((b - a).cross(p - a))


func _run() -> void:
	scene.advance(30.0)
	var sim: SimCore = scene.sim
	var iv: Node = scene.iv
	iv.points = 300.0
	# Membrane straight through the busiest colony.
	var crowd: Vector2 = sim.get_positions(0)[0]
	var a := crowd + Vector2(-170, -40)
	var b := crowd + Vector2(170, 40)
	scene.set_mode("membrane")
	iv.begin_drag(a)
	iv.update_drag(b)
	iv.finish_drag()
	check(iv.points < 300.0, "a membrane costs points (%d left)" % int(iv.points))
	var before := {}
	for s in sim.get_species_deck(0).size() * 0 + 2:
		pass
	var near := []
	for s in [0, 1, 4, 5, 6, 7]:
		for p: Vector2 in sim.get_positions(s):
			var t := (p - a).dot(b - a) / (b - a).length_squared()
			if t > 0.05 and t < 0.95 and absf((b - a).normalized().cross(p - a)) < 80.0:
				near.append([sim.find_agent(p, 1.0), _side(p, a, b)])
	var crossed := 0
	for k in 150: # 10 s
		sim.step(1.0 / 15.0)
	for e: Array in near:
		var ag: Dictionary = sim.get_agent(e[0])
		if ag.is_empty():
			continue
		var p: Vector2 = ag.position
		var t := (p - a).dot(b - a) / (b - a).length_squared()
		if t > 0.0 and t < 1.0 and _side(p, a, b) != e[1]:
			crossed += 1
	check(near.size() > 5 and crossed == 0, "nobody crosses the membrane (%d watched, %d crossed)" % [near.size(), crossed])
	scene.focus(crowd, 1.4)
	await create_timer(0.6).timeout
	await _shot("membrane")
	# Warm spot.
	var spot: Vector2 = scene.DISH_CENTER + Vector2(-200, 300)
	var t0: float = sim.get_env_at(spot).temp
	scene.set_mode("heat")
	iv.cold = false
	iv.place("heat", spot)
	for k in 60:
		sim.step(1.0 / 15.0)
	var t1: float = sim.get_env_at(spot).temp
	check(t1 > t0 + 8.0, "a warm spot warms the water (%.1f -> %.1f °C)" % [t0, t1])
	scene.focus(spot, 0.9)
	await create_timer(0.6).timeout
	await _shot("warm")
	# Current: organisms inside drift along it.
	var c: Vector2 = sim.get_positions(1)[0]
	scene.set_mode("current")
	iv.begin_drag(c - Vector2(130, 0))
	iv.update_drag(c + Vector2(130, 0))
	iv.finish_drag()
	var ids := []
	for p: Vector2 in sim.get_positions(1):
		if p.distance_to(c) < 90.0:
			ids.append([sim.find_agent(p, 1.0), p])
	for k in 45: # 3 s
		sim.step(1.0 / 15.0)
	var drift := 0.0
	var n := 0
	for e: Array in ids:
		var ag: Dictionary = sim.get_agent(e[0])
		if not ag.is_empty():
			drift += ag.position.x - e[1].x
			n += 1
	check(n > 0 and drift / n > 25.0, "a current carries organisms along (mean drift %.0f µm in 3 s)" % (drift / maxf(n, 1)))
	scene.focus(c, 1.2)
	await create_timer(0.6).timeout
	await _shot("current")
	# Out of points: refused.
	iv.points = 5.0
	scene.set_mode("")
	iv.select("membrane")
	check(scene.mode == "", "an unaffordable intervention is refused")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
