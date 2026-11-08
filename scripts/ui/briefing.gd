class_name Briefing
extends CanvasLayer
# A level's briefing (2026-11-07, the user: "引导可以减少但还得有——开始编辑
# 基因之前，先让玩家了解本关目标和特点"). Past chapter 1 the step-by-step guide
# no longer comes by itself; instead, before the designer opens, a card over
# the dish: page 1 what the level asks (the story, the goal, the challenge
# star, the budget star, the time), page 2 what is special here (the level's
# threats, one by one). 开始设计 (Enter) opens the designer, 跳过 (Esc) too.
# Not on a retry. The designer's 本关要点 shows the same, while designing
# (Briefing.fill). The words are the level's own.

signal finished

var level: Dictionary
var page := 0
var card: GlassPanel
var body: VBoxContainer
var back_b: Widgets.Pill
var next_b: Widgets.Pill
var dots: Label
var veil: ColorRect
var _done := false


static func split_threat(t: String) -> Array:
	var s := t.strip_edges()
	var nl := s.find("\n")
	return [s, ""] if nl < 0 else [s.substr(0, nl), s.substr(nl + 1)]


# The level's goal and stars, as rows in `box` (shared with the designer).
static func fill_goal(box: Control, l: Dictionary, width: float) -> void:
	var rows := [["目标", str(l.goal.get("text", ""))]]
	if l.has("challenge") and l.challenge.has("text"):
		rows.append(["挑战星", str(l.challenge.text)])
	if l.has("star_shots"):
		rows.append(["第三颗星", "投放病毒不超过 %d 次" % int(l.star_shots)])
	elif l.has("star_blocks"):
		rows.append(["第三颗星", "身体不超过 %d 块" % int(l.star_blocks)])
	elif l.has("star_budget"):
		rows.append(["第三颗星", "基因预算不超过 %d 点（满额 %d 点）" % [int(l.star_budget), int(l.get("budget", 0))]])
	if l.has("time_limit"):
		rows.append(["时间", "%d 分钟" % roundi(float(l.time_limit) / 60.0)])
	for r: Array in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		box.add_child(h)
		var k := Ui.label(r[0], 14, Ui.ACCENT, Ui.sans(700))
		k.custom_minimum_size.x = 72
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(k)
		var v := Ui.label(r[1], 15, Ui.INK, Ui.sans(600))
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size.x = width - 86.0
		h.add_child(v)


# The level's features (its threats): a title and a few lines each.
static func fill_features(box: Control, l: Dictionary, width: float, small := false) -> void:
	for t: String in l.get("threats", []):
		var tb := split_threat(t)
		var title := Ui.label("·  " + str(tb[0]), 14 if small else 16, Ui.INK, Ui.sans(700))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size.x = width
		box.add_child(title)
		if str(tb[1]) != "":
			var b := Ui.label(str(tb[1]), 12 if small else 14, Ui.INK_SOFT, Ui.sans(500))
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size.x = width
			box.add_child(b)


func _init(l: Dictionary) -> void:
	level = l
	layer = 45


func _ready() -> void:
	veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.94, 0.97, 0.99, 0.35)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	card = GlassPanel.new(Vector4(34, 26, 34, 24))
	add_child(card)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(880, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.body.add_child(v)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.custom_minimum_size = Vector2(812, 420)
	v.add_child(body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	var skip := Widgets.Pill.new("跳过  Esc", 0, Ui.sans(500))
	skip.custom_minimum_size = Vector2(120, 40)
	skip.pressed.connect(_end)
	foot.add_child(skip)
	dots = Ui.label("", 13, Ui.INK_SOFT, Ui.mono("Medium"))
	dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(dots)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	back_b = Widgets.Pill.new("上一页", 0, Ui.sans(500))
	back_b.custom_minimum_size = Vector2(110, 40)
	back_b.pressed.connect(func() -> void: _show(page - 1))
	foot.add_child(back_b)
	next_b = Widgets.Pill.new("", 0, Ui.sans(600))
	next_b.custom_minimum_size = Vector2(170, 40)
	next_b.active = true
	next_b.pressed.connect(func() -> void:
		if page >= _pages() - 1:
			_end()
		else:
			_show(page + 1))
	foot.add_child(next_b)
	_show(0)
	card.appear(0.0)


func _pages() -> int:
	return 2 if not (level.get("threats", []) as Array).is_empty() else 1


func _show(p: int) -> void:
	page = clampi(p, 0, _pages() - 1)
	for c in body.get_children():
		c.queue_free()
	if page == 0:
		body.add_child(Ui.caption("%s · %s" % [str(level.id), str(level.get("en", ""))], "BRIEFING"))
		body.add_child(Ui.label(str(level.get("name", "")), Ui.SIZE_TITLE + 6, Ui.INK, Ui.sans(700)))
		if level.has("teach"):
			body.add_child(Ui.label(str(level.teach), 16, Ui.ACCENT, Ui.sans(600)))
		var brief := Ui.label(str(level.get("brief", "")), 15, Ui.INK_SOFT, Ui.sans(500))
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.custom_minimum_size.x = 812
		body.add_child(brief)
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		body.add_child(gap)
		fill_goal(body, level, 812.0)
	else:
		body.add_child(Ui.caption("这关的特点：设计时想着它们", "WHAT TO KNOW"))
		fill_features(body, level, 812.0)
	back_b.visible = page > 0
	next_b.text = "开始设计  Enter" if page >= _pages() - 1 else "下一页：这关的特点  ▸"
	dots.text = "%d / %d" % [page + 1, _pages()]


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		_end()
	elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		next_b.pressed.emit()
	elif k.keycode == KEY_LEFT and page > 0:
		_show(page - 1)
	elif k.keycode == KEY_RIGHT and page < _pages() - 1:
		_show(page + 1)
	else:
		return
	get_viewport().set_input_as_handled()


func _end() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()
