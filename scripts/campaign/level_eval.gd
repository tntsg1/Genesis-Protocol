class_name LevelEval
extends RefCounted
# Scores one run of a campaign level, live (LevelRunner) or headless (control
# experiments, the level bot): goal, extra challenge, the value the
# prediction was about, and the plain facts the report draws on. Fed with
# observe() every half second of sim time after the release.

var level: Dictionary
var sp := -1 # the player's species index
var sp2 := -1 # level 8: the player's second species (the predator)
var alive2 := 0
var sp3 := -1 # chapter 6 (6-4): the third species
var alive3 := 0
var peak3 := 0
var o2_mean := 0.0 # chapter 6: the dish's mean oxygen (0..1)
var held: Array = [] # 6-1: the player's cells at each spring
var o2_dead := 0 # 6-3: the second species' cells poisoned by oxygen
var net_cov := 0.0 # 6-5: the share of the dish under the pseudopod net
var dawns := 0 # chapter 7: long nights come through
var _was_night := false
var season_counts: Array = [] # 7-4: in the bloom at each season's end
var helio := {} # 7-5
var passed := 0 # 7-5: cells through to the far side
var net_cov_peak := 0.0
var net_low_since := -1.0 # since when it has been held under the goal (or -1)
var net_caught := 0
var net_done := -1.0 # when the goal was reached
var o2_peak := 0.0
var uses_state := false # level 8: the predator's deck switches into the challenge's state
var peak2 := 0
var budget_used := 0.0
var goal_met := false
var goal_time := -1.0
var first_in := -1.0
var first_kill := -1.0 # first prey eaten (level 6)
var eaten := 0 # the player's cells eaten so far (level 7)
var min_after := 1 << 30
var count_by_t := -1.0 # level 22: when the count was back up after the famine
var zone_peak := 0
var alive := 0
var peak := 0
var zone_now := 0
var extinct := false
var t := 0.0
var curve: Array = [] # [t, alive, in zone]
var algae0 := -1 # energy in the algae when observing began (level 3: how much is left)
var algae_now := 0
var patches_won := 0 # level 5: patches where the player outnumbers the rival
var patch_counts: Array = [] # [[mine, rival], ...]
var boss_alive := -1 # level 10: the boss species' count
var boss_dead := -1.0 # level 10: when the last boss starved (or -1)
var boss_energy := -1.0 # level 10: the devourers' mean energy, 0 starved .. 1 about to split
var rival_alive := -1 # chapter 3 boss: the rival colony's count
var slug_stats := {} # level 20
var zone_by_t := -1.0 # level 20: when the zone first held enough
var blocks_used := 0 # level 21: the size of the body
var colony_stats := {}
var giants := -1 # level 19: giant viruses, in the water and in factories
var giant_peak := 0
var giants_zero := -1.0 # level 19: when the last one went (or -1)
var giant_stats := {}
var rival_dead := -1.0 # when the rival colony died out (or -1)
var blooms: Array = [] # level 11: [{at, t, reached}] algae blooms so far
var next_bloom := -1.0
var rng := RandomNumberGenerator.new()
var lysed := 0 # level 15: cells burst by phages
var immune := 0 # level 16: cells carrying the memory
var storm0 := {} # level 16: the counts as the storm arrives
var rival_lysed := 0 # level 17: the rival's cells burst by phages
var shots := 0 # level 18: phage drops
var shot_times: Array = [] # ... and when
var cold_share := 0.0 # level 4: share of the population on cold-ward lineages
var founder := {topt = 12.0, tol = 2.5} # the released design's temperature genes
var _sim: SimCore
# Chapter 8.
var symb_now := 0 # 8-2: cells carrying a symbiont
var symb_by_t := -1.0
var tox_used := [false, false] # 8-3: toxin A / B ever put out
var rain_ends := 0 # 8-4: rains come through
var _was_rain := false
var slime := {} # 8-5: the slime mould, as get_slime() gives it
var hold_t: Array = [] # ... seconds each food point has been held
var _slime_last := 0.0


func _init(l: Dictionary, species_index: int, used: float) -> void:
	level = l
	sp = species_index
	budget_used = used
	rng.randomize()
	next_bloom = float(l.blooms.first) if l.has("blooms") else -1.0


static func count_in(sim: SimCore, s: int, zone: Dictionary) -> int:
	var n := 0
	var c: Vector2 = zone.center
	var r2: float = float(zone.radius) * float(zone.radius)
	for p: Vector2 in sim.get_positions(s):
		if p.distance_squared_to(c) <= r2:
			n += 1
	return n


func observe(sim: SimCore, time: float) -> void:
	t = time
	_sim = sim
	if level.challenge.kind == "algae_left":
		algae_now = int(sim.get_stats().energy_algae)
		if algae0 < 0:
			algae0 = algae_now
	if level.goal.kind == "patches":
		_count_patches(sim)
	alive = sim.get_positions(sp).size()
	peak = maxi(peak, alive)
	if sp2 >= 0:
		alive2 = sim.get_positions(sp2).size()
		peak2 = maxi(peak2, alive2)
	if sp3 >= 0:
		alive3 = sim.get_positions(sp3).size()
		peak3 = maxi(peak3, alive3)
	if level.challenge.kind == "zones_held":
		held.clear()
		for c: Vector2 in level.challenge.zones:
			held.append(count_in(sim, sp, {center = c, radius = level.challenge.radius}))
	if level.has("net"):
		var ns: Dictionary = sim.get_net_stats()
		net_cov = float(ns.coverage)
		net_cov_peak = maxf(net_cov_peak, net_cov)
		net_caught = int(ns.caught)
		if level.goal.kind == "net_push" and alive > 0:
			if net_cov <= float(level.goal.frac):
				if net_low_since < 0.0:
					net_low_since = t
				elif t - net_low_since >= float(level.goal.hold) and not goal_met:
					goal_met = true
					goal_time = t
					net_done = t
			else:
				net_low_since = -1.0
	# Chapter 7: a night come through (the dawn after it).
	var now_night := sim.get_night()
	if _was_night and not now_night:
		dawns += 1
		if level.goal.kind == "nights" and dawns >= int(level.goal.nights) and not goal_met and alive >= int(level.goal.n):
			goal_met = true
			goal_time = t
	_was_night = now_night
	if level.goal.kind == "seasons":
		var ends: Array = level.goal.ends
		while season_counts.size() < ends.size() and t >= float(ends[season_counts.size()][0]):
			var se: Array = ends[season_counts.size()]
			season_counts.append(count_in(sim, sp, {center = se[1], radius = float(se[2])}))
	# Chapter 8.
	if level.goal.kind in ["symb_end"] or level.challenge.kind == "symb_by":
		symb_now = sim.get_symb_count(sp)
		if level.challenge.kind == "symb_by" and symb_by_t < 0.0 and symb_now >= int(level.challenge.n):
			symb_by_t = t
	if level.goal.kind == "coexist_algae":
		algae_now = int(sim.get_stats().energy_algae)
	if level.challenge.kind == "both_toxins" and not (tox_used[0] and tox_used[1]):
		for w in 2:
			if not tox_used[w]:
				var sum := 0.0
				for v in sim.get_tox_field(w):
					sum += v
				tox_used[w] = sum > 2.0
	if level.has("slime"):
		_slime(sim)
	if _was_rain and not sim_raining(sim):
		rain_ends += 1
		if level.goal.kind == "rains" and rain_ends >= int(level.goal.rains) and not goal_met and alive >= int(level.goal.n):
			goal_met = true
			goal_time = t
	_was_rain = sim_raining(sim)
	if level.has("helio"):
		helio = sim.get_helio()
		if level.goal.kind == "helio":
			passed = count_in(sim, sp, level.goal.zone)
			if not goal_met and alive > 0 and (bool(helio.get("dead", false)) or passed >= int(level.goal.n)):
				goal_met = true
				goal_time = t
	if level.world.has("oxygen"):
		o2_mean = sim.get_o2_mean()
		if sp2 >= 0:
			o2_dead = int(sim.get_stats().species[sp2].o2)
		o2_peak = maxf(o2_peak, o2_mean)
	if level.has("blooms"):
		_blooms(sim, t)
	# Chapter 3 boss: a rival colony; crowding it out (any time) wins.
	if level.goal.kind == "clear_rival":
		rival_alive = sim.get_positions(int(level.goal.rival)).size()
	if level.goal.kind == "outnumber":
		rival_alive = sim.get_positions(int(level.goal.rival)).size()
		if rival_alive == 0 and rival_dead < 0.0 and alive > 0:
			rival_dead = t
			if not goal_met:
				goal_met = true
				goal_time = t
	if level.has("phage"):
		var stat: Dictionary = sim.get_stats().species[sp]
		lysed = int(stat.phage)
		immune = int(stat.immune)
		if level.goal.has("rival"):
			rival_lysed = int(sim.get_stats().species[int(level.goal.rival)].phage)
		for e: Dictionary in level.get("events", []):
			if e.kind == "phage_storm" and t >= float(e.at) and storm0.is_empty():
				storm0 = {alive = alive, immune = immune, lysed = lysed}
	if level.has("giant"):
		giant_stats = sim.get_giant_stats()
		giants = int(giant_stats.total)
		giant_peak = maxi(giant_peak, giants)
		# (Only after the last lot has come: until then the water is not clear.)
		var last := 0.0
		for e: Dictionary in level.get("events", []):
			last = maxf(last, float(e.at))
		if giants == 0 and giants_zero < 0.0 and not extinct and t >= last + 1.0:
			giants_zero = t
	var zone: Dictionary = level.goal.get("zone", level.challenge.get("zone", {}))
	zone_now = count_in(sim, sp, zone) if not zone.is_empty() else 0
	if level.has("colony"):
		colony_stats = sim.get_colony_stats()
		var own: Dictionary = sim.get_stats().species[sp]
		colony_stats.starved = int(own.starved)
		colony_stats.burned_all = int(own.temp)
		colony_stats.aged = int(own.aged)
		colony_stats.merge(sim.get_rotifer_stats(), true)
		if level.challenge.kind == "zone_by" and zone_by_t < 0.0 and zone_now >= int(level.challenge.n):
			zone_by_t = t
	if level.has("slug"):
		# (Only living, swimming cells: not spores, not cells still in a slug.)
		zone_now = sim.count_active(sp, zone.center, float(zone.radius))
		slug_stats = sim.get_slug_stats()
		if level.challenge.kind == "zone_by" and zone_by_t < 0.0 and zone_now >= int(level.challenge.n):
			zone_by_t = t
	zone_peak = maxi(zone_peak, zone_now)
	curve.append([t, alive, alive2 if sp2 >= 0 else (_phage_line() if level.has("phage") else zone_now)])
	# Two species: losing either one ends it (keeping both is the point).
	# (Chapter 6, 6-3: the second species may die out; saving it is the challenge.)
	if alive == 0 or (sp2 >= 0 and alive2 == 0 and not level.get("b_may_die", false)) or (sp3 >= 0 and alive3 == 0):
		extinct = true
	var ch: Dictionary = level.challenge
	if ch.kind == "first_in" and first_in < 0.0 and zone_now > 0:
		first_in = t
	if ch.kind == "first_kill" and first_kill < 0.0:
		# The player is the only hunter in such a level: any cell eaten is theirs.
		var eaten := 0
		var per: Array = sim.get_stats().species
		for k in per.size():
			if k != sp:
				eaten += int(per[k].eaten)
		if eaten > 0:
			first_kill = t
	if ch.kind == "eaten_max" or level.goal.kind in ["alive_safe", "boss", "outnumber"]:
		eaten = int(sim.get_stats().species[sp].eaten)
	if ch.kind == "floor_after" and t >= float(ch.from):
		min_after = mini(min_after, alive)
	if ch.kind == "count_by" and count_by_t < 0.0 and t >= float(ch.from) and t <= float(ch.by) and alive >= int(ch.n):
		count_by_t = t
	var g: Dictionary = level.goal
	if not goal_met:
		if g.kind == "zone_count" and zone_now >= int(g.n):
			goal_met = true
			goal_time = t
		# alive_end is judged at the end (finish()).
	# Level 10: the boss starved out (any time, while the player lives) wins.
	if g.kind == "boss":
		var bp: PackedVector2Array = sim.get_positions(int(g.boss))
		boss_alive = bp.size()
		# (Review: "饿死它" needs to be seen happening.)
		var sum := 0.0
		for p: Vector2 in bp:
			sum += float(sim.get_agent(sim.find_agent(p, 1.0)).get("energy_frac", 0.0))
		boss_energy = sum / bp.size() if bp.size() > 0 else 0.0
		if boss_alive == 0 and boss_dead < 0.0 and not extinct:
			boss_dead = t
			if not goal_met:
				goal_met = true
				goal_time = t



# Chapter 8 (8-4): is it raining now (from the level's rain event)?
func sim_raining(_s: SimCore) -> bool:
	for e: Dictionary in level.get("events", []):
		if e.kind == "rain":
			var per := float(e.dry) + float(e.wet)
			return fposmod(t - float(e.get("offset", 0.0)), per) >= float(e.dry)
	return false


# Chapter 8 boss (8-5): a food point held long enough by enough of the
# player's cells is theirs; four of them, or the mould starved, wins.
func _slime(sim: SimCore) -> void:
	slime = sim.get_slime()
	var cfg: Dictionary = level.slime
	var pts: Array = slime.points
	if hold_t.size() != pts.size():
		hold_t.resize(pts.size())
		hold_t.fill(0.0)
	var dt := t - _slime_last
	_slime_last = t
	for k in pts.size():
		if int(pts[k].owner) == 1:
			continue
		var n := count_in(sim, sp, {center = pts[k].pos, radius = float(cfg.hold_r)})
		hold_t[k] = float(hold_t[k]) + dt if n >= int(cfg.hold_n) else 0.0
		if float(hold_t[k]) >= float(cfg.hold_t):
			sim.set_slime_owner(k, 1)
			slime = sim.get_slime()
	if level.goal.kind == "slime" and not goal_met and alive > 0 and (bool(slime.dead) or int(slime.owned) >= int(cfg.need)):
		goal_met = true
		goal_time = t

# The second line on the report: what the level's goal turns on.
func _phage_line() -> int:
	if level.has("giant"):
		return maxi(giants, 0)
	if level.goal.has("rival"):
		return maxi(rival_alive, 0)
	return lysed if level.goal.kind == "alive_phage" else immune


# Level 11: algae blooms at random spots every so often (nutrient with
# spores, in the dark they fade within a minute); a bloom counts as reached
# once enough of the player's cells are on it while it lasts.
func _blooms(sim: SimCore, time: float) -> void:
	var b: Dictionary = level.blooms
	while next_bloom >= 0.0 and time >= next_bloom:
		var a := rng.randf() * TAU
		var at := Vector2(1100, 1100) + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * float(b.spread)
		# A light shines there for its life (the algae grow under it, then rot).
		sim.light_pulse(at, float(b.radius), float(b.power), float(b.life))
		sim.add_algae_patch(at, float(b.radius) * 0.8, int(b.clumps), float(b.each))
		blooms.append({at = at, t = next_bloom, reached = false})
		next_bloom += float(b.every)
	for bl: Dictionary in blooms:
		if not bl.reached and time - float(bl.t) < float(b.life):
			if count_in(sim, sp, {center = bl.at, radius = float(b.radius)}) >= int(b.reach_n):
				bl.reached = true


# Level 11: blooms reached of those that had time to be (the last 20 s don't count).
func blooms_counted() -> Array:
	var due := 0
	var got := 0
	for bl: Dictionary in blooms:
		if float(bl.t) <= float(level.time_limit) - 20.0:
			due += 1
			got += 1 if bl.reached else 0
	return [got, due]


# Called when the time limit is reached (or the run ends early).
func finish() -> void:
	var g: Dictionary = level.goal
	if g.kind == "alive_end" and not extinct and alive >= int(g.n):
		goal_met = true
		goal_time = t
	# Level 9: enough of them, and few lost to the hunters on the way.
	if g.kind == "alive_safe" and not extinct and alive >= int(g.n) and eaten <= int(g.eaten):
		goal_met = true
		goal_time = t
	# Level 18: the rival cleared back, and the player's own still standing.
	if g.kind == "clear_rival" and not extinct and rival_alive <= int(g.rival_max) and alive >= int(g.n):
		goal_met = true
		goal_time = t
	# Level 19: enough of them, and the giants held down.
	if g.kind == "giant_limit" and not extinct and alive >= int(g.n) and giants <= int(g.giant_max):
		goal_met = true
		goal_time = t
	# Level 15: enough of them, and few burst by phages on the way.
	if g.kind == "alive_phage" and not extinct and alive >= int(g.n) and lysed <= int(g.lysed):
		goal_met = true
		goal_time = t
	# Chapter 3 boss: or more of yours than of theirs at the end.
	if g.kind == "outnumber" and not extinct and alive > rival_alive and alive >= int(g.get("n", 0)):
		goal_met = true
		goal_time = t
	# Level 10: or enough of them at the end, the boss still about.
	if g.kind == "boss" and not extinct and alive >= int(g.n):
		goal_met = true
		goal_time = t
	if g.kind == "patches" and not extinct and patches_won >= int(g.n):
		goal_met = true
		goal_time = t
	if g.kind == "coexist" and not extinct and alive >= int(g.n) and alive2 >= int(g.n2):
		goal_met = true
		goal_time = t
	# Chapter 6: the three of a food chain, each above its floor (6-4).
	if g.kind == "coexist3" and not extinct and alive >= int(g.n) and alive2 >= int(g.n2) and alive3 >= int(g.n3):
		goal_met = true
		goal_time = t
	# Chapter 7 (7-4): enough in the bloom at every season's end.
	if g.kind == "seasons" and not extinct and season_counts.size() >= (g.ends as Array).size() and season_counts.all(func(v: int) -> bool: return v >= int(g.n)):
		goal_met = true
		goal_time = t
	# Chapter 8.
	if g.kind == "coexist_algae" and not extinct and alive >= int(g.n) and alive2 >= int(g.n2) and algae_now >= int(g.algae):
		goal_met = true
		goal_time = t
	if g.kind == "symb_end" and not extinct and symb_now >= int(g.n):
		goal_met = true
		goal_time = t
	# Chapter 6: the water's mean oxygen at the end (6-3).
	if g.kind == "o2_end" and not extinct and o2_mean >= float(g.frac):
		goal_met = true
		goal_time = t
	if level.challenge.kind == "cold_lineage" and _sim and not extinct:
		cold_share = cold_lineage_share(_sim, sp, {founder_topt = founder.topt, founder_tol = founder.tol, degrees = level.challenge.degrees})


# Level 5: in each patch, the player's cells against the rival's, averaged
# over the last 30 seconds (one instant of small numbers is a coin toss).
var _patch_hist: Array = [] # [t, [[mine, theirs], ...]]


func _count_patches(sim: SimCore) -> void:
	var g: Dictionary = level.goal
	var now := []
	for z: Dictionary in g.patches:
		now.append([count_in(sim, sp, z), count_in(sim, int(g.rival), z)])
	_patch_hist.append([t, now])
	while _patch_hist.size() > 1 and _patch_hist[0][0] < t - 30.0:
		_patch_hist.pop_front()
	patch_counts.clear()
	patches_won = 0
	for k in g.patches.size():
		var mine := 0.0
		var theirs := 0.0
		for h: Array in _patch_hist:
			mine += h[1][k][0]
			theirs += h[1][k][1]
		mine /= _patch_hist.size()
		theirs /= _patch_hist.size()
		patch_counts.append([roundi(mine), roundi(theirs)])
		if mine > theirs and mine >= 3.0:
			patches_won += 1


# Level 4: the share of living cells whose line has mutated toward the cold:
# a preferred temperature at least `degrees` lower than the founders', or a
# wider tolerance (gene up by 0.3 or more).
static func cold_lineage_share(sim: SimCore, s: int, ch: Dictionary) -> float:
	var n := 0
	var cold := 0
	for p: Vector2 in sim.get_positions(s):
		var a: Dictionary = sim.get_agent(sim.find_agent(p, 1.0))
		if a.is_empty() or int(a.species) != s:
			continue
		n += 1
		var g: PackedFloat32Array = a.genes
		if float(a.temp_opt) <= float(ch.founder_topt) - float(ch.degrees) or (g.size() > 7 and g[7] >= float(ch.founder_tol) + 0.3):
			cold += 1
	return float(cold) / float(maxi(n, 1))


# The fewest alive seen between t0 and t1 (the curve, every half second).
func floor_low(t0: float, t1: float) -> int:
	var low := 1 << 30
	for c: Array in curve:
		if float(c[0]) >= t0 and float(c[0]) <= t1:
			low = mini(low, int(c[1]))
	return low if low < (1 << 30) else 0


func challenge_met() -> bool:
	var ch: Dictionary = level.challenge
	match ch.kind:
		"first_in":
			return first_in >= 0.0 and first_in <= float(ch.seconds)
		"floor_after":
			return t >= float(ch.from) and min_after >= int(ch.n) and not extinct
		"count_by":
			return count_by_t >= 0.0 and not extinct
		"heal_share":
			# Level 23: of the blocks bitten through, the share the regeneration
			# block grew back (at least `min` wounds, so a body never bitten
			# does not pass on nothing).
			var broken := int(colony_stats.get("broken", 0))
			return not extinct and broken >= int(ch.get("min", 20)) and 100 * int(colony_stats.get("healed", 0)) >= int(ch.n) * broken
		"floor":
			# Level 22: never fewer than n from `from` to `by` (the famine).
			return not extinct and floor_low(float(ch.from), float(ch.by)) >= int(ch.n)
		"whole":
			return not extinct and int(colony_stats.get("whole", 0)) >= int(ch.n)
		"healed":
			# Level 23: broken blocks grown back beside a working regeneration block.
			return not extinct and int(colony_stats.get("healed", 0)) >= int(ch.n)
		"algae_left":
			return not extinct and algae0 > 0 and float(algae_now) >= float(algae0) * float(ch.frac)
		"patches_all":
			return not extinct and patches_won >= level.goal.patches.size()
		"cold_lineage":
			return not extinct and cold_share >= float(ch.frac)
		"alive_end":
			return not extinct and alive >= int(ch.n)
		"o2_end":
			return not extinct and o2_mean >= float(ch.frac)
		"alive_b":
			return not extinct and alive2 >= int(ch.n)
		"symb_by":
			return symb_by_t >= 0.0 and symb_by_t <= float(ch.seconds) and not extinct
		"both_toxins":
			return not extinct and tox_used[0] and tox_used[1]
		"acid_max":
			return not extinct and _sim != null and int(_sim.get_stats().species[sp].acid) <= int(ch.n)
		"slime_by":
			return not extinct and goal_met and goal_time <= float(ch.seconds)
		"helio_by":
			return not extinct and goal_met and goal_time <= float(ch.seconds)
		"never_frozen":
			return not extinct and _sim != null and int(_sim.get_stats().species[sp].temp) <= int(ch.n)
		"net_push_by":
			return not extinct and net_done >= 0.0 and net_done <= float(ch.seconds)
		"o2_deaths_max":
			return not extinct and alive2 > 0 and o2_dead <= int(ch.n)
		"zones_held":
			return not extinct and held.size() > 0 and held.all(func(v: int) -> bool: return v >= int(ch.n))
		"first_kill":
			return first_kill >= 0.0 and first_kill <= float(ch.seconds)
		"uses_state":
			return not extinct and uses_state
		"eaten_max":
			return not extinct and eaten <= int(ch.n)
		"lysed_max":
			return not extinct and lysed <= int(ch.n)
		"zone_by":
			return zone_by_t >= 0.0 and zone_by_t <= float(ch.seconds)
		"giants_zero":
			return not extinct and giants_zero >= 0.0
		"rival_under":
			return not extinct and rival_alive <= int(ch.n)
		"immune_share":
			return not extinct and alive > 0 and float(immune) >= float(ch.frac) * float(alive)
		"boss_dead":
			# (by: it has to starve before that time, level 24's rage.)
			return not extinct and boss_dead >= 0.0 and boss_dead < float(ch.get("by", INF))
		"rival_dead":
			return not extinct and rival_dead >= 0.0
		"outnumber_x":
			return not extinct and (rival_dead >= 0.0 or float(alive) >= float(ch.ratio) * float(maxi(rival_alive, 1)))
		"blooms":
			var bc := blooms_counted()
			return not extinct and bc[1] > 0 and float(bc[0]) >= float(ch.frac) * float(bc[1])
	return false


func stars() -> Array:
	var thrifty: bool = shots <= int(level.star_shots) if level.has("star_shots") else budget_used <= float(level.star_budget)
	if level.has("star_blocks"):
		thrifty = blocks_used > 0 and blocks_used <= int(level.star_blocks)
	return [goal_met, goal_met and challenge_met(), goal_met and thrifty]


# The quantity the prediction asked about, at the end of the run.
func predicted_value() -> int:
	match level.predict.metric:
		"zone_count":
			return zone_now
		"first_in":
			return int(first_in) if first_in >= 0.0 else 100000
	return alive


func prediction_index() -> int:
	var v := predicted_value()
	var opts: Array = level.predict.options
	for k in opts.size():
		if v >= int(opts[k][1]) and v < int(opts[k][2]):
			return k
	return opts.size() - 1


# Runs a level headless (no rendering) with a design: for control
# experiments and the level bot. Returns the evaluator.
static func simulate(l: Dictionary, design: Dictionary, seed: int, step := 1.0 / 15.0) -> LevelEval:
	var run := prepare(l, design, seed, 1)
	var sim: SimCore = run.sim
	var ev: LevelEval = run.eval
	while run.t < float(l.time_limit) and not ev.extinct:
		advance(run, step)
	ev.finish()
	return ev


# A level run as plain data, for headless runs and the side-by-side bench:
# the sim (world built, the design released), its evaluator and the clock.
static func prepare(l: Dictionary, design: Dictionary, seed: int, threads := 8) -> Dictionary:
	var sim := SimCore.new()
	sim.set_max_threads(threads)
	sim.setup(Vector2(2200, 2200), seed)
	sim.set_dish(Vector2(1100, 1100), 1060.0)
	# (A lambda captures locals by value: count in an array.)
	var count := [0]
	Worlds.populate(sim, l.world, func(params: Dictionary, _label: String) -> void:
		sim.add_species(params)
		count[0] += 1)
	var n: int = count[0]
	sim.add_species(level_params(l, design.params))
	var ev := LevelEval.new(l, n, float(design.used))
	ev.rng.seed = seed
	ev.founder = {topt = float(design.params.get("temp_opt", 12.0)), tol = float(design.params.get("temp_tol", 2.5))}
	sim.spawn(n, l.release.at, int(l.release.count), 60.0)
	if l.has("phage"):
		var ph: Dictionary = (l.phage as Dictionary).duplicate()
		ph.host = int(l.goal.get("rival", n))
		ph.merge(virus_params(design.get("virus", {})), true)
		sim.set_phage(ph)
	if l.has("giant"):
		start_giants(sim, l, n)
	if l.has("slug"):
		start_slug(sim, l, n)
	if l.has("net"):
		sim.set_net(l.net)
	if l.has("helio"):
		sim.set_helio(l.helio)
	if l.has("slime"):
		sim.set_slime(l.slime)
	if l.has("colony"):
		sim.set_colony(l.colony)
		ev.blocks_used = (design.params.get("blocks", []) as Array).size()
	# Level 8: the second species beside the first.
	for k in (design.get("extra", []) as Array).size():
		var pb: Dictionary = level_params(l, design.extra[k])
		sim.add_species(pb)
		var rb: Dictionary = l.get(["release_b", "release_c"][mini(k, 1)], l.get("release_b", l.release))
		sim.spawn(n + 1 + k, rb.at, int(rb.count), 60.0)
		if k == 0:
			ev.sp2 = n + 1 + k
		else:
			ev.sp3 = n + 1 + k
		ev.uses_state = deck_uses(design.extra[k].get("deck", []), int(l.challenge.get("state", -1)))
	var pulses: Dictionary = l.get("pulses", {})
	return {sim = sim, eval = ev, t = 0.0, next_obs = 0.0, next_pulse = float(pulses.get("every", -1.0)), level = l, fired = {},
		plan = design.get("plan", []).duplicate(), feed = design.get("feed", false), feed_pts = 60.0, feed_cool = 0.0, feed_t = 0.0, feeds = 0}


# Level 20: the rules of the slug; it crawls to the goal's light.
static func start_slug(sim: SimCore, l: Dictionary, host: int) -> void:
	var p: Dictionary = (l.slug as Dictionary).duplicate()
	p.host = host
	p.target = l.goal.zone.center
	p.stay = l.goal.zone.radius
	sim.set_slug(p)


# Level 19: the giants, drifting in the water before the first cell is out.
static func start_giants(sim: SimCore, l: Dictionary, host: int) -> void:
	var gv: Dictionary = (l.giant as Dictionary).duplicate()
	gv.host = host
	sim.set_giant(gv)
	# (Around the release, not on it: the first few seconds are the player's.)
	for k in int(gv.start):
		var r: float = lerpf(float(gv.inner), float(gv.spread), fposmod(k * 0.618034, 1.0))
		sim.add_giants(Vector2(1100, 1100) + Vector2.from_angle(k * 2.399963) * r, 40.0, 1)


# Where a lot of them drifts in: together, so a drop can be waiting there.
static func wave_pos(e: Dictionary) -> Vector2:
	return Vector2(1100, 1100) + Vector2.from_angle(float(e.at) * 0.71) * 560.0


# The middle of the biggest gathering of giants, roughly, for a drop.
static func giant_thick(sim: SimCore) -> Vector2:
	var ps: PackedVector2Array = sim.get_giant_positions()
	var best := Vector2(1100, 1100)
	var most := -1
	for p: Vector2 in ps:
		var n := 0
		for q: Vector2 in ps:
			if p.distance_squared_to(q) < 14400.0:
				n += 1
		if n > most:
			most = n
			best = p
	return best


# The player's virus (level 18), points 1..5 on each trait, as the kernel's
# numbers. Shell: lasts longer, holds on worse.
static func virus_params(v: Dictionary) -> Dictionary:
	if v.is_empty():
		return {}
	var shell := float(v.shell)
	return {"yield": 10 + 10 * int(v.burst), "burst": 30.0 - 5.0 * float(v.speed), "life": 4.0 * pow(2.0, shell - 1.0),
		"stick": 0.05 * float(v.stick) * (1.0 - 0.14 * (shell - 1.0)), "diffuse": 100.0 * (1.0 - 0.15 * (shell - 1.0)),
		"temperate": bool(v.get("temperate", false))}


# The released species' parameters as the level runs them: a level may set
# how long its cells live (`lifespan`, level 3: cold water, slow lives).
# Chapter 6 boss: the point on the net's rim with the most oxygen.
static func net_rim(sim: SimCore) -> Vector2:
	var nf: PackedFloat32Array = sim.get_net_field()
	var of: PackedFloat32Array = sim.get_o2_field()
	var g: Vector2i = sim.get_grid_size()
	var cell: float = sim.get_cell_size()
	var best := -1.0
	var at := Vector2(1100, 1100)
	for j in range(0, g.y, 2):
		for i in range(0, g.x, 2):
			var c := j * g.x + i
			if nf[c] > 0.3 and nf[c] < 0.9 and of[c] > best:
				best = of[c]
				at = Vector2((i + 0.5) * cell, (j + 0.5) * cell)
	return at


static func level_params(l: Dictionary, params: Dictionary) -> Dictionary:
	if not l.has("lifespan") and not l.has("keep_act") and not l.has("prophage") and not params.has("blocks"):
		return params
	var p := params.duplicate()
	if params.has("blocks"):
		# (The level's own balance, then any probe's on top.)
		var tune: Dictionary = (l.get("colony", {}) as Dictionary).get("tune", {}).duplicate()
		tune.merge(params.get("tune", {}), true)
		p.merge(Colony.params(params.blocks, tune), true)
	if l.has("lifespan"):
		p.lifespan = float(l.lifespan) * float(params.get("life", 1.0)) # (chapter 7: the life slider still counts)
	if l.has("keep_act"):
		p.keep_act = int(l.keep_act)
	if l.has("prophage"):
		p.prophage = float(l.prophage)
	return p


# The middle of the rival's biggest crowd, roughly: the cell with most others
# within 120 µm, from a sample.
static func rival_thick(sim: SimCore, s: int) -> Vector2:
	var ps: PackedVector2Array = sim.get_positions(s)
	var best := Vector2(1100, 1100)
	var most := -1
	var step: int = maxi(1, ps.size() / 40)
	for i in range(0, ps.size(), step):
		var n := 0
		for j in range(0, ps.size(), step):
			if ps[i].distance_squared_to(ps[j]) < 14400.0:
				n += 1
		if n > most:
			most = n
			best = ps[i]
	return best


# Announced world events (level data `events`), applied between t0 and t1
# (seconds since the release). Returns what to tell the player now:
# [{text, pos?}]. `fired` remembers one-off announcements.
#   chill  {at, over, from, to}: the whole dish's water cools (or warms)
#          linearly from `from` to `to` °C over `over` seconds from `at`
static func tick_events(l: Dictionary, sim: SimCore, t0: float, t1: float, fired: Dictionary) -> Array:
	var said := []
	for k in l.get("events", []).size():
		var e: Dictionary = l.events[k]
		match e.kind:
			"cycle":
				# Chapter 7: day, then the long night (dark, frozen), over and over.
				var per := float(e.day) + float(e.night)
				var ph := fposmod(t1 - float(e.get("offset", 0.0)), per)
				var dark := ph >= float(e.day)
				var nth := int(floor((t1 - float(e.get("offset", 0.0))) / per))
				if not dark and ph >= float(e.day) - 10.0 and not fired.has("%d_warn%d" % [k, nth]):
					fired["%d_warn%d" % [k, nth]] = true
					said.append({text = "长夜 10 秒后到来：光会消失，水会结冰"})
				if dark != bool(fired.get("%d_dark" % k, false)):
					fired["%d_dark" % k] = dark
					sim.set_night(dark)
					sim.set_light_scale(float(e.get("night_light", 0.03)) if dark else 1.0)
					sim.set_base_environment({temp = float(e.cold) if dark else float(e.warm)})
					said.append({text = "长夜来了：全暗，水温降到 %d°C" % int(e.cold) if dark else "天亮了：水温回到 %d°C" % int(e.warm)})
			"rain":
				# Chapter 8 (8-4): dry spells and acid rain, over and over.
				var per := float(e.dry) + float(e.wet)
				var ph := fposmod(t1 - float(e.get("offset", 0.0)), per)
				var wet := ph >= float(e.dry)
				var nth := int(floor((t1 - float(e.get("offset", 0.0))) / per))
				if not wet and ph >= float(e.dry) - 10.0 and not fired.has("%d_warn%d" % [k, nth]):
					fired["%d_warn%d" % [k, nth]] = true
					said.append({text = "酸雨 10 秒后到来：酸会从水面往下渗"})
				if wet != bool(fired.get("%d_wet" % k, false)):
					fired["%d_wet" % k] = wet
					sim.set_rain(float(e.level) if wet else 0.0, float(e.get("top", 60.0)))
					said.append({text = "酸雨来了：酸正从水面往下渗" if wet else "雨停了：酸会慢慢退去"})
			"seasons":
				# Chapter 7 (7-4): the bloom moves on with the season.
				for w in e.list.size():
					var se: Dictionary = e.list[w]
					if t1 >= float(se.at) - 12.0 and not fired.has("%d_s%dw" % [k, w]) and w > 0:
						fired["%d_s%dw" % [k, w]] = true
						said.append({text = "季节要变了：12 秒后雪藻会在别处长出来", pos = se.pos})
					if t1 >= float(se.at) and not fired.has("%d_s%d" % [k, w]):
						fired["%d_s%d" % [k, w]] = true
						sim.light_pulse(se.pos, float(se.radius), float(se.power), float(se.seconds))
						sim.add_algae_patch(se.pos, float(se.radius) * 0.6, int(se.get("n", 40)), 20.0)
						if w > 0:
							said.append({text = "新的季节：雪藻在这里长了出来", pos = se.pos})
			"chill":
				var at := float(e.at)
				var end := at + float(e.over)
				if t1 >= at - 10.0 and not fired.has("%d_warn" % k):
					fired["%d_warn" % k] = true
					said.append({text = "寒潮 10 秒后到达：水温将在 %d 秒内从 %d°C 降到 %d°C" % [int(e.over), int(e.from), int(e.to)]})
				if t1 >= at and t0 <= end + 0.5:
					if not fired.has("%d_start" % k):
						fired["%d_start" % k] = true
						said.append({text = "寒潮到达：全皿开始降温"})
					var k2 := clampf((t1 - at) / maxf(float(e.over), 0.01), 0.0, 1.0)
					sim.set_base_environment({temp = lerpf(float(e.from), float(e.to), k2)})
					if k2 >= 1.0 and not fired.has("%d_end" % k):
						fired["%d_end" % k] = true
						said.append({text = "降温结束：水温稳定在 %d°C" % int(e.to)})
			"giant_wave":
				# Level 19: another lot drifts in from the edges of the water.
				var gat := float(e.at)
				if t1 >= gat - 10.0 and not fired.has("%d_warn" % k):
					fired["%d_warn" % k] = true
					said.append({text = "又一批巨毒囊正漂过来：10 秒后到达", pos = wave_pos(e)})
				if t1 >= gat and not fired.has("%d_start" % k):
					fired["%d_start" % k] = true
					sim.add_giants(wave_pos(e), 70.0, int(e.n))
					said.append({text = "又有 %d 颗巨毒囊漂了进来" % int(e.n), pos = wave_pos(e)})
			"phage_storm":
				# Level 16: phages through the whole dish at once.
				var sat := float(e.at)
				if t1 >= sat - 15.0 and not fired.has("%d_warn" % k):
					fired["%d_warn" % k] = true
					said.append({text = "冰缝上游涌来一大片裂囊针：15 秒后到达"})
				if t1 >= sat and not fired.has("%d_start" % k):
					fired["%d_start" % k] = true
					sim.add_phages(Vector2(1100, 1100), 1040.0, int(e.n))
					said.append({text = "大爆发：裂囊针铺满了整片水域"})
			"hunt_waves":
				# Levels 22-23: the hunters to a timetable, the same every run.
				# waves [[t, total, pos]]: from t on, `total` hunters are kept in
				# the water (one lost is replaced from pos after `gap` s); each
				# rise is announced `warn` s ahead, marked where they come in.
				var hs := int(e.species)
				var have := sim.get_positions(hs).size()
				var want := 0
				var from := Vector2.ZERO
				for w in e.waves.size():
					var wave: Array = e.waves[w]
					var wt := float(wave[0])
					if t1 >= wt - float(e.warn) and not fired.has("%d_w%d" % [k, w]) and w > 0:
						fired["%d_w%d" % [k, w]] = true
						said.append({text = "巨噬者 %d 秒后增援：入口已在皿边标出，之后陆续游进来，最多 %d 只" % [int(e.warn), int(wave[1])], pos = wave[2]})
					if t1 >= wt:
						want = int(wave[1])
						from = wave[2]
				var key := "%d_last" % k
				if have < want and t1 - float(fired.get(key, -999.0)) >= float(e.gap):
					fired[key] = t1
					sim.spawn(hs, from, 1, 30.0)
			"rage":
				# Level 24: near starving the guardian goes into a frenzy (suction
				# and speed; what it spits it pulls straight back): `below` its
				# energy share, announced at `warn_below`. (Or at a fixed `at`.)
				var low := 1.0
				if e.has("below"):
					var bp: PackedVector2Array = sim.get_positions(int(l.goal.boss))
					if bp.is_empty():
						continue
					low = float(sim.get_agent(sim.find_agent(bp[0], 1.0)).get("energy_frac", 1.0))
				var warn_now: bool = low <= float(e.warn_below) if e.has("below") else t1 >= float(e.at) - float(e.get("warn", 8.0))
				var go_now: bool = low <= float(e.below) if e.has("below") else t1 >= float(e.at)
				if warn_now and not fired.has("%d_warn" % k):
					fired["%d_warn" % k] = true
					said.append({text = "喷口守卫饿急了：再饿一点它就会暴走，吸力和速度大涨，吐出的群体也只放过两秒"})
				if go_now and not fired.has("%d_start" % k):
					fired["%d_start" % k] = true
					fired["rage_t"] = t1
					sim.set_rot_rage(float(e.mult))
					said.append({text = "喷口守卫暴走：吸力和速度大涨，吐出的群体两秒后又会被吸回去"})
			"famine":
				# The light fails: the algae stop growing and fade, for `over` s.
				var fat := float(e.at)
				var fend := fat + float(e.over)
				if t1 >= fat - 10.0 and not fired.has("%d_warn" % k):
					fired["%d_warn" % k] = true
					said.append({text = "荒年 10 秒后开始：%d 秒里藻类不再生长，只会越吃越少" % int(e.over)})
				if t1 >= fat and not fired.has("%d_start" % k):
					fired["%d_start" % k] = true
					# (fade: how fast the clumps left wither meanwhile, 1 = as usual.)
					sim.set_algae_rates(0.0, float(e.get("fade", 1.0)))
					said.append({text = "荒年开始：藻类停止生长"})
				if t1 >= fend and not fired.has("%d_end" % k):
					fired["%d_end" % k] = true
					var r: Array = l.world.get("algae_rates", [1.0, 1.0])
					sim.set_algae_rates(float(r[0]), float(r[1]))
					said.append({text = "荒年结束：藻类重新开始生长"})
	return said


# Level 24's bot playing the lever (design.feed): on a player's points
# (interventions.gd: 60 to start, 0.5 + 0.05 a body each second, a current 30
# and 6 s to cool), a full current on the body nearest the guardian's mouth
# whose rim armour is whole, toward the mouth, so it chews and spits once more.
static func _feed(run: Dictionary, step: float) -> void:
	var sim: SimCore = run.sim
	run.feed_cool = maxf(0.0, run.feed_cool - step)
	run.feed_t += step
	if run.feed_t < 0.5:
		return
	var dt: float = run.feed_t
	run.feed_t = 0.0
	var mine := sim.get_positions(run.eval.sp).size()
	run.feed_pts = minf(300.0, run.feed_pts + (0.5 + 0.05 * minf(float(mine), 400.0)) * dt)
	if run.feed_pts < 30.0 or run.feed_cool > 0.0:
		return
	var rot: PackedFloat32Array = sim.get_rotifers(1.0)
	if rot.size() < 6:
		return
	var mouth := Vector2(rot[0], rot[1]) + Vector2.from_angle(rot[2]) * 88.0
	var worn: PackedFloat32Array = sim.get_worn(1.0)
	if int(run.feed) == 3:
		# The irritant (30 points, 8 s): when a body with cracked armour is in
		# its pull, make it draw its corona in.
		if sim.get_rotifer_retract()[0] > 0.0:
			return
		# A body in its mouth: make it let go.
		if rot[4] > 0.0:
			if sim.irritate(mouth, 60.0) > 0.0:
				run.feed_pts -= 30.0
				run.feed_cool = 8.0
				run.feeds += 1
			return
		for w in range(0, worn.size(), 5):
			if Vector2(worn[w], worn[w + 1]).distance_to(mouth) < 420.0 and worn[w + 4] <= 0.0:
				if sim.irritate(mouth, 60.0) > 0.0:
					run.feed_pts -= 30.0
					run.feed_cool = 8.0
					run.feeds += 1
				return
		return
	var cs: PackedFloat32Array = sim.get_colonies()
	# feed 1: the whole body nearest the mouth; feed 2: the nearest one still
	# outside the pull (450 µm), carried into it.
	var near := 70.0 if int(run.feed) == 1 else 450.0
	var best := Vector2.INF
	var bd := 520.0 if int(run.feed) == 1 else 850.0
	for k in range(0, cs.size(), 6):
		var p := Vector2(cs[k + 1], cs[k + 2])
		var d := p.distance_to(mouth)
		if d >= bd or d < near:
			continue
		var cracked := false
		for w in range(0, worn.size(), 5):
			if Vector2(worn[w], worn[w + 1]).distance_squared_to(p) < 4.0:
				cracked = true
				break
		if not cracked:
			best = p
			bd = d
	if not best.is_finite():
		return
	run.feed_pts -= 30.0
	run.feed_cool = 6.0
	run.feeds += 1
	sim.add_current(best, 170.0, (mouth - best).normalized() * 70.0, 30.0)


# One tick of a prepared run: step, announced pulses, observation.
static func advance(run: Dictionary, step: float) -> void:
	var sim: SimCore = run.sim
	sim.step(step)
	run.t += step
	var l: Dictionary = run.level
	tick_events(l, sim, run.t - step, run.t, run.fired)
	# Scripted interventions (the level bot plays them as a player would):
	# [{at, kind = "current", pos, velocity}] (a player's current: 170 µm
	# across, 30 s).
	while not run.plan.is_empty() and run.t >= float(run.plan[0].at):
		var iv: Dictionary = run.plan.pop_front()
		if iv.kind == "stir":
			sim.add_stir(iv.pos, 200.0, 30.0)
			run.eval.shots += 1
			continue
		if iv.kind == "iron":
			# Chapter 6: where the net's rim has the most oxygen (a player sees
			# it on the oxygen map), or where the plan says.
			sim.add_iron(iv.get("pos", net_rim(sim)), 220.0, 40.0)
			run.eval.shots += 1
			continue
		if iv.kind == "phage":
			# Where the rival is thickest (a player sees that much).
			run.eval.shots += 1
			run.eval.shot_times.append(run.t)
			sim.add_phages(rival_thick(sim, int(l.goal.rival)), 90.0, int(iv.n))
		elif iv.kind == "drop_giants":
			run.eval.shots += 1
			run.eval.shot_times.append(run.t)
			sim.add_phages(giant_thick(sim), 90.0, int(iv.n))
		elif iv.kind == "drop_wave":
			run.eval.shots += 1
			run.eval.shot_times.append(run.t)
			sim.add_phages(wave_pos(l.events[int(iv.wave)]), 90.0, int(iv.n))
		elif iv.kind == "drop_own":
			run.eval.shots += 1
			run.eval.shot_times.append(run.t)
			sim.add_phages(rival_thick(sim, run.eval.sp), 90.0, int(iv.n))
		elif iv.kind == "current_own":
			sim.add_current(rival_thick(sim, run.eval.sp), 170.0, iv.velocity, 30.0)
		elif iv.kind == "nutrient_at":
			sim.add_nutrient(iv.pos, 45.0, 150.0)
		elif iv.kind == "heat_at":
			sim.add_temp_spot(iv.pos, 190.0, 12.0, 40.0)
		elif iv.kind == "heat_rival":
			sim.add_temp_spot(rival_thick(sim, int(l.goal.rival)), 190.0, 12.0, 40.0)
		elif iv.kind == "current":
			sim.add_current(iv.pos, 170.0, iv.velocity, 30.0)
		elif iv.kind == "heat":
			# A warm spot (190 µm, +12 °C, 40 s) on the middle of the player's cells.
			var ps: PackedVector2Array = sim.get_positions(run.eval.sp)
			if ps.size() > 0:
				var c := Vector2.ZERO
				for p in ps:
					c += p
				sim.add_temp_spot(c / ps.size(), 190.0, 12.0, 40.0)
	if run.feed:
		_feed(run, step)
	if run.next_pulse > 0.0 and run.t >= run.next_pulse:
		var pulses: Dictionary = l.pulses
		sim.add_nutrient(pulses.at, pulses.radius, pulses.amount)
		run.next_pulse += float(pulses.every)
	if run.t >= run.next_obs:
		run.eval.observe(sim, run.t)
		run.next_obs += 0.5


# Does a deck switch into state `st` (a "进入 X" card)?
static func deck_uses(deck: Array, st: int) -> bool:
	return st >= 0 and deck.any(func(c: Dictionary) -> bool: return Rules.target_state(int(c.act)) == st)


# Species parameters and budget use for a gene list (the designer's own
# mapping), for headless runs.
static func design_from_genes(genes: Array, deck: Array, color := Color(0.42, 0.8, 0.88), temp_opt := 12.0, mutates := true,
		organs := [], level_id := "") -> Dictionary:
	var used := 0.0
	for g in genes:
		used += float(g) - 1.0
	var params := Organs.apply({
		color = color, radius = 5.5, speed = genes[0], vision = genes[1], armor = genes[2], attack = genes[3],
		fertility = genes[4], efficiency = genes[5], neural = genes[6], lifespan = 90.0, cohesion = 0.2,
		temp_opt = temp_opt, temp_tol = genes[7], deck = deck, mutates = mutates}, organs)
	params.merge(Rules.masks(level_id, organs), true)
	return {used = used, params = params}
