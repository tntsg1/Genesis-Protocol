extends SceneTree

var scene: Node2D
var failures := 0

func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1

func click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event)
		await process_frame

func _run() -> void:
	await create_timer(1.0).timeout
	scene.start_experiment()
	await create_timer(3.5).timeout
	var hud = scene.hud_root
	var row: Control = hud.species_rows[0][3]
	var point := row.get_global_rect().get_center()
	check(hud.pinned_row == -1 and scene.focus_species == -1, "normal view starts with all species visible")
	await click(point)
	await create_timer(0.5).timeout
	check(hud.pinned_row == 0 and scene.focus_amt > 0.9 and hud.clear_species_focus.visible, "click highlights and exposes clear control")
	await click(point)
	await create_timer(0.5).timeout
	check(hud.pinned_row == -1 and scene.focus_amt == 0.0, "second click restores view without moving pointer")
	await click(point)
	await create_timer(0.3).timeout
	await click(hud.clear_species_focus.get_global_rect().get_center())
	await create_timer(0.5).timeout
	check(hud.pinned_row == -1 and scene.focus_amt == 0.0, "show all restores view")
	scene.start_level(Levels.by_id("2-2"))
	var deadline := Time.get_ticks_msec() + 30000
	while (scene.designer == null or scene.designer.busy) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.designer != null and not scene.designer.busy, "2-2 designer opens")
	if scene.designer != null and not scene.designer.busy:
		scene.designer.release()
		deadline = Time.get_ticks_msec() + 15000
		while scene.level_runner.phase != "run" and Time.get_ticks_msec() < deadline:
			await process_frame
		await create_timer(0.5).timeout
		check(scene.level_runner.phase == "run" and hud.pinned_row == -1 and scene.focus_amt == 0.0, "2-2 release leaves all species visible")
	quit(failures)
