extends SceneTree
# The sandbox's terrain editor (DECISIONS 地形编辑器): every brush stroked
# through TerrainEditor.handle (as the dish hands it mouse input), undo and
# redo, save / load, a template; also the sandbox's nine tools and the
# designer's switches. Shoots proofs/terrain_*.png. Prints PASS / FAIL lines.
# Run: tools/run_test.sh tests/terrain_check.gd

var scene: Node2D
var ed: TerrainEditor
var fails := 0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _btn(pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	return e


func _stroke(brush: String, a: Vector2, b: Vector2) -> void:
	ed.set_brush(brush)
	ed.handle(_btn(true), a)
	for k in 6:
		ed.handle(InputEventMouseMotion.new(), a.lerp(b, (k + 1) / 6.0))
	ed.handle(_btn(false), b)


func _run() -> void:
	await create_timer(1.5).timeout
	ed = scene.hud_root.terrain
	var shown := 0
	for k: String in ToolTray.KINDS:
		shown += 1 if scene.hud_root.tools.cards[k].visible else 0
	_check(shown == 9, "工具托盘九个工具都在（%d）" % shown)
	ed.open()
	_check(ed.active and scene.paused, "地形编辑打开，培养皿暂停")
	var m: Dictionary = scene.sandbox_world.map
	var z0 := (m.zones as Array).size()
	_stroke("zone", Vector2(700, 1500), Vector2(900, 1500))
	_check((scene.sandbox_world.map.zones as Array).size() == z0 + 1, "画了一个环境区")
	_stroke("wall", Vector2(1000, 300), Vector2(1000, 900))
	_check(scene.sim.get_walls().size() >= 2, "画了一道冰墙")
	_stroke("light", Vector2(1500, 700), Vector2(1700, 700))
	_stroke("band", Vector2(1100, 800), Vector2(1100, 800))
	_stroke("mud", Vector2(1100, 1300), Vector2(1100, 1300))
	_check(not (scene.sandbox_world.map.mud as Dictionary).is_empty() and scene.o2_world, "泥层和氧气")
	var a0: int = int(scene.sim.get_stats().algae)
	_stroke("algae", Vector2(600, 800), Vector2(900, 900))
	_check(int(scene.sim.get_stats().algae) > a0, "刷了藻团（%d → %d）" % [a0, int(scene.sim.get_stats().algae)])
	_stroke("shells", Vector2(1300, 1600), Vector2(1500, 1650))
	_stroke("slime", Vector2(1100, 1100), Vector2(1100, 1100))
	_check(bool(scene.sim.get_slime().get("on", false)), "放下了黏菌")
	_stroke("helio", Vector2(1600, 1100), Vector2(1600, 1100))
	_check(bool(scene.sim.get_helio().get("on", false)), "放下了太阳虫")
	_stroke("net", Vector2(1100, 1800), Vector2(1100, 1800))
	scene.sandbox_world.edit(func(mm: Dictionary) -> void: mm.night = {day = 40.0, night = 20.0, cold = -20.0})
	scene.sandbox_world.edit(func(mm: Dictionary) -> void: mm.rain = {dry = 40.0, wet = 20.0, level = 5.0})
	_check(scene.sandbox_world.events.size() == 2, "长夜和酸雨在跑")
	ed.close()
	scene.set_speed(8.0)
	await create_timer(6.0).timeout
	scene.set_speed(1.0)
	ed.open()
	scene.focus(Vector2(1100, 1100), 0.45)
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/terrain_edit.png"))
	ed.handle(_ctrl(KEY_Z), Vector2.INF)
	ed.handle(_ctrl(KEY_Z), Vector2.INF)
	_check((scene.sandbox_world.map.night as Dictionary).is_empty(), "撤销两步（酸雨、长夜）")
	ed.handle(_ctrl(KEY_Y), Vector2.INF)
	_check(not (scene.sandbox_world.map.night as Dictionary).is_empty(), "重做一步")
	_stroke("erase", Vector2(1100, 1100), Vector2(1100, 1100))
	_check(not bool(scene.sim.get_slime().get("on", false)), "橡皮擦掉了黏菌")
	_check(scene.sandbox_world.save_as("测试世界"), "保存")
	scene.sandbox_world.load_map(SandboxWorld.template("p3"))
	_check(not (scene.sandbox_world.map.mud as Dictionary).is_empty() and scene.sandbox_world.events.size() == 1, "换成星球三模板（泥层、酸雨）")
	_check(scene.sandbox_world.load_saved("测试世界") and scene.sim.get_walls().size() >= 2, "读取保存的世界")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SandboxWorld.DIR + "测试世界.world"))
	ed.close()
	ed.show_picker()
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/terrain_picker.png"))
	ed.picker.visible = false
	scene.open_designer()
	await create_timer(2.0).timeout
	var d: Control = scene.designer
	_check(d != null and d.rule_open("resp_open") and d.rule_open("euk_open") and d.rule_open("acid_open") and d.rule_open("life_open"), "设计器四个开关都开放")
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit()


func _ctrl(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.ctrl_pressed = true
	e.pressed = true
	return e
