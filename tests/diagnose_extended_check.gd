extends SceneTree
# Exercise the level-specific diagnoses against controlled 30-second snapshots.
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok: fails += 1

func snap(t: float) -> Dictionary:
	return {t = t, alive = 30, births = 0, starved = 0, eaten = 0, aged = 0, temp = 0, acid = 0, o2 = 0, phage = 0, all = [], col = {}, slug = {}}

func has_id(results: Array, id: String) -> bool:
	return results.any(func(r: Dictionary) -> bool: return str(r.id) == id)

func _initialize() -> void:
	CampaignSave.reset_for_tests()
	var sim := SimCore.new()
	var a := snap(60.0)
	var b := snap(90.0)
	var l := Levels.by_id("4-4")
	var ev := LevelEval.new(l, 1, 0.0)
	b.all = [[101, 0], [30, 0]]
	check(has_id(Diagnose.read(l, sim, ev, a, b), "no_drop"), "4-4 达到条件时提醒投放")
	b.all = [[100, 0], [30, 0]]
	check(not has_id(Diagnose.read(l, sim, ev, a, b), "no_drop"), "4-4 对手未超过 100 时不提醒")
	l = Levels.by_id("1-4")
	ev = LevelEval.new(l, 0, 0.0)
	var des := {params = {deck = [{act = Rules.A_REST}, {act = Rules.A_DIVIDE}]}}
	check(has_id(Diagnose.read(l, sim, ev, a, b, -1, des), "rest_first"), "1-4 休息排在分裂前时给诊断")
	des.params.deck.reverse()
	check(not has_id(Diagnose.read(l, sim, ev, a, b, -1, des), "rest_first"), "1-4 分裂排在前时不误报")
	l = Levels.by_id("5-2")
	ev = LevelEval.new(l, 0, 0.0)
	b.col = {burned = 1}
	check(has_id(Diagnose.read(l, sim, ev, a, b), "vent"), "5-2 群体被冲入喷口时给诊断")
	b.col = {burned = 0}
	check(not has_id(Diagnose.read(l, sim, ev, a, b), "vent"), "5-2 没有冲入喷口时不误报")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
