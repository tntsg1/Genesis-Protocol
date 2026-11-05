extends SceneTree
# The end of Europa (scripts/ui/ending.gd) at its key moments: proofs/boss/end_*.png.
# Run: tools/run_test.sh tests/ending_shot.gd

func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/boss"))
	var e: CanvasLayer = preload("res://scripts/ui/ending.gd").new()
	root.add_child(e)
	e.set_process(false)
	for at in [4.0, 10.5, 12.8, 15.5, 18.5, 24.0, 28.5, 37.0]:
		e.t = at
		e.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/boss/end_%04.1f.png" % at))
	quit()
