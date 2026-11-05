extends SceneTree
# Close-up frames of a phage infection in 4-1, from landing to the burst.
# Shots go to proofs/phage/. Run: tools/run_test.sh tests/phage_shot.gd

var scene: Node2D
var dir := ""


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/phage")
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)


# Seconds since landing of the followed cell (-1 when it is gone).
func _clock(pos: Vector2) -> Array:
	var cells: PackedFloat32Array = scene.sim.get_infected(Rect2(pos - Vector2(60, 60), Vector2(120, 120)), 0.0)
	var best := -1.0
	var at := pos
	var nearest := 1e9
	for k in range(0, cells.size(), 10):
		var p := Vector2(cells[k], cells[k + 1])
		if p.distance_to(pos) < nearest:
			nearest = p.distance_to(pos)
			best = cells[k + 5]
			at = p
	return [best, at]


func _run() -> void:
	scene.start_level(Levels.by_id("4-1"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	# (The guide stays on: the level's own close-up of the first infection.)
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	await create_timer(6.0).timeout
	var ps: PackedVector2Array = scene.sim.get_positions(scene.level_runner.sp_index)
	scene.sim.add_phages(ps[0], 40.0, 70)
	await _until(func() -> bool: return scene.level_runner.fired.has("phage_seen"), 20.0)
	var id: int = scene.level_runner.tagged_id
	scene.selected = id
	scene.gone_timer = 0.0
	scene.following = true
	scene.goal_zoom = 16.0
	print("following ", id, " ", scene.following)
	var marks := [0.7, 1.35, 1.9, 8.0, 15.0, 21.0, 23.7]
	for m: float in marks:
		await _until(func() -> bool:
			var info: Dictionary = scene.sim.get_agent(id)
			return info.is_empty() or float(info.infected) >= m, 25.0)
		await _shot("t_%04.1f" % m)
	await _until(func() -> bool: return scene.sim.get_agent(id).is_empty(), 5.0)
	await process_frame
	await _shot("t_burst_a")
	await create_timer(0.5).timeout
	await _shot("t_burst_b")
	await create_timer(1.2).timeout
	await _shot("t_burst_c")
	await create_timer(1.6).timeout
	await _shot("t_burst_far")
	await create_timer(3.5).timeout
	await _shot("t_group")
	scene.set_speed(8.0)
	await create_timer(20.0).timeout
	scene.set_speed(1.0)
	await _shot("t_outbreak")
	var lr: Node = scene.level_runner
	lr.finish()
	await _until(func() -> bool: return is_instance_valid(lr.report), 10.0)
	await create_timer(7.0).timeout
	await _shot("t_report")
	quit()
