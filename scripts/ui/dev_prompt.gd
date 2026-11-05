extends CanvasLayer
# The passcode box for developer mode (scripts/dev_mode.gd): ` (~) brings it
# up over a soft white veil; digits land as filled dots, Backspace takes one
# back, Enter checks it (111). A wrong code shakes the box and clears; the
# right one fills the dots with the accent, flashes and closes (`unlocked`).
# Esc or a click outside cancels.

signal unlocked
signal closed

var host: Node2D
var panel: GlassPanel
var dim: ColorRect
var dots: Control
var note: Label
var typed := ""
var shake := 0.0
var ok_t := -1.0
var _x0 := 0.0


func _ready() -> void:
	layer = 62
	dim = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.93, 0.96, 0.98, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(dim)
	Ui.tween(dim).tween_property(dim, "color:a", 0.5, Ui.T_MID)
	panel = GlassPanel.new(Vector4(28, 22, 28, 22))
	for side in ["left", "right", "top", "bottom"]:
		panel.set("anchor_" + side, 0.5)
	panel.offset_left = -170
	panel.offset_right = 170
	panel.offset_top = -110
	panel.offset_bottom = 110
	_x0 = panel.offset_left
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.body.add_child(v)
	v.add_child(Ui.caption("开发者模式", "DEVELOPER"))
	v.add_child(Ui.label("输入口令", 15, Ui.INK, Ui.sans(600)))
	dots = Control.new()
	dots.custom_minimum_size = Vector2(0, 40)
	dots.draw.connect(_draw_dots)
	v.add_child(dots)
	note = Ui.label("数字键输入 · Enter 确认 · Esc 取消", 11, Ui.INK_FAINT, Ui.sans())
	v.add_child(note)
	panel.appear(0.03)
	Audio.sfx("holo_boot", -14.0, 1.3)


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	if ok_t >= 0.0:
		return
	var code := k.keycode
	if code == KEY_ESCAPE or code == KEY_QUOTELEFT:
		_close()
	elif code == KEY_BACKSPACE:
		typed = typed.substr(0, maxi(typed.length() - 1, 0))
	elif code == KEY_ENTER or code == KEY_KP_ENTER:
		_check()
	else:
		var digit := -1
		if code >= KEY_0 and code <= KEY_9:
			digit = code - KEY_0
		elif code >= KEY_KP_0 and code <= KEY_KP_9:
			digit = code - KEY_KP_0
		if digit >= 0 and typed.length() < 6:
			typed += str(digit)
			Audio.sfx("holo_tick", -12.0, 1.0 + 0.08 * typed.length())
			if typed.length() == DevMode.CODE.length() and typed == DevMode.CODE:
				_check()
	dots.queue_redraw()


func _check() -> void:
	if typed == DevMode.CODE:
		ok_t = 0.0
		note.text = "已解锁 · 开发者存档已启用"
		note.add_theme_color_override("font_color", Ui.ACCENT)
		Audio.sfx("holo_on", -8.0, 1.3)
	else:
		shake = 1.0
		typed = ""
		note.text = "口令不对，再试一次"
		note.add_theme_color_override("font_color", Ui.WARN.darkened(0.25))
		Audio.sfx("ui_click", -6.0, 0.6)
	dots.queue_redraw()


func _process(delta: float) -> void:
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 2.8)
		var off := sin(shake * 40.0) * 12.0 * shake
		panel.offset_left = _x0 + off
		panel.offset_right = -_x0 + off
	if ok_t >= 0.0:
		ok_t += delta
		dots.queue_redraw()
		if ok_t > 0.45:
			unlocked.emit()
			_close()


func _draw_dots() -> void:
	var n := DevMode.CODE.length()
	var c := dots.size * 0.5
	var gap := 34.0
	for i in n:
		var p := c + Vector2((i - (n - 1) * 0.5) * gap, 0)
		var filled := i < typed.length()
		if ok_t >= 0.0:
			var a := clampf(1.0 - ok_t * 2.0, 0.0, 1.0)
			dots.draw_circle(p, 9.0 + 10.0 * ok_t, Color(Ui.ACCENT, 0.25 * a))
			dots.draw_circle(p, 9.0, Ui.ACCENT)
		elif filled:
			dots.draw_circle(p, 9.0, Ui.INK)
		else:
			dots.draw_arc(p, 9.0, 0.0, TAU, 32, Color(Ui.INK, 0.45), 1.5, true)


func _close() -> void:
	set_process_input(false)
	var t := Ui.tween(dim)
	t.tween_property(dim, "color:a", 0.0, Ui.T_FAST)
	panel.disappear()
	t.tween_callback(func() -> void:
		closed.emit()
		queue_free())
