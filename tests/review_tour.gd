extends SceneTree
# A screenshot tour for the player review (Sonnet as the player): the main
# menu, the campaign page, then every campaign level: its page, the designer
# as the guide opens it, the rules page, the dish a while after release (the
# guide's run line; from 1-5 on with the player's species picked out), and
# the report of a failed try.
# Shots go to proofs/tour/; the guide's lines and the level texts go to
# proofs/tour/texts.md.
# Run: tools/run_test.sh tests/review_tour.gd -- --menu

var scene: Node2D
var dir := ""
var texts := []


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/tour")
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String, wait := 0.8) -> void:
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])


func _run() -> void:
	await _until(func() -> bool: return scene.in_menu and scene.menu.shown, 20.0)
	await _shot("00_menu", 2.5)
	scene.open_campaign()
	await _shot("01_campaign", 3.0)
	var only := ""
	for u: String in OS.get_cmdline_user_args():
		if u.begins_with("--level="):
			only = u.trim_prefix("--level=")
	for l: Dictionary in Levels.ALL:
		var id: String = l.id
		if only != "" and id != only:
			continue
		texts.append("## %s %s\n\n简报：%s\n\n目标：%s\n\n附加挑战：%s\n\n已知情况：\n- %s\n\n过关提示（第一次失败时显示，只给方向）：\n- %s\n\n过关要点（第二次失败起显示）：\n- %s\n" % [id, l.name, l.brief, l.goal.text, l.challenge.text, "\n- ".join(l.threats), "\n- ".join(l.get("hints", [])), "\n- ".join(l.get("tips", []))])
		var steps: Dictionary = preload("res://scripts/campaign/tutorial.gd").STEPS.get(id, {})
		for part in ["design", "run"]:
			var lines := []
			for st: Variant in steps.get(part, []):
				var tail := ""
				if st is Dictionary and st.has("wait"):
					tail = "（做到才往下走%s）" % ("；小字目标：" + String(st.goal) if st.has("goal") else "")
				lines.append("- " + Keys.fill(st if st is String else String(st.text)) + tail)
			texts.append("引导（%s）：\n%s\n" % ["设计器里" if part == "design" else "投放后", "\n".join(lines)])
		# Unlock it, open it from the campaign page.
		var k: int = l.index - 1
		if k > 0:
			CampaignSave.record(Levels.ALL[k - 1].id, [true, false, false], false)
		scene.campaign._select(k)
		await _shot("%s_a_page" % id, 1.6)
		scene.start_level(l)
		await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
		await _shot("%s_b_designer" % id, 1.5)
		var d: Control = scene.designer
		if d.tab_buttons["rules"].modulate.a > 0.9:
			d.show_page("rules")
			await _shot("%s_c_rules" % id, 1.0)
			d.show_page("genome")
			await create_timer(0.5).timeout
		var g: Node = scene.level_runner.tutorial
		if g:
			g._skip()
		# A design the level accepts: its required organs.
		for o: String in l.get("require_organs", []):
			d.organ_bay.install(o)
		d.release()
		await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
		scene.set_speed(3.0)
		# The player's species picked out (a click on its row in the species panel).
		if l.index >= 5:
			scene.hud_root.pinned_row = scene.level_runner.sp_index
		await _shot("%s_d_run" % id, 6.0)
		scene.hud_root.pinned_row = -1
		scene.set_speed(1.0)
		var lr: Node = scene.level_runner
		lr.eval.extinct = true
		lr.finish()
		await _until(func() -> bool: return is_instance_valid(lr.report), 10.0)
		await _shot("%s_e_report" % id, 3.5)
		lr.exit_level()
		await _until(func() -> bool: return scene.level_runner == null)
		await create_timer(1.0).timeout
	var f := FileAccess.open("%s/texts.md" % dir, FileAccess.WRITE)
	f.store_string("# 关卡文字与引导全文\n\n" + "\n".join(texts))
	f.close()
	print("TOUR DONE")
	quit()
