extends SceneTree
# Developer mode: ` brings up the passcode box, a wrong code is refused, 111
# opens the panel (developer save on), switches and buttons do what they say,
# the campaign page shows every level open, Esc closes, turning the mode off
# goes back to the normal save. Synthetic keys only. Saves proofs/dev_*.png.
# Run: tools/run_test.sh tests/dev_mode_check.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/dev_%s.png" % name))


func _key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _ok(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		fails += 1


# The panel's button or switch whose text contains `text`.
func _pill(text: String) -> Button:
	for n in scene.dev_panel.find_children("*", "Button", true, false):
		if (n as Button).text.contains(text) and (n as Button).is_visible_in_tree():
			return n
	return null


func _run() -> void:
	await _frames(90)
	await _key(KEY_QUOTELEFT)
	await _frames(20)
	_ok(is_instance_valid(scene.dev_prompt), "` opens the passcode box")
	for c in [KEY_2, KEY_2, KEY_2, KEY_ENTER]:
		await _key(c)
	await _frames(10)
	_ok(not DevMode.auth and is_instance_valid(scene.dev_prompt), "a wrong code is refused")
	await _shot("prompt_wrong")
	for c in [KEY_1, KEY_1, KEY_1]:
		await _key(c)
	await _frames(50)
	_ok(DevMode.auth and DevMode.active, "111 unlocks, developer save on")
	_ok(is_instance_valid(scene.dev_panel), "the panel opens")
	await _frames(30)
	await _shot("panel_dish")
	var p := _pill("×4")
	if p:
		p.pressed.emit()
	await _frames(5)
	_ok(is_equal_approx(scene.speed, 4.0), "speed ×4")
	_pill("×1").pressed.emit()
	_pill("干预免费").pressed.emit()
	_ok(DevMode.free_iv and scene.iv.ready_to_use("nutrient"), "free interventions")
	scene.iv.points = 0.0
	_pill("生物质点加满").pressed.emit()
	_ok(scene.iv.points >= scene.iv.MAX_POINTS, "biomass points filled")
	_pill("帧率与模拟耗时").pressed.emit()
	await _frames(30)
	_ok(scene.dev_overlay.visible, "timings overlay shows")
	await _shot("panel_toggles")
	var r0 := CampaignSave.research()
	_pill("研究点 +100").pressed.emit()
	_ok(CampaignSave.research() == r0 + 100, "research +100")
	_pill("解锁全部关卡").pressed.emit()
	_ok(CampaignSave.unlocked(Levels.ALL.size()), "every level open")
	await _key(KEY_ESCAPE)
	await _frames(30)
	_ok(not is_instance_valid(scene.dev_panel) and DevMode.active, "Esc hides the panel, the mode stays on")
	scene.open_campaign()
	await _frames(150)
	await _key(KEY_QUOTELEFT)
	await _frames(40)
	_ok(not DevMode.active and not is_instance_valid(scene.dev_panel) and not is_instance_valid(scene.dev_prompt), "` again turns the mode off (no panel, no prompt)")
	await _key(KEY_QUOTELEFT)
	await _frames(40)
	_ok(DevMode.active and is_instance_valid(scene.dev_panel) and not is_instance_valid(scene.dev_prompt), "` turns it back on without the passcode")
	await _shot("panel_campaign")
	# The designer: everything open, no budget limit.
	await _key(KEY_QUOTELEFT)
	await _frames(20)
	scene.open_designer()
	var d: Control = scene.designer
	while d.busy:
		await process_frame
	await _key(KEY_QUOTELEFT)
	await _frames(30)
	_pill("基因、规则零件全部开放").pressed.emit()
	_pill("基因预算不限").pressed.emit()
	d.genes = [5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0]
	d._refresh()
	await _frames(10)
	_ok(d.level_id() == "" and not d.go_hint.text.contains("基因预算超出"), "designer: all open, budget not enforced")
	await _shot("panel_designer")
	_pill("关闭开发者模式").pressed.emit()
	await _frames(30)
	_ok(not DevMode.active and not DevMode.unlock_all, "off: back to the normal save, switches cleared")
	_ok(not CampaignSave.unlocked(Levels.ALL.size()) or CampaignSave.stars(Levels.ALL[Levels.ALL.size() - 2].id)[0], "levels locked again")
	print("dev_mode_check: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(fails)
