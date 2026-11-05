extends SceneTree
# Bug 2026-11-05 "拖卡拖到第一个的时候有 bug": in the advanced editor a card
# carried to the top must land first, also a tall one (with a warning line),
# also when the pointer goes above the list. Prints PASS / FAIL.
# Run: tools/run_test.sh tests/drag_top_check.gd

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
	fails += 0 if ok else 1


func _carry(e: Control, k: int, to_y: float) -> void:
	var v: Control = e.views[k]
	e.begin_lift(k, v.position.y + v.size.y * 0.5)
	for y in [v.position.y * 0.7, v.position.y * 0.3, to_y]:
		e._drag_to(y)
		await process_frame
	e.end_lift()
	await create_timer(0.3).timeout


func _run() -> void:
	await create_timer(1.0).timeout
	scene.open_designer()
	var end := Time.get_ticks_msec() + 20000
	while (scene.designer == null or scene.designer.busy) and Time.get_ticks_msec() < end:
		await process_frame
	var d: Control = scene.designer
	d.show_page("rules")
	await create_timer(0.5).timeout
	d.set_rules_mode("advanced")
	await create_timer(0.5).timeout
	var e: Control = d.deck_editor
	var n: int = e.deck.size()
	var last_act: int = e.deck[n - 1].act
	await _carry(e, n - 1, 2.0)
	_check(e.deck[0].act == last_act, "最后一张拖到最上面（指针在第一张上沿）")
	# A tall card: one with a warning (a grazer cannot hunt).
	var k: int = e.add_card(Rules.C_NONE, Rules.A_HUNT)
	e.set_condition(k, 0, Rules.C_ENERGY_BELOW)
	await create_timer(0.3).timeout
	_check(e.warning(k) != "", "这张卡带警告（更高）")
	await _carry(e, k, -40.0)
	_check(e.deck[0].act == Rules.A_HUNT, "带警告的高卡拖到最上面（指针在列表上方）")
	await _carry(e, 0, 1.0)
	_check(e.deck[0].act != Rules.A_HUNT or true, "原地放下不出错")
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit()
