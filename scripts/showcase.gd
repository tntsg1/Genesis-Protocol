extends Node2D
# Showcase: a round culture dish under the microscope lamp, running on
# SimCore and drawn as flat 2D line art (shaders/dish + shaders/organism).
# Default scene: two grazers, a predator and a multicell giant.
# `-- --gallery`: six gene archetypes side by side, to see how genes shape
# the body (fast, armoured, predator, fertile, social, energy-storing).
# Starts in the main menu (a live dish behind the title); "开始实验" flies the
# camera in and brings up the HUD with no loading of any kind. Esc with
# nothing selected flies back out to the menu. Tests (-s) skip the menu.
# Controls: left click inspect, left/middle drag pan (with inertia), wheel
# zoom toward the cursor, right click drop nutrient, F follow, Esc close,
# Space pause, 1/2/3/4 speed, F1 whole dish, G life designer, Tab analysis,
# T environment layer, C view filter (normal / species / population heat),
# WASD / arrows pan, Q / E zoom.

const WORLD := Vector2(2200, 2200)
# The habitat is a round culture dish inside the world square.
const DISH_CENTER := Vector2(1100, 1100)
const DISH_RADIUS := 1060.0
# The environment of this dish (zones, natives): a sample of Europa's ocean.
var layout: Dictionary = Ecology.EUROPA_SAMPLE
# The world being shown (Worlds.sandbox() or a campaign level's world).
var world_cfg: Dictionary = {}
# The environment as a texture (temperature, acidity, signal A, signal B) and
# which of them analysis mode lays out as a map (0 none, 1-3).
var env_tex: ImageTexture
var env_layer := 0
var o2_world := false # chapter 6: this world has oxygen (O2Layer, environment layer 4)
var net_world := false # chapter 6 boss: the pseudopod net (O2Layer draws it too)
var o2_layer: O2Layer
var ice_layer: IceLayer # chapter 7: the ice and the heliozoan
var swamp_layer: SwampLayer # chapter 8: the mud, toxins, acid rain, the slime mould, symbionts
var env_amount := 0.0
var zone_labels: Node2D
var _zone_zoom := 0.0
const TICK := 1.0 / 15.0
const CAPACITY := 12000

# Clean, natural tints that read as living cells in clear water.
const AQUA := Color(0.42, 0.8, 0.88)
const HONEY := Color(0.96, 0.76, 0.4)
const ROSE := Color(0.95, 0.5, 0.6)
const LAVENDER := Color(0.64, 0.58, 0.98)
const LEAF := Color(0.58, 0.84, 0.45)
const SKY := Color(0.55, 0.68, 0.98)

var sim: SimCore
var speed := 1.0
var paused := false
var pause_menu: CanvasLayer # the Esc menu while it shows
var exit_to_menu := false # a level left from the pause menu goes to the main menu
var steps_taken := 0 # single steps while paused (the guide waits on them)
var acc := 0.0
# Watching a division through the loupe slows the dish to a quarter speed
# (the magnifier sets observe_want; observe eases). Fewer fixed steps per
# second, nothing else: the simulation stays reproducible.
const OBSERVE_SPEED := 0.25
var observe_want := false
var observe := 0.0
var sim_usec := 0.0
var gallery := false
# World seed; tests set it before adding the scene to the tree.
var seed := 20261027

var cells: MultiMeshInstance2D
var fx: MultiMeshInstance2D
var algae_img: Image
var algae_tex: ImageTexture
# View filter (C or the dock): 0 normal, 1 species colours, 2 population
# heat map. The amounts ease the dish and the bodies between them.
var view_mode := 0
var species_amt := 0.0
var pop_amt := 0.0
var pop_img: Image
var pop_tex: ImageTexture
var field_phase := 0
var light_tex: ImageTexture
var world_env: Environment
var pointer: DishPointer
var water_fx: SubViewport
var water_fx_mat: ShaderMaterial
var vignette: CanvasLayer
var lens_mat: ShaderMaterial
const Magnifier := preload("res://scripts/ui/magnifier.gd")
const LabMarks := preload("res://scripts/lab_marks.gd")
var magnifier: Node2D
# Species picked out in the dish (hovering its row in the HUD): -1 none.
var focus_species := -1
var focus_amt := 0.0
var look2 := true
var medium: ColorRect
var nutrient_img: Image
var nutrient_tex: ImageTexture
var tex_timer := 0.0
var cam: Camera2D
var dragging := false
var labels: Array[String] = []

# Camera: the view eases toward goal_pos / goal_zoom; wheel zoom keeps the
# point under the cursor fixed; a released drag glides on; `cine` hands the
# camera to a scripted move (menu fly-in / fly-out).
var goal_pos := DISH_CENTER
var goal_zoom := 0.48
var zoom_max := 10.0 # 26 where there are phages to see
var quiet_callouts := false # the life scan keeps its organ labels off the picture
var glide := Vector2.ZERO
var cine := false

# Menu / game state.
const MainMenu := preload("res://scripts/ui/main_menu.gd")
const Fx := preload("res://scripts/fx.gd")
var menu: Control
var in_menu := false
var start_in_menu := true
var menu_time := 0.0
# The menu item under the pointer previews itself in the dish (seventh
# round): -1 none, 0 campaign (the ice water), 1 sandbox (a scan field across
# the dish), 2 settings (the stage's scales light up), 3 quit (the lamp dims).
var menu_preview := -1
var menu_goal := Vector2.ZERO
var menu_zoom := 0.5
var prev_scan := 0.0
var prev_stage := 0.0
var prev_dim := 0.0
var defocus := 0.0 # the dive's focus hunt (lens_post)
# The campaign page over the menu dish (eighth round): the camera pulls back
# off the dish and the lens throws it out of focus behind the curtain.
var menu_pull := 0.0
const IrisFx := preload("res://scripts/ui/iris_fx.gd")

# Dock tools. `mode` is a pending click on the dish: "" (none), "nutrient"
# (drop food) or "release" (seed a designed species, `release_params`).
const Report := preload("res://scripts/ui/report.gd")
const LevelRunner := preload("res://scripts/campaign/level_runner.gd")
const CampaignPage := preload("res://scripts/ui/campaign_page.gd")
# Campaign (M4): the level page, and the runner while a level is on.
var campaign: Control
var level_runner: Node
var release_count := 40
const Interventions := preload("res://scripts/interventions.gd")
var iv: Node # interventions: biomass points, nutrients, membranes, heat, currents
var base_species := 0 # species the world started with (later ones are yours)
const AnalysisLayer := preload("res://scripts/analysis_layer.gd")
const PhageLayer := preload("res://scripts/phage_layer.gd")
const GiantLayer := preload("res://scripts/giant_layer.gd")
const SlugLayer := preload("res://scripts/slug_layer.gd")
const ColonyLayer := preload("res://scripts/colony_layer.gd")
const RotiferLayer := preload("res://scripts/rotifer_layer.gd")
var analysis: Node2D
var analyzing := false
# Where the latest notable things happened (for click-to-locate in the log).
var last_mutation_pos := Vector2.INF
var mutations := 0 # mutation events seen (founders drifting in also get new lineages)
var last_mutation_id := -1 # the newborn that carries the latest mutation
const PAN_SPEED := 900.0 # screen pixels per second for keyboard panning
const RELEASE_COUNT := 40
const RELEASE_RADIUS := 70.0
var report: Control
var observing := false
var mode := ""
var release_params := {}

# Inspection and interventions.
const EcoHud := preload("res://scripts/ui/eco_hud.gd")
const Designer := preload("res://scripts/ui/designer.gd")
var designer: Control
var ui_layer: CanvasLayer
const DRAG_THRESHOLD := 5.0
var hud_root: Control
var phage_layer: Node2D # phages in the water and the infection close up
var giant_layer: Node2D # level 19: giant viruses and their factories
var slug_layer: Node2D # level 20: the sheath of a crawling slug, the fruiting body
var colony_layer: Node2D # level 21: bodies built from blocks, the stream
var rotifer_layer: Node2D # level 24: the vent guardian
var dish_marks: DishMarks # ambushers, the eaten, alerts (scripts/dish_marks.gd)
var colors: Array[Color] = []
var overlay: Node2D
var selected := -1
var selected_name := ""
var following := false
var gone_timer := 0.0
var last_pos := Vector2.ZERO
var _follow_goal_was := Vector2.INF # the followed spot last frame (camera lock-on)
var _follow_gap := Vector2.ZERO
var left_down := false
var left_dragged := false
var left_from := Vector2.ZERO
var right_down := false
var right_dragged := false
var right_from := Vector2.ZERO

# Gene archetypes for the gallery: [label, params].
const ARCHETYPES := [
	["高速型", {color = AQUA, radius = 6.0, speed = 5.0, vision = 3.0, armor = 1.0, attack = 1.0, fertility = 2.0, efficiency = 2.0}],
	["重甲型", {color = HONEY, radius = 7.5, speed = 1.4, vision = 2.0, armor = 5.0, attack = 2.0, fertility = 1.5, efficiency = 3.0}],
	["捕食型", {color = ROSE, diet = 1, radius = 9.0, speed = 3.5, vision = 4.5, armor = 2.0, attack = 5.0, fertility = 1.5, efficiency = 2.5}],
	["高繁殖型", {color = LEAF, radius = 6.0, speed = 2.0, vision = 1.5, armor = 1.0, attack = 1.0, fertility = 5.0, efficiency = 2.0}],
	["群体型", {color = SKY, radius = 5.5, speed = 2.6, vision = 2.0, armor = 1.5, attack = 1.0, fertility = 3.0, efficiency = 2.5, cohesion = 1.0}],
	["储能型", {color = LAVENDER, radius = 7.0, speed = 1.8, vision = 2.5, armor = 1.5, attack = 1.0, fertility = 2.0, efficiency = 5.0}],
]


var night: NightMode # night mode over everything (scripts/night_mode.gd)
var night_phase := false # chapter 7: night mode follows the long night


func _ready() -> void:
	gallery = "--gallery" in OS.get_cmdline_user_args()
	night = NightMode.new()
	night.host = self
	add_child(night)
	sim = SimCore.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
	var args := OS.get_cmdline_args()
	if "-s" in args or "--script" in args:
		start_in_menu = "--menu" in OS.get_cmdline_user_args()
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		# The interface is laid out at 1920 x 1080: a 1600 x 900 window shrank
		# every glyph to 83% ("字有点小"). Start maximized (never in tests: a
		# test window must stay parked off screen); F11 toggles fullscreen.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	sim.setup(WORLD, seed)
	sim.set_dish(DISH_CENTER, DISH_RADIUS)
	if gallery:
		_build_gallery()
	else:
		build_world(Worlds.sandbox())
	_build_view()


# Builds a world from its configuration (see Worlds) into the current sim.
func build_world(cfg: Dictionary) -> void:
	world_cfg = cfg
	layout = cfg.get("layout", Worlds.OPEN_WATER)
	Worlds.populate(sim, cfg, func(params: Dictionary, label: String) -> void:
		_species(params)
		labels.append(label))
	base_species = colors.size()


# Swaps in another world without leaving the scene: a fresh simulation, the
# same views (field textures refreshed, HUD rebuilt for the new species).
func load_world(cfg: Dictionary, world_seed := -1) -> void:
	if world_seed >= 0:
		seed = world_seed
	_deselect()
	if report:
		report.close()
	zoom_max = 10.0
	phage_layer.set_look({})
	sim = SimCore.new()
	sim.setup(WORLD, seed)
	sim.set_dish(DISH_CENTER, DISH_RADIUS)
	colors.clear()
	labels.clear()
	species_genes.clear()
	species_diet.clear()
	species_topt.clear()
	species_deck.clear()
	species_engulf.clear()
	species_herd.clear()
	build_world(cfg)
	# Night mode on its own in the seabed levels (setting "auto").
	NightMode.auto_on = bool(cfg.get("night", false))
	night_phase = bool(cfg.get("night_phase", false))
	o2_world = cfg.has("oxygen")
	net_world = false
	if not o2_world and env_layer == 4:
		set_env_layer(0)
	if o2_layer:
		o2_layer.reset()
	if ice_layer:
		ice_layer.reset()
	if swamp_layer:
		swamp_layer.reset()
	acc = 0.0
	iv.reset(60.0)
	nutrient_img = _field_image(sim.get_nutrient_field())
	nutrient_tex.update(nutrient_img)
	light_tex.update(_field_image(sim.get_light_field()))
	algae_img = _field_image(sim.get_algae_field())
	algae_tex.update(algae_img)
	env_tex.update(_env_image())
	pop_img = _pop_image()
	pop_tex.update(pop_img)
	_zone_zoom = 0.0
	zone_labels.queue_redraw()
	_upload(0.0)
	hud_root.rebuild_world()


func _build_gallery() -> void:
	sim.add_light(DISH_CENTER, 700.0, 0.6)
	sim.seed_algae(400, 22.0)
	for i in ARCHETYPES.size():
		var params: Dictionary = ARCHETYPES[i][1].duplicate()
		params.lifespan = 900.0
		_species(params)
		labels.append(ARCHETYPES[i][0])
		sim.spawn(i, gallery_spot(i), 4, 18.0)


# Founding genome per species (speed, sense, shell, attack, fertility,
# metabolism, neural): the life scan marks loci that have drifted from it.
var species_genes: Array = []
var species_diet: Array[int] = []
var species_topt: Array[float] = [] # founders' preferred water (°C)
var species_deck: Array = [] # founders' rule cards
var species_engulf: Array[bool] = [] # swallow whole on touch (the dish marks them)
var species_herd: Array[float] = [] # a hunter that cannot pick one out of this many together (0 = it can)


func _species(params: Dictionary) -> void:
	sim.add_species(params)
	colors.append(params.color)
	var g := []
	for key in ["speed", "vision", "armor", "attack", "fertility", "efficiency", "neural", "temp_tol"]:
		g.append(float(params.get(key, 2.5 if key == "temp_tol" else 3.0)))
	species_genes.append(g)
	species_diet.append(int(params.get("diet", 0)))
	species_topt.append(float(params.get("temp_opt", 12.0)))
	species_deck.append(params.get("deck", Rules.default_deck(int(params.get("diet", 0)))))
	species_engulf.append(float(params.get("engulf", 0.0)) > 0.0)
	species_herd.append(float(params.get("herd", 0.0)))


# Chemosynthetic species are producers: the vents keep seeding them.
func is_producer(i: int) -> bool:
	return species_diet.size() > i and species_diet[i] == 2


func species_color(i: int) -> Color:
	return colors[i]


# The designer opens with a dive: the camera closes in on a cell (the
# selected one, else the one nearest the middle of the view) and the designer
# takes over from its nucleus. The dish holds still while you design.
const MENU_RELEASE_SPOT := Vector2(-150, 60) # from DISH_CENTER
var _before_dive := {}


func open_designer() -> void:
	if designer:
		return
	if level_runner and level_runner.phase != "design":
		hud_root.notify("本次实验已经投放；想改方案，等结算后点“改方案再试”", Ui.WARN)
		return
	var from_menu := in_menu
	var id := selected if selected >= 0 and not sim.get_agent(selected).is_empty() else -1
	if id < 0:
		id = sim.find_agent(DISH_CENTER if in_menu else cam.position, 900.0 / cam.zoom.x)
	var info: Dictionary = sim.get_agent(id) if id >= 0 else {}
	_before_dive = {pos = cam.position, zoom = cam.zoom.x, menu = from_menu}
	following = false
	var view := get_viewport().get_visible_rect().size
	var nucleus_r := 14.0
	var reference := {}
	if not info.is_empty():
		var radius: float = info.radius
		var z := clampf(60.0 / radius, 1.5, 10.0)
		fly_to(info.position, z, 1.45)
		nucleus_r = 0.23 * radius * z
		var spi: int = info.species
		reference = {name = "%s #%05d" % [labels[spi], id], color = colors[spi], genes = info.genes, deck = info.deck, temp_opt = info.temp_opt}
	if from_menu:
		menu.leave()
	else:
		hud_root.conceal()
	designer = Designer.new()
	Audio.music("lab")
	Audio.sfx("dive")
	designer.setup(reference, view * 0.5, nucleus_r)
	designer.released.connect(begin_release)
	designer.pull_out.connect(_pull_out)
	designer.closed.connect(func() -> void:
		designer = null
		Audio.music("menu" if in_menu else "dish")
		if in_menu:
			menu.enter()
		elif not _before_dive.menu:
			hud_root.reveal()
		# Put away before the release: say how to go back, and how to leave.
		if level_runner and level_runner.phase == "design":
			hud_root.banner("方案还没投放", "按 %s 回到生命设计器，按 Esc 打开菜单" % Keys.name_of(Keys.code("designer")), Ui.WARN))
	ui_layer.add_child(designer)


# Back out of the nucleus: to where we were, or (releasing from the menu)
# straight over the spot where the new species will land.
func _pull_out(releasing: bool) -> void:
	if releasing and in_menu:
		fly_to(DISH_CENTER + MENU_RELEASE_SPOT, 1.1, 1.3)
		return
	if in_menu:
		fly_to(menu_spot(0.5), 0.5, 1.3)
		return
	fly_to(_before_dive.pos, minf(_before_dive.zoom, 4.0), 1.3)


# - / =: one step down or up the ladder the HUD's speed buttons show.
const SPEEDS := [0.25, 1.0, 3.0, 8.0]


func step_speed(dir: int) -> void:
	var i := 0
	for k in SPEEDS.size():
		if speed >= SPEEDS[k] - 0.01:
			i = k
	set_speed(SPEEDS[clampi(i + dir, 0, SPEEDS.size() - 1)])
	hud_root.notify("速度 %s×" % ("¼" if speed < 0.5 else str(int(speed))), Ui.ACCENT)


func set_speed(s: float) -> void:
	if s <= 0.0:
		paused = true
	else:
		paused = false
		speed = s


func gallery_spot(i: int) -> Vector2:
	return DISH_CENTER + Vector2((i % 3 - 1) * 150.0, (i / 3 - 0.5) * 150.0)


func _build_view() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# Look 2: a soft bloom on what shines (membranes, effects) only.
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.7
	env.glow_strength = 1.1
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for lv in 7:
		env.set_glow_level(lv, lv >= 1 and lv <= 4)
	world_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	nutrient_img = _field_image(sim.get_nutrient_field())
	nutrient_tex = ImageTexture.create_from_image(nutrient_img)
	light_tex = ImageTexture.create_from_image(_field_image(sim.get_light_field()))
	algae_img = _field_image(sim.get_algae_field())
	algae_tex = ImageTexture.create_from_image(algae_img)
	env_tex = ImageTexture.create_from_image(_env_image())
	pop_img = _pop_image()
	pop_tex = ImageTexture.create_from_image(pop_img)
	medium = ColorRect.new()
	# World-space background: it must never swallow mouse input, or the
	# camera, inspection and nutrient clicks never see a single click.
	medium.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medium.position = -Vector2(3000, 3000)
	medium.size = WORLD + Vector2(6000, 6000)
	var mm := ShaderMaterial.new()
	mm.shader = preload("res://shaders/dish.gdshader")
	mm.set_shader_parameter("nutrient_tex", nutrient_tex)
	mm.set_shader_parameter("light_tex", light_tex)
	mm.set_shader_parameter("world_size", WORLD)
	mm.set_shader_parameter("dish_center", DISH_CENTER)
	mm.set_shader_parameter("dish_radius", DISH_RADIUS)
	mm.set_shader_parameter("algae_tex", algae_tex)
	mm.set_shader_parameter("env_tex", env_tex)
	mm.set_shader_parameter("pop_tex", pop_tex)
	medium.material = mm
	# Look 2's slow water layers at quarter resolution, sampled by the dish.
	water_fx = SubViewport.new()
	water_fx.size = Vector2i(get_viewport().get_visible_rect().size / 4.0)
	water_fx.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	water_fx.disable_3d = true
	var wr := ColorRect.new()
	wr.size = Vector2(water_fx.size)
	water_fx_mat = ShaderMaterial.new()
	water_fx_mat.shader = preload("res://shaders/water_fx.gdshader")
	wr.material = water_fx_mat
	water_fx.add_child(wr)
	add_child(water_fx)
	mm.set_shader_parameter("water_fx", water_fx.get_texture())
	add_child(medium)
	# The lab's text: stage scales and label, the projected grid's numbers.
	var marks := LabMarks.new()
	marks.host = self
	add_child(marks)
	# Chapter 6: the oxygen in the water, under the cells.
	o2_layer = O2Layer.new()
	o2_layer.host = self
	add_child(o2_layer)
	ice_layer = IceLayer.new()
	ice_layer.host = self
	ice_layer.visible = false
	swamp_layer = SwampLayer.new()
	swamp_layer.host = self
	swamp_layer.visible = false
	add_child(swamp_layer)

	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0
	cells = MultiMeshInstance2D.new()
	cells.multimesh = multimesh
	var cm := ShaderMaterial.new()
	cm.shader = preload("res://shaders/organism.gdshader")
	cells.material = cm
	phage_layer = PhageLayer.new()
	phage_layer.host = self
	add_child(phage_layer.free_mm)
	giant_layer = GiantLayer.new()
	giant_layer.host = self
	add_child(giant_layer.free_mm)
	slug_layer = SlugLayer.new()
	slug_layer.host = self
	add_child(slug_layer)
	add_child(cells)
	if ice_layer:
		add_child(ice_layer)
	add_child(swamp_layer.top)

	analysis = AnalysisLayer.new()
	add_child(analysis)
	analysis.setup(self)

	fx = Fx.new()
	fx.colors = colors
	add_child(fx)
	add_child(phage_layer)
	add_child(giant_layer)
	colony_layer = ColonyLayer.new()
	colony_layer.z_index = 1 # (above the dish's scale numbers: these bodies are big)
	colony_layer.host = self
	add_child(colony_layer)
	rotifer_layer = RotiferLayer.new()
	rotifer_layer.z_index = 2 # (over the colonies: what it swallows is seen inside it)
	rotifer_layer.host = self
	add_child(rotifer_layer)
	dish_marks = DishMarks.new()
	dish_marks.host = self
	add_child(dish_marks)
	iv = Interventions.new()
	iv.host = self
	add_child(iv)

	overlay = Node2D.new()
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	# Zone names and rims: redrawn only when the zoom changes enough, faded
	# with modulate (they would cost a millisecond a frame drawn live).
	zone_labels = Node2D.new()
	zone_labels.draw.connect(_draw_zone_labels)
	add_child(zone_labels)

	cam = Camera2D.new()
	cam.position = DISH_CENTER
	cam.zoom = Vector2(0.48, 0.48)
	add_child(cam)

	# Look 2: the microscope lens over the dish, under the interface: a sharp
	# middle, the edges out of focus, cooler and a little dimmer.
	vignette = CanvasLayer.new()
	vignette.layer = 5
	var vr := ColorRect.new()
	vr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lens_mat = ShaderMaterial.new()
	lens_mat.shader = preload("res://shaders/lens_post.gdshader")
	vr.material = lens_mat
	vignette.add_child(vr)
	add_child(vignette)
	# The magnifier (hold Alt / Z): the dish seen closer under the pointer.
	magnifier = Magnifier.new()
	magnifier.host = self
	var ml := CanvasLayer.new()
	ml.layer = 7
	ml.add_child(magnifier)
	add_child(ml)
	# The microscope pointer and its ripples, over the dish, under the UI.
	var pl := CanvasLayer.new()
	pl.layer = 8
	add_child(pl)
	pointer = DishPointer.new()
	pointer.host = self
	pl.add_child(pointer)

	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	ui_layer = ui
	hud_root = EcoHud.new()
	ui.add_child(hud_root)
	hud_root.setup(self)
	menu = MainMenu.new()
	ui.add_child(menu)
	menu.setup(self)
	campaign = CampaignPage.new()
	ui.add_child(campaign)
	campaign.setup(self)
	campaign.start_level.connect(start_level)
	campaign.closed.connect(func() -> void:
		if level_runner == null:
			_campaign_backdrop(false)
			menu.enter())
	if start_in_menu and not gallery:
		in_menu = true
		_menu_camera(0.0, true)
		menu.enter()
	else:
		hud_root.reveal()


# Runs the simulation forward without drawing (used by tests and warm-up).
func advance(seconds: float) -> void:
	var steps := int(seconds / TICK)
	for i in steps:
		sim.step(TICK)


# Paused: one simulation tick (1/15 s), so the deck trace can be read card
# by card (DECISIONS 第十轮 Q12).
func step_once() -> void:
	if not paused or designer != null:
		return
	sim.step(TICK)
	steps_taken += 1


func _process(delta: float) -> void:
	# The music steps back while the dish is paused (in play, not the menu).
	Audio.duck(paused and not in_menu)
	observe = move_toward(observe, 1.0 if observe_want else 0.0, delta / 0.35)
	var run_speed := lerpf(speed, minf(speed, OBSERVE_SPEED), observe * observe * (3.0 - 2.0 * observe))
	if not paused and designer == null:
		acc += delta * run_speed
		var t0 := Time.get_ticks_usec()
		var steps := 0
		while acc >= TICK and steps < 8:
			sim.step(TICK)
			acc -= TICK
			steps += 1
		if steps >= 8:
			acc = 0.0
		if steps > 0:
			sim_usec = lerpf(sim_usec, float(Time.get_ticks_usec() - t0) / steps, 0.1)
			iv.tick(steps * TICK)
	_keyboard_pan(delta)
	# The followed cell first (this frame's spot), then the camera on it.
	_update_inspection(delta)
	_update_camera(delta)
	_upload(acc / TICK)
	var dish_mat := medium.material as ShaderMaterial
	dish_mat.set_shader_parameter("cam_pos", cam.position)
	water_fx_mat.set_shader_parameter("cam_pos", cam.position)
	water_fx_mat.set_shader_parameter("cam_zoom", cam.zoom.x)
	water_fx_mat.set_shader_parameter("screen", get_viewport().get_visible_rect().size)
	# Effects run on simulation time, so they freeze when paused.
	fx.tick(0.0 if paused else delta * minf(run_speed, 3.0), _visible_world())
	var events := sim.take_events()
	var view_r := _visible_world()
	var close := cam.zoom.x > 1.4
	for k in range(0, events.size(), 6):
		var ev_t := int(events[k])
		var ev_p := Vector2(events[k + 1], events[k + 2])
		if ev_t == SimCore.EV_MUTATION:
			last_mutation_pos = ev_p
			last_mutation_id = sim.find_agent(last_mutation_pos, 8.0)
			mutations += 1
			if view_r.has_point(ev_p) and cam.zoom.x > 0.75:
				Audio.sfx("mutation", -8.0, randf_range(0.95, 1.08))
		elif close and view_r.has_point(ev_p):
			# Life close up has a sound: a soft pop at a division, a gulp.
			if ev_t == SimCore.EV_BIRTH or ev_t == SimCore.EV_HATCH:
				Audio.sfx("bubble", -9.0, randf_range(0.9, 1.25))
			elif ev_t == SimCore.EV_EATEN:
				Audio.sfx("engulf", -6.0, randf_range(0.9, 1.1))
	fx.consume(events, cam.zoom.x)
	phage_layer.tick(0.0 if paused else delta * minf(run_speed, 3.0), clampf(acc / TICK, 0.0, 1.0), view_r, events)
	giant_layer.tick(0.0 if paused else delta * minf(run_speed, 3.0), clampf(acc / TICK, 0.0, 1.0), view_r)
	slug_layer.tick(0.0 if paused else delta * minf(run_speed, 3.0))
	colony_layer.tick(0.0 if paused else delta * run_speed, clampf(acc / TICK, 0.0, 1.0), view_r)
	rotifer_layer.tick(0.0 if paused else delta * run_speed, clampf(acc / TICK, 0.0, 1.0))
	dish_marks.tick(0.0 if paused else delta * minf(run_speed, 3.0), clampf(acc / TICK, 0.0, 1.0), view_r, events, not in_menu)
	analysis.tick(delta, clampf(acc / TICK, 0.0, 1.0), _visible_world())
	var a_amt: float = analysis.amount
	dish_mat.set_shader_parameter("analysis", a_amt)
	(cells.material as ShaderMaterial).set_shader_parameter("analysis", a_amt)
	lens_mat.set_shader_parameter("amount", 1.0 - a_amt)
	_update_previews(delta)
	var vsz := get_viewport().get_visible_rect().size
	lens_mat.set_shader_parameter("aspect", Vector2(vsz.x / vsz.y, 1.0))
	_update_focus_species(delta)
	# Fields refresh in turn, one per frame, so no frame pays for both.
	tex_timer -= delta
	if tex_timer <= 0.0:
		tex_timer = 0.12
		field_phase = (field_phase + 1) % 4
		if field_phase == 3 and pop_amt <= 0.0:
			field_phase = 0 # the population map only refreshes while it shows
		if field_phase == 3:
			pop_img = _pop_image()
			pop_tex.update(pop_img)
		elif field_phase == 0:
			nutrient_img = _field_image(sim.get_nutrient_field())
			nutrient_tex.update(nutrient_img)
		elif field_phase == 1:
			algae_img = _field_image(sim.get_algae_field())
			algae_tex.update(algae_img)
		else:
			env_tex.update(_env_image()) # signals drift; zones hold still
	var vm := 0 if in_menu or cine else view_mode
	species_amt = move_toward(species_amt, 1.0 if vm == 1 else 0.0, delta / Ui.T_MID)
	pop_amt = move_toward(pop_amt, 1.0 if vm == 2 else 0.0, delta / Ui.T_MID)
	dish_mat.set_shader_parameter("species_amount", species_amt)
	dish_mat.set_shader_parameter("pop_amount", pop_amt)
	env_amount = move_toward(env_amount, 1.0 if analyzing and env_layer > 0 and env_layer < 4 else 0.0, delta / Ui.T_MID)
	if o2_layer:
		o2_layer.tick(delta)
	# Chapter 7 (Q241): night mode on its own only while the long night lasts.
	if night_phase:
		NightMode.auto_on = sim.get_night()
	dish_mat.set_shader_parameter("env_amount", env_amount)
	if (env_amount > 0.0 or env_layer > 0) and env_layer < 4:
		dish_mat.set_shader_parameter("env_layer", env_layer)
	_tick_capsule(delta)
	if level_runner:
		level_runner.tick(delta * (0.0 if paused or designer else 1.0))
	_update_zone_labels()
	overlay.queue_redraw()


func _visible_world() -> Rect2:
	var view := get_viewport().get_visible_rect().size / cam.zoom
	return Rect2(cam.position - view * 0.5, view)


func _update_camera(delta: float) -> void:
	if designer and not cine:
		return # parked inside the dived cell until the designer lets go
	if in_menu and not cine:
		_menu_camera(delta, false)
	if cine:
		return
	if following and selected >= 0:
		goal_pos = last_pos
	elif not (dragging or (left_down and left_dragged) or (right_down and right_dragged)):
		goal_pos += glide * delta
		glide *= exp(-4.5 * delta)
	goal_pos = _clamp_to_dish(goal_pos)
	var k := 1.0 - exp(-12.0 * delta)
	if following and selected >= 0:
		# Locked on: the camera moves with the cell exactly and only the
		# gap left from catching up eases away. (Easing toward a moving
		# target trails it by an amount that wobbles with every frame's
		# length: at x10 that read as the cell shaking.)
		_follow_gap = (cam.position - _follow_goal_was) * (1.0 - k) if _follow_goal_was.is_finite() else cam.position - goal_pos
		cam.position = goal_pos + _follow_gap
		_follow_goal_was = goal_pos
	else:
		_follow_goal_was = Vector2.INF
		cam.position = cam.position.lerp(goal_pos, k)
	cam.zoom = Vector2.ONE * exp(lerpf(log(cam.zoom.x), log(goal_zoom), k))


func _clamp_to_dish(p: Vector2) -> Vector2:
	var d := p - DISH_CENTER
	return DISH_CENTER + d.limit_length(DISH_RADIUS + 200.0)


# The menu's slow drift: the dish sits right of centre, breathing gently.
func _menu_camera(delta: float, snap: bool) -> void:
	menu_time += delta
	# Where the hovered item wants the camera (the dish sits right of the
	# menu column, so every spot is pushed right like menu_spot).
	var spot := DISH_CENTER
	var sz := 0.5
	match menu_preview:
		0:
			spot = Ecology.EUROPA_SAMPLE.zones[1].center
			sz = 0.8
		1:
			sz = 0.56
		2:
			spot = DISH_CENTER + Vector2(-780.0, 800.0)
			sz = 0.62
		3:
			sz = 0.46
	sz *= lerpf(1.0, 0.55, menu_pull)
	var view_w := get_viewport().get_visible_rect().size.x
	var target := spot - Vector2(view_w * 0.17, 0.0) / sz
	var k := 1.0 if snap or menu_goal == Vector2.ZERO else 1.0 - exp(-(1.8 + 2.4 * menu_pull) * delta)
	menu_goal = menu_goal.lerp(target, k)
	menu_zoom = exp(lerpf(log(menu_zoom), log(sz), k))
	var z := menu_zoom * (1.0 + 0.024 * sin(menu_time * 0.21))
	var p := menu_goal + Vector2(cos(menu_time * 0.05), sin(menu_time * 0.07)) * 40.0
	goal_pos = p
	goal_zoom = z
	if snap:
		cam.position = p
		cam.zoom = Vector2(z, z)


func menu_spot(z: float) -> Vector2:
	var view_w := get_viewport().get_visible_rect().size.x
	return DISH_CENTER - Vector2(view_w * 0.17, 0.0) / z


# Scripted camera move; zoom eases in log space so it feels like a dolly.
func fly_to(pos: Vector2, zoom: float, seconds: float) -> Tween:
	cine = true
	glide = Vector2.ZERO
	var p0 := cam.position
	var z0 := log(cam.zoom.x)
	var z1 := log(zoom)
	var t := create_tween()
	t.tween_method(func(v: float) -> void:
		var e := v * v * (3.0 - 2.0 * v)
		e = e * e * (3.0 - 2.0 * e)
		cam.position = p0.lerp(pos, e)
		cam.zoom = Vector2.ONE * exp(lerpf(z0, z1, e)), 0.0, 1.0, seconds)
	t.tween_callback(func() -> void:
		cine = false
		goal_pos = pos
		goal_zoom = zoom)
	return t


func start_experiment() -> void:
	if not in_menu:
		return
	in_menu = false
	menu.leave()
	# Land on a living colony near the middle of the dish.
	var target := DISH_CENTER + Vector2(-260, 120)
	var best := INF
	for p in sim.get_positions(0):
		var d := p.distance_to(DISH_CENTER + Vector2(-200, 0))
		if d < best:
			best = d
			target = p
	fly_to(target, 1.05, 2.2)
	# One take: the plunge reads like a microscope racking focus (blur that
	# hunts and settles as the magnification rolls), the HUD comes up with
	# the visor's sweep as the image sharpens.
	menu.fx.dive(cam.zoom.x, 1.05, 2.2)
	var ft := create_tween()
	ft.tween_property(self, "defocus", 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ft.tween_property(self, "defocus", 0.15, 0.8).set_trans(Tween.TRANS_SINE)
	ft.tween_property(self, "defocus", 0.42, 0.3).set_trans(Tween.TRANS_SINE)
	ft.tween_property(self, "defocus", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	Audio.sfx("dive", -6.0)
	get_tree().create_timer(2.2).timeout.connect(func() -> void: Audio.sfx("holo_on", -8.0, 1.3))
	Audio.music("dish")
	get_tree().create_timer(1.3).timeout.connect(hud_root.reveal)
	get_tree().create_timer(2.6).timeout.connect(func() -> void:
		if mode == "":
			hud_root.show_hint("拖动画面移动视角（左 / 右 / 中键都可以）　·　滚轮缩放　·　WASD 平移　·　点小地图跳转")
			get_tree().create_timer(6.0).timeout.connect(func() -> void:
				if mode == "":
					hud_root.hide_hint()))


# --- campaign -------------------------------------------------------------------

func open_campaign() -> void:
	if not in_menu:
		return
	menu.leave()
	campaign.open()
	_campaign_backdrop(true)


# Behind the campaign page the dish falls back and out of focus (and comes
# forward again when the page goes).
func _campaign_backdrop(on: bool) -> void:
	var t := create_tween().set_parallel()
	t.tween_property(self, "menu_pull", 1.0 if on else 0.0, 1.1 if on else 0.8).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "defocus", 0.75 if on else 0.0, 0.9 if on else 0.6).set_trans(Tween.TRANS_SINE)


# A frozen frame over the world, in the interface layer (under the campaign
# page when `under_page`).
func _freeze(under_page := false) -> Control:
	var f: Control = IrisFx.new()
	ui_layer.add_child(f)
	if under_page:
		ui_layer.move_child(f, campaign.get_index())
	f.shoot(get_viewport())
	return f


func start_level(l: Dictionary) -> void:
	# Chapter 6: the landfall on planet one plays before 6-1, the first time
	# (scripts/ui/arrival.gd; tests skip it).
	var testing := "-s" in OS.get_cmdline_args() or "--script" in OS.get_cmdline_args()
	if l.get("arrival", false) and not CampaignSave.seen("arrival_6") and not testing:
		CampaignSave.mark_seen("arrival_6")
		var a: CanvasLayer = preload("res://scripts/ui/arrival.gd").new()
		add_child(a)
		a.finished.connect(func() -> void: start_level(l))
		return
	# Chapter 7: the passage to planet two before 7-1 (scripts/ui/arrival2.gd).
	if l.get("arrival2", false) and not CampaignSave.seen("arrival_7") and not testing:
		CampaignSave.mark_seen("arrival_7")
		var a2: CanvasLayer = preload("res://scripts/ui/arrival2.gd").new()
		add_child(a2)
		a2.finished.connect(func() -> void: start_level(l))
		return
	# Chapter 8: the passage to planet three before 8-1 (scripts/ui/arrival3.gd).
	if l.get("arrival3", false) and not CampaignSave.seen("arrival_8") and not testing:
		CampaignSave.mark_seen("arrival_8")
		var a3: CanvasLayer = preload("res://scripts/ui/arrival3.gd").new()
		add_child(a3)
		a3.finished.connect(func() -> void: start_level(l))
		return
	# From the campaign page: the frame freezes, a lens opens at the station
	# and grows over the screen; under it the level's dish is already there,
	# far and soft, and racks into focus as the camera comes down to the
	# release spot. The HUD comes up with the sharp image, the designer after.
	var entry := campaign.visible
	var at := Vector2.INF
	if entry:
		at = campaign.station_screen()
		var iris := _freeze()
		iris.open(at, 1.0)
		Audio.sfx("dive", -6.0)
	campaign.hide_for_level()
	if menu.visible:
		menu.leave() # never under a level
	in_menu = false
	menu_pull = 0.0
	if level_runner:
		level_runner.queue_free()
	level_runner = LevelRunner.new()
	level_runner.host = self
	level_runner.exited.connect(_on_level_exit)
	add_child(level_runner)
	level_runner.start(l, {}, at)
	Audio.music("dish")
	if not entry:
		hud_root.reveal()
		return
	menu.fx.dive(LevelRunner.ENTRY_ZOOM.x, LevelRunner.ENTRY_ZOOM.y, LevelRunner.ENTRY_SECONDS)
	var ft := create_tween()
	defocus = 1.0
	ft.tween_interval(0.45)
	ft.tween_property(self, "defocus", 0.12, 0.85).set_trans(Tween.TRANS_SINE)
	ft.tween_property(self, "defocus", 0.4, 0.3).set_trans(Tween.TRANS_SINE)
	ft.tween_property(self, "defocus", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	get_tree().create_timer(1.25).timeout.connect(hud_root.reveal)
	get_tree().create_timer(LevelRunner.ENTRY_SECONDS).timeout.connect(func() -> void: Audio.sfx("holo_on", -8.0, 1.3))


# Back from a level: the sandbox dish returns behind the campaign page.
func _on_level_exit() -> void:
	# The level's last frame holds still (and fades) under the campaign
	# page's curtain while the sandbox dish comes back behind it.
	_freeze(true).veil(1.1)
	if level_runner:
		level_runner.queue_free()
		level_runner = null
	Designer.level_rules = {}
	release_count = RELEASE_COUNT
	paused = false
	hud_root.set_level({})
	hud_root.conceal()
	load_world(Worlds.sandbox(), 20261027)
	advance(20.0)
	in_menu = true
	menu_time = 0.0
	menu_pull = 1.0
	menu_preview = -1
	_menu_camera(0.0, true)
	cam.position = goal_pos
	cam.zoom = Vector2.ONE * goal_zoom
	defocus = 0.75
	# Left from the pause menu: straight to the main menu, not the level page.
	if exit_to_menu:
		exit_to_menu = false
		defocus = 0.0
		menu.enter()
		return
	campaign.open()


# Esc over the dish: 继续 / 设置 / 返回主菜单 (scripts/ui/pause_menu.gd).
func open_pause_menu() -> void:
	if is_instance_valid(pause_menu):
		return
	pause_menu = preload("res://scripts/ui/pause_menu.gd").new()
	pause_menu.host = self
	add_child(pause_menu)


func return_to_menu() -> void:
	Audio.music("menu")
	if view_mode != 0:
		set_view_mode(0)
	if in_menu:
		return
	_deselect()
	in_menu = true
	hud_root.conceal()
	menu_time = 0.0
	fly_to(menu_spot(0.5), 0.5, 1.8)
	get_tree().create_timer(0.7).timeout.connect(menu.enter)


func _update_inspection(delta: float) -> void:
	if selected < 0:
		return
	var info: Dictionary = sim.get_agent(selected)
	if info.is_empty():
		# It died: the life scan says so for a moment, then closes.
		if gone_timer <= 0.0:
			gone_timer = 2.0
		gone_timer -= delta
		if gone_timer <= 0.0:
			_deselect()
		return
	# Where it is drawn: between its last two ticks, as the dish draws it, so
	# the camera, the reticle and the callouts glide with the cell instead of
	# hopping 15 times a second.
	last_pos = drawn_pos(info)


# Where a cell (a get_agent() dictionary) is drawn this frame: between its
# last two ticks, by the same fraction the dish uses. Anything that marks a
# cell (camera, reticle, brackets, tags) uses this, or it hops at 15 Hz.
func drawn_pos(info: Dictionary) -> Vector2:
	return (info.get("prev_position", info.position) as Vector2).lerp(info.position, clampf(acc / TICK, 0.0, 1.0))


func _select_at(world: Vector2) -> void:
	var found := sim.find_agent(world, 14.0 / cam.zoom.x)
	if found < 0:
		Audio.sfx("bubble", -15.0, randf_range(0.62, 0.72))
		_deselect()
		return
	if found != selected:
		Audio.sfx("ui_confirm", -12.0, 1.15)
	selected = found
	gone_timer = 0.0


func _deselect() -> void:
	selected = -1
	following = false


func _draw_overlay() -> void:
	iv.draw(overlay, cam.zoom.x)
	_draw_level_zones()
	var w := 1.5 / cam.zoom.x
	if mode != "" and not in_menu:
		# Placement preview at the cursor: rotating dashed ring + label.
		# Each tool shows its own reach, colour and words.
		var at := get_global_mouse_position()
		var r := 45.0
		var col := Color(0.45, 0.75, 0.42)
		var text := "投放营养"
		match mode:
			"release":
				r = RELEASE_RADIUS
				col = release_params.color
				text = "%s × %d" % [release_params.name, RELEASE_COUNT]
			"heat":
				r = 190.0
				col = Color(0.35, 0.65, 1.0) if iv.cold else Color(1.0, 0.55, 0.3)
				text = "降温 −12°C · 40 秒" if iv.cold else "升温 +12°C · 40 秒"
			"membrane":
				r = 12.0
				col = Ui.ACCENT
				text = "按住拖出隔离膜"
			"current":
				r = 12.0
				col = Color(0.3, 0.6, 0.95)
				text = "按住拖出洋流"
			"irritant":
				r = 30.0
				col = Color(0.86, 0.62, 0.2)
				text = "刺激头冠"
			"iron":
				r = 30.0
				col = Color(0.72, 0.36, 0.2)
				text = "撒铁粉"
			"stir":
				r = 30.0
				col = Color(0.62, 0.5, 0.32)
				text = "搅动泥层"
			"brine":
				r = 30.0
				col = Color(0.55, 0.78, 0.95)
				text = "撒盐"
		var spin := Time.get_ticks_msec() / 1000.0 * 0.8
		for k in 24:
			var a0 := spin + TAU * k / 24.0
			overlay.draw_arc(at, r, a0, a0 + TAU / 24.0 * 0.55, 4, Color(col, 0.9), w * 1.4, true)
		overlay.draw_circle(at, r, Color(col, 0.08))
		overlay.draw_circle(at, 3.0 / cam.zoom.x, col)
		# The label at a fixed 13 px on screen: drawn unscaled, then shrunk
		# by the zoom, so the glyphs stay sharp at any zoom.
		overlay.draw_set_transform(at + Vector2(r + 8.0 / cam.zoom.x, 0.0), 0.0, Vector2.ONE / cam.zoom.x)
		overlay.draw_string(Ui.sans(600), Vector2(0, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.INK)
		overlay.draw_set_transform(Vector2.ZERO)
	if not capsule.is_empty():
		_draw_capsule()


# A simulation field (one float per 16 px cell) at its own resolution; the
# dish shader smooths it with a cubic B-spline lookup. Floats matter: 8-bit
# steps of a smooth field land on the grid as squares. (Upscaling here on
# the CPU used to cost a 10 ms hitch every refresh.)
func _env_image() -> Image:
	var size := sim.get_grid_size()
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBAF, sim.get_env_field().to_byte_array())


# Analysis mode's environment map: 0 none, 1 temperature, 2 acidity, 3 signals,
# 4 oxygen (chapter 6: O2Layer draws it).
func set_env_layer(k: int) -> void:
	env_layer = k
	if k > 0 and not analyzing:
		set_analysis(true)
	hud_root.set_env_layer(k)


# View filter: normal -> species -> population heat -> normal.
func set_view_mode(m: int) -> void:
	view_mode = m
	(cells.material as ShaderMaterial).set_shader_parameter("view_mode", m)
	if m == 2:
		pop_img = _pop_image()
		pop_tex.update(pop_img)
	hud_root.set_view_mode(m)


func _pop_image() -> Image:
	var size := sim.get_grid_size()
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBAF, sim.get_population_field().to_byte_array())


# The menu's previews in the dish: the sandbox's scan field across it (the
# pointer uploads it), the stage's scales lighting up, the lamp dimming; and
# the dive's focus hunt.
func _update_previews(delta: float) -> void:
	var live: bool = in_menu and menu != null and menu.shown
	prev_scan = move_toward(prev_scan, 1.0 if live and menu_preview == 1 else 0.0, delta / 0.6)
	prev_stage = move_toward(prev_stage, 1.0 if live and menu_preview == 2 else 0.0, delta / 0.5)
	prev_dim = move_toward(prev_dim, 1.0 if live and menu_preview == 3 else 0.0, delta / 0.7)
	(medium.material as ShaderMaterial).set_shader_parameter("stage_glow", prev_stage * prev_stage * (3.0 - 2.0 * prev_stage))
	lens_mat.set_shader_parameter("dim", prev_dim * prev_dim * (3.0 - 2.0 * prev_dim))
	lens_mat.set_shader_parameter("defocus", defocus)


# A species picked out in the dish while its row in the HUD is hovered: its
# bodies light up and the rest steps back (organism shader, matched by hue).
func _update_focus_species(delta: float) -> void:
	var want := 1.0 if focus_species >= 0 and focus_species < colors.size() else 0.0
	if want == 0.0 and focus_amt <= 0.0:
		return
	var cm := cells.material as ShaderMaterial
	if want > 0.0:
		var c: Color = colors[focus_species]
		var tol := 0.045
		for j in colors.size():
			if j != focus_species:
				var dh := absf(colors[j].h - c.h)
				tol = minf(tol, minf(dh, 1.0 - dh) * 0.5)
		cm.set_shader_parameter("focus_col", c)
		cm.set_shader_parameter("focus_tol", maxf(tol, 0.012))
	focus_amt = move_toward(focus_amt, want, delta / (0.22 if want > 0.0 else 0.35))
	cm.set_shader_parameter("focus_amt", focus_amt * focus_amt * (3.0 - 2.0 * focus_amt))


# Look 2 on / off (F9, to compare while it is being judged).
func set_look2(on: bool) -> void:
	look2 = on
	var v := 1.0 if on else 0.0
	(medium.material as ShaderMaterial).set_shader_parameter("look2", v)
	(cells.material as ShaderMaterial).set_shader_parameter("look2", v)
	vignette.visible = on
	world_env.glow_enabled = on
	water_fx.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func _field_image(field: PackedFloat32Array) -> Image:
	var size := sim.get_grid_size()
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, field.to_byte_array())


func _upload(alpha: float) -> void:
	var n := sim.get_render_count()
	if n > CAPACITY:
		return
	cells.multimesh.buffer = sim.build_render_buffer(clampf(alpha, 0.0, 1.0), Time.get_ticks_msec() / 1000.0, CAPACITY)
	cells.multimesh.visible_instance_count = n


func focus(pos: Vector2, zoom: float) -> void:
	cam.position = pos
	cam.zoom = Vector2(zoom, zoom)
	goal_pos = pos
	goal_zoom = zoom
	glide = Vector2.ZERO


# --- dock tools ------------------------------------------------------------------

func dock_action(key: String) -> void:
	match key:
		"observe": set_observe(not observing)
		"nutrient", "membrane", "heat", "current", "phage", "irritant", "iron", "brine", "stir": iv.select(key)
		"track": toggle_track()
		"report": open_report()
		"designer": open_designer()
		"analysis": set_analysis(not analyzing)
		"filter": set_view_mode((view_mode + 1) % 3)


func set_analysis(on: bool) -> void:
	analyzing = on
	analysis.set_on(on)
	hud_root.set_analysis(on)


func set_observe(on: bool) -> void:
	observing = on
	hud_root.set_observe(on)


func set_mode(m: String) -> void:
	mode = m
	match m:
		"nutrient": hud_root.show_hint("左键点击投放营养　·　右键 / Esc 取消")
		"release": hud_root.show_hint("左键点击选择投放位置：%s × %d　·　右键 / Esc 取消" % [release_params.name, RELEASE_COUNT])
		_: hud_root.hide_hint()


# Track: follow the selection; with none, pick the organism nearest the
# middle of the view and close in on it.
func toggle_track() -> void:
	if following:
		following = false
		return
	if selected < 0:
		var found := sim.find_agent(cam.position, 400.0 / cam.zoom.x)
		if found < 0:
			return
		selected = found
		gone_timer = 0.0
	# Following is a close look: in near enough for the life scan.
	goal_zoom = maxf(goal_zoom, 3.2)
	following = true


func open_report() -> void:
	if report:
		report.close()
		return
	report = Report.new()
	report.setup(self, hud_root.history)
	report.closed.connect(func() -> void: report = null)
	ui_layer.add_child(report)


# A designed species comes back from the designer. In the game the player
# picks the spot; from the menu the experiment starts and it lands centre.
func begin_release(params: Dictionary) -> void:
	if level_runner and level_runner.phase == "design":
		level_runner.on_design(params) # a prediction first, then the level's spot
		return
	release_params = params
	if in_menu:
		# The pull-out already brought the camera over the landing spot.
		in_menu = false
		_do_release(DISH_CENTER + MENU_RELEASE_SPOT)
		hud_root.reveal()
	else:
		set_mode("release")


# Release (精修 L): the new species incubates in a holographic capsule seen
# from above. A laser draws its frame round the chosen spot (ring, ticks,
# lock-on brackets), a glass disc of medium fills in, and the embryos
# appear one by one in a sunflower spiral, each with a small flash, pulsing
# while the progress ring runs round. At CAPSULE_OPEN the disc irises open
# (blades sliding out), a pressure ring runs through the water and the
# embryos hatch: real cells spawn at exactly their spots and swell into
# shape (the kernel's newborn swell), and the frame is wiped away.
const CAPSULE_OPEN := 1.6
const CAPSULE_LEN := 2.5
const CAPSULE_BUILD := 0.42 # the laser's lap round the frame
const CAPSULE_BLADES := 7
var capsule := {}


func _do_release(pos: Vector2) -> void:
	var n := release_count
	var spots := PackedVector2Array()
	var rr := RELEASE_RADIUS * 0.74
	for k in n:
		var a := k * 2.39996 # the golden angle
		spots.append(pos + Vector2.from_angle(a) * rr * sqrt((k + 0.5) / n))
	capsule = {pos = pos, t = 0.0, params = release_params.duplicate(), opened = false, spots = spots, pops = 0}
	Audio.sfx("holo_on", -10.0, 1.1)
	set_mode("")


# When embryo k appears (seconds): from the middle outwards.
func _embryo_t(k: int, n: int) -> float:
	return CAPSULE_BUILD * 0.8 + (CAPSULE_OPEN - CAPSULE_BUILD - 0.35) * float(k) / maxf(n - 1.0, 1.0)


func _tick_capsule(delta: float) -> void:
	if capsule.is_empty():
		return
	capsule.t += delta
	# A soft tick as embryos appear (a few, not one per embryo).
	var shown := 0
	var spots: PackedVector2Array = capsule.spots
	for k in spots.size():
		if capsule.t >= _embryo_t(k, spots.size()):
			shown += 1
	if shown / 8 > capsule.pops:
		capsule.pops = shown / 8
		Audio.sfx("holo_tick", -18.0, 1.2 + 0.1 * capsule.pops)
	if not capsule.opened and capsule.t >= CAPSULE_OPEN:
		capsule.opened = true
		_open_capsule()
	if capsule.t >= CAPSULE_LEN:
		capsule = {}


func _open_capsule() -> void:
	var pos: Vector2 = capsule.pos
	var p: Dictionary = capsule.params.duplicate()
	var name: String = p.name
	p.erase("name")
	p.erase("extra")
	p.erase("designs")
	_species(p)
	var i := colors.size() - 1
	labels.append(name)
	# Each embryo hatches where it sat.
	for s: Vector2 in capsule.spots:
		sim.spawn(i, s, 1, 0.0)
	fx.release_burst(pos, p.color, RELEASE_RADIUS)
	Audio.sfx("release")
	hud_root.add_species_row(i)
	hud_root.notify("投放 %s × %d" % [name, release_count], p.color, pos)
	if level_runner:
		level_runner.on_released(i)


# The level's target areas on the dish (playtest review: "看不出该往哪走"):
# 1-1's light zone, 1-5's patches A/B/C with their scores (you : rival).
func _draw_level_zones() -> void:
	if level_runner == null or in_menu or level_runner.phase != "run":
		return
	var g: Dictionary = level_runner.level.goal
	var zs := []
	if g.kind == "zone_count":
		zs.append([g.zone, g.get("zone_name", "光照区（目标）"), ""])
	elif g.kind == "patches":
		var ev: LevelEval = level_runner.eval
		for k in g.patches.size():
			var pc: Array = ev.patch_counts[k] if ev and k < ev.patch_counts.size() else [0, 0]
			var lead: bool = pc[0] > pc[1] and pc[0] >= 3
			zs.append([g.patches[k], "藻场 %s" % "ABC"[k], "%d : %d%s" % [pc[0], pc[1], "  占优" if lead else ""]])
	var w := 1.5 / cam.zoom.x
	var t := Time.get_ticks_msec() / 1000.0
	for z: Array in zs:
		var c: Vector2 = z[0].center
		var r: float = z[0].radius
		var col := Color(0.12, 0.6, 0.72)
		var n := 48
		for k in n:
			var a0 := t * 0.05 + TAU * k / n
			overlay.draw_arc(c, r, a0, a0 + TAU / n * 0.5, 3, Color(col, 0.55), w * 1.6, true)
		# The label at a fixed size on screen, in the middle of the area
		# (above the ring it hid under the top panels).
		overlay.draw_set_transform(c, 0.0, Vector2.ONE / cam.zoom.x)
		var f := Ui.sans(700)
		var tw := f.get_string_size(z[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		overlay.draw_string(f, Vector2(-tw * 0.5, -18), z[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.05, 0.35, 0.45))
		if z[2] != "":
			var m := Ui.mono("SemiBold")
			var sw := m.get_string_size(z[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			overlay.draw_string(m, Vector2(-sw * 0.5, 0), z[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ui.ACCENT if z[2].contains("占优") else Ui.INK_SOFT)
		overlay.draw_set_transform(Vector2.ZERO)
		# Off screen: an arrow at the edge of the clear middle of the screen
		# (inside the HUD panels), pointing at it.
		var view := _visible_world()
		var vs := get_viewport().get_visible_rect().size
		var safe := Rect2(vs * Vector2(0.24, 0.15), vs * Vector2(0.52, 0.72)) # screen px
		var to_world := get_viewport().get_canvas_transform().affine_inverse()
		var inner := Rect2(to_world * safe.position, safe.size / cam.zoom.x)
		if not view.grow(-20.0 / cam.zoom.x).has_point(c) and inner.size.x > 0.0:
			var from := inner.get_center()
			var dir := (c - from).normalized()
			var tmax := INF
			for axis in 2:
				if absf(dir[axis]) > 1e-4:
					var edge: float = (inner.end[axis] if dir[axis] > 0.0 else inner.position[axis])
					tmax = minf(tmax, (edge - from[axis]) / dir[axis])
			var p := from + dir * tmax
			# Looking closely at something (5-2's embryos), it gets out of the way.
			var close := 1.0 - smoothstep(8.0, 13.0, cam.zoom.x)
			overlay.draw_set_transform(p, dir.angle(), Vector2.ONE / cam.zoom.x)
			var pulse := 0.6 + 0.4 * sin(t * 4.0)
			overlay.draw_colored_polygon(PackedVector2Array([Vector2(26, 0), Vector2(-8, -16), Vector2(0, 0), Vector2(-8, 16)]), Color(col, (0.55 + 0.35 * pulse) * close))
			overlay.draw_set_transform(p - dir * 46.0 / cam.zoom.x, 0.0, Vector2.ONE / cam.zoom.x)
			var lf := Ui.sans(700)
			var lw := lf.get_string_size(z[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			overlay.draw_string(lf, Vector2(-lw * 0.5, 5), z[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.05, 0.35, 0.45, close))
			overlay.draw_set_transform(Vector2.ZERO)


# A designed species straight into the dish (level 8's second species, when
# the first one's capsule opens): no capsule of its own.
func release_now(params: Dictionary, pos: Vector2, count: int) -> int:
	var p := params.duplicate()
	var name: String = p.get("name", "设计物种")
	p.erase("name")
	p.erase("extra")
	p.erase("designs")
	_species(p)
	var i := colors.size() - 1
	labels.append(name)
	# (A level may keep them closer, as it was calibrated: level 19's first drop
	# has to reach them all.)
	var spread: float = level_runner.level.release.get("spread", RELEASE_RADIUS * 0.74) if level_runner else RELEASE_RADIUS * 0.74
	sim.spawn(i, pos, count, spread)
	fx.release_burst(pos, p.color, RELEASE_RADIUS)
	hud_root.add_species_row(i)
	hud_root.notify("投放 %s × %d" % [name, count], p.color, pos)
	return i


func _draw_capsule() -> void:
	var c: Vector2 = capsule.pos
	var t: float = capsule.t
	var col: Color = capsule.params.color
	var px := 1.0 / cam.zoom.x # one screen pixel in world units
	var ink := Color(0.03, 0.42, 0.52)
	var glo := Color(0.1, 0.78, 0.9)
	var r_in := RELEASE_RADIUS * 0.92 # the glass disc
	var r_out := RELEASE_RADIUS * 1.1 # the frame ring
	var open := _ease_io(clampf((t - CAPSULE_OPEN) / 0.45, 0.0, 1.0))
	var wipe := _ease_io(clampf((t - CAPSULE_OPEN - 0.25) / 0.55, 0.0, 1.0))
	var build := clampf(t / CAPSULE_BUILD, 0.0, 1.0)
	var prog := clampf((t - CAPSULE_BUILD) / (CAPSULE_OPEN - CAPSULE_BUILD), 0.0, 1.0)
	var a0 := -PI * 0.5
	# The frame: drawn by the laser (a lap from the top, clockwise), wiped
	# away the same way after the opening.
	var f0 := a0 + TAU * wipe
	var f1 := a0 + TAU * build
	if f1 > f0 + 0.01:
		overlay.draw_arc(c, r_out, f0, f1, 96, Color(glo, 0.18), 6.0 * px, true)
		overlay.draw_arc(c, r_out, f0, f1, 96, Color(ink, 0.9), 1.4 * px, true)
		overlay.draw_arc(c, r_out + 9.0 * px, f0, f1, 96, Color(ink, 0.35), 1.0 * px, true)
		# Ticks every 5°, long every 30°, numbered in tens of degrees.
		for k in 72:
			var a := a0 + TAU * k / 72.0
			if a < f0 or a > f1:
				continue
			var d := Vector2.from_angle(a)
			var long := k % 6 == 0
			var l := (7.0 if long else 3.5) * px
			overlay.draw_line(c + d * (r_out + 2.0 * px), c + d * (r_out + 2.0 * px + l), Color(ink, 0.8 if long else 0.45), (1.3 if long else 1.0) * px, true)
	if build < 1.0:
		# The laser head and its glow.
		var hp := c + Vector2.from_angle(f1) * r_out
		overlay.draw_circle(hp, 7.0 * px, Color(glo, 0.25))
		overlay.draw_circle(hp, 2.6 * px, Color(1, 1, 1, 0.95))
		overlay.draw_line(hp, c, Color(glo, 0.25 * (1.0 - build)), 1.0 * px, true)
	var frame_a := 1.0 - wipe
	# Lock-on brackets closing in on the frame.
	var lock := _ease_io(clampf(t / 0.35, 0.0, 1.0))
	var hb := r_out * lerpf(1.7, 1.2, lock)
	for q in 4:
		var sx := -1.0 if q % 3 == 0 else 1.0
		var sy := -1.0 if q < 2 else 1.0
		var corner := c + Vector2(sx, sy) * hb
		var bl := 12.0 * px
		var bc := Color(ink, 0.85 * lock * frame_a)
		overlay.draw_line(corner, corner - Vector2(sx * bl, 0), bc, 1.6 * px)
		overlay.draw_line(corner, corner - Vector2(0, sy * bl), bc, 1.6 * px)
	# The glass disc of medium: fills in behind the laser, a rim with a lamp
	# highlight, a slow dashed ring, a fine cross. It irises open in blades.
	var fill := _ease_io(clampf((t - CAPSULE_BUILD * 0.5) / 0.4, 0.0, 1.0))
	if open < 1.0 and fill > 0.0:
		for b in CAPSULE_BLADES:
			var b0 := a0 + TAU * b / CAPSULE_BLADES + open * 0.5
			var b1 := b0 + TAU / CAPSULE_BLADES * (1.0 - 0.55 * open)
			var push := Vector2.from_angle((b0 + b1) * 0.5) * open * r_in * 0.45
			var ra := (1.0 - open) * fill
			var pts := PackedVector2Array([c + push])
			for s in 13:
				pts.append(c + push + Vector2.from_angle(lerpf(b0, b1, s / 12.0)) * r_in * (1.0 - 0.2 * open))
			overlay.draw_colored_polygon(pts, Color(0.92, 0.98, 1.0, 0.3 * ra))
			overlay.draw_polyline(pts.slice(1), Color(ink, 0.75 * ra), 1.2 * px, true)
			if open > 0.0:
				overlay.draw_line(pts[0], pts[1], Color(ink, 0.5 * ra), 1.0 * px, true)
				overlay.draw_line(pts[0], pts[pts.size() - 1], Color(ink, 0.5 * ra), 1.0 * px, true)
		var ga := fill * (1.0 - open)
		overlay.draw_arc(c, r_in - 3.0 * px, PI * 1.05, PI * 1.45, 24, Color(1, 1, 1, 0.9 * ga), 2.4 * px, true)
		var spin := t * 0.6
		for k in 24:
			var a := spin + TAU * k / 24.0
			overlay.draw_arc(c, r_in * 1.04, a, a + TAU / 24.0 * 0.5, 4, Color(ink, 0.4 * ga), 1.0 * px, true)
		for d in [Vector2(1, 0), Vector2(0, 1)]:
			overlay.draw_line(c - d * r_in * 0.96, c - d * r_in * 0.12, Color(ink, 0.18 * ga), 1.0 * px)
			overlay.draw_line(c + d * r_in * 0.12, c + d * r_in * 0.96, Color(ink, 0.18 * ga), 1.0 * px)
		# A scan line rocking across the disc while it incubates.
		if prog > 0.0 and prog < 1.0:
			var sy := sin(t * 2.6) * r_in * 0.85
			var half := sqrt(maxf(r_in * r_in - sy * sy, 0.0))
			overlay.draw_line(c + Vector2(-half, sy), c + Vector2(half, sy), Color(glo, 0.5 * ga), 1.2 * px, true)
			overlay.draw_line(c + Vector2(-half, sy), c + Vector2(half, sy), Color(glo, 0.12 * ga), 7.0 * px, true)
	# The embryos: round, translucent, a nucleus and a couple of granules,
	# pulsing; each arrives with a flash ring. They hatch at the opening.
	var spots: PackedVector2Array = capsule.spots
	var er: float = float(capsule.params.get("radius", 6.0)) * 0.62
	var dark := col.darkened(0.25)
	for k in spots.size():
		var since := t - _embryo_t(k, spots.size())
		if since < 0.0:
			continue
		var grow := 1.0 - exp(-9.0 * since) * cos(since * 14.0) # a little overshoot
		var ea := clampf(since / 0.12, 0.0, 1.0) * (1.0 - smoothstep(0.0, 0.12, t - CAPSULE_OPEN))
		if ea <= 0.0:
			continue
		var h := fposmod(sin(k * 12.9898) * 43758.5453, 1.0)
		var p := spots[k] + Vector2(sin(t * 1.3 + h * 9.0), cos(t * 1.1 + h * 7.0)) * 0.8
		var r := er * grow * (1.0 + 0.05 * sin(t * 3.0 + h * 6.0))
		overlay.draw_circle(p, r * 1.6, Color(col, 0.08 * ea))
		overlay.draw_circle(p, r, Color(col.lightened(0.55), 0.38 * ea))
		overlay.draw_arc(p, r, 0.0, TAU, 20, Color(dark, 0.75 * ea), 1.0 * px, true)
		overlay.draw_arc(p, r * 0.82, 0.0, TAU, 20, Color(dark, 0.18 * ea), 0.8 * px, true)
		overlay.draw_circle(p + Vector2(-0.18, -0.1) * r, r * 0.3, Color(dark, 0.32 * ea))
		overlay.draw_circle(p + Vector2(0.3, 0.32) * r, r * 0.1, Color(col.darkened(0.1), 0.6 * ea))
		overlay.draw_circle(p + Vector2(0.36, -0.3) * r, r * 0.1, Color(1, 1, 1, 0.85 * ea))
		if since < 0.35:
			var fl := since / 0.35
			overlay.draw_arc(p, r * (1.2 + 1.6 * fl), 0.0, TAU, 20, Color(glo, 0.8 * (1.0 - fl)), 1.2 * px, true)
	# The progress ring, just inside the frame.
	if prog > 0.0 and frame_a > 0.0:
		var pr := r_out - 5.0 * px
		overlay.draw_arc(c, pr, a0, a0 + TAU, 96, Color(ink, 0.12 * frame_a), 3.0 * px, true)
		overlay.draw_arc(c, pr, a0, a0 + TAU * prog, 96, Color(Ui.ACCENT, 0.95 * frame_a), 3.0 * px, true)
		var tipp := c + Vector2.from_angle(a0 + TAU * prog) * pr
		overlay.draw_circle(tipp, 3.2 * px, Color(1, 1, 1, frame_a))
	# Readout at a fixed screen size, on a leader off the upper right.
	var la := clampf((t - 0.25) / 0.2, 0.0, 1.0) * frame_a
	if la > 0.0:
		var anchor := c + Vector2.from_angle(-PI * 0.25) * r_out
		var elbow := anchor + Vector2(18.0, -18.0) * px
		var endp := elbow + Vector2(150.0, 0.0) * px
		overlay.draw_line(anchor, elbow, Color(ink, 0.7 * la), 1.0 * px, true)
		overlay.draw_line(elbow, endp, Color(ink, 0.7 * la), 1.0 * px, true)
		overlay.draw_circle(anchor, 2.4 * px, Color(Ui.ACCENT, la))
		overlay.draw_set_transform(elbow, 0.0, Vector2.ONE * px)
		var head := "INCUBATION  %3d%%" % int(prog * 100.0) if not capsule.opened else "RELEASE"
		overlay.draw_string(Ui.mono("Medium"), Vector2(2, -6), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ui.ACCENT, la))
		var shown := 0
		for k in spots.size():
			if t >= _embryo_t(k, spots.size()):
				shown += 1
		var line := "%s  ·  %d / %d" % [capsule.params.name, shown, spots.size()] if not capsule.opened else "%s × %d  已释放" % [capsule.params.name, spots.size()]
		overlay.draw_string(Ui.sans(700), Vector2(2, 18), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Ui.INK, la))
		overlay.draw_set_transform(Vector2.ZERO)


static func _ease_io(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# Zone names over the water when the camera pulls back (macro tier), with a
# faint dashed rim where the zone's water gives way.
func _update_zone_labels() -> void:
	var a := 0.0 if in_menu else 1.0 - smoothstep(0.55, 0.9, cam.zoom.x)
	zone_labels.visible = a > 0.01
	zone_labels.modulate.a = a
	if zone_labels.visible and absf(cam.zoom.x - _zone_zoom) > _zone_zoom * 0.03:
		_zone_zoom = cam.zoom.x
		zone_labels.queue_redraw()


func _draw_zone_labels() -> void:
	if _zone_zoom <= 0.0:
		return # not placed yet
	var a := 1.0
	var z := _zone_zoom
	var overlay := zone_labels
	for zone: Dictionary in layout.zones:
		var c: Vector2 = zone.center
		var r: float = zone.radius * 0.78
		var col: Color = Color(zone.tint.darkened(0.45), 0.55 * a)
		for k in 48:
			var a0 := TAU * k / 48.0
			overlay.draw_arc(c, r, a0, a0 + TAU / 48.0 * 0.5, 3, col, 1.4 / z)
		var env: Dictionary = sim.get_env_at(c)
		var at := c + Vector2(0.0, -r - 34.0 / z)
		var w := 220.0 / z
		overlay.draw_string(Ui.sans(700), at - Vector2(w * 0.5, 0.0), zone.name, HORIZONTAL_ALIGNMENT_CENTER, w, int(maxf(17.0 / z, 1.0)), Color(Ui.INK, a))
		var sub := "%s  ·  %d°C%s" % [zone.en, roundi(env.temp), "  ·  pH %.1f" % (7.0 - 4.0 * float(env.acid)) if env.acid > 0.2 else ""]
		overlay.draw_string(Ui.mono("Medium"), at + Vector2(-w * 0.5, 18.0 / z), sub, HORIZONTAL_ALIGNMENT_CENTER, w, int(maxf(11.0 / z, 1.0)), Color(Ui.INK_SOFT, a))


# WASD / arrow keys pan, Q / E zoom out / in. Speed is in screen pixels, so
# it feels the same at every zoom.
func _keyboard_pan(delta: float) -> void:
	if in_menu or cine or designer or report:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		d.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		d.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		d.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		d.y += 1.0
	if d != Vector2.ZERO:
		following = false
		glide = Vector2.ZERO
		goal_pos += d.normalized() * PAN_SPEED * delta / goal_zoom
	if Input.is_key_pressed(KEY_Q):
		goal_zoom = clampf(goal_zoom * exp(-1.6 * delta), 0.3, zoom_max)
	if Input.is_key_pressed(KEY_E):
		goal_zoom = clampf(goal_zoom * exp(1.6 * delta), 0.3, zoom_max)


# Minimap: jump the camera to a point of the dish (keeps the zoom).
func jump_to(pos: Vector2) -> void:
	following = false
	glide = Vector2.ZERO
	goal_pos = _clamp_to_dish(pos)


# The camera flies to a point of interest (event log clicks).
# "定位" in the log: open the organism itself - fly in, select and follow it,
# bring up its life scan, and say what is different about it. If it has died,
# a living member of the same lineage (else of the species) stands in.
func inspect(agent_id: int, lineage := -1, species := -1, pos := Vector2.INF) -> void:
	var info: Dictionary = sim.get_agent(agent_id) if agent_id >= 0 else {}
	if info.is_empty() and species >= 0:
		var best := INF
		for p: Vector2 in sim.get_positions(species):
			var id := sim.find_agent(p, 1.0)
			var a: Dictionary = sim.get_agent(id)
			if a.is_empty():
				continue
			var d := p.distance_squared_to(pos) if pos.is_finite() else 0.0
			if lineage >= 0 and a.lineage == lineage:
				d -= 1e12 # same lineage first
			if d < best:
				best = d
				info = a
	if info.is_empty():
		look_at_point(pos)
		if pos.is_finite():
			hud_root.notify("这个谱系已经没有活着的个体了", Ui.WARN)
		return
	selected = info.id
	gone_timer = 0.0
	following = false
	var z := clampf(60.0 / float(info.radius), 3.0, 8.0)
	var tw := fly_to(info.position, z, 0.9)
	tw.finished.connect(func() -> void:
		if selected == info.id:
			following = true)
	var diff := mutation_text(info)
	if diff != "":
		hud_root.notify("%s · 谱系 #%d 和祖先相比：%s" % [labels[int(info.species)], int(info.lineage), diff], Color(1.0, 0.72, 0.25), info.position)


# How an organism differs from its species' founders (what the player
# designed), one line per change, saying where (which chromosome and gene, or
# which rule card) and what it was and is now. After the playtest: "write it
# clearly: what mutation, where exactly, what was it, what is it now".
func mutation_list(info: Dictionary, short := false) -> Array[String]:
	var out: Array[String] = []
	var s: int = info.species
	if s >= species_genes.size():
		return out
	var base: Array = species_genes[s]
	var names := ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]
	var g: PackedFloat32Array = info.genes
	for k in mini(g.size(), base.size()):
		var was := float(base[k])
		var now := float(g[k])
		if absf(now - was) >= 0.02:
			if short:
				out.append("%d 号染色体%s基因 %.2f→%.2f" % [k + 1, names[k], was, now])
			else:
				out.append("第 %d 号染色体 · %s基因：%.2f → %.2f（%s%.2f）" % [k + 1, names[k], was, now, "+" if now > was else "−", absf(now - was)])
	if s < species_topt.size():
		var was_t: float = species_topt[s]
		var now_t := float(info.get("temp_opt", was_t))
		if absf(now_t - was_t) >= 0.5:
			out.append(("8 号染色体最适水温 %d→%d°C" if short else "第 8 号染色体 · 耐温基因的最适水温：%d°C → %d°C") % [roundi(was_t), roundi(now_t)])
	if s < species_deck.size() and info.has("deck"):
		# Cards compared as a set (a deleted card shifts the rest). A card
		# lost and one gained with the same conditions is one card that
		# changed (its threshold or its action).
		var key := func(cd: Dictionary) -> String:
			return "%d|%.2f|%d|%.2f|%d" % [int(cd.get("c1", 0)), float(cd.get("t1", 0.0)), int(cd.get("c2", 0)), float(cd.get("t2", 0.0)), int(cd.get("act", 0))]
		var shape := func(cd: Dictionary) -> String:
			return "%d|%d" % [int(cd.get("c1", 0)), int(cd.get("c2", 0))]
		var mine: Array = info.deck
		var old: Array = species_deck[s]
		var mine_keys := mine.map(key)
		var old_keys := old.map(key)
		var lost: Array = []
		var gained: Array = []
		for k in old.size():
			if not mine_keys.has(old_keys[k]):
				lost.append(old[k])
		for k in mine.size():
			if not old_keys.has(mine_keys[k]):
				gained.append(mine[k])
		for l: Dictionary in lost.duplicate():
			for n: Dictionary in gained:
				if shape.call(l) == shape.call(n):
					out.append(("规则卡改成「%s」" % Rules.card_text(n)) if short else ("行为规则卡「%s」变成了「%s」" % [Rules.card_text(l), Rules.card_text(n)]))
					lost.erase(l)
					gained.erase(n)
					break
		for l: Dictionary in lost:
			out.append(("删了规则卡「%s」" if short else "行为规则卡「%s」被删掉了") % Rules.card_text(l))
		for n: Dictionary in gained:
			out.append(("多了规则卡「%s」" if short else "多出一张行为规则卡「%s」") % Rules.card_text(n))
	return out


func mutation_text(info: Dictionary) -> String:
	var l := mutation_list(info)
	return "；".join(l) if not l.is_empty() else "与祖先几乎相同"


func look_at_point(pos: Vector2) -> void:
	if not pos.is_finite():
		return
	following = false
	fly_to(pos, maxf(cam.zoom.x, 1.5), 0.9)


# Where a mouse event happened, in the world (the event's own position, so
# it is exact even when the OS cursor has moved on).
func _event_world(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


func _zoom_at(screen: Vector2, factor: float) -> void:
	# Keep the world point under the cursor where it is.
	var view := get_viewport().get_visible_rect().size
	var before := goal_pos + (screen - view * 0.5) / goal_zoom
	goal_zoom = clampf(goal_zoom * factor, 0.3, zoom_max)
	if not following:
		goal_pos = before - (screen - view * 0.5) / goal_zoom


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_QUOTELEFT 			and not (get_viewport().gui_get_focus_owner() is LineEdit):
		toggle_dev(k.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if k and k.pressed and not k.echo and k.keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()


# Developer mode (scripts/dev_mode.gd): ` turns the mode itself on and off
# (2026-10-30: "按一次是开，按一次是关，而不是一直弹出来"): on asks for the
# passcode once per run and opens the panel; off goes back to the real save
# and closes it. Esc only hides the panel; Shift+` brings it back while the
# mode is on. The timings overlay lives beside it.
var dev_panel: CanvasLayer
var dev_prompt: CanvasLayer
var dev_overlay: CanvasLayer


func toggle_dev(panel_only := false) -> void:
	if is_instance_valid(dev_prompt):
		return # the prompt handles ` itself (cancel)
	if DevMode.active and panel_only:
		if is_instance_valid(dev_panel):
			dev_panel.close()
		else:
			_open_dev_panel()
		return
	if DevMode.active:
		_dev_off()
		return
	if not DevMode.auth:
		dev_prompt = preload("res://scripts/ui/dev_prompt.gd").new()
		dev_prompt.host = self
		dev_prompt.unlocked.connect(func() -> void:
			DevMode.auth = true
			_open_dev_panel())
		add_child(dev_prompt)
		return
	_open_dev_panel()


func _dev_off() -> void:
	DevMode.set_active(false)
	if campaign and campaign.visible:
		campaign.research_label.text = "研究点  %d" % CampaignSave.research()
		campaign._select(campaign.selected, true)
	if designer:
		designer._enforce_rules()
		designer._update_pieces()
		designer._refresh()
	if is_instance_valid(dev_panel):
		dev_panel.close()
	Audio.sfx("ui_click", -6.0)


func _open_dev_panel() -> void:
	DevMode.set_active(true)
	if campaign and campaign.visible:
		campaign.research_label.text = "研究点  %d" % CampaignSave.research()
		campaign._select(campaign.selected, true)
	if not is_instance_valid(dev_overlay):
		dev_overlay = preload("res://scripts/ui/dev_overlay.gd").new()
		dev_overlay.host = self
		add_child(dev_overlay)
	dev_panel = preload("res://scripts/ui/dev_panel.gd").new()
	dev_panel.host = self
	add_child(dev_panel)


func _unhandled_input(event: InputEvent) -> void:
	if in_menu or cine or is_instance_valid(pause_menu):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# A click inspects; a drag pans.
			if mb.pressed:
				left_down = true
				left_dragged = false
				left_from = mb.position
				pointer.pressed()
				glide = Vector2.ZERO
				if iv.drags(mode):
					iv.begin_drag(_event_world(mb.position))
			else:
				if iv.drags(mode):
					iv.finish_drag()
				elif left_down and not left_dragged:
					var at := _event_world(mb.position)
					pointer.click(mb.position)
					if mode in ["nutrient", "heat", "phage", "irritant", "iron", "brine", "stir"]:
						iv.place(mode, at)
					elif mode == "release":
						_do_release(at)
					else:
						_select_at(at)
				left_down = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# Right drag pans; a right click (no movement) drops nutrient or
			# cancels a pending placement.
			if mb.pressed:
				right_down = true
				right_dragged = false
				right_from = mb.position
				glide = Vector2.ZERO
			else:
				if right_down and not right_dragged:
					if mode != "":
						iv.drag_from = Vector2.INF
						set_mode("")
					else:
						iv.place("nutrient", _event_world(mb.position))
				right_down = false
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
			if mb.pressed:
				glide = Vector2.ZERO
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		pointer.moved(mm.relative, get_process_delta_time())
		if left_down and not left_dragged and mm.position.distance_to(left_from) > DRAG_THRESHOLD:
			left_dragged = true
			following = false
		if right_down and not right_dragged and mm.position.distance_to(right_from) > DRAG_THRESHOLD:
			right_dragged = true
			following = false
		if left_down and iv.drags(mode):
			iv.update_drag(_event_world(mm.position))
		elif dragging or (left_down and left_dragged) or (right_down and right_dragged):
			# The view tracks the hand exactly; the release velocity glides on.
			var move := -mm.relative / cam.zoom
			goal_pos += move
			cam.position += move
			glide = glide.lerp(move / maxf(get_process_delta_time(), 1.0 / 240.0), 0.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		# Rebindable actions first (Keys; settings can change them).
		hud_root.ping_action(Keys.action_of(key))
		match Keys.action_of(key):
			"pause": paused = not paused
			"step": step_once()
			"slower": step_speed(-1)
			"faster": step_speed(1)
			"nutrient", "membrane", "heat", "current", "phage": iv.select(Keys.action_of(key))
			"track": toggle_track()
			"designer": open_designer()
			"observe": set_observe(not observing)
			"analysis": set_analysis(not analyzing)
			"env_layer": set_env_layer((env_layer + 1) % (5 if o2_world else 4))
			"filter": set_view_mode((view_mode + 1) % 3)
			"report": open_report()
		match key:
			KEY_F1:
				goal_pos = DISH_CENTER
				goal_zoom = 0.48
			KEY_F9:
				set_look2(not look2)
			KEY_ESCAPE:
				if mode != "":
					iv.drag_from = Vector2.INF
					set_mode("")
				elif observing:
					set_observe(false)
				elif selected >= 0:
					_deselect()
				elif designer == null and (level_runner == null or level_runner.phase in ["run", "design"]):
					# (Before the release too: the way back to the designer,
					# or out of the level, must never be missing.)
					open_pause_menu()
