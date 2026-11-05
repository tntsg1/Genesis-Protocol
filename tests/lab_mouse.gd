extends SceneTree
# The genome stage under a real (pushed) mouse: hover lens and probe, a drag
# that scrubs the strand and snaps to a gene when thrown, the wheel, a click
# with its ripple, a karyotype click, arrow keys.
# Run: tools/run_test.sh tests/lab_mouse.gd

var scene: Node2D
var fails := 0
var _last := Vector2.ZERO


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


func _btn(at: Vector2, idx: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = pressed
	e.position = at
	e.global_position = at
	e.button_mask = (1 << (idx - 1)) if pressed else 0
	root.push_input(e)


func _move(at: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = at - _last
	_last = at
	e.position = at
	e.global_position = at
	e.button_mask = mask
	root.push_input(e)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = pressed
		root.push_input(e)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	await _wait(1.0)
	scene.open_designer()
	var d: Control = scene.designer
	while d.busy:
		await process_frame
	await _wait(0.3)
	var c: Vector2 = d.STAGE_CENTER
	# Hover: the mouse lens comes up and the probe names the pair.
	_move(c + Vector2(60, 10), 0)
	await _wait(0.5)
	check(d.mouse_on > 0.8, "hovering the strand brings the mouse lens up (%.2f)" % d.mouse_on)
	check(d._probe_text(c + Vector2(60, 10)).begins_with("SPD"), "the probe reads the pair under it: " + d._probe_text(c + Vector2(60, 10)))
	await _shot("lab_hover")
	# Drag left fast and let go: it scrubs, coasts, snaps to a gene.
	var from := c + Vector2(200, 0)
	_move(from, 0)
	await process_frame
	_btn(from, MOUSE_BUTTON_LEFT, true)
	await process_frame
	for k in range(1, 11):
		_move(from + Vector2(-60.0 * k, 0), 1)
		await process_frame
	var mid_view: float = d.view_x
	await _shot("lab_drag")
	_btn(from + Vector2(-600, 0), MOUSE_BUTTON_LEFT, false)
	check(mid_view > d._gene_x(0) + 300.0, "dragging scrubs along the strand (view %.0f)" % mid_view)
	await _wait(2.5)
	check(d.sel_gene > 0 and absf(d.view_x - d._gene_x(d.sel_gene)) < 2.0, "the throw coasts and snaps to gene %d" % d.sel_gene)
	# Wheel: next gene.
	var before: int = d.sel_gene
	_move(c, 0)
	_btn(c, MOUSE_BUTTON_WHEEL_DOWN, true)
	_btn(c, MOUSE_BUTTON_WHEEL_DOWN, false)
	await _wait(0.1)
	check(d.sel_gene == mini(before + 1, d.NG - 1), "the wheel steps to the next gene")
	await _wait(1.0)
	# Click: a ripple, and the gene clicked.
	_btn(c + Vector2(-20, 0), MOUSE_BUTTON_LEFT, true)
	_btn(c + Vector2(-20, 0), MOUSE_BUTTON_LEFT, false)
	await _wait(0.12)
	check(d.ripple_t < 0.5, "a click sends a ripple along the strand")
	await _shot("lab_ripple")
	# Karyotype: click the first chromosome.
	var ky: float = d._specimen_center().y + d.TANK_BOTTOM + 92.0
	var kx: float = d.chamber.position.x + 18.0 + (d.chamber.size.x - 36.0) / 7.0 * 0.5
	_btn(Vector2(kx, ky), MOUSE_BUTTON_LEFT, true)
	_btn(Vector2(kx, ky), MOUSE_BUTTON_LEFT, false)
	await _wait(0.1)
	check(d.sel_gene == 0, "clicking a chromosome in the karyotype selects its gene")
	await _wait(0.4)
	await _shot("lab_run")
	await _wait(1.4)
	_key(KEY_RIGHT)
	await _wait(0.1)
	check(d.sel_gene == 1, "→ steps to the next gene")
	await _wait(0.9)
	await _shot("lab_lock")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
