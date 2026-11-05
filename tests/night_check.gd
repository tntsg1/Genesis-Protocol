extends SceneTree
# Night mode's rules (scripts/night_mode.gd): "auto" is on in chapter 6's
# seabed and off elsewhere; the key flips it and the choice sticks (saved);
# a cutscene holds it off. Prints PASS / FAIL.
# Run: tools/run_test.sh tests/night_check.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	NightMode.set_setting("auto")
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	fails += 0 if ok else 1


func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.pressed = down
		root.push_input(e)
		await process_frame


func _run() -> void:
	await create_timer(1.0).timeout
	_check(not NightMode.on(), "自动：沙盒里不开")
	scene.load_world(Levels.by_id("6-1").world)
	_check(NightMode.on(), "自动：第六章海底关卡开")
	scene.load_world(Levels.by_id("2-1").world)
	_check(not NightMode.on(), "自动：第二章不开")
	await _key(Keys.code("night"))
	_check(NightMode.on() and NightMode.setting == "on", "按 %s 打开（设置变成始终开）" % Keys.name_of(Keys.code("night")))
	var cf := ConfigFile.new()
	cf.load(Keys.path())
	_check(str(cf.get_value("display", "night", "")) == "on", "选择写进了设置文件")
	await create_timer(0.5).timeout
	_check(scene.night.amt > 0.9, "画面变黑（渐变完成）")
	var e: CanvasLayer = preload("res://scripts/ui/ending.gd").new()
	scene.add_child(e)
	await create_timer(0.6).timeout
	_check(scene.night.amt < 0.05, "过场动画播放时让开")
	e._end()
	await create_timer(0.6).timeout
	_check(scene.night.amt > 0.9, "过场结束后恢复")
	await _key(Keys.code("night"))
	_check(not NightMode.on() and NightMode.setting == "off", "再按一次关掉")
	NightMode.set_setting("auto")
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit()
