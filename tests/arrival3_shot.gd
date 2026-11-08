extends SceneTree
# The passage to planet three (scripts/ui/arrival3.gd) at its key moments:
# proofs/ch8/arrival_*.png. Run: tools/run_test.sh tests/arrival3_shot.gd

func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/ch8"))
	var e: CanvasLayer = preload("res://scripts/ui/arrival3.gd").new()
	root.add_child(e)
	e.set_process(false)
	for at in [3.0, 9.0, 15.0, 19.5, 23.5, 26.0, 27.5, 29.0]:
		e.t = at
		e.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/ch8/arrival_%04.1f.png" % at))
	quit()
