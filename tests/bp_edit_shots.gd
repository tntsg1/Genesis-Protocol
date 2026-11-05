extends SceneTree
# A gene edit on the designer's stage: the old base pairs pulled out like
# pins, the new level's sliding in and locking; then a fast drag across
# several levels (the edit hurries and follows on). Frames go to proofs/.
# Run: tools/run_test.sh tests/bp_edit_shots.gd

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


func _level(d: Control, k: int, v: float) -> void:
	d.gene_sliders[k].value = v
	d.gene_sliders[k].changed.emit(v)


func _run() -> void:
	await create_timer(1.0).timeout
	scene.focus(Vector2(900, 1000), 1.2)
	scene.open_designer()
	var d: Control = scene.designer
	while d.busy:
		await process_frame
	await create_timer(1.2).timeout
	await _shot("bp_0_before")
	var t0 := Time.get_ticks_msec()
	_level(d, 0, d.genes[0] + 0.5)
	for at in [0.12, 0.26, 0.4, 0.54, 0.7, 1.0]:
		while Time.get_ticks_msec() - t0 < at * 1000.0:
			await process_frame
		await _shot("bp_%d_edit" % roundi(at * 100.0))
		print("edit_t %.2f at %.2f" % [d.edit_t[0], at])
	# A fast drag: three levels in 0.15 s.
	await create_timer(0.5).timeout
	for i in 3:
		_level(d, 0, d.genes[0] + 0.5)
		await create_timer(0.05).timeout
	await create_timer(0.3).timeout
	await _shot("bp_drag_mid")
	await create_timer(1.6).timeout
	await _shot("bp_drag_done")
	print("final level %s shows %s, ticker: %s" % [d.genes[0], d.bp_lv[0], d.ticker.text])
	quit()
