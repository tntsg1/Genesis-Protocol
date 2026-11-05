extends SceneTree
# A short film of 5-3 for --write-movie: the guide's body released, a hunter
# closing on a colony and biting its rim (armour throws it off), then the
# famine close up, the store cells drawn on. Prints the frames to cut at.
# Run: tools/run_test.sh tests/clip_53.gd --write-movie <file.avi> --fixed-fps 30

var scene: Node2D
var follow := -1
var zoom := 6.0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, frames := 3600) -> void:
	var n := 0
	while not cond.call() and n < frames:
		await process_frame
		n += 1


# The colony a hunter is nearest, and how near.
func _prey() -> Array:
	var hs: PackedVector2Array = scene.sim.get_positions(0)
	var cs: PackedFloat32Array = scene.sim.get_colonies()
	var best := -1
	var bd := 1e12
	for h: Vector2 in hs:
		for k in range(0, cs.size(), 6):
			var d := Vector2(cs[k + 1], cs[k + 2]).distance_squared_to(h)
			if d < bd:
				bd = d
				best = int(cs[k])
	return [best, sqrt(bd)]


func _body() -> PackedFloat32Array:
	var cs: PackedFloat32Array = scene.sim.get_colonies()
	for k in range(0, cs.size(), 6):
		if int(cs[k]) == follow or follow < 0:
			return cs.slice(k, k + 6)
	return PackedFloat32Array()


func _follow() -> void:
	while true:
		await process_frame
		var b := _body()
		if b.is_empty():
			# (It was eaten: the next nearest to a hunter.)
			follow = int(_prey()[0])
			continue
		var at := Vector2(b[1], b[2])
		var hs: PackedVector2Array = scene.sim.get_positions(0)
		for h: Vector2 in hs:
			if h.distance_to(at) < 160.0:
				at = at.lerp(h, 0.35)
				break
		scene.focus(scene.cam.position.lerp(at, 0.08), zoom)


func _run() -> void:
	scene.start_level(Levels.by_id("5-3"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	var b: Control = scene.designer.body_bench
	var lo := Vector2i(100, 100)
	for c: Array in b.cells:
		lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
	b.place(lo, Colony.ARMOR)
	b.place(lo + Vector2i(0, 2), Colony.ARMOR)
	b.place(lo + Vector2i(1, 1), Colony.STORE)
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	var lr: Node = scene.level_runner
	if lr.tutorial:
		lr.tutorial._skip()
	scene.set_speed(3.0)
	await _until(func() -> bool: return float(_prey()[1]) < 260.0)
	scene.set_speed(1.0)
	follow = int(_prey()[0])
	var b0 := _body()
	scene.focus(Vector2(b0[1], b0[2]), zoom)
	_follow()
	print("bites from frame ", Engine.get_frames_drawn())
	await _until(func() -> bool: return false, 600)
	print("bites to frame ", Engine.get_frames_drawn())
	scene.set_speed(8.0)
	await _until(func() -> bool: return lr.eval.t > 140.0)
	scene.set_speed(1.0)
	zoom = 9.0
	follow = -1
	print("famine from frame ", Engine.get_frames_drawn())
	await _until(func() -> bool: return false, 300)
	print("famine to frame ", Engine.get_frames_drawn())
	quit()
