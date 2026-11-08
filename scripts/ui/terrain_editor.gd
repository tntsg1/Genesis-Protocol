class_name TerrainEditor
extends Control
# The sandbox's terrain editor (DECISIONS 地形编辑器, Q278–Q282): G (or the
# dock's 地形编辑) opens it any time in the sandbox; the dish pauses, the
# brushes come up beside the species list, every stroke takes effect at once
# and can be undone (Ctrl+Z / Ctrl+Y). Brushes: ice walls (drag a line),
# zones (drag a circle: temperature, acid, light, vent, sulfide), lights
# (drag a circle), light from above and the mud's layers (click a depth),
# algae and shells (paint), the three bosses (click to place), the eraser.
# The long night and acid rain: switches with their numbers. 模板 starts the
# dish over from a planet (or a saved world); 保存 keeps this one.
# The model: SandboxWorld (host.sandbox_world). The words are a first draft.

const BRUSHES := [
	["wall", "冰墙", "按住拖一条冰墙：谁都过不去，也看不穿"],
	["zone", "环境区", "按住拖出一个圆：下面的滑条决定它的温度、酸度、光照、营养喷口和硫化物"],
	["light", "光源", "按住拖出一片光"],
	["band", "光照带", "点一个深度：光从上面照下来，到这里变暗"],
	["mud", "泥层", "点一个深度：氧气到这里为止，再往下是硫化氢"],
	["algae", "藻场", "按住刷出藻团"],
	["shells", "空壳", "按住刷出死去生命的空壳（分解者的食物）"],
	["net", "伪足网", "点一下放下有孔虫（它要氧气）"],
	["helio", "太阳虫", "点一下放一个它会埋伏的地方（最多三个，它会轮流换）"],
	["slime", "菌毯意识", "点一下放下黏菌：它朝周围六个点伸管道"],
	["erase", "橡皮擦", "点或拖：擦掉冰墙、环境区、光源、Boss、藻团和空壳"],
]
const ZONE_PRESETS := [
	["热泉", {temp = 30.0, acid = 0.05, light = 1.0, vent = 1.5, chem = 1.0}],
	["冷水", {temp = 0.0, acid = 0.0, light = 0.8, vent = 0.0, chem = 0.0}],
	["酸池", {temp = 19.0, acid = 0.8, light = 0.9, vent = 1.0, chem = 0.5}],
	["暗区", {temp = 12.0, acid = 0.03, light = 0.1, vent = 0.0, chem = 0.0}],
]
const ZONE_TINT := Color(0.55, 0.75, 0.95)

var host: Node2D
var model: SandboxWorld
var active := false
var brush := "zone"
var panel: GlassPanel
var params_box: VBoxContainer
var brush_pills := {}
var undo_pill: Widgets.Pill
var redo_pill: Widgets.Pill
var night_pill: Widgets.Pill
var rain_pill: Widgets.Pill
var oxygen_pill: Widgets.Pill
var picker: GlassPanel
var preview: Node2D
var _was_paused := false
var _from := Vector2.INF
var _now := Vector2.INF
var _painted: Array = []
var _last_paint := Vector2.INF
# Brush settings.
var zone := {temp = 25.0, acid = 0.05, light = 1.0, vent = 0.0, chem = 0.0}
var light_power := 0.5
var band_power := 0.6
var h2s := 1.0
var night := {day = 70.0, night = 45.0, cold = -20.0}
var rain := {dry = 70.0, wet = 35.0, level = 5.0}


func setup(h: Node2D) -> void:
	host = h
	model = host.sandbox_world
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	_build_picker()
	preview = Node2D.new()
	preview.z_index = 3
	preview.draw.connect(_draw_preview)
	preview.visible = false
	host.add_child(preview)


# --- the panel ------------------------------------------------------------------

func _place(p: Control, anchor: Vector2, offset: Vector2, w: float) -> void:
	p.anchor_left = anchor.x
	p.anchor_right = anchor.x
	p.anchor_top = anchor.y
	p.anchor_bottom = anchor.y
	p.custom_minimum_size.x = w
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH if anchor.x > 0.4 else Control.GROW_DIRECTION_END
	p.grow_vertical = Control.GROW_DIRECTION_BOTH if anchor.y > 0.4 else Control.GROW_DIRECTION_END
	p.offset_left = offset.x
	p.offset_top = offset.y
	p.offset_right = offset.x
	p.offset_bottom = offset.y


func _pill(text: String, tip: String, cb: Callable, h := 30) -> Widgets.Pill:
	var b := Widgets.Pill.new(text, 0, Ui.sans(600))
	b.custom_minimum_size = Vector2(b.label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 28, h)
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func _flow(parent: Control) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	f.custom_minimum_size.x = 316
	parent.add_child(f)
	return f


func _slider(parent: Control, label: String, lo: float, hi: float, step: float, value: float, fmt: String, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Ui.label(label, 12, Ui.INK_SOFT, Ui.sans(500))
	l.custom_minimum_size.x = 64
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(170, 20)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var v := Ui.label(fmt % value, 12, Ui.INK, Ui.mono("Medium"))
	v.custom_minimum_size.x = 60
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % x
		cb.call(x))


func _build_panel() -> void:
	panel = GlassPanel.new(Vector4(16, 10, 16, 12))
	add_child(panel)
	_place(panel, Vector2(0, 0), Vector2(340, 104), 348)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.body.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	head.add_child(Ui.caption("地形编辑", "TERRAIN"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	undo_pill = _pill("撤销", "Ctrl+Z", func() -> void: _undo(), 26)
	head.add_child(undo_pill)
	redo_pill = _pill("重做", "Ctrl+Y", func() -> void: _redo(), 26)
	head.add_child(redo_pill)
	head.add_child(_pill("完成  G", "回到培养皿，继续运行", func() -> void: close(), 26))
	var bf := _flow(v)
	for b: Array in BRUSHES:
		var key: String = b[0]
		var p := _pill(b[1], b[2], func() -> void: set_brush(key))
		bf.add_child(p)
		brush_pills[key] = p
	params_box = VBoxContainer.new()
	params_box.add_theme_constant_override("separation", 4)
	v.add_child(params_box)
	v.add_child(Ui.caption("水与周期", "WATER · CYCLES"))
	var ef := _flow(v)
	oxygen_pill = _pill("氧气", "水里有氧气：生产者放氧，厌氧的怕氧、好氧的靠氧", func() -> void:
		model.edit(func(m: Dictionary) -> void: m.oxygen = not m.oxygen)
		_sync())
	ef.add_child(oxygen_pill)
	night_pill = _pill("长夜", "周期性的长夜：全暗、水结冰", func() -> void:
		model.edit(func(m: Dictionary) -> void: m.night = {} if not (m.night as Dictionary).is_empty() else night.duplicate())
		_sync())
	ef.add_child(night_pill)
	rain_pill = _pill("酸雨", "周期性的酸雨：酸从水面往下渗", func() -> void:
		model.edit(func(m: Dictionary) -> void: m.rain = {} if not (m.rain as Dictionary).is_empty() else rain.duplicate())
		_sync())
	ef.add_child(rain_pill)
	_slider(v, "白天", 20, 200, 5, night.day, "%d 秒", func(x: float) -> void: _set_cycle("night", "day", x))
	_slider(v, "长夜", 10, 120, 5, night.night, "%d 秒", func(x: float) -> void: _set_cycle("night", "night", x))
	_slider(v, "夜里水温", -40, 5, 1, night.cold, "%d°C", func(x: float) -> void: _set_cycle("night", "cold", x))
	_slider(v, "雨的间隔", 20, 200, 5, rain.dry, "%d 秒", func(x: float) -> void: _set_cycle("rain", "dry", x))
	_slider(v, "雨下多久", 10, 90, 5, rain.wet, "%d 秒", func(x: float) -> void: _set_cycle("rain", "wet", x))
	_slider(v, "雨有多酸", 1, 10, 0.5, rain.level, "%.1f", func(x: float) -> void: _set_cycle("rain", "level", x))
	v.add_child(Ui.caption("加入原生物种", "ADD NATIVES"))
	var nf := _flow(v)
	for n: Array in SandboxWorld.NATIVES:
		var name: String = n[0]
		nf.add_child(_pill("+ " + name, n[1], func() -> void: model.add_native(name)))
	var foot := _flow(v)
	foot.add_child(_pill("换起点 / 读取…", "从一颗星球或保存过的世界重新开始（培养皿里的生命会清空）", func() -> void: show_picker(true)))
	foot.add_child(_pill("保存这个世界", "存进“我的世界”，以后从“读取”打开", func() -> void: _save()))
	panel.visible = false
	set_brush("zone")


func _set_cycle(which: String, key: String, x: float) -> void:
	var d: Dictionary = night if which == "night" else rain
	d[key] = x
	if not (model.map[which] as Dictionary).is_empty():
		model.edit(func(m: Dictionary) -> void: m[which] = d.duplicate())


func set_brush(key: String) -> void:
	brush = key
	for k: String in brush_pills:
		(brush_pills[k] as Widgets.Pill).active = k == key
	for c in params_box.get_children():
		c.queue_free()
	match key:
		"zone":
			var pf := _flow(params_box)
			for pr: Array in ZONE_PRESETS:
				var vals: Dictionary = pr[1]
				pf.add_child(_pill(pr[0], "预设", func() -> void:
					zone = vals.duplicate()
					set_brush("zone"), 26))
			_slider(params_box, "温度", -20, 45, 1, zone.temp, "%d°C", func(x: float) -> void: zone.temp = x)
			_slider(params_box, "酸度", 0, 1, 0.05, zone.acid, "%.2f", func(x: float) -> void: zone.acid = x)
			_slider(params_box, "光照", 0, 1.5, 0.05, zone.light, "×%.2f", func(x: float) -> void: zone.light = x)
			_slider(params_box, "营养喷口", 0, 3, 0.1, zone.vent, "%.1f", func(x: float) -> void: zone.vent = x)
			_slider(params_box, "硫化物", 0, 1, 0.05, zone.chem, "%.2f", func(x: float) -> void: zone.chem = x)
		"light":
			_slider(params_box, "亮度", 0.1, 1.0, 0.05, light_power, "%.2f", func(x: float) -> void: light_power = x)
		"band":
			_slider(params_box, "亮度", 0.1, 1.0, 0.05, band_power, "%.2f", func(x: float) -> void: band_power = x)
			params_box.add_child(_pill("去掉光照带", "", func() -> void: model.edit(func(m: Dictionary) -> void: m.band = []), 26))
		"mud":
			_slider(params_box, "硫化氢", 0.1, 1.0, 0.05, h2s, "%.2f", func(x: float) -> void: h2s = x)
			params_box.add_child(_pill("去掉泥层", "", func() -> void: model.edit(func(m: Dictionary) -> void: m.mud = {}), 26))
		"helio", "net", "slime":
			params_box.add_child(_pill("去掉它", "", func() -> void: model.edit(func(m: Dictionary) -> void: m[key] = {}), 26))
	var tip := ""
	for b: Array in BRUSHES:
		if b[0] == key:
			tip = b[2]
	var l := Ui.label(tip, 12, Ui.INK_SOFT, Ui.sans(500))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 316
	params_box.add_child(l)


func _sync() -> void:
	if undo_pill == null:
		return
	undo_pill.modulate.a = 1.0 if model.can_undo() else 0.4
	redo_pill.modulate.a = 1.0 if model.can_redo() else 0.4
	oxygen_pill.active = bool(model.map.get("oxygen", false))
	night_pill.active = not (model.map.get("night", {}) as Dictionary).is_empty()
	rain_pill.active = not (model.map.get("rain", {}) as Dictionary).is_empty()
	preview.queue_redraw()


# --- open / close ----------------------------------------------------------------

func toggle() -> void:
	if active:
		close()
	else:
		open()


func open() -> void:
	if host.level_runner != null:
		return
	active = true
	_was_paused = host.paused
	host.paused = true
	host.set_mode("")
	panel.visible = true
	panel.appear(0.0)
	preview.visible = true
	_sync()
	host.hud_root.notify("地形编辑：培养皿已暂停", Ui.ACCENT)


func close() -> void:
	if not active:
		return
	active = false
	host.paused = _was_paused
	panel.visible = false
	preview.visible = false
	_from = Vector2.INF


func _undo() -> void:
	model.do_undo()
	_sync()


func _redo() -> void:
	model.do_redo()
	_sync()


func _save() -> void:
	var name := "我的世界 %s" % Time.get_datetime_string_from_system().replace("T", " ").replace(":", "-")
	if model.save_as(name):
		host.hud_root.notify("已保存：" + name, Ui.GOOD)
	else:
		host.hud_root.notify("保存失败", Ui.WARN)


# --- the start: a template or a saved world --------------------------------------

func _build_picker() -> void:
	picker = GlassPanel.new(Vector4(22, 16, 22, 18))
	add_child(picker)
	_place(picker, Vector2(0.5, 0.5), Vector2(0, 0), 560)
	picker.visible = false


func show_picker(from_editor := false) -> void:
	for c in picker.body.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	picker.body.add_child(v)
	v.add_child(Ui.caption("选择起点", "START FROM"))
	var note := Ui.label("从哪颗星球开始？之后随时按 G 编辑地形。" + ("\n换起点会清空培养皿里的生命。" if from_editor else ""), 14, Ui.INK_SOFT, Ui.sans(500))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 516
	v.add_child(note)
	for t: Array in SandboxWorld.TEMPLATES:
		var key: String = t[0]
		var b := Widgets.Pill.new("%s　·　%s" % [t[1], t[2]], 0, Ui.sans(600))
		b.custom_minimum_size = Vector2(516, 40)
		b.active = key == "europa" and not from_editor
		b.pressed.connect(func() -> void:
			picker.visible = false
			if key == "europa" and not from_editor:
				return # (already there)
			model.load_map(SandboxWorld.template(key))
			_sync()
			host.hud_root.notify("起点：" + str(t[1]), Ui.ACCENT))
		v.add_child(b)
	var saved := SandboxWorld.saved_list()
	if not saved.is_empty():
		v.add_child(Ui.caption("我的世界", "SAVED"))
		for name: String in saved:
			var b := Widgets.Pill.new(name, 0, Ui.sans(500))
			b.custom_minimum_size = Vector2(516, 34)
			b.pressed.connect(func() -> void:
				picker.visible = false
				model.load_saved(name)
				_sync()
				host.hud_root.notify("读取：" + name, Ui.ACCENT))
			v.add_child(b)
	var close_b := Widgets.Pill.new("取消  Esc", 0, Ui.sans(500))
	close_b.custom_minimum_size = Vector2(120, 34)
	close_b.pressed.connect(func() -> void: picker.visible = false)
	v.add_child(close_b)
	picker.visible = true
	picker.appear(0.0)


# --- the brushes on the dish -------------------------------------------------------

# The showcase hands the dish's input here while the editor is open; true:
# taken (left button strokes, the editor's keys). Right / middle drags and
# the wheel still move the view.
func handle(event: InputEvent, at: Vector2) -> bool:
	if picker.visible:
		if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			picker.visible = false
			return true
		return false
	if not active:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			close()
			return true
		if k.ctrl_pressed and k.keycode == KEY_Z:
			_redo() if k.shift_pressed else _undo()
			return true
		if k.ctrl_pressed and k.keycode == KEY_Y:
			_redo()
			return true
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _from.is_finite():
			_from = Vector2.INF
			preview.queue_redraw()
			return true
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			_from = at
			_now = at
			_painted = []
			_last_paint = Vector2.INF
			if brush in ["algae", "shells", "erase"]:
				_stroke(at)
		elif _from.is_finite():
			_finish(at)
			_from = Vector2.INF
		preview.queue_redraw()
		return true
	if event is InputEventMouseMotion:
		_now = at
		if _from.is_finite() and brush in ["algae", "shells", "erase"]:
			_stroke(at)
		preview.queue_redraw()
		return _from.is_finite()
	return false


# Painting and erasing as the hand moves (one undo step per stroke).
func _stroke(at: Vector2) -> void:
	if _last_paint.is_finite() and at.distance_to(_last_paint) < 50.0:
		return
	_last_paint = at
	match brush:
		"algae", "shells":
			_painted.append(model.paint_food(at, 60.0, brush))
		"erase":
			host.sim.remove_food(at, 80.0, true, true)
			_painted.append([at, 80.0, "erase"])


func _finish(at: Vector2) -> void:
	var a := _from
	var d := a.distance_to(at)
	match brush:
		"wall":
			if d > 20.0:
				model.edit(func(m: Dictionary) -> void: (m.walls as Array).append([a, at]))
		"zone":
			var z := {key = "z%d" % Time.get_ticks_msec(), name = "自定义区", en = "CUSTOM ZONE", center = a, radius = maxf(80.0, d),
				temp = zone.temp, acid = zone.acid, radiation = 0.05, light = zone.light, vent = zone.vent, chem = zone.chem,
				tint = Color(1.0, 0.6, 0.3) if zone.temp > 22.0 else (Color(0.55, 0.82, 1.0) if zone.temp < 6.0 else (Color(0.78, 0.86, 0.3) if zone.acid > 0.4 else ZONE_TINT))}
			model.edit(func(m: Dictionary) -> void: (m.zones as Array).append(z))
		"light":
			model.edit(func(m: Dictionary) -> void: (m.lights as Array).append([a, maxf(80.0, d), light_power]))
		"band":
			model.edit(func(m: Dictionary) -> void: m.band = [maxf(60.0, at.y - 700.0), at.y, band_power])
		"mud":
			model.edit(func(m: Dictionary) -> void: m.mud = {o2_full = at.y - 250.0, o2_zero = at.y + 150.0, h2s_from = at.y + 150.0, h2s_full = at.y + 800.0, h2s = h2s, relax = 0.15, harm = 1.4, safe = 0.15})
		"algae", "shells":
			var stroke := _painted.duplicate()
			var key: String = brush
			var each := 20.0 if key == "algae" else 25.0
			var change := func(m: Dictionary) -> void:
				for p: Array in stroke:
					(m[key] as Array).append([p[0], p[1], 6, each])
			model.edit(change, stroke)
		"net":
			model.edit(func(m: Dictionary) -> void: m.net = {center = at})
		"slime":
			model.edit(func(m: Dictionary) -> void: m.slime = {center = at})
		"helio":
			model.edit(func(m: Dictionary) -> void:
				var spots: Array = (m.helio as Dictionary).get("spots", []).duplicate()
				spots.append(at)
				if spots.size() > 3:
					spots.pop_front()
				m.helio = {spots = spots})
		"erase":
			var pts := _painted.duplicate()
			model.edit(func(m: Dictionary) -> void:
				for p: Array in pts:
					_erase_at(m, p[0])
				_erase_at(m, at))
	_sync()


# What the eraser at `p` takes out of the map: the nearest wall, zone, light
# or boss within reach, and painted food records there.
func _erase_at(m: Dictionary, p: Vector2) -> void:
	m.walls = (m.walls as Array).filter(func(w: Array) -> bool: return Geometry2D.get_closest_point_to_segment(p, w[0], w[1]).distance_to(p) > 30.0)
	m.zones = (m.zones as Array).filter(func(z: Dictionary) -> bool: return (z.center as Vector2).distance_to(p) > maxf(60.0, float(z.radius) * 0.35))
	m.lights = (m.lights as Array).filter(func(l: Array) -> bool: return (l[0] as Vector2).distance_to(p) > maxf(60.0, float(l[1]) * 0.35))
	m.algae = (m.algae as Array).filter(func(a: Array) -> bool: return (a[0] as Vector2).distance_to(p) > 80.0)
	m.shells = (m.shells as Array).filter(func(a: Array) -> bool: return (a[0] as Vector2).distance_to(p) > 80.0)
	if not (m.net as Dictionary).is_empty() and (m.net.center as Vector2).distance_to(p) < 120.0:
		m.net = {}
	if not (m.slime as Dictionary).is_empty() and (m.slime.center as Vector2).distance_to(p) < 120.0:
		m.slime = {}
	if not (m.helio as Dictionary).is_empty():
		var spots: Array = (m.helio.spots as Array).filter(func(s: Vector2) -> bool: return s.distance_to(p) > 120.0)
		m.helio = {spots = spots} if not spots.is_empty() else {}


# --- the editor's drawing over the dish ----------------------------------------------

func _draw_preview() -> void:
	var zoom: float = host.cam.zoom.x
	var px := 1.0 / zoom
	var m: Dictionary = model.map
	var font := Ui.sans(600)
	for z: Dictionary in m.get("zones", []):
		var c: Vector2 = z.center
		var col: Color = z.get("tint", ZONE_TINT)
		preview.draw_arc(c, float(z.radius), 0, TAU, 72, Color(col, 0.85), 2.0 * px, true)
		preview.draw_string(font, c + Vector2(-60, -float(z.radius) - 8.0 * px) , "%d°C 酸%.2f" % [int(z.temp), float(z.acid)], HORIZONTAL_ALIGNMENT_LEFT, -1, int(13.0 * px), Color(col.darkened(0.3), 0.95))
	for l: Array in m.get("lights", []):
		preview.draw_arc(l[0], float(l[1]), 0, TAU, 64, Color(1.0, 0.92, 0.5, 0.7), 1.5 * px, true)
		preview.draw_circle(l[0], 6.0 * px, Color(1.0, 0.92, 0.5, 0.9))
	var band: Array = m.get("band", [])
	if not band.is_empty():
		preview.draw_line(Vector2(80, band[1]), Vector2(2120, band[1]), Color(1.0, 0.9, 0.5, 0.8), 2.0 * px, true)
		preview.draw_string(font, Vector2(120, float(band[1]) - 8.0 * px), "光照到此为止", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13.0 * px), Color(0.6, 0.5, 0.2))
	var mud: Dictionary = m.get("mud", {})
	if not mud.is_empty():
		preview.draw_line(Vector2(80, mud.o2_zero), Vector2(2120, mud.o2_zero), Color(0.5, 0.36, 0.22, 0.85), 2.0 * px, true)
		preview.draw_string(font, Vector2(120, float(mud.o2_zero) - 8.0 * px), "泥层：往下没有氧，硫化氢渐浓", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13.0 * px), Color(0.45, 0.32, 0.2))
	for key: String in ["net", "slime"]:
		var b: Dictionary = m.get(key, {})
		if not b.is_empty():
			preview.draw_arc(b.center, 90.0, 0, TAU, 48, Color(0.9, 0.7, 0.2, 0.9), 2.0 * px, true)
	for s: Vector2 in (m.get("helio", {}) as Dictionary).get("spots", []):
		preview.draw_arc(s, 60.0, 0, TAU, 40, Color(0.98, 0.8, 0.5, 0.9), 2.0 * px, true)
	# The stroke in progress / the brush under the pointer.
	if not active:
		return
	var at := _now
	if not at.is_finite():
		return
	match brush:
		"wall":
			if _from.is_finite():
				preview.draw_line(_from, at, Color(0.84, 0.94, 0.99, 0.9), 22.0, true)
		"zone", "light":
			if _from.is_finite():
				preview.draw_arc(_from, maxf(80.0, _from.distance_to(at)), 0, TAU, 72, Color(Ui.ACCENT, 0.9), 2.5 * px, true)
		"band", "mud":
			preview.draw_line(Vector2(80, at.y), Vector2(2120, at.y), Color(Ui.ACCENT, 0.7), 2.0 * px, true)
		"algae", "shells":
			preview.draw_arc(at, 60.0, 0, TAU, 40, Color(Ui.ACCENT, 0.7), 1.5 * px, true)
		"erase":
			preview.draw_arc(at, 80.0, 0, TAU, 40, Color(Ui.WARN, 0.8), 2.0 * px, true)
		_:
			preview.draw_arc(at, 50.0, 0, TAU, 40, Color(Ui.ACCENT, 0.7), 1.5 * px, true)
