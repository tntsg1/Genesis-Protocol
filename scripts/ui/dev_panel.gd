extends CanvasLayer
# The developer panel (scripts/dev_mode.gd): opens when ` turns the mode on
# and closes when ` turns it off; Esc hides it, Shift+` shows it again. A glass column on the left, every developer action as a
# button, switch or speed selector, grouped by where they apply; groups that
# do not apply right now (no level running, the designer closed...) are
# hidden, so what shows always works. Switches light while on. The header
# says which save is in use. Also draws the timings overlay (帧 / 模拟 /
# 细胞) when that switch is on.

signal closed

const W := 372.0

var host: Node2D
var panel: GlassPanel
var rows: Array = [] # [Control, when: Callable] — shown while when() holds
var toggles: Array = [] # [Widgets.Pill, get: Callable]
var segs: Array = [] # [[Widgets.Pill, value], get: Callable]
var status: Label
var _t := 0.0
var _closing := false


func _ready() -> void:
	layer = 61
	panel = GlassPanel.new(Vector4(20, 16, 20, 16))
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20.0
	panel.offset_right = 20.0 + W
	panel.offset_top = 20.0
	panel.offset_bottom = -20.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.body.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	_build(v)
	panel.appear(0.0)
	Audio.sfx("holo_boot", -14.0, 1.15)
	_sync()


# --- where things apply --------------------------------------------------------

func _in_dish() -> bool:
	return not host.in_menu and host.designer == null and not _campaign_open()


func _in_level() -> bool:
	return host.level_runner != null and host.level_runner.phase == "run" and host.designer == null


func _campaign_open() -> bool:
	return host.campaign != null and host.campaign.visible


func _in_designer() -> bool:
	return host.designer != null


# --- building --------------------------------------------------------------------

func _build(v: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_child(Ui.caption("开发者模式", "DEVELOPER"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(Ui.label("` 关闭", 11, Ui.INK_FAINT, Ui.mono("Medium")))
	v.add_child(head)
	status = Ui.label("", 11, Ui.INK_SOFT, Ui.sans())
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = W - 40.0
	v.add_child(status)

	_section(v, "时间", "TIME", _in_dish)
	_seg(v, [["×¼", 0.25], ["×1", 1.0], ["×2", 2.0], ["×4", 4.0], ["×8", 8.0], ["×16", 16.0]],
		func() -> float: return 0.0 if host.paused else host.speed,
		func(s: float) -> void: host.set_speed(s), _in_dish)
	_buttons(v, [
		["暂停 / 继续", func() -> void: host.paused = not host.paused],
		["单步", func() -> void:
			host.paused = true
			host.step_once()],
		["快进 10 秒", func() -> void: host.advance(10.0)],
	], _in_dish)

	_section(v, "培养皿", "DISH", _in_dish)
	_buttons(v, [
		["生物质点加满", func() -> void: host.iv.points = host.iv.MAX_POINTS],
		["视野中心投营养", func() -> void:
			host.sim.add_nutrient(host.cam.position, 45.0, 150.0)
			host.fx.nutrient_splash(host.cam.position)],
	], _in_dish)
	_toggle(v, "干预免费、无冷却", func() -> bool: return DevMode.free_iv,
		func(on: bool) -> void: DevMode.free_iv = on, _in_dish)
	_buttons(v, [
		["在视野中心再投放上次的物种", func() -> void: host._do_release(host.cam.position)],
	], func() -> bool: return _in_dish() and not host.release_params.is_empty() and host.capsule.is_empty())

	_section(v, "当前关卡", "LEVEL", _in_level)
	_buttons(v, [
		["立即通关 ★★★", func() -> void: _finish_level([true, true, true])],
		["立即失败", func() -> void: _finish_level([false, false, false])],
	], _in_level)
	_buttons(v, [
		["剩余时间跳到 10 秒", func() -> void:
			var lr: Node = host.level_runner
			lr.t0 = host.sim.get_time() - (float(lr.level.time_limit) - 10.0)],
	], _in_level)

	_section(v, "战役进度（开发者存档）", "CAMPAIGN", func() -> bool: return true)
	_toggle(v, "解锁全部关卡", func() -> bool: return DevMode.unlock_all,
		func(on: bool) -> void:
			DevMode.unlock_all = on
			_refresh_campaign(), func() -> bool: return true)
	_toggle(v, "跳过关卡引导", func() -> bool: return DevMode.no_tutorial,
		func(on: bool) -> void: DevMode.no_tutorial = on, func() -> bool: return true)
	_buttons(v, [
		["研究点 +100", func() -> void:
			CampaignSave.add_research(100)
			_refresh_campaign()],
		["清空进度", func() -> void:
			CampaignSave.data = {levels = {}, research = 0, seen_tutorial = {}}
			CampaignSave.save()
			_refresh_campaign()],
		["重新复制真实进度", func() -> void:
			DevMode.copy_real()
			_refresh_campaign()],
	], func() -> bool: return true)

	_section(v, "生命设计器", "DESIGNER", func() -> bool: return true)
	_toggle(v, "基因、规则零件全部开放", func() -> bool: return DevMode.all_genes,
		func(on: bool) -> void:
			DevMode.all_genes = on
			_refresh_designer(), func() -> bool: return true)
	_toggle(v, "基因预算不限", func() -> bool: return DevMode.free_budget,
		func(on: bool) -> void:
			DevMode.free_budget = on
			_refresh_designer(), func() -> bool: return true)

	_section(v, "显示", "VIEW", func() -> bool: return true)
	_toggle(v, "帧率与模拟耗时", func() -> bool: return DevMode.perf,
		func(on: bool) -> void: DevMode.perf = on, func() -> bool: return true)

	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	v.add_child(gap)
	_buttons(v, [["关闭开发者模式（回到真实存档）", func() -> void:
		DevMode.set_active(false)
		_refresh_campaign()
		_refresh_designer()
		close()]], func() -> bool: return true)


func _section(v: VBoxContainer, zh: String, en: String, when: Callable) -> void:
	var box := VBoxContainer.new()
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	box.add_child(gap)
	box.add_child(Ui.caption(zh, en))
	v.add_child(box)
	rows.append([box, when])


func _buttons(v: VBoxContainer, items: Array, when: Callable) -> void:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 6)
	for it in items:
		var b := Widgets.Pill.new(it[0], 0, Ui.sans(600))
		b.custom_minimum_size = Vector2(0, 32)
		var f: Callable = it[1]
		b.pressed.connect(func() -> void:
			f.call()
			_sync())
		h.add_child(b)
	v.add_child(h)
	rows.append([h, when])


func _toggle(v: VBoxContainer, text: String, get_: Callable, set_: Callable, when: Callable) -> void:
	var b := Widgets.Pill.new("", 0, Ui.sans(600))
	b.custom_minimum_size = Vector2(0, 32)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.set_meta("text", text)
	b.pressed.connect(func() -> void:
		set_.call(not get_.call())
		_sync())
	v.add_child(b)
	toggles.append([b, get_])
	rows.append([b, when])


func _seg(v: VBoxContainer, opts: Array, get_: Callable, set_: Callable, when: Callable) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var pills := []
	for o in opts:
		var b := Widgets.Pill.new(o[0], 46)
		var val: float = o[1]
		b.pressed.connect(func() -> void:
			set_.call(val)
			_sync())
		h.add_child(b)
		pills.append([b, val])
	v.add_child(h)
	segs.append([pills, get_])
	rows.append([h, when])


# --- actions ------------------------------------------------------------------------

func _finish_level(stars: Array) -> void:
	DevMode.force_stars(stars)
	host.level_runner.finish()
	close()


# The campaign page shows the developer save as it is now.
func _refresh_campaign() -> void:
	if _campaign_open():
		var c: Control = host.campaign
		c.research_label.text = "研究点  %d" % CampaignSave.research()
		c._select(c.selected, true)


func _refresh_designer() -> void:
	var d: Control = host.designer
	if d == null:
		return
	d._enforce_rules()
	d._update_pieces()
	d._refresh()


# --- state ------------------------------------------------------------------------

func _sync() -> void:
	status.text = "开发者存档 dev_campaign.json：这里的关卡进度、研究点不会写进你的真实存档。" if DevMode.active \
		else "开发者模式已关闭。"
	for r in rows:
		(r[0] as Control).visible = (r[1] as Callable).call()
	for t in toggles:
		var on: bool = (t[1] as Callable).call()
		var b: Widgets.Pill = t[0]
		b.active = on
		b.text = str(b.get_meta("text")) + ("　开" if on else "　关")
	for s in segs:
		var now: float = (s[1] as Callable).call()
		for pv in s[0]:
			(pv[0] as Widgets.Pill).active = is_equal_approx(float(pv[1]), now)


func _process(delta: float) -> void:
	_t += delta
	if _t > 0.25:
		_t = 0.0
		if not _closing:
			_sync()


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE and not _closing:
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	if _closing:
		return
	_closing = true
	panel.disappear()
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		closed.emit()
		queue_free())
