class_name Worlds
extends RefCounted
# World configurations: everything a dish starts with, as data, so the sandbox
# and every campaign level are built by the same code (showcase.build_world)
# and can be swapped in place with no loading.
#
#   name          shown in the HUD header
#   layout        Ecology layout: base environment + zones (may have none)
#   natives       true: add the layout's native species (data/natives_*.json)
#   lights        [[centre, radius, strength], ...]
#   algae_cap     algae clump cap; algae_seed = [count, energy each];
#                 algae_dark how often clumps settle out of the light (0.02)
#   algae_rates   [growth, rot] multipliers (default [1, 1])
#   algae_tough   0..1: share of an algae bite locked behind digestive enzyme (level 13)
#   species       [{label, params (SimCore.add_species), spawn: [[pos, n, spread]]}]
#                 or {native = "冰晶游丝", spawn, override?}: one of the Europa
#                 natives (override: params a level changes)
#                 role: chapter 6, a species the player designed earlier
#                 (CampaignSave.look: their name and colour, the level's numbers)
#   light_band    [y_full, y_dark, power]: light from above (chapter 6)
#   oxygen        SimCore.set_oxygen params (chapter 6)
#   walls         [[a, b], ...]: ice nothing crosses or sees through (chapter 7)
#   divide_min_temp  colder water than this, no dividing (chapter 7)

const AQUA := Color(0.42, 0.8, 0.88)
const HONEY := Color(0.96, 0.76, 0.4)
const ROSE := Color(0.95, 0.5, 0.6)
const LAVENDER := Color(0.64, 0.58, 0.98)

const BEAST_BODY := [
	Vector3(0, 0, 0),
	Vector3(1, 0, 3), Vector3(1.5, 0.87, 4), Vector3(1.5, -0.87, 4),
	Vector3(0.5, 0.87, 2), Vector3(0.5, -0.87, 2),
	Vector3(-0.5, 0.87, 5), Vector3(-0.5, -0.87, 5), Vector3(-1, 0, 5),
	Vector3(-1.5, 0.87, 1), Vector3(-1.5, -0.87, 1), Vector3(-2, 0, 1),
]

# A dish with no zones: mild open water.
const OPEN_WATER := {
	name = "木卫二 · 冰下海洋样本",
	code = "EUR-00",
	base = {temp = 12.0, acid = 0.03, radiation = 0.05},
	zones = [],
}


# The sandbox: the Europa sample with its zones, four sample species and
# the natives evolved in each zone.
static func sandbox() -> Dictionary:
	return {
		name = "木卫二冰下海洋样本",
		layout = Ecology.EUROPA_SAMPLE,
		natives = true,
		lights = [[Vector2(700, 700), 380.0, 0.5], [Vector2(1500, 650), 340.0, 0.4],
			[Vector2(1550, 1450), 420.0, 0.55], [Vector2(750, 1500), 380.0, 0.45],
			[Vector2(1100, 1100), 380.0, 0.6], [Vector2(1100, 450), 300.0, 0.45]],
		algae_cap = 1500,
		algae_seed = [800, 22.0],
		species = [
			# The dish's own wanderers: open-water species, the hunters broader
			# in the temperatures they bear (they roam every zone).
			{label = "银尘", params = {color = AQUA, radius = 5.5, speed = 1.9, vision = 2.6, armor = 1.4,
				attack = 1.0, fertility = 3.2, efficiency = 3.0, lifespan = 80.0, cohesion = 0.7, temp_tol = 2.5},
				spawn = [[Vector2(1000, 900), 180, 220.0], [Vector2(1150, 1350), 140, 200.0]]},
			{label = "琥珀", params = {color = HONEY, radius = 6.5, speed = 1.6, vision = 2.2, armor = 2.2,
				attack = 1.0, fertility = 2.6, efficiency = 3.4, lifespan = 110.0, cohesion = 0.25, temp_tol = 3.0},
				spawn = [[Vector2(1500, 700), 150, 220.0], [Vector2(1200, 1050), 80, 180.0]]},
			{label = "猎手", params = {color = ROSE, diet = 1, radius = 10.0, speed = 2.8, vision = 3.2,
				armor = 2.0, attack = 3.6, fertility = 1.3, efficiency = 2.6, lifespan = 140.0, temp_tol = 3.5},
				spawn = [[Vector2(1100, 1100), 16, 500.0]]},
			{label = "巨兽", params = {color = LAVENDER, diet = 1, radius = 36.0, speed = 2.0, vision = 4.0,
				armor = 4.0, attack = 4.0, fertility = 0.6, efficiency = 3.0, lifespan = 900.0, temp_tol = 4.0,
				body = PackedVector3Array(BEAST_BODY)},
				spawn = [[Vector2(1100, 600), 2, 100.0], [Vector2(900, 1300), 2, 100.0]]},
		],
	}


# One of the Europa sample's natives (evolved in its zone), as species params.
static func native(name: String) -> Dictionary:
	for p: Dictionary in Natives.load_for(Ecology.EUROPA_SAMPLE):
		if p.name == name:
			var params := p.duplicate()
			for k in ["name", "zone", "home", "niche", "count"]:
				params.erase(k)
			return params
	push_error("no native called " + name)
	return {}


# Builds a world into `sim`. `on_species(params, label)` must add the species
# to the sim (the showcase also records colours and names); spawning follows.
static func populate(sim: SimCore, cfg: Dictionary, on_species: Callable) -> void:
	var layout: Dictionary = cfg.get("layout", OPEN_WATER)
	for spot: Array in cfg.get("lights", []):
		sim.add_light(spot[0], spot[1], spot[2])
	if cfg.has("light_band"):
		sim.add_light_band(cfg.light_band[0], cfg.light_band[1], cfg.light_band[2])
	sim.set_algae_cap(int(cfg.get("algae_cap", 1500)))
	var rates: Array = cfg.get("algae_rates", [1.0, 1.0]) # [growth, rot] multipliers
	sim.set_algae_rates(float(rates[0]), float(rates[1]))
	# Level 13: tough algae, worth eating in full only where enzyme is thick.
	sim.set_algae_tough(float(cfg.get("algae_tough", 0.0)))
	var seed_cfg: Array = cfg.get("algae_seed", [0, 22.0])
	if int(seed_cfg[0]) > 0:
		sim.seed_algae(int(seed_cfg[0]), float(seed_cfg[1]), float(cfg.get("algae_dark", 0.02)))
	var n := 0
	for sp: Dictionary in cfg.get("species", []):
		if sp.has("native"):
			var params := native(sp.native)
			params.merge(sp.get("override", {}), true) # a level's handicap
			on_species.call(params, sp.native)
		elif sp.has("role") and not CampaignSave.look(sp.role).is_empty():
			var lk := CampaignSave.look(sp.role)
			var params: Dictionary = sp.params.duplicate()
			params.name = lk.name
			params.color = lk.color
			on_species.call(params, lk.name)
		else:
			on_species.call(sp.params, sp.label)
		for at: Array in sp.get("spawn", []):
			sim.spawn(n, at[0], at[1], at[2])
		n += 1
	# The water: the zones, and the natives evolved in them.
	Ecology.apply(sim, layout)
	if cfg.has("oxygen"):
		sim.set_oxygen(cfg.oxygen)
	for pa: Array in cfg.get("algae_patches", []): # [[pos, radius, n, each]]: ready-grown food
		sim.add_algae_patch(pa[0], float(pa[1]), int(pa[2]), float(pa[3]))
	for w: Array in cfg.get("walls", []):
		sim.add_wall(w[0], w[1])
	if cfg.has("divide_min_temp"):
		sim.set_divide_min_temp(float(cfg.divide_min_temp))
	if cfg.get("natives", false):
		for p: Dictionary in Natives.load_for(layout):
			var params := p.duplicate()
			for k in ["name", "zone", "home", "niche", "count"]:
				params.erase(k)
			on_species.call(params, p.name)
			sim.spawn(n, p.home, p.count, 300.0 if p.niche == "chemo" else 150.0)
			n += 1

