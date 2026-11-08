class_name SandboxWorld
extends RefCounted
# The sandbox's terrain (DECISIONS 地形编辑器, Q278–Q282): everything the
# campaign taught, as data the player edits while the dish runs. `map`:
#   base      {temp, acid, radiation}
#   zones     [{center, radius, temp, acid, radiation, light, vent, chem, name, key, tint}]
#   lights    [[pos, radius, power]]
#   band      [] or [y_full, y_dark, power]: light from above
#   oxygen    the water holds oxygen (producers give it off)
#   mud       {} or {o2_full, o2_zero, h2s_from, h2s_full, h2s}: the mud's layers
#   walls     [[a, b]]: ice
#   algae     [[pos, radius, n, each]] painted food; shells likewise
#   night     {} or {day, night, cold}: the long night
#   rain      {} or {dry, wet, level}: acid rain
#   net       {} or {center}; helio {} or {spots}; slime {} or {center}
# Edits go through `edit()` (undoable); `apply()` brings the running sim in
# line with the map without restarting it. Templates are the planets the
# campaign visits; worlds are saved as Godot variant text in user://worlds/.
# The editor's panel and brushes: scripts/ui/terrain_editor.gd.

const DIR := "user://worlds/"
const TEMPLATES := [
	["blank", "空白皿", "什么都没有：从零开始"],
	["europa", "木卫二样本", "三个环境区和它们的原生物种（原来的沙盒）"],
	["p1", "星球一 · 热泉海床", "热泉、上方的光、氧气"],
	["p2", "星球二 · 冰封海", "冰缝迷宫、长夜"],
	["p3", "星球三 · 酸性沼泽", "泥层分带、酸雨"],
]
const NATIVES := [
	["硫泉游丝", "吃热泉的硫化物，厌氧"],
	["晨光丝", "晒光的生产者，放出氧气"],
	["紫光游丝", "会用氧的小细菌，吞噬泡能把它吞成共生菌"],
	["抢食游丝", "繁殖很快的采集者"],
	["蜉游丝", "活得快死得快，留下很多空壳"],
]

var host: Node2D
var map := {}
var undo: Array = [] # [{before, after, paint}]
var redo: Array = []
var applied := {} # what the sim was last given (only changes are re-sent)
var events: Array = []
# The designed virus (投放病毒 drops it) and its host; whether the colony
# rules have been given to the sim (the first multicell release).
var virus := {}
var virus_host := -1
var colony_on := false
# The sandbox's multicell rules: still water, no grit, the regenerating
# body of level 23 open (every block kind).
const COLONY := {stream = Vector2.ZERO, grit = 0, grit_speed = 1.6, gest = 25.0, wait = 8.0, child = 0.9,
	store_e = 350.0, armor = 0.04, bite_e = 100.0, bite_gap = 3.0, kinds = [1, 6, 7, 8, 9], tune = {burn = 2.4}, specimen = "SANDBOX",
	hurt = 1.0, crack = 0.34, regrow = 180.0, regen = 12.0, regen_all = true, regrow_e = 15.0, bleed = 14.0}
var fired := {}
var _t0 := 0.0
var _last := 0.0


static func empty_map() -> Dictionary:
	return {base = {temp = 12.0, acid = 0.03, radiation = 0.05}, zones = [], lights = [], band = [], oxygen = false, mud = {},
		walls = [], algae = [], shells = [], night = {}, rain = {}, net = {}, helio = {}, slime = {}}


static func template(key: String) -> Dictionary:
	var m := empty_map()
	m.template = key
	match key:
		"blank":
			m.lights = [[Vector2(1100, 1100), 760.0, 0.5]]
			m.algae = [[Vector2(1100, 1100), 500.0, 120, 22.0]]
		"europa":
			var w := Worlds.sandbox()
			m.base = (Ecology.EUROPA_SAMPLE.base as Dictionary).duplicate()
			m.zones = (Ecology.EUROPA_SAMPLE.zones as Array).duplicate(true)
			m.lights = (w.lights as Array).duplicate(true)
		"p1":
			m.base = (LevelsCh6.SEABED.base as Dictionary).duplicate()
			m.zones = (LevelsCh6.SEABED.zones as Array).duplicate(true)
			m.band = (LevelsCh6.LIGHT_BAND as Array).duplicate()
			m.oxygen = true
		"p2":
			m.base = {temp = 6.0, acid = 0.02, radiation = 0.05}
			m.lights = [[Vector2(1100, 1100), 900.0, 0.5]]
			m.walls = (LevelsCh7.MAZE as Array).duplicate(true)
			m.night = {day = 70.0, night = 45.0, cold = -20.0}
		"p3":
			m.base = (LevelsCh8.SWAMP.base as Dictionary).duplicate()
			m.band = (LevelsCh8.LIGHT_BAND as Array).duplicate()
			m.oxygen = true
			m.mud = (LevelsCh8.MUD as Dictionary).duplicate()
			m.rain = {dry = 70.0, wet = 35.0, level = 5.0}
			m.shells = [[Vector2(1100, 900), 500.0, 200, 30.0]]
	return m


# A world config (Worlds.populate) for a fresh dish from a map; the species
# of the template come with it.
func world_cfg(m: Dictionary) -> Dictionary:
	var cfg := {name = "沙盒", layout = {name = "沙盒", code = "SBX", base = m.base, zones = m.zones},
		lights = m.lights, algae_cap = 1500, algae_seed = [300 if m.get("template", "") != "europa" else 800, 22.0],
		algae_patches = m.algae, shells = m.shells, walls = m.walls, species = []}
	if not (m.band as Array).is_empty():
		cfg.light_band = m.band
	if m.oxygen:
		cfg.oxygen = (LevelsCh6.OXYGEN as Dictionary).duplicate()
	if not (m.mud as Dictionary).is_empty():
		cfg.mud = m.mud
	match m.get("template", ""):
		"europa":
			var w := Worlds.sandbox()
			cfg.natives = true
			cfg.species = w.species
			cfg.layout = Ecology.EUROPA_SAMPLE
		"p1":
			cfg.species = [LevelsCh6.SULFUR_AT_SPRINGS, {label = "晨光丝", params = LevelsCh6.DAWN, spawn = [[Vector2(1100, 380), 60, 300.0]]}]
		"p2":
			cfg.species = [{native = "冰晶游丝", spawn = [[Vector2(1100, 1100), 60, 500.0]]}]
		"p3":
			cfg.species = [{label = "蜉游丝", params = LevelsCh8.MAYFLY, spawn = [[Vector2(1100, 450), 60, 300.0]]},
				{label = "紫光游丝", params = LevelsCh8.PURPLE_BUG, spawn = [[Vector2(1100, 700), 40, 300.0]]}]
	return cfg


# A new dish from a template or a saved map (the species in it start over).
func load_map(m: Dictionary) -> void:
	map = m.duplicate(true)
	undo.clear()
	redo.clear()
	host.load_world(world_cfg(map))
	applied = {}
	_sync_extras()
	_refresh_views()


func reset() -> void:
	map = template("europa")
	applied = {}
	undo.clear()
	redo.clear()
	events.clear()
	fired.clear()
	virus = {}
	virus_host = -1
	colony_on = false


# A new dish forgets the virus and the colony rules (load_world).
func world_reset() -> void:
	virus = {}
	virus_host = -1
	colony_on = false


# The designer's virus page: this design, infecting species `sp`.
func set_virus(v: Dictionary, sp: int) -> void:
	virus = v.duplicate()
	virus_host = sp
	var ph := {"host": sp, "rain": 0.0, "rain_from": 0.0, "virophage": false}
	ph.merge(LevelEval.virus_params(v), true)
	host.sim.set_phage(ph)
	host.phage_layer.set_look(v, false)
	host.giant_layer.takeover = float(ph.burst)
	host.zoom_max = maxf(host.zoom_max, 26.0)


# A multicell species released: its body as colony parameters, the rules
# given to the sim once.
func colony_params(params: Dictionary) -> Dictionary:
	if not colony_on:
		host.sim.set_colony(COLONY)
		colony_on = true
		host.zoom_max = maxf(host.zoom_max, 20.0)
	var p := params.duplicate()
	p.merge(Colony.params(params.blocks, COLONY.tune), true)
	return p


# --- editing -------------------------------------------------------------------

# One edit: `change` alters the map (a Callable taking it); `paint` the food
# painted with it ([[pos, r, kind]]: undo erases it again).
func edit(change: Callable, paint := []) -> void:
	var before: Dictionary = map.duplicate(true)
	change.call(map)
	undo.append({before = before, after = map.duplicate(true), paint = paint})
	if undo.size() > 60:
		undo.pop_front()
	redo.clear()
	apply()


func can_undo() -> bool:
	return not undo.is_empty()


func can_redo() -> bool:
	return not redo.is_empty()


func do_undo() -> void:
	if undo.is_empty():
		return
	var e: Dictionary = undo.pop_back()
	map = (e.before as Dictionary).duplicate(true)
	for p: Array in e.paint:
		host.sim.remove_food(p[0], float(p[1]), true, true)
	redo.append(e)
	apply()


func do_redo() -> void:
	if redo.is_empty():
		return
	var e: Dictionary = redo.pop_back()
	map = (e.after as Dictionary).duplicate(true)
	for p: Array in e.paint:
		_paint(p[0], float(p[1]), p[2])
	undo.append(e)
	apply()


func _paint(at: Vector2, r: float, kind: String) -> void:
	if kind == "algae":
		host.sim.add_algae_patch(at, r, 6, 20.0)
	else:
		host.sim.add_shells(at, r, 6, 25.0, 0)


# Food painted live (stored in the map for saving).
func paint_food(at: Vector2, r: float, kind: String) -> Array:
	_paint(at, r, kind)
	return [at, r, kind]


# --- the running sim brought in line with the map --------------------------------

func apply() -> void:
	var sim: SimCore = host.sim
	sim.set_base_environment(map.base)
	sim.clear_zones()
	for z: Dictionary in map.zones:
		sim.add_zone(z)
	host.layout = {name = "沙盒", code = "SBX", base = map.base, zones = map.zones}
	sim.reset_lights()
	for l: Array in map.lights:
		sim.add_light(l[0], float(l[1]), float(l[2]))
	if not (map.band as Array).is_empty():
		sim.add_light_band(float(map.band[0]), float(map.band[1]), float(map.band[2]))
	sim.clear_walls()
	for w: Array in map.walls:
		sim.add_wall(w[0], w[1])
	_sync_extras()
	_refresh_views()


# Oxygen, the mud, the bosses, the events: re-sent only when changed (each
# restarts its own state).
func _sync_extras() -> void:
	var sim: SimCore = host.sim
	if bool(applied.get("oxygen", false)) != bool(map.oxygen):
		if map.oxygen:
			var ox: Dictionary = (LevelsCh6.OXYGEN as Dictionary).duplicate()
			ox.start = 0.2
			sim.set_oxygen(ox)
		else:
			sim.set_oxygen({on = false})
	if applied.get("mud", {}) != map.mud:
		sim.set_mud(map.mud if not (map.mud as Dictionary).is_empty() else {on = false})
		if not (map.mud as Dictionary).is_empty():
			map.oxygen = true
	if applied.get("net", {}) != map.net:
		if (map.net as Dictionary).is_empty():
			sim.set_net({on = false})
		else:
			var n: Dictionary = (Levels.by_id("6-5").net as Dictionary).duplicate()
			n.center = map.net.center
			sim.set_net(n)
			if not map.oxygen:
				map.oxygen = true
				var ox2: Dictionary = (LevelsCh6.OXYGEN as Dictionary).duplicate()
				ox2.start = 0.2
				sim.set_oxygen(ox2)
	if applied.get("helio", {}) != map.helio:
		if (map.helio as Dictionary).is_empty():
			sim.set_helio({})
		else:
			var hp: Dictionary = (Levels.by_id("7-5").helio as Dictionary).duplicate()
			hp.spots = map.helio.spots
			sim.set_helio(hp)
	if applied.get("slime", {}) != map.slime:
		if (map.slime as Dictionary).is_empty():
			sim.set_slime({})
		else:
			var sp: Dictionary = (Levels.by_id("8-5").slime as Dictionary).duplicate()
			var c: Vector2 = map.slime.center
			sp.center = c
			sp.points = slime_points(c)
			sim.set_slime(sp)
	if applied.get("night", {}) != map.night or applied.get("rain", {}) != map.rain:
		events.clear()
		fired.clear()
		_t0 = sim.get_time()
		_last = 0.0
		if not (map.night as Dictionary).is_empty():
			events.append({kind = "cycle", day = float(map.night.day), night = float(map.night.night), cold = float(map.night.cold), warm = float(map.base.temp), offset = 0.0})
		else:
			sim.set_night(false)
			sim.set_light_scale(1.0)
			sim.set_base_environment(map.base)
		if not (map.rain as Dictionary).is_empty():
			events.append({kind = "rain", dry = float(map.rain.dry), wet = float(map.rain.wet), level = float(map.rain.level), top = 60.0, offset = 0.0})
		else:
			sim.set_rain(0.0, 60.0)
	applied = map.duplicate(true)


# The slime mould's six food points round its body, kept inside the dish.
static func slime_points(c: Vector2) -> Array:
	var out := []
	var dish := Vector2(1100, 1100)
	for k in 6:
		var p := c + Vector2.from_angle(TAU * k / 6.0 - PI * 0.5) * 650.0
		if p.distance_to(dish) > 900.0:
			p = dish + (p - dish).normalized() * 900.0
		out.append(p)
	return out


func _refresh_views() -> void:
	host.o2_world = bool(map.oxygen)
	host.net_world = not (map.net as Dictionary).is_empty()
	host.env_tex.update(host._env_image())
	host.light_tex.update(host._field_image(host.sim.get_light_field()))
	host.zone_labels.queue_redraw()
	host.o2_layer.reset()
	host.ice_layer.reset()
	host.swamp_layer.reset()


# --- the long night and the rain, as a level runs them --------------------------

func tick() -> void:
	if events.is_empty():
		return
	var t: float = host.sim.get_time() - _t0
	var t0 := _last if _last <= t else t
	_last = t
	for said: Dictionary in LevelEval.tick_events({events = events}, host.sim, t0, t, fired):
		host.hud_root.notify(said.text, Color(0.35, 0.6, 0.95), said.get("pos", Vector2.INF))


# --- natives ------------------------------------------------------------------

func add_native(name: String) -> void:
	var p: Dictionary
	var at := Vector2(1100, 1100)
	match name:
		"硫泉游丝":
			p = LevelsCh6.SULFUR
			at = Vector2(1590, 1500)
		"晨光丝":
			p = LevelsCh6.DAWN
			at = Vector2(1100, 380)
		"紫光游丝":
			p = LevelsCh8.PURPLE_BUG
		"抢食游丝":
			p = LevelsCh8.RIVAL
		"蜉游丝":
			p = LevelsCh8.MAYFLY
	var params := p.duplicate()
	params.erase("name")
	host._species(params)
	var i: int = host.colors.size() - 1
	host.labels.append(name)
	host.sim.spawn(i, at, 40, 160.0)
	host.hud_root.add_species_row(i)
	host.hud_root.notify("加入 %s × 40" % name, params.color, at)


# --- saving -------------------------------------------------------------------

static func saved_list() -> Array:
	var out := []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".world"):
			out.append(f.get_basename())
	out.sort()
	return out


func save_as(name: String) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + name.validate_filename() + ".world", FileAccess.WRITE)
	if f == null:
		return false
	var m := map.duplicate(true)
	m.name = name
	f.store_string(var_to_str(m))
	return true


func load_saved(name: String) -> bool:
	var f := FileAccess.open(DIR + name + ".world", FileAccess.READ)
	if f == null:
		return false
	var v: Variant = str_to_var(f.get_as_text())
	if not (v is Dictionary):
		return false
	var m := empty_map()
	m.merge(v, true)
	load_map(m)
	return true
