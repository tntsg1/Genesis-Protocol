class_name NightMode
extends CanvasLayer
# Night mode (DECISIONS 黑夜模式 2026-11-05): the whole game black, by a
# full-screen pass over the finished frame (shaders/night.gdshader), so no
# panel or shader of its own needs a second look. Setting (settings file,
# display/night): "auto" (the default: on in the seabed levels, chapter 6,
# whose worlds say night = true), "on", "off". The key (N by default) flips
# it from whatever it is now, and that choice sticks. Cutscenes are dark
# already and hold it off while they play (suspend).

const LAYER := 100

static var setting := "auto"
static var auto_on := false # the world on show asks for it (seabed)
static var suspend := 0 # cutscenes playing
static var _loaded := false

var host: Node
var rect: ColorRect
var mat: ShaderMaterial
var amt := 0.0
var note: Label
var note_t := 0.0


static func load_setting() -> void:
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(Keys.path()) == OK:
		setting = str(cf.get_value("display", "night", "auto"))


static func save_setting() -> void:
	var cf := ConfigFile.new()
	cf.load(Keys.path())
	cf.set_value("display", "night", setting)
	cf.save(Keys.path())


static func set_setting(s: String) -> void:
	setting = s
	save_setting()


static func on() -> bool:
	if not _loaded:
		load_setting()
	return setting == "on" or (setting == "auto" and auto_on)


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	# (The screen is copied once a frame for whoever reads it first; the lens
	# pass far below has, so force a fresh copy of everything drawn so far.)
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bb)
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/night.gdshader")
	rect.material = mat
	add_child(rect)
	note = Label.new()
	note.add_theme_font_override("font", Ui.sans(600))
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	note.add_theme_constant_override("outline_size", 6)
	note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.modulate.a = 0.0
	add_child(note)


func _ready() -> void:
	amt = 1.0 if on() else 0.0
	_apply()


func _process(delta: float) -> void:
	var want := 1.0 if on() and suspend <= 0 else 0.0
	amt = move_toward(amt, want, delta / 0.3)
	_apply()
	if note_t > 0.0:
		note_t -= delta
		note.modulate.a = clampf(note_t / 0.5, 0.0, 1.0)
		var vs := get_viewport().get_visible_rect().size
		note.position = Vector2(0, vs.y * 0.16)
		note.size = Vector2(vs.x, 30)


func _apply() -> void:
	rect.visible = amt > 0.001
	mat.set_shader_parameter("amount", amt)


# The key: flip from what it is now; the choice sticks.
func toggle() -> void:
	set_setting("off" if on() else "on")
	note.text = "黑夜模式：%s　·　按 %s 切换　·　设置里可改回“自动”" % ["开" if on() else "关", Keys.name_of(Keys.code("night"))]
	note_t = 2.4
	Audio.sfx("holo_tick", -8.0, 0.8 if on() else 1.2)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if Keys.action_of((event as InputEventKey).keycode) != "night":
		return
	# Not while typing a name, nor while a key is being rebound.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if host and host.get("menu") and str(host.menu.get("capturing")) != "":
		return
	toggle()
	get_viewport().set_input_as_handled()
