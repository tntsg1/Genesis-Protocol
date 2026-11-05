extends SceneTree
# Recording of gene edits on the designer's stage: 速度 up, up again, down,
# a fast drag across three levels, then 繁殖 edited after the strand runs to
# it. Each edit cuts the gene's stretch of DNA out, peels it away and presses the new
# level's in.
# Run: tools/run_test.sh tests/record_bp_edit.gd --write-movie <out.avi> --fixed-fps 60

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


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
	await create_timer(0.8).timeout
	for step in [0.5, 0.5, -0.5]:
		_level(d, 0, d.genes[0] + step)
		await create_timer(1.3).timeout
	for i in 3:
		_level(d, 0, d.genes[0] + 0.5)
		await create_timer(0.07).timeout
	await create_timer(1.8).timeout
	d.select_gene(4)
	await create_timer(1.4).timeout
	_level(d, 4, d.genes[4] - 0.5)
	await create_timer(1.5).timeout
	quit()
