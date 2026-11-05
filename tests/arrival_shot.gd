extends SceneTree
# Landfall on planet one (scripts/ui/arrival.gd) at its key moments:
# proofs/ch6/arrival_*.png. Run: tools/run_test.sh tests/arrival_shot.gd

func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/ch6"))
	var e: CanvasLayer = preload("res://scripts/ui/arrival.gd").new()
	root.add_child(e)
	e.set_process(false)
	for at in [4.0, 10.0, 12.95, 15.5, 20.5, 24.5, 27.0, 29.0]:
		e.t = at
		e.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/ch6/arrival_%04.1f.png" % at))
	quit()
