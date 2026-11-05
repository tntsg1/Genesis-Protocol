extends SceneTree
# Close-ups of the designer's lab: the genome page settled, a level change
# mid-flash, the lens sliding to another gene, the rules page.
# Run: tools/run_test.sh tests/lab_shots.gd

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


func _run() -> void:
	await create_timer(1.0).timeout
	scene.focus(Vector2(900, 1000), 1.2)
	scene.open_designer()
	var d: Control = scene.designer
	await create_timer(1.9).timeout
	await _shot("lab_dive")
	while d.busy:
		await process_frame
	await create_timer(0.5).timeout
	await _shot("lab_genome")
	d.gene_sliders[3].value = 3.0
	d.gene_sliders[3].changed.emit(3.0)
	await create_timer(0.25).timeout
	await _shot("lab_change")
	await create_timer(1.5).timeout
	d.select_gene(5)
	await create_timer(0.2).timeout
	await _shot("lab_slide")
	await create_timer(1.0).timeout
	d.show_page("rules")
	await create_timer(0.8).timeout
	await _shot("lab_rules")
	quit()
