extends SceneTree
# The mutation spelled out: the log entry and the life scan of the mutant.
# Saves proofs/mutation_scan.png. Run: tools/run_test.sh tests/mutation_shot.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await process_frame


func _run() -> void:
	scene.set_speed(8.0)
	var t0 := Time.get_ticks_msec()
	var info := {}
	while Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		if scene.last_mutation_id >= 0:
			var a: Dictionary = scene.sim.get_agent(scene.last_mutation_id)
			if not a.is_empty() and scene.mutation_list(a).size() >= 2:
				info = a
				break
	scene.set_speed(1.0)
	if info.is_empty():
		print("no mutant found")
		quit()
		return
	scene.inspect(int(info.id), int(info.lineage), int(info.species), info.position)
	await _wait(2.5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/mutation_scan.png"))
	print("MUT: ", scene.mutation_text(info))
	quit()
