extends Node2D
# A self-contained view of one dish (for the side-by-side control experiment
# and anything else that shows a second simulation): the water and its
# fields (shaders/dish.gdshader), the organisms (shaders/organism.gdshader)
# and a camera. The owner steps the sim; render() draws it.

const CAPACITY := 8000
const WORLD := Vector2(2200, 2200)
const DISH_CENTER := Vector2(1100, 1100)
const DISH_RADIUS := 1060.0

var sim: SimCore
var cam: Camera2D
var cells: MultiMeshInstance2D
var medium: ColorRect
var dish_mat: ShaderMaterial
var tex := {}
var _tex_t := 0.0
var _phase := 0


func setup(s: SimCore) -> void:
	sim = s
	tex.nutrient = ImageTexture.create_from_image(_field(sim.get_nutrient_field()))
	tex.light = ImageTexture.create_from_image(_field(sim.get_light_field()))
	tex.algae = ImageTexture.create_from_image(_field(sim.get_algae_field()))
	tex.env = ImageTexture.create_from_image(_rgbaf(sim.get_env_field()))
	tex.pop = ImageTexture.create_from_image(_rgbaf(sim.get_population_field()))
	medium = ColorRect.new()
	medium.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medium.position = -Vector2(3000, 3000)
	medium.size = WORLD + Vector2(6000, 6000)
	dish_mat = ShaderMaterial.new()
	dish_mat.shader = preload("res://shaders/dish.gdshader")
	dish_mat.set_shader_parameter("nutrient_tex", tex.nutrient)
	dish_mat.set_shader_parameter("light_tex", tex.light)
	dish_mat.set_shader_parameter("algae_tex", tex.algae)
	dish_mat.set_shader_parameter("env_tex", tex.env)
	dish_mat.set_shader_parameter("pop_tex", tex.pop)
	dish_mat.set_shader_parameter("world_size", WORLD)
	dish_mat.set_shader_parameter("dish_center", DISH_CENTER)
	dish_mat.set_shader_parameter("dish_radius", DISH_RADIUS)
	medium.material = dish_mat
	add_child(medium)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	cells = MultiMeshInstance2D.new()
	cells.multimesh = mm
	var cm := ShaderMaterial.new()
	cm.shader = preload("res://shaders/organism.gdshader")
	cells.material = cm
	add_child(cells)
	cam = Camera2D.new()
	cam.position = DISH_CENTER
	cam.zoom = Vector2(0.4, 0.4)
	add_child(cam)
	cam.make_current()


func render(alpha: float, delta: float) -> void:
	var n := sim.get_render_count()
	if n <= CAPACITY:
		cells.multimesh.buffer = sim.build_render_buffer(clampf(alpha, 0.0, 1.0), Time.get_ticks_msec() / 1000.0, CAPACITY)
		cells.multimesh.visible_instance_count = n
	dish_mat.set_shader_parameter("cam_pos", cam.position)
	# Fields refresh in turn, a few times a second.
	_tex_t -= delta
	if _tex_t <= 0.0:
		_tex_t = 0.12
		_phase = (_phase + 1) % 2
		if _phase == 0:
			tex.nutrient.update(_field(sim.get_nutrient_field()))
		else:
			tex.algae.update(_field(sim.get_algae_field()))


func _field(f: PackedFloat32Array) -> Image:
	var g := sim.get_grid_size()
	return Image.create_from_data(g.x, g.y, false, Image.FORMAT_RF, f.to_byte_array())


func _rgbaf(f: PackedFloat32Array) -> Image:
	var g := sim.get_grid_size()
	return Image.create_from_data(g.x, g.y, false, Image.FORMAT_RGBAF, f.to_byte_array())
