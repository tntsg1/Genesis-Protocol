extends CanvasLayer
# Developer mode's timings (the 帧率与模拟耗时 switch, scripts/dev_mode.gd):
# one line at the top right, four times a second: frames per second, the
# frame's time, the simulation's cost per step, how many cells and species.

var host: Node2D
var label: Label
var _t := 0.0


func _ready() -> void:
	layer = 60
	label = Ui.label("", 12, Ui.INK, Ui.mono("Medium"))
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.offset_left = -560.0
	label.offset_right = -24.0
	label.offset_top = 8.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _process(delta: float) -> void:
	visible = DevMode.on(DevMode.perf)
	_t += delta
	if not visible or _t < 0.25:
		return
	_t = 0.0
	var fps := Engine.get_frames_per_second()
	label.text = "DEV   %d FPS   帧 %.1f ms   模拟 %.2f ms/步   细胞 %d   物种 %d" % [
		fps, 1000.0 / maxf(fps, 1.0), host.sim_usec / 1000.0, host.sim.get_count(), host.colors.size()]
