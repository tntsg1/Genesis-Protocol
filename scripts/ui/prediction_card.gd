extends Control
# Before release (DECISIONS M4 Q2): write down a prediction. One question
# with 3-4 measurable ranges; 1-4 or a click picks one, Enter confirms and
# the release goes ahead. A right prediction earns research points.

signal chosen(index: int)

var level: Dictionary
var pick := -1
var options: Array = []
var go: Widgets.Pill
var panel: GlassPanel


func setup(l: Dictionary) -> void:
	level = l


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.95, 0.975, 0.99, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	panel = GlassPanel.new(Vector4(34, 28, 34, 28))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -430
	panel.offset_right = 430
	panel.offset_top = -250
	panel.offset_bottom = 250
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.body.add_child(v)
	v.add_child(Ui.caption("写下你的预测", "PREDICTION · %s" % level.id))
	var q := Ui.label(level.predict.question, 24, Ui.INK, Ui.sans(700))
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size.x = 780
	v.add_child(q)
	v.add_child(Ui.label("投放前先想一想。实验结束时揭晓，猜对 +5 研究点。", 13, Ui.INK_SOFT, Ui.sans()))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	var opts: Array = level.predict.options
	for k in opts.size():
		var b := Widgets.Pill.new("%d    %s" % [k + 1, opts[k][0]], 0, Ui.sans(600))
		b.custom_minimum_size = Vector2(380, 54)
		var idx := k
		b.pressed.connect(func() -> void: _pick(idx))
		grid.add_child(b)
		options.append(b)
	var foot := HBoxContainer.new()
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	go = Widgets.Pill.new("确认并投放  Enter", 0, Ui.sans(600))
	go.custom_minimum_size = Vector2(220, 44)
	go.modulate.a = 0.45
	go.pressed.connect(_confirm)
	foot.add_child(go)
	v.add_child(foot)
	modulate.a = 0.0
	Ui.tween(self).tween_property(self, "modulate:a", 1.0, Ui.T_MID)
	panel.appear(0.05)


func _pick(k: int) -> void:
	pick = k
	for j in options.size():
		options[j].active = j == k
	go.active = true
	go.modulate.a = 1.0


func _confirm() -> void:
	if pick < 0:
		return
	var t := Ui.tween(self)
	t.tween_property(self, "modulate:a", 0.0, Ui.T_MID)
	t.tween_callback(queue_free)
	chosen.emit(pick)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key < KEY_1 + options.size():
			_pick(key - KEY_1)
		elif key == KEY_ENTER or key == KEY_KP_ENTER:
			_confirm()
		else:
			return
		get_viewport().set_input_as_handled()
