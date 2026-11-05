extends SceneTree
# Level 22's hunter at work, followed by the camera: it closes on a colony,
# bites mouthfuls off the rim (each drawn in and digested) and, when the body
# is eaten down, draws the rest in whole. Stills of the swallow go to
# proofs/hunter/swallow_*.png; with --write-movie the whole run is the film.
# Env H_LEVEL (5-3), H_SECONDS (film length after the first bite, 28).
# Run: tools/run_test.sh tests/hunter_clip.gd [--write-movie <file.avi> --fixed-fps 30]

var scene: Node2D
var at := Vector2.ZERO
var zoom := 3.4


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


# The hunter nearest a colony, and how near.
func _closest() -> Array:
	var hs: PackedVector2Array = scene.sim.get_positions(0)
	var cs: PackedFloat32Array = scene.sim.get_colonies()
	var best := Vector2.INF
	var bd := 1e12
	for h: Vector2 in hs:
		for k in range(0, cs.size(), 6):
			var d := Vector2(cs[k + 1], cs[k + 2]).distance_squared_to(h)
			if d < bd:
				bd = d
				best = h
	return [best, sqrt(bd)]


# The camera stays on the hunter it is watching (the one nearest where it was),
# moving on now and then to whichever is closest to a colony.
func _follow() -> void:
	var n := 0
	while true:
		await process_frame
		n += 1
		if n % 90 == 0 and float(_closest()[1]) < 200.0 and _closest()[0].distance_to(at) > 400.0:
			at = _closest()[0]
		var hs: PackedVector2Array = scene.sim.get_positions(0)
		var near := Vector2.INF
		for h: Vector2 in hs:
			if not near.is_finite() or h.distance_squared_to(at) < near.distance_squared_to(at):
				near = h
		if near.is_finite():
			at = at.lerp(near, 0.12)
		scene.focus(scene.cam.position.lerp(at, 0.1), zoom)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/hunter/%s.png" % name))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/hunter"))
	var lid := OS.get_environment("H_LEVEL") if OS.get_environment("H_LEVEL") != "" else "5-3"
	scene.start_level(Levels.by_id(lid))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	if OS.get_environment("H_GUIDE") == "1":
		# The guide's body (tests/play_ch5.gd), so what the level teaches shows.
		var pc: GDScript = preload("res://tests/play_ch5.gd")
		var rows: Array = pc.GUIDES[lid]
		var bench: Control = scene.designer.body_bench
		var kinds := {"F": Colony.FLAG, "G": Colony.GERM, "A": Colony.ARMOR, "S": Colony.STORE, "R": Colony.REGEN}
		var lo := Vector2i(100, 100)
		for c: Array in bench.cells:
			lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
		for j in rows.size():
			for i in (rows[j] as String).length():
				if int(Colony.type_at(bench.cells, lo.x + i, lo.y + j)) != int(kinds[rows[j][i]]):
					bench.place(lo + Vector2i(i, j), kinds[rows[j][i]])
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	var lr: Node = scene.level_runner
	if lr.tutorial:
		lr.tutorial._skip()
	scene.set_speed(4.0)
	await _until(func() -> bool: return float(_closest()[1]) < 320.0)
	scene.set_speed(float(OS.get_environment("H_SPEED")) if OS.get_environment("H_SPEED") != "" else 1.0)
	at = _closest()[0]
	scene.focus(at, zoom)
	_follow()
	var eaten0 := int(scene.sim.get_colony_stats().get("eaten", 0))
	var seconds := float(OS.get_environment("H_SECONDS")) if OS.get_environment("H_SECONDS") != "" else 28.0
	var frames := int(seconds * 30.0)
	var shot := false
	var irr := OS.get_environment("H_IRR") == "1"
	for f in frames:
		await process_frame
		# (H_IRR: level 24's irritant used as a player would, when a cracked
		# body is in the guardian's pull.)
		if irr and f % 10 == 0 and scene.sim.get_rotifer_retract()[0] <= 0.0 and scene.iv.ready_to_use("irritant"):
			var rot: PackedFloat32Array = scene.sim.get_rotifers(1.0)
			var head := Vector2(rot[0], rot[1]) + Vector2.from_angle(rot[2]) * 88.0
			var worn: PackedFloat32Array = scene.sim.get_worn(1.0)
			for w in range(0, worn.size(), 5):
				if Vector2(worn[w], worn[w + 1]).distance_to(head) < 420.0 and worn[w + 4] <= 0.0:
					scene.iv.select("current")
					scene.iv.place("irritant", head)
					break
		if not shot and int(scene.sim.get_colony_stats().get("eaten", 0)) > eaten0:
			shot = true
			print("swallow at frame ", Engine.get_frames_drawn())
			scene.set_speed(1.0)
			for k in 6:
				await _shot("swallow_%d" % k)
				await _until(func() -> bool: return false, 8)
			if OS.get_environment("H_SPEED") != "":
				break
	if not shot:
		await _shot("no_swallow")
	quit()
