extends SceneTree
# The release capsule (精修 L): a designed species released at a spot, seen
# close: the laser frame, embryos appearing, the progress ring, the iris
# opening and the hatch. Frame-counted (works under --write-movie); also
# saves proofs/release_<frame>.png at a few moments.
# Run: tools/run_test.sh tests/record_release.gd [--write-movie <out.avi> --fixed-fps 60]

const SPOT := Vector2(900, 1050)
const SHOTS := [12, 30, 55, 80, 100, 108, 118, 135, 170]

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(30)
	scene.focus(SPOT, 1.0)
	scene.open_designer()
	var d: Control = scene.designer
	while d.busy:
		await process_frame
	await _frames(10)
	d.genes = [3.0, 3.0, 2.0, 1.0, 4.0, 3.0, 3.0, 2.5]
	d._refresh()
	d.color = d.SWATCHES[0]
	d.release()
	while scene.designer != null:
		await process_frame
	scene.focus(SPOT, 2.6)
	await _frames(70)
	scene._do_release(SPOT)
	for f in 200:
		await RenderingServer.frame_post_draw
		if f in SHOTS:
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/release_%03d.png" % f))
	quit()
