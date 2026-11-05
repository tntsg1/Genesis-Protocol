extends VBoxContainer
# The rules page's simple mode (scripts/personas.gd): a column of personality
# cards and one 保守 <-> 激进 slider. The designer owns the deck; this only
# says what was picked.

signal picked(id: String)
signal bold_changed(value: float, done: bool)

var cards := {} # id -> PersonaCard
var slider: BoldSlider
var summary: Label
var list: VBoxContainer
var note: Label


func _init() -> void:
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Ui.caption("性格预设", "PERSONALITY"))
	var sub := Ui.label("选择一套行为预设，细胞就会按照对应的规则行动。\n右侧会显示具体的规则卡，你也可以在高级编辑中修改。", 12, Ui.INK_SOFT, Ui.sans())
	add_child(sub)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(list)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	add_child(gap)
	add_child(Ui.caption("性子", "TEMPER"))
	add_child(Ui.label("调整细胞对食物和繁殖的积极程度。", 12, Ui.INK_SOFT, Ui.sans()))
	slider = BoldSlider.new()
	slider.changed.connect(func(v: float, done: bool) -> void: bold_changed.emit(v, done))
	add_child(slider)
	summary = Ui.label("", 12, Ui.INK, Ui.sans(500))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.custom_minimum_size.x = 340
	add_child(summary)
	note = Ui.label("", 11, Ui.INK_FAINT, Ui.sans())
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 340
	add_child(note)


# The personalities on offer (Personas.available) and the one picked
# ("" = the deck was edited by hand: none lights up).
func set_list(items: Array, sel: String) -> void:
	for c in list.get_children():
		c.queue_free()
	cards.clear()
	for p: Dictionary in items:
		var c := PersonaCard.new(p)
		var id: String = p.id
		c.pressed.connect(func() -> void: picked.emit(id))
		list.add_child(c)
		cards[id] = c
	set_selected(sel)


func set_selected(id: String) -> void:
	for k: String in cards:
		cards[k].active = k == id
		cards[k].queue_redraw()


# One personality: name, English tag, what it does, all on a glass plate.
class PersonaCard extends Button:
	var spec: Dictionary
	var active := false
	var _hover := 0.0

	func _init(p: Dictionary) -> void:
		spec = p
		flat = true
		focus_mode = Control.FOCUS_NONE
		# As tall as its words: name, the short first line, then the rest.
		var h := Ui.sans().get_multiline_string_size(_body(), HORIZONTAL_ALIGNMENT_LEFT, 340 - 32, 12).y
		custom_minimum_size = Vector2(340, maxf(70.0, 38.0 + h + 12.0))
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _fade(1.0))
		mouse_exited.connect(func() -> void: _fade(0.0))

	func _fade(to: float) -> void:
		var t := Ui.tween(self)
		t.tween_method(func(v: float) -> void:
			_hover = v
			queue_redraw(), _hover, to, Ui.T_FAST)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.anti_aliasing = true
		sb.bg_color = Color(Ui.ACCENT, 0.1) if active else Color(1, 1, 1, 0.45 + 0.25 * _hover)
		sb.border_color = Ui.ACCENT if active else Color(Ui.LINE_STRONG, 0.3 + 0.3 * _hover)
		sb.set_border_width_all(2 if active else 1)
		draw_style_box(sb, r.grow(-1.0))
		if active:
			draw_rect(Rect2(1, 12, 3, size.y - 24), Ui.ACCENT)
			var c := Vector2(size.x - 24, 22)
			draw_circle(c, 9.0, Ui.ACCENT)
			draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3), c + Vector2(4, -3)]), Color.WHITE, 1.6, true)
		var f := Ui.sans(700)
		draw_string(f, Vector2(16, 26), spec.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Ui.ACCENT if active else Ui.INK)
		var nw := f.get_string_size(spec.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(Ui.mono("Medium"), Vector2(24 + nw, 25), spec.en, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK_FAINT)
		var y := 47.0
		if spec.has("tag"):
			draw_string(Ui.sans(600), Vector2(16, y), spec.tag, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 12, Ui.ACCENT if active else Ui.INK)
			y += Ui.sans().get_height(12) + 2.0
		draw_multiline_string(Ui.sans(), Vector2(16, y), spec.line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 12, -1, Ui.INK_SOFT)

	func _body() -> String:
		return (str(spec.tag) + "\n" if spec.has("tag") else "") + str(spec.line)


# 保守 (left) … 激进 (right), with a soft centre notch: the personality as built.
class BoldSlider extends Control:
	signal changed(value: float, done: bool)
	var value := 0.5
	var _drag := false

	func _init() -> void:
		custom_minimum_size = Vector2(340, 46)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "保守：留足余粮、早早避险\n激进：一有能量就分裂、敢冒险"

	func _x_of(v: float) -> float:
		return 14.0 + (size.x - 28.0) * v

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
			_set_from(event.position.x, not event.pressed)
			accept_event()
		elif event is InputEventMouseMotion and _drag:
			_set_from(event.position.x, false)

	func _set_from(px: float, done: bool) -> void:
		var v := snappedf(clampf((px - 14.0) / (size.x - 28.0), 0.0, 1.0), 0.05)
		# A little pull toward the middle (the personality as designed).
		if absf(v - 0.5) < 0.04:
			v = 0.5
		if v != value or done:
			value = v
			queue_redraw()
			changed.emit(v, done)

	func set_value(v: float) -> void:
		value = v
		queue_redraw()

	func _draw() -> void:
		var y := 16.0
		var a := _x_of(0.0)
		var b := _x_of(1.0)
		draw_line(Vector2(a, y), Vector2(b, y), Color(Ui.LINE, 0.7), 2.0, true)
		var m := _x_of(0.5)
		draw_line(Vector2(m, y), Vector2(_x_of(value), y), Ui.ACCENT, 3.0, true)
		for k in 5:
			var x := _x_of(k / 4.0)
			draw_line(Vector2(x, y - (6.0 if k == 2 else 3.0)), Vector2(x, y + (6.0 if k == 2 else 3.0)), Color(Ui.INK_FAINT, 0.7), 1.0)
		var kx := _x_of(value)
		draw_circle(Vector2(kx, y), 8.0 + (1.5 if _drag else 0.0), Color.WHITE)
		draw_arc(Vector2(kx, y), 8.0, 0, TAU, 28, Ui.ACCENT, 1.8, true)
		var f := Ui.sans(600)
		draw_string(f, Vector2(a - 4.0, y + 26.0), "保守", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK if value < 0.45 else Ui.INK_SOFT)
		draw_string(f, Vector2(m - 12.0, y + 26.0), "适中", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.INK_FAINT)
		draw_string(f, Vector2(b - 22.0, y + 26.0), "激进", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK if value > 0.55 else Ui.INK_SOFT)
