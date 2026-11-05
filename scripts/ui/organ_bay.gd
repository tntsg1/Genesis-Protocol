extends VBoxContainer
# The organ bay on the designer's genome page (DECISIONS 第十四轮): the
# level's organ slots, and every organ as a chip below them. Click a chip to
# install it in a free slot (one of a pair replaces the other), click an
# installed slot's × to take it out. Organs that open later are grey and say
# where; the ones new in this level say 新.

signal changed

var organs: Array = [] # installed organ ids, in slot order
var slots := 2
var level_id := ""
var readonly := false
var slot_row: HBoxContainer
var chips := {} # organ id -> chip
var count_label: Label
var toast: Callable # (text) -> void


func setup(n_slots: int, lid: String, toast_fn: Callable) -> void:
	slots = n_slots
	level_id = lid
	toast = toast_fn
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	head.add_child(Ui.caption("器官", "ORGANS"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	count_label = Ui.label("", 11, Ui.ACCENT, Ui.mono("Medium"))
	head.add_child(count_label)
	slot_row = HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 8)
	add_child(slot_row)
	for k in slots:
		var s := Slot.new(self, k)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_row.add_child(s)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	add_child(flow)
	var later := []
	for o: Dictionary in Organs.LIST:
		var c := Chip.new(o, self)
		chips[o.id] = c
		if Organs.open_in(o, level_id):
			flow.add_child(c)
		else:
			later.append(c)
	for c: Control in later:
		flow.add_child(c)
	_sync()


func set_organs(ids: Array) -> void:
	organs = ids.filter(func(id: String) -> bool: return Organs.open_in(Organs.by_id(id), level_id)).slice(0, slots)
	_sync()


func install(id: String) -> void:
	if readonly or organs.has(id):
		return
	var o := Organs.by_id(id)
	if not Organs.open_in(o, level_id):
		toast.call("%s：第 %s 关解锁" % [o.name, o.opens])
		return
	# One of a pair (armour, motor) replaces the other.
	if o.has("pair"):
		for k in organs.size():
			var old := Organs.by_id(organs[k])
			if old.get("pair", "") == o.pair:
				organs[k] = id
				_done("%s 换成了 %s（%s和%s只能二选一）" % [old.name, o.name, old.name, o.name])
				return
	if organs.size() >= slots:
		toast.call("器官槽满了：先点已装器官右上角的 × 取下一个")
		Audio.sfx("ui_deny")
		return
	organs.append(id)
	_done("装上了 %s" % o.name)


func remove(k: int) -> void:
	if readonly or k >= organs.size():
		return
	var o := Organs.by_id(organs[k])
	organs.remove_at(k)
	_done("取下了 %s" % o.name)


func _done(msg: String) -> void:
	Audio.sfx("ui_confirm")
	toast.call(msg)
	_sync()
	changed.emit()


func _sync() -> void:
	if count_label == null:
		return
	count_label.text = "槽位 %d / %d" % [organs.size(), slots]
	for s: Control in slot_row.get_children():
		s.queue_redraw()
	for id: String in chips:
		chips[id].active = organs.has(id)
		chips[id].queue_redraw()


# One slot: the installed organ (name, its first line, ×) or an empty frame.
class Slot extends Control:
	var bay: Control
	var k := 0
	var _hover := 0.0

	func _init(b: Control, index: int) -> void:
		bay = b
		k = index
		custom_minimum_size = Vector2(0, 48)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(delta: float) -> void:
		var h := 1.0 if get_global_rect().has_point(get_global_mouse_position()) else 0.0
		if absf(_hover - h) > 0.01:
			_hover = lerpf(_hover, h, minf(1.0, delta / Ui.T_FAST))
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if k < bay.organs.size():
				if Rect2(size.x - 26, 4, 22, 22).has_point(e.position):
					bay.remove(k)
			else:
				bay.toast.call("点下面的器官装进这个槽")
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-1)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.anti_aliasing = true
		if k < bay.organs.size():
			var o := Organs.by_id(bay.organs[k])
			sb.bg_color = Color(Ui.ACCENT, 0.1 + 0.06 * _hover)
			sb.border_color = Ui.ACCENT
			sb.set_border_width_all(1)
			draw_style_box(sb, r)
			draw_string(Ui.sans(700), Vector2(12, 22), o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ui.INK)
			draw_string(Ui.mono("Medium"), Vector2(12, 39), o.en, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 9, Ui.ACCENT)
			if not bay.readonly:
				var c := Vector2(size.x - 15, 15)
				var a := 0.35 + 0.65 * _hover
				draw_line(c - Vector2(4, 4), c + Vector2(4, 4), Color(Ui.ALERT, a), 1.4, true)
				draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), Color(Ui.ALERT, a), 1.4, true)
			tooltip_text = o.desc
		else:
			sb.bg_color = Color(1, 1, 1, 0.25 + 0.15 * _hover)
			sb.border_color = Color(Ui.LINE_STRONG, 0.5)
			sb.set_border_width_all(1)
			draw_style_box(sb, r)
			var t := "空槽"
			var f := Ui.sans(500)
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(f, Vector2((size.x - w) * 0.5, 29), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK_FAINT)
			tooltip_text = ""


# An organ in the list: click to install. Grey when it opens later; 新 when
# it opens in this level; filled while installed.
class Chip extends Widgets.Pill:
	var o: Dictionary
	var bay: Control

	func _init(organ: Dictionary, b: Control) -> void:
		super(organ.name, 0, Ui.sans(500))
		o = organ
		bay = b
		custom_minimum_size.x = label_font.get_string_size(o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 30
		var open := Organs.open_in(o, bay.level_id)
		modulate.a = 1.0 if open else 0.42
		tooltip_text = o.desc if open else "第 %s 关解锁\n%s" % [o.opens, o.desc]
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if open else Control.CURSOR_FORBIDDEN
		pressed.connect(func() -> void: bay.install(o.id))

	func _draw() -> void:
		super()
		if bay.level_id != "" and o.opens == bay.level_id:
			var c := Vector2(size.x - 4, 3)
			draw_circle(c, 9.0, Ui.ACCENT)
			draw_string(Ui.sans(700), c + Vector2(-5.5, 4.5), "新", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
