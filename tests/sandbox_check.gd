extends SceneTree
# The sandbox has everything the campaign taught (DECISIONS 沙盒补全): every
# environment switch on and off while it runs, the natives added, all nine
# tools in the tray with their own keys, the designer's switches open.
# Shoots proofs/sandbox_world.png. Prints PASS / FAIL lines.
# Run: tools/run_test.sh tests/sandbox_check.gd

var scene: Node2D
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


func _run() -> void:
	await create_timer(1.5).timeout
	_check(scene.level_runner == null, "在沙盒里")
	var tray: ToolTray = scene.hud_root.tools
	await process_frame
	var shown := 0
	for k: String in ToolTray.KINDS:
		shown += 1 if tray.cards[k].visible else 0
	_check(shown == 9, "工具托盘九个工具都在（%d）" % shown)
	_check(scene.iv.slot_kind("phage") == "phage" and scene.iv.slot_kind("heat") == "heat", "沙盒里病毒、升温不被换成别的工具")
	for key: String in ["oxygen", "net", "walls", "night", "helio", "mud", "rain", "slime"]:
		scene.sandbox_world.toggle(key)
		_check(scene.sandbox_world.is_on(key), "打开：" + key)
	for n: Array in SandboxWorld.NATIVES:
		scene.sandbox_world.add_native(n[0])
	scene.set_speed(8.0)
	await create_timer(8.0).timeout
	scene.set_speed(1.0)
	var st: Dictionary = scene.sim.get_stats()
	_check((st.species as Array).size() >= 9, "原生物种加进来了（%d 个物种）" % (st.species as Array).size())
	_check(bool(scene.sim.get_slime().get("on", false)), "黏菌在")
	_check(scene.sim.get_walls().size() > 0, "冰墙在")
	scene.hud_root.toggle_world_panel()
	scene.focus(Vector2(1100, 1100), 0.45)
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/sandbox_world.png"))
	for key: String in ["oxygen", "net", "walls", "night", "helio", "mud", "rain", "slime"]:
		if scene.sandbox_world.is_on(key):
			scene.sandbox_world.toggle(key)
	await create_timer(1.0).timeout
	_check(scene.sim.get_walls().size() == 0 and not bool(scene.sim.get_slime().get("on", false)), "全部关掉")
	scene.open_designer()
	await create_timer(2.0).timeout
	var d: Control = scene.designer
	_check(d != null and d.rule_open("resp_open") and d.rule_open("euk_open") and d.rule_open("acid_open") and d.rule_open("life_open"), "设计器四个开关都开放")
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit()
