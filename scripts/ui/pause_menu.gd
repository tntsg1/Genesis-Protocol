extends CanvasLayer
# The pause menu over the dish (Esc when nothing else is open): 继续 /
# 设置 / 返回主菜单. The simulation holds while it shows and goes back to
# how it was on 继续. 设置 borrows the main menu's settings panel; leaving a
# level from here goes to the main menu, not the level page.

signal closed

var host: Node2D
var panel: GlassPanel
var dim: ColorRect
var buttons: Array = []
var was_paused := false
var settings_open := false
var _settings_parent: Node


func _ready() -> void:
	layer = 26
	was_paused = host.paused
	host.paused = true
	dim = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.93, 0.96, 0.98, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# A click outside closes the settings (or the menu itself).
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if settings_open:
				_close_settings()
			else:
				_resume())
	add_child(dim)
	Ui.tween(dim).tween_property(dim, "color:a", 0.45, Ui.T_MID)
	panel = GlassPanel.new(Vector4(28, 22, 28, 24))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -170
	panel.offset_right = 170
	panel.offset_top = -150
	panel.offset_bottom = 150
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.body.add_child(v)
	v.add_child(Ui.caption("已暂停", "PAUSED"))
	var specs := [["继续", "Esc", _resume], ["设置", "", _settings], ["返回主菜单", "", _to_menu]]
	# In a level: start over (the same design back on the bench), or back to
	# the level page (review round 4: only "main menu" was too far).
	var lr: Node = host.level_runner
	if lr and lr.phase == "run":
		specs.insert(1, ["重新开始本关", "", _restart])
		specs.insert(3, ["返回关卡页", "", _to_levels])
		panel.offset_top = -200
		panel.offset_bottom = 200
	elif lr and lr.phase == "design":
		# The designer was put away before the release: back into it, or out.
		specs.insert(1, ["回到生命设计器", Keys.name_of(Keys.code("designer")), _to_designer])
		specs.insert(3, ["返回关卡页", "", _to_levels])
		panel.offset_top = -200
		panel.offset_bottom = 200
	for spec in specs:
		var b := Widgets.Pill.new(spec[0] + ("    " + spec[1] if spec[1] != "" else ""), 0, Ui.sans(600))
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(spec[2])
		v.add_child(b)
		buttons.append(b)
	buttons[0].active = true
	panel.appear(0.05)
	Audio.sfx("holo_boot", -14.0, 1.2)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).keycode
	var menu: Control = host.menu
	# Rebinding a key in the borrowed settings panel.
	if settings_open and menu.capturing != "":
		menu._capture(key)
		get_viewport().set_input_as_handled()
		return
	if key == KEY_ESCAPE:
		if settings_open:
			_close_settings()
		else:
			_resume()
		get_viewport().set_input_as_handled()


func _resume() -> void:
	if settings_open:
		_close_settings()
	host.paused = was_paused
	_close()


func _settings() -> void:
	if settings_open:
		_close_settings()
		return
	# The main menu's panel, brought over here while it is open.
	var s: GlassPanel = host.menu.settings
	_settings_parent = s.get_parent()
	s.reparent(self, false)
	s.visible = true
	s.set_wipe(Vector2(1, 0), 9.0) # fully swept in (-1 would hide it)
	s.appear(0.0)
	settings_open = true
	panel.visible = false


func _close_settings() -> void:
	var s: GlassPanel = host.menu.settings
	host.menu.capturing = ""
	s.visible = false
	s.reparent(_settings_parent, false)
	settings_open = false
	panel.visible = true
	panel.appear(0.0)


func _restart() -> void:
	_close()
	host.paused = false
	host.level_runner._on_report_action("retry", {})


func _to_designer() -> void:
	_close()
	host.paused = false
	host.open_designer()


func _to_levels() -> void:
	_close()
	host.paused = false
	host.level_runner.exit_level()


func _to_menu() -> void:
	if settings_open:
		_close_settings()
	_close()
	if host.level_runner:
		host.exit_to_menu = true
		host.level_runner.exit_level()
	else:
		host.paused = false
		host.return_to_menu()


func _close() -> void:
	set_process_input(false)
	var t := Ui.tween(dim)
	t.tween_property(dim, "color:a", 0.0, Ui.T_FAST)
	panel.disappear()
	t.tween_callback(queue_free)
	closed.emit()
