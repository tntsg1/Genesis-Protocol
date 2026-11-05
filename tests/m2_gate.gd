extends SceneTree
# M2 acceptance (GDD 17): changing one key card makes a measurable difference
# in a controlled experiment, and decks really evolve.
#   A: default grazer deck (divide when energy > 100%)
#   B: the same deck with one card changed: divide when energy > 35%
# Same dish, same seeds; only the card differs. Headless.
# Run: godot --headless --path . -s tests/m2_gate.gd

const TICK := 1.0 / 15.0
const SEEDS := [11, 22, 33, 44, 55]
const MINUTES := 3.0


func _initialize() -> void:
	_run.call_deferred()


func _dish(seed: int, deck: Array) -> SimCore:
	var sim := SimCore.new()
	sim.setup(Vector2(1400, 1400), seed)
	sim.set_dish(Vector2(700, 700), 660.0)
	sim.add_light(Vector2(500, 600), 300.0, 0.5)
	sim.add_light(Vector2(900, 800), 300.0, 0.5)
	sim.set_algae_cap(700)
	sim.seed_algae(400, 22.0)
	sim.add_species({color = Color.AQUA, radius = 5.5, speed = 1.9, vision = 2.6, armor = 1.4, attack = 1.0,
		fertility = 3.2, efficiency = 3.0, lifespan = 80.0, neural = 3.0, deck = deck})
	sim.spawn(0, Vector2(700, 700), 120, 300.0)
	return sim


func _trial(seed: int, deck: Array) -> Dictionary:
	var sim := _dish(seed, deck)
	var sum := 0.0
	var n := 0
	for t in int(MINUTES * 60.0 / TICK):
		sim.step(TICK)
		if t % 15 == 0:
			sum += sim.get_count()
			n += 1
	var st: Dictionary = sim.get_stats().species[0]
	var deaths: int = st.starved + st.eaten + st.aged
	return {mean = sum / n, starved_share = float(st.starved) / maxf(deaths, 1.0), births = st.births, sim = sim}


func _stats(v: Array) -> Array:
	var m := 0.0
	for x in v:
		m += x
	m /= v.size()
	var s := 0.0
	for x in v:
		s += (x - m) * (x - m)
	return [m, sqrt(s / (v.size() - 1))]


func _run() -> void:
	var deck_a := Rules.default_deck(0)
	var deck_b := Rules.default_deck(0)
	deck_b[1] = Rules.card(Rules.C_ENERGY_ABOVE, 0.35, Rules.C_NONE, 0.0, Rules.A_DIVIDE)
	print("A: ", ", ".join(deck_a.map(Rules.card_text)))
	print("B: ", ", ".join(deck_b.map(Rules.card_text)))
	var ma := []
	var mb := []
	var sa := []
	var sb := []
	var last_a: SimCore
	for seed in SEEDS:
		var a := _trial(seed, deck_a)
		var b := _trial(seed, deck_b)
		print("seed %d  A mean %.0f starved %.0f%% births %d  |  B mean %.0f starved %.0f%% births %d" % [
			seed, a.mean, a.starved_share * 100, a.births, b.mean, b.starved_share * 100, b.births])
		ma.append(a.mean)
		mb.append(b.mean)
		sa.append(a.starved_share)
		sb.append(b.starved_share)
		last_a = a.sim
	var pa := _stats(ma)
	var pb := _stats(mb)
	var qa := _stats(sa)
	var qb := _stats(sb)
	# Welch t for the starvation share (the mechanism: dividing too early
	# leaves both halves too poor to last).
	var t_pop: float = (pa[0] - pb[0]) / sqrt(pa[1] * pa[1] / 5.0 + pb[1] * pb[1] / 5.0 + 1e-9)
	var t_starve: float = (qb[0] - qa[0]) / sqrt(qa[1] * qa[1] / 5.0 + qb[1] * qb[1] / 5.0 + 1e-9)
	print("population  A %.0f ± %.0f   B %.0f ± %.0f   t = %.1f" % [pa[0], pa[1], pb[0], pb[1], t_pop])
	print("starved     A %.0f%% ± %.0f   B %.0f%% ± %.0f   t = %.1f" % [qa[0] * 100, qa[1] * 100, qb[0] * 100, qb[1] * 100, t_starve])
	var differs: bool = absf(t_pop) > 3.0 or absf(t_starve) > 3.0
	print(("PASS" if differs else "FAIL") + "  one card changes the outcome significantly (|t| > 3)")
	# Evolution: after 3 minutes the population holds more than one deck.
	var decks := {}
	for p in last_a.get_positions(0):
		var info: Dictionary = last_a.get_agent(last_a.find_agent(p, 2.0))
		if info.is_empty():
			continue
		decks[" | ".join(info.deck.map(Rules.card_text))] = decks.get(" | ".join(info.deck.map(Rules.card_text)), 0) + 1
	var top := decks.keys()
	top.sort_custom(func(x, y) -> bool: return decks[x] > decks[y])
	print("distinct decks after %.0f min: %d" % [MINUTES, decks.size()])
	for k in mini(4, top.size()):
		print("  %3d × %s" % [decks[top[k]], top[k]])
	var evolves := decks.size() > 1
	print(("PASS" if evolves else "FAIL") + "  decks mutate and diverge")
	print("RESULT: ", "PASS" if differs and evolves else "FAIL")
	quit(0 if differs and evolves else 1)
