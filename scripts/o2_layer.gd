class_name O2Layer
extends ColorRect
# Chapter 6's oxygen over the dish (shaders/o2_field.gdshader): the faint
# wash and bubbles always, the map in the analysis view (environment layer 4,
# 氧气). Hidden in worlds without oxygen. The field is refreshed a few times
# a second (it changes slowly).

var host: Node2D
var tex: ImageTexture
var mat: ShaderMaterial
var map_amt := 0.0
var _t := 0.0
var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/o2_field.gdshader")
	material = mat
	visible = false


# A new world: show only where there is oxygen.
func reset() -> void:
	var on: bool = host.o2_world
	visible = on
	if not on:
		return
	var c: Vector2 = host.DISH_CENTER
	var r: float = host.DISH_RADIUS
	position = c - Vector2(r, r)
	size = Vector2(r, r) * 2.0
	var g: Vector2i = host.sim.get_grid_size()
	var cell: float = host.sim.get_cell_size()
	mat.set_shader_parameter("rect_pos", position)
	mat.set_shader_parameter("rect_size", size)
	mat.set_shader_parameter("field_size", Vector2(g) * cell)
	mat.set_shader_parameter("dish_center", c)
	mat.set_shader_parameter("dish_radius", r)
	_refresh()


func _refresh() -> void:
	var g: Vector2i = host.sim.get_grid_size()
	var img := Image.create_from_data(g.x, g.y, false, Image.FORMAT_RF, host.sim.get_o2_field().to_byte_array())
	if tex == null or tex.get_size() != Vector2(g):
		tex = ImageTexture.create_from_image(img)
		mat.set_shader_parameter("o2_tex", tex)
	else:
		tex.update(img)


func tick(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_clock += delta
	if _clock >= 0.25:
		_clock = 0.0
		_refresh()
	var want: float = 1.0 if host.analyzing and host.env_layer == 4 else 0.0
	map_amt = move_toward(map_amt, want, delta / Ui.T_MID)
	mat.set_shader_parameter("map_amount", map_amt)
	mat.set_shader_parameter("ambient", 1.0 - 0.6 * map_amt)
	mat.set_shader_parameter("t", _t)
