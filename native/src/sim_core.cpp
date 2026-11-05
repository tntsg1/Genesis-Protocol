#include "sim_core.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <thread>

using namespace godot;

namespace {
constexpr float TAU = 6.28318530718f;
constexpr float PI_F = 3.14159265359f;
constexpr int CAUSE_STARVE = 0;
constexpr int CAUSE_EATEN = 1;
constexpr int CAUSE_AGE = 2;
constexpr int CAUSE_TEMP = 3; // starved while the water's heat or cold did most of the draining
constexpr int CAUSE_ACID = 4;
constexpr int CAUSE_PHAGE = 5;
constexpr int CAUSE_STALK = 6; // gave itself to a fruiting body's stalk
constexpr int CAUSE_HATCH = 7; // its young left and the body it built for them died (Volvox)
constexpr int CAUSE_O2 = 8;    // starved while oxygen did most of the draining (an anaerobe, chapter 6)
constexpr float COL_BLOCK = 22.0f;  // one block's side, µm (scripts/colony.gd has the same)
constexpr float COL_GROW = 14.0f;   // seconds for a hatchling to reach full size
constexpr float COL_GHOST = 16.0f;  // seconds the empty shell lasts
constexpr float COL_SWALLOW = 1.3f; // seconds a hunter takes to draw a body in

// Environment (GDD 5.3).
constexpr float TEMP_COST = 0.05f;      // energy/s per degree outside the band
constexpr float TEMP_SEVERE = 10.0f;    // beyond this many degrees it also hurts
constexpr float TEMP_HURT = 0.12f;      // extra energy/s per degree past severe
constexpr float CHEMO_RATE = 4.0f;      // energy/s at full vent chemistry (shared with neighbours)
constexpr float CHEMO_SEED = 0.35f;     // vent-borne chemosynthetic cells per second
constexpr float PHOTO_RATE = 5.0f;      // energy/s at light 1 for a producer (光合膜; shared with neighbours)
constexpr float ACID_COST = 1.5f;       // energy/s at acidity 1 (armour softens it)
constexpr float TOL_UPKEEP = 0.04f;     // per tolerance level around the default 2.5
// Gene trade-offs (DECISIONS 第十四轮 Q32): no gene is "max it and done".
constexpr float METAB_DIVIDE = 0.25f;   // r^2 more energy to divide per metabolism level above 3
constexpr float FERT_LEAN = 0.05f;      // share of the split the child loses per fertility level above 2
constexpr float SENSE_SEEN = 0.12f;     // hunters notice keen-eyed prey this much further per sense level above 2
constexpr float SPINE_HURT = 0.3f;      // share of a full bite a spiny prey costs its hunter
// Signals.
constexpr float SIGNAL_EMIT = 6.0f;     // concentration added per second
constexpr float SIGNAL_COST = 0.2f;     // energy/s while emitting
// (Level 11, food calls: a call has to carry a few hundred µm, so signals
// fade slowly and spread wide; a cell smells far further than it sees.)
constexpr float SIGNAL_DECAY = 0.2f;    // per second
constexpr float SIGNAL_DIFFUSE = 1.5f;
constexpr float SMELL_RANGE = 240.0f;   // how far off a chemoreceptor picks up a trail
constexpr float SMELL_MIN = 0.004f;     // the faintest trail it follows
// Digestive enzyme (level 13): fades fast and spreads little, so one cell's
// is too thin to matter; a crowd secreting together makes it thick.
constexpr float ENZ_EMIT = 3.0f;
constexpr float ENZ_DECAY = 0.3f;
constexpr float ENZ_DIFFUSE = 1.5f;
constexpr float ENZ_MIN = 0.6f;         // below this it does nothing (about one cell's own)
constexpr float ENZ_FULL = 2.5f;        // enzyme at which tough algae yield in full
constexpr float SECRETE_COST = 1.0f;    // energy/s while secreting (signals cost SIGNAL_COST)
// Phages (level 15): the seconds after landing, shared with the drawn scene
// in scripts/phage_layer.gd. Tail fires at ATTACH, the DNA is in by INJECT.
constexpr float PHAGE_ATTACH = 1.2f;
constexpr float PHAGE_INJECT = 2.2f;
constexpr float PHAGE_FLING_DRAG = 1.2f;
constexpr float PHAGE_DRIFT_T = 1.6f;   // seconds a drift lasts: jostled by the water, a phage wanders smoothly
constexpr float PHAGE_SPILL = 1.1f;     // the new phages come out of a burst cell over this long
constexpr float PHAGE_REACH = 2.0f;     // how close to the membrane counts as touching
constexpr float PHAGE_FLING = 16.0f;    // µm/s out of a bursting cell
constexpr float SLUG_HEAT = 8.0f;       // degrees past its tolerance before the water burns a slug
constexpr float S_SPORE_EDGE = 6.0f;    // how near the dish's wall a spore may land
constexpr float GIANT_R = 8.0f;         // a giant virus: a little bigger than a cell
constexpr float GIANT_MIN = 0.03f;      // the least share of its giants a stolen factory still makes
constexpr float GIANT_SETUP = 3.0f;     // seconds a new factory takes to turn out its first capsid
constexpr float PHAGE_CUT_NEW = 8.0f;   // seconds to find, cut and store a piece of a phage's DNA, the first time
constexpr float PHAGE_CUT_OLD = 3.6f;   // ... and with the memory already there
constexpr float WAKE_HUNGER = 0.35f;    // energy share below which a carried phage may wake
constexpr float WAKE_HEAT = 3.0f;       // degrees past comfort at full stress
constexpr float WAKE_CARRIED = 0.25f;   // per second at full stress, for a phage that landed and settled
const Color MEMORY_TINT(0.04f, 0.76f, 0.6f);

// Algae.
constexpr float ALGAE_MAX_E = 30.0f;     // a full-grown clump
constexpr float ALGAE_LIGHT = 10.0f;     // light -> energy per second at light 1
constexpr float ALGAE_UPTAKE = 1.5f;     // dissolved nutrient taken per second
constexpr float ALGAE_UPKEEP = 0.015f;   // fraction of energy lost per second
// Shells.
constexpr float SHELL_DECAY = 0.25f;     // energy released per second (base)
constexpr float SHELL_DECAY_FRAC = 0.04f;
// Digestion efficiencies (the rest is dissipated).
constexpr float EAT_ALGAE_EFF = 0.85f;
constexpr float EAT_PREY_EFF = 0.6f;
constexpr float DIGEST_TIME = 6.0f;      // a predator rests this long after a kill
constexpr float EAT_SHELL_EFF = 0.3f;   // strong jaws (attack >= 3.2); weaker ones digest shells better

inline float clampf(float v, float a, float b) { return v < a ? a : (v > b ? b : v); }
inline float lerpf(float a, float b, float t) { return a + (b - a) * t; }
inline float angle_lerp(float a, float b, float t) {
	float d = std::remainder(b - a, TAU);
	return a + d * t;
}
} // namespace

SimCore::SimCore() {
	const int n = MAX_AGENTS;
	for (auto *v : { &id, &sp, &lineage, &gen, &target }) {
		v->resize(n);
	}
	for (auto *v : { &x, &y, &px, &py, &vx, &vy, &heading, &pheading, &energy, &age, &phase, &cooldown, &wander, &digest,
				 &t_speed, &t_vision, &t_armor, &t_attack, &t_fertility, &t_efficiency }) {
		v->resize(n);
	}
	for (auto *v : { &alive, &bitten, &action, &crowd }) {
		v->resize(n);
	}
	inf_t.resize(n);
	inf_ang.resize(n);
	inf_fate.resize(n);
	immune.resize(n);
	carry.resize(n);
	hijack.resize(n);
	slug.resize(n);
	gest.assign(n, -1.0f);
	gwait.assign(n, 0.0f);
	emb.assign(n * COL_GERMS, 0.0f);
	store.assign(n, 0.0f);
	cmark.assign(n * COL_MAXB, 0.0f);
	cdmg.assign(n * COL_MAXB, 0.0f);
	cbroken.assign(n * COL_MAXB, 0);
	cslow.assign(n, 0.0f);
	cspurn.assign(n, 0.0f);
	cpiece.assign(n, 0);
	rot_meal.assign(n, -1);
	rot_t.assign(n, 0.0f);
	cheld.assign(n, 0);
	sl_ox.resize(n);
	sl_oy.resize(n);
	spore.resize(n);
	anext.resize(n);
	gnext.resize(MAX_GIANTS);
	scans.resize(n);
	cards.resize(n * MAX_CARDS);
	for (auto *v : { &ncards, &sense }) {
		v->resize(n);
	}
	fired.resize(n);
	state.resize(n);
	st_time.resize(n);
	for (auto *v : { &t_neural, &hurt, &threat_d, &tgx, &tgy, &t_topt, &t_ttol, &stress_t, &stress_a, &join,
				 &sw, &psw, &curl, &ha, &hb, &vs, &angv, &latch, &gulp_t, &gulp_r, &gulp_lx, &gulp_ly, &gulp_h, &gulp_ph }) {
		v->resize(n);
	}
	gulp_sp.resize(n);
	gulp_lin.resize(n);
	pair.resize(n);
	join_mut.resize(n);
	for (auto *v : { &al_x, &al_y, &al_px, &al_py, &al_e, &al_ph, &al_bud }) {
		v->resize(MAX_ALGAE);
	}
	lnext.resize(MAX_ALGAE);
	for (auto *v : { &sh_x, &sh_y, &sh_e, &sh_e0, &sh_h, &sh_r, &sh_ph }) {
		v->resize(MAX_SHELLS);
	}
	sh_sp.resize(MAX_SHELLS);
	sh_lineage.resize(MAX_SHELLS);
	snext.resize(MAX_SHELLS);
	for (auto *v : { &ph_x, &ph_y, &ph_px, &ph_py, &ph_vx, &ph_vy, &ph_dx, &ph_dy, &ph_life, &ph_age }) {
		v->resize(MAX_PHAGES);
	}
	ph_seed.resize(MAX_PHAGES);
}

// --- random -----------------------------------------------------------------

float SimCore::randf() {
	rng ^= rng << 13;
	rng ^= rng >> 7;
	rng ^= rng << 17;
	return (float)((rng >> 40) & 0xFFFFFF) / 16777216.0f;
}

float SimCore::rand_range(float a, float b) { return a + (b - a) * randf(); }

float SimCore::gauss() {
	float u = std::max(1e-6f, randf());
	float v = randf();
	return std::sqrt(-2.0f * std::log(u)) * std::cos(TAU * v);
}

// --- world ------------------------------------------------------------------

void SimCore::setup(Vector2 world_size, int seed) {
	world_w = world_size.x;
	world_h = world_size.y;
	gw = (int)std::ceil(world_w / cell);
	gh = (int)std::ceil(world_h / cell);
	nutrient.assign(gw * gh, 0.0f);
	light.assign(gw * gh, 0.01f);
	flow_u.assign(gw * gh, 0.0f);
	flow_v.assign(gw * gh, 0.0f);
	flux_tmp.assign(gw * gh, 0.0f);
	flow_age = 1000;
	spots.clear();
	light_pulses.clear();
	zones.clear();
	light_base.assign(gw * gh, 0.01f);
	temp.assign(gw * gh, base_temp);
	acid.assign(gw * gh, base_acid);
	rad.assign(gw * gh, base_rad);
	vent.assign(gw * gh, 0.0f);
	chem.assign(gw * gh, 0.0f);
	sig_a.assign(gw * gh, 0.0f);
	sig_b.assign(gw * gh, 0.0f);
	enzyme.assign(gw * gh, 0.0f);
	o2.assign(gw * gh, 0.0f);
	o2_on = false;
	net.assign(gw * gh, 0.0f);
	net_tmp.assign(gw * gh, 0.0f);
	net_on = false;
	net_phase = 0;
	net_fed = 0.0;
	net_caught = 0;
	o2_phase = 0;
	o2_made = o2_breathed = 0.0;
	irons.clear();
	vent_total = 0.0;
	signal_phase = 0;
	agw = (int)std::ceil(world_w / acell);
	agh = (int)std::ceil(world_h / acell);
	ahead.assign(agw * agh, -1);
	lhead.assign(agw * agh, -1);
	shead.assign(agw * agh, -1);
	ghead.assign(agw * agh, -1);
	species.clear();
	max_extent = 6.0f;
	count = algae = shells = phages = 0;
	phage_host = -1;
	phage_rain = phage_rain_from = phage_rain_debt = 0.0f;
	phage_temperate = false;
	phage_virophage = false;
	giants.clear();
	giant_host = -1;
	giant_taken = giant_hijacked = 0;
	giant_saved = 0.0f;
	slugs.clear();
	grits.clear();
	ghosts.clear();
	stream_x = stream_y = 0.0f;
	embryos_lost = col_hatched = col_born = 0;
	col_bites = col_blocked = col_eaten = 0;
	col_splits = col_whole = col_broken = col_healed = 0;
	rot_rage = 1.0f;
	rot_swallowed = rot_spat = rot_eaten = rot_worn = 0;
	rot_retract = rot_retract_last = 0.0f;
	rot_since = 1e9f;
	rot_irritated = rot_rescued = 0;
	slug_host = -1;
	slug_formed = slug_lost = slug_stalked = slug_spored = slug_broke = 0;
	next_id = 1;
	next_lineage = 1;
	sim_time = 0.0;
	energy_in = energy_out = 0.0;
	dish_r = 0.0f;
	rng = 0x9E3779B97F4A7C15ull ^ ((uint64_t)(uint32_t)seed * 0x2545F4914F6CDD1Dull);
	if (rng == 0) {
		rng = 1;
	}
}

int SimCore::add_species(Dictionary p) {
	Species s;
	s.color = p.get("color", Color(0.4, 1.0, 0.85));
	s.diet = (int)p.get("diet", 0);
	s.radius = (float)(double)p.get("radius", 6.0);
	s.mutates = (bool)p.get("mutates", true);
	s.keep_act = (int)p.get("keep_act", -1);
	s.crispr = p.get("crispr", 0.0f);
	s.prophage = p.get("prophage", 0.0f);
	s.cond_mask = (uint32_t)(int64_t)p.get("cond_mask", (int64_t)0xFFFFFFFF);
	s.act_mask = (uint32_t)(int64_t)p.get("act_mask", (int64_t)0xFFFFFFFF);
	s.speed = (float)(double)p.get("speed", 2.5);
	s.vision = (float)(double)p.get("vision", 2.5);
	s.armor = (float)(double)p.get("armor", 1.0);
	s.attack = (float)(double)p.get("attack", 1.0);
	s.fertility = (float)(double)p.get("fertility", 2.5);
	s.efficiency = (float)(double)p.get("efficiency", 2.5);
	s.lifespan = (float)(double)p.get("lifespan", 90.0);
	s.cohesion = (float)(double)p.get("cohesion", 0.0);
	s.bite_taken = (float)(double)p.get("bite_taken", 1.0);
	s.digest_time = (float)(double)p.get("digest", (double)DIGEST_TIME);
	s.engulf = (float)(double)p.get("engulf", 0.0);
	s.burn = (float)(double)p.get("burn", 1.0);
	s.confuse = (float)(double)p.get("confuse", 1.0);
	s.herd = (float)(double)p.get("herd", 0.0);
	s.speed_mult = (float)(double)p.get("speed_mult", 1.0);
	s.spines = (float)(double)p.get("spines", 0.0);
	s.motor_speed = (float)(double)p.get("motor_speed", 1.0);
	s.turn_mult = (float)(double)p.get("turn_mult", 1.0);
	s.move_cost = (float)(double)p.get("move_cost", 1.0);
	s.rest_cost = (float)(double)p.get("rest_cost", 1.0);
	s.store = (float)(double)p.get("store", 0.0);
	s.resp = (int)p.get("resp", 0);
	s.reseed = (bool)p.get("reseed", true);
	s.rotifer = p.get("rotifer", false);
	if (s.rotifer) {
		s.rot_reach = p.get("rot_reach", s.rot_reach);
		s.rot_pull = p.get("rot_pull", s.rot_pull);
		s.rot_cone = p.get("rot_cone", s.rot_cone);
		s.rot_chew = p.get("rot_chew", s.rot_chew);
		s.rot_full = p.get("rot_full", s.rot_full);
		s.rot_fury = p.get("rot_fury", s.rot_fury);
		s.rot_spit = p.get("rot_spit", s.rot_spit);
		s.rot_gain = p.get("rot_gain", s.rot_gain);
		s.rot_bruise = p.get("rot_bruise", s.rot_bruise);
		s.rot_wear = p.get("rot_wear", s.rot_wear);
		s.rot_spurn = p.get("rot_spurn", s.rot_spurn);
		s.rot_cost = p.get("rot_cost", s.rot_cost);
		s.rot_rage_gain = p.get("rot_rage_gain", s.rot_rage_gain);
		s.rot_rage_spurn = p.get("rot_rage_spurn", s.rot_rage_spurn);
	}
	s.organ_mask = (int)p.get("organ_mask", 0);
	s.logic = (bool)p.get("logic", true);
	s.size_factor = std::pow(s.radius / 6.0f, 0.75f);
	s.neural = (float)(double)p.get("neural", 3.0);
	s.temp_opt = (float)(double)p.get("temp_opt", base_temp);
	s.temp_tol = (float)(double)p.get("temp_tol", 2.5);
	Array deck = p.get("deck", Array());
	for (int k = 0; k < deck.size() && k < MAX_CARDS; k++) {
		s.deck.push_back(card_from(deck[k]));
	}
	if (s.deck.empty()) {
		s.deck = default_deck(s.diet);
	}
	s.extent = s.radius;
	PackedVector3Array body = p.get("body", PackedVector3Array());
	for (int i = 0; i < body.size(); i++) {
		s.body.push_back(body[i].x);
		s.body.push_back(body[i].y);
		s.body.push_back(body[i].z);
	}
	s.colony = p.get("colony", false);
	if (s.colony) {
		s.col_speed = p.get("col_speed", 0.0f);
		s.col_turn = p.get("col_turn", 1.0f);
		s.col_bite = p.get("col_bite", 1.0f);
		s.col_keep = p.get("col_keep", 1.0f);
		s.col_e = p.get("col_e", 100.0f);
		s.col_skin = p.get("col_skin", 100.0f);
		int m = (int)(s.body.size() / 3);
		float len = 0.0f, wid = 0.0f;
		for (int k = 0; k < m; k++) {
			uint8_t open = 15;
			for (int j = 0; j < m; j++) {
				float dx = s.body[j * 3] - s.body[k * 3], dy = s.body[j * 3 + 1] - s.body[k * 3 + 1];
				if (std::abs(dx - 1.0f) < 0.1f && std::abs(dy) < 0.1f) {
					open &= ~1;
				} else if (std::abs(dx + 1.0f) < 0.1f && std::abs(dy) < 0.1f) {
					open &= ~2;
				} else if (std::abs(dy - 1.0f) < 0.1f && std::abs(dx) < 0.1f) {
					open &= ~4;
				} else if (std::abs(dy + 1.0f) < 0.1f && std::abs(dx) < 0.1f) {
					open &= ~8;
				}
			}
			s.col_rim.push_back(open);
			int type = (int)s.body[k * 3 + 2];
			s.col_kind.push_back(type == 6 ? 1 : (type == 7 ? 3 : (type == 8 ? 4 : (type == 9 ? 5 : 0))));
			s.col_store += type == 8 ? 1 : 0;
			s.col_rimflags += (type == 1 || type == 0) && open != 0 ? 1 : 0;
			for (int d = 0; d < 4; d++) {
				const float ox = d == 0 ? 1.0f : (d == 1 ? -1.0f : 0.0f), oy = d == 2 ? 1.0f : (d == 3 ? -1.0f : 0.0f);
				int nb = -1;
				for (int j = 0; j < m; j++) {
					if (std::abs(s.body[j * 3] - s.body[k * 3] - ox) < 0.1f && std::abs(s.body[j * 3 + 1] - s.body[k * 3 + 1] - oy) < 0.1f) {
						nb = j;
					}
				}
				s.col_nb.push_back(nb);
			}
			if (type == 6 && (int)s.col_germ.size() < COL_GERMS) {
				s.col_germ.push_back(k);
			}
			len = std::max(len, std::abs(s.body[k * 3]) + 0.5f);
			wid = std::max(wid, std::abs(s.body[k * 3 + 1]) + 0.5f);
		}
		s.half_len = len * COL_BLOCK + 3.0f;
		s.half_wid = wid * COL_BLOCK + 3.0f;
		s.extent = 0.5f * (s.half_len + s.half_wid);
		s.center_off = 0.0f;
	} else if (!s.body.empty()) {
		// A multicell body is drawn much larger than its radius (modules plus
		// the envelope); collide with what the player sees.
		float mr = s.radius * 0.34f;
		float minx = 1e9f, maxx = -1e9f, miny = 1e9f, maxy = -1e9f;
		for (size_t k = 0; k + 2 < s.body.size(); k += 3) {
			minx = std::min(minx, s.body[k]);
			maxx = std::max(maxx, s.body[k]);
			miny = std::min(miny, s.body[k + 1]);
			maxy = std::max(maxy, s.body[k + 1]);
		}
		float len = (maxx - minx) * 1.8f * mr + 4.6f * mr;
		float wid = (maxy - miny) * 1.8f * mr + 4.8f * mr;
		s.extent = 0.5f * (0.6f * len + 0.4f * wid);
		// +10%: the drawn membrane wobbles out by up to ~10% and the body wave
		// sways the modules; collide with the outline at its widest.
		s.half_len = 0.55f * len;
		s.half_wid = 0.55f * wid + 0.14f * mr;
		s.center_off = (minx + maxx) * 0.5f * 1.8f * mr;
	}
	max_extent = std::max(max_extent, s.extent);
	species.push_back(s);
	return (int)species.size() - 1;
}

void SimCore::set_dish(Vector2 center, float radius) {
	dish_x = center.x;
	dish_y = center.y;
	dish_r = radius;
	// Nothing grows outside the glass.
	for (int j = 0; j < gh; j++) {
		for (int i = 0; i < gw; i++) {
			if (!inside_dish((i + 0.5f) * cell, (j + 0.5f) * cell, 0.0f)) {
				light[j * gw + i] = 0.0f;
				light_base[j * gw + i] = 0.0f;
			}
		}
	}
	rebuild_env();
}

void SimCore::add_light(Vector2 pos, float radius, float power) {
	spots.push_back({ pos.x, pos.y, radius, power });
	flow_age = 1000;
	light_profile(pos.x, pos.y, radius, power);
}

void SimCore::light_pulse(Vector2 pos, float radius, float power, float seconds) {
	light_pulses.push_back({ pos.x, pos.y, radius, power, 0.0f, seconds });
	light_profile(pos.x, pos.y, radius, power);
}

void SimCore::light_profile(float px, float py, float radius, float power) {
	const Vector2 pos(px, py);
	for (int j = 0; j < gh; j++) {
		for (int i = 0; i < gw; i++) {
			float cx = (i + 0.5f) * cell - pos.x;
			float cy = (j + 0.5f) * cell - pos.y;
			if (!inside_dish((i + 0.5f) * cell, (j + 0.5f) * cell, 0.0f)) {
				continue;
			}
			float d2 = (cx * cx + cy * cy) / (radius * radius);
			light_base[j * gw + i] += power * std::exp(-d2 * 2.0f);
		}
	}
	rebuild_env();
}

// --- environment --------------------------------------------------------------

void SimCore::set_base_environment(Dictionary p) {
	base_temp = (float)(double)p.get("temp", base_temp);
	base_acid = (float)(double)p.get("acid", base_acid);
	base_rad = (float)(double)p.get("radiation", base_rad);
	rebuild_env();
}

int SimCore::add_zone(Dictionary p) {
	Vector2 c = p.get("center", Vector2());
	Zone z;
	z.x = c.x;
	z.y = c.y;
	z.r = (float)(double)p.get("radius", 300.0);
	z.temp = (float)(double)p.get("temp", base_temp);
	z.acid = (float)(double)p.get("acid", base_acid);
	z.rad = (float)(double)p.get("radiation", base_rad);
	z.light = (float)(double)p.get("light", 1.0);
	z.vent = (float)(double)p.get("vent", 0.0);
	z.chem = (float)(double)p.get("chem", 0.0);
	zones.push_back(z);
	rebuild_env();
	return (int)zones.size() - 1;
}

// Every cell starts from the base and is pulled toward each zone it lies in,
// fully inside half the radius, fading out to the rim. A zone's vent input is
// spread over its cells by the same weight.
void SimCore::rebuild_env() {
	if (gw == 0) {
		return;
	}
	const int n = gw * gh;
	std::vector<float> wsum(zones.size(), 0.0f);
	auto weight = [&](const Zone &z, int i, int j) {
		float dx = (i + 0.5f) * cell - z.x, dy = (j + 0.5f) * cell - z.y;
		float d = std::sqrt(dx * dx + dy * dy);
		float u = clampf((z.r - d) / (z.r * 0.5f), 0.0f, 1.0f);
		return u * u * (3.0f - 2.0f * u);
	};
	for (size_t k = 0; k < zones.size(); k++) {
		for (int j = 0; j < gh; j++) {
			for (int i = 0; i < gw; i++) {
				if (inside_dish((i + 0.5f) * cell, (j + 0.5f) * cell, 0.0f)) {
					wsum[k] += weight(zones[k], i, j);
				}
			}
		}
	}
	vent_total = 0.0;
	for (int j = 0; j < gh; j++) {
		for (int i = 0; i < gw; i++) {
			int c = j * gw + i;
			float t = base_temp, a = base_acid, r = base_rad, m = 1.0f, v = 0.0f, ch = 0.0f;
			bool in = inside_dish((i + 0.5f) * cell, (j + 0.5f) * cell, 0.0f);
			for (size_t k = 0; k < zones.size(); k++) {
				const Zone &z = zones[k];
				float w = weight(z, i, j);
				if (w <= 0.0f) {
					continue;
				}
				t = lerpf(t, z.temp, w);
				a = lerpf(a, z.acid, w);
				r = lerpf(r, z.rad, w);
				m = lerpf(m, z.light, w);
				ch = std::max(ch, z.chem * w);
				if (in && wsum[k] > 0.0f) {
					v += z.vent * w / wsum[k];
				}
			}
			for (const TempSpot &sp : temp_spots) {
				float dx = (i + 0.5f) * cell - sp.x, dy = (j + 0.5f) * cell - sp.y;
				float u = clampf((sp.r - std::sqrt(dx * dx + dy * dy)) / (sp.r * 0.5f), 0.0f, 1.0f);
				t += sp.delta * u * u * (3.0f - 2.0f * u) * spot_fade(sp.life, sp.ttl);
			}
			temp[c] = t;
			acid[c] = a;
			rad[c] = r;
			vent[c] = v;
			chem[c] = ch;
			vent_total += v;
			light[c] = in ? light_base[c] * m : 0.0f;
		}
	}
	(void)n;
}

Array SimCore::get_zones() const {
	Array out;
	for (const Zone &z : zones) {
		Dictionary d;
		d["center"] = Vector2(z.x, z.y);
		d["radius"] = z.r;
		d["temp"] = z.temp;
		d["acid"] = z.acid;
		d["radiation"] = z.rad;
		d["light"] = z.light;
		d["vent"] = z.vent;
		d["chem"] = z.chem;
		out.push_back(d);
	}
	return out;
}

PackedFloat32Array SimCore::get_env_field() const {
	PackedFloat32Array out;
	out.resize(gw * gh * 4);
	float *w = out.ptrw();
	for (int c = 0; c < gw * gh; c++) {
		w[c * 4] = temp[c];
		w[c * 4 + 1] = acid[c];
		w[c * 4 + 2] = sig_a[c];
		w[c * 4 + 3] = sig_b[c];
	}
	return out;
}

Dictionary SimCore::get_env_at(Vector2 pos) const {
	Dictionary d;
	int c = nutrient_index(pos.x, pos.y);
	d["temp"] = temp[c];
	d["acid"] = acid[c];
	d["radiation"] = rad[c];
	d["light"] = light[c];
	d["chem"] = chem[c];
	d["signal_a"] = sig_a[c];
	d["signal_b"] = sig_b[c];
	return d;
}

float SimCore::temp_at(float wx, float wy) const {
	return temp[nutrient_index(wx, wy)];
}

float SimCore::temp_dev(int i) const {
	return std::max(0.0f, std::abs(temp_at(x[i], y[i]) - t_topt[i]) - band_for(t_ttol[i]));
}

// "Seek comfort": the direction, within sight, toward water nearer the
// organism's optimum (16 samples: 8 headings at half and full vision range).
// False when nothing in view is at least 0.5 °C better, e.g. when the whole
// dish has cooled evenly: then the card is skipped instead of swimming blind.
bool SimCore::comfort_dir(int i, float &dx, float &dy) const {
	const float here = std::abs(temp_at(x[i], y[i]) - t_topt[i]);
	const float reach = 30.0f + 24.0f * t_vision[i];
	float best = here - 0.5f;
	bool found = false;
	for (int k = 0; k < 8; k++) {
		const float a = k * 0.785398f;
		const float cx = std::cos(a), cy = std::sin(a);
		for (float d : { reach * 0.5f, reach }) {
			const float dev = std::abs(temp_at(x[i] + cx * d, y[i] + cy * d) - t_topt[i]);
			if (dev < best) {
				best = dev;
				dx = cx;
				dy = cy;
				found = true;
			}
		}
	}
	return found;
}

// The direction in which signal `which` (0 A, 1 B) smells strongest within
// SMELL_RANGE, if anywhere smells stronger than here (at the source, or with
// nothing to smell, none: the card yields to the next).
bool SimCore::signal_dir(int i, int which, float &dx, float &dy) const {
	const std::vector<float> &f = which ? sig_b : sig_a;
	float best = std::max(f[nutrient_index(x[i], y[i])] * 1.08f, SMELL_MIN);
	bool found = false;
	for (int k = 0; k < 8; k++) {
		const float a = k * 0.785398f;
		const float cx = std::cos(a), cy = std::sin(a);
		for (float d : { SMELL_RANGE * 0.2f, SMELL_RANGE * 0.45f, SMELL_RANGE * 0.7f, SMELL_RANGE }) {
			const float sx = x[i] + cx * d, sy = y[i] + cy * d;
			if (!inside_dish(sx, sy, 0.0f)) {
				continue;
			}
			// A far trail counts for a little less: the nearest strong patch wins.
			const float v = f[nutrient_index(sx, sy)] * (1.0f - 0.25f * d / SMELL_RANGE);
			if (v > best) {
				best = v;
				dx = cx;
				dy = cy;
				found = true;
			}
		}
	}
	return found;
}

void SimCore::seed_algae(int n, float energy_each, float dark) {
	// Clumps settle where the light is: rejection-sample by light level.
	float lmax = 0.01f;
	for (float l : light) {
		lmax = std::max(lmax, l);
	}
	int tries = 0;
	while (n > 0 && tries < n * 60) {
		tries++;
		float wx = rand_range(0.0f, world_w), wy = rand_range(0.0f, world_h);
		if (!inside_dish(wx, wy, 20.0f)) {
			continue;
		}
		// `dark`: how often a clump still settles where there is no light.
		if (randf() * lmax > light[nutrient_index(wx, wy)] + dark) {
			continue;
		}
		float e = energy_each * rand_range(0.5f, 1.0f);
		if (add_algae(wx, wy, e) >= 0) {
			energy_in += e;
			n--;
		}
	}
}

void SimCore::add_algae_patch(Vector2 pos, float radius, int n, float each) {
	for (int k = 0; k < n; k++) {
		float a = rand_range(0.0f, TAU), r = radius * std::sqrt(randf());
		float wx = pos.x + std::cos(a) * r, wy = pos.y + std::sin(a) * r;
		if (!inside_dish(wx, wy, 20.0f)) {
			continue;
		}
		float e = std::min(ALGAE_MAX_E, each * rand_range(0.7f, 1.0f));
		if (add_algae(wx, wy, e) >= 0) {
			energy_in += e;
		}
	}
}

void SimCore::add_nutrient(Vector2 pos, float radius, float amount) {
	// Intervention: most of it dissolves into the water around `pos`; a share
	// arrives as algae spores, so the player sees the bloom start.
	float spores = amount * 0.3f;
	int nspores = std::max(1, (int)(spores / 4.0f));
	for (int k = 0; k < nspores; k++) {
		float a = rand_range(0.0f, TAU), r = radius * 0.7f * std::sqrt(randf());
		float e = spores / nspores;
		if (add_algae(pos.x + std::cos(a) * r, pos.y + std::sin(a) * r, e) >= 0) {
			energy_in += e;
		} else {
			amount += e / 0.7f; // no room: dissolve it instead
		}
	}
	float dissolve = amount * 0.7f;
	std::vector<int> cells;
	std::vector<float> w;
	float total = 0.0f;
	int rc = (int)std::ceil(radius / cell);
	int ci = (int)(pos.x / cell), cj = (int)(pos.y / cell);
	for (int j = cj - rc; j <= cj + rc; j++) {
		for (int i = ci - rc; i <= ci + rc; i++) {
			if (i < 0 || j < 0 || i >= gw || j >= gh) {
				continue;
			}
			float dx = (i + 0.5f) * cell - pos.x, dy = (j + 0.5f) * cell - pos.y;
			float d = std::sqrt(dx * dx + dy * dy) / radius;
			if (d < 1.0f) {
				cells.push_back(j * gw + i);
				w.push_back(1.0f - d);
				total += 1.0f - d;
			}
		}
	}
	if (total <= 0.0f) {
		return;
	}
	for (size_t k = 0; k < cells.size(); k++) {
		float add = dissolve * w[k] / total;
		nutrient[cells[k]] += add;
		energy_in += add;
	}
}

bool SimCore::inside_dish(float wx, float wy, float margin) const {
	if (wx < 0 || wy < 0 || wx >= world_w || wy >= world_h) {
		return false;
	}
	if (dish_r <= 0.0f) {
		return true;
	}
	float dx = wx - dish_x, dy = wy - dish_y;
	float lim = dish_r - margin;
	return dx * dx + dy * dy <= lim * lim;
}

void SimCore::keep_in_dish(float &wx, float &wy, float r) const {
	wx = clampf(wx, r, world_w - r);
	wy = clampf(wy, r, world_h - r);
	if (dish_r > 0.0f) {
		float dx = wx - dish_x, dy = wy - dish_y;
		float d = std::sqrt(dx * dx + dy * dy);
		float lim = dish_r - r;
		if (d > lim && d > 1e-3f) {
			wx = dish_x + dx / d * lim;
			wy = dish_y + dy / d * lim;
		}
	}
}

void SimCore::current(float wx, float wy, float &u, float &v) const {
	// Large-scale drift: two stream functions psi = A/k sin(kx + wt) sin(k'y - w't).
	const float t = (float)sim_time;
	const float k1 = 0.0035f, k2 = 0.009f;
	float a1 = k1 * wx + 0.05f * t, b1 = 0.8f * k1 * wy - 0.04f * t;
	float a2 = k2 * wy - 0.07f * t, b2 = 0.9f * k2 * wx + 0.06f * t;
	u = 7.0f * 0.8f * std::sin(a1) * std::cos(b1) + 3.0f * std::cos(a2) * std::sin(b2);
	v = -7.0f * std::cos(a1) * std::sin(b1) - 3.0f * 0.9f * std::sin(a2) * std::cos(b2);
	// Local circulation: warm, lit water turns slowly around each light spot
	// (alternating direction), a pure rotation, so still divergence-free.
	for (size_t k = 0; k < spots.size(); k++) {
		const LightSpot &s = spots[k];
		float dx = wx - s.x, dy = wy - s.y;
		float q = (dx * dx + dy * dy) / (s.r * s.r);
		if (q > 6.0f) {
			continue;
		}
		float swirl = (k % 2 ? -1.0f : 1.0f) * 22.0f * s.power * std::exp(-q) / s.r;
		u += -dy * swirl;
		v += dx * swirl;
	}
	u *= flow_scale;
	v *= flow_scale;
}

int SimCore::nutrient_index(float wx, float wy) const {
	int i = (int)clampf(wx / cell, 0.0f, (float)(gw - 1));
	int j = (int)clampf(wy / cell, 0.0f, (float)(gh - 1));
	return j * gw + i;
}

void SimCore::step_nutrients(float dt) {
	// Refresh the cached water velocity a few times a second.
	if (++flow_age >= 15) {
		flow_age = 0;
		for (int j = 0; j < gh; j++) {
			for (int i = 0; i < gw; i++) {
				int c = j * gw + i;
				if (!inside_dish((i + 0.5f) * cell, (j + 0.5f) * cell, -cell)) {
					flow_u[c] = flow_v[c] = 0.0f;
					continue;
				}
				current((i + 0.5f) * cell, (j + 0.5f) * cell, flow_u[c], flow_v[c]);
			}
		}
	}
	transport(nutrient, 0.08f, dt);
	// Vents feed nutrient in (energy enters the world here).
	if (vent_total > 0.0) {
		for (int c = 0; c < gw * gh; c++) {
			nutrient[c] += vent[c] * dt;
		}
		energy_in += vent_total * dt;
	}
}

// Signals: every other tick, carried and spread like nutrient, and fading.
void SimCore::step_signals(float dt) {
	if (++signal_phase % 2) {
		return;
	}
	float d2 = dt * 2.0f;
	transport(sig_a, SIGNAL_DIFFUSE, d2);
	transport(sig_b, SIGNAL_DIFFUSE, d2);
	float keep = std::exp(-SIGNAL_DECAY * d2);
	for (int c = 0; c < gw * gh; c++) {
		sig_a[c] *= keep;
		sig_b[c] *= keep;
	}
	if (algae_tough > 0.0f) {
		transport(enzyme, ENZ_DIFFUSE, d2);
		float keep_e = std::exp(-ENZ_DECAY * d2);
		for (int c = 0; c < gw * gh; c++) {
			enzyme[c] *= keep_e;
		}
	}
}

// Advection with the water (donor-cell fluxes) and diffusion (pairwise
// exchange): both conserve the field's total.
void SimCore::transport(std::vector<float> &field, float kd_rate, float dt) {
	std::fill(flux_tmp.begin(), flux_tmp.end(), 0.0f);
	const float k = dt / cell;
	for (int j = 0; j < gh; j++) {
		for (int i = 0; i + 1 < gw; i++) {
			int a = j * gw + i;
			float uf = 0.5f * (flow_u[a] + flow_u[a + 1]) * k;
			float f = uf > 0.0f ? field[a] * uf : field[a + 1] * uf;
			flux_tmp[a] -= f;
			flux_tmp[a + 1] += f;
		}
	}
	for (int j = 0; j + 1 < gh; j++) {
		for (int i = 0; i < gw; i++) {
			int a = j * gw + i;
			float vf = 0.5f * (flow_v[a] + flow_v[a + gw]) * k;
			float f = vf > 0.0f ? field[a] * vf : field[a + gw] * vf;
			flux_tmp[a] -= f;
			flux_tmp[a + gw] += f;
		}
	}
	for (int c = 0; c < gw * gh; c++) {
		field[c] += flux_tmp[c];
	}
	// Diffusion along x then y.
	const float kd = kd_rate * dt;
	for (int j = 0; j < gh; j++) {
		for (int i = 0; i + 1 < gw; i++) {
			int a = j * gw + i;
			float f = (field[a] - field[a + 1]) * kd;
			field[a] -= f;
			field[a + 1] += f;
		}
	}
	for (int j = 0; j + 1 < gh; j++) {
		for (int i = 0; i < gw; i++) {
			int a = j * gw + i;
			float f = (field[a] - field[a + gw]) * kd;
			field[a] -= f;
			field[a + gw] += f;
		}
	}
}

// --- algae and shells -------------------------------------------------------

float SimCore::algae_radius(float e) const {
	return 2.5f + 5.5f * std::sqrt(clampf(e / ALGAE_MAX_E, 0.0f, 1.0f));
}

int SimCore::add_algae(float wx, float wy, float e) {
	if (algae >= algae_cap || !inside_dish(wx, wy, 8.0f)) {
		return -1;
	}
	int a = algae++;
	al_x[a] = al_px[a] = wx;
	al_y[a] = al_py[a] = wy;
	al_e[a] = e;
	al_ph[a] = rand_range(0.0f, 100.0f);
	al_bud[a] = rand_range(4.0f, 10.0f);
	return a;
}

void SimCore::step_algae(float dt) {
	int n = algae;
	for (int a = 0; a < n; a++) {
		al_px[a] = al_x[a];
		al_py[a] = al_y[a];
		int c = nutrient_index(al_x[a], al_y[a]);
		float room = std::max(0.0f, 1.0f - al_e[a] / ALGAE_MAX_E);
		// Photosynthesis (energy enters the world here) and nutrient uptake.
		float gain = light[c] * ALGAE_LIGHT * room * dt * algae_growth;
		float take = std::min(nutrient[c], ALGAE_UPTAKE * room * dt); // recycling is not new growth
		nutrient[c] -= take;
		float loss = al_e[a] * ALGAE_UPKEEP * dt * algae_upkeep;
		al_e[a] += gain + take - loss;
		energy_in += gain;
		energy_out += loss;
		// Drift with the water.
		float u = flow_u[c], v = flow_v[c];
		al_x[a] += u * dt;
		al_y[a] += v * dt;
		keep_in_dish(al_x[a], al_y[a], 8.0f);
		// A full clump buds off a new one nearby.
		al_bud[a] -= dt;
		if (al_e[a] > ALGAE_MAX_E * 0.7f && al_bud[a] <= 0.0f && algae < algae_cap) {
			float ang = rand_range(0.0f, TAU), d = rand_range(12.0f, 26.0f);
			float e = al_e[a] * 0.4f;
			if (add_algae(al_x[a] + std::cos(ang) * d, al_y[a] + std::sin(ang) * d, e) >= 0) {
				al_e[a] -= e;
			}
			al_bud[a] = rand_range(6.0f, 12.0f);
		}
	}
	// Vents seed their own: now and then a chemosynthetic cell drifts out of
	// the rich water (as algae spores do where light falls), so a vent's
	// producers can recover after being grazed bare.
	for (size_t s = 0; s < species.size(); s++) {
		if (species[s].diet != DIET_CHEMO || !species[s].reseed || randf() >= CHEMO_SEED * dt) {
			continue;
		}
		for (int tries = 0; tries < 12; tries++) {
			float wx = rand_range(0.0f, world_w), wy = rand_range(0.0f, world_h);
			if (inside_dish(wx, wy, 20.0f) && chem[nutrient_index(wx, wy)] > 0.6f) {
				spawn_one((int)s, wx, wy, -1);
				break;
			}
		}
	}
	// Spores drift in: now and then a new clump starts where light falls, so
	// algae can always recover even after a patch has been eaten bare.
	if (randf() < 4.0f * dt * algae_growth && algae < algae_cap) {
		float wx = rand_range(0.0f, world_w), wy = rand_range(0.0f, world_h);
		if (inside_dish(wx, wy, 20.0f) && light[nutrient_index(wx, wy)] > 0.08f && add_algae(wx, wy, 1.0f) >= 0) {
			energy_in += 1.0f;
		}
	}
	// Grazed-out clumps dissolve.
	int w = 0;
	for (int a = 0; a < algae; a++) {
		if (al_e[a] < 0.25f) {
			nutrient[nutrient_index(al_x[a], al_y[a])] += std::max(0.0f, al_e[a]);
			continue;
		}
		if (w != a) {
			al_x[w] = al_x[a];
			al_y[w] = al_y[a];
			al_px[w] = al_px[a];
			al_py[w] = al_py[a];
			al_e[w] = al_e[a];
			al_ph[w] = al_ph[a];
			al_bud[w] = al_bud[a];
		}
		w++;
	}
	algae = w;
}

void SimCore::add_shell(int i) {
	// Whatever the organism still held (its body and any energy left) stays
	// in the shell and decomposes slowly.
	float e = std::max(0.0f, energy[i]) + body_energy(sp[i]);
	if (shells >= MAX_SHELLS) {
		nutrient[nutrient_index(x[i], y[i])] += e;
		return;
	}
	int s = shells++;
	sh_x[s] = x[i];
	sh_y[s] = y[i];
	sh_e[s] = sh_e0[s] = e;
	sh_h[s] = heading[i];
	sh_r[s] = species[sp[i]].radius;
	sh_ph[s] = phase[i];
	sh_sp[s] = sp[i];
	sh_lineage[s] = lineage[i];
}

void SimCore::step_shells(float dt) {
	int w = 0;
	for (int s = 0; s < shells; s++) {
		int c = nutrient_index(sh_x[s], sh_y[s]);
		float release = std::min(sh_e[s], (SHELL_DECAY + SHELL_DECAY_FRAC * sh_e[s]) * dt);
		sh_e[s] -= release;
		nutrient[c] += release * 0.9f;
		energy_out += release * 0.1f;
		sh_x[s] += flow_u[c] * dt * 0.6f;
		sh_y[s] += flow_v[c] * dt * 0.6f;
		keep_in_dish(sh_x[s], sh_y[s], sh_r[s]);
		if (sh_e[s] <= 0.05f) {
			nutrient[c] += sh_e[s];
			continue;
		}
		if (w != s) {
			sh_x[w] = sh_x[s];
			sh_y[w] = sh_y[s];
			sh_e[w] = sh_e[s];
			sh_e0[w] = sh_e0[s];
			sh_h[w] = sh_h[s];
			sh_r[w] = sh_r[s];
			sh_ph[w] = sh_ph[s];
			sh_sp[w] = sh_sp[s];
			sh_lineage[w] = sh_lineage[s];
		}
		w++;
	}
	shells = w;
}

// --- organisms --------------------------------------------------------------

float SimCore::body_energy(int s) const {
	float r = species[s].radius;
	return 0.6f * r * r;
}

// Default instincts: exactly the behaviour every species had before decks
// existed, so the native ecology is unchanged (tests/eco_check.gd).
std::vector<SimCore::Card> SimCore::default_deck(int diet) const {
	auto make = [](uint8_t c0, float t0, uint8_t c1, float t1, uint8_t a) {
		Card c;
		c.c[0] = c0;
		c.t[0] = t0;
		c.c[1] = c1;
		c.t[1] = t1;
		c.act = a;
		return c;
	};
	std::vector<Card> d;
	d.push_back(make(C_PREDATOR_NEAR, 60.0f, C_NONE, 0.0f, A_FLEE));
	if (diet == DIET_PREDATOR) {
		d.push_back(make(C_ENERGY_BELOW, 1.0f, C_SEE_PREY, 0.0f, A_HUNT));
		d.push_back(make(C_ENERGY_ABOVE, 1.0f, C_NONE, 0.0f, A_DIVIDE));
		d.push_back(make(C_ENERGY_BELOW, 1.0f, C_SEE_SHELL, 0.0f, A_SCAVENGE));
		// Lurk: hungry with nothing in sight, wait instead of burning
		// the last reserves cruising (the hunt card above still fires the
		// moment prey drifts into view). Keeps hunters through prey crashes.
		d.push_back(make(C_ENERGY_BELOW, 0.6f, C_NONE, 0.0f, A_REST));
	} else {
		d.push_back(make(C_ENERGY_ABOVE, 1.0f, C_NONE, 0.0f, A_DIVIDE));
		d.push_back(make(C_ENERGY_BELOW, 1.0f, C_SEE_ALGAE, 0.0f, A_SEEK_ALGAE));
		d.push_back(make(C_ENERGY_ABOVE, 1.0f, C_NONE, 0.0f, A_REST));
	}
	return d;
}

SimCore::Card SimCore::card_from(const Dictionary &d) {
	Card c;
	c.c[0] = (uint8_t)clampf((float)(int)d.get("c1", 0), 0.0f, (float)(C_COUNT - 1));
	c.c[1] = (uint8_t)clampf((float)(int)d.get("c2", 0), 0.0f, (float)(C_COUNT - 1));
	c.t[0] = (float)(double)d.get("t1", 0.0);
	c.t[1] = (float)(double)d.get("t2", 0.0);
	c.act = (uint8_t)clampf((float)(int)d.get("act", (int)A_WANDER), 0.0f, (float)(A_COUNT - 1));
	c.neg = (uint8_t)(((bool)d.get("n1", false) ? 1 : 0) | ((bool)d.get("n2", false) ? 2 : 0));
	c.any = (bool)d.get("any", false);
	c.st = (uint8_t)clampf((float)(int)d.get("st", 0), 0.0f, (float)(S_COUNT - 1));
	return c;
}

Dictionary SimCore::card_to(const Card &c) {
	Dictionary d;
	d["c1"] = (int)c.c[0];
	d["t1"] = c.t[0];
	d["c2"] = (int)c.c[1];
	d["t2"] = c.t[1];
	d["act"] = (int)c.act;
	d["n1"] = (c.neg & 1) != 0;
	d["n2"] = (c.neg & 2) != 0;
	d["any"] = c.any;
	d["st"] = (int)c.st;
	return d;
}

int SimCore::slots_for(float neural) {
	static const int table[5] = { 3, 4, 5, 6, 8 };
	return table[(int)clampf(std::round(neural), 1.0f, 5.0f) - 1];
}

namespace {
// Threshold range of each condition (min, max, drift step); 0,0 = none.
void cond_range(uint8_t c, float &lo, float &hi, float &step, float &def) {
	switch (c) {
		case SimCore::C_ENERGY_BELOW: lo = 0.05f; hi = 1.5f; step = 0.12f; def = 0.6f; return;
		case SimCore::C_ENERGY_ABOVE: lo = 0.05f; hi = 1.5f; step = 0.12f; def = 1.0f; return;
		case SimCore::C_PREDATOR_NEAR: lo = 15.0f; hi = 200.0f; step = 15.0f; def = 60.0f; return;
		case SimCore::C_CROWD: lo = 1.0f; hi = 12.0f; step = 1.0f; def = 3.0f; return;
		case SimCore::C_AGE_ABOVE: lo = 0.05f; hi = 1.0f; step = 0.1f; def = 0.7f; return;
		case SimCore::C_SIGNAL_A:
		case SimCore::C_SIGNAL_B: lo = 0.05f; hi = 3.0f; step = 0.15f; def = 0.3f; return;
		case SimCore::C_PREY_NEAR: lo = 15.0f; hi = 200.0f; step = 15.0f; def = 80.0f; return;
		case SimCore::C_PREY_SMALL: lo = 0.3f; hi = 0.9f; step = 0.08f; def = 0.6f; return;
		case SimCore::C_STATE_TIME: lo = 1.0f; hi = 90.0f; step = 3.0f; def = 20.0f; return;
		case SimCore::C_PEER_STATE: lo = 0.0f; hi = 3.0f; step = 1.0f; def = 1.0f; return;
		default: lo = hi = step = def = 0.0f; return;
	}
}
} // namespace

// One heritable change to organism i's deck. Only primitives that exist in
// the simulation can appear (GDD 3.2: nothing is learnt from thin air).
bool SimCore::mutate_deck(int i) {
	Card *d = &cards[i * MAX_CARDS];
	int n = ncards[i];
	int slots = slots_for(t_neural[i]);
	if (n == 0) {
		return false;
	}
	int k = (int)(randf() * n) % n;
	float r = randf();
	const int keep = species[sp[i]].keep_act;
	if (keep >= 0) {
		// Not this card, nor anything climbing past it.
		int k2 = k + 1 < n ? k + 1 : k - 1;
		if (d[k].act == keep || (k2 >= 0 && d[k2].act == keep)) {
			return false;
		}
	}
	if (r < 0.5f) {
		// Threshold drift (the most common change).
		int j = d[k].c[1] != C_NONE && randf() < 0.5f ? 1 : 0;
		float lo, hi, step, def;
		cond_range(d[k].c[j], lo, hi, step, def);
		if (step > 0.0f) {
			float v = d[k].t[j] + gauss() * step;
			if (d[k].c[j] == C_CROWD) {
				v = std::round(v);
			}
			d[k].t[j] = clampf(v, lo, hi);
			return true;
		}
	}
	if (r < 0.56f && species[sp[i]].logic && d[k].c[0] != C_NONE) {
		// Flip a 不, or switch 且 / 或.
		if (randf() < 0.5f && d[k].c[1] != C_NONE) {
			d[k].any = !d[k].any;
		} else {
			d[k].neg ^= (uint8_t)(1 << (d[k].c[1] != C_NONE && randf() < 0.5f ? 1 : 0));
		}
		return true;
	}
	if (r < 0.65f && n >= 2) {
		int k2 = k + 1 < n ? k + 1 : k - 1;
		std::swap(d[k], d[k2]);
	} else if (r < 0.75f && n < slots) {
		for (int m = n; m > k + 1; m--) {
			d[m] = d[m - 1];
		}
		d[k + 1] = d[k];
		ncards[i] = (uint8_t)(n + 1);
	} else if (r < 0.85f && n > 1) {
		for (int m = k; m < n - 1; m++) {
			d[m] = d[m + 1];
		}
		ncards[i] = (uint8_t)(n - 1);
	} else if (randf() < 0.5f) {
		// Only pieces this species may use (the level's unlocked ones).
		const Species &S = species[sp[i]];
		uint8_t a = (uint8_t)((int)(randf() * A_COUNT) % A_COUNT);
		if (!(S.act_mask & (1u << a))) {
			return false;
		}
		d[k].act = a;
	} else {
		int j = d[k].c[0] == C_NONE || randf() < 0.5f ? 0 : 1;
		uint8_t c = (uint8_t)(1 + (int)(randf() * (C_COUNT - 1)) % (C_COUNT - 1));
		if (!(species[sp[i]].cond_mask & (1u << c))) {
			return false;
		}
		float lo, hi, step, def;
		cond_range(c, lo, hi, step, def);
		d[k].c[j] = c;
		d[k].t[j] = def;
	}
	return true;
}

int SimCore::spawn_one(int s, float wx, float wy, int parent) {
	if (count >= MAX_AGENTS || s < 0 || s >= (int)species.size()) {
		return -1;
	}
	const Species &S = species[s];
	int i = count++;
	id[i] = next_id++;
	sp[i] = s;
	keep_in_dish(wx, wy, S.radius);
	x[i] = px[i] = wx;
	y[i] = py[i] = wy;
	vx[i] = vy[i] = 0.0f;
	heading[i] = pheading[i] = rand_range(0.0f, TAU);
	age[i] = 0.0f;
	digest[i] = 0.0f;
	phase[i] = rand_range(0.0f, 100.0f);
	wander[i] = heading[i];
	alive[i] = 1;
	bitten[i] = 0;
	crowd[i] = 0;
	inf_t[i] = -1.0f;
	inf_ang[i] = 0.0f;
	inf_fate[i] = 0;
	immune[i] = parent >= 0 ? immune[parent] : 0;
	carry[i] = parent >= 0 ? carry[parent] : 0;
	hijack[i] = -1.0f;
	slug[i] = -1;
	sl_ox[i] = sl_oy[i] = 0.0f;
	spore[i] = 0.0f;
	action[i] = ACT_WANDER;
	target[i] = 0;
	hurt[i] = 0.0f;
	stress_t[i] = 0.0f;
	stress_a[i] = 0.0f;
	join[i] = 0.0f;
	pair[i] = -1;
	join_mut[i] = 0;
	sw[i] = rand_range(0.0f, TAU);
	psw[i] = sw[i];
	curl[i] = 0.0f;
	vs[i] = 0.0f;
	angv[i] = 0.0f;
	latch[i] = 0.0f;
	gulp_t[i] = -1.0f;
	gest[i] = -1.0f;
	gwait[i] = 0.0f;
	store[i] = 0.0f;
	cslow[i] = 0.0f;
	cspurn[i] = 0.0f;
	cpiece[i] = 0;
	rot_meal[i] = -1;
	rot_t[i] = 0.0f;
	cheld[i] = 0;
	for (int k = 0; k < COL_MAXB; k++) {
		cmark[i * COL_MAXB + k] = 0.0f;
		cdmg[i * COL_MAXB + k] = 0.0f;
		cbroken[i * COL_MAXB + k] = 0;
	}
	sense[i] = 0;
	fired[i] = -1;
	state[i] = S_FORAGE; // newborns start foraging (DECISIONS 第十二轮 Q23)
	st_time[i] = 0.0f;
	threat_d[i] = 1e9f;
	tgx[i] = wx;
	tgy[i] = wy;
	if (parent >= 0) {
		t_neural[i] = t_neural[parent];
		ncards[i] = ncards[parent];
		for (int k = 0; k < MAX_CARDS; k++) {
			cards[i * MAX_CARDS + k] = cards[parent * MAX_CARDS + k];
		}
		t_speed[i] = t_speed[parent];
		t_vision[i] = t_vision[parent];
		t_armor[i] = t_armor[parent];
		t_attack[i] = t_attack[parent];
		t_fertility[i] = t_fertility[parent];
		t_efficiency[i] = t_efficiency[parent];
		t_topt[i] = t_topt[parent];
		t_ttol[i] = t_ttol[parent];
		lineage[i] = lineage[parent];
		gen[i] = gen[parent] + 1;
		cooldown[i] = rand_range(4.0f, 7.0f);
		energy[i] = 0.0f; // the caller hands over the parent's energy
		// Radiation where the child is born raises the mutation rate (up to 4x).
		float rmul = 1.0f + 3.0f * rad[nutrient_index(wx, wy)];
		// Natural mutation switched off (a control experiment): no drift at all.
		if (!species[sp[i]].mutates) {
			rmul = 0.0f;
		}
		if (randf() < std::min(0.9f, 0.18f * rmul)) {
			float *traits[8] = { &t_speed[i], &t_vision[i], &t_armor[i], &t_attack[i], &t_fertility[i], &t_efficiency[i], &t_neural[i], &t_ttol[i] };
			int which = (int)(randf() * 9.0f) % 9;
			if (which == 8) {
				// The preferred temperature drifts by a few degrees.
				t_topt[i] = clampf(t_topt[i] + gauss() * 3.0f, -5.0f, 60.0f);
			} else {
				float &t = *traits[which];
				t = clampf(t + gauss() * 0.35f, 1.0f, 5.0f);
			}
			// A smaller brain forgets the cards it no longer has room for.
			ncards[i] = (uint8_t)std::min((int)ncards[i], slots_for(t_neural[i]));
			lineage[i] = next_lineage++;
			mutated_now = true;
		}
		if (randf() < std::min(0.9f, 0.12f * rmul) && mutate_deck(i)) {
			if (!mutated_now) {
				lineage[i] = next_lineage++;
			}
			mutated_now = true;
		}
	} else {
		t_speed[i] = S.speed;
		t_vision[i] = S.vision;
		t_armor[i] = S.armor;
		t_attack[i] = S.attack;
		t_fertility[i] = S.fertility;
		t_efficiency[i] = S.efficiency;
		t_neural[i] = S.neural;
		t_topt[i] = S.temp_opt;
		t_ttol[i] = S.temp_tol;
		int nd = std::min((int)S.deck.size(), slots_for(S.neural));
		ncards[i] = (uint8_t)nd;
		for (int k = 0; k < nd; k++) {
			cards[i * MAX_CARDS + k] = S.deck[k];
		}
		lineage[i] = next_lineage++;
		gen[i] = 1;
		cooldown[i] = rand_range(1.0f, 6.0f);
		// Founders arrive at mixed ages, so a cohort does not die all at once.
		age[i] = rand_range(0.0f, S.colony ? 8.0f : S.lifespan * 0.5f);
		// A fresh organism brings its starting energy and body into the world.
		float e0 = S.colony ? S.col_e * 0.4f : S.radius * S.radius * 1.4f;
		energy[i] = e0;
		// (Founders come with their stores a third full.)
		store[i] = S.colony ? 0.3f * S.col_store * col_store_e : 0.0f;
		energy_in += e0 + body_energy(s);
	}
	set_shape(i);
	species[s].alive++;
	return i;
}

// A single cell's drawn outline as an ellipse (the same gene and lineage
// proportions organism.gdshader uses), slightly padded for the membrane wobble.
void SimCore::set_shape(int i) {
	const Species &S = species[sp[i]];
	if (!S.body.empty()) {
		ha[i] = hb[i] = S.extent;
		return;
	}
	auto q = [](float t) { return std::round(clampf((t - 1.0f) / 4.0f, 0.0f, 1.0f) * 15.0f) / 15.0f; };
	float gs = q(t_speed[i]), gf = q(t_fertility[i]);
	uint32_t sig = ((uint32_t)lineage[i] * 2654435761u) >> 27;
	float s1 = std::fmod(sig * 0.6180339f, 1.0f), s2 = std::fmod(sig * 0.3819660f + 0.27f, 1.0f);
	float ax = (1.0f + 0.35f * gs - 0.1f * gf) * (0.95f + 0.1f * s1);
	float ay = (1.0f - 0.18f * gs + 0.14f * gf) * (0.96f + 0.08f * s2);
	ha[i] = 0.9f * S.radius * ax * 1.04f;
	hb[i] = 0.9f * S.radius * ay * 1.04f;
}

float SimCore::cell_radius(int i, float dx, float dy) const {
	if (!species[sp[i]].body.empty()) {
		return body_radius(i, dx, dy);
	}
	float c = std::cos(heading[i]), s = std::sin(heading[i]);
	float lx = dx * c + dy * s, ly = -dx * s + dy * c;
	float l = std::sqrt(lx * lx + ly * ly) + 1e-5f;
	float ct = lx / l, st = ly / l;
	float a = ha[i], b = hb[i];
	return a * b / std::sqrt(b * b * ct * ct + a * a * st * st);
}

// After everyone has moved: push touching single cells fully apart and
// cancel the part of their velocity that drives them into each other, so
// bodies slide past instead of sinking in. Candidate pairs are gathered once
// from a fresh grid, then relaxed up to eight times (crowds need several
// passes to settle), stopping once nothing overlaps by a quarter pixel.
void SimCore::relax_contacts(int) {
	const int n = count;
	std::fill(ahead.begin(), ahead.end(), -1);
	if ((int)hcos.size() < n) {
		hcos.resize(alive.size());
		hsin.resize(alive.size());
	}
	for (int i = 0; i < n; i++) {
		int c = (int)clampf(y[i] / acell, 0.0f, (float)(agh - 1)) * agw + (int)clampf(x[i] / acell, 0.0f, (float)(agw - 1));
		anext[i] = ahead[c];
		ahead[c] = i;
		hcos[i] = std::cos(heading[i]);
		hsin[i] = std::sin(heading[i]);
	}
	// Ellipse radius of body k toward (dx, dy), with its cached heading.
	auto rad = [&](int k, float dx, float dy) {
		float lx = dx * hcos[k] + dy * hsin[k], ly = -dx * hsin[k] + dy * hcos[k];
		float l2 = lx * lx + ly * ly + 1e-10f;
		float a = ha[k], b = hb[k];
		return a * b * std::sqrt(l2 / (b * b * lx * lx + a * a * ly * ly + 1e-10f));
	};
	auto solid = [&](int i) { return alive[i] && join[i] <= 0.0f && species[sp[i]].body.empty(); };
	contact_pairs.clear();
	contact_r.clear();
	for (int i = 0; i < n; i++) {
		if (!solid(i)) {
			continue;
		}
		int ci = (int)clampf(x[i] / acell, 0.0f, (float)(agw - 1));
		int cj = (int)clampf(y[i] / acell, 0.0f, (float)(agh - 1));
		for (int gy = std::max(cj - 1, 0); gy <= std::min(cj + 1, agh - 1); gy++) {
			for (int gx = std::max(ci - 1, 0); gx <= std::min(ci + 1, agw - 1); gx++) {
				for (int j = ahead[gy * agw + gx]; j >= 0; j = anext[j]) {
					if (j <= i || !solid(j)) {
						continue;
					}
					float dx = x[j] - x[i], dy = y[j] - y[i];
					float reach = ha[i] + ha[j] + 2.0f;
					if (dx * dx + dy * dy < reach * reach) {
						// Directions barely turn while the pair settles, so the
						// ellipse radii are worked out once per tick.
						contact_pairs.push_back(i);
						contact_pairs.push_back(j);
						contact_r.push_back(rad(i, dx, dy) + rad(j, -dx, -dy));
					}
				}
			}
		}
	}
	const int np = (int)contact_pairs.size() / 2;
	// Over-relaxed (each push a little past contact) so crowds settle in
	// fewer passes; stops once nothing overlaps by a quarter pixel.
	const float omega = 1.35f;
	for (int iter = 0; iter < 8; iter++) {
		float worst = 0.0f;
		for (int k = 0; k < np; k++) {
			int i = contact_pairs[2 * k], j = contact_pairs[2 * k + 1];
			float dx = x[j] - x[i], dy = y[j] - y[i];
			float d2 = dx * dx + dy * dy;
			float rsum = contact_r[k];
			if (d2 < 1e-6f || d2 >= rsum * rsum) {
				continue;
			}
			float d = std::sqrt(d2);
			float ov = rsum - d;
			if (ov <= 0.0f) {
				continue;
			}
			worst = std::max(worst, ov);
			float nx = dx / d, ny = dy / d;
			float mi = ha[i] * hb[i], mj = ha[j] * hb[j];
			float wi = mj / (mi + mj); // the lighter body gives way more
			// Against the glass a body cannot give way: its partner takes it all.
			float push = ov * omega;
			float xi = x[i] - nx * push * wi, yi = y[i] - ny * push * wi;
			float xj = x[j] + nx * push * (1.0f - wi), yj = y[j] + ny * push * (1.0f - wi);
			float xi0 = xi, yi0 = yi, xj0 = xj, yj0 = yj;
			keep_in_dish(xi, yi, species[sp[i]].extent);
			keep_in_dish(xj, yj, species[sp[j]].extent);
			float dix = xi - xi0, diy = yi - yi0, djx = xj - xj0, djy = yj - yj0;
			xj += dix;
			yj += diy;
			xi += djx;
			yi += djy;
			x[i] = xi;
			y[i] = yi;
			x[j] = xj;
			y[j] = yj;
			float vrel = (vx[j] - vx[i]) * nx + (vy[j] - vy[i]) * ny;
			if (vrel < 0.0f) {
				vx[i] += nx * vrel * wi;
				vy[i] += ny * vrel * wi;
				vx[j] -= nx * vrel * (1.0f - wi);
				vy[j] -= ny * vrel * (1.0f - wi);
			}
		}
		prof_iters += 1.0;
		if (worst < 0.25f) { // settled to under a pixel at normal zoom
			break;
		}
	}
	prof_pairs += np;
	for (int i = 0; i < n; i++) {
		if (alive[i] && species[sp[i]].body.empty()) {
			keep_in_dish(x[i], y[i], species[sp[i]].extent);
		}
	}
}

// --- interventions --------------------------------------------------------------

// 0..1: eases in over 2 s and out over the last 4 s.
float SimCore::spot_fade(float life, float ttl) const {
	return clampf(life / 2.0f, 0.0f, 1.0f) * clampf((ttl - life) / 4.0f, 0.0f, 1.0f);
}

int SimCore::add_barrier(Vector2 a, Vector2 b, float seconds) {
	barriers.push_back({ a.x, a.y, b.x, b.y, 0.0f, seconds });
	return (int)barriers.size() - 1;
}

int SimCore::add_temp_spot(Vector2 pos, float radius, float delta, float seconds) {
	temp_spots.push_back({ pos.x, pos.y, radius, delta, 0.0f, seconds });
	rebuild_env();
	return (int)temp_spots.size() - 1;
}

int SimCore::add_current(Vector2 pos, float radius, Vector2 velocity, float seconds) {
	jets.push_back({ pos.x, pos.y, radius, velocity.x, velocity.y, 0.0f, seconds });
	return (int)jets.size() - 1;
}

void SimCore::step_interventions(float dt) {
	auto age = [dt](auto &list) {
		for (auto &e : list) {
			e.life += dt;
		}
		list.erase(std::remove_if(list.begin(), list.end(), [](const auto &e) { return e.life >= e.ttl; }), list.end());
	};
	// Passing lights: the light is taken back out when one goes.
	for (auto &lp : light_pulses) {
		lp.life += dt;
		if (lp.life >= lp.ttl) {
			light_profile(lp.x, lp.y, lp.r, -lp.power);
		}
	}
	light_pulses.erase(std::remove_if(light_pulses.begin(), light_pulses.end(), [](const LightPulse &e) { return e.life >= e.ttl; }), light_pulses.end());
	size_t spots_before = temp_spots.size();
	age(barriers);
	age(temp_spots);
	age(jets);
	age(irons);
	// Warm / cold spots fade: refresh the water twice a second while any
	// is on (and once more when the last one goes).
	temp_rebuild -= dt;
	if ((!temp_spots.empty() && temp_rebuild <= 0.0f) || temp_spots.size() != spots_before) {
		temp_rebuild = 0.5f;
		rebuild_env();
	}
}

// No organism crosses a membrane: anyone on the wrong side of a segment (or
// inside its thickness) is put back on the side it came from, and its
// velocity into the membrane is reflected.
void SimCore::enforce_barriers() {
	if (barriers.empty()) {
		return;
	}
	const float half = 4.0f;
	for (const Barrier &b : barriers) {
		float ex = b.bx - b.ax, ey = b.by - b.ay;
		float len2 = std::max(ex * ex + ey * ey, 1e-3f);
		float len = std::sqrt(len2);
		float nx = -ey / len, ny = ex / len;
		for (int i = 0; i < count; i++) {
			if (!alive[i] || join[i] > 0.0f) {
				continue;
			}
			float r = species[sp[i]].body.empty() ? hb[i] : species[sp[i]].extent;
			float t = ((x[i] - b.ax) * ex + (y[i] - b.ay) * ey) / len2;
			if (t < -0.05f || t > 1.05f) {
				continue;
			}
			float side_now = (x[i] - b.ax) * nx + (y[i] - b.ay) * ny;
			float side_was = (px[i] - b.ax) * nx + (py[i] - b.ay) * ny;
			float s = side_was >= 0.0f ? 1.0f : -1.0f;
			float need = r + half;
			if (side_now * s < need) {
				float push = need - side_now * s;
				x[i] += nx * s * push;
				y[i] += ny * s * push;
				float vn = vx[i] * nx + vy[i] * ny;
				if (vn * s < 0.0f) {
					vx[i] -= 1.6f * vn * nx;
					vy[i] -= 1.6f * vn * ny;
				}
			}
		}
	}
}

Array SimCore::get_interventions() const {
	Array out;
	for (const Barrier &b : barriers) {
		Dictionary d;
		d["kind"] = "membrane";
		d["a"] = Vector2(b.ax, b.ay);
		d["b"] = Vector2(b.bx, b.by);
		d["fade"] = spot_fade(b.life, b.ttl);
		d["left"] = b.ttl - b.life;
		out.push_back(d);
	}
	for (const TempSpot &sp : temp_spots) {
		Dictionary d;
		d["kind"] = sp.delta >= 0.0f ? "warm" : "cold";
		d["center"] = Vector2(sp.x, sp.y);
		d["radius"] = sp.r;
		d["delta"] = sp.delta;
		d["fade"] = spot_fade(sp.life, sp.ttl);
		d["left"] = sp.ttl - sp.life;
		out.push_back(d);
	}
	for (const IronSpot &ir : irons) {
		Dictionary d;
		d["kind"] = "iron";
		d["center"] = Vector2(ir.x, ir.y);
		d["radius"] = ir.r;
		d["fade"] = spot_fade(ir.life, ir.ttl);
		d["left"] = ir.ttl - ir.life;
		out.push_back(d);
	}
	for (const Jet &jt : jets) {
		Dictionary d;
		d["kind"] = "current";
		d["center"] = Vector2(jt.x, jt.y);
		d["radius"] = jt.r;
		d["velocity"] = Vector2(jt.vx, jt.vy);
		d["fade"] = spot_fade(jt.life, jt.ttl);
		d["left"] = jt.ttl - jt.life;
		out.push_back(d);
	}
	return out;
}

int SimCore::spawn(int s, Vector2 pos, int n, float spread) {
	int made = 0;
	for (int k = 0; k < n; k++) {
		float a = rand_range(0.0f, TAU), r = spread * std::sqrt(randf());
		if (spawn_one(s, pos.x + std::cos(a) * r, pos.y + std::sin(a) * r, -1) >= 0) {
			made++;
		}
	}
	return made;
}

void SimCore::kill(int i, int cause) {
	if (!alive[i]) {
		return;
	}
	alive[i] = 0;
	if (pair[i] >= 0) {
		int o = pair[i];
		pair[o] = -1;
		join[o] = 0.0f;
		pair[i] = -1;
	}
	Species &S = species[sp[i]];
	S.alive--;
	if (cause != CAUSE_HATCH) {
		emit(cause == CAUSE_EATEN ? EV_EATEN : (cause == CAUSE_PHAGE ? EV_LYSIS : EV_DIED), x[i], y[i], sp[i], species[sp[i]].extent, heading[i]);
	}
	if (cause == CAUSE_EATEN) {
		// The predator has already taken everything (see the bite code).
		S.deaths_eaten++;
		energy[i] = 0.0f;
		return;
	}
	if (cause == CAUSE_PHAGE) {
		// Burst: no shell; what it held spills into the water (the viral shunt).
		S.deaths_phage++;
		nutrient[nutrient_index(x[i], y[i])] += std::max(0.0f, energy[i]) + body_energy(sp[i]);
		energy[i] = 0.0f;
		return;
	}
	if (cause == CAUSE_STALK || cause == CAUSE_HATCH) {
		(cause == CAUSE_STALK ? S.deaths_stalk : S.deaths_hatch)++;
		nutrient[nutrient_index(x[i], y[i])] += std::max(0.0f, energy[i]) + body_energy(sp[i]);
		energy[i] = 0.0f;
		return;
	}
	if (cause == CAUSE_STARVE) {
		S.deaths_starve++;
	} else if (cause == CAUSE_TEMP) {
		S.deaths_temp++;
	} else if (cause == CAUSE_ACID) {
		S.deaths_acid++;
	} else if (cause == CAUSE_O2) {
		S.deaths_o2++;
	} else {
		S.deaths_age++;
	}
	if (S.rotifer) {
		// (Its body is drawn as it sags and fades: scripts/rotifer_layer.gd.)
		energy_out += std::max(0.0f, energy[i]) + body_energy(sp[i]);
	} else {
		add_shell(i);
	}
	energy[i] = 0.0f;
}

void SimCore::move_agent(int w, int r) {
	id[w] = id[r];
	sp[w] = sp[r];
	lineage[w] = lineage[r];
	gen[w] = gen[r];
	target[w] = target[r];
	x[w] = x[r];
	y[w] = y[r];
	px[w] = px[r];
	py[w] = py[r];
	vx[w] = vx[r];
	vy[w] = vy[r];
	heading[w] = heading[r];
	pheading[w] = pheading[r];
	energy[w] = energy[r];
	age[w] = age[r];
	phase[w] = phase[r];
	cooldown[w] = cooldown[r];
	wander[w] = wander[r];
	digest[w] = digest[r];
	t_speed[w] = t_speed[r];
	t_vision[w] = t_vision[r];
	t_armor[w] = t_armor[r];
	t_attack[w] = t_attack[r];
	t_fertility[w] = t_fertility[r];
	t_efficiency[w] = t_efficiency[r];
	t_neural[w] = t_neural[r];
	alive[w] = 1;
	bitten[w] = bitten[r];
	action[w] = action[r];
	crowd[w] = crowd[r];
	inf_t[w] = inf_t[r];
	inf_ang[w] = inf_ang[r];
	inf_fate[w] = inf_fate[r];
	immune[w] = immune[r];
	carry[w] = carry[r];
	hijack[w] = hijack[r];
	slug[w] = slug[r];
	sl_ox[w] = sl_ox[r];
	sl_oy[w] = sl_oy[r];
	spore[w] = spore[r];
	gest[w] = gest[r];
	gwait[w] = gwait[r];
	store[w] = store[r];
	cslow[w] = cslow[r];
	cspurn[w] = cspurn[r];
	cpiece[w] = cpiece[r];
	rot_meal[w] = rot_meal[r];
	rot_t[w] = rot_t[r];
	cheld[w] = cheld[r];
	for (int k = 0; k < COL_MAXB; k++) {
		cmark[w * COL_MAXB + k] = cmark[r * COL_MAXB + k];
		cdmg[w * COL_MAXB + k] = cdmg[r * COL_MAXB + k];
		cbroken[w * COL_MAXB + k] = cbroken[r * COL_MAXB + k];
	}
	if (gest[r] >= 0.0f) {
		for (int k = 0; k < COL_GERMS; k++) {
			emb[w * COL_GERMS + k] = emb[r * COL_GERMS + k];
		}
	}
	ncards[w] = ncards[r];
	for (int k = 0; k < MAX_CARDS; k++) {
		cards[w * MAX_CARDS + k] = cards[r * MAX_CARDS + k];
	}
	sense[w] = sense[r];
	fired[w] = fired[r];
	state[w] = state[r];
	st_time[w] = st_time[r];
	hurt[w] = hurt[r];
	threat_d[w] = threat_d[r];
	tgx[w] = tgx[r];
	tgy[w] = tgy[r];
	t_topt[w] = t_topt[r];
	t_ttol[w] = t_ttol[r];
	stress_t[w] = stress_t[r];
	stress_a[w] = stress_a[r];
	join[w] = join[r];
	join_mut[w] = join_mut[r];
	for (auto *v : { &sw, &psw, &curl, &ha, &hb, &vs, &angv, &latch, &gulp_t, &gulp_r, &gulp_lx, &gulp_ly, &gulp_h, &gulp_ph }) {
		(*v)[w] = (*v)[r];
	}
	gulp_sp[w] = gulp_sp[r];
	gulp_lin[w] = gulp_lin[r];
	pair[w] = pair[r];
	if (pair[w] >= 0) {
		pair[pair[w]] = w; // the partner keeps pointing at us
	}
}

void SimCore::compact() {
	int w = 0;
	for (int r = 0; r < count; r++) {
		if (!alive[r]) {
			continue;
		}
		if (w != r) {
			move_agent(w, r);
		}
		w++;
	}
	count = w;
}

void SimCore::rebuild_grids() {
	auto cell_of = [&](float wx, float wy) {
		int ci = (int)clampf(wx / acell, 0.0f, (float)(agw - 1));
		int cj = (int)clampf(wy / acell, 0.0f, (float)(agh - 1));
		return cj * agw + ci;
	};
	std::fill(ahead.begin(), ahead.end(), -1);
	for (int i = 0; i < count; i++) {
		int c = cell_of(x[i], y[i]);
		anext[i] = ahead[c];
		ahead[c] = i;
	}
	std::fill(lhead.begin(), lhead.end(), -1);
	for (int a = 0; a < algae; a++) {
		int c = cell_of(al_x[a], al_y[a]);
		lnext[a] = lhead[c];
		lhead[c] = a;
	}
	std::fill(shead.begin(), shead.end(), -1);
	for (int s = 0; s < shells; s++) {
		int c = cell_of(sh_x[s], sh_y[s]);
		snext[s] = shead[c];
		shead[c] = s;
	}
}

void SimCore::emit(int type, float ex, float ey, int s, float a, float b) {
	if (events.size() >= 6 * 6000) {
		return;
	}
	events.push_back((float)type);
	events.push_back(ex);
	events.push_back(ey);
	events.push_back((float)s);
	events.push_back(a);
	events.push_back(b);
}

PackedFloat32Array SimCore::take_events() {
	PackedFloat32Array out;
	out.resize((int)events.size());
	std::copy(events.begin(), events.end(), out.ptrw());
	events.clear();
	return out;
}

// Energy to divide: fertility lowers it; a thrifty metabolism raises it
// (the cost of efficiency: it lasts longer, but breeds slower).
float SimCore::divide_energy(int i) const {
	if (species[sp[i]].colony) {
		return species[sp[i]].col_e;
	}
	float r = species[sp[i]].radius;
	// Breeding: splits at six tenths (leaner children; the cooldown halves too).
	return (r * r * (2.6f - 0.22f * t_fertility[i] + METAB_DIVIDE * (t_efficiency[i] - 3.0f)) + body_energy(sp[i])) * (1.0f + 0.2f * species[sp[i]].store)
			* (state[i] == S_BREED ? 0.6f : 1.0f);
}

bool SimCore::cond_true(int i, uint8_t c, float t) const {
	const Species &S = species[sp[i]];
	switch (c) {
		case C_NONE: return true;
		case C_ENERGY_BELOW: return energy[i] < t * divide_energy(i);
		case C_ENERGY_ABOVE: return energy[i] > t * divide_energy(i);
		case C_SEE_ALGAE: return (sense[i] & S_ALGAE) != 0;
		case C_PREDATOR_NEAR: return (sense[i] & S_THREAT) != 0 && threat_d[i] < t;
		case C_SEE_PREY: return (sense[i] & S_PREY) != 0;
		case C_CROWD: return crowd[i] >= t;
		case C_ATTACKED: return (sense[i] & S_ATTACKED) != 0;
		case C_AGE_ABOVE: return age[i] > t * S.lifespan * (0.85f + 0.06f * t_efficiency[i]);
		case C_SEE_SHELL: return (sense[i] & S_SHELL) != 0;
		case C_TEMP_BAD: return temp_dev(i) > 0.0f;
		case C_SIGNAL_A: return sig_a[nutrient_index(x[i], y[i])] > t;
		case C_SIGNAL_B: return sig_b[nutrient_index(x[i], y[i])] > t;
		case C_STATE_TIME: return st_time[i] > t;
		case C_PEER_STATE: return scans[i].peer[std::min(3, std::max(0, (int)t))] >= 0;
		case C_IMMUNE: return immune[i] != 0;
		case C_O2_ABOVE: return o2_on && o2[nutrient_index(x[i], y[i])] > t;
		case C_PREY_NEAR:
		case C_PREY_SMALL: {
			Card one;
			one.c[0] = c;
			one.t[0] = t;
			return pick_prey(i, one) >= 0;
		}
		default: return false;
	}
}

// The prey a card is about: the best-ranked one in sight that meets all of
// the card's prey conditions together (seeing prey, close enough, small
// enough), or -1. A card with no prey condition takes the usual target.
int SimCore::pick_prey(int i, const Card &cd) const {
	const Scan &sc = scans[i];
	const float r = species[sp[i]].radius;
	for (int k = 0; k < sc.ncand; k++) {
		int j = sc.cand[k];
		if (!alive[j]) {
			continue;
		}
		bool ok = true;
		for (int m = 0; m < 2 && ok; m++) {
			if (cd.neg & (1 << m)) {
				continue;
			}
			if (cd.c[m] == C_PREY_NEAR) {
				ok = sc.cand_d[k] < cd.t[m];
			} else if (cd.c[m] == C_PREY_SMALL) {
				ok = species[sp[j]].radius < cd.t[m] * r;
			}
		}
		if (ok) {
			return j;
		}
	}
	return -1;
}

// Condition k of a card, with its 不 applied (an empty slot always holds).
bool SimCore::cond_ok(int i, const Card &cd, int k) const {
	if (cd.c[k] == C_NONE) {
		return true;
	}
	return cond_true(i, cd.c[k], cd.t[k]) != ((cd.neg >> k) & 1);
}

// Both conditions (且), or either (或; with one slot empty it is just the other).
bool SimCore::card_holds(int i, const Card &cd) const {
	bool a = cond_ok(i, cd, 0), b = cond_ok(i, cd, 1);
	if (cd.any && cd.c[0] != C_NONE && cd.c[1] != C_NONE) {
		return a || b;
	}
	return a && b;
}

bool SimCore::act_possible(int i, uint8_t a) const {
	const Species &S = species[sp[i]];
	switch (a) {
		case A_SEEK_ALGAE: return (sense[i] & S_ALGAE) != 0;
		case A_FLEE: return (sense[i] & S_THREAT) != 0;
		case A_HUNT: return (sense[i] & S_PREY) != 0 && digest[i] <= 0.0f;
		case A_FOLLOW: return crowd[i] > 0;
		case A_DISPERSE: return crowd[i] > 0;
		case A_INDUCE: return S.prophage > 0.0f && inf_t[i] < 0.0f && join[i] <= 0.0f;
		// (Not once it has arrived: on the far field it is home.)
		case A_AGGREGATE: {
			float gx = x[i] - slug_tx, gy = y[i] - slug_ty;
			return slug_host == sp[i] && join[i] <= 0.0f && pair[i] < 0 && inf_t[i] < 0.0f && gx * gx + gy * gy > slug_stay * slug_stay;
		}
		case A_DIVIDE:
			if (S.colony) {
				return gest[i] < 0.0f && energy[i] >= S.col_e && cooldown[i] <= 0.0f && !S.col_germ.empty();
			}
			return energy[i] > body_energy(sp[i]) + S.radius * S.radius * 0.8f && cooldown[i] <= 0.0f && count < MAX_AGENTS && (inf_t[i] < 0.0f || inf_fate[i] == 2);
		case A_SCAVENGE: return (sense[i] & S_SHELL) != 0;
		case A_SEEK_COMFORT: {
			float dx, dy;
			return temp_dev(i) > 0.0f && comfort_dir(i, dx, dy);
		}
		case A_SEEK_SIG_A:
		case A_SEEK_SIG_B: {
			float dx, dy;
			return signal_dir(i, a - A_SEEK_SIG_A, dx, dy);
		}
		case A_AVOID_O2:
		case A_SEEK_O2: {
			float dx, dy;
			return o2_dir(i, a == A_SEEK_O2, dx, dy);
		}
		case A_TO_FORAGE:
		case A_TO_ALERT:
		case A_TO_BREED:
		case A_TO_SLEEP: return state[i] != a - A_TO_FORAGE;
		default: return true; // rest, wander, signals
	}
}

PackedFloat32Array SimCore::get_analysis(Rect2 rect, float alpha) const {
	PackedFloat32Array out;
	for (int i = 0; i < count; i++) {
		float ox = lerpf(px[i], x[i], alpha), oy = lerpf(py[i], y[i], alpha);
		if (!rect.has_point(Vector2(ox, oy))) {
			continue;
		}
		const Species &S = species[sp[i]];
		float vision_r = 30.0f + 24.0f * t_vision[i] + (S.body.empty() ? 0.0f : S.radius * 2.0f);
		out.push_back(ox);
		out.push_back(oy);
		out.push_back(vision_r);
		out.push_back((float)action[i]);
		out.push_back(tgx[i] + (ox - x[i]));
		out.push_back(tgy[i] + (oy - y[i]));
		out.push_back((float)sp[i]);
		out.push_back(S.extent);
	}
	return out;
}

PackedFloat32Array SimCore::get_marks(Rect2 rect, float alpha) const {
	PackedFloat32Array out;
	for (int i = 0; i < count; i++) {
		float ox = lerpf(px[i], x[i], alpha), oy = lerpf(py[i], y[i], alpha);
		if (!rect.has_point(Vector2(ox, oy))) {
			continue;
		}
		out.push_back(ox);
		out.push_back(oy);
		out.push_back((float)sp[i]);
		out.push_back((float)state[i]);
		out.push_back((float)action[i]);
		out.push_back(species[sp[i]].extent);
	}
	return out;
}

Array SimCore::get_analysis_lines(Rect2 rect, float alpha) const {
	std::vector<PackedVector2Array> lines(ACT_DISPERSE + 1);
	for (int i = 0; i < count; i++) {
		float ox = lerpf(px[i], x[i], alpha), oy = lerpf(py[i], y[i], alpha);
		if (!rect.has_point(Vector2(ox, oy))) {
			continue;
		}
		float tx = tgx[i] + (ox - x[i]), ty = tgy[i] + (oy - y[i]);
		if ((tx - ox) * (tx - ox) + (ty - oy) * (ty - oy) < 4.0f || action[i] >= lines.size()) {
			continue;
		}
		lines[action[i]].push_back(Vector2(ox, oy));
		lines[action[i]].push_back(Vector2(tx, ty));
	}
	Array out;
	for (const PackedVector2Array &l : lines) {
		out.push_back(l);
	}
	return out;
}

PackedFloat32Array SimCore::build_analysis_buffer(Rect2 rect, float alpha, int capacity) {
	// One ring instance per organism in view: transform scale = vision
	// diameter, colour = species, custom.x = action. Unused slots are zero.
	PackedFloat32Array out;
	out.resize(std::max(capacity, 0) * FLOATS_PER_INSTANCE);
	float *w = out.ptrw();
	std::fill(w, w + out.size(), 0.0f);
	int n = 0;
	for (int i = 0; i < count && n < capacity; i++) {
		float ox = lerpf(px[i], x[i], alpha), oy = lerpf(py[i], y[i], alpha);
		if (!rect.has_point(Vector2(ox, oy))) {
			continue;
		}
		const Species &S = species[sp[i]];
		float d = 2.0f * (30.0f + 24.0f * t_vision[i] + (S.body.empty() ? 0.0f : S.radius * 2.0f));
		float *q = w + n * FLOATS_PER_INSTANCE;
		q[0] = d;
		q[3] = ox;
		q[5] = d;
		q[7] = oy;
		q[8] = S.color.r;
		q[9] = S.color.g;
		q[10] = S.color.b;
		q[11] = 1.0f;
		q[12] = (float)action[i];
		q[13] = S.extent / (0.5f * d);
		n++;
	}
	analysis_count = n;
	return out;
}

Array SimCore::get_species_deck(int s) const {
	Array out;
	if (s >= 0 && s < (int)species.size()) {
		for (const Card &c : species[s].deck) {
			out.push_back(card_to(c));
		}
	}
	return out;
}

float SimCore::body_radius(int i, float dx, float dy) const {
	const Species &S = species[sp[i]];
	if (S.half_len <= 0.0f) {
		return S.extent;
	}
	// Ellipse radius toward (dx, dy) in the body's own frame.
	float c = std::cos(heading[i]), s = std::sin(heading[i]);
	float lx = dx * c + dy * s, ly = -dx * s + dy * c;
	float l = std::sqrt(lx * lx + ly * ly) + 1e-5f;
	float ct = lx / l, st = ly / l;
	float a = S.half_len, b = S.half_wid;
	return a * b / std::sqrt(b * b * ct * ct + a * a * st * st);
}

void SimCore::scan_one(int i) {
	// Read-only look around for organism i, against the state at the start of
	// the tick; safe to run for many organisms in parallel.
	Scan &out = scans[i];
	const Species &S = species[sp[i]];
	const float r = S.radius;
	const bool multicell = !S.body.empty();
	// Alert: it looks further (and pays for it, see the metabolism).
	const float vision_r = (30.0f + 24.0f * t_vision[i] + (multicell ? r * 2.0f : 0.0f)) * (state[i] == S_ALERT ? 1.3f : 1.0f);
	const float divide_at = divide_energy(i);
	const bool hungry = energy[i] < divide_at;
	const float reach = std::max(std::max(vision_r, 60.0f), S.extent + max_extent);
	const float scan_d2 = reach * reach;
	int c0 = std::max((int)((x[i] - reach) / acell), 0);
	int c1 = std::min((int)((x[i] + reach) / acell), agw - 1);
	int r0 = std::max((int)((y[i] - reach) / acell), 0);
	int r1 = std::min((int)((y[i] + reach) / acell), agh - 1);

	// Neighbour scan: nearest threat, nearest prey, flock centre, separation.
	int threat = -1, prey = -1;
	int cfood = -1;
	float cfood_best = 0.0f;
	// Every predator in sight is noted with its distance; the deck decides how
	// close is too close (default card: 60).
	float threat_d2 = vision_r * vision_r, prey_d2 = vision_r * vision_r;
	float cand_rank[PREY_CAND];
	out.ncand = 0;
	float fx = 0, fy = 0, sx = 0, sy = 0;
	int flock = 0;
	for (int cj = r0; cj <= r1; cj++) {
		for (int ci = c0; ci <= c1; ci++) {
			for (int j = ahead[cj * agw + ci]; j >= 0; j = anext[j]) {
				if (j == i || !alive[j] || join[j] > 0.0f) {
					continue;
				}
				float dx = x[j] - x[i], dy = y[j] - y[i];
				float d2 = dx * dx + dy * dy;
				if (d2 > scan_d2) {
					continue;
				}
				const Species &T = species[sp[j]];
				float touch = std::max(S.extent, ha[i]) + std::max(T.extent, ha[j]);
				if (d2 < touch * touch && d2 > 1e-4f) {
					// Push apart, the smaller body giving way more. Multicell
					// bodies collide as their drawn ellipse, from its centre.
					float ex = dx, ey = dy;
					float ri = cell_radius(i, dx, dy), rj = cell_radius(j, -dx, -dy);
					if (S.half_len > 0.0f || T.half_len > 0.0f) {
						ex += T.center_off * std::cos(heading[j]) - S.center_off * std::cos(heading[i]);
						ey += T.center_off * std::sin(heading[j]) - S.center_off * std::sin(heading[i]);
						ri = body_radius(i, ex, ey);
						rj = body_radius(j, -ex, -ey);
					}
					float d = std::sqrt(ex * ex + ey * ey);
					float t2 = ri + rj;
					if (d < t2 && d > 1e-3f) {
						// Big bodies resolve the whole overlap at once (the
						// usual half step lets two giants sink into each other).
						float share = 2.0f * rj / (ri + rj) * (S.half_len > 0.0f && T.half_len > 0.0f ? 2.0f : 1.0f);
						sx -= ex / d * (t2 - d) * share;
						sy -= ey / d * (t2 - d) * share;
					}
				}
				if (sp[j] == sp[i]) {
					// Peers in sight by the state they are in (level 12: “看见
					// 处于 X 状态的同伴”).
					if (d2 < vision_r * vision_r && d2 < out.peer_d2[state[j]]) {
						out.peer_d2[state[j]] = d2;
						out.peer[state[j]] = j;
					}
					if (d2 < 60.0f * 60.0f) {
						fx += dx;
						fy += dy;
						flock++;
						if (S.diet == DIET_PREDATOR && d2 > 1e-4f) {
							// Predators keep their distance from rivals of their own kind.
							float d = std::sqrt(d2);
							sx -= dx / d * (60.0f - d) * 0.02f;
							sy -= dy / d * (60.0f - d) * 0.02f;
						}
					}
					continue;
				}
				// Chapter 6: a producer cell is a grazer's food (bigger and closer is better).
				if (S.diet == DIET_GRAZER && T.diet == DIET_PHOTO && d2 < vision_r * vision_r && join[j] <= 0.0f && y[j] >= graze_refuge) {
					float score = (std::max(0.0f, energy[j]) + 5.0f) / (std::sqrt(d2) + 12.0f);
					if (score > cfood_best) {
						cfood_best = score;
						cfood = j;
					}
				}
				bool they_eat_me = T.diet == DIET_PREDATOR && r < T.radius * 0.9f;
				// (Chapter 6: a hunter goes after what moves; producers are grazed, not hunted.)
				bool i_eat_them = S.diet == DIET_PREDATOR && T.radius < r * 0.9f && T.diet != DIET_PHOTO;
				if (they_eat_me && d2 < threat_d2) {
					threat_d2 = d2;
					threat = j;
				}
				// A herd: it cannot pick one out of a tight group, only
				// stragglers (level 12; real fish shoals and bacterial clumps).
				if (i_eat_them && S.herd > 0.0f && crowd[j] >= S.herd) {
					i_eat_them = false;
				}
				if (i_eat_them) {
					// Prey switching: hunters fix on whichever prey is
					// common and overlook rare kinds, which protects them.
					// Measured against the average share, so it keeps
					// working however many species share the dish.
					float share = (float)T.alive / (float)std::max(count, 1);
					float rel = share * (float)species.size();
					float pd2 = d2 * (1.0f + 4.0f * (1.0f - std::min(1.0f, rel)));
					// Big eyespots catch the light: prey with keen sense is
					// spotted from further off.
					float seen = 1.0f + SENSE_SEEN * (t_vision[j] - 2.0f);
					pd2 /= seen * seen;
					if (pd2 < prey_d2) {
						prey_d2 = pd2;
						prey = j;
					}
					if (pd2 < vision_r * vision_r) {
						// Keep the few best-ranked, in order (insertion).
						int at = out.ncand < PREY_CAND ? out.ncand : PREY_CAND - 1;
						if (out.ncand < PREY_CAND || pd2 < cand_rank[at]) {
							while (at > 0 && cand_rank[at - 1] > pd2) {
								cand_rank[at] = cand_rank[at - 1];
								out.cand[at] = out.cand[at - 1];
								out.cand_d[at] = out.cand_d[at - 1];
								at--;
							}
							cand_rank[at] = pd2;
							out.cand[at] = j;
							out.cand_d[at] = std::sqrt(d2);
							out.ncand = std::min(out.ncand + 1, PREY_CAND);
						}
					}
				}
			}
		}
	}

	out.threat = threat;
	out.threat_d = threat >= 0 ? std::sqrt(threat_d2) : 1e9f;
	out.prey = prey;
	out.fx = fx;
	out.fy = fy;
	out.sx = sx;
	out.sy = sy;
	out.flock = flock;
	out.cfood = cfood;
	out.food = -1;
	out.carcass = -1;
	out.lure = -1;
	(void)hungry;
	// A giant virus looks like food: the nearest one in sight, to a cell that
	// could eat it (level 19; the mimicry the real one is named for).
	if (giant_host == sp[i] && !giants.empty()) {
		float near2 = vision_r * vision_r;
		for (int cj = r0; cj <= r1; cj++) {
			for (int ci = c0; ci <= c1; ci++) {
				for (int g = ghead[cj * agw + ci]; g >= 0; g = gnext[g]) {
					float dx = giants[g].x - x[i], dy = giants[g].y - y[i];
					float d2 = dx * dx + dy * dy;
					if (d2 < near2 && giants[g].age > 1.0f) {
						near2 = d2;
						out.lure = g;
					}
				}
			}
		}
	}
	if (S.diet == DIET_GRAZER) {
		// Best clump in sight: bigger and closer is better.
		float best = 0.0f;
		for (int cj = r0; cj <= r1; cj++) {
			for (int ci = c0; ci <= c1; ci++) {
				for (int a = lhead[cj * agw + ci]; a >= 0; a = lnext[a]) {
					float dx = al_x[a] - x[i], dy = al_y[a] - y[i];
					float d2 = dx * dx + dy * dy;
					if (d2 > vision_r * vision_r) {
						continue;
					}
					float score = al_e[a] / (std::sqrt(d2) + 12.0f);
					if (score > best) {
						best = score;
						out.food = a;
					}
				}
			}
		}
	} else if (S.diet == DIET_PREDATOR) {
		float best_d2 = vision_r * vision_r;
		for (int cj = r0; cj <= r1; cj++) {
			for (int ci = c0; ci <= c1; ci++) {
				for (int s = shead[cj * agw + ci]; s >= 0; s = snext[s]) {
					float dx = sh_x[s] - x[i], dy = sh_y[s] - y[i];
					float d2 = dx * dx + dy * dy;
					if (d2 < best_d2) {
						best_d2 = d2;
						out.carcass = s;
					}
				}
			}
		}
	}
}

void SimCore::step(float dt) {
	sim_time += dt;
	last_dt = dt;
	step_interventions(dt);
	for (int i = 0; i < count; i++) {
		px[i] = x[i];
		py[i] = y[i];
		pheading[i] = heading[i];
		if (sw[i] > 1000.0f) {
			sw[i] -= TAU * std::floor(sw[i] / TAU);
		}
		psw[i] = sw[i];
		bitten[i] = 0;
	}
	using clk = std::chrono::steady_clock;
	auto t0 = clk::now();
	step_nutrients(dt);
	step_signals(dt);
	step_oxygen(dt);
	step_net(dt);
	auto t1 = clk::now();
	step_algae(dt);
	step_shells(dt);
	auto t2 = clk::now();
	rebuild_grids();
	auto t3 = clk::now();

	const int n = count;
	// Look around in parallel (read-only), then act in order.
	int threads = std::min(max_threads, (int)std::min(8u, std::max(1u, std::thread::hardware_concurrency())));
	if (n < 400) {
		threads = 1;
	}
	if (threads == 1) {
		for (int i = 0; i < n; i++) {
			scan_one(i);
		}
	} else {
		std::vector<std::thread> pool;
		int chunk = (n + threads - 1) / threads;
		for (int k = 0; k < threads; k++) {
			int a = k * chunk, b = std::min(n, a + chunk);
			pool.emplace_back([this, a, b]() {
				for (int i = a; i < b; i++) {
					scan_one(i);
				}
			});
		}
		for (std::thread &t : pool) {
			t.join();
		}
	}
	auto t3b = clk::now();
	for (int i = 0; i < n; i++) {
		if (!alive[i]) {
			continue;
		}
		if (cheld[i]) {
			continue; // (in a rotifer's mouth: step_rotifers holds it)
		}
		if (slug[i] >= 0) {
			action[i] = ACT_SLUG;
			continue;
		}
		if (spore[i] > 0.0f) {
			// A spore: flung out, it settles and waits, then wakes fed.
			float k = std::exp(-1.1f * dt);
			vx[i] *= k;
			vy[i] *= k;
			x[i] += vx[i] * dt;
			y[i] += vy[i] * dt;
			keep_in_dish(x[i], y[i], S_SPORE_EDGE);
			spore[i] -= dt;
			if (spore[i] <= 0.0f) {
				spore[i] = 0.0f;
				energy[i] = std::max(energy[i], divide_energy(i) * 0.8f);
				age[i] = 0.0f;
			}
			action[i] = ACT_REST;
			continue;
		}
		if (join[i] > 0.0f) {
			int o = pair[i];
			join[i] = std::max(0.0f, join[i] - dt);
			if (o >= 0 && alive[o]) {
				// Held ahead of the parent along its heading, the gap opening
				// as the parent's body pinches (the shader draws the same curve).
				float u = 1.0f - join[i] / JOIN_TIME;
				float sep = clampf((u - 0.08f) / 0.87f, 0.0f, 1.0f); // = smoothstep(0.08, 0.95) in the shader
				sep = sep * sep * (3.0f - 2.0f * sep);
				// Fully parted, the two drawn bodies just touch end to end.
				float gap = (ha[o] + ha[i]) * sep;
				x[i] = x[o] + std::cos(heading[o]) * gap;
				y[i] = y[o] + std::sin(heading[o]) * gap;
				vx[i] = vx[o];
				vy[i] = vy[o];
				heading[i] = heading[o];
			}
			if (join[i] <= 0.0f || o < 0 || !alive[o]) {
				// Parted: two organisms now, each its own way.
				join[i] = 0.0f;
				if (o >= 0) {
					pair[o] = -1;
				}
				pair[i] = -1;
				wander[i] = heading[i] + 0.6f;
				if (o >= 0) {
					wander[o] = heading[o] - 0.6f;
				}
				emit(join_mut[i] ? EV_MUTATION : EV_BIRTH, x[i], y[i], sp[i], o >= 0 ? x[o] : x[i], o >= 0 ? y[o] : y[i]);
			}
			continue;
		}
		const Species &S = species[sp[i]];
		const float r = S.radius;
		const float body_r = S.colony ? S.extent : r; // what touches its food
		const bool multicell = !S.body.empty() && !S.colony; // (a colony swims like a cell: it turns, then pushes)
		const float vision_r = 30.0f + 24.0f * t_vision[i] + (multicell ? r * 2.0f : 0.0f);
		// Alert swims 25% faster (its top speed, so a flat-out flight gains too).
		const float max_speed = S.colony ? S.col_speed * (1.0f - cslow[i]) : (18.0f + 14.0f * t_speed[i]) * (1.0f - 0.04f * t_armor[i]) * (multicell ? 0.7f : 1.0f) * S.speed_mult
				* S.motor_speed * (state[i] == S_ALERT ? 1.25f : 1.0f)
				* (net_on ? 1.0f - net_slow * net_at(x[i], y[i]) : 1.0f); // (chapter 6 boss: held in the net)
		// Division needs the split energy plus a new body for the child; an
		// organism keeps feeding until it has both.
		const float child_body = body_energy(sp[i]);
		const float divide_at = divide_energy(i);
		const bool hungry = energy[i] < divide_at;

		// Results of this tick's parallel scan (see scan_one).
		const Scan &sc = scans[i];
		int threat = sc.threat >= 0 && alive[sc.threat] ? sc.threat : -1;
		int prey = sc.prey >= 0 && alive[sc.prey] ? sc.prey : -1;
		float fx = sc.fx, fy = sc.fy, sx = sc.sx, sy = sc.sy;
		int flock = sc.flock;

		// What it senses, kept for the deck and for explanations.
		int food = S.diet == DIET_GRAZER && sc.food >= 0 && al_e[sc.food] > 0.0f ? sc.food : -1;
		int lure = sc.lure >= 0 && sc.lure < (int)giants.size() ? sc.lure : -1;
		// (Chapter 6: a grazer that has just eaten one up digests it first, as
		// a real protist does: the brake on eating the producers bare.)
		int cfood = S.diet == DIET_GRAZER && food < 0 && sc.cfood >= 0 && alive[sc.cfood] && join[sc.cfood] <= 0.0f && digest[i] <= 0.0f ? sc.cfood : -1;
		// Chemosynthetic cells "see food" when richer vent water lies nearby.
		float cgx = 0.0f, cgy = 0.0f;
		bool chem_near = false;
		if (S.diet == DIET_CHEMO) {
			cgx = chem[nutrient_index(x[i] + 16.0f, y[i])] - chem[nutrient_index(x[i] - 16.0f, y[i])];
			cgy = chem[nutrient_index(x[i], y[i] + 16.0f)] - chem[nutrient_index(x[i], y[i] - 16.0f)];
			chem_near = chem[nutrient_index(x[i], y[i])] < 0.95f && cgx * cgx + cgy * cgy > 1e-6f;
		} else if (S.diet == DIET_PHOTO) {
			// A producer "sees food" where brighter water lies nearby.
			cgx = light[nutrient_index(x[i] + 24.0f, y[i])] - light[nutrient_index(x[i] - 24.0f, y[i])];
			cgy = light[nutrient_index(x[i], y[i] + 24.0f)] - light[nutrient_index(x[i], y[i] - 24.0f)];
			chem_near = cgx * cgx + cgy * cgy > 1e-8f;
		}
		int carcass = S.diet == DIET_PREDATOR && sc.carcass >= 0 && sh_e[sc.carcass] > 0.0f ? sc.carcass : -1;
		hurt[i] = std::max(0.0f, hurt[i] - dt);
		sense[i] = (uint8_t)((food >= 0 || cfood >= 0 || chem_near || lure >= 0 ? S_ALGAE : 0) | (prey >= 0 ? S_PREY : 0) | (carcass >= 0 ? S_SHELL : 0) |
				(threat >= 0 ? S_THREAT : 0) | (hurt[i] > 0.0f ? S_ATTACKED : 0));
		threat_d[i] = threat >= 0 ? sc.threat_d : 1e9f;
		// Chapter 6 boss: the pseudopod net is felt as a danger close by (a
		// flee card runs from it as from a hunter).
		bool net_near = false;
		float ndx = 0.0f, ndy = 0.0f;
		if (net_on) {
			float best = 1e9f;
			if (net_at(x[i], y[i]) > 0.15f) {
				best = 0.0f;
			}
			for (int k = 0; k < 8; k++) {
				const float a = k * 0.785398f;
				for (float d : { 20.0f, 45.0f, 70.0f }) {
					if (d < best && net_at(x[i] + std::cos(a) * d, y[i] + std::sin(a) * d) > 0.15f) {
						best = d;
						ndx += std::cos(a);
						ndy += std::sin(a);
					}
				}
			}
			if (best < 1e8f) {
				net_near = true;
				if (ndx * ndx + ndy * ndy < 1e-4f) {
					ndx = net_x - x[i];
					ndy = net_y - y[i];
				}
				float nl = std::sqrt(ndx * ndx + ndy * ndy) + 1e-6f;
				ndx /= nl;
				ndy /= nl;
				if (best < threat_d[i]) {
					threat_d[i] = best;
					sense[i] |= S_THREAT;
				}
			}
		}
		crowd[i] = (uint8_t)std::min(flock, 255);

		// Run the deck: the first card whose conditions hold and whose action
		// can be done right now wins.
		int chosen = -1;
		uint8_t todo = A_WANDER;
		bool has_divide = false;
		int smell_which = -1; // a "signal + flee" card: which smell it runs from
		int follow_peer = -1; // a "peer in state X + follow" card: the peer it goes to
		st_time[i] += dt;
		for (int k = 0; k < ncards[i]; k++) {
			const Card &cd = cards[i * MAX_CARDS + k];
			has_divide = has_divide || cd.act == A_DIVIDE;
			// Only the cards of the state it is in are read.
			if (cd.st != state[i]) {
				continue;
			}
			// "信号 A/B 浓" with "逃离" on one card: an alarm. It runs from the
			// smell even with no hunter in sight (level 11: a warning that only
			// helped those who could already see the danger was no warning).
			bool sig0 = (cd.c[0] == C_SIGNAL_A || cd.c[0] == C_SIGNAL_B) && !(cd.neg & 1);
			bool sig1 = (cd.c[1] == C_SIGNAL_A || cd.c[1] == C_SIGNAL_B) && !(cd.neg & 2);
			bool smell_flee = cd.act == A_FLEE && !cd.any && (sig0 || sig1);
			// "看见处于 X 状态的同伴" with "跟随同伴": goes to that peer, however
			// far off in sight (plain following only gathers within 60 µm).
			int peer_to = -1;
			bool peer_card = false;
			if (cd.act == A_FOLLOW && !cd.any) {
				for (int m = 0; m < 2; m++) {
					if (cd.c[m] == C_PEER_STATE && !(cd.neg & (1 << m))) {
						peer_to = sc.peer[std::min(3, std::max(0, (int)cd.t[m]))];
						peer_card = true;
					}
				}
				// Close enough: it has joined them, and the next cards (feeding)
				// carry on beside them.
				if (peer_to >= 0 && (!alive[peer_to] || (x[peer_to] - x[i]) * (x[peer_to] - x[i]) + (y[peer_to] - y[i]) * (y[peer_to] - y[i]) < 35.0f * 35.0f)) {
					peer_to = -1;
				}
			}
			bool can = peer_card ? peer_to >= 0 : (act_possible(i, cd.act) || smell_flee);
			if (chosen < 0 && card_holds(i, cd) && can) {
				// Prey conditions hold for one prey together, and that is
				// the one this card hunts (an "且" card with them, not negated).
				bool about_prey = !cd.any && ((cd.c[0] == C_PREY_NEAR || cd.c[0] == C_PREY_SMALL) && !(cd.neg & 1) ||
						(cd.c[1] == C_PREY_NEAR || cd.c[1] == C_PREY_SMALL) && !(cd.neg & 2));
				int pick = about_prey ? pick_prey(i, cd) : prey;
				if (about_prey && pick < 0) {
					continue;
				}
				chosen = k;
				todo = cd.act;
				prey = pick;
				if (smell_flee) {
					smell_which = (sig0 ? cd.c[0] : cd.c[1]) == C_SIGNAL_B ? 1 : 0;
				}
				follow_peer = peer_to;
			}
		}
		fired[i] = (int8_t)chosen;

		float dirx = std::cos(wander[i]), diry = std::sin(wander[i]);
		float want = 0.45f;
		int act = ACT_WANDER;
		bool resting = false;
		bool divide_now = false;
		bool emitting = false;
		target[i] = 0;
		tgx[i] = x[i];
		tgy[i] = y[i];
		switch (todo) {
			case A_FLEE: {
				if (threat < 0 || (sense[i] & S_THREAT) == 0 || (net_near && threat_d[i] < sc.threat_d)) {
					// Running from an alarm: away from where it smells strongest
					// (right at its source, straight on); or from the net.
					float sdx, sdy;
					if (net_near) {
						dirx = -ndx;
						diry = -ndy;
						wander[i] = std::atan2(diry, dirx);
					} else if (smell_which >= 0 && signal_dir(i, smell_which, sdx, sdy)) {
						dirx = -sdx;
						diry = -sdy;
						wander[i] = std::atan2(diry, dirx);
					}
					want = 1.0f;
					act = ACT_FLEE;
					tgx[i] = x[i] + dirx * 60.0f;
					tgy[i] = y[i] + diry * 60.0f;
					break;
				}
				float dx = x[i] - x[threat], dy = y[i] - y[threat];
				float d = std::max(1e-3f, std::sqrt(dx * dx + dy * dy));
				dirx = dx / d;
				diry = dy / d;
				want = 1.0f;
				act = ACT_FLEE;
				target[i] = id[threat];
				tgx[i] = x[threat];
				tgy[i] = y[threat];
			} break;
			case A_HUNT: {
				float dx = x[prey] - x[i], dy = y[prey] - y[i];
				float d = std::max(1e-3f, std::sqrt(dx * dx + dy * dy));
				dirx = dx / d;
				diry = dy / d;
				want = 1.0f;
				act = ACT_HUNT;
				target[i] = id[prey];
				tgx[i] = x[prey];
				tgy[i] = y[prey];
			} break;
			case A_SEEK_ALGAE: {
				if (S.diet == DIET_CHEMO || S.diet == DIET_PHOTO) {
					// Up the chemical gradient, toward the vent (a producer: toward the light).
					float gl = std::sqrt(cgx * cgx + cgy * cgy) + 1e-6f;
					dirx = cgx / gl;
					diry = cgy / gl;
					wander[i] = std::atan2(diry, dirx);
					want = 0.5f;
					act = ACT_SEEK_FOOD;
					tgx[i] = x[i] + dirx * 50.0f;
					tgy[i] = y[i] + diry * 50.0f;
					break;
				}
				if (lure >= 0) {
					float lx = giants[lure].x - x[i], ly = giants[lure].y - y[i];
					float ld = std::max(1e-3f, std::sqrt(lx * lx + ly * ly));
					dirx = lx / ld;
					diry = ly / ld;
					want = 0.6f;
					act = ACT_SEEK_FOOD;
					wander[i] = std::atan2(ly, lx);
					tgx[i] = giants[lure].x;
					tgy[i] = giants[lure].y;
					break;
				}
				if (food < 0 && cfood >= 0) {
					// Chapter 6: a producer cell, grazed down where it floats.
					float dx = x[cfood] - x[i], dy = y[cfood] - y[i];
					float d = std::max(1e-3f, std::sqrt(dx * dx + dy * dy));
					float reach = body_r + species[sp[cfood]].extent + 4.0f;
					bool touching = d < reach;
					dirx = dx / d;
					diry = dy / d;
					want = touching ? 0.08f : clampf((d - reach) / 45.0f + 0.12f, 0.12f, 0.75f);
					act = touching ? ACT_GRAZE : ACT_SEEK_FOOD;
					wander[i] = std::atan2(dy, dx);
					target[i] = id[cfood];
					tgx[i] = x[cfood];
					tgy[i] = y[cfood];
					break;
				}
				float dx = al_x[food] - x[i], dy = al_y[food] - y[i];
				float d = std::max(1e-3f, std::sqrt(dx * dx + dy * dy));
				float reach = body_r + algae_radius(al_e[food]) + 5.0f;
				bool touching = d < reach;
				dirx = dx / d;
				diry = dy / d;
				// Arrive, don't overshoot: ease off as the clump gets close
				// (with momentum, a full-speed approach just circles it).
				want = touching ? 0.08f : clampf((d - reach) / 45.0f + 0.12f, 0.12f, 0.75f);
				act = touching ? ACT_GRAZE : ACT_SEEK_FOOD;
				wander[i] = std::atan2(dy, dx);
				tgx[i] = al_x[food];
				tgy[i] = al_y[food];
			} break;
			case A_SCAVENGE: {
				float dx = sh_x[carcass] - x[i], dy = sh_y[carcass] - y[i];
				float d = std::max(1e-3f, std::sqrt(dx * dx + dy * dy));
				dirx = dx / d;
				diry = dy / d;
				want = clampf((d - r - sh_r[carcass]) / 45.0f + 0.1f, 0.1f, 0.7f);
				act = ACT_SCAVENGE;
				tgx[i] = sh_x[carcass];
				tgy[i] = sh_y[carcass];
			} break;
			case A_FOLLOW: {
				if (follow_peer >= 0) {
					float dx = x[follow_peer] - x[i], dy = y[follow_peer] - y[i];
					float d = std::max(1e-3f, std::sqrt(dx * dx + dy * dy));
					dirx = dx / d;
					diry = dy / d;
					want = clampf(d / 50.0f, 0.2f, 0.9f);
					act = ACT_FOLLOW;
					tgx[i] = x[follow_peer];
					tgy[i] = y[follow_peer];
					break;
				}
				float d = std::sqrt(fx * fx + fy * fy) + 1e-3f;
				dirx = fx / d;
				diry = fy / d;
				want = clampf(d / flock / 40.0f, 0.15f, 0.6f);
				act = ACT_FOLLOW;
				tgx[i] = x[i] + fx / flock;
				tgy[i] = y[i] + fy / flock;
			} break;
			case A_INDUCE:
				wake_phage(i, true);
				want = 0.2f;
				break;
			case A_AGGREGATE:
				join_slug(i);
				want = 0.2f;
				act = ACT_SLUG;
				break;
			case A_DISPERSE: {
				float d = std::sqrt(fx * fx + fy * fy) + 1e-3f;
				dirx = -fx / d;
				diry = -fy / d;
				want = 0.8f;
				act = ACT_DISPERSE;
				tgx[i] = x[i] - fx / flock;
				tgy[i] = y[i] - fy / flock;
			} break;
			case A_REST:
				want = 0.2f;
				act = ACT_REST;
				resting = true;
				break;
			case A_DIVIDE:
				want = 0.15f;
				divide_now = true;
				break;
			case A_EMIT_A:
			case A_EMIT_B:
			case A_SECRETE: {
				int c = nutrient_index(x[i], y[i]);
				if (todo == A_SECRETE) {
					enzyme[c] += ENZ_EMIT * dt;
					// A secreting cell keeps calling too (quorum sensing feeds on itself),
					// so a group that has started doesn't fall silent and stop.
					sig_a[c] += SIGNAL_EMIT * 0.5f * dt;
					energy[i] -= (SECRETE_COST - SIGNAL_COST) * dt; // (the rest is the emitting upkeep)
				} else {
					(todo == A_EMIT_A ? sig_a : sig_b)[c] += SIGNAL_EMIT * dt;
				}
				emitting = true;
				want = 0.3f;
				act = ACT_SIGNAL;
				// A hunter calling the pack: it chases its prey as it calls
				// (level 14: wolf bacteria bring the others to a kill).
				if (S.diet == DIET_PREDATOR && prey >= 0 && alive[prey]) {
					float dx = x[prey] - x[i], dy = y[prey] - y[i];
					float d = std::max(1e-3f, std::sqrt(dx * dx + dy * dy));
					dirx = dx / d;
					diry = dy / d;
					want = 1.0f;
					act = ACT_HUNT;
					target[i] = id[prey];
					tgx[i] = x[prey];
					tgy[i] = y[prey];
				}
				// Calling on the run: with a hunter in sight it flees as it calls
				// (an alarm that cost the escape was never worth making).
				else if ((sense[i] & S_THREAT) != 0 && threat >= 0) {
					float dx = x[i] - x[threat], dy = y[i] - y[threat];
					float d = std::max(1e-3f, std::sqrt(dx * dx + dy * dy));
					dirx = dx / d;
					diry = dy / d;
					want = 1.0f;
					act = ACT_FLEE;
					target[i] = id[threat];
					tgx[i] = x[threat];
					tgy[i] = y[threat];
				}
				// Calling with its mouth full: a grazer with food in sight keeps
				// going to it and eating at the full rate while it calls (level
				// 11: a call that cost the meal was never worth making).
				else if (food >= 0 && S.diet != DIET_CHEMO) {
					float dx = al_x[food] - x[i], dy = al_y[food] - y[i];
					float d = std::max(1e-3f, std::sqrt(dx * dx + dy * dy));
					float reach = r + algae_radius(al_e[food]) + 5.0f;
					bool touching = d < reach;
					dirx = dx / d;
					diry = dy / d;
					want = touching ? 0.08f : clampf((d - reach) / 45.0f + 0.12f, 0.12f, 0.75f);
					act = touching ? ACT_GRAZE : ACT_SIGNAL;
					wander[i] = std::atan2(dy, dx);
					tgx[i] = al_x[food];
					tgy[i] = al_y[food];
				}
			} break;
			case A_SEEK_COMFORT: {
				// Toward the water in sight nearest its optimum.
				float cdx, cdy;
				if (comfort_dir(i, cdx, cdy)) {
					dirx = cdx;
					diry = cdy;
					wander[i] = std::atan2(diry, dirx);
				}
				want = 0.8f;
				act = ACT_COMFORT;
				tgx[i] = x[i] + dirx * 60.0f;
				tgy[i] = y[i] + diry * 60.0f;
			} break;
			case A_SEEK_SIG_A:
			case A_SEEK_SIG_B: {
				// Up the trail, toward where the smell is strongest.
				float sdx, sdy;
				if (signal_dir(i, todo - A_SEEK_SIG_A, sdx, sdy)) {
					dirx = sdx;
					diry = sdy;
					wander[i] = std::atan2(diry, dirx);
				}
				want = 0.9f;
				act = ACT_TRACK;
				tgx[i] = x[i] + dirx * 60.0f;
				tgy[i] = y[i] + diry * 60.0f;
			} break;
			case A_AVOID_O2:
			case A_SEEK_O2: {
				// Away from oxygen (into the anoxic water), or toward it.
				float odx, ody;
				if (o2_dir(i, todo == A_SEEK_O2, odx, ody)) {
					dirx = odx;
					diry = ody;
					wander[i] = std::atan2(diry, dirx);
				}
				want = 0.85f;
				act = ACT_AIR;
				tgx[i] = x[i] + dirx * 60.0f;
				tgy[i] = y[i] + diry * 60.0f;
			} break;
			case A_TO_FORAGE:
			case A_TO_ALERT:
			case A_TO_BREED:
			case A_TO_SLEEP:
				// Switching takes the tick; the new state's cards run next.
				state[i] = (uint8_t)(todo - A_TO_FORAGE);
				st_time[i] = 0.0f;
				want = 0.2f;
				break;
			default:
				// Nothing to do: cruise further and straighter while hungry.
				want = energy[i] < divide_at ? 0.7f : 0.45f;
				break;
		}
		// State physiology (DECISIONS 第十二轮 Q22): asleep it barely moves.
		if (state[i] == S_SLEEP) {
			want = std::min(want, 0.12f);
		}
		// No division card at all: divide whenever full (older behaviour).
		if (!has_divide && energy[i] > divide_at) {
			divide_now = true;
		}
		// A colony's flagella never stop. The cards ask for a speed over the
		// ground and it points itself so the stream leaves it that; with
		// nothing to do, it heads up the stream.
		if (S.colony) {
			float sl = std::sqrt(stream_x * stream_x + stream_y * stream_y);
			bool going = act == ACT_SEEK_FOOD || act == ACT_GRAZE || act == ACT_FLEE || sl < 0.01f;
			float ux = going ? dirx * want * max_speed : -stream_x / std::max(sl, 0.01f) * max_speed * 0.8f;
			float uy = going ? diry * want * max_speed : -stream_y / std::max(sl, 0.01f) * max_speed * 0.8f;
			float ax = ux - stream_x, ay = uy - stream_y;
			float al = std::sqrt(ax * ax + ay * ay) + 1e-5f;
			dirx = ax / al;
			diry = ay / al;
			want = std::min(1.0f, al / std::max(max_speed, 0.1f));
		}
		const bool hungry_wander = act == ACT_WANDER && energy[i] < divide_at;
		if (flock > 0 && S.cohesion > 0.0f && act != ACT_FLEE) {
			float d = std::sqrt(fx * fx + fy * fy) + 1e-3f;
			dirx += fx / d * S.cohesion;
			diry += fy / d * S.cohesion;
		}
		wander[i] += gauss() * (hungry_wander ? 0.4f : 0.9f) * dt;
		float dl = std::sqrt(dirx * dirx + diry * diry) + 1e-5f;
		// Algae thickets are a refuge: big bodies push through them slowly,
		// small grazers slip between the clumps.
		float thicket = 1.0f;
		if (r > 8.0f && !S.colony) {
			int clumps = 0;
			int tc = (int)clampf(x[i] / acell, 0.0f, (float)(agw - 1)), tr = (int)clampf(y[i] / acell, 0.0f, (float)(agh - 1));
			for (int a = lhead[tr * agw + tc]; a >= 0; a = lnext[a]) {
				float dx = al_x[a] - x[i], dy = al_y[a] - y[i];
				if (dx * dx + dy * dy < (r + 14.0f) * (r + 14.0f)) {
					clumps++;
				}
			}
			thicket = std::max(0.5f, 1.0f / (1.0f + 0.13f * clumps));
		}
		want *= thicket;
		if (inf_t[i] >= PHAGE_INJECT && doomed(i)) {
			want *= 0.5f; // its machinery has gone over to making phages
		}
		// Gentle surges only: a strong push/coast cycle read as stuttering.
		float stroke;
		if (multicell) {
			stroke = 1.0f + 0.1f * std::sin((float)sim_time * 2.2f + phase[i]);
		} else {
			// Each stroke of the cilia / tail is a surge forward; the faster
			// it swims, the quicker the strokes.
			float sf = clampf(std::sqrt(vx[i] * vx[i] + vy[i] * vy[i]) / max_speed, 0.0f, 1.0f);
			sw[i] += dt * (3.0f + 7.0f * sf);
			vs[i] += (sf - vs[i]) * std::min(1.0f, dt * 2.5f);
			stroke = S.colony ? 1.0f : 1.0f + 0.3f * std::sin(sw[i]);
		}
		float tx, ty;
		if (multicell) {
			tx = dirx / dl * max_speed * want * stroke;
			ty = diry / dl * max_speed * want * stroke;
		} else {
			// A single cell steers like a swimmer: its cilia / tail turn the
			// body (a torque toward the goal, limited, damped by the water,
			// so turning has inertia), and it pushes along its own axis,
			// easing off while it is still coming round.
			float err = want > 0.05f ? std::remainder(std::atan2(diry, dirx) - heading[i], TAU) : 0.0f;
			float wmax = S.colony ? S.col_turn : (1.6f + 0.7f * t_speed[i]) * S.turn_mult;
			float wgoal = clampf(err * 3.0f, -wmax, wmax);
			angv[i] += (wgoal - angv[i]) * std::min(1.0f, dt * 4.0f);
			heading[i] = std::remainder(heading[i] + angv[i] * dt, TAU);
			float thrust = max_speed * want * stroke * (0.35f + 0.65f * std::max(0.0f, std::cos(err)));
			tx = std::cos(heading[i]) * thrust;
			ty = std::sin(heading[i]) * thrust;
		}
		// Low steering gain = momentum: organisms drift on between strokes.
		float steer = std::min(1.0f, dt * (multicell ? 1.1f : 2.4f));
		vx[i] += (tx - vx[i]) * steer;
		vy[i] += (ty - vy[i]) * steer;
		float spd = std::sqrt(vx[i] * vx[i] + vy[i] * vy[i]);
		if (multicell && spd > 2.0f) {
			heading[i] = angle_lerp(heading[i], std::atan2(vy[i], vx[i]), std::min(1.0f, dt * 6.0f));
		}
		// The body bends into turns smoothly, not tick by tick.
		float turn_rate = std::remainder(heading[i] - pheading[i], TAU) / std::max(dt, 1e-4f);
		curl[i] += (turn_rate - curl[i]) * std::min(1.0f, dt * 3.0f);
		// The water carries everything along (small cells more than big bodies).
		int fc = nutrient_index(x[i], y[i]);
		float carry = clampf(6.0f / r, 0.25f, 1.0f);
		float jx = 0.0f, jy = 0.0f;
		for (const Jet &jt : jets) {
			float dx = x[i] - jt.x, dy = y[i] - jt.y;
			float w = std::exp(-(dx * dx + dy * dy) / (jt.r * jt.r)) * spot_fade(jt.life, jt.ttl);
			jx += jt.vx * w;
			jy += jt.vy * w;
		}
		// (Level 24: a player's current takes a body along at its full
		// strength, so bodies can be steered.)
		float jcarry = S.colony && col_jet > 0.0f ? col_jet : carry;
		float nx0 = x[i] + (vx[i] + flow_u[fc] * carry + jx * jcarry + (S.colony ? stream_x : 0.0f)) * dt + sx * 0.5f;
		float ny0 = y[i] + (vy[i] + flow_v[fc] * carry + jy * jcarry + (S.colony ? stream_y : 0.0f)) * dt + sy * 0.5f;
		x[i] = nx0;
		y[i] = ny0;
		keep_in_dish(x[i], y[i], S.extent);
		if (x[i] != nx0 || y[i] != ny0) {
			// Hit the glass: bounce off and turn back inward.
			float nx = x[i] - (dish_r > 0.0f ? dish_x : world_w * 0.5f), ny = y[i] - (dish_r > 0.0f ? dish_y : world_h * 0.5f);
			float nl = std::sqrt(nx * nx + ny * ny) + 1e-3f;
			nx /= nl;
			ny /= nl;
			float vn = vx[i] * nx + vy[i] * ny;
			if (vn > 0.0f) {
				vx[i] -= 2.0f * vn * nx;
				vy[i] -= 2.0f * vn * ny;
			}
			wander[i] = std::atan2(-ny, -nx) + gauss() * 0.6f;
		}

		// Chapter 6: what a meal is worth depends on how it breathes and the
		// oxygen here (1 everywhere oxygen means nothing).
		const float rmul = resp_gain(i);
		// Chemosynthesis: the vent's chemistry, shared among neighbours.
		if (S.diet == DIET_CHEMO) {
			float gain = CHEMO_RATE * chem[nutrient_index(x[i], y[i])] * S.size_factor / (1.0f + 0.1f * flock) * dt;
			energy[i] += gain;
			energy_in += gain;
		}
		// Photosynthesis (光合膜): light, shared with its neighbours (they shade
		// one another); oxygen goes into the water as it works.
		if (S.diet == DIET_PHOTO) {
			int lc = nutrient_index(x[i], y[i]);
			float gain = PHOTO_RATE * light[lc] * S.size_factor / (1.0f + 0.04f * flock) * dt;
			energy[i] += gain;
			energy_in += gain;
			if (o2_on) {
				o2[lc] += gain * o2_emit;
				o2_made += gain * o2_emit;
			}
		}
		// A boss engulfs every smaller cell its body touches, whatever it is
		// doing (a crowd in its path goes in all at once).
		if (S.engulf > 0.0f) {
			for (int j = 0; j < count; j++) {
				// (A colony is bitten block by block instead: bite_colony.)
				if (!alive[j] || sp[j] == sp[i] || species[sp[j]].radius > r * 0.9f || species[sp[j]].colony) {
					continue;
				}
				float dx = x[j] - x[i], dy = y[j] - y[i];
				float touch = S.extent + species[sp[j]].extent;
				if (dx * dx + dy * dy < touch * touch) {
					float rest = std::max(0.0f, energy[j]) + body_energy(sp[j]);
					energy[i] += rest * EAT_PREY_EFF * rmul;
					energy_in += rest * EAT_PREY_EFF * (rmul - 1.0f);
					energy_out += rest * (1.0f - EAT_PREY_EFF);
					energy[j] = 0.0f;
					kill(j, CAUSE_EATEN);
				}
			}
		}
		// Chapter 6: grazing a producer cell (it is eaten down, then dies).
		if (act == ACT_GRAZE && food < 0 && cfood >= 0 && alive[cfood]) {
			float take = std::min(std::max(0.0f, energy[cfood]), cell_graze * (r / 6.0f) * dt);
			energy[cfood] -= take;
			hurt[cfood] = 2.0f;
			energy[i] += take * EAT_ALGAE_EFF * rmul;
			energy_in += take * EAT_ALGAE_EFF * (rmul - 1.0f);
			energy_out += take * (1.0f - EAT_ALGAE_EFF);
			if (energy[cfood] <= 0.5f) {
				float rest = std::max(0.0f, energy[cfood]) + body_energy(sp[cfood]);
				energy[i] += rest * EAT_ALGAE_EFF * rmul;
				energy_in += rest * EAT_ALGAE_EFF * (rmul - 1.0f);
				energy_out += rest * (1.0f - EAT_ALGAE_EFF);
				energy[cfood] = 0.0f;
				kill(cfood, CAUSE_EATEN);
				digest[i] = graze_rest;
			}
			if (randf() < 1.2f * dt) {
				emit(EV_GRAZE, x[cfood], y[cfood], sp[i], x[i], y[i]);
			}
		}
		// Feeding.
		bool touching_food = false;
		if (food >= 0 && act != ACT_GRAZE && act != ACT_FLEE && act != ACT_HUNT) {
			// Food under its nose is eaten automatically (more slowly).
			float dx = al_x[food] - x[i], dy = al_y[food] - y[i];
			float reach = body_r + algae_radius(al_e[food]) + 3.0f;
			touching_food = dx * dx + dy * dy < reach * reach;
		}
		if ((act == ACT_GRAZE || touching_food) && food >= 0) {
			// Small clumps are slow to graze, so a patch is rarely eaten bare.
			float rate = act == ACT_GRAZE ? 1.0f : 0.5f;
			float take = std::min(al_e[food], rate * 9.0f * (r / 6.0f) * S.col_bite * dt * clampf(al_e[food] / (ALGAE_MAX_E * 0.4f), 0.15f, 1.0f));
			al_e[food] -= take;
			// Tough algae: only what the enzyme in the water unlocks is gained.
			// (A colony narrower than the clump only catches part of it.)
			float eff = EAT_ALGAE_EFF * S.col_keep;
			if (algae_tough > 0.0f) {
				eff *= (1.0f - algae_tough) + algae_tough * clampf((enzyme[nutrient_index(x[i], y[i])] - ENZ_MIN) / (ENZ_FULL - ENZ_MIN), 0.0f, 1.0f);
			}
			energy[i] += take * eff * rmul;
			energy_in += take * eff * (rmul - 1.0f);
			energy_out += take * (1.0f - eff);
			if (act == ACT_GRAZE) {
				target[i] = -1 - food;
			}
			if (randf() < 1.2f * dt) {
				emit(EV_GRAZE, al_x[food], al_y[food], sp[i], x[i], y[i]);
			}
		} else if (act == ACT_SCAVENGE && carcass >= 0) {
			float dx = sh_x[carcass] - x[i], dy = sh_y[carcass] - y[i];
			float reach = r + sh_r[carcass] + 4.0f;
			if (dx * dx + dy * dy < reach * reach) {
				float take = std::min(sh_e[carcass], 12.0f * dt);
				sh_e[carcass] -= take;
				// Teeth or gut: the weaker the attack, the more a shell yields.
				float eff = EAT_SHELL_EFF + 0.3f * clampf((3.2f - t_attack[i]) / 1.6f, 0.0f, 1.0f);
				energy[i] += take * eff * rmul;
				energy_in += take * eff * (rmul - 1.0f);
				energy_out += take * (1.0f - eff);
			}
		} else if (act == ACT_HUNT && prey >= 0 && alive[prey]) {
			float dx = x[prey] - x[i], dy = y[prey] - y[i];
			float touch = std::max(S.extent, ha[i]) + std::max(species[sp[prey]].extent, ha[prey]) + 2.0f;
			if (dx * dx + dy * dy < touch * touch && species[sp[prey]].colony && S.rotifer) {
				// (A rotifer swallows whole: step_rotifers.)
			} else if (dx * dx + dy * dy < touch * touch && species[sp[prey]].colony) {
				// Level 22: a mouthful off the rim, then a pause to swallow it.
				if (bite_colony(i, prey)) {
					act = ACT_BITE;
				}
			} else if (dx * dx + dy * dy < touch * touch) {
				act = ACT_BITE;
				latch[i] += dt;
				// Confusion effect: prey in a crowd is harder to pin down.
				// Interference: hunters crowding the same spot get in each
				// other's way (keeps predator booms in check).
				float confusion = 1.0f / (1.0f + 0.12f * S.confuse * crowd[prey]);
				confusion /= 1.0f + 0.35f * flock;
				const Species &PS = species[sp[prey]];
				float bite = 30.0f * t_attack[i] / (1.0f + 0.6f * t_armor[prey]) * (r / 9.0f) * confusion * dt * PS.bite_taken;
				float take = std::min(std::max(0.0f, energy[prey]), bite);
				if (PS.spines > 0.0f) {
					// Spines: the hunter pays for every bite, and feels it.
					energy[i] -= SPINE_HURT * PS.spines * 30.0f * t_attack[i] * (r / 9.0f) * dt;
					hurt[i] = 2.0f;
				}
				energy[prey] -= take;
				bitten[prey] = 1;
				hurt[prey] = 2.0f;
				if (randf() < 3.0f * dt) {
					emit(EV_BITE, x[prey], y[prey], sp[prey], x[i], y[i]);
				}
				energy[i] += take * EAT_PREY_EFF * rmul;
				energy_in += take * EAT_PREY_EFF * (rmul - 1.0f);
				energy_out += take * (1.0f - EAT_PREY_EFF);
				if (energy[prey] <= 0.5f) {
					// Swallowed whole: the body goes to the predator, no shell.
					float rest = std::max(0.0f, energy[prey]) + body_energy(sp[prey]);
					energy[i] += rest * EAT_PREY_EFF * rmul;
					energy_in += rest * EAT_PREY_EFF * (rmul - 1.0f);
					energy_out += rest * (1.0f - EAT_PREY_EFF);
					energy[prey] = 0.0f;
					// The prey goes in whole and is digested where it can be seen.
					float ch = std::cos(heading[i]), sh = std::sin(heading[i]);
					gulp_t[i] = 0.0f;
					gulp_sp[i] = sp[prey];
					gulp_lin[i] = lineage[prey];
					gulp_r[i] = species[sp[prey]].radius;
					gulp_lx[i] = dx * ch + dy * sh;
					gulp_ly[i] = -dx * sh + dy * ch;
					gulp_h[i] = std::remainder(heading[prey] - heading[i], TAU);
					gulp_ph[i] = phase[prey];
					kill(prey, CAUSE_EATEN);
					digest[i] = S.digest_time;
				}
			}
		}

		// Metabolism.
		float size = r / 6.0f;
		float base = 0.45f * S.size_factor * (1.3f - 0.09f * t_efficiency[i]) * (1.0f - 0.2f * S.store);
		// State costs: asleep very little; alert and breeding run hot.
		static const float STATE_BASE[4] = { 1.0f, 1.4f, 1.3f, 0.1f };
		base *= STATE_BASE[state[i]] * S.burn;
		float sv = spd / 50.0f;
		float move = 0.32f * sv * sv * size * S.move_cost;
		// A bigger brain costs more to run (level 3 is the baseline).
		float upkeep = 0.05f * t_vision[i] + 0.08f * t_attack[i] + 0.06f * t_armor[i] + 0.03f * (t_neural[i] - 3.0f)
				+ TOL_UPKEEP * (t_ttol[i] - 2.5f) + (emitting ? SIGNAL_COST : 0.0f);
		if (resting) {
			base *= 0.6f * S.rest_cost; // cilia hold still for less
		}
		// The water: heat or cold outside its band, and acid (armour helps).
		int ec = nutrient_index(x[i], y[i]);
		float dev = std::max(0.0f, std::abs(temp[ec] - t_topt[i]) - band_for(t_ttol[i]));
		float st = (TEMP_COST * dev + (dev > TEMP_SEVERE ? TEMP_HURT * (dev - TEMP_SEVERE) : 0.0f)) * S.size_factor;
		float sa = acid[ec] * ACID_COST * S.size_factor / (1.0f + 0.35f * t_armor[i]);
		// Chapter 6: oxygen above the threshold poisons an anaerobe, the more
		// the thicker it is (a facultative one only if the level says so).
		float so = 0.0f;
		if (o2_on && S.diet != DIET_PHOTO && (S.resp == 1 || (S.resp == 3 && fac_harm > 0.0f))) {
			so = std::max(0.0f, o2[ec] - o2_tox) * o2_harm * S.size_factor * (S.resp == 3 ? fac_harm : 1.0f);
		}
		// Chapter 6 boss: in the net it is being digested.
		float sn = net_on ? net_drain * net_at(x[i], y[i]) * S.size_factor : 0.0f;
		stress_t[i] = st;
		stress_a[i] = sa + so;
		float own = std::max(0.0f, base + move + upkeep);
		float cost = std::min(energy[i], (own + st + sa + so + sn) * dt);
		{
			Species &W = species[sp[i]];
			float k = cost / std::max(1e-6f, (own + st + sa + so + sn) * dt);
			W.burn_total += cost;
			W.burn_temp += st * dt * k;
			W.burn_acid += sa * dt * k;
			W.burn_o2 += so * dt * k;
			net_fed += sn * dt * k;
		}
		energy[i] -= cost;
		energy_out += cost;
		// Aerobic breathing takes oxygen from the water in step with its burn.
		if (o2_on && S.diet != DIET_PHOTO && (S.resp == 2 || S.resp == 3)) {
			float use = std::min(o2[ec], own * dt * o2_use);
			o2[ec] -= use;
			o2_breathed += use;
		}
		// Dormancy slows the clock as well as the metabolism: a lurking
		// hunter can outlast a lean spell instead of ageing out in it.
		age[i] += state[i] == S_SLEEP ? dt * 0.25f : (resting ? dt * 0.5f : dt);
		cooldown[i] -= dt;
		digest[i] -= dt;
		if (act != ACT_BITE) {
			latch[i] = 0.0f;
		}
		if (gulp_t[i] >= 0.0f) {
			gulp_t[i] += dt;
			if (gulp_t[i] >= DIGEST_TIME) {
				gulp_t[i] = -1.0f;
			}
		}

		// Level 22: store blocks bank what is left over while the embryos grow
		// (or the body waits to start them) and pay it back when it runs low.
		if (S.colony && S.col_store > 0) {
			float cap = S.col_store * col_store_e;
			if ((gest[i] >= 0.0f || cooldown[i] > 0.0f) && energy[i] > S.col_e && store[i] < cap) {
				float put = std::min(std::min(energy[i] - S.col_e, cap - store[i]), 10.0f * dt);
				energy[i] -= put;
				store[i] += put;
			}
			float low = 0.3f * S.col_e;
			if (energy[i] < low && store[i] > 0.0f) {
				float get = std::min(std::min(low - energy[i], store[i]), 15.0f * dt);
				energy[i] += get;
				store[i] -= get;
			}
		}
		if (S.colony) {
			for (int k = 0; k < COL_MAXB; k++) {
				float &mk = cmark[i * COL_MAXB + k];
				mk = std::max(0.0f, mk - dt / 8.0f);
			}
			// Level 23: what was bitten grows back, every block by itself, four
			// times as fast beside a working regeneration block; it costs.
			if (col_hurt > 0.0f) {
				int m = (int)(S.body.size() / 3);
				bool any = false;
				int slow = 0;
				for (int b = 0; b < m; b++) {
					float &d = cdmg[i * COL_MAXB + b];
					if (d <= 0.0f) {
						continue;
					}
					float rate = 1.0f / col_regrow;
					bool helped = false;
					if (col_regen_all) {
						for (int q = 0; q < m; q++) {
							if (S.col_kind[q] == 5 && !cbroken[i * COL_MAXB + q]) {
								rate *= col_regen;
								helped = true;
								break;
							}
						}
					}
					for (int q = 0; q < 4 && !helped; q++) {
						int nb = S.col_nb[b * 4 + q];
						if (nb >= 0 && S.col_kind[nb] == 5 && !cbroken[i * COL_MAXB + nb]) {
							rate *= col_regen;
							helped = true;
							break;
						}
					}
					float grow = std::min(d, rate * dt);
					if (cbroken[i * COL_MAXB + b]) {
						// An open wound costs while it lasts (a piece broken off is
						// growing a body, not bleeding).
						float leak = cpiece[i] ? 0.0f : std::min(std::max(0.0f, energy[i]), col_bleed * dt);
						energy[i] -= leak;
						energy_out += leak;
						if (energy[i] < grow * col_regrow_e) {
							continue; // (too hungry to rebuild)
						}
						energy[i] -= grow * col_regrow_e;
						energy_out += grow * col_regrow_e;
					}
					d -= grow;
					if (d <= 0.0f) {
						d = 0.0f;
						col_healed += cbroken[i * COL_MAXB + b] && helped ? 1 : 0;
						cbroken[i * COL_MAXB + b] = 0;
					}
					any = any || cbroken[i * COL_MAXB + b];
				}
				for (int b = 0; b < m; b++) {
					slow += cbroken[i * COL_MAXB + b] && S.col_kind[b] == 0 && S.col_rim[b] != 0 ? 1 : 0;
				}
				cslow[i] = S.col_rimflags > 0 ? (float)slow / (float)S.col_rimflags : 0.0f;
				if (cpiece[i] && !any) {
					cpiece[i] = 0;
					col_whole++;
				}
			}
		}
		if (energy[i] <= 0.01f) {
			// The water killed it when heat, cold or acid took a third or more
			// of what it was burning.
			int cause = CAUSE_STARVE;
			if (st + sa + so > 0.5f * own) {
				cause = so >= st && so >= sa ? CAUSE_O2 : (st >= sa ? CAUSE_TEMP : CAUSE_ACID);
			}
			if (sn > 0.0f && sn >= st + sa + so && sn > 0.3f * own) {
				cause = CAUSE_EATEN; // (taken in by the net)
				net_caught++;
			}
			kill(i, cause);
			continue;
		}
		if (age[i] > S.lifespan * (0.85f + 0.06f * t_efficiency[i])) {
			kill(i, CAUSE_AGE);
			continue;
		}

		// A colony: "divide" starts the embryos in its germ blocks. It swims on
		// with them; when they are ready they break out and the body dies.
		if (S.colony) {
			if (gest[i] < 0.0f && divide_now && energy[i] >= divide_at && cooldown[i] <= 0.0f && !S.col_germ.empty()) {
				gest[i] = 0.0f;
				gwait[i] = 0.0f;
				for (int k = 0; k < COL_GERMS; k++) {
					emb[i * COL_GERMS + k] = 0.0f;
				}
				act = ACT_DIVIDE;
			}
			if (gest[i] >= 0.0f) {
				gest[i] += dt;
				int ng = (int)S.col_germ.size(), ready = 0;
				for (int k = 0; k < ng; k++) {
					float &e = emb[i * COL_GERMS + k];
					if (!cbroken[i * COL_MAXB + S.col_germ[k]]) {
						e = std::min(1.0f, e + dt / col_gest);
					}
					ready += e >= 1.0f ? 1 : 0;
				}
				gwait[i] += ready > 0 ? dt : 0.0f;
				// (The first one ready waits a little for the others, not for ever.)
				if (ready == ng || gwait[i] >= col_wait) {
					hatch(i);
					continue;
				}
			}
			action[i] = (uint8_t)act;
			continue;
		}
		// Division: the child's body is built first, then the remaining energy
		// is split and a tenth is lost to the effort.
		if (divide_now && energy[i] > child_body + r * r * 0.8f && cooldown[i] <= 0.0f && count < MAX_AGENTS) {
			// Bud off just beside the parent's body, not inside it.
			float ba = heading[i] + PI_F * 0.5f * (randf() < 0.5f ? 1.0f : -1.0f) + rand_range(-0.4f, 0.4f);
			float bd = S.half_len > 0.0f ? S.half_wid + S.extent + 4.0f : rand_range(0.0f, r);
			mutated_now = false;
			bool scene = S.body.empty() && pair[i] < 0;
			int c = scene ? spawn_one(sp[i], x[i], y[i], i) : spawn_one(sp[i], x[i] + std::cos(ba) * bd, y[i] + std::sin(ba) * bd, i);
			if (c >= 0) {
				if (scene) {
					join[c] = JOIN_TIME;
					join_mut[c] = mutated_now ? 1 : 0;
					pair[c] = i;
					pair[i] = c;
					age[c] = 0.9f; // full grown when it steps out
				} else {
					emit(mutated_now ? EV_MUTATION : EV_BIRTH, x[c], y[c], sp[i], x[i], y[i]);
				}
				// High fertility breeds often but sends the child off lean.
				float e = energy[i] - child_body;
				float lean = clampf(FERT_LEAN * (t_fertility[i] - 2.0f), -0.05f, 0.18f);
				energy[c] = e * (0.45f - lean);
				energy[i] = e * 0.45f;
				energy_out += e * (0.10f + lean);
				cooldown[i] = clampf(11.0f - 1.3f * t_fertility[i], 3.0f, 12.0f) * (state[i] == S_BREED ? 0.5f : 1.0f);
				species[sp[i]].births++;
				act = ACT_DIVIDE;
				tgx[i] = x[c];
				tgy[i] = y[c];
			}
		}
		action[i] = (uint8_t)act;
	}
	auto t3c = clk::now();
	relax_contacts(n);
	enforce_barriers();
	step_phages(dt);
	step_giants(dt);
	step_slugs(dt);
	step_colonies(dt);
	step_rotifers(dt);
	auto t3d = clk::now();
	compact();
	auto t4 = clk::now();
	auto us = [](auto a, auto b) { return std::chrono::duration<double, std::micro>(b - a).count(); };
	prof[0] += us(t0, t1);
	prof[1] += us(t1, t2);
	prof[2] += us(t2, t3) + us(t3, t3b);
	prof[3] += us(t3b, t3c) + us(t3d, t4);
	prof[4] += us(t3c, t3d);
	prof_n++;
}

Dictionary SimCore::get_profile() {
	// Mean microseconds per tick for each phase since the last call.
	Dictionary d;
	double n = std::max(prof_n, 1);
	d["water"] = prof[0] / n;
	d["algae_shells"] = prof[1] / n;
	d["grids_scan"] = prof[2] / n;
	d["organisms"] = prof[3] / n;
	d["contacts"] = prof[4] / n;
	d["contact_pairs"] = prof_pairs / n;
	d["contact_iters"] = prof_iters / n;
	prof_pairs = prof_iters = 0.0;
	prof[0] = prof[1] = prof[2] = prof[3] = prof[4] = 0.0;
	prof_n = 0;
	return d;
}

// --- colonies (level 21) -----------------------------------------------------

void SimCore::set_colony(Dictionary d) {
	Vector2 st = d.get("stream", Vector2());
	stream_x = st.x;
	stream_y = st.y;
	grit_speed = d.get("grit_speed", grit_speed);
	col_gest = d.get("gest", col_gest);
	col_wait = d.get("wait", col_wait);
	col_child = d.get("child", col_child);
	col_store_e = d.get("store_e", col_store_e);
	col_armor = d.get("armor", col_armor);
	col_bite_e = d.get("bite_e", col_bite_e);
	col_bite_gap = d.get("bite_gap", col_bite_gap);
	col_hurt = d.get("hurt", 0.0f);
	col_crack = d.get("crack", col_crack);
	col_regrow = d.get("regrow", col_regrow);
	col_regen = d.get("regen", col_regen);
	col_regen_all = d.get("regen_all", col_regen_all);
	col_dig = d.get("dig", col_dig);
	col_depth = d.get("depth", col_depth);
	col_regrow_e = d.get("regrow_e", col_regrow_e);
	col_bleed = d.get("bleed", 0.0f);
	col_jet = d.get("jet", 0.0f);
	grits.assign((int)d.get("grit", 0), Grit());
	for (Grit &g : grits) {
		respawn_grit(g, true);
	}
}

// Grit comes in on the upstream rim of the dish (or anywhere, at the start).
void SimCore::respawn_grit(Grit &g, bool anywhere) {
	float sl = std::sqrt(stream_x * stream_x + stream_y * stream_y) + 1e-5f;
	float ux = stream_x / sl, uy = stream_y / sl;
	float t = rand_range(-0.96f, 0.96f);
	float along = anywhere ? rand_range(-1.0f, 1.0f) : -1.0f;
	float h = std::sqrt(1.0f - t * t) * along * dish_r;
	g.x = g.px = dish_x + ux * h - uy * t * dish_r;
	g.y = g.py = dish_y + uy * h + ux * t * dish_r;
	float sp_mul = grit_speed * rand_range(0.85f, 1.15f);
	g.vx = stream_x * sp_mul;
	g.vy = stream_y * sp_mul;
	g.ph = rand_range(0.0f, 100.0f);
}

void SimCore::hatch(int i) {
	const Species &S = species[sp[i]];
	const int s = sp[i];
	float ch = std::cos(heading[i]), sh = std::sin(heading[i]);
	float share = std::max(0.0f, energy[i]) * col_child / (float)S.col_germ.size();
	float kept = store[i] / (float)S.col_germ.size(); // (the young carry the stores on)
	col_hatched++;
	for (int k = 0; k < (int)S.col_germ.size(); k++) {
		if (emb[i * COL_GERMS + k] < 1.0f) {
			continue;
		}
		int b = S.col_germ[k];
		float lx = S.body[b * 3] * COL_BLOCK, ly = S.body[b * 3 + 1] * COL_BLOCK;
		float wx = x[i] + lx * ch - ly * sh, wy = y[i] + lx * sh + ly * ch;
		mutated_now = false;
		int c = spawn_one(s, wx, wy, i);
		if (c < 0) {
			continue;
		}
		energy[c] = share;
		energy[i] -= share;
		store[c] = std::min(kept, S.col_store * col_store_e);
		heading[c] = pheading[c] = heading[i] + rand_range(-0.5f, 0.5f);
		wander[c] = heading[c];
		vx[c] = std::cos(heading[c]) * 12.0f;
		vy[c] = std::sin(heading[c]) * 12.0f;
		cooldown[c] = rand_range(0.0f, 3.0f);
		species[s].births++;
		col_born++;
		emit(EV_HATCH, wx, wy, s, x[i], y[i]);
		if (mutated_now) {
			emit(EV_MUTATION, wx, wy, s, x[i], y[i]);
		}
	}
	Ghost g;
	g.x = x[i];
	g.y = y[i];
	g.h = heading[i];
	g.t = 0.0f;
	g.ph = phase[i];
	g.s = s;
	g.lin = lineage[i];
	ghosts.push_back(g);
	kill(i, CAUSE_HATCH);
}

// Level 22: a hunter takes a mouthful off a colony: the rim block nearest it
// (armour gives up little), then pauses to swallow (digest). False while it
// is not yet against a block.
bool SimCore::bite_colony(int i, int j) {
	const Species &S = species[sp[i]];
	const Species &C = species[sp[j]];
	float ch = std::cos(heading[j]), sh = std::sin(heading[j]);
	float dx = x[i] - x[j], dy = y[i] - y[j];
	float lx = dx * ch + dy * sh, ly = -dx * sh + dy * ch;
	int m = (int)(C.body.size() / 3), best = -1;
	float bd = 1e9f, breach = 1e9f;
	for (int b = 0; b < m; b++) {
		// Level 23 (dig): a broken block is already torn, and the hunter goes
		// on into the wound (a block beside a broken one, even walled in, is
		// taken first), so a body can be bitten through.
		bool open = false;
		for (int q = 0; q < 4 && col_dig; q++) {
			int nb = C.col_nb[b * 4 + q];
			open = open || (nb >= 0 && cbroken[j * COL_MAXB + nb]);
		}
		if (col_dig && cbroken[j * COL_MAXB + b]) {
			continue;
		}
		if (C.col_rim[b] == 0 && !open) {
			continue; // (walled in: out of reach)
		}
		float qx = std::max(std::abs(lx - C.body[b * 3] * COL_BLOCK) - 0.5f * COL_BLOCK, 0.0f);
		float qy = std::max(std::abs(ly - C.body[b * 3 + 1] * COL_BLOCK) - 0.5f * COL_BLOCK, 0.0f);
		float reach = std::sqrt(qx * qx + qy * qy);
		float d = reach - (open ? COL_BLOCK * 1.5f : 0.0f);
		if (d < bd) {
			bd = d;
			breach = reach;
			best = b;
		}
	}
	if (best < 0 || breach > S.extent + 3.0f) {
		return false;
	}
	bool armour = C.col_kind[best] == 3 && !cbroken[j * COL_MAXB + best];
	float take = std::min(std::max(0.0f, energy[j]) + store[j], col_bite_e * (armour ? col_armor : 1.0f));
	float from_e = std::min(std::max(0.0f, energy[j]), take);
	energy[j] -= from_e;
	store[j] -= take - from_e;
	energy[i] += take * EAT_PREY_EFF;
	energy_out += take * (1.0f - EAT_PREY_EFF);
	{
		// The mouthful goes in where it was torn off and is digested in a
		// food vacuole (armour gives only a flake); a whole body being
		// swallowed is not replaced by it.
		float bx0 = C.body[best * 3] * COL_BLOCK, by0 = C.body[best * 3 + 1] * COL_BLOCK;
		float wx0 = x[j] + bx0 * ch - by0 * sh, wy0 = y[j] + bx0 * sh + by0 * ch;
		if (gulp_t[i] < 0.0f || gulp_r[i] <= 8.0f) {
			float hc = std::cos(heading[i]), hs = std::sin(heading[i]);
			float ex = wx0 - x[i], ey = wy0 - y[i];
			gulp_t[i] = 0.0f;
			gulp_sp[i] = sp[j];
			gulp_lin[i] = lineage[j];
			gulp_r[i] = armour ? 3.0f : 7.5f;
			gulp_lx[i] = ex * hc + ey * hs;
			gulp_ly[i] = -ex * hs + ey * hc;
			gulp_h[i] = 0.0f;
			gulp_ph[i] = phase[j];
		}
	}
	cmark[j * COL_MAXB + best] = 1.0f;
	hurt[j] = 2.0f;
	bitten[j] = 1;
	digest[i] = col_bite_gap;
	float bx = C.body[best * 3] * COL_BLOCK, by = C.body[best * 3 + 1] * COL_BLOCK;
	float wx = x[j] + bx * ch - by * sh, wy = y[j] + bx * sh + by * ch;
	emit(EV_CBITE, wx, wy, sp[j], armour ? 1.0f : 0.0f, std::atan2(y[i] - wy, x[i] - wx));
	col_bites++;
	col_blocked += armour ? 1 : 0;
	// Level 23: the bite leaves the block useless (armour only cracks, until
	// it gives); the body may come apart where it was bitten.
	if (col_hurt > 0.0f && !cbroken[j * COL_MAXB + best]) {
		float &d = cdmg[j * COL_MAXB + best];
		d = armour ? d + col_crack : 1.0f;
		if (d >= 1.0f) {
			break_block(j, best);
			// A big mouth tears on into the body, block by block along the
			// bite (col_depth), so a body can be bitten through.
			int at = best;
			float dirx = -lx, diry = -ly; // (from the hunter into the body, in its frame)
			for (int k = 1; k < col_depth; k++) {
				int next = -1;
				float bestdot = 0.3f * COL_BLOCK;
				for (int q = 0; q < 4; q++) {
					int nb = C.col_nb[at * 4 + q];
					if (nb < 0 || cbroken[j * COL_MAXB + nb]) {
						continue;
					}
					float ox = (C.body[nb * 3] - C.body[at * 3]) * COL_BLOCK, oy = (C.body[nb * 3 + 1] - C.body[at * 3 + 1]) * COL_BLOCK;
					float dot = (ox * dirx + oy * diry) / std::max(std::sqrt(dirx * dirx + diry * diry), 1e-3f);
					if (dot > bestdot) {
						bestdot = dot;
						next = nb;
					}
				}
				if (next < 0 || C.col_kind[next] == 3) {
					break; // (armour stops it)
				}
				cdmg[j * COL_MAXB + next] = 1.0f;
				break_block(j, next);
				at = next;
			}
			split_colony(j);
		}
	}
	if (alive[j] && energy[j] <= 0.5f && store[j] <= 0.5f) {
		// Eaten down to nothing: the hunter takes what is left in whole.
		Ghost g;
		g.x = x[j];
		g.y = y[j];
		g.h = heading[j];
		g.t = 0.0f;
		g.ph = phase[j];
		g.s = sp[j];
		g.lin = lineage[j];
		g.eater = id[i];
		float hc = std::cos(heading[i]), hs = std::sin(heading[i]);
		g.lx = dx * -hc + dy * -hs; // (dx, dy run from the body to the hunter)
		g.ly = dx * hs - dy * hc;
		g.dh = std::remainder(heading[j] - heading[i], TAU);
		ghosts.push_back(g);
		digest[i] = std::max(digest[i], COL_SWALLOW + DIGEST_TIME * 0.5f);
		col_eaten++;
		kill(j, CAUSE_EATEN);
	}
	return true;
}

// Level 23: a block gives way. A germ block loses its embryo.
void SimCore::break_block(int j, int b) {
	const Species &S = species[sp[j]];
	cdmg[j * COL_MAXB + b] = 1.0f;
	cbroken[j * COL_MAXB + b] = 1;
	col_broken++;
	for (int k = 0; k < (int)S.col_germ.size(); k++) {
		if (S.col_germ[k] == b && gest[j] >= 0.0f && emb[j * COL_GERMS + k] > 0.0f) {
			emb[j * COL_GERMS + k] = 0.0f;
			embryos_lost++;
		}
	}
}

// Level 23: if the working blocks no longer hold together, the body comes
// apart. The biggest piece stays; any other of three blocks or more swims off
// as a body of its own, the rest of the blueprint regrowing on it (a
// planarian's fragments each grow a whole worm); smaller crumbs are lost.
void SimCore::split_colony(int j) {
	const Species &S = species[sp[j]];
	int m = (int)(S.body.size() / 3);
	int part[COL_MAXB];
	int sizes[COL_MAXB];
	int np = 0;
	for (int b = 0; b < m; b++) {
		part[b] = -1;
	}
	for (int b = 0; b < m; b++) {
		if (part[b] >= 0 || cbroken[j * COL_MAXB + b]) {
			continue;
		}
		int stack[COL_MAXB];
		int top = 0;
		stack[top++] = b;
		part[b] = np;
		sizes[np] = 0;
		while (top > 0) {
			int c = stack[--top];
			sizes[np]++;
			for (int q = 0; q < 4; q++) {
				int nb = S.col_nb[c * 4 + q];
				if (nb >= 0 && part[nb] < 0 && !cbroken[j * COL_MAXB + nb]) {
					part[nb] = np;
					stack[top++] = nb;
				}
			}
		}
		np++;
	}
	if (np < 2) {
		return;
	}
	int keep = 0;
	for (int p = 1; p < np; p++) {
		if (sizes[p] > sizes[keep]) {
			keep = p;
		}
	}
	float total = 0.0f;
	for (int p = 0; p < np; p++) {
		total += sizes[p];
	}
	float e0 = std::max(0.0f, energy[j]), s0 = store[j];
	float ch = std::cos(heading[j]), sh = std::sin(heading[j]);
	for (int p = 0; p < np; p++) {
		if (p == keep) {
			continue;
		}
		// The piece leaves the parent: there, its blocks are lost too.
		for (int b = 0; b < m; b++) {
			if (part[b] == p) {
				cdmg[j * COL_MAXB + b] = 1.0f;
				cbroken[j * COL_MAXB + b] = 1;
			}
		}
		if (sizes[p] < 3 || count >= MAX_AGENTS) {
			continue;
		}
		// Off it swims: same blueprint, same place, everything but itself regrowing.
		float cx = 0.0f, cy = 0.0f;
		for (int b = 0; b < m; b++) {
			if (part[b] == p) {
				cx += S.body[b * 3] * COL_BLOCK;
				cy += S.body[b * 3 + 1] * COL_BLOCK;
			}
		}
		cx /= sizes[p];
		cy /= sizes[p];
		mutated_now = false;
		int c = spawn_one(sp[j], x[j], y[j], j);
		if (c < 0) {
			continue;
		}
		heading[c] = pheading[c] = heading[j];
		float ux = cx * ch - cy * sh, uy = cx * sh + cy * ch, ul = std::sqrt(ux * ux + uy * uy) + 1e-3f;
		vx[c] = ux / ul * 25.0f;
		vy[c] = uy / ul * 25.0f;
		energy[c] = e0 * sizes[p] / total;
		store[c] = s0 * sizes[p] / total;
		cpiece[c] = 1;
		age[c] = age[j];
		for (int b = 0; b < m; b++) {
			bool mine = part[b] == p;
			cdmg[c * COL_MAXB + b] = mine ? cdmg[j * COL_MAXB + b] : 1.0f;
			cbroken[c * COL_MAXB + b] = mine ? 0 : 1;
		}
		col_splits++;
		col_split_x = x[j];
		col_split_y = y[j];
		species[sp[j]].births++;
		emit(EV_HATCH, x[j] + ux, y[j] + uy, sp[j], x[j], y[j]);
	}
	energy[j] = e0 * sizes[keep] / total;
	store[j] = s0 * sizes[keep] / total;
	cpiece[j] = 1;
}

// Level 24: the rotifers. Each pulls the colonies ahead of it toward its
// mouth (a colony's working flagella pull against it), swallows the first to
// reach the mouth, chews it, and either eats it or, if it has armour enough
// (rot_spit working armour blocks), spits it out hurt. Hungrier, it pulls
// harder and swims faster.
void SimCore::set_rot_rage(float r) {
	rot_rage = r;
}

// An irritant dropped at pos: a rotifer whose head is within radius draws its
// corona in. Returns how long (seconds), -1 when no head is near enough, -2
// when the corona is drawn in already (nothing to gain).
constexpr float ROT_RETRACT = 6.0f, ROT_HABIT = 20.0f, ROT_SHELTER = 12.0f, ROT_SHELTER_R = 400.0f;

float SimCore::irritate(Vector2 pos, float radius) {
	if (rot_retract > 0.0f) {
		return -2.0f;
	}
	for (int i = 0; i < count; i++) {
		if (!alive[i] || !species[sp[i]].rotifer) {
			continue;
		}
		const Species &R = species[sp[i]];
		float hx = x[i] + std::cos(heading[i]) * R.extent * 0.8f, hy = y[i] + std::sin(heading[i]) * R.extent * 0.8f;
		if ((hx - pos.x) * (hx - pos.x) + (hy - pos.y) * (hy - pos.y) > radius * radius) {
			continue;
		}
		float d = rot_since < ROT_HABIT ? std::max(2.0f, rot_retract_last * 0.5f) : ROT_RETRACT;
		rot_retract = std::max(rot_retract, d);
		if (rot_meal[i] >= 0) {
			for (int j = 0; j < count; j++) {
				if (!alive[j] || id[j] != rot_meal[i]) {
					continue;
				}
				float ch = std::cos(heading[i]), sh = std::sin(heading[i]);
				cheld[j] = 0;
				x[j] = px[j] = hx + ch * 60.0f;
				y[j] = py[j] = hy + sh * 60.0f;
				vx[j] = ch * 70.0f;
				vy[j] = sh * 70.0f;
				cspurn[j] = std::max(cspurn[j], ROT_SHELTER);
				energy[i] -= R.rot_cost * divide_energy(i);
				energy_out += R.rot_cost * divide_energy(i);
				rot_rescued++;
				emit(EV_CBITE, x[j], y[j], sp[j], 1.0f, heading[i]);
				break;
			}
			rot_meal[i] = -1;
			rot_t[i] = 0.0f;
		}
		// The bodies by its head with cracked armour slip away meanwhile: it
		// leaves them alone for a while after (ROT_SHELTER).
		for (int j = 0; j < count; j++) {
			if (!alive[j] || !species[sp[j]].colony || cheld[j]) {
				continue;
			}
			if ((x[j] - hx) * (x[j] - hx) + (y[j] - hy) * (y[j] - hy) > ROT_SHELTER_R * ROT_SHELTER_R) {
				continue;
			}
			const Species &S = species[sp[j]];
			int m = (int)(S.body.size() / 3);
			for (int b = 0; b < m; b++) {
				if (S.col_kind[b] == 3 && S.col_rim[b] != 0 && cbroken[j * COL_MAXB + b]) {
					cspurn[j] = std::max(cspurn[j], ROT_SHELTER);
					break;
				}
			}
		}
		rot_retract_last = d;
		rot_since = 0.0f;
		rot_irritated++;
		return d;
	}
	return -1.0f;
}

PackedFloat32Array SimCore::get_rotifer_retract() const {
	PackedFloat32Array out;
	out.push_back(rot_retract);
	out.push_back(rot_retract_last);
	out.push_back(rot_since < ROT_HABIT ? std::max(2.0f, rot_retract_last * 0.5f) : ROT_RETRACT);
	return out;
}

void SimCore::step_rotifers(float dt) {
	rot_retract = std::max(0.0f, rot_retract - dt);
	rot_since += dt;
	for (int j = 0; j < count; j++) {
		cspurn[j] = std::max(0.0f, cspurn[j] - dt);
	}
	for (int i = 0; i < count; i++) {
		if (!alive[i] || !species[sp[i]].rotifer) {
			continue;
		}
		const Species &R = species[sp[i]];
		float fury = clampf(1.0f - energy[i] / R.rot_full, 0.0f, 1.0f);
		float ch = std::cos(heading[i]), sh = std::sin(heading[i]);
		float mx = x[i] + ch * R.extent * 0.8f, my = y[i] + sh * R.extent * 0.8f;
		// Hungrier, faster (and late in the run, angrier: rot_rage).
		x[i] += ch * 18.0f * R.rot_fury * rot_rage * fury * dt;
		y[i] += sh * 18.0f * R.rot_fury * rot_rage * fury * dt;
		if (rot_meal[i] >= 0) {
			int j = -1;
			for (int k = 0; k < count; k++) {
				if (alive[k] && id[k] == rot_meal[i]) {
					j = k;
					break;
				}
			}
			if (j < 0) {
				rot_meal[i] = -1;
				continue;
			}
			// Held in the mouth while it chews (slowly, it swims on).
			x[j] = px[j] = mx;
			y[j] = py[j] = my;
			vx[j] = vy[j] = 0.0f;
			vx[i] *= std::exp(-2.0f * dt);
			vy[i] *= std::exp(-2.0f * dt);
			rot_t[i] += dt;
			if (rot_t[i] < R.rot_chew) {
				continue;
			}
			const Species &C = species[sp[j]];
			int armour = 0;
			int m = (int)(C.body.size() / 3);
			for (int b = 0; b < m; b++) {
				armour += C.col_kind[b] == 3 && C.col_rim[b] != 0 && !cbroken[j * COL_MAXB + b] ? 1 : 0;
			}
			cheld[j] = 0;
			rot_meal[i] = -1;
			rot_t[i] = 0.0f;
			if (armour >= R.rot_spit) {
				// Too hard to grind: out it goes, the soft blocks hurt.
				rot_spat++;
				x[j] = px[j] = mx + ch * 60.0f;
				y[j] = py[j] = my + sh * 60.0f;
				vx[j] = ch * 70.0f;
				vy[j] = sh * 70.0f;
				energy[j] *= 0.7f;
				cspurn[j] = (rot_rage > 1.0f ? R.rot_rage_spurn : R.rot_spurn) * (1.0f + 0.5f * (float)std::max(0, armour - R.rot_spit));
				// The wasted chew costs it (a meal ground at and given up).
				energy[i] -= R.rot_cost * divide_energy(i);
				energy_out += R.rot_cost * divide_energy(i);
				if (col_hurt > 0.0f) {
					int hurt = 0;
					for (int b = 0; b < m && (R.rot_bruise < 0 || hurt < R.rot_bruise); b++) {
						int k = (b * 7 + id[j]) % m;
						if (C.col_kind[k] != 3 && C.col_rim[k] != 0 && !cbroken[j * COL_MAXB + k]) {
							break_block(j, k);
							hurt++;
						}
					}
					// The grinding wears the shell: one armour block (the rim's
					// most worn) takes rot_wear and cracks through at 1, so a body
					// swallowed again before the wear has regrown is eaten.
					if (R.rot_wear > 0.0f) {
						int k = -1;
						float best = -1.0f;
						for (int b = 0; b < m; b++) {
							int q = (b * 5 + id[j]) % m;
							if (C.col_kind[q] != 3 || cbroken[j * COL_MAXB + q]) {
								continue;
							}
							float v = cdmg[j * COL_MAXB + q] + (C.col_rim[q] != 0 ? 2.0f : 0.0f);
							if (v > best) {
								best = v;
								k = q;
							}
						}
						if (k >= 0) {
							float &d = cdmg[j * COL_MAXB + k];
							d += R.rot_wear;
							if (d >= 0.999f) {
								break_block(j, k);
								rot_worn++;
							}
						}
					}
					split_colony(j);
				}
				emit(EV_CBITE, x[j], y[j], sp[j], 1.0f, heading[i]);
			} else {
				rot_eaten++;
				float rest = std::max(0.0f, energy[j]) + store[j] + body_energy(sp[j]);
				energy[i] += rest * EAT_PREY_EFF * R.rot_gain * (rot_rage > 1.0f ? R.rot_rage_gain : 1.0f);
				energy_out += rest * (1.0f - EAT_PREY_EFF);
				energy[j] = 0.0f;
				store[j] = 0.0f;
				col_eaten++;
				kill(j, CAUSE_EATEN);
			}
			continue;
		}
		// The corona drawn in: no current, nothing taken in.
		if (rot_retract > 0.0f) {
			continue;
		}
		// The corona's current: ahead of it, within reach, toward the mouth.
		float reach = R.rot_reach * (1.0f + 0.25f * fury);
		float pull = R.rot_pull * (1.0f + R.rot_fury * rot_rage * fury);
		for (int j = 0; j < count; j++) {
			if (!alive[j] || cheld[j] || !species[sp[j]].colony || cspurn[j] > 0.0f) {
				continue;
			}
			float dx = mx - x[j], dy = my - y[j];
			float d = std::sqrt(dx * dx + dy * dy) + 1e-3f;
			if (d > reach) {
				continue;
			}
			// (Ahead of it: the mouth faces along the heading.)
			if (-(dx * ch + dy * sh) / d < std::cos(R.rot_cone) && d > R.extent * 0.6f) {
				continue;
			}
			const Species &C = species[sp[j]];
			if (d < C.extent * 0.9f + 20.0f) {
				rot_meal[i] = id[j];
				rot_t[i] = 0.0f;
				cheld[j] = 1;
				rot_swallowed++;
				emit(EV_EATEN, x[j], y[j], sp[j], C.extent, heading[j]);
				break;
			}
			float resist = C.col_speed * (1.0f - cslow[j]) * 0.9f;
			float net = pull * (1.0f - 0.6f * d / reach) - resist;
			if (net > 0.0f) {
				x[j] += dx / d * net * dt;
				y[j] += dy / d * net * dt;
			}
		}
	}
}

PackedFloat32Array SimCore::get_rotifers(float alpha) const {
	PackedFloat32Array out;
	for (int i = 0; i < count; i++) {
		if (!alive[i] || !species[sp[i]].rotifer) {
			continue;
		}
		const Species &R = species[sp[i]];
		out.push_back(lerpf(px[i], x[i], alpha));
		out.push_back(lerpf(py[i], y[i], alpha));
		out.push_back(angle_lerp(pheading[i], heading[i], alpha));
		out.push_back(clampf(1.0f - energy[i] / R.rot_full, 0.0f, 1.0f));
		out.push_back(rot_meal[i] >= 0 ? clampf(rot_t[i] / R.rot_chew, 0.0f, 1.0f) : 0.0f);
		out.push_back(clampf(energy[i] / R.rot_full, 0.0f, 1.0f));
	}
	return out;
}

Dictionary SimCore::get_rotifer_stats() const {
	Dictionary d;
	d["swallowed"] = rot_swallowed;
	d["spat"] = rot_spat;
	d["worn"] = rot_worn;
	d["irritated"] = rot_irritated;
	d["rescued"] = rot_rescued;
	d["eaten"] = rot_eaten;
	return d;
}

void SimCore::step_colonies(float dt) {
	for (int k = (int)ghosts.size() - 1; k >= 0; k--) {
		Ghost &g = ghosts[k];
		g.t += dt;
		if (g.eater >= 0) {
			// Being swallowed: it follows the hunter in; at the mouth the gut
			// takes it (a green mass digested inside), and it is gone.
			int e = -1;
			for (int i = 0; i < count; i++) {
				if (alive[i] && id[i] == g.eater) {
					e = i;
					break;
				}
			}
			if (e < 0) {
				g.eater = -1; // (the hunter died first: the remains stay)
				g.t = 0.0f;
				continue;
			}
			float pull = clampf(g.t / COL_SWALLOW, 0.0f, 1.0f);
			float hc = std::cos(heading[e]), hs = std::sin(heading[e]);
			float r = species[sp[e]].radius;
			float lx = lerpf(g.lx, 0.35f * r, pull), ly = lerpf(g.ly, 0.0f, pull);
			g.x = x[e] + lx * hc - ly * hs;
			g.y = y[e] + lx * hs + ly * hc;
			g.h = heading[e] + g.dh;
			if (!g.handed && g.t >= COL_SWALLOW) {
				g.handed = true;
				gulp_t[e] = 0.0f;
				gulp_sp[e] = g.s;
				gulp_lin[e] = g.lin;
				gulp_r[e] = std::min(r * 0.42f, species[g.s].col_skin * 0.22f);
				gulp_lx[e] = 0.35f * r;
				gulp_ly[e] = 0.0f;
				gulp_h[e] = g.dh;
				gulp_ph[e] = g.ph;
				emit(EV_EATEN, x[e], y[e], g.s, r * 0.5f, 0.0f);
			}
			if (g.t >= COL_SWALLOW + 0.5f) {
				ghosts[k] = ghosts.back();
				ghosts.pop_back();
			}
			continue;
		}
		g.x += stream_x * 0.8f * dt;
		g.y += stream_y * 0.8f * dt;
		if (g.t >= COL_GHOST) {
			ghosts[k] = ghosts.back();
			ghosts.pop_back();
		}
	}
	if (grits.empty()) {
		return;
	}
	// A body as long as twelve blocks reaches this far from its centre.
	const int cr = (int)(6.5f * COL_BLOCK / acell) + 1;
	const float half = 0.5f * COL_BLOCK + 1.5f;
	for (Grit &g : grits) {
		g.px = g.x;
		g.py = g.y;
		g.x += g.vx * dt;
		g.y += g.vy * dt;
		if (!inside_dish(g.x, g.y, 0.0f)) {
			respawn_grit(g, false);
			continue;
		}
		int ci = (int)clampf(g.x / acell, 0.0f, (float)(agw - 1));
		int cj = (int)clampf(g.y / acell, 0.0f, (float)(agh - 1));
		bool struck = false;
		for (int gy = std::max(cj - cr, 0); gy <= std::min(cj + cr, agh - 1) && !struck; gy++) {
			for (int gx = std::max(ci - cr, 0); gx <= std::min(ci + cr, agw - 1) && !struck; gx++) {
				for (int j = ahead[gy * agw + gx]; j >= 0 && !struck; j = anext[j]) {
					if (j >= count || !alive[j] || !species[sp[j]].colony) {
						continue;
					}
					const Species &S = species[sp[j]];
					float dx = g.x - x[j], dy = g.y - y[j];
					float reach = S.half_len + S.half_wid;
					if (dx * dx + dy * dy > reach * reach) {
						continue;
					}
					float ch = std::cos(heading[j]), sh = std::sin(heading[j]);
					float lx = (dx * ch + dy * sh) / COL_BLOCK, ly = (-dx * sh + dy * ch) / COL_BLOCK;
					int m = (int)(S.body.size() / 3);
					for (int b = 0; b < m && !struck; b++) {
						if (std::abs(lx - S.body[b * 3]) * COL_BLOCK > half || std::abs(ly - S.body[b * 3 + 1]) * COL_BLOCK > half) {
							continue;
						}
						struck = true;
						float killed = 0.0f;
						if (gest[j] >= 0.0f) {
							for (int k = 0; k < (int)S.col_germ.size(); k++) {
								if (S.col_germ[k] == b && emb[j * COL_GERMS + k] > 0.04f) {
									emb[j * COL_GERMS + k] = 0.0f;
									embryos_lost++;
									killed = 1.0f;
								}
							}
						}
						emit(EV_GRIT, g.x, g.y, sp[j], killed, heading[j]);
					}
				}
			}
		}
		if (struck) {
			respawn_grit(g, false);
		}
	}
}

Dictionary SimCore::get_colony_stats() const {
	Dictionary d;
	int bodies = 0, carrying = 0, burned = 0;
	for (int i = 0; i < count; i++) {
		if (alive[i] && species[sp[i]].colony) {
			bodies++;
			carrying += gest[i] >= 0.0f ? 1 : 0;
		}
	}
	for (const Species &S : species) {
		burned += S.colony ? S.deaths_temp : 0;
	}
	d["burned"] = burned;
	d["bodies"] = bodies;
	d["carrying"] = carrying;
	d["hatched"] = col_hatched;
	d["born"] = col_born;
	d["lost"] = embryos_lost;
	d["bites"] = col_bites;
	d["blocked"] = col_blocked;
	d["eaten"] = col_eaten;
	float stored = 0.0f;
	for (int i = 0; i < count; i++) {
		stored += alive[i] && species[sp[i]].colony ? store[i] : 0.0f;
	}
	d["stored"] = stored;
	d["splits"] = col_splits;
	d["whole"] = col_whole;
	d["broken"] = col_broken;
	d["healed"] = col_healed;
	d["split_at"] = Vector2(col_split_x, col_split_y);
	return d;
}

PackedFloat32Array SimCore::get_colonies() const {
	PackedFloat32Array out;
	for (int i = 0; i < count; i++) {
		const Species &S = species[sp[i]];
		if (!alive[i] || !S.colony) {
			continue;
		}
		float most = 0.0f;
		if (gest[i] >= 0.0f) {
			for (int k = 0; k < (int)S.col_germ.size(); k++) {
				most = std::max(most, emb[i * COL_GERMS + k]);
			}
		}
		out.push_back((float)id[i]);
		out.push_back(x[i]);
		out.push_back(y[i]);
		out.push_back(heading[i]);
		out.push_back(most);
		out.push_back(gest[i] >= 0.0f ? 1.0f : 0.0f);
	}
	return out;
}

// Level 24: the bodies whose rim armour the guardian cracked and that have not
// regrown it yet, [x, y, cracked, regrown 0..1, spurned seconds left] each
// (scripts/colony_layer.gd marks them).
PackedFloat32Array SimCore::get_worn(float alpha) const {
	PackedFloat32Array out;
	for (int i = 0; i < count; i++) {
		const Species &S = species[sp[i]];
		if (!alive[i] || !S.colony || cheld[i]) {
			continue;
		}
		int m = (int)(S.body.size() / 3);
		int cracked = 0;
		float worst = 0.0f;
		for (int b = 0; b < m; b++) {
			if (S.col_kind[b] == 3 && S.col_rim[b] != 0 && cbroken[i * COL_MAXB + b]) {
				cracked++;
				worst = std::max(worst, cdmg[i * COL_MAXB + b]);
			}
		}
		if (cracked == 0) {
			continue;
		}
		out.push_back(lerpf(px[i], x[i], alpha));
		out.push_back(lerpf(py[i], y[i], alpha));
		out.push_back((float)cracked);
		out.push_back(clampf(1.0f - worst, 0.0f, 1.0f));
		out.push_back(cspurn[i]);
	}
	return out;
}

// Blocks and grit, one quad each (shaders/colony.gdshader). custom = ((kind +
// 8 * open sides) / 128, phase, embryo, shell fade), all 0..1 as the shader
// gets them clamped; colour.a = how hard it swims.
PackedFloat32Array SimCore::build_colony_blocks(Rect2 rect, float alpha, float time, int capacity) {
	PackedFloat32Array out;
	out.resize(std::max(capacity, 0) * FLOATS_PER_INSTANCE);
	float *w = out.ptrw();
	std::fill(w, w + out.size(), 0.0f);
	int n = 0;
	auto put = [&](float ox, float oy, float h, float side, const Color &col, float a, float c0, float c1, float c2, float c3) {
		if (n >= capacity) {
			return;
		}
		float cs = std::cos(h) * side, sn = std::sin(h) * side;
		w[0] = cs;
		w[1] = -sn;
		w[3] = ox;
		w[4] = sn;
		w[5] = cs;
		w[7] = oy;
		w[8] = col.r;
		w[9] = col.g;
		w[10] = col.b;
		w[11] = a;
		w[12] = c0;
		w[13] = c1;
		w[14] = c2;
		w[15] = c3;
		w += FLOATS_PER_INSTANCE;
		n++;
	};
	const float quad = 2.2f; // block sides: room for the flagella beyond it
	auto body = [&](const Species &S, float ox, float oy, float h, float sc, const Color &col, float a, float ph, const float *embryos, float fade, int who) {
		float cs = std::cos(h), sn = std::sin(h);
		int m = (int)(S.body.size() / 3);
		for (int k = 0; k < m; k++) {
			float bx = S.body[k * 3] * COL_BLOCK * sc, by = S.body[k * 3 + 1] * COL_BLOCK * sc;
			int kind = S.col_kind[k];
			int germ = kind == 1 ? 1 : 0;
			float e = 0.0f;
			// z: the embryo (germ), the fresh bite (armour), how full (store).
			if (kind == 3 && who >= 0) {
				e = cmark[who * COL_MAXB + k];
			} else if (kind == 4 && who >= 0) {
				e = clampf(store[who] / std::max(1e-3f, S.col_store * col_store_e), 0.0f, 1.0f);
			}
			if (germ && embryos != nullptr) {
				for (int g = 0; g < (int)S.col_germ.size(); g++) {
					if (S.col_germ[g] == k) {
						e = embryos[g];
					}
				}
			}
			float w4 = fade > 0.0f ? fade * 0.49f : 0.0f;
			if (who >= 0 && cdmg[who * COL_MAXB + k] > 0.0f) {
				float dd = std::min(cdmg[who * COL_MAXB + k], 1.0f);
				w4 = cbroken[who * COL_MAXB + k] ? 0.75f + 0.25f * dd : 0.5f + 0.24f * dd;
			}
			put(ox + bx * cs - by * sn, oy + bx * sn + by * cs, h, COL_BLOCK * sc * quad, col, a, ((float)kind + 8.0f * S.col_rim[k]) / 128.0f, std::fmod(ph + k * 0.37f, 1.0f), e, w4);
		}
	};
	Rect2 near = rect.grow(COL_BLOCK * 7.0f);
	for (const Ghost &g : ghosts) {
		float gx, gy, gh, gs, gf;
		if (ghost_pose(g, alpha, gx, gy, gh, gs, gf) && near.has_point(Vector2(gx, gy))) {
			body(species[g.s], gx, gy, gh, gs, lineage_color(g.s, g.lin), 0.0f, g.ph, nullptr, gf, -1);
		}
	}
	for (int i = 0; i < count; i++) {
		const Species &S = species[sp[i]];
		if (!S.colony || !alive[i]) {
			continue;
		}
		float ox = lerpf(px[i], x[i], alpha), oy = lerpf(py[i], y[i], alpha);
		if (!near.has_point(Vector2(ox, oy))) {
			continue;
		}
		float h = angle_lerp(pheading[i], heading[i], alpha);
		float sw_a = clampf(std::sqrt(vx[i] * vx[i] + vy[i] * vy[i]) / std::max(S.col_speed, 1.0f), 0.0f, 1.0f);
		float grow = gen[i] > 1 ? clampf(age[i] / COL_GROW, 0.0f, 1.0f) : 1.0f;
		float sc = 0.45f + 0.55f * grow * grow * (3.0f - 2.0f * grow);
		body(S, ox, oy, h, sc, lineage_color(sp[i], lineage[i]), sw_a, phase[i], gest[i] >= 0.0f ? &emb[i * COL_GERMS] : nullptr, 0.0f, i);
	}
	for (const Grit &g : grits) {
		float ox = lerpf(g.px, g.x, alpha), oy = lerpf(g.py, g.y, alpha);
		if (rect.has_point(Vector2(ox, oy))) {
			put(ox, oy, g.ph + time * 0.7f, 9.0f, Color(0.42f, 0.36f, 0.3f), 1.0f, 2.0f / 128.0f, std::fmod(g.ph, 1.0f), 0.0f, 0.0f);
		}
	}
	colony_drawn = n;
	return out;
}

// Where an empty body is drawn: a torn shell where it died, fading; or, being
// swallowed, drawn into its hunter's mouth (shrinking, turning with it, gone as
// the gut takes it). False once nothing is left to draw.
bool SimCore::ghost_pose(const Ghost &g, float alpha, float &ox, float &oy, float &h, float &sc, float &fade) const {
	ox = g.x;
	oy = g.y;
	h = g.h;
	sc = 1.0f;
	fade = clampf(g.t / COL_GHOST, 0.02f, 1.0f);
	if (g.eater < 0) {
		return true;
	}
	int e = -1;
	for (int i = 0; i < count; i++) {
		if (alive[i] && id[i] == g.eater) {
			e = i;
			break;
		}
	}
	if (e < 0) {
		return true;
	}
	float t = g.t + alpha * last_dt;
	float pull = clampf(t / COL_SWALLOW, 0.0f, 1.0f);
	pull = pull * pull * (3.0f - 2.0f * pull);
	float eh = angle_lerp(pheading[e], heading[e], alpha);
	float ex = lerpf(px[e], x[e], alpha), ey = lerpf(py[e], y[e], alpha);
	float r = species[sp[e]].radius;
	float lx = lerpf(g.lx, 0.35f * r, pull), ly = lerpf(g.ly, 0.0f, pull);
	ox = ex + lx * std::cos(eh) - ly * std::sin(eh);
	oy = ey + lx * std::sin(eh) + ly * std::cos(eh);
	h = eh + g.dh;
	sc = lerpf(1.0f, 0.4f, pull);
	fade = 0.02f + 0.98f * clampf((t - COL_SWALLOW * 0.75f) / 0.7f, 0.0f, 1.0f);
	return fade < 0.99f;
}

// One species' outer jelly, a quad each; the shape is baked per blueprint
// (scripts/colony.gd). custom = (0, phase, energy, shell fade).
PackedFloat32Array SimCore::build_colony_skins(int s, Rect2 rect, float alpha, int capacity) {
	PackedFloat32Array out;
	out.resize(std::max(capacity, 0) * FLOATS_PER_INSTANCE);
	float *w = out.ptrw();
	std::fill(w, w + out.size(), 0.0f);
	int n = 0;
	const Species &S = species[s];
	auto put = [&](float ox, float oy, float h, float side, const Color &col, float ph, float e, float fade) {
		if (n >= capacity) {
			return;
		}
		float cs = std::cos(h) * side, sn = std::sin(h) * side;
		w[0] = cs;
		w[1] = -sn;
		w[3] = ox;
		w[4] = sn;
		w[5] = cs;
		w[7] = oy;
		w[8] = col.r;
		w[9] = col.g;
		w[10] = col.b;
		w[11] = 1.0f;
		w[13] = std::fmod(ph, 1.0f);
		w[14] = e;
		w[15] = fade;
		w += FLOATS_PER_INSTANCE;
		n++;
	};
	Rect2 near = rect.grow(S.col_skin);
	for (const Ghost &g : ghosts) {
		float gx, gy, gh, gs, gf;
		if (g.s == s && ghost_pose(g, alpha, gx, gy, gh, gs, gf) && near.has_point(Vector2(gx, gy))) {
			put(gx, gy, gh, S.col_skin * gs, lineage_color(g.s, g.lin), g.ph, 0.0f, gf);
		}
	}
	for (int i = 0; i < count; i++) {
		if (sp[i] != s || !alive[i]) {
			continue;
		}
		float ox = lerpf(px[i], x[i], alpha), oy = lerpf(py[i], y[i], alpha);
		if (!near.has_point(Vector2(ox, oy))) {
			continue;
		}
		float grow = gen[i] > 1 ? clampf(age[i] / COL_GROW, 0.0f, 1.0f) : 1.0f;
		float sc = 0.45f + 0.55f * grow * grow * (3.0f - 2.0f * grow);
		put(ox, oy, angle_lerp(pheading[i], heading[i], alpha), S.col_skin * sc, lineage_color(sp[i], lineage[i]), phase[i], clampf(energy[i] / S.col_e, 0.0f, 1.0f), 0.0f);
	}
	colony_drawn = n;
	return out;
}

// --- phages -----------------------------------------------------------------

void SimCore::set_phage(Dictionary d) {
	phage_host = d.get("host", phage_host);
	phage_life = d.get("life", phage_life);
	phage_burst = d.get("burst", phage_burst);
	phage_yield = d.get("yield", phage_yield);
	phage_diffuse = d.get("diffuse", phage_diffuse);
	phage_stick = d.get("stick", phage_stick);
	phage_temperate = d.get("temperate", phage_temperate);
	phage_virophage = d.get("virophage", phage_virophage);
	phage_rain = d.get("rain", phage_rain);
	phage_rain_from = d.get("rain_from", phage_rain_from);
}

int SimCore::add_phages(Vector2 pos, float radius, int n) {
	int made = 0;
	for (int k = 0; k < n && phages < MAX_PHAGES; k++) {
		float a = rand_range(0.0f, TAU), d = radius * std::sqrt(randf());
		float wx = pos.x + std::cos(a) * d, wy = pos.y + std::sin(a) * d;
		keep_in_dish(wx, wy, 2.0f);
		int p = phages++;
		ph_x[p] = ph_px[p] = wx;
		ph_y[p] = ph_py[p] = wy;
		ph_vx[p] = ph_vy[p] = 0.0f;
		float sd = std::sqrt(phage_diffuse / PHAGE_DRIFT_T);
		ph_dx[p] = (randf() - 0.5f) * 3.4641f * sd;
		ph_dy[p] = (randf() - 0.5f) * 3.4641f * sd;
		ph_life[p] = phage_life * rand_range(0.6f, 1.4f);
		ph_age[p] = 0.0f;
		ph_seed[p] = next_phage++;
		made++;
	}
	return made;
}

// A burst: the new phages fly out of the cell's body and slow in the water.
void SimCore::release_phages(float wx, float wy, float r, int n) {
	for (int k = 0; k < n && phages < MAX_PHAGES; k++) {
		float a = rand_range(0.0f, TAU), d = r * std::sqrt(randf());
		float out = PHAGE_FLING * rand_range(0.5f, 1.3f);
		int p = phages++;
		ph_x[p] = ph_px[p] = wx + std::cos(a) * d;
		ph_y[p] = ph_py[p] = wy + std::sin(a) * d;
		ph_vx[p] = std::cos(a) * out;
		ph_vy[p] = std::sin(a) * out;
		ph_dx[p] = ph_dy[p] = 0.0f;
		ph_life[p] = phage_life * rand_range(0.6f, 1.4f) + PHAGE_SPILL;
		ph_age[p] = -PHAGE_SPILL * randf(); // not all at once: the torn cell spills them
		ph_seed[p] = next_phage++;
	}
}

// The carried phage comes out of the genes: the same end as an infection,
// from the point the DNA would have reached the nucleus.
void SimCore::wake_phage(int i, bool by_card) {
	inf_t[i] = PHAGE_INJECT;
	inf_ang[i] = by_card ? 1.0f : 0.0f; // (no landing spot here: says who woke it)
	inf_fate[i] = 3;
}

void SimCore::step_phages(float dt) {
	if (phage_host < 0) {
		return;
	}
	if (phage_rain > 0.0f && sim_time >= phage_rain_from) {
		phage_rain_debt += phage_rain * dt;
		while (phage_rain_debt >= 1.0f) {
			phage_rain_debt -= 1.0f;
			float wx = rand_range(0.0f, world_w), wy = rand_range(0.0f, world_h);
			if (dish_r > 0.0f) {
				float a = rand_range(0.0f, TAU), d = dish_r * std::sqrt(randf());
				wx = dish_x + std::cos(a) * d;
				wy = dish_y + std::sin(a) * d;
			}
			add_phages(Vector2(wx, wy), 0.0f, 1);
		}
	}
	for (int i = 0; i < count; i++) {
		if (!alive[i]) {
			continue;
		}
		if (inf_t[i] < 0.0f) {
			if (phage_virophage) {
				continue; // only a giant virus wakes a virophage
			}
			// Hard times wake a carried phage: hunger or heat, the worse the likelier.
			const Species &S = species[sp[i]];
			float wake_rate = carry[i] ? WAKE_CARRIED : S.prophage;
			if (wake_rate > 0.0f && join[i] <= 0.0f) {
				float hunger = clampf(1.0f - energy[i] / divide_energy(i) / WAKE_HUNGER, 0.0f, 1.0f);
				float stress = hunger + clampf(temp_dev(i) / WAKE_HEAT, 0.0f, 1.0f);
				if (stress > 0.0f && randf() < wake_rate * stress * dt) {
					wake_phage(i, false);
				}
			}
			continue;
		}
		inf_t[i] += dt;
		if (!doomed(i)) {
			if (inf_t[i] >= (inf_fate[i] == 1 ? PHAGE_CUT_NEW : PHAGE_CUT_OLD)) {
				if (inf_fate[i] == 1) {
					immune[i] = 1;
					emit(EV_IMMUNE, x[i], y[i], sp[i], species[sp[i]].extent, heading[i]);
				}
				inf_t[i] = -1.0f;
				inf_fate[i] = 0;
			}
			continue;
		}
		if (inf_fate[i] == 4) {
			if (inf_t[i] >= giant_burst) {
				burst_factory(i);
			}
			continue;
		}
		if (inf_t[i] >= phage_burst) {
			release_phages(x[i], y[i], species[sp[i]].extent, phage_yield);
			kill(i, CAUSE_PHAGE);
		}
	}
	// Drift: a velocity that wanders (Ornstein-Uhlenbeck), same spread over time
	// as a random walk of phage_diffuse, without the jitter tick by tick.
	const float keep = std::exp(-dt / PHAGE_DRIFT_T);
	const float kick = std::sqrt((1.0f - keep * keep) * phage_diffuse / PHAGE_DRIFT_T) * 3.4641f; // uniform in +-0.5: sd 1
	const float drag = std::exp(-PHAGE_FLING_DRAG * dt);
	int w = 0;
	for (int p = 0; p < phages; p++) {
		float life = ph_life[p] - dt;
		if (life <= 0.0f) {
			continue;
		}
		int fc = nutrient_index(ph_x[p], ph_y[p]);
		float ox = ph_x[p], oy = ph_y[p];
		if (ph_age[p] < 0.0f) { // still in the torn cell
			ph_x[w] = ph_px[w] = ox;
			ph_y[w] = ph_py[w] = oy;
			ph_vx[w] = ph_vx[p];
			ph_vy[w] = ph_vy[p];
			ph_dx[w] = ph_dy[w] = 0.0f;
			ph_life[w] = life;
			ph_age[w] = ph_age[p] + dt;
			ph_seed[w] = ph_seed[p];
			w++;
			continue;
		}
		float dvx = ph_dx[p] * keep + (randf() - 0.5f) * kick;
		float dvy = ph_dy[p] * keep + (randf() - 0.5f) * kick;
		float nx = ox + (flow_u[fc] + ph_vx[p] + dvx) * dt;
		float ny = oy + (flow_v[fc] + ph_vy[p] + dvy) * dt;
		keep_in_dish(nx, ny, 2.0f);
		for (const Barrier &b : barriers) {
			float ex = b.bx - b.ax, ey = b.by - b.ay;
			float s0 = ex * (oy - b.ay) - ey * (ox - b.ax), s1 = ex * (ny - b.ay) - ey * (nx - b.ax);
			if (s0 * s1 >= 0.0f) {
				continue;
			}
			float u = s0 / (s0 - s1);
			float cx = ox + (nx - ox) * u - b.ax, cy = oy + (ny - oy) * u - b.ay;
			float along = (cx * ex + cy * ey) / std::max(ex * ex + ey * ey, 1e-3f);
			if (along >= 0.0f && along <= 1.0f) {
				nx = ox;
				ny = oy;
				break;
			}
		}
		float age_now = ph_age[p] + dt;
		bool landed = false;
		if (phage_virophage) {
			landed = age_now > 0.3f && virophage_lands(nx, ny);
		} else if (age_now > 0.3f) {
			int gx = (int)clampf(nx / acell, 0.0f, (float)(agw - 1)), gy = (int)clampf(ny / acell, 0.0f, (float)(agh - 1));
			for (int b = std::max(0, gy - 1); b <= std::min(agh - 1, gy + 1) && !landed; b++) {
				for (int a = std::max(0, gx - 1); a <= std::min(agw - 1, gx + 1) && !landed; a++) {
					for (int j = ahead[b * agw + a]; j >= 0; j = anext[j]) {
						if (sp[j] != phage_host || !alive[j] || inf_t[j] >= 0.0f || join[j] > 0.0f || carry[j]) {
							continue;
						}
						float dx = nx - x[j], dy = ny - y[j];
						float reach = species[phage_host].extent + 4.0f + PHAGE_REACH;
						if (dx * dx + dy * dy > reach * reach) {
							continue;
						}
						float d = std::sqrt(dx * dx + dy * dy) + 1e-4f;
						if (d > cell_radius(j, dx / d, dy / d) + PHAGE_REACH || randf() > phage_stick) {
							continue;
						}
						// Temperate: most settle in the genes; some go the other way
						// and burst, which is how it spreads at all (phage lambda).
						if (phage_temperate && randf() < 0.65f) {
							carry[j] = 1;
							landed = true;
							break;
						}
						inf_t[j] = 0.0f;
						inf_ang[j] = std::atan2(dy, dx) - heading[j];
						inf_fate[j] = immune[j] ? 2 : (randf() < species[phage_host].crispr ? 1 : 0);
						landed = true;
						break;
					}
				}
			}
		}
		if (landed) {
			continue;
		}
		ph_x[w] = nx;
		ph_y[w] = ny;
		ph_px[w] = ox;
		ph_py[w] = oy;
		ph_vx[w] = ph_vx[p] * drag;
		ph_vy[w] = ph_vy[p] * drag;
		ph_dx[w] = dvx;
		ph_dy[w] = dvy;
		ph_life[w] = life;
		ph_age[w] = age_now;
		ph_seed[w] = ph_seed[p];
		w++;
	}
	phages = w;
}

// A virophage is nothing on its own: it takes hold on a giant in the water, on
// a cell with a factory, and (temperate) in the genes of a healthy cell.
bool SimCore::virophage_lands(float wx, float wy) {
	int gx = (int)clampf(wx / acell, 0.0f, (float)(agw - 1)), gy = (int)clampf(wy / acell, 0.0f, (float)(agh - 1));
	for (int b = std::max(0, gy - 1); b <= std::min(agh - 1, gy + 1); b++) {
		for (int a = std::max(0, gx - 1); a <= std::min(agw - 1, gx + 1); a++) {
			for (int g = ghead[b * agw + a]; g >= 0; g = gnext[g]) {
				if (g >= (int)giants.size() || giants[g].load > 0) {
					continue;
				}
				float dx = wx - giants[g].x, dy = wy - giants[g].y;
				if (dx * dx + dy * dy < (GIANT_R + PHAGE_REACH) * (GIANT_R + PHAGE_REACH) && randf() < phage_stick) {
					giants[g].load = 1;
					return true;
				}
			}
			for (int j = ahead[b * agw + a]; j >= 0; j = anext[j]) {
				if (sp[j] != phage_host || !alive[j] || join[j] > 0.0f) {
					continue;
				}
				bool factory = inf_t[j] >= 0.0f && inf_fate[j] == 4 && hijack[j] < 0.0f;
				bool settle = inf_t[j] < 0.0f && phage_temperate && !carry[j];
				if (!factory && !settle) {
					continue;
				}
				float dx = wx - x[j], dy = wy - y[j];
				float d = std::sqrt(dx * dx + dy * dy) + 1e-4f;
				if (d > cell_radius(j, dx / d, dy / d) + PHAGE_REACH || randf() > phage_stick) {
					continue;
				}
				if (factory) {
					hijack[j] = inf_t[j];
					giant_hijacked++;
				} else {
					carry[j] = 1;
				}
				return true;
			}
		}
	}
	return false;
}

void SimCore::set_slug(Dictionary d) {
	slug_host = d.get("host", slug_host);
	Vector2 at = d.get("target", Vector2(slug_tx, slug_ty));
	slug_tx = at.x;
	slug_ty = at.y;
	slug_speed = d.get("speed", slug_speed);
	slug_gather = d.get("gather", slug_gather);
	slug_loss = d.get("loss", slug_loss);
	slug_arrive = d.get("arrive", slug_arrive);
	slug_share = d.get("stalk", slug_share);
	slug_rise = d.get("rise", slug_rise);
	slug_wait = d.get("wait", slug_wait);
	slug_min = d.get("min", slug_min);
	slug_stay = d.get("stay", slug_stay);
}

// A cell gives itself up to the nearest slug still on the move, or starts one.
void SimCore::join_slug(int i) {
	int best = -1;
	float near2 = 130.0f * 130.0f;
	for (int s = 0; s < (int)slugs.size(); s++) {
		if (slugs[s].stage > 1) {
			continue;
		}
		float dx = slugs[s].x - x[i], dy = slugs[s].y - y[i];
		if (dx * dx + dy * dy < near2) {
			near2 = dx * dx + dy * dy;
			best = s;
		}
	}
	if (best < 0) {
		Slug g{};
		g.x = x[i];
		g.y = y[i];
		g.hx = slug_tx - x[i];
		g.hy = slug_ty - y[i];
		float l = std::sqrt(g.hx * g.hx + g.hy * g.hy) + 1e-3f;
		g.hx /= l;
		g.hy /= l;
		slugs.push_back(g);
		best = (int)slugs.size() - 1;
	}
	float a = rand_range(0.0f, TAU), d = std::sqrt(randf());
	slug[i] = best;
	sl_ox[i] = std::cos(a) * d;
	sl_oy[i] = std::sin(a) * d;
}

void SimCore::step_slugs(float dt) {
	if (slug_host < 0 || slugs.empty()) {
		return;
	}
	int ns = (int)slugs.size();
	std::vector<float> sx(ns, 0.0f), sy(ns, 0.0f);
	std::vector<int> nn(ns, 0);
	for (int i = 0; i < count; i++) {
		if (alive[i] && slug[i] >= 0) {
			sx[slug[i]] += x[i];
			sy[slug[i]] += y[i];
			nn[slug[i]]++;
		}
	}
	const Species &S = species[slug_host];
	const float pull = 1.0f - std::exp(-3.0f * dt);
	// Streams run together: two slugs that meet are one slug.
	for (int a = 0; a < ns; a++) {
		if (slugs[a].stage > 1 || nn[a] == 0) {
			continue;
		}
		for (int b = a + 1; b < ns; b++) {
			if (slugs[b].stage > 1 || nn[b] == 0) {
				continue;
			}
			float dx = slugs[a].x - slugs[b].x, dy = slugs[a].y - slugs[b].y;
			float reach = 60.0f + 3.0f * (std::sqrt((float)nn[a]) + std::sqrt((float)nn[b]));
			if (dx * dx + dy * dy > reach * reach) {
				continue;
			}
			int big = nn[a] >= nn[b] ? a : b, small = big == a ? b : a;
			for (int i = 0; i < count; i++) {
				if (alive[i] && slug[i] == small) {
					slug[i] = big;
				}
			}
			sx[big] += sx[small];
			sy[big] += sy[small];
			nn[big] += nn[small];
			sx[small] = sy[small] = 0.0f;
			nn[small] = 0;
			if (slugs[big].stage < slugs[small].stage) {
				slugs[big].stage = slugs[small].stage;
				slugs[big].t = slugs[small].t;
			}
		}
	}
	// Only a species that calls has a centre the others run to; the biggest
	// gathering is the loudest (no calling: each lump stays on its own).
	bool calling = false;
	for (const Card &cd : S.deck) {
		calling = calling || cd.act == A_EMIT_A;
	}
	int lead = -1;
	for (int s = 0; s < ns; s++) {
		if (slugs[s].stage == 0 && nn[s] > 0 && (lead < 0 || nn[s] > nn[lead])) {
			lead = s;
		}
	}
	for (int s = 0; s < ns; s++) {
		Slug &g = slugs[s];
		g.t += dt;
		g.n = nn[s];
		if (g.n > g.peak) {
			g.peak = g.n;
			g.grew = g.t;
		}
		if (g.stage == 3) {
			if (g.t > 45.0f) {
				g.stage = 4;
			}
			continue;
		}
		if (g.stage == 4) {
			continue;
		}
		if (g.n == 0) {
			if (g.t > 1.0f) {
				g.stage = 4;
			}
			continue;
		}
		if (g.stage <= 1) {
			float cx = sx[s] / g.n, cy = sy[s] / g.n;
			g.mx = cx;
			g.my = cy;
			if (g.stage == 0) {
				g.x = lerpf(g.x, cx, pull);
				g.y = lerpf(g.y, cy, pull);
				if (calling) {
					// The centre keeps calling: the pulse that draws the streams in.
					sig_a[nutrient_index(g.x, g.y)] += SIGNAL_EMIT * 4.0f * dt;
					if (s != lead && lead >= 0) {
						float dx = slugs[lead].x - g.x, dy = slugs[lead].y - g.y;
						float d = std::sqrt(dx * dx + dy * dy) + 1e-3f;
						if (d < 520.0f) {
							g.x += dx / d * 34.0f * dt;
							g.y += dy / d * 34.0f * dt;
						}
					}
				}
				// It waits while cells are still coming in, up to a point.
				if (g.t >= slug_gather && (g.t - g.grew >= 5.0f || g.t >= slug_gather * 3.0f)) {
					if (g.n < slug_min) {
						// Too few to go anywhere: they fall apart again.
						g.stage = 4;
						slug_broke++;
						for (int i = 0; i < count; i++) {
							if (slug[i] == s) {
								slug[i] = -1;
							}
						}
						continue;
					}
					g.stage = 1;
					g.t = 0.0f;
					slug_formed++;
				}
			} else {
				// To the light; a warm spot close by draws it aside (slugs turn to heat too).
				float dx = slug_tx - g.x, dy = slug_ty - g.y;
				float best = 340.0f * 340.0f;
				g.warm_off = std::max(0.0f, g.warm_off - dt);
				for (const TempSpot &ts : temp_spots) {
					float wx = ts.x - g.x, wy = ts.y - g.y;
					float d2 = wx * wx + wy * wy;
					if (ts.delta <= 0.0f || g.warm_off > 0.0f) {
						continue;
					}
					// Once there it has what it came for: on to the light, for
					// long enough not to turn back to the same spot.
					if (d2 < 80.0f * 80.0f) {
						g.warm_off = 40.0f;
						dx = slug_tx - g.x;
						dy = slug_ty - g.y;
						break;
					}
					if (d2 < best) {
						best = d2;
						dx = wx;
						dy = wy;
					}
				}
				float l = std::sqrt(dx * dx + dy * dy) + 1e-3f;
				float turn = std::min(1.0f, dt * 0.9f);
				g.hx = lerpf(g.hx, dx / l, turn);
				g.hy = lerpf(g.hy, dy / l, turn);
				float hl = std::sqrt(g.hx * g.hx + g.hy * g.hy) + 1e-3f;
				g.hx /= hl;
				g.hy /= hl;
				g.x += g.hx * slug_speed * dt;
				g.y += g.hy * slug_speed * dt;
				keep_in_dish(g.x, g.y, 40.0f);
				// The hot water takes its outermost cells, the rest shelter behind them.
				// (Real heat only: a player's warm spot leads it, it doesn't cook it.)
				float dev = std::abs(temp_at(g.x, g.y) - S.temp_opt) - S.temp_tol;
				if (dev > SLUG_HEAT) {
					g.debt += slug_loss * dt;
					while (g.debt >= 1.0f && g.n > 0) {
						g.debt -= 1.0f;
						int out = -1;
						float far = -1.0f;
						for (int i = 0; i < count; i++) {
							if (alive[i] && slug[i] == s) {
								float r2 = sl_ox[i] * sl_ox[i] + sl_oy[i] * sl_oy[i];
								if (r2 > far) {
									far = r2;
									out = i;
								}
							}
						}
						if (out < 0) {
							break;
						}
						slug[out] = -1;
						kill(out, CAUSE_TEMP);
						slug_lost++;
						g.n--;
					}
				}
				float ax = slug_tx - g.x, ay = slug_ty - g.y;
				if (ax * ax + ay * ay < slug_arrive * slug_arrive) {
					// Here: the stalk cells are told off, the rest climb them.
					g.stage = 2;
					g.t = 0.0f;
					g.bx = g.x;
					g.by = g.y;
					int want = (int)std::round(g.n * slug_share), rank = 0;
					for (int i = 0; i < count && rank < want; i++) {
						if (alive[i] && slug[i] == s) {
							spore[i] = -1.0f;
							sl_ox[i] = (rank + 0.5f) / std::max(want, 1);
							rank++;
						}
					}
				}
			}
			float size = 3.0f * std::sqrt((float)g.n);
			float along = g.stage == 0 ? size : size * 2.2f;
			float ang = g.stage == 0 ? 0.0f : std::atan2(g.hy, g.hx);
			for (int i = 0; i < count; i++) {
				if (!alive[i] || slug[i] != s) {
					continue;
				}
				float ox = sl_ox[i] * along, oy = sl_oy[i] * size;
				float tx = g.x + ox * g.hx - oy * g.hy, ty = g.y + ox * g.hy + oy * g.hx;
				float mx = (tx - x[i]) * pull, my = (ty - y[i]) * pull;
				float cap = 70.0f * dt, ml = std::sqrt(mx * mx + my * my);
				if (ml > cap) {
					mx *= cap / ml;
					my *= cap / ml;
				}
				x[i] += mx;
				y[i] += my;
				vx[i] = vy[i] = 0.0f;
				if (g.stage == 1) {
					heading[i] = ang;
				}
			}
			continue;
		}
		// Rising: the stalk goes up, the rest climb to its head.
		float size = 3.0f * std::sqrt((float)g.n);
		float tall = 22.0f + size * 2.4f;
		float u = clampf(g.t / slug_rise, 0.0f, 1.0f);
		for (int i = 0; i < count; i++) {
			if (!alive[i] || slug[i] != s) {
				continue;
			}
			float tx, ty;
			if (spore[i] < 0.0f) {
				tx = g.bx;
				ty = g.by - tall * sl_ox[i] * u;
			} else {
				tx = g.bx + sl_ox[i] * size * 0.8f;
				ty = g.by - tall * u + sl_oy[i] * size * 0.8f;
			}
			x[i] += (tx - x[i]) * pull;
			y[i] += (ty - y[i]) * pull;
			vx[i] = vy[i] = 0.0f;
		}
		if (g.t >= slug_rise) {
			g.stage = 3;
			g.t = 0.0f;
			for (int i = 0; i < count; i++) {
				if (!alive[i] || slug[i] != s) {
					continue;
				}
				slug[i] = -1;
				if (spore[i] < 0.0f) {
					spore[i] = 0.0f;
					kill(i, CAUSE_STALK);
					slug_stalked++;
				} else {
					float a = rand_range(0.0f, TAU), v = rand_range(60.0f, 200.0f);
					vx[i] = std::cos(a) * v;
					vy[i] = std::sin(a) * v;
					spore[i] = slug_wait + rand_range(0.0f, 4.0f);
					g.spores++;
					slug_spored++;
				}
			}
		}
	}
}

Array SimCore::get_slugs() const {
	Array out;
	for (int s = 0; s < (int)slugs.size(); s++) {
		const Slug &g = slugs[s];
		if (g.stage >= 4) {
			continue;
		}
		Dictionary d;
		d["id"] = s;
		d["pos"] = Vector2(g.x, g.y);
		d["mid"] = Vector2(g.mx, g.my);
		d["heading"] = Vector2(g.hx, g.hy);
		d["base"] = Vector2(g.bx, g.by);
		d["n"] = g.n;
		d["stage"] = g.stage;
		d["t"] = g.t;
		d["spores"] = g.spores;
		out.push_back(d);
	}
	return out;
}

Dictionary SimCore::get_slug_stats() const {
	Dictionary d;
	int inside = 0, waiting = 0;
	for (int i = 0; i < count; i++) {
		if (alive[i]) {
			inside += slug[i] >= 0 ? 1 : 0;
			waiting += spore[i] > 0.0f ? 1 : 0;
		}
	}
	d["inside"] = inside;
	d["spores"] = waiting;
	d["formed"] = slug_formed;
	d["broke"] = slug_broke;
	d["lost"] = slug_lost;
	d["stalk"] = slug_stalked;
	d["spored"] = slug_spored;
	return d;
}

int SimCore::count_active(int s, Vector2 pos, float radius) const {
	int n = 0;
	float r2 = radius * radius;
	for (int i = 0; i < count; i++) {
		if (alive[i] && sp[i] == s && slug[i] < 0 && spore[i] <= 0.0f) {
			float dx = x[i] - pos.x, dy = y[i] - pos.y;
			n += dx * dx + dy * dy <= r2 ? 1 : 0;
		}
	}
	return n;
}

void SimCore::set_giant(Dictionary d) {
	giant_host = d.get("host", giant_host);
	giant_life = d.get("life", giant_life);
	giant_burst = d.get("burst", giant_burst);
	giant_yield = d.get("yield", giant_yield);
	giant_diffuse = d.get("diffuse", giant_diffuse);
	giant_swallow = d.get("swallow", giant_swallow);
	giant_crispr = d.get("crispr", giant_crispr);
}

int SimCore::add_giants(Vector2 pos, float radius, int n) {
	int made = 0;
	for (int k = 0; k < n && (int)giants.size() < MAX_GIANTS; k++) {
		float a = rand_range(0.0f, TAU), d = radius * std::sqrt(randf());
		float wx = pos.x + std::cos(a) * d, wy = pos.y + std::sin(a) * d;
		keep_in_dish(wx, wy, GIANT_R);
		Giant g{};
		g.x = g.px = wx;
		g.y = g.py = wy;
		g.life = giant_life * rand_range(0.7f, 1.3f);
		g.age = 2.0f;
		g.seed = next_giant++;
		giants.push_back(g);
		made++;
	}
	return made;
}

// Out of a burst cell, as a burst of phages, only slower and heavier.
void SimCore::release_giants(float wx, float wy, float r, int n) {
	for (int k = 0; k < n && (int)giants.size() < MAX_GIANTS; k++) {
		float a = rand_range(0.0f, TAU), d = r * std::sqrt(randf());
		float out = 0.6f * PHAGE_FLING * rand_range(0.5f, 1.3f);
		Giant g{};
		g.x = g.px = wx + std::cos(a) * d;
		g.y = g.py = wy + std::sin(a) * d;
		g.vx = std::cos(a) * out;
		g.vy = std::sin(a) * out;
		g.life = giant_life * rand_range(0.7f, 1.3f) + PHAGE_SPILL;
		g.age = -PHAGE_SPILL * randf();
		g.seed = next_giant++;
		giants.push_back(g);
	}
}

// A factory comes to its end. The sooner a virophage took it over, the fewer
// giants it finished and the more virophages it made instead.
void SimCore::burst_factory(int i) {
	float share = 1.0f, spare = 0.0f;
	if (hijack[i] >= 0.0f) {
		float taken = std::max(0.0f, hijack[i] + phage_burst - GIANT_SETUP) / giant_burst;
		share = clampf(taken, GIANT_MIN, 1.0f);
		spare = clampf(1.0f - taken, 0.0f, 1.0f);
	}
	float e = species[sp[i]].extent;
	float made = giant_yield * share;
	giant_saved += giant_yield * (1.0f - share);
	release_giants(x[i], y[i], e, (int)made + (randf() < made - (int)made ? 1 : 0));
	release_phages(x[i], y[i], e, (int)(phage_yield * spare));
	kill(i, CAUSE_PHAGE);
}

void SimCore::step_giants(float dt) {
	if (giant_host < 0) {
		return;
	}
	const float keep = std::exp(-dt / PHAGE_DRIFT_T);
	const float kick = std::sqrt((1.0f - keep * keep) * giant_diffuse / PHAGE_DRIFT_T) * 3.4641f;
	const float drag = std::exp(-PHAGE_FLING_DRAG * dt);
	const float take = 1.0f - std::exp(-giant_swallow * dt);
	int w = 0;
	for (int p = 0; p < (int)giants.size(); p++) {
		Giant g = giants[p];
		g.life -= dt;
		if (g.life <= 0.0f) {
			continue;
		}
		g.px = g.x;
		g.py = g.y;
		g.age += dt;
		if (g.age < 0.0f) {
			giants[w++] = g;
			continue;
		}
		int fc = nutrient_index(g.x, g.y);
		g.dx = g.dx * keep + (randf() - 0.5f) * kick;
		g.dy = g.dy * keep + (randf() - 0.5f) * kick;
		float nx = g.x + (flow_u[fc] + g.vx + g.dx) * dt;
		float ny = g.y + (flow_v[fc] + g.vy + g.dy) * dt;
		keep_in_dish(nx, ny, GIANT_R);
		for (const Barrier &b : barriers) {
			float ex = b.bx - b.ax, ey = b.by - b.ay;
			float s0 = ex * (g.y - b.ay) - ey * (g.x - b.ax), s1 = ex * (ny - b.ay) - ey * (nx - b.ax);
			if (s0 * s1 >= 0.0f) {
				continue;
			}
			float u = s0 / (s0 - s1);
			float cx = g.x + (nx - g.x) * u - b.ax, cy = g.y + (ny - g.y) * u - b.ay;
			float along = (cx * ex + cy * ey) / std::max(ex * ex + ey * ey, 1e-3f);
			if (along >= 0.0f && along <= 1.0f) {
				nx = g.x;
				ny = g.y;
				break;
			}
		}
		g.x = nx;
		g.y = ny;
		g.vx *= drag;
		g.vy *= drag;
		bool eaten = false;
		if (g.age > 1.0f) {
			int gx = (int)clampf(nx / acell, 0.0f, (float)(agw - 1)), gy = (int)clampf(ny / acell, 0.0f, (float)(agh - 1));
			for (int b = std::max(0, gy - 1); b <= std::min(agh - 1, gy + 1) && !eaten; b++) {
				for (int a = std::max(0, gx - 1); a <= std::min(agw - 1, gx + 1) && !eaten; a++) {
					for (int j = ahead[b * agw + a]; j >= 0; j = anext[j]) {
						// Only a cell out feeding takes it for food.
						if (sp[j] != giant_host || !alive[j] || inf_t[j] >= 0.0f || join[j] > 0.0f || (action[j] != ACT_SEEK_FOOD && action[j] != ACT_GRAZE)) {
							continue;
						}
						float dx = nx - x[j], dy = ny - y[j];
						float d = std::sqrt(dx * dx + dy * dy) + 1e-4f;
						if (d > cell_radius(j, dx / d, dy / d) + GIANT_R || randf() > take) {
							continue;
						}
						inf_t[j] = 0.0f;
						inf_ang[j] = std::atan2(dy, dx) - heading[j];
						inf_fate[j] = immune[j] ? 2 : (randf() < species[giant_host].crispr * giant_crispr ? 1 : 4);
						hijack[j] = g.load > 0 ? 0.0f : (carry[j] ? PHAGE_INJECT : -1.0f);
						if (inf_fate[j] == 4) {
							giant_taken++;
							giant_hijacked += hijack[j] >= 0.0f ? 1 : 0;
						}
						eaten = true;
						break;
					}
				}
			}
		}
		if (!eaten) {
			giants[w++] = g;
		}
	}
	giants.resize(w);
	std::fill(ghead.begin(), ghead.end(), -1);
	for (int g = 0; g < w; g++) {
		int c = (int)clampf(giants[g].y / acell, 0.0f, (float)(agh - 1)) * agw + (int)clampf(giants[g].x / acell, 0.0f, (float)(agw - 1));
		gnext[g] = ghead[c];
		ghead[c] = g;
	}
}

PackedVector2Array SimCore::get_giant_positions() const {
	PackedVector2Array out;
	for (const Giant &g : giants) {
		out.push_back(Vector2(g.x, g.y));
	}
	return out;
}

Dictionary SimCore::get_giant_stats() const {
	Dictionary d;
	int factories = 0, stolen = 0, carriers = 0;
	for (int i = 0; i < count; i++) {
		if (!alive[i]) {
			continue;
		}
		carriers += carry[i] ? 1 : 0;
		if (inf_t[i] >= 0.0f && inf_fate[i] == 4) {
			factories++;
			stolen += hijack[i] >= 0.0f ? 1 : 0;
		}
	}
	int loaded = 0;
	for (const Giant &g : giants) {
		loaded += g.load > 0 ? 1 : 0;
	}
	d["water"] = (int)giants.size();
	d["loaded"] = loaded;
	d["factories"] = factories;
	d["stolen"] = stolen;
	d["carriers"] = carriers;
	d["taken"] = giant_taken;
	d["hijacked"] = giant_hijacked;
	d["saved"] = (int)giant_saved;
	d["total"] = (int)giants.size() + factories;
	return d;
}

PackedFloat32Array SimCore::build_giant_buffer(Rect2 rect, float alpha, float side, int capacity) {
	PackedFloat32Array out;
	out.resize(capacity * 12);
	float *w = out.ptrw();
	std::fill(w, w + out.size(), 0.0f);
	int n = 0;
	for (const Giant &g : giants) {
		float ox = lerpf(g.px, g.x, alpha), oy = lerpf(g.py, g.y, alpha);
		if (n >= capacity || !rect.has_point(Vector2(ox, oy))) {
			continue;
		}
		w[0] = side;
		w[3] = ox;
		w[5] = side;
		w[7] = oy;
		w[8] = std::fmod(g.seed * 2.399963f, TAU);
		w[9] = g.load > 0 ? 1.0f : 0.0f;
		w[10] = clampf(g.age * 0.5f + 0.5f, 0.0f, 1.0f); // grows in as it leaves the torn cell
		w[11] = clampf(g.life, 0.0f, 1.0f) * 0.49f;
		w += 12;
		n++;
	}
	giant_drawn = n;
	return out;
}

PackedFloat32Array SimCore::get_phages(Rect2 rect, float alpha) const {
	PackedFloat32Array out;
	for (int p = 0; p < phages; p++) {
		float ox = lerpf(ph_px[p], ph_x[p], alpha), oy = lerpf(ph_py[p], ph_y[p], alpha);
		if (!rect.has_point(Vector2(ox, oy))) {
			continue;
		}
		out.push_back(ox);
		out.push_back(oy);
		out.push_back((float)ph_seed[p]);
		out.push_back(ph_age[p]);
	}
	return out;
}

PackedFloat32Array SimCore::get_infected(Rect2 rect, float alpha) const {
	PackedFloat32Array out;
	for (int i = 0; i < count; i++) {
		if (inf_t[i] < 0.0f) {
			continue;
		}
		float ox = lerpf(px[i], x[i], alpha), oy = lerpf(py[i], y[i], alpha);
		if (!rect.has_point(Vector2(ox, oy))) {
			continue;
		}
		out.push_back(ox);
		out.push_back(oy);
		out.push_back(angle_lerp(pheading[i], heading[i], alpha));
		out.push_back(ha[i]);
		out.push_back(hb[i]);
		out.push_back(inf_t[i] + alpha * last_dt); // (between ticks: the scene runs smooth)
		out.push_back(inf_ang[i]);
		out.push_back(burst_of(i));
		out.push_back((float)sp[i]);
		out.push_back(infect_swell(i, alpha));
		out.push_back((float)inf_fate[i]);
		out.push_back(hijack[i]);
	}
	return out;
}

PackedFloat32Array SimCore::get_carriers(Rect2 rect, float alpha) const {
	PackedFloat32Array out;
	for (int i = 0; i < count; i++) {
		bool latent = species[sp[i]].prophage > 0.0f || carry[i];
		if (!immune[i] && !latent) {
			continue;
		}
		float ox = lerpf(px[i], x[i], alpha), oy = lerpf(py[i], y[i], alpha);
		if (!rect.has_point(Vector2(ox, oy))) {
			continue;
		}
		out.push_back(ox);
		out.push_back(oy);
		out.push_back(angle_lerp(pheading[i], heading[i], alpha));
		out.push_back(ha[i]);
		out.push_back(hb[i]);
		out.push_back(latent ? 1.0f : 0.0f);
	}
	return out;
}

// The cell fills with new phages: it swells, slowly and then fast, and strains
// (a slow pulse, growing) just before it goes.
float SimCore::infect_swell(int i, float alpha) const {
	float t = inf_t[i] + alpha * last_dt;
	if (t < PHAGE_INJECT || !doomed(i)) {
		return 1.0f;
	}
	float u = clampf((t - PHAGE_INJECT) / (burst_of(i) - PHAGE_INJECT), 0.0f, 1.0f);
	float strain = clampf((u - 0.85f) / 0.15f, 0.0f, 1.0f);
	return 1.0f + (inf_fate[i] == 4 ? 0.34f : 0.2f) * u * u * u + 0.018f * strain * std::sin(t * 7.0f);
}

// How far an infected cell has reddened: all the way toward a burst; a cell
// beating the phage only flushes and recovers.
float SimCore::infect_tint(int i) const {
	if (doomed(i)) {
		return 0.2f + 0.75f * clampf(inf_t[i] / burst_of(i), 0.0f, 1.0f);
	}
	float len = inf_fate[i] == 1 ? PHAGE_CUT_NEW : PHAGE_CUT_OLD;
	return (inf_fate[i] == 1 ? 0.45f : 0.2f) * std::sin(clampf(inf_t[i] / len, 0.0f, 1.0f) * PI_F);
}

PackedFloat32Array SimCore::build_phage_buffer(Rect2 rect, float alpha, float side, int capacity) {
	PackedFloat32Array out;
	out.resize(capacity * 12);
	float *w = out.ptrw();
	std::fill(w, w + out.size(), 0.0f);
	int n = 0;
	for (int p = 0; p < phages && n < capacity; p++) {
		float ox = lerpf(ph_px[p], ph_x[p], alpha), oy = lerpf(ph_py[p], ph_y[p], alpha);
		if (!rect.has_point(Vector2(ox, oy))) {
			continue;
		}
		w[0] = side;
		w[3] = ox;
		w[5] = side;
		w[7] = oy;
		w[8] = std::fmod(ph_seed[p] * 2.399963f, TAU);
		w[11] = clampf(ph_life[p], 0.0f, 1.0f) * 0.49f;
		w += 12;
		n++;
	}
	phage_drawn = n;
	return out;
}

double SimCore::world_energy() const {
	double e = 0.0;
	for (int c = 0; c < gw * gh; c++) {
		e += nutrient[c];
	}
	for (int i = 0; i < count; i++) {
		e += energy[i] + body_energy(sp[i]);
	}
	for (int a = 0; a < algae; a++) {
		e += al_e[a];
	}
	for (int s = 0; s < shells; s++) {
		e += sh_e[s];
	}
	return e;
}

// --- output -----------------------------------------------------------------

Color SimCore::lineage_color(int s, int lin) const {
	// Each lineage drifts a little in hue, so branching is visible.
	const Color &c = species[s].color;
	uint32_t lh = (uint32_t)lin * 2654435761u;
	float jitter = ((lh >> 8) & 0xFFFF) / 65535.0f - 0.5f;
	return Color::from_hsv(std::fmod(c.get_h() + jitter * 0.07f + 1.0f, 1.0f),
			clampf(c.get_s() + jitter * 0.12f, 0.0f, 1.0f), c.get_v());
}

int SimCore::get_render_count() const {
	int n = algae + shells;
	for (int i = 0; i < count; i++) {
		const Species &S = species[sp[i]];
		if (S.colony || S.rotifer) {
			continue; // (scripts/colony_layer.gd and rotifer_layer.gd draw those)
		}
		n += S.body.empty() ? 1 : (int)(S.body.size() / 3) + 1;
		if (gulp_t[i] >= 0.0f) {
			n++; // the prey being digested inside it
		}
	}
	return n;
}

PackedFloat32Array SimCore::build_render_buffer(float alpha, float time, int capacity) {
	// The buffer always covers `capacity` instances (the MultiMesh's fixed
	// instance_count); slots past the visible count are left zeroed.
	PackedFloat32Array out;
	int needed = get_render_count();
	out.resize(std::max(capacity, 0) * FLOATS_PER_INSTANCE);
	float *w = out.ptrw();
	std::fill(w, w + out.size(), 0.0f);
	if (needed > capacity) {
		return out;
	}
	// Quads stay upright; custom.x = heading + 8 * phase bucket, so the shader
	// lights everything from one screen direction while shapes follow heading.
	auto put = [&](float ox, float oy, float h, float side, const Color &col, float kind, float c0, float c1, float c2, float c3) {
		float hh = std::remainder(h, TAU);
		w[0] = side;
		w[1] = 0.0f;
		w[2] = 0.0f;
		w[3] = ox;
		w[4] = 0.0f;
		w[5] = side;
		w[6] = 0.0f;
		w[7] = oy;
		w[8] = col.r;
		w[9] = col.g;
		w[10] = col.b;
		w[11] = kind;
		w[12] = hh + 8.0f * std::floor(std::fmod(std::abs(c0), 100.0f));
		w[13] = c1;
		w[14] = c2;
		w[15] = c3;
		w += FLOATS_PER_INSTANCE;
	};
	const Color algae_col(0.62f, 0.84f, 0.45f);
	for (int a = 0; a < algae; a++) {
		float rr = algae_radius(al_e[a]);
		put(lerpf(al_px[a], al_x[a], alpha), lerpf(al_py[a], al_y[a], alpha), 0.0f, rr * 5.0f, algae_col, 8.0f,
				al_ph[a], al_e[a] / ALGAE_MAX_E, 0.0f, 0.0f);
	}
	for (int s = 0; s < shells; s++) {
		float fade = clampf(sh_e[s] / std::max(sh_e0[s], 1e-3f), 0.0f, 1.0f);
		put(sh_x[s], sh_y[s], sh_h[s], sh_r[s] * 6.0f, lineage_color(sh_sp[s], sh_lineage[s]), 9.0f, sh_ph[s], fade, 0.0f, 0.0f);
	}
	for (int i = 0; i < count; i++) {
		const Species &S = species[sp[i]];
		if (S.colony || S.rotifer) {
			continue;
		}
		float ox = lerpf(px[i], x[i], alpha);
		float oy = lerpf(py[i], y[i], alpha);
		float h = angle_lerp(pheading[i], heading[i], alpha);
		if (gulp_t[i] >= 0.0f) {
			// The swallowed prey, drawn first so it sits inside the body: it
			// is drawn in through the front over 0.9 s, then shrinks, pales
			// and dissolves in a food vacuole as it is digested (state 8).
			float ts = gulp_t[i] + alpha * last_dt;
			float g = clampf(ts / DIGEST_TIME, 0.0f, 1.0f);
			float pull = clampf(ts / 0.9f, 0.0f, 1.0f);
			pull = pull * pull * (3.0f - 2.0f * pull);
			float lx = lerpf(gulp_lx[i], 0.08f * S.radius, pull);
			float ly = lerpf(gulp_ly[i], 0.0f, pull);
			float ch = std::cos(h), sh = std::sin(h);
			float shrink = 1.0f - 0.55f * clampf((g - 0.1f) / 0.9f, 0.0f, 1.0f);
			uint32_t gsig = ((uint32_t)gulp_lin[i] * 2654435761u) >> 27;
			// The organs ride on colour.r: r + 2 * mask (the shader takes it apart).
			Color gcol = lineage_color(gulp_sp[i], gulp_lin[i]);
			gcol.r += 2.0f * (float)species[gulp_sp[i]].organ_mask;
			put(ox + lx * ch - ly * sh, oy + lx * sh + ly * ch, h + gulp_h[i] * (1.0f - 0.6f * pull),
					gulp_r[i] * 6.0f * shrink, gcol, (32.0f * (float)gsig) / 4194304.0f,
					gulp_ph[i], std::min(g, 0.99f) + 8.0f * 2.0f, 0.0f, 0.0f);
		}
		float spd = std::sqrt(vx[i] * vx[i] + vy[i] * vy[i]);
		float max_speed = 18.0f + 14.0f * t_speed[i];
		float e01 = clampf(energy[i] / (S.radius * S.radius * 2.6f), 0.0f, 1.0f);
		Color col = lineage_color(sp[i], lineage[i]);
		if (S.body.empty()) {
			// kind < 1: single cell; (speed fraction in 5 bits + 32 * lineage
			// signature in 5 bits + 1024 * stroke phase in 12 bits) / 2^22, so
			// each lineage keeps its own look and the swimming stroke is the
			// kernel's own (smooth, whatever the speed does).
			// custom.y = energy (0..0.99) + 2 * state (0 idle, 1 eat, 2 hunt,
			// 3 flee, 4 bitten, 5 dividing, 6 held inside its parent, 7 biting,
			// 8 being digested (the prey instance above), 9 digesting a meal).
			// For 7 the fraction is how far the body has closed round the prey,
			// for 9 how far digestion has got, instead of energy.
			int a = action[i];
			float state = bitten[i] ? 4.0f : (a == ACT_FLEE ? 3.0f : (a == ACT_BITE ? 7.0f : (a == ACT_HUNT ? 2.0f : (a == ACT_GRAZE ? 1.0f : 0.0f))));
			float frac = std::min(e01, 0.99f);
			if (state == 7.0f) {
				frac = std::min(1.0f - std::exp(-(latch[i] + alpha * last_dt) * 0.9f), 0.99f);
			} else if (gulp_t[i] >= 0.0f && (state == 0.0f || state == 1.0f || state == 2.0f)) {
				state = 9.0f;
				frac = std::min((gulp_t[i] + alpha * last_dt) / DIGEST_TIME, 0.99f);
			}
			float split = -1.0f; // division progress 0..1 while dividing
			if (join[i] > 0.0f) {
				state = 6.0f;
			} else if (pair[i] >= 0 && join[pair[i]] > 0.0f) {
				state = 5.0f;
				// Interpolated between ticks so the scene runs smoothly.
				split = clampf(1.0f - (join[pair[i]] - alpha * last_dt) / JOIN_TIME, 0.0f, 1.0f);
			}
			uint32_t sig = ((uint32_t)lineage[i] * 2654435761u) >> 27; // 0..31
			// All six genes drive a visible part: 4 bits each in custom.z
			// (exact in a float). custom.w = diet + 2 * cohesion level (0..7)
			// + 16 * bend (0..15, 7.5 = straight) so the body curves into turns.
			auto q4 = [](float t) { return (uint32_t)clampf(std::round((t - 1.0f) / 4.0f * 15.0f), 0.0f, 15.0f); };
			uint32_t genes = q4(t_speed[i]) | q4(t_vision[i]) << 4 | q4(t_armor[i]) << 8 | q4(t_attack[i]) << 12 |
					q4(t_fertility[i]) << 16 | q4(t_efficiency[i]) << 20;
			float bend = std::round((clampf(curl[i] / 3.0f, -1.0f, 1.0f) * 0.5f + 0.5f) * 15.0f);
			// + 256 * growth (0..15, 15 = grown): newborns swell into shape.
			float growth = std::floor(clampf(age[i] / 0.9f, 0.0f, 1.0f) * 15.0f);

			// + 4096 * neural (0..15): a bigger brain shows as a ring of ganglia.
			float neural = std::round((t_neural[i] - 1.0f) / 4.0f * 15.0f);
			float social = (S.diet == DIET_PREDATOR ? 1.0f : 0.0f) + 2.0f * std::floor(clampf(S.cohesion, 0.0f, 1.0f) * 7.0f) + 16.0f * bend + 256.0f * growth + 4096.0f * neural;
			if (split >= 0.0f) {
				// While dividing .w carries the scene's progress finely instead.
				social = (S.diet == DIET_PREDATOR ? 1.0f : 0.0f) + 2.0f * std::round(split * 4000.0f);
			}
			float speedq = std::round(clampf(vs[i], 0.0f, 1.0f) * 31.0f);
			float swi = lerpf(psw[i], sw[i], alpha);
			float phq = (float)((uint32_t)(std::fmod(swi, TAU) / TAU * 4096.0f) & 4095u);
			// A dividing cell gets a 1.5x quad so both halves fit (the shader rescales).
			Color ocol = col;
			if (immune[i]) {
				ocol = ocol.lerp(MEMORY_TINT, 0.85f); // carrying the memory
			}
			if (inf_t[i] >= 0.0f) {
				// Infected: the whole cell reddens as the burst nears.
				Color sick = inf_fate[i] != 4 ? Color(0.92f, 0.22f, 0.38f) : (hijack[i] >= 0.0f ? Color(0.08f, 0.68f, 0.62f) : Color(0.52f, 0.3f, 0.82f));
				ocol = ocol.lerp(sick, infect_tint(i));
				if (inf_fate[i] == 1) {
					// The stored piece takes: the colour of the memory comes in.
					ocol = ocol.lerp(MEMORY_TINT, 0.85f * clampf((inf_t[i] - 5.0f) / 2.5f, 0.0f, 1.0f));
				}
			}
			ocol.r += 2.0f * (float)S.organ_mask;
			put(ox, oy, h, S.radius * (split >= 0.0f ? 9.0f : 6.0f) * infect_swell(i, alpha) * (spore[i] > 0.0f ? 0.5f : 1.0f), ocol, (speedq + 32.0f * (float)sig + 1024.0f * phq) / 4194304.0f,
					phase[i], frac + state * 2.0f, (float)genes, social);
		} else {
			// kind 1..6: one module of a multicell body (1 + module type);
			// kind 7: the envelope membrane around the whole body.
			float mr = S.radius * 0.34f;
			float cs = std::cos(h), sn = std::sin(h);
			int m = (int)(S.body.size() / 3);
			float wave_amp = mr * 0.14f * clampf(spd / 20.0f, 0.3f, 1.0f);
			float minx = 1e9f, maxx = -1e9f, miny = 1e9f, maxy = -1e9f;
			for (int k = 0; k < m; k++) {
				minx = std::min(minx, S.body[k * 3]);
				maxx = std::max(maxx, S.body[k * 3]);
				miny = std::min(miny, S.body[k * 3 + 1]);
				maxy = std::max(maxy, S.body[k * 3 + 1]);
			}
			// The envelope has room for module radius, wobble and the body wave,
			// so no module ever pokes out through it.
			float len = (maxx - minx) * 1.8f * mr + 4.6f * mr;
			float wid = (maxy - miny) * 1.8f * mr + 4.8f * mr + 2.0f * wave_amp;
			float bcx = (minx + maxx) * 0.5f * 1.8f * mr;
			// The envelope sways with exactly the wave that moves the modules
			// (same phase, wavelength and amplitude, same clock), so skin and
			// cells always bend the same way. In envelope-local units
			// (p in -1..1 spans len / 1.4): offset = amp * sin(phi + k * p.x).
			float half = len / 1.4f;
			float phi = std::fmod(time * 3.0f + phase[i] + 0.7f * bcx / mr, TAU);
			if (phi < 0.0f) {
				phi += TAU;
			}
			float k = 0.7f * half / mr;
			float amp_local = wave_amp / half;
			// custom: y = phi, z = aspect + 2 * round(k * 100),
			// w = bitten + 2 * round(amp * 10000).
			put(ox + bcx * cs, oy + bcx * sn, h, len / 0.7f, col, 7.0f, phase[i], phi,
					wid / len + 2.0f * std::round(k * 100.0f), (bitten[i] ? 1.0f : 0.0f) + 2.0f * std::round(amp_local * 10000.0f));
			for (int k = 0; k < m; k++) {
				float bx = S.body[k * 3] * mr * 1.8f, by = S.body[k * 3 + 1] * mr * 1.8f;
				// A travelling wave runs from head to tail while it swims (the
				// envelope above uses the same wave).
				by += std::sin(time * 3.0f + phase[i] + bx / mr * 0.7f) * wave_amp;
				float wx = ox + bx * cs - by * sn, wy = oy + bx * sn + by * cs;
				int type = (int)S.body[k * 3 + 2];
				// Flagella and jaws reach beyond the module, so their quads are larger.
				float scale = type == 1 ? 3.0f : (type == 3 ? 1.6f : 1.0f);
				put(wx, wy, h, mr * 6.0f * scale, col, 1.0f + type, phase[i] + k * 1.7f, e01,
						clampf(spd / max_speed, 0.0f, 1.0f), (float)k / std::max(1, m - 1));
			}
		}
	}
	return out;
}

PackedVector2Array SimCore::get_positions(int s) const {
	// Children still held inside a parent mid-division are not out yet.
	PackedVector2Array out;
	for (int i = 0; i < count; i++) {
		if (sp[i] == s && join[i] <= 0.0f) {
			out.push_back(Vector2(x[i], y[i]));
		}
	}
	return out;
}

PackedFloat32Array SimCore::get_signal_field(int which) const {
	const std::vector<float> &f = which ? sig_b : sig_a;
	PackedFloat32Array out;
	out.resize(gw * gh);
	for (int c = 0; c < gw * gh; c++) {
		out[c] = f[c];
	}
	return out;
}

PackedFloat32Array SimCore::get_nutrient_field() const {
	// Display copy only: two separable box-blur passes (radius 2) turn the
	// patchwork of 16 px cells into soft, rounded shapes.
	std::vector<float> a(gw * gh), b(gw * gh);
	for (int c = 0; c < gw * gh; c++) {
		a[c] = clampf(nutrient[c] / 6.0f, 0.0f, 1.0f);
	}
	const int r = 2;
	for (int pass = 0; pass < 2; pass++) {
		for (int j = 0; j < gh; j++) {
			for (int i = 0; i < gw; i++) {
				float s = 0.0f;
				for (int k = -r; k <= r; k++) {
					s += a[j * gw + std::min(std::max(i + k, 0), gw - 1)];
				}
				b[j * gw + i] = s / (2 * r + 1);
			}
		}
		for (int j = 0; j < gh; j++) {
			for (int i = 0; i < gw; i++) {
				float s = 0.0f;
				for (int k = -r; k <= r; k++) {
					s += b[std::min(std::max(j + k, 0), gh - 1) * gw + i];
				}
				a[j * gw + i] = s / (2 * r + 1);
			}
		}
	}
	PackedFloat32Array out;
	out.resize(gw * gh);
	std::copy(a.begin(), a.end(), out.ptrw());
	return out;
}

PackedFloat32Array SimCore::get_algae_field() const {
	// Display only: algae energy per field cell, blurred, scaled to 0..1.
	std::vector<float> a(gw * gh, 0.0f), b(gw * gh);
	for (int k = 0; k < algae; k++) {
		a[nutrient_index(al_x[k], al_y[k])] += al_e[k];
	}
	const int r = 3;
	for (int pass = 0; pass < 2; pass++) {
		for (int j = 0; j < gh; j++) {
			for (int i = 0; i < gw; i++) {
				float s = 0.0f;
				for (int k = -r; k <= r; k++) {
					s += a[j * gw + std::min(std::max(i + k, 0), gw - 1)];
				}
				b[j * gw + i] = s / (2 * r + 1);
			}
		}
		for (int j = 0; j < gh; j++) {
			for (int i = 0; i < gw; i++) {
				float s = 0.0f;
				for (int k = -r; k <= r; k++) {
					s += b[std::min(std::max(j + k, 0), gh - 1) * gw + i];
				}
				a[j * gw + i] = s / (2 * r + 1);
			}
		}
	}
	PackedFloat32Array out;
	out.resize(gw * gh);
	float *w = out.ptrw();
	for (int c = 0; c < gw * gh; c++) {
		w[c] = clampf(a[c] / 18.0f, 0.0f, 1.0f);
	}
	return out;
}

// Test hook: how much single cells overlap as drawn (ellipses), measured by
// brute force over neighbours (a predator engulfing its prey excluded): [pairs touching, pairs overlapping > 0.5 px,
// deepest overlap in px, deepest as a fraction of the smaller half width].
PackedFloat32Array SimCore::get_overlap_stats() const {
	float touching = 0.0f, over = 0.0f, deepest = 0.0f, deepest_rel = 0.0f;
	for (int i = 0; i < count; i++) {
		if (!alive[i] || join[i] > 0.0f || !species[sp[i]].body.empty()) {
			continue;
		}
		for (int j = i + 1; j < count; j++) {
			if (!alive[j] || join[j] > 0.0f || !species[sp[j]].body.empty()) {
				continue;
			}
			float dx = x[j] - x[i], dy = y[j] - y[i];
			float reach = ha[i] + ha[j];
			float d2 = dx * dx + dy * dy;
			if (d2 > reach * reach || d2 < 1e-6f) {
				continue;
			}
			float d = std::sqrt(d2);
			float ov = cell_radius(i, dx, dy) + cell_radius(j, -dx, -dy) - d;
			if (action[i] == ACT_BITE || action[j] == ACT_BITE) {
				continue; // engulfing is meant to close round the prey
			}
			if (ov > -0.5f) {
				touching += 1.0f;
			}
			if (ov > 0.5f) {
				over += 1.0f;
				deepest = std::max(deepest, ov);
				deepest_rel = std::max(deepest_rel, ov / std::min(hb[i], hb[j]));
			}
		}
	}
	PackedFloat32Array out;
	out.push_back(touching);
	out.push_back(over);
	out.push_back(deepest);
	out.push_back(deepest_rel);
	return out;
}

PackedFloat32Array SimCore::get_population_field() const {
	// Display only, for the population heat filter: per field cell, the
	// species colours mixed by headcount (rgb) and how crowded it is (a, 0..1),
	// blurred so herds read as soft territories.
	const int n = gw * gh;
	std::vector<float> f(n * 4, 0.0f), t(n * 4);
	for (int i = 0; i < count; i++) {
		if (!alive[i] || join[i] > 0.0f) {
			continue;
		}
		const Color &col = species[sp[i]].color;
		float *v = &f[nutrient_index(x[i], y[i]) * 4];
		v[0] += col.r;
		v[1] += col.g;
		v[2] += col.b;
		v[3] += 1.0f;
	}
	const int r = 3;
	for (int pass = 0; pass < 2; pass++) {
		for (int j = 0; j < gh; j++) {
			for (int i = 0; i < gw; i++) {
				float *o = &t[(j * gw + i) * 4];
				o[0] = o[1] = o[2] = o[3] = 0.0f;
				for (int k = -r; k <= r; k++) {
					const float *v = &f[(j * gw + std::min(std::max(i + k, 0), gw - 1)) * 4];
					o[0] += v[0]; o[1] += v[1]; o[2] += v[2]; o[3] += v[3];
				}
			}
		}
		for (int j = 0; j < gh; j++) {
			for (int i = 0; i < gw; i++) {
				float *o = &f[(j * gw + i) * 4];
				o[0] = o[1] = o[2] = o[3] = 0.0f;
				for (int k = -r; k <= r; k++) {
					const float *v = &t[(std::min(std::max(j + k, 0), gh - 1) * gw + i) * 4];
					o[0] += v[0]; o[1] += v[1]; o[2] += v[2]; o[3] += v[3];
				}
			}
		}
	}
	PackedFloat32Array out;
	out.resize(n * 4);
	float *w = out.ptrw();
	const float norm = 1.0f / ((2 * r + 1) * (2 * r + 1));
	for (int k = 0; k < n; k++) {
		const float *v = &f[k * 4];
		float m = std::max(v[3], 1e-4f);
		w[k * 4] = v[0] / m;
		w[k * 4 + 1] = v[1] / m;
		w[k * 4 + 2] = v[2] / m;
		w[k * 4 + 3] = 1.0f - std::exp(-v[3] * norm * 0.45f); // ~0.6 in a thick herd
	}
	return out;
}

PackedFloat32Array SimCore::get_light_field() const {
	PackedFloat32Array out;
	out.resize(gw * gh);
	float *w = out.ptrw();
	for (int c = 0; c < gw * gh; c++) {
		w[c] = clampf(light[c] * 400.0f / 255.0f, 0.0f, 1.0f);
	}
	return out;
}


// --- chapter 6: light from above, oxygen ---------------------------------------

void SimCore::add_light_band(float y_full, float y_dark, float power) {
	for (int j = 0; j < gh; j++) {
		float wy = (j + 0.5f) * cell;
		float t = clampf((y_dark - wy) / std::max(1.0f, y_dark - y_full), 0.0f, 1.0f);
		t = t * t * (3.0f - 2.0f * t);
		for (int i = 0; i < gw; i++) {
			if (inside_dish((i + 0.5f) * cell, wy, 0.0f)) {
				light_base[j * gw + i] += power * t;
			}
		}
	}
	rebuild_env();
}

void SimCore::set_oxygen(Dictionary p) {
	o2_on = (bool)p.get("on", true);
	o2_decay = p.get("decay", o2_decay);
	o2_diffuse = p.get("diffuse", o2_diffuse);
	o2_sulfide = p.get("sulfide", o2_sulfide);
	o2_emit = p.get("emit", o2_emit);
	o2_use = p.get("use", o2_use);
	o2_tox = p.get("tox", o2_tox);
	o2_harm = p.get("harm", o2_harm);
	o2_need = p.get("need", o2_need);
	aero_mult = p.get("aero_mult", aero_mult);
	aero_low = p.get("aero_low", aero_low);
	fac_mult = p.get("fac_mult", fac_mult);
	fac_low = p.get("fac_low", fac_low);
	fac_harm = p.get("fac_harm", fac_harm);
	iron_rate = p.get("iron", iron_rate);
	cell_graze = p.get("graze", cell_graze);
	graze_rest = p.get("graze_rest", graze_rest);
	graze_refuge = p.get("refuge", graze_refuge);
	float start = p.get("start", 0.0f);
	for (int j = 0; j < gh; j++) {
		for (int i = 0; i < gw; i++) {
			o2[j * gw + i] = inside_dish((i + 0.5f) * cell, (j + 0.5f) * cell, 0.0f) ? start : 0.0f;
		}
	}
}

int SimCore::add_iron(Vector2 pos, float radius, float seconds) {
	irons.push_back({ pos.x, pos.y, radius, 0.0f, seconds });
	return (int)irons.size() - 1;
}

void SimCore::step_oxygen(float dt) {
	if (!o2_on || gw == 0) {
		return;
	}
	const float d2 = dt; // (every tick: oxygen spreads far, faster than a smell)
	transport(o2, o2_diffuse, d2);
	// Fading, and the vents' sulfide taking it up (so the water round a vent
	// stays anoxic: a refuge).
	for (int c = 0; c < gw * gh; c++) {
		float k = o2_decay + o2_sulfide * chem[c];
		o2[c] = clampf(o2[c] * std::exp(-k * d2), 0.0f, 1.5f);
	}
	// Iron dust soaks it up where it was scattered (banded iron formations).
	for (const IronSpot &ir : irons) {
		float f = spot_fade(ir.life, ir.ttl);
		int i0 = std::max(0, (int)((ir.x - ir.r) / cell)), i1 = std::min(gw - 1, (int)((ir.x + ir.r) / cell));
		int j0 = std::max(0, (int)((ir.y - ir.r) / cell)), j1 = std::min(gh - 1, (int)((ir.y + ir.r) / cell));
		for (int j = j0; j <= j1; j++) {
			for (int i = i0; i <= i1; i++) {
				float dx = (i + 0.5f) * cell - ir.x, dy = (j + 0.5f) * cell - ir.y;
				float u = clampf((ir.r - std::sqrt(dx * dx + dy * dy)) / (ir.r * 0.4f), 0.0f, 1.0f);
				if (u > 0.0f) {
					o2[j * gw + i] *= std::exp(-iron_rate * u * f * d2);
				}
			}
		}
	}
}

// A meal's worth by how it breathes: an aerobe gets aero_mult with oxygen
// enough (need), little without; a facultative one a little less either way.
float SimCore::resp_gain(int i) const {
	const Species &S = species[sp[i]];
	if (!o2_on || S.resp <= 1) {
		return 1.0f;
	}
	float u = clampf(o2[nutrient_index(x[i], y[i])] / std::max(1e-4f, o2_need), 0.0f, 1.0f);
	return S.resp == 2 ? lerpf(aero_low, aero_mult, u) : lerpf(fac_low, fac_mult, u);
}

// Toward the most (up) or least oxygen within reach; none when it is already
// where it wants to be (an anaerobe in anoxic water stays put).
bool SimCore::o2_dir(int i, bool up, float &dx, float &dy) const {
	if (!o2_on) {
		return false;
	}
	const float here = o2[nutrient_index(x[i], y[i])];
	if (!up && here < 0.01f) {
		return false;
	}
	float best = up ? std::max(here * 1.05f, here + 0.01f) : std::min(here * 0.95f, here - 0.005f);
	bool found = false;
	const float range = 220.0f;
	for (int k = 0; k < 8; k++) {
		const float a = k * 0.785398f;
		const float cx = std::cos(a), cy = std::sin(a);
		for (float d : { range * 0.2f, range * 0.45f, range * 0.7f, range }) {
			const float sx = x[i] + cx * d, sy = y[i] + cy * d;
			if (!inside_dish(sx, sy, 10.0f)) {
				continue;
			}
			// Far water counts for a little less: the nearest good patch wins.
			float v = o2[nutrient_index(sx, sy)];
			v = up ? v * (1.0f - 0.2f * d / range) : v * (1.0f + 0.2f * d / range) + 0.002f * d / range;
			if (up ? v > best : v < best) {
				best = v;
				dx = cx;
				dy = cy;
				found = true;
			}
		}
	}
	return found;
}

PackedFloat32Array SimCore::get_o2_field() const {
	PackedFloat32Array out;
	out.resize(gw * gh);
	float *w = out.ptrw();
	for (int c = 0; c < gw * gh; c++) {
		w[c] = o2_on ? clampf(o2[c], 0.0f, 1.0f) : 0.0f;
	}
	return out;
}

float SimCore::get_o2_at(Vector2 pos) const {
	return o2_on && gw > 0 ? o2[nutrient_index(pos.x, pos.y)] : 0.0f;
}

float SimCore::get_o2_mean() const {
	if (!o2_on) {
		return 0.0f;
	}
	double sum = 0.0;
	int n = 0;
	for (int j = 0; j < gh; j++) {
		for (int i = 0; i < gw; i++) {
			if (inside_dish((i + 0.5f) * cell, (j + 0.5f) * cell, 0.0f)) {
				sum += o2[j * gw + i];
				n++;
			}
		}
	}
	return n ? (float)(sum / n) : 0.0f;
}

float SimCore::get_o2_share(float above) const {
	if (!o2_on) {
		return 0.0f;
	}
	int hit = 0, n = 0;
	for (int j = 0; j < gh; j++) {
		for (int i = 0; i < gw; i++) {
			if (inside_dish((i + 0.5f) * cell, (j + 0.5f) * cell, 0.0f)) {
				hit += o2[j * gw + i] > above ? 1 : 0;
				n++;
			}
		}
	}
	return n ? (float)hit / (float)n : 0.0f;
}


// --- chapter 6 boss: the pseudopod net ------------------------------------------

void SimCore::set_net(Dictionary p) {
	net_on = (bool)p.get("on", true);
	Vector2 c = p.get("center", Vector2(net_x, net_y));
	net_x = c.x;
	net_y = c.y;
	net_core = p.get("core", net_core);
	net_need = p.get("need", net_need);
	net_grow = p.get("grow", net_grow);
	net_shrink = p.get("shrink", net_shrink);
	net_drain = p.get("drain", net_drain);
	net_slow = p.get("slow", net_slow);
	net_use = p.get("use", net_use);
	net_top = p.get("top", 0.0f);
	float r0 = p.get("radius", 300.0f);
	for (int j = 0; j < gh; j++) {
		for (int i = 0; i < gw; i++) {
			float dx = (i + 0.5f) * cell - net_x, dy = (j + 0.5f) * cell - net_y;
			float d = std::sqrt(dx * dx + dy * dy);
			net[j * gw + i] = inside_dish((i + 0.5f) * cell, (j + 0.5f) * cell, 0.0f) ? clampf((r0 - d) / 60.0f, 0.0f, 1.0f) : 0.0f;
		}
	}
}

// How firmly the net holds here, 0..1 (thin strands do not).
float SimCore::net_at(float wx, float wy) const {
	return clampf((net[nutrient_index(wx, wy)] - 0.25f) / 0.75f, 0.0f, 1.0f);
}

void SimCore::step_net(float dt) {
	if (!net_on || gw == 0 || ++net_phase % 3) {
		return;
	}
	const float d = dt * 3.0f;
	for (int j = 0; j < gh; j++) {
		for (int i = 0; i < gw; i++) {
			const int c = j * gw + i;
			const float wx = (i + 0.5f) * cell, wy = (j + 0.5f) * cell;
			if (!inside_dish(wx, wy, 6.0f) || wy < net_top) {
				net_tmp[c] = 0.0f;
				continue;
			}
			const float dx = wx - net_x, dy = wy - net_y;
			if (dx * dx + dy * dy < net_core * net_core) {
				net_tmp[c] = 1.0f; // (its body: always there)
				continue;
			}
			float n = net[c];
			float nb = 0.0f;
			if (i > 0) {
				nb = std::max(nb, net[c - 1]);
			}
			if (i + 1 < gw) {
				nb = std::max(nb, net[c + 1]);
			}
			if (j > 0) {
				nb = std::max(nb, net[c - gw]);
			}
			if (j + 1 < gh) {
				nb = std::max(nb, net[c + gw]);
			}
			// Oxygen to spare: it reaches out from where it already is; too
			// little: the pseudopods there are drawn back in.
			const float o = o2_on ? o2[c] : 1.0f;
			const float ok = clampf((o - net_need) / (net_need * 0.5f), -1.0f, 1.0f);
			if (ok > 0.0f) {
				n += net_grow * d * ok * std::max(nb, n);
			} else {
				n += net_shrink * d * ok;
			}
			net_tmp[c] = clampf(n, 0.0f, 1.0f);
		}
	}
	net.swap(net_tmp);
	// It breathes where it lies.
	if (o2_on) {
		for (int c = 0; c < gw * gh; c++) {
			if (net[c] > 0.0f) {
				o2[c] = std::max(0.0f, o2[c] - net_use * net[c] * d);
			}
		}
	}
}

PackedFloat32Array SimCore::get_net_field() const {
	PackedFloat32Array out;
	out.resize(gw * gh);
	float *w = out.ptrw();
	for (int c = 0; c < gw * gh; c++) {
		w[c] = net_on ? net[c] : 0.0f;
	}
	return out;
}

Dictionary SimCore::get_net_stats() const {
	Dictionary d;
	int hit = 0, n = 0;
	if (net_on) {
		for (int j = 0; j < gh; j++) {
			for (int i = 0; i < gw; i++) {
				if (inside_dish((i + 0.5f) * cell, (j + 0.5f) * cell, 0.0f)) {
					hit += net[j * gw + i] > 0.5f ? 1 : 0;
					n++;
				}
			}
		}
	}
	d["coverage"] = n ? (float)hit / (float)n : 0.0f;
	d["caught"] = net_caught;
	d["fed"] = net_fed;
	d["center"] = Vector2(net_x, net_y);
	return d;
}

Dictionary SimCore::get_stats() const {
	Dictionary d;
	Array per;
	for (const Species &S : species) {
		Dictionary s;
		s["alive"] = S.alive;
		s["births"] = S.births;
		s["starved"] = S.deaths_starve;
		s["eaten"] = S.deaths_eaten;
		s["aged"] = S.deaths_age;
		s["temp"] = S.deaths_temp;
		s["acid"] = S.deaths_acid;
		s["phage"] = S.deaths_phage;
		s["stalk"] = S.deaths_stalk;
		s["hatched"] = S.deaths_hatch;
		int carriers = 0;
		for (int i = 0; i < count; i++) {
			carriers += alive[i] && immune[i] && &species[sp[i]] == &S ? 1 : 0;
		}
		s["immune"] = carriers;
		s["burn_total"] = S.burn_total;
		s["burn_temp"] = S.burn_temp;
		s["burn_acid"] = S.burn_acid;
		s["o2"] = S.deaths_o2;
		s["burn_o2"] = S.burn_o2;
		per.push_back(s);
	}
	double e_org = 0.0, e_alg = 0.0, e_sh = 0.0, e_nut = 0.0;
	for (int i = 0; i < count; i++) {
		e_org += energy[i] + body_energy(sp[i]);
	}
	for (int a = 0; a < algae; a++) {
		e_alg += al_e[a];
	}
	for (int s = 0; s < shells; s++) {
		e_sh += sh_e[s];
	}
	for (float v : nutrient) {
		e_nut += v;
	}
	d["species"] = per;
	d["count"] = count;
	d["algae"] = algae;
	d["shells"] = shells;
	d["time"] = sim_time;
	d["lineages"] = next_lineage - 1;
	d["energy_organisms"] = e_org;
	d["energy_algae"] = e_alg;
	d["energy_shells"] = e_sh;
	d["energy_nutrient"] = e_nut;
	if (o2_on) {
		d["o2_mean"] = get_o2_mean();
		d["o2_made"] = o2_made;
		d["o2_breathed"] = o2_breathed;
	}
	return d;
}

Dictionary SimCore::energy_audit() const {
	Dictionary d;
	double now = world_energy();
	double expected = energy_in - energy_out;
	d["world"] = now;
	d["input"] = energy_in;
	d["dissipated"] = energy_out;
	d["expected"] = expected;
	d["error"] = now - expected;
	d["relative_error"] = std::abs(now - expected) / std::max(1.0, std::abs(expected));
	return d;
}

int SimCore::find_agent(Vector2 pos, float radius) const {
	int best = -1;
	float bd = radius * radius;
	for (int i = 0; i < count; i++) {
		if (join[i] > 0.0f) {
			continue; // still inside its parent
		}
		float dx = x[i] - pos.x, dy = y[i] - pos.y;
		float rr = species[sp[i]].radius;
		float d2 = dx * dx + dy * dy - rr * rr;
		if (d2 < bd) {
			bd = d2;
			best = id[i];
		}
	}
	return best;
}

Dictionary SimCore::get_agent(int agent_id) const {
	Dictionary d;
	for (int i = 0; i < count; i++) {
		if (id[i] != agent_id) {
			continue;
		}
		const Species &S = species[sp[i]];
		d["id"] = id[i];
		d["species"] = sp[i];
		d["position"] = Vector2(x[i], y[i]);
		d["prev_position"] = Vector2(px[i], py[i]); // last tick (drawing interpolates between)
		d["radius"] = S.radius;
		d["heading"] = heading[i];
		d["speed"] = std::sqrt(vx[i] * vx[i] + vy[i] * vy[i]);
		d["energy"] = energy[i];
		d["divide_at"] = divide_energy(i);
		d["fed"] = energy[i] >= (float)d["divide_at"];
		d["body"] = body_energy(sp[i]);
		d["age"] = age[i];
		d["lifespan"] = S.lifespan * (0.85f + 0.06f * t_efficiency[i]);
		d["generation"] = gen[i];
		d["lineage"] = lineage[i];
		d["action"] = (int)action[i];
		d["target"] = target[i];
		d["diet"] = S.diet;
		// Division scene: progress 0..1 while this one is parting in two, else -1.
		d["dividing"] = (pair[i] >= 0 && join[pair[i]] > 0.0f) ? 1.0f - join[pair[i]] / JOIN_TIME : -1.0f;
		PackedFloat32Array genes;
		genes.push_back(t_speed[i]);
		genes.push_back(t_vision[i]);
		genes.push_back(t_armor[i]);
		genes.push_back(t_attack[i]);
		genes.push_back(t_fertility[i]);
		genes.push_back(t_efficiency[i]);
		genes.push_back(t_neural[i]);
		genes.push_back(t_ttol[i]);
		d["genes"] = genes;
		// Its water and how well it suits it.
		int ec = nutrient_index(x[i], y[i]);
		d["temp"] = temp[ec];
		d["temp_opt"] = t_topt[i];
		d["temp_band"] = band_for(t_ttol[i]);
		d["acid"] = acid[ec];
		d["radiation"] = rad[ec];
		d["signal_a"] = sig_a[ec];
		d["signal_b"] = sig_b[ec];
		d["stress_temp"] = stress_t[i];
		d["stress_acid"] = stress_a[i];
		d["slots"] = slots_for(t_neural[i]);
		d["fired"] = (int)fired[i];
		d["state"] = (int)state[i];
		d["state_time"] = st_time[i];
		// The deck with, for each card, which condition held and whether the
		// action was possible this tick: "why this card, why not the others".
		Array deck;
		for (int k = 0; k < ncards[i]; k++) {
			const Card &cd = cards[i * MAX_CARDS + k];
			Dictionary cdict = card_to(cd);
			cdict["ok1"] = cond_ok(i, cd, 0);
			cdict["ok2"] = cond_ok(i, cd, 1);
			cdict["possible"] = act_possible(i, cd.act);
			deck.push_back(cdict);
		}
		d["deck"] = deck;
		d["energy_frac"] = energy[i] / divide_energy(i);
		d["threat_distance"] = (sense[i] & S_THREAT) ? threat_d[i] : -1.0f;
		d["crowd"] = (int)crowd[i];
		d["infected"] = doomed(i) ? inf_t[i] : -1.0f;
		d["immune"] = immune[i] != 0;
		d["cutting"] = inf_t[i] >= 0.0f && !doomed(i);
		d["cut_t"] = inf_t[i];
		d["latent"] = species[sp[i]].prophage > 0.0f || carry[i];
		d["woken"] = inf_t[i] >= 0.0f && inf_fate[i] == 3;
		d["burst_in"] = burst_of(i) - inf_t[i];
		d["slug"] = slug[i] >= 0;
		d["spore_in"] = spore[i] > 0.0f ? spore[i] : -1.0f;
		d["factory"] = inf_t[i] >= 0.0f && inf_fate[i] == 4;
		d["hijacked"] = hijack[i] >= 0.0f;
		d["sense"] = (int)sense[i];
		break;
	}
	return d;
}

void SimCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "world_size", "seed"), &SimCore::setup);
	ClassDB::bind_method(D_METHOD("add_species", "params"), &SimCore::add_species);
	ClassDB::bind_method(D_METHOD("set_dish", "center", "radius"), &SimCore::set_dish);
	ClassDB::bind_method(D_METHOD("add_light", "pos", "radius", "power"), &SimCore::add_light);
	ClassDB::bind_method(D_METHOD("add_light_band", "y_full", "y_dark", "power"), &SimCore::add_light_band);
	ClassDB::bind_method(D_METHOD("set_oxygen", "params"), &SimCore::set_oxygen);
	ClassDB::bind_method(D_METHOD("set_net", "params"), &SimCore::set_net);
	ClassDB::bind_method(D_METHOD("get_net_field"), &SimCore::get_net_field);
	ClassDB::bind_method(D_METHOD("get_net_stats"), &SimCore::get_net_stats);
	ClassDB::bind_method(D_METHOD("add_iron", "pos", "radius", "seconds"), &SimCore::add_iron);
	ClassDB::bind_method(D_METHOD("get_o2_field"), &SimCore::get_o2_field);
	ClassDB::bind_method(D_METHOD("get_o2_at", "pos"), &SimCore::get_o2_at);
	ClassDB::bind_method(D_METHOD("get_o2_mean"), &SimCore::get_o2_mean);
	ClassDB::bind_method(D_METHOD("get_o2_share", "above"), &SimCore::get_o2_share);
	ClassDB::bind_method(D_METHOD("set_base_environment", "params"), &SimCore::set_base_environment);
	ClassDB::bind_method(D_METHOD("add_zone", "params"), &SimCore::add_zone);
	ClassDB::bind_method(D_METHOD("get_zones"), &SimCore::get_zones);
	ClassDB::bind_method(D_METHOD("get_env_field"), &SimCore::get_env_field);
	ClassDB::bind_method(D_METHOD("get_env_at", "pos"), &SimCore::get_env_at);
	ClassDB::bind_method(D_METHOD("seed_algae", "count", "energy_each", "dark"), &SimCore::seed_algae, DEFVAL(0.02f));
	ClassDB::bind_method(D_METHOD("set_max_threads", "n"), &SimCore::set_max_threads);
	ClassDB::bind_method(D_METHOD("set_algae_cap", "count"), &SimCore::set_algae_cap);
	ClassDB::bind_method(D_METHOD("set_algae_rates", "growth", "upkeep"), &SimCore::set_algae_rates);
	ClassDB::bind_method(D_METHOD("set_flow_scale", "scale"), &SimCore::set_flow_scale);
	ClassDB::bind_method(D_METHOD("get_flow_scale"), &SimCore::get_flow_scale);
	ClassDB::bind_method(D_METHOD("add_nutrient", "pos", "radius", "amount"), &SimCore::add_nutrient);
	ClassDB::bind_method(D_METHOD("add_algae_patch", "pos", "radius", "n", "each"), &SimCore::add_algae_patch);
	ClassDB::bind_method(D_METHOD("light_pulse", "pos", "radius", "power", "seconds"), &SimCore::light_pulse);
	ClassDB::bind_method(D_METHOD("set_algae_tough", "tough"), &SimCore::set_algae_tough);
	ClassDB::bind_method(D_METHOD("set_phage", "params"), &SimCore::set_phage);
	ClassDB::bind_method(D_METHOD("add_phages", "pos", "radius", "n"), &SimCore::add_phages);
	ClassDB::bind_method(D_METHOD("get_phage_count"), &SimCore::get_phage_count);
	ClassDB::bind_method(D_METHOD("get_phages", "rect", "alpha"), &SimCore::get_phages);
	ClassDB::bind_method(D_METHOD("get_infected", "rect", "alpha"), &SimCore::get_infected);
	ClassDB::bind_method(D_METHOD("get_carriers", "rect", "alpha"), &SimCore::get_carriers);
	ClassDB::bind_method(D_METHOD("build_phage_buffer", "rect", "alpha", "side", "capacity"), &SimCore::build_phage_buffer);
	ClassDB::bind_method(D_METHOD("get_phage_drawn"), &SimCore::get_phage_drawn);
	ClassDB::bind_method(D_METHOD("set_slug", "params"), &SimCore::set_slug);
	ClassDB::bind_method(D_METHOD("get_slugs"), &SimCore::get_slugs);
	ClassDB::bind_method(D_METHOD("get_slug_stats"), &SimCore::get_slug_stats);
	ClassDB::bind_method(D_METHOD("set_colony", "params"), &SimCore::set_colony);
	ClassDB::bind_method(D_METHOD("set_rot_rage", "r"), &SimCore::set_rot_rage);
	ClassDB::bind_method(D_METHOD("irritate", "pos", "radius"), &SimCore::irritate);
	ClassDB::bind_method(D_METHOD("get_rotifer_retract"), &SimCore::get_rotifer_retract);
	ClassDB::bind_method(D_METHOD("get_rot_rage"), &SimCore::get_rot_rage);
	ClassDB::bind_method(D_METHOD("get_colony_stats"), &SimCore::get_colony_stats);
	ClassDB::bind_method(D_METHOD("get_colonies"), &SimCore::get_colonies);
	ClassDB::bind_method(D_METHOD("get_worn", "alpha"), &SimCore::get_worn);
	ClassDB::bind_method(D_METHOD("build_colony_blocks", "rect", "alpha", "time", "capacity"), &SimCore::build_colony_blocks);
	ClassDB::bind_method(D_METHOD("build_colony_skins", "species", "rect", "alpha", "capacity"), &SimCore::build_colony_skins);
	ClassDB::bind_method(D_METHOD("get_colony_drawn"), &SimCore::get_colony_drawn);
	ClassDB::bind_method(D_METHOD("count_active", "species", "pos", "radius"), &SimCore::count_active);
	ClassDB::bind_method(D_METHOD("set_giant", "params"), &SimCore::set_giant);
	ClassDB::bind_method(D_METHOD("add_giants", "pos", "radius", "n"), &SimCore::add_giants);
	ClassDB::bind_method(D_METHOD("get_giant_stats"), &SimCore::get_giant_stats);
	ClassDB::bind_method(D_METHOD("get_giant_positions"), &SimCore::get_giant_positions);
	ClassDB::bind_method(D_METHOD("build_giant_buffer", "rect", "alpha", "side", "capacity"), &SimCore::build_giant_buffer);
	ClassDB::bind_method(D_METHOD("get_giant_drawn"), &SimCore::get_giant_drawn);
	ClassDB::bind_method(D_METHOD("spawn", "species", "pos", "count", "spread"), &SimCore::spawn);
	ClassDB::bind_method(D_METHOD("step", "dt"), &SimCore::step);
	ClassDB::bind_method(D_METHOD("get_count"), &SimCore::get_count);
	ClassDB::bind_method(D_METHOD("get_algae_count"), &SimCore::get_algae_count);
	ClassDB::bind_method(D_METHOD("get_shell_count"), &SimCore::get_shell_count);
	ClassDB::bind_method(D_METHOD("get_time"), &SimCore::get_time);
	ClassDB::bind_method(D_METHOD("get_grid_size"), &SimCore::get_grid_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &SimCore::get_cell_size);
	ClassDB::bind_method(D_METHOD("build_render_buffer", "alpha", "time", "capacity"), &SimCore::build_render_buffer);
	ClassDB::bind_method(D_METHOD("get_render_count"), &SimCore::get_render_count);
	ClassDB::bind_method(D_METHOD("get_positions", "species"), &SimCore::get_positions);
	ClassDB::bind_method(D_METHOD("get_nutrient_field"), &SimCore::get_nutrient_field);
	ClassDB::bind_method(D_METHOD("get_signal_field", "which"), &SimCore::get_signal_field);
	ClassDB::bind_method(D_METHOD("get_population_field"), &SimCore::get_population_field);
	ClassDB::bind_method(D_METHOD("get_overlap_stats"), &SimCore::get_overlap_stats);
	ClassDB::bind_method(D_METHOD("add_barrier", "a", "b", "seconds"), &SimCore::add_barrier);
	ClassDB::bind_method(D_METHOD("add_temp_spot", "pos", "radius", "delta", "seconds"), &SimCore::add_temp_spot);
	ClassDB::bind_method(D_METHOD("add_current", "pos", "radius", "velocity", "seconds"), &SimCore::add_current);
	ClassDB::bind_method(D_METHOD("get_interventions"), &SimCore::get_interventions);
	ClassDB::bind_method(D_METHOD("get_light_field"), &SimCore::get_light_field);
	ClassDB::bind_method(D_METHOD("get_stats"), &SimCore::get_stats);
	ClassDB::bind_method(D_METHOD("energy_audit"), &SimCore::energy_audit);
	ClassDB::bind_method(D_METHOD("find_agent", "pos", "radius"), &SimCore::find_agent);
	ClassDB::bind_method(D_METHOD("get_agent", "agent_id"), &SimCore::get_agent);
	ClassDB::bind_method(D_METHOD("get_profile"), &SimCore::get_profile);
	ClassDB::bind_method(D_METHOD("take_events"), &SimCore::take_events);
	ClassDB::bind_method(D_METHOD("get_analysis", "rect", "alpha"), &SimCore::get_analysis);
	ClassDB::bind_method(D_METHOD("get_marks", "rect", "alpha"), &SimCore::get_marks);
	ClassDB::bind_method(D_METHOD("build_analysis_buffer", "rect", "alpha", "capacity"), &SimCore::build_analysis_buffer);
	ClassDB::bind_method(D_METHOD("get_analysis_count"), &SimCore::get_analysis_count);
	ClassDB::bind_method(D_METHOD("get_analysis_lines", "rect", "alpha"), &SimCore::get_analysis_lines);
	ClassDB::bind_method(D_METHOD("get_species_deck", "species"), &SimCore::get_species_deck);
	ClassDB::bind_method(D_METHOD("get_algae_field"), &SimCore::get_algae_field);
	BIND_CONSTANT(MAX_AGENTS);
	BIND_CONSTANT(MAX_ALGAE);
	BIND_CONSTANT(MAX_SHELLS);
	BIND_ENUM_CONSTANT(EV_BIRTH);
	BIND_ENUM_CONSTANT(EV_MUTATION);
	BIND_ENUM_CONSTANT(EV_EATEN);
	BIND_ENUM_CONSTANT(EV_DIED);
	BIND_ENUM_CONSTANT(EV_BITE);
	BIND_ENUM_CONSTANT(EV_GRAZE);
	BIND_ENUM_CONSTANT(EV_LYSIS);
	BIND_ENUM_CONSTANT(EV_IMMUNE);
	BIND_ENUM_CONSTANT(EV_HATCH);
	BIND_ENUM_CONSTANT(EV_GRIT);
	BIND_ENUM_CONSTANT(EV_CBITE);
	ClassDB::bind_method(D_METHOD("get_rotifers", "alpha"), &SimCore::get_rotifers);
	ClassDB::bind_method(D_METHOD("get_rotifer_stats"), &SimCore::get_rotifer_stats);
}
