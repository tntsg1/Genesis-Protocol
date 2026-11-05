extends SceneTree
# The event log with long lines (the cause of what happened): they wrap on the
# glass instead of running off it. proofs/log_wrap.png.
# Run: tools/run_test.sh tests/log_wrap_aw.gd

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _run() -> void:
	await create_timer(2.0).timeout
	var hud: Node = scene.hud_root
	hud._event("第一批子体破壳，亲体留下空壳死去", Color(0.3, 0.7, 0.5), Vector2(1100, 1100))
	hud._event("巨噬者从没甲的外缘咬掉了一大口：没甲的块一口就被咬残，鞭毛不划水", Color(0.86, 0.3, 0.4), Vector2(1100, 1100))
	hud._event("水熊方案 #16 突变：8 号染色体耐温基因 3.00→2.63 等 2 处（同期另有 3 次突变）", Color(1.0, 0.72, 0.25), Vector2(1000, 1000), true, {id = 1, lineage = 16, species = 0})
	hud._event("一个群体被喷口守卫吞下：外缘的好甲不到 3 块，嚼不动的才会被吐出来", Color(0.86, 0.3, 0.4))
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/log_wrap.png"))
	quit()
