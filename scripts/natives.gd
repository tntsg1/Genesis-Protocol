class_name Natives
extends RefCounted
# Native species (GDD 5.2): generated from an environment layout with the
# same genome and rule cards the player uses, one per niche a zone can feed,
# each suited to its own water. tools/evolve_natives.gd then lets them evolve
# for about 50 generations and stores the result, which the game loads
# (data/natives_<code>.json) so a dish starts already lived-in.

# Niches: chemo (a producer living on the vent's chemistry, like algae on
# light), grazer (eats algae), hunter (eats other cells), decomposer (a small
# hunter that lives off empty shells first).
# Where each lives: the vent feeds chemosynthetic cells and a grazer, the
# cold water a thrifty grazer, the acid pool an armoured one. The hunters are
# the open water's own (猎手 and the 巨兽 in the showcase dish), who roam
# every zone; zone hunters of their own proved too fragile to hold on.
const NICHES := {
	vent = ["chemo", "grazer"],
	ice = ["grazer"],
	acid = ["grazer"],
}
const PREFIX := {vent = "热泉", ice = "冰晶", acid = "硫池"}
const SUFFIX := {chemo = "化能菌", grazer = "游丝", hunter = "刺猎", decomposer = "噬壳"}
# Each distinct from the sample species (aqua, honey, rose, lavender), so
# the species view filter tells every population apart.
const COLORS := {
	vent = [Color(0.9, 0.86, 0.26), Color(0.86, 0.38, 0.78)],
	ice = [Color(0.3, 0.76, 0.62)],
	acid = [Color(0.66, 0.82, 0.3)],
}
# How many founders each niche starts with.
const COUNT := {chemo = 80, grazer = 70, hunter = 16, decomposer = 30}


static func generate(layout: Dictionary, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := []
	for z: Dictionary in layout.zones:
		var niches: Array = NICHES.get(z.key, ["grazer"])
		for n in niches.size():
			out.append(_make(z, niches[n], COLORS[z.key][n], rng))
	return out


static func _make(z: Dictionary, niche: String, color: Color, rng: RandomNumberGenerator) -> Dictionary:
	var j := func(v: float, spread := 0.4) -> float: return clampf(v + rng.randf_range(-spread, spread), 1.0, 5.0)
	var p := {
		name = PREFIX[z.key] + SUFFIX[niche], color = color, zone = z.key, home = z.center, niche = niche,
		count = COUNT[niche], temp_opt = float(z.temp) + rng.randf_range(-2.0, 2.0), temp_tol = j.call(2.0, 0.2),
		neural = 3.0, cohesion = 0.3,
	}
	match niche:
		"chemo":
			# Near-sessile and thick-walled: they cannot outswim a hunter, so
			# they are hard to bite instead.
			p.merge({diet = 2, radius = 4.0, speed = j.call(1.4, 0.2), vision = j.call(1.8, 0.2), armor = j.call(3.2, 0.3),
				attack = 1.0, fertility = j.call(3.5), efficiency = j.call(3.0), lifespan = 100.0})
		"grazer":
			p.merge({diet = 0, radius = 5.0, speed = j.call(2.0), vision = j.call(2.4), armor = j.call(1.4),
				attack = 1.0, fertility = j.call(3.0), efficiency = j.call(3.0), lifespan = 85.0})
		"hunter":
			p.merge({diet = 1, radius = 9.0, speed = j.call(3.0), vision = j.call(3.2), armor = j.call(1.8),
				attack = j.call(3.4), fertility = j.call(1.4, 0.2), efficiency = j.call(2.8), lifespan = 180.0})
			p.neural = 4.0 # room for the lurk card as well as the way home
		"decomposer":
			p.merge({diet = 1, radius = 6.5, speed = j.call(2.2), vision = j.call(3.8, 0.3), armor = j.call(2.0),
				attack = j.call(2.2), fertility = j.call(3.0), efficiency = j.call(3.4), lifespan = 170.0})
	# Grazers school and vent cells grow in mats (a hunter in a crowd cannot
	# pin one down, though the mat shares the chemistry); hunters hunt alone
	# (crowded hunters get in each other's way).
	if niche == "chemo":
		p.cohesion = 0.6
	elif niche != "grazer":
		p.cohesion = 0.0
	# Each water shapes the body: acid favours shells, cold favours thrift,
	# the vent's currents favour strong swimmers.
	match z.key:
		"acid": p.armor = clampf(p.armor + 1.2, 1.0, 5.0)
		"ice": p.efficiency = clampf(p.efficiency + 0.8, 1.0, 5.0)
		"vent": p.speed = clampf(p.speed + 0.3, 1.0, 5.0)
	# Locals keep to their own water: when it turns wrong and there is no
	# food in sight, they head home.
	var deck := Rules.default_deck(1 if p.diet == 1 else 0)
	deck.insert(3, Rules.card(Rules.C_TEMP_BAD, 0.0, Rules.C_NONE, 0.0, Rules.A_SEEK_COMFORT))
	if niche == "chemo":
		deck = [
			Rules.card(Rules.C_ENERGY_ABOVE, 1.0, Rules.C_NONE, 0.0, Rules.A_DIVIDE),
			Rules.card(Rules.C_ENERGY_BELOW, 1.0, Rules.C_SEE_ALGAE, 0.0, Rules.A_SEEK_ALGAE),
			Rules.card(Rules.C_TEMP_BAD, 0.0, Rules.C_NONE, 0.0, Rules.A_SEEK_COMFORT),
			Rules.card(Rules.C_ENERGY_ABOVE, 1.0, Rules.C_NONE, 0.0, Rules.A_REST),
		]
	if niche == "decomposer":
		# Shells first, live prey when they are not well fed.
		deck = [
			Rules.card(Rules.C_PREDATOR_NEAR, 60.0, Rules.C_NONE, 0.0, Rules.A_FLEE),
			Rules.card(Rules.C_ENERGY_BELOW, 1.0, Rules.C_SEE_SHELL, 0.0, Rules.A_SCAVENGE),
			Rules.card(Rules.C_TEMP_BAD, 0.0, Rules.C_NONE, 0.0, Rules.A_SEEK_COMFORT),
			Rules.card(Rules.C_ENERGY_ABOVE, 1.0, Rules.C_NONE, 0.0, Rules.A_DIVIDE),
			Rules.card(Rules.C_ENERGY_BELOW, 0.8, Rules.C_SEE_PREY, 0.0, Rules.A_HUNT),
		]
	p.deck = deck.slice(0, Rules.slots(p.neural))
	return p


# The stored, evolved natives for a layout (or freshly generated ones).
static func load_for(layout: Dictionary, seed := 7) -> Array:
	var path := "res://data/natives_%s.json" % String(layout.code).to_lower()
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			return (parsed as Array).map(from_json)
	return generate(layout, seed)


static func to_json(p: Dictionary) -> Dictionary:
	var d := p.duplicate(true)
	d.color = p.color.to_html()
	d.home = [p.home.x, p.home.y]
	return d


static func from_json(d: Dictionary) -> Dictionary:
	var p := d.duplicate(true)
	p.color = Color.html(d.color)
	p.home = Vector2(d.home[0], d.home[1])
	for k in ["diet", "count"]:
		p[k] = int(p[k])
	var deck := []
	for c: Dictionary in d.deck:
		deck.append(Rules.card(int(c.c1), float(c.t1), int(c.c2), float(c.t2), int(c.act)))
	p.deck = deck
	return p
