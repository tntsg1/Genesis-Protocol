extends SceneTree
# Bodies must not sink into each other: run the showcase dish headless and
# sample how deep single cells overlap as drawn (SimCore.get_overlap_stats).
# Run: godot --headless -s tests/overlap_check.gd

func _initialize() -> void:
	var scene: Node2D = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	_run.call_deferred(scene)


func _run(scene: Node2D) -> void:
	var worst_frac := 0.0
	var worst_px := 0.0
	var over_share := 0.0
	var samples := 0
	for k in 12:
		scene.advance(10.0)
		var o: PackedFloat32Array = scene.sim.get_overlap_stats()
		var share := o[1] / maxf(o[0], 1.0)
		print("t=%3ds  touching %4d  overlapping %3d (%.1f%%)  deepest %.2f px (%.0f%% of a half width)" % [(k + 1) * 10, o[0], o[1], share * 100.0, o[2], o[3] * 100.0])
		worst_frac = maxf(worst_frac, o[3])
		worst_px = maxf(worst_px, o[2])
		over_share += share
		samples += 1
	over_share /= samples
	# A few pairs in a jam can stay a pixel or two apart for one tick.
	var ok := worst_frac < 0.6 and over_share < 0.01
	print("%s  deepest overlap %.0f%% of a half width, %.1f%% of touching pairs overlap" % ["PASS" if ok else "FAIL", worst_frac * 100.0, over_share * 100.0])
	quit()
