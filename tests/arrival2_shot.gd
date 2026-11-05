extends SceneTree
# The passage to planet two (scripts/ui/arrival2.gd) at its key moments:
# proofs/ch7/arrival_*.png. Run: tools/run_test.sh tests/arrival2_shot.gd

func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/ch7"))
	var e: CanvasLayer = preload("res://scripts/ui/arrival2.gd").new()
	root.add_child(e)
	e.set_process(false)
	for at in [4.0, 9.5, 16.5, 21.0, 25.0, 26.8, 28.0, 29.0]:
		e.t = at
		e.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/ch7/arrival_%04.1f.png" % at))
	quit()
