extends SceneTree
# The whole end of Europa (scripts/ui/ending.gd) as it plays, for --write-movie.
# Run: tools/run_test.sh tests/ending_clip.gd --write-movie <file.avi> --fixed-fps 30

func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	var e: CanvasLayer = preload("res://scripts/ui/ending.gd").new()
	e.finished.connect(quit)
	root.add_child(e)
