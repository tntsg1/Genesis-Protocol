class_name SandboxWorld
extends RefCounted
# The sandbox's environment switches (DECISIONS 沙盒补全, Q275 b): one dish,
# and everything the campaign has taught can be switched on in it, one by
# one, while it runs: planet one's oxygen and light from above, planet two's
# ice, long night and heliozoan, planet three's mud, acid rain and slime
# mould, the foraminiferan's net; and the planets' natives added on request.
# The numbers are the levels' own (LevelsCh6/7/8). The panel itself is in
# EcoHud (G).

const SWITCHES := [
	["oxygen", "氧气与光照", "星球一：上面有光，生产者放出氧气；厌氧怕氧、好氧靠氧"],
	["net", "伪足网", "星球一 Boss：有孔虫在海床织网（要先开氧气）"],
	["walls", "冰墙", "星球二：冰缝迷宫，谁都过不去，也看不穿"],
	["night", "长夜", "星球二：每 115 秒有 45 秒全暗、水温 -20°C"],
	["helio", "太阳虫", "星球二 Boss：伸着轴足埋伏，粘住细胞拖进去"],
	["mud", "泥层分带", "星球三：越往下氧越少、硫化氢越浓"],
	["rain", "酸雨", "星球三：每 105 秒下一场 35 秒的酸雨"],
	["slime", "菌毯意识", "星球三 Boss：黏菌朝六个点伸管道，吞掉碰到的细胞"],
]
const NATIVES := [
	["硫泉游丝", "吃热泉的硫化物，厌氧"],
	["晨光丝", "晒光的生产者，放出氧气"],
	["紫光游丝", "会用氧的小细菌，吞噬泡能把它吞成共生菌"],
	["抢食游丝", "繁殖很快的采集者"],
	["蜉游丝", "活得快死得快，留下很多空壳"],
]
const NIGHT := {kind = "cycle", day = 70.0, night = 45.0, cold = -20.0, warm = 12.0, offset = 0.0}
const RAIN := {kind = "rain", dry = 70.0, wet = 35.0, level = 5.0, top = 60.0, offset = 0.0}

var host: Node2D
var on := {}
var events: Array = []
var fired := {}
var _t0 := 0.0
var _last := 0.0


func reset() -> void:
	on.clear()
	events.clear()
	fired.clear()


func is_on(key: String) -> bool:
	return bool(on.get(key, false))


func toggle(key: String) -> String:
	var sim: SimCore = host.sim
	var want := not is_on(key)
	match key:
		"oxygen":
			if want:
				var ox: Dictionary = (LevelsCh6.OXYGEN as Dictionary).duplicate()
				ox.start = 0.2
				sim.set_oxygen(ox)
				sim.add_light_band(LevelsCh6.LIGHT_BAND[0], LevelsCh6.LIGHT_BAND[1], LevelsCh6.LIGHT_BAND[2])
			else:
				if is_on("net"):
					toggle("net")
				if is_on("mud"):
					toggle("mud")
				sim.set_oxygen({on = false})
				sim.add_light_band(LevelsCh6.LIGHT_BAND[0], LevelsCh6.LIGHT_BAND[1], -float(LevelsCh6.LIGHT_BAND[2]))
			host.o2_world = want
			host.o2_layer.reset()
		"net":
			if want and not is_on("oxygen"):
				toggle("oxygen")
			sim.set_net((Levels.by_id("6-5").net as Dictionary).duplicate() if want else {on = false})
			host.net_world = want
			host.o2_layer.reset()
		"walls":
			if want:
				for w: Array in LevelsCh7.MAZE:
					sim.add_wall(w[0], w[1])
			else:
				sim.clear_walls()
			host.ice_layer.reset()
		"night":
			if want:
				events.append(NIGHT)
				_t0 = sim.get_time()
				_last = 0.0
				fired.clear()
			else:
				events.erase(NIGHT)
				sim.set_night(false)
				sim.set_light_scale(1.0)
				sim.set_base_environment({temp = 12.0})
		"helio":
			sim.set_helio((Levels.by_id("7-5").helio as Dictionary).duplicate() if want else {})
			host.ice_layer.reset()
		"mud":
			if want:
				sim.set_mud(LevelsCh8.MUD)
				host.o2_world = true
				on["oxygen"] = true
			else:
				sim.set_mud({on = false})
			host.o2_layer.reset()
		"rain":
			if want:
				events.append(RAIN)
				_t0 = sim.get_time()
				_last = 0.0
				fired.clear()
			else:
				events.erase(RAIN)
				sim.set_rain(0.0, 60.0)
		"slime":
			sim.set_slime((Levels.by_id("8-5").slime as Dictionary).duplicate() if want else {})
	on[key] = want
	host.swamp_layer.reset()
	for s: Array in SWITCHES:
		if s[0] == key:
			return "%s：%s" % [s[1], "开" if want else "关"]
	return ""


# A planet's native, 40 of them, where it lives.
func add_native(name: String) -> void:
	var p: Dictionary
	var at := Vector2(1100, 1100)
	match name:
		"硫泉游丝":
			p = LevelsCh6.SULFUR
			at = Vector2(1590, 1500) # (the sample's vent)
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


# The long night and the rain, run in the sandbox as a level runs them.
func tick() -> void:
	if events.is_empty():
		return
	var t: float = host.sim.get_time() - _t0
	var t0 := _last if _last <= t else t
	_last = t
	for said: Dictionary in LevelEval.tick_events({events = events}, host.sim, t0, t, fired):
		host.hud_root.notify(said.text, Color(0.35, 0.6, 0.95), said.get("pos", Vector2.INF))
