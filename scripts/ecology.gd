class_name Ecology
extends RefCounted
# Environment layouts (GDD 5): a base environment plus named zones, each a
# soft-edged disc with its own temperature, acidity, radiation, light and
# vent input. SimCore turns a layout into per-cell fields (add_zone); the
# same layouts will describe the long game's planets (M7).
#
# The showcase dish is a sample of Europa's ocean under the ice: a warm
# hydrothermal vent, cold water under the ice shell, an acid sulfide pool,
# and mild water in between.

const EUROPA_SAMPLE := {
	name = "木卫二 · 冰下海洋样本",
	code = "EUR-01",
	base = {temp = 12.0, acid = 0.03, radiation = 0.05},
	zones = [
		{key = "vent", name = "热液喷口区", en = "HYDROTHERMAL VENT", center = Vector2(1590, 1500), radius = 470.0,
			temp = 36.0, acid = 0.08, radiation = 0.12, light = 1.0, vent = 1.5, chem = 1.0, tint = Color(1.0, 0.62, 0.32)},
		{key = "ice", name = "冰壳冷水区", en = "UNDER-ICE WATER", center = Vector2(640, 660), radius = 490.0,
			temp = 1.0, acid = 0.0, radiation = 0.04, light = 0.75, vent = 0.0, tint = Color(0.55, 0.82, 1.0)},
		{key = "acid", name = "硫化物酸池", en = "SULFIDE POOL", center = Vector2(620, 1580), radius = 430.0,
			temp = 19.0, acid = 0.8, radiation = 0.35, light = 0.9, vent = 3.0, chem = 0.5, tint = Color(0.78, 0.86, 0.3)},
	],
}


static func apply(sim: SimCore, layout: Dictionary) -> void:
	sim.set_base_environment(layout.base)
	for z: Dictionary in layout.zones:
		sim.add_zone(z)


# The zone a point belongs to most (its key), or "" in the open water.
static func zone_at(layout: Dictionary, pos: Vector2) -> Dictionary:
	var best := {}
	var best_w := 0.25
	for z: Dictionary in layout.zones:
		var d: float = pos.distance_to(z.center)
		var w := clampf((z.radius - d) / (z.radius * 0.5), 0.0, 1.0)
		if w > best_w:
			best_w = w
			best = z
	return best


# How well a genome would do in an environment, 0..1, mirroring SimCore's
# metabolism: its own running cost against the extra drain of heat, cold and
# acid there (shown in the designer and the life scan).
static func fitness(genes: Array, temp_opt: float, env: Dictionary, radius := 5.5) -> float:
	var size_factor := pow(radius / 6.0, 0.75)
	var tol: float = genes[7] if genes.size() > 7 else 2.5
	var band := 3.0 + 4.0 * (tol - 1.0)
	var dev := maxf(0.0, absf(float(env.temp) - temp_opt) - band)
	var st := (0.05 * dev + (0.12 * (dev - 10.0) if dev > 10.0 else 0.0)) * size_factor
	var sa := float(env.acid) * 1.5 * size_factor / (1.0 + 0.35 * float(genes[2]))
	var own := 0.45 * size_factor * (1.3 - 0.09 * float(genes[5])) + 0.05 * float(genes[1]) + 0.08 * float(genes[3]) + 0.06 * float(genes[2])
	return clampf(own / (own + st + sa), 0.0, 1.0)
