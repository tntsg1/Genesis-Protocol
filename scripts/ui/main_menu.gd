extends Control
# Main menu over the live dish (DECISIONS Q10). The dish keeps living behind
# a soft light wash on the left; the title writes itself in letter by letter;
# items answer the mouse and the keyboard (Up/Down, Enter): 战役 opens the
# campaign page, 沙盒 hands over to the camera fly-in; no loading anywhere.
# Seventh round: hovering an item previews it in the dish behind (the camera
# drifts there: 战役 the ice water, 沙盒 a scan field across the dish, 设置 the
# stage's scales light up, 退出 the lamp dims); the dish on the right answers
# the pointer as in play; choosing locks the item on with a burst
# (scripts/ui/menu_fx.gd), then the menu dissolves along a scan front and
# the camera plunges in, one take, no cut.

# Tests (-s) read and write their own file: never the player's settings.
var SETTINGS_PATH := Keys.path()

var host: Node2D
var wash: ColorRect
var column: VBoxContainer
var title_chars: Array[Label] = []
var rule: ColorRect
var items: Array = []
var focus_index := 0
var live_label: Label
var settings: GlassPanel
var shown := false
var _live_timer := 0.0
const MenuFx := preload("res://scripts/ui/menu_fx.gd")
var fx: Control
var dissolve_mat: ShaderMaterial
var wash_mat: ShaderMaterial
var _leaving := false


func setup(showcase: Node2D) -> void:
	host = showcase
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_load_settings()

	# A light wash on the left so the type reads over the living dish.
	wash = ColorRect.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float amount = 1.0;
uniform float front = -1.0;
void fragment() {
	float x = UV.x;
	float a = (1.0 - smoothstep(0.18, 0.58, x)) * 0.82 + 0.06;
	a += (1.0 - smoothstep(0.0, 0.2, UV.y)) * 0.08 + smoothstep(0.85, 1.0, UV.y) * 0.1;
	if (front > -0.5) {
		a *= smoothstep(front - 0.02, front + 0.12, x);
	}
	COLOR = vec4(0.975, 0.99, 1.0, a * amount);
}
"""
	var wm := ShaderMaterial.new()
	wm.shader = sh
	wash.material = wm
	wash_mat = wm
	add_child(wash)

	column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	column.anchor_top = 0.5
	column.anchor_bottom = 0.5
	column.offset_left = 128
	column.offset_top = -330
	column.offset_right = 760
	column.offset_bottom = 330
	add_child(column)

	column.add_child(Ui.label("EUROPA STATION  ·  SAMPLE EUR-01  ·  木卫二冰下海洋", 11, Ui.INK_FAINT, Ui.mono("Medium")))
	_gap(18)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 6)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	for ch in "创生协议":
		var l := Ui.label(ch, 84, Ui.INK, Ui.sans(800))
		title.add_child(l)
		title_chars.append(l)
	_gap(6)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 14)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(sub)
	rule = ColorRect.new()
	rule.color = Ui.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.add_child(rule)
	var en := Ui.label("G E N E S I S    P R O T O C O L", 15, Ui.ACCENT, Ui.mono("SemiBold"))
	sub.add_child(en)
	_gap(16)
	column.add_child(Ui.label("设计一种生命，然后看它自己活下去。", 19, Ui.INK_SOFT, Ui.sans(500)))
	_gap(52)

	var specs := [
		["战役", "CAMPAIGN", "木卫二 · 第一章：单细胞篇", true],
		["沙盒", "SANDBOX", "自由的培养皿：观察、设计与干预", true],
		["设置", "SETTINGS", "画面、帧率与按键", true],
		["退出", "QUIT", "", true],
	]
	for k in specs.size():
		var it := MenuItem.new(k + 1, specs[k][0], specs[k][1], specs[k][2], specs[k][3])
		var idx := k
		it.chosen.connect(func(at: Vector2) -> void: _activate(idx, at))
		it.hovered.connect(func() -> void: _set_focus(idx))
		column.add_child(it)
		items.append(it)

	# Bottom: build tag and a live readout of the dish behind.
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.anchor_right = 1.0
	foot.offset_left = 128
	foot.offset_right = -48
	foot.offset_top = -64
	foot.offset_bottom = -36
	add_child(foot)
	foot.add_child(Ui.label("v0.1  ·  BUILD 2026.10.27", 11, Ui.INK_FAINT, Ui.mono()))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(sp)
	var dot := Widgets.Chip.new(Ui.GOOD, 10)
	foot.add_child(dot)
	live_label = Ui.label("", 12, Ui.INK_SOFT, Ui.mono("Medium"))
	foot.add_child(live_label)

	_build_settings()
	# The menu's text and items dissolve through one material.
	dissolve_mat = ShaderMaterial.new()
	dissolve_mat.shader = preload("res://shaders/menu_dissolve.gdshader")
	column.material = dissolve_mat
	_adopt(column)
	column.child_entered_tree.connect(_adopt)
	fx = MenuFx.new()
	fx.host = host
	# Over everything else in the interface (added after the other pages).
	get_parent().add_child.call_deferred(fx)


func _adopt(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasItem and (c as CanvasItem).material == null:
			(c as CanvasItem).use_parent_material = true
		_adopt(c)


func _gap(h: float) -> void:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(g)


# --- entrance / exit -----------------------------------------------------------

func enter() -> void:
	Audio.music("menu")
	visible = true
	shown = true
	_leaving = false
	dissolve_mat.set_shader_parameter("front", -1.0)
	wash_mat.set_shader_parameter("front", -1.0)
	modulate.a = 1.0
	wash.modulate.a = 0.0
	Ui.tween(wash).tween_property(wash, "modulate:a", 1.0, Ui.T_SLOW)
	column.position.x = column.offset_left
	for k in column.get_child_count():
		var c := column.get_child(k) as Control
		c.modulate.a = 0.0
	# Title letters rise in one by one; the rule draws out; then the rest.
	var d := 0.15
	for l in title_chars:
		var t := Ui.tween(l)
		t.tween_interval(d)
		t.tween_property(l, "modulate:a", 1.0, Ui.T_SLOW)
		l.pivot_offset = l.size * 0.5
		l.scale = Vector2(0.92, 0.92)
		var t2 := Ui.tween(l)
		t2.tween_interval(d)
		t2.tween_property(l, "scale", Vector2.ONE, Ui.T_SLOW)
		d += 0.09
	rule.custom_minimum_size.x = 0.0
	var tr := Ui.tween(rule)
	tr.tween_interval(0.5)
	tr.tween_property(rule, "custom_minimum_size:x", 56.0, Ui.T_SLOW)
	var order := 0
	for k in column.get_child_count():
		var c := column.get_child(k) as Control
		if c is HBoxContainer and c.get_child_count() > 0 and c.get_child(0) is Label and title_chars.has(c.get_child(0) as Label):
			c.modulate.a = 1.0
			continue
		var t := Ui.tween(c)
		t.tween_interval(0.35 + order * 0.06)
		t.tween_property(c, "modulate:a", 1.0, Ui.T_MID)
		order += 1
	_set_focus(0)
	host.menu_preview = -1 # previews follow the hand (or the arrow keys)


# The menu goes along a scan front sweeping left to right: the wash and
# every line of type break up into blocks behind a bright edge, shards peel
# off it (MenuFx), the footer fades.
func leave() -> void:
	shown = false
	_leaving = true
	host.menu_preview = -1
	if settings.visible:
		_settings_open = false
		if _proj:
			_proj.kill()
		fx.proj_a = 0.0
		fx.proj_k = -1.0
		settings.set_wipe(Vector2(1, 0), 9.0)
		settings.disappear()
	Audio.sfx("holo_boot", -12.0, 1.15)
	var t := create_tween()
	t.tween_method(func(v: float) -> void:
		dissolve_mat.set_shader_parameter("front", v)
		wash_mat.set_shader_parameter("front", v)
		fx.dissolve_at(v), -0.12, 1.15, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(live_label.get_parent(), "modulate:a", 0.0, 0.3)
	t.tween_callback(func() -> void:
		fx.dissolve_at(-1.0)
		visible = false
		_leaving = false
		live_label.get_parent().modulate.a = 1.0
		dissolve_mat.set_shader_parameter("front", -1.0)
		wash_mat.set_shader_parameter("front", -1.0))


# --- items ---------------------------------------------------------------------

func _set_focus(i: int) -> void:
	if i != focus_index and shown:
		Audio.sfx("holo_tick", -14.0, 1.0 + 0.05 * i)
	focus_index = i
	for k in items.size():
		items[k].focused = k == i
	# The dish behind previews the item.
	if shown:
		host.menu_preview = i
		if fx:
			fx.wake()


func _activate(i: int, at := Vector2.INF) -> void:
	if not shown or _leaving:
		return
	# The chosen item locks on: beam, rings, streak, shards.
	var it: Control = items[i]
	var r := it.get_global_rect()
	fx.lock(r, at if at.is_finite() else Vector2(r.position.x + 60.0, r.get_center().y))
	it.lock()
	match i:
		0:
			_leaving = true
			get_tree().create_timer(0.16).timeout.connect(func() -> void:
				_leaving = false
				host.open_campaign())
		1:
			_leaving = true
			get_tree().create_timer(0.16).timeout.connect(func() -> void:
				_leaving = false
				host.start_experiment())
		2: _toggle_settings()
		3:
			shown = false
			fx.fade_out(0.6)
			Audio.music("")
			get_tree().create_timer(0.65).timeout.connect(func() -> void: get_tree().quit())


# Is the pointer over the live dish on the right (not the menu column, not
# the settings panel)? The dish answers it there as in play.
func dish_hand(p: Vector2) -> bool:
	if not shown or not visible or _leaving:
		return false
	if p.x < get_viewport_rect().size.x * 0.4:
		return false
	return not (settings.visible and settings.get_global_rect().grow(8.0).has_point(p))


func _unhandled_input(event: InputEvent) -> void:
	if not shown or not visible:
		return
	# A click on the dish: a ripple, as in play.
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and host.pointer and host.pointer.shown:
		host.pointer.pressed()
		host.pointer.click(mb.position)
		Audio.sfx("bubble", -8.0, randf_range(0.9, 1.1))
		get_viewport().set_input_as_handled()
		return
	if capturing != "" and event is InputEventKey and event.pressed and not event.echo:
		_capture((event as InputEventKey).keycode)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_DOWN or key == KEY_UP:
			var step := 1 if key == KEY_DOWN else -1
			var i := focus_index
			for n in items.size():
				i = posmod(i + step, items.size())
				if items[i].enabled:
					break
			_set_focus(i)
			get_viewport().set_input_as_handled()
		elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			if items[focus_index].enabled:
				items[focus_index].flash()
				_activate(focus_index)
			get_viewport().set_input_as_handled()
		elif key == KEY_ESCAPE and settings.visible:
			_toggle_settings()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	# The hand on the dish: whatever was previewed lets go.
	if shown and host.pointer and host.pointer.shown and host.menu_preview != -1:
		host.menu_preview = -1
	_live_timer -= delta
	if _live_timer <= 0.0:
		_live_timer = 0.5
		var st: Dictionary = host.sim.get_stats()
		live_label.text = "培养皿实时  ·  %d 个生命  ·  %d 条谱系" % [st.count, st.lineages]


# --- settings --------------------------------------------------------------------

var _cfg := {"fps": 120, "vsync": true}


func _build_settings() -> void:
	settings = GlassPanel.new(Vector4(22, 16, 22, 18))
	settings.anchor_top = 0.5
	settings.anchor_bottom = 0.5
	settings.offset_left = 640
	settings.offset_right = 1300
	settings.offset_top = -330
	settings.offset_bottom = 380
	settings.visible = false
	add_child(settings)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	settings.body.add_child(v)
	v.add_child(Ui.caption("设置", "SETTINGS"))
	v.add_child(Ui.label("帧率上限", 14, Ui.INK, Ui.sans(600)))
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 8)
	v.add_child(fps_row)
	var fps_pills := []
	for spec in [["60", 60], ["120", 120], ["144", 144], ["不限", 0]]:
		var b := Widgets.Pill.new(spec[0], 64)
		var val: int = spec[1]
		fps_pills.append([b, val])
		b.pressed.connect(func() -> void:
			_cfg.fps = val
			_apply()
			for pr in fps_pills:
				pr[0].active = pr[1] == _cfg.fps)
		b.active = val == _cfg.fps
		fps_row.add_child(b)
	v.add_child(Ui.label("垂直同步", 14, Ui.INK, Ui.sans(600)))
	var vs_row := HBoxContainer.new()
	vs_row.add_theme_constant_override("separation", 8)
	v.add_child(vs_row)
	var vs_pills := []
	for spec in [["开", true], ["关", false]]:
		var b := Widgets.Pill.new(spec[0], 64, Ui.sans(600))
		var val: bool = spec[1]
		vs_pills.append([b, val])
		b.pressed.connect(func() -> void:
			_cfg.vsync = val
			_apply()
			for pr in vs_pills:
				pr[0].active = pr[1] == _cfg.vsync)
		b.active = val == _cfg.vsync
		vs_row.add_child(b)
	v.add_child(Ui.label("关闭垂直同步可在高刷新率显示器上突破 60 FPS。", 11, Ui.INK_FAINT, Ui.sans()))
	# Night mode (scripts/night_mode.gd).
	v.add_child(Ui.label("黑夜模式", 14, Ui.INK, Ui.sans(600)))
	var nm_row := HBoxContainer.new()
	nm_row.add_theme_constant_override("separation", 8)
	v.add_child(nm_row)
	var nm_pills := []
	for spec in [["自动", "auto"], ["始终开", "on"], ["始终关", "off"]]:
		var b := Widgets.Pill.new(spec[0], 84, Ui.sans(600))
		var val: String = spec[1]
		nm_pills.append([b, val])
		b.pressed.connect(func() -> void:
			NightMode.set_setting(val)
			for pr in nm_pills:
				pr[0].active = pr[1] == NightMode.setting)
		b.active = val == NightMode.setting
		nm_row.add_child(b)
	v.add_child(Ui.label("自动：第六章海底关卡自动变黑，其他地方保持明亮。按 %s 随时切换。" % Keys.name_of(Keys.code("night")), 11, Ui.INK_FAINT, Ui.sans()))
	# Music and sound effect volume.
	for which in ["music", "sfx"]:
		v.add_child(Ui.label("音乐" if which == "music" else "音效", 14, Ui.INK, Ui.sans(600)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var pills := []
		var cur: float = Audio.get_instance().music_vol if which == "music" else Audio.get_instance().sfx_vol
		for spec in [["关", 0.0], ["低", 0.35], ["中", 0.7], ["高", 1.0]]:
			var b := Widgets.Pill.new(spec[0], 64, Ui.sans(600))
			var val: float = spec[1]
			pills.append([b, val])
			var w: String = which
			b.pressed.connect(func() -> void:
				var me := Audio.get_instance()
				Audio.set_volumes(val if w == "music" else me.music_vol, val if w == "sfx" else me.sfx_vol)
				for pr in pills:
					pr[0].active = is_equal_approx(pr[1], val))
			b.active = is_equal_approx(val, cur) or (val == 0.7 and not [0.0, 0.35, 0.7, 1.0].any(func(x: float) -> bool: return is_equal_approx(x, cur)))
			row.add_child(b)
	# Keys: click one, press the new key (Esc cancels); a key already in use
	# swaps with it. Camera and menu keys stay fixed.
	var kh := HBoxContainer.new()
	kh.add_child(Ui.label("按键", 14, Ui.INK, Ui.sans(600)))
	var ks := Control.new()
	ks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kh.add_child(ks)
	var reset := Widgets.Pill.new("恢复默认", 90, Ui.sans(500))
	reset.pressed.connect(func() -> void:
		Keys.reset()
		_refresh_keys()
		key_status.text = "已恢复默认按键")
	kh.add_child(reset)
	v.add_child(kh)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for a: Array in Keys.ACTIONS:
		var l := Ui.label(a[1], 13, Ui.INK_SOFT, Ui.sans(500))
		l.custom_minimum_size.x = 120
		grid.add_child(l)
		var b := Widgets.Pill.new("", 150, Ui.mono("Medium"))
		var id: String = a[0]
		b.pressed.connect(func() -> void:
			capturing = id
			_refresh_keys())
		grid.add_child(b)
		key_pills[id] = b
	key_status = Ui.label("点一个按键再按新键；已被占用的键会互换；Esc 取消。镜头与菜单键（WASD、Q/E、方向键、Esc、F1、回车）固定。", 11, Ui.INK_FAINT, Ui.sans())
	key_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	key_status.custom_minimum_size.x = 600
	v.add_child(key_status)
	_refresh_keys()


var key_pills := {}
var key_status: Label
var capturing := ""


func _refresh_keys() -> void:
	for id: String in key_pills:
		var b: Widgets.Pill = key_pills[id]
		b.text = "按下新键…" if id == capturing else Keys.name_of(Keys.code(id))
		b.active = id == capturing
		b.queue_redraw()
	if host and host.hud_root:
		host.hud_root.refresh_key_labels()


func _capture(key: int) -> void:
	if key == KEY_ESCAPE:
		capturing = ""
		key_status.text = "已取消"
	elif Keys.FIXED.has(key):
		key_status.text = "%s 固定用于镜头或菜单，换一个键" % Keys.name_of(key)
		return
	else:
		var swapped := Keys.bind(capturing, key)
		key_status.text = ("%s 改为 %s" % [Keys.label(capturing), Keys.name_of(key)]) + (("；%s 换到了原来的键" % Keys.label(swapped)) if swapped != "" else "")
		capturing = ""
	_refresh_keys()


# 设置 projects its panel (eighth round): a beam from the item to the
# panel's place, a bar standing up there and sweeping the panel in left to
# right (MenuFx draws the beam and bar, the panel's own wipe follows the
# bar); closing, the bar sweeps it back into the beam.
var _proj: Tween
var _settings_open := false


func _toggle_settings() -> void:
	var item: Control = items[2]
	var ir := item.get_global_rect()
	fx.project(Vector2(ir.position.x + 300.0, ir.get_center().y), settings.get_global_rect())
	if _proj:
		_proj.kill()
	var view := get_viewport_rect().size.x
	var follow := func(v: float) -> void:
		fx.proj_k = v
		settings.set_wipe(Vector2(1, 0), fx.proj_x() / view if v > MenuFx.BEAM else -1.0)
	_proj = create_tween()
	if _settings_open:
		_settings_open = false
		Audio.sfx("holo_off", -10.0)
		var from: float = maxf(fx.proj_k, MenuFx.BEAM)
		_proj.tween_method(follow, from, MenuFx.BEAM, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		_proj.tween_method(follow, MenuFx.BEAM, 0.0, 0.12)
		_proj.tween_callback(func() -> void:
			settings.visible = false
			settings.set_wipe(Vector2(1, 0), 9.0)
			fx.proj_a = 0.0
			fx.proj_k = -1.0)
	else:
		_settings_open = true
		settings.visible = true
		settings.set_wipe(Vector2(1, 0), -1.0)
		settings.appear(MenuFx.BEAM * 0.6)
		Audio.sfx("holo_banner", -12.0, 1.3)
		var from: float = clampf(fx.proj_k, 0.0, 1.0)
		_proj.tween_method(follow, from, MenuFx.BEAM, 0.16 * (1.0 - from / MenuFx.BEAM) + 0.01).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_proj.tween_method(follow, maxf(from, MenuFx.BEAM), 1.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_proj.tween_callback(func() -> void: settings.set_wipe(Vector2(1, 0), 9.0))
		_proj.tween_property(fx, "proj_a", 0.0, 0.3)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		_cfg.fps = int(cf.get_value("display", "fps", 120))
		_cfg.vsync = bool(cf.get_value("display", "vsync", true))
	_apply(false)


func _apply(save := true) -> void:
	Engine.max_fps = _cfg.fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _cfg.vsync else DisplayServer.VSYNC_DISABLED)
	if save:
		var cf := ConfigFile.new()
		cf.set_value("display", "fps", _cfg.fps)
		cf.set_value("display", "vsync", _cfg.vsync)
		cf.save(SETTINGS_PATH)


# One menu line: index, title, English tag, hint. Hover / keyboard focus
# slides an accent bar in, nudges the text right and lights a soft band.
class MenuItem extends Control:
	signal chosen(at: Vector2)
	signal hovered
	var index := 1
	var title := ""
	var tag := ""
	var hint := ""
	var enabled := true
	var focused := false
	var _f := 0.0
	var _flash := 0.0
	var _lock := 0.0 # 1 when chosen: the title decodes, the bar flares

	func _init(i: int, t: String, g: String, h: String, e: bool) -> void:
		index = i
		title = t
		tag = g
		hint = h
		enabled = e
		custom_minimum_size = Vector2(520, 74)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if e else Control.CURSOR_ARROW
		mouse_entered.connect(func() -> void:
			if enabled:
				hovered.emit())

	func _gui_input(event: InputEvent) -> void:
		if enabled and event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			flash()
			chosen.emit(get_global_mouse_position())

	func flash() -> void:
		_flash = 1.0

	func lock() -> void:
		_lock = 1.0
		_flash = 1.0

	func _process(delta: float) -> void:
		var goal := 1.0 if focused and enabled else 0.0
		var changed := absf(_f - goal) > 0.001 or _flash > 0.0 or _lock > 0.0
		_f = lerpf(_f, goal, 1.0 - exp(-delta / Ui.T_FAST * 2.2))
		_flash = maxf(0.0, _flash - delta * 3.0)
		_lock = maxf(0.0, _lock - delta * 2.2)
		if changed:
			queue_redraw()

	func _draw() -> void:
		var h := size.y
		# Soft highlight band fading to the right.
		var band := 440.0
		for k in 22:
			var x0 := band * k / 22.0
			var a := (1.0 - float(k) / 22.0) * 0.16 * _f + _flash * 0.12 * (1.0 - float(k) / 22.0)
			draw_rect(Rect2(x0, 6, band / 22.0 + 1.0, h - 12), Color(Ui.ACCENT, a))
		# Accent bar grows in from the left edge.
		draw_rect(Rect2(0, 10, 3.0, (h - 20) * _f), Ui.ACCENT)
		if _lock > 0.0:
			# The bar flares (bright enough to bloom) and brackets close in.
			draw_rect(Rect2(-1, 6, 5.0, h - 12), Color(1.4, 2.4, 2.7, _lock))
			var bw := 440.0 * (0.6 + 0.4 * (1.0 - _lock))
			for sy in [6.0, h - 6.0]:
				draw_line(Vector2(bw - 18.0, sy), Vector2(bw, sy), Color(Ui.ACCENT, _lock), 1.4)
			draw_line(Vector2(bw, 6.0), Vector2(bw, h - 6.0), Color(Ui.ACCENT, _lock * 0.8), 1.4)
		var dx := 22.0 + 12.0 * _f
		var ink := Ui.INK if enabled else Ui.INK_FAINT
		var mono := Ui.mono("Medium")
		var sans := Ui.sans(650 if _f > 0.5 else 550)
		draw_string(mono, Vector2(dx, h * 0.5 - 1), "%02d" % index, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.ACCENT.lerp(Ui.INK_FAINT, 1.0 - _f) if enabled else Ui.INK_FAINT)
		# Locked on: the title decodes from code glyphs, left to right.
		var shown_title := title
		if _lock > 0.45:
			var settled := int((1.0 - (_lock - 0.45) / 0.55) * title.length())
			shown_title = ""
			for ci in title.length():
				shown_title += title[ci] if ci < settled else Holo.GLYPHS[randi() % Holo.GLYPHS.length()]
		draw_string(sans, Vector2(dx + 34, h * 0.5 + 4), shown_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink.lerp(Ui.ACCENT, _lock))
		var tw := sans.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(mono, Vector2(dx + 48 + tw, h * 0.5 + 1), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ui.INK_FAINT, 0.9))
		if hint != "":
			var ha := 0.35 + 0.65 * _f if enabled else 0.6
			draw_string(Ui.sans(), Vector2(dx + 34, h * 0.5 + 25), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Ui.INK_SOFT, ha))
