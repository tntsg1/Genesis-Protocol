class_name NightMode
extends CanvasLayer
# Night mode (DECISIONS 黑夜模式 2026-11-05), the look "深海荧光": the water a
# warm deep black with motes of light drifting in it, cells glowing softly in
# their own colours, the vents and the producers with a warm halo, the UI dark
# glass with warm white ink and the accents as vivid as by day. Every shader
# that draws something of its own reads the global shader parameter `night`
# (0..1, eased here; shaders/night.gdshaderinc) and has its own night look;
# whatever draws without a shader (labels, the panels' content, icons, the
# dish's marks) gets shaders/night_remap.gdshader, put on it here, which turns
# its colours to the night palette. Setting (settings file, display/night):
# "auto" (the default: on in the seabed levels, chapter 6, whose worlds say
# night = true), "on", "off". The key (N by default) flips it from whatever it
# is now, and that choice sticks. Cutscenes are dark already and hold it off
# while they play (suspend).

const LAYER := 100

static var setting := "auto"
static var auto_on := false # the world on show asks for it (seabed)
static var suspend := 0 # cutscenes playing
static var _loaded := false

const REMAP := preload("res://shaders/night_remap.gdshader")

var host: Node
var remap: ShaderMaterial
var painting := false # the remap is being put on everything new
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
	remap = ShaderMaterial.new()
	remap.shader = REMAP
	note = Label.new()
	note.add_theme_font_override("font", Ui.sans(600))
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color(0.96, 0.92, 0.85))
	note.add_theme_constant_override("outline_size", 6)
	note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.modulate.a = 0.0
	note.set_meta("night_keep", true)
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
	RenderingServer.global_shader_parameter_set("night", amt)
	if amt > 0.0 and not painting:
		# From the first time it comes on: everything drawn without a shader
		# takes the remap (at night = 0 it changes nothing), now and as it
		# is made.
		painting = true
		_paint_all(get_tree().root)
		get_tree().node_added.connect(_paint)
	# The world's bloom reaches further down at night: what glows, glows.
	var env: Environment = host.get("world_env") if host else null
	if env:
		env.glow_hdr_threshold = lerpf(1.0, 0.42, amt)
		env.glow_intensity = lerpf(0.7, 0.95, amt)


func _paint_all(n: Node) -> void:
	_paint(n)
	for k in n.get_children(true):
		_paint_all(k)


# Anything drawn without a shader of its own, unless it asks not to be
# (meta night_keep: drawn for the night already, or a picture).
func _paint(n: Node) -> void:
	var ci := n as CanvasItem
	if ci == null or ci.material != null or ci.use_parent_material or ci.has_meta("night_keep"):
		return
	ci.material = remap


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
