#pragma once

// SimCore: the life simulation kernel (GDD section 3 / 14).
// Organisms, algae clumps and empty shells live in structure-of-arrays
// storage, neighbours come from uniform grids, and every unit of energy is
// accounted for: the world total must always equal what was put in minus what
// was dissipated (see energy_audit()).
//
// Energy pools: organism energy + body (a fixed structural store per species),
// algae, shells, dissolved nutrient. Inputs: light (taken up by algae), new
// organisms, interventions. Outputs: metabolism, digestion and division losses.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cstdint>
#include <vector>

namespace godot {

class SimCore : public RefCounted {
	GDCLASS(SimCore, RefCounted)

public:
	static constexpr int MAX_AGENTS = 4096;
	static constexpr int MAX_ALGAE = 2000;
	static constexpr int MAX_SHELLS = 1000;
	static constexpr int MAX_PHAGES = 5000;
	static constexpr int MAX_GIANTS = 800;
	static constexpr int FLOATS_PER_INSTANCE = 16; // Transform2D(8) + Color(4) + Custom(4)

	// Chemosynthetic cells live on the vents' chemical energy (like algae on
	// light), sharing it with their neighbours; they eat nothing.
	// Chapter 6: photosynthetic producers (the 光合膜 organ) live on light and
	// give off oxygen; grazers there eat them, as they would algae.
	enum Diet { DIET_GRAZER = 0, DIET_PREDATOR = 1, DIET_CHEMO = 2, DIET_PHOTO = 3 };
	// Event stream for visual effects: (type, x, y, species, a, b) per event.
	enum Event {
		EV_BIRTH = 0,   // a, b = parent position
		EV_MUTATION,    // a birth whose child carries a new mutation
		EV_EATEN,       // a = body extent, b = heading
		EV_DIED,        // starved or old age (a shell is left)
		EV_BITE,        // a, b = predator position
		EV_GRAZE,       // at the clump; a, b = grazer position
		EV_LYSIS,       // a cell burst by phages; a = body extent, b = heading
		EV_IMMUNE,      // a cell cut up a phage and kept a piece of it
		EV_HATCH,       // a young colony left its parent; a, b = parent position
		EV_GRIT,        // grit struck a block; a = 1 if it killed an embryo
		EV_CBITE,       // a hunter bit a colony's block; a = 1 if armour took it, b = the hunter's bearing from it
	};
	// What an organism is doing this tick (shown on the inspection card).
	enum Action {
		ACT_WANDER = 0,
		ACT_SEEK_FOOD,
		ACT_GRAZE,
		ACT_HUNT,
		ACT_BITE,
		ACT_FLEE,
		ACT_SCAVENGE,
		ACT_REST,
		ACT_DIVIDE,
		ACT_FOLLOW,
		ACT_SIGNAL,  // releasing signal A or B
		ACT_COMFORT, // swimming toward water of its own temperature
		ACT_TRACK,   // following a smell (signal A or B) up to where it is strongest
		ACT_DISPERSE, // swimming away from the peers around it
		ACT_SLUG,     // part of a crawling aggregate
		ACT_AIR,      // swimming away from oxygen, or toward it (chapter 6)
		ACT_HOME,     // going back to the spot it remembers (chapter 7)
		ACT_SPORE,    // forming a spore, a spore, or germinating (chapter 7)
	};

	// Behaviour cards (GDD 3.2). Each organism carries its own deck, checked
	// top to bottom every tick: the first card whose conditions hold and whose
	// action is possible right now is carried out; none -> wander. Decks are
	// inherited on division and mutate. Ids are stable: scripts/rules.gd
	// names them in the same order.
	enum Cond : uint8_t {
		C_NONE = 0,
		C_ENERGY_BELOW,  // energy / division energy < t (0..1.5)
		C_ENERGY_ABOVE,  // energy / division energy > t
		C_SEE_ALGAE,     // an algae clump in sight
		C_PREDATOR_NEAR, // a predator closer than t (world units)
		C_SEE_PREY,      // something it can eat in sight
		C_CROWD,         // at least t of its own kind nearby
		C_ATTACKED,      // bitten within the last 2 s
		C_AGE_ABOVE,     // age / lifespan > t
		C_SEE_SHELL,     // an empty shell in sight
		C_TEMP_BAD,      // the water is outside its comfortable band
		C_SIGNAL_A,      // signal A here above t
		C_SIGNAL_B,      // signal B here above t
		C_PREY_NEAR,     // prey in sight closer than t (world units)
		C_PREY_SMALL,    // prey in sight whose size is under t of its own (0..1)
		C_STATE_TIME,    // in its current state for more than t seconds
		C_PEER_STATE,    // a peer in sight is in state t (needs the recognition protein)
		C_IMMUNE,        // carries a memory of the phage (level 16; needs the memory fragment)
		C_O2_ABOVE,      // oxygen here above t (0..1 of full; chapter 6)
		C_FAR_MEM,       // further than t from the spot it remembers (chapter 7; needs the memory vesicle)
		C_NIGHT,         // the long night is on (chapter 7)
		C_DAY,           // it is day
		C_SYMB,          // carries an endosymbiont (chapter 8; needs the phagosome)
		C_RIVAL_NEAR,    // a cell of another species closer than t (chapter 8)
		C_COUNT,
	};
	enum Act : uint8_t {
		A_SEEK_ALGAE = 0,
		A_FLEE,
		A_HUNT,
		A_FOLLOW,
		A_REST,
		A_DIVIDE,
		A_WANDER,
		A_SCAVENGE,
		A_EMIT_A,        // release signal A (costs a little energy)
		A_EMIT_B,
		A_SEEK_COMFORT,  // follow the temperature gradient toward its optimum
		A_TO_FORAGE,     // switch state (DECISIONS 第十一轮): forage / alert / breed / sleep
		A_TO_ALERT,
		A_TO_BREED,
		A_TO_SLEEP,
		A_SEEK_SIG_A,    // swim up the smell of signal A (needs the chemoreceptor)
		A_SEEK_SIG_B,
		A_SECRETE,       // release digestive enzyme (eats as it secretes; costs a little)
		A_DISPERSE,      // swim away from the peers around it (level 15)
		A_INDUCE,        // wake the phage in its own genes: it dies of it, and its phages go for the others (level 17)
		A_AGGREGATE,     // join the peers around it in one body that crawls as one (level 20)
		A_AVOID_O2,      // swim toward the least oxygen in reach (chapter 6)
		A_SEEK_O2,       // swim toward the most oxygen in reach
		A_REMEMBER,      // remember this spot (chapter 7; passes to the daughters)
		A_RETURN,        // swim back to the spot it remembers, along the ice where it blocks
		A_TO_SPORE,      // switch to the spore state (chapter 7; needs the spore coat)
		A_SWALLOW,       // swallow a symbiont cell without digesting it (chapter 8; needs the phagosome)
		A_TOXIN_A,       // release toxin A round itself (chapter 8; needs the toxin gland)
		A_TOXIN_B,
		A_COUNT,
	};
	static constexpr int MAX_CARDS = 8;
	// S_SPORE (chapter 7): the first SPORE_FORM seconds it forms (and is as
	// open to harm as ever), then it is a spore: no cost, no ageing, no cold,
	// not food; leaving, it germinates for SPORE_GERM seconds before it moves.
	enum State : uint8_t { S_FORAGE = 0, S_ALERT, S_BREED, S_SLEEP, S_SPORE, S_COUNT };
	static constexpr float JOIN_TIME = 2.0f;
	float last_dt = 1.0f / 15.0f; // the last tick, to interpolate the division scene
	struct Card {
		uint8_t c[2] = { C_NONE, C_NONE };
		float t[2] = { 0.0f, 0.0f };
		uint8_t act = A_WANDER;
		uint8_t st = 0;    // the state this card belongs to (S_FORAGE..S_SLEEP)
		uint8_t neg = 0;   // bit k: condition k is negated ("不")
		bool any = false;  // the two conditions are joined by "或", not "且"
	};
	// What an organism sensed this tick, kept per organism for explanations.
	enum Sense : uint8_t {
		S_ALGAE = 1,
		S_PREY = 2,
		S_SHELL = 4,
		S_THREAT = 8,
		S_ATTACKED = 16,
	};

	struct Species {
		Color color;
		int diet = DIET_GRAZER;
		float radius = 6.0f;
		float speed = 2.5f;
		float vision = 2.5f;
		float armor = 1.0f;
		float attack = 1.0f;
		float fertility = 2.5f;
		float efficiency = 2.5f;
		float lifespan = 90.0f;
		float cohesion = 0.0f;
		float size_factor = 1.0f; // (radius / 6)^0.75, for metabolism
		float extent = 6.0f;      // collision radius: matches the drawn body
		// Multicell envelope as an ellipse: half length / half width and the
		// centre's offset along the heading (all 0 for single cells).
		float half_len = 0.0f, half_wid = 0.0f, center_off = 0.0f;
		// Multicell body: (x, y, module type) in module units. Empty = single cell.
		std::vector<float> body;
		// Level 21: a body the player built from blocks (Volvox). `body` holds
		// them centred, in blocks (type 1 flagellum, 6 germ); the balance comes
		// worked out from scripts/colony.gd.
		bool colony = false;
		float col_speed = 0.0f, col_turn = 1.0f, col_bite = 1.0f, col_keep = 1.0f, col_e = 100.0f, col_skin = 100.0f;
		std::vector<uint8_t> col_rim; // per block: open water on bit 0 front, 1 back, 2 +y, 3 -y
		std::vector<int> col_germ;    // which blocks are germ blocks
		std::vector<uint8_t> col_kind; // per block, as the shader draws it: 0 flagellum, 1 germ, 3 armour, 4 store, 5 regeneration
		int col_store = 0;            // level 22: how many store blocks
		int col_rimflags = 0;         // flagellum blocks on the rim (what pushes)
		// Level 24: the vent guardian, a rotifer. Its corona of cilia pulls the
		// water (and colonies) in ahead of it; what is swallowed is chewed, and
		// a body with enough armour is spat out, hurt; it grows wilder as it
		// starves. rot_full = the energy it counts as fed.
		bool rotifer = false;
		float rot_reach = 260.0f, rot_pull = 70.0f, rot_cone = 0.85f, rot_chew = 3.0f, rot_full = 3000.0f, rot_fury = 1.0f, rot_gain = 1.0f;
		int rot_spit = 3;
		int rot_bruise = 2; // soft rim blocks crushed in what it spits out (-1: all of them)
		float rot_wear = 0.0f; // wear one armour block takes in what it spits out (1: cracked through)
		float rot_spurn = 0.0f; // seconds it leaves alone what it has just spat out (none once raging)
		float rot_cost = 0.0f; // share of its energy bar each wasted chew (a spit) costs it
		float rot_rage_gain = 1.0f; // raging, what a meal is worth to it (too far gone to recover)
		float rot_rage_spurn = 0.0f; // raging, seconds it leaves alone what it spat
		std::vector<int> col_nb;      // level 23: each block's four neighbours (-1: none), 4 per block
		float neural = 3.0f;
		float temp_opt = 14.0f; // preferred water temperature (deg C)
		float temp_tol = 2.5f;  // tolerance level 1..5: band = 3 + 4 (tol - 1) deg
		bool mutates = true;     // natural mutation on (a designer switch, chapter 1 level 4)
		// Pieces mutation may use (bit per Cond / Act): the level's unlocked
		// ones, so a mutant never shows a piece the player has not met.
		uint32_t cond_mask = 0xFFFFFFFFu, act_mask = 0xFFFFFFFFu;
		bool logic = true;       // mutation may flip 不 / 且↔或 (open from level 7)
		int keep_act = -1;       // cards with this action stay as designed (level 15: selection against spreading out would undo the lesson)
		// Armour organs (level 7): bites on it are scaled (silica shell 0.5),
		// it swims slower (0.85), and biting it hurts the hunter (spines).
		float bite_taken = 1.0f, speed_mult = 1.0f, spines = 0.0f;
		float digest_time = 6.0f; // rest after a kill (a boss barely stops)
		float crispr = 0.0f; // chance a first infection is cut up and remembered (level 16)
		float prophage = 0.0f; // carries a phage in its genes: chance per second it wakes at full stress (level 17)
		float engulf = 0.0f; // a boss: swallows every smaller cell its body touches
		float burn = 1.0f; // base metabolism multiplier (a boss runs hot)
		float confuse = 1.0f; // a hunter: how badly a crowd of prey throws its aim off
		float herd = 0.0f; // a hunter: prey among this many of its own kind or more cannot be singled out (0 = off)
		// Motor organ (level 9): flagellum = fast straight, slow to turn,
		// dear to run; cilia = nimble, cheap, can hover, slower.
		float motor_speed = 1.0f, turn_mult = 1.0f, move_cost = 1.0f, rest_cost = 1.0f;
		float store = 0.0f; // storage granules (level 8): thriftier, slower to divide
		int organ_mask = 0; // installed organs, bit k = Organs.LIST[k]: drawn on the cells
		// Chapter 6 respiration: 0 none (oxygen means nothing: every earlier
		// level), 1 anaerobic (oxygen poisons it), 2 aerobic (food yields far
		// more with oxygen, little without), 3 facultative (both, each a little worse).
		int resp = 0;
		float slow_divide = 1.0f; // chapter 7 (寿命): a long life divides this much dearer
		// Chapter 8: a decomposer (分解酶) eats shells for food and gives this
		// share of what it takes back to the water at once; a phagocyte (吞噬泡)
		// can swallow a symbiont; a symbiont is what it swallows; a eukaryote
		// is born with one; a toxin gland (毒素腺) makes it immune to toxins;
		// acid_tol 0..1 (耐酸): acid costs less, the upkeep more.
		float decomp = 0.0f;
		bool phago = false, symbiont = false, eukaryote = false, toxin = false;
		float acid_tol = 0.0f;
		bool reseed = true; // a chemosynthetic native drifts back out of the vents now and then (not a player's)
		std::vector<Card> deck; // founders start with this deck
		int alive = 0;
		int births = 0;
		int deaths_starve = 0;
		int deaths_eaten = 0;
		int deaths_age = 0;
		int deaths_temp = 0;
		int deaths_acid = 0;
		int deaths_phage = 0;
		int deaths_stalk = 0;
		int deaths_hatch = 0;
		int deaths_o2 = 0;
		// Where its energy went: all running costs, and the water's share.
		double burn_total = 0.0, burn_temp = 0.0, burn_acid = 0.0, burn_o2 = 0.0;
	};

	// One organism's look around this tick (filled in parallel).
	// The few nearest prey in sight, nearest (by the hunter's ranking) first:
	// a card can pick one by distance and size (C_PREY_NEAR, C_PREY_SMALL).
	static constexpr int PREY_CAND = 6;
	struct Scan {
		int threat = -1, prey = -1, food = -1, carcass = -1, flock = 0, lure = -1;
		int cfood = -1; // chapter 6: a producer cell a grazer can eat
		int symb_t = -1; // chapter 8: the nearest symbiont cell in sight (a phagocyte)
		float rival_d = 1e9f; // chapter 8: the nearest cell of another species
		float fx = 0, fy = 0, sx = 0, sy = 0, threat_d = 1e9f;
		int ncand = 0;
		int peer[5] = { -1, -1, -1, -1, -1 }; // nearest peer in sight in each state
		float peer_d2[5] = { 1e18f, 1e18f, 1e18f, 1e18f, 1e18f };
		int cand[PREY_CAND];
		float cand_d[PREY_CAND]; // true distance
	};

	struct LightSpot {
		float x, y, r, power;
	};

	// An environment zone (GDD 5.3): a soft-edged disc that pulls the field
	// toward its own temperature, acidity, radiation, light multiplier, and
	// feeds nutrient in through vents (energy per second, whole zone).
	struct Zone {
		float x, y, r;
		float temp, acid, rad, light, vent, chem;
	};
	// Player interventions (GDD 6), each lasting `ttl` seconds of sim time:
	// a membrane no organism can cross, a warm / cold spot (delta deg C,
	// fading in and out), a current pushing everything along.
	struct Barrier {
		float ax, ay, bx, by, life, ttl;
	};
	struct TempSpot {
		float x, y, r, delta, life, ttl;
		bool brine = false; // chapter 7: salt, not heat (drawn so)
	};
	struct Jet {
		float x, y, r, vx, vy, life, ttl;
	};

private:
	// World.
	float world_w = 2400.0f;
	float world_h = 1500.0f;
	float cell = 16.0f;
	int gw = 0, gh = 0;
	std::vector<float> nutrient;
	std::vector<float> light;
	std::vector<LightSpot> spots;
	// Environment per field cell, rebuilt from the base plus zones; signals
	// A/B share the grid (emitted, diffused, decayed, carried by the water).
	std::vector<Zone> zones;
	float base_temp = 14.0f, base_acid = 0.0f, base_rad = 0.0f;
	float algae_growth = 1.0f, algae_upkeep = 1.0f;
	std::vector<float> temp, acid, rad, vent, chem, light_base, sig_a, sig_b;
	std::vector<float> enzyme; // digestive enzyme in the water (level 13): grazing on tough algae pays only where it is thick
	// Chapter 6: dissolved oxygen, 0..1 of full (as the HUD shows it, x100 %).
	// Producers give it off in the light; it spreads and slowly fades; the
	// vents' sulfide and aerobic breathing take it up; iron dust soaks it.
	std::vector<float> o2;
	bool o2_on = false;
	int o2_phase = 0;
	float o2_decay = 0.003f, o2_diffuse = 3.0f, o2_sulfide = 0.6f, o2_emit = 0.02f, o2_use = 0.01f;
	float o2_tox = 0.08f, o2_harm = 1.2f, o2_need = 0.08f;
	float aero_mult = 3.0f, aero_low = 0.45f, fac_mult = 2.2f, fac_low = 0.85f, fac_harm = 0.0f;
	double o2_made = 0.0, o2_breathed = 0.0;
	struct IronSpot {
		float x, y, r, life, ttl;
	};
	std::vector<IronSpot> irons;
	float iron_rate = 1.5f; // per second at the centre
	float cell_graze = 3.0f; // energy/s a grazer takes off a producer cell (6 µm grazer)
	float graze_rest = 1.0f;
	float graze_refuge = 0.0f; // producers above this y (µm) cannot be grazed (0: none) // seconds a grazer digests after eating one up (it does not graze meanwhile)
	void step_oxygen(float dt);
	// Chapter 6 boss (6-5): a giant foraminiferan's pseudopod net on the
	// seabed, coverage 0..1 per field cell. It spreads only where the water
	// holds oxygen enough (it breathes), draws back where it does not; a
	// cell in it is slowed and drained (food for the foraminiferan).
	std::vector<float> net, net_tmp;
	bool net_on = false;
	int net_phase = 0;
	float net_x = 1100.0f, net_y = 1300.0f, net_core = 70.0f;
	float net_top = 0.0f; // it lies on the seabed: none above this y (µm)
	float net_need = 0.06f, net_grow = 0.12f, net_shrink = 0.05f, net_drain = 3.0f, net_slow = 0.7f, net_use = 0.004f;
	double net_fed = 0.0;
	int net_caught = 0;
	void step_net(float dt);
	// Chapter 7: the ice (walls nothing crosses and nothing sees through),
	// the long night, salt (brine: the water there does not freeze).
	std::vector<Barrier> walls;
	bool night_now = false;
	float divide_min_temp = -1000.0f; // chapter 7: colder water than this, no dividing
	// Chapter 7 boss (7-5): a heliozoan (太阳虫) lying in wait at a junction
	// of the ice. Its axopods reach `reach` all round, not through ice; what
	// they touch is caught and drawn in along them, drained, then eaten. It
	// burns all the while and starves if nothing comes; it moves between
	// its spots now and then. A closed spore is not caught.
	struct Helio {
		bool on = false;
		float x = 0.0f, y = 0.0f, tx = 0.0f, ty = 0.0f;
		float energy = 0.0f, full = 1000.0f, burn = 4.0f, reach = 150.0f, body = 34.0f;
		float catch_rate = 1.2f, pull = 26.0f, drain = 6.0f, gain = 0.8f, speed = 10.0f;
		float move_every = 70.0f, move_t = 0.0f;
		int spot = 0, caught = 0, eaten = 0;
		bool dead = false;
	};
	Helio helio;
	std::vector<Vector2> helio_spots;
	std::vector<int> held; // the heliozoan has this cell (1) or not
	void step_helio(float dt);
	// --- chapter 8 ---
	// Mud layers (8-1 on): fixed profiles of oxygen from above and hydrogen
	// sulfide from below (the chem field: a chemosynthetic cell feeds on it,
	// it poisons an aerobe). The water's oxygen is pulled back toward the
	// profile; stirring (搅动泥层) carries oxygen down and thins the sulfide
	// for a while.
	bool mud_on = false;
	float mud_relax = 0.15f, h2s_harm = 1.2f, h2s_safe = 0.15f, stir_o2 = 0.7f;
	std::vector<float> mud_o2, mud_h2s;
	struct StirSpot {
		float x, y, r, life, ttl;
	};
	std::vector<StirSpot> stirs;
	float stir_rebuild = 0.0f;
	float stir_at(float wx, float wy) const;
	// Acid rain (8-4): the rain's acid per field cell, soaking down slowly
	// (the deeper, the slower), draining away faster once it stops.
	std::vector<float> rain;
	float rain_level = 0.0f, rain_top = 0.0f, rain_depth = 350.0f, rain_rate = 0.12f;
	// Toxins (8-3): two fields; resistance per cell, gained by living
	// through them, passed to the daughters, slowly lost without them.
	std::vector<float> tox_a, tox_b;
	std::vector<float> res_a, res_b;
	std::vector<uint8_t> symb; // carries an endosymbiont (8-2)
	std::vector<uint8_t> emitting_tox; // put out toxin this tick (drawn)
	float tox_harm = 4.0f, tox_emit = 0.8f, tox_cost = 0.5f, tox_decay = 0.12f, tox_diffuse = 2.0f;
	float res_gain = 0.06f, res_loss = 0.006f, res_max = 0.95f;
	float symb_mult = 1.8f, symb_speed = 0.82f, symb_upkeep = 1.25f;
	int swallowed = 0;
	void step_ch8(float dt);
	// --- chapter 8 boss ---
	// 8-5: a slime mould (菌毯意识, Physarum) at the centre puts out tubes to
	// the food points, each the shortest way it can find (bending round
	// membranes and ice); a tube engulfs the cells it lies across; a
	// connected point feeds it unless the player holds it; toxin burns a
	// tube through. It burns all the while, more the longer its tubes, and
	// starves when the food stops coming.
	struct SlimeTube {
		std::vector<Vector2> pts;
		std::vector<float> dmg;
		int target = -1;
		bool done = false;
		float ang = 0.0f;
		float wait = 0.0f;
	};
	struct SlimePoint {
		float x, y;
		int owner = 0; // 0 nobody, 1 the player
		bool linked = false;
	};
	bool slime_on = false, slime_dead = false;
	float slime_x = 1100.0f, slime_y = 1100.0f, slime_core = 60.0f;
	float slime_e = 0.0f, slime_full = 2000.0f, slime_burn = 2.0f, slime_len_cost = 0.002f, slime_feed = 6.0f;
	float slime_speed = 9.0f, slime_reach = 12.0f, slime_drain = 8.0f, slime_gain = 0.7f, slime_cut = 0.25f, slime_regrow = 8.0f;
	int slime_eaten = 0, slime_cuts = 0;
	std::vector<SlimeTube> tubes;
	std::vector<SlimePoint> slime_pts;
	std::vector<float> slime_d; // per cell: how far the nearest tube is
	bool path_blocked(float ax, float ay, float bx, float by) const;
	void step_slime(float dt);
	float light_scale = 1.0f;
	float spore_form = 8.0f, spore_germ = 8.0f;
	bool sight_blocked(float ax, float ay, float bx, float by) const;
	bool spore_closed(int i) const { return state[i] == S_SPORE && st_time[i] >= spore_form && germ[i] <= 0.0f; }
	float net_at(float wx, float wy) const;
	bool o2_dir(int i, bool up, float &dx, float &dy) const;
	float resp_gain(int i) const;
	double vent_total = 0.0;
	int signal_phase = 0;
	float dish_x = 0.0f, dish_y = 0.0f, dish_r = 0.0f;

	// Water: cached velocity per field cell, refreshed every few ticks.
	float flow_scale = 1.0f;
	std::vector<float> flow_u, flow_v, flux_tmp;
	int flow_age = 1000;

	// Organisms (SoA).
	int count = 0;
	std::vector<int> id, sp, lineage, gen, target;
	std::vector<float> x, y, px, py, vx, vy, heading, pheading;
	std::vector<float> energy, age, phase, cooldown, wander, digest;
	std::vector<uint8_t> crowd; // same-species neighbours last tick (confusion effect)
	std::vector<float> t_speed, t_vision, t_armor, t_attack, t_fertility, t_efficiency;
	std::vector<uint8_t> alive, bitten, action;
	// Behaviour: deck (MAX_CARDS per organism), its size, the neural gene,
	// the card that fired (-1 none), what was sensed, hurt timer, and where
	// the current action is aimed (for the analysis view).
	std::vector<Card> cards;
	std::vector<uint8_t> ncards, sense;
	std::vector<int8_t> fired;
	// Gene-expression state (觅食 / 警戒 / 繁殖期 / 休眠) and seconds in it.
	std::vector<uint8_t> state;
	std::vector<float> st_time;
	// Chapter 7: the spot it remembers (NAN: none) and its germination left.
	std::vector<float> mem_x, mem_y, germ;
	std::vector<float> t_neural, hurt, threat_d, tgx, tgy;
	// Thermal genes and the environmental drain last tick (for explanations
	// and the cause of death).
	std::vector<float> t_topt, t_ttol, stress_t, stress_a;
	// Division as a scene: for JOIN_TIME after a split the child stays held
	// inside its parent's body (hidden, pinned ahead of it along the heading)
	// while the parent is drawn swelling, pinching and parting in two. `pair`
	// links the two while joined; `join` counts down on the child; the child's
	// birth (and any mutation) is announced when they part.
	std::vector<float> join;
	std::vector<int> pair;
	std::vector<uint8_t> join_mut;
	// Swimming as the shader draws it: `sw` is each cell's stroke phase
	// (advances faster the faster it swims; thrust surges with each stroke),
	// `psw` its value at the start of the tick for interpolation, `curl` the
	// smoothed turn rate the body bends into. `ha`/`hb` are a single cell's
	// drawn half length / half width, so bodies collide as they are drawn.
	std::vector<float> sw, psw, curl, ha, hb;
	std::vector<float> vs; // smoothed speed fraction, so the drawn stroke eases
	std::vector<float> angv; // turning speed (rad/s): the cilia turn the body, with inertia
	// relax_contacts scratch: candidate pairs and each body's heading trig.
	std::vector<int> contact_pairs;
	std::vector<float> contact_r; // the pair's two ellipse radii toward each other
	std::vector<float> hcos, hsin;
	// Feeding as a scene. `latch` grows while a predator is biting (its front
	// reaches round the prey). A kill is swallowed whole: the predator carries
	// the prey (species, lineage, size, where it was in the predator's frame)
	// and digests it over DIGEST_TIME; gulp_t < 0 means an empty gut.
	std::vector<float> latch, gulp_t, gulp_r, gulp_lx, gulp_ly, gulp_h, gulp_ph;
	std::vector<int> gulp_sp, gulp_lin;
	int next_id = 1;
	int next_lineage = 1;

	// Algae clumps (SoA).
	int algae = 0;
	int algae_cap = 900;
	std::vector<float> al_x, al_y, al_px, al_py, al_e, al_ph, al_bud;

	// Empty shells left by starvation and old age (SoA).
	int shells = 0;
	std::vector<float> sh_x, sh_y, sh_e, sh_e0, sh_h, sh_r, sh_ph;
	std::vector<int> sh_sp, sh_lineage;

	// Phages (level 15), real particles: they drift in the water until one
	// touches a host, which then carries the infection to its burst. `inf_t`
	// is the seconds since one landed on it (-1 clean), `inf_ang` where on the
	// body it landed, in the body's own frame.
	int phages = 0;
	std::vector<float> ph_x, ph_y, ph_px, ph_py, ph_vx, ph_vy, ph_dx, ph_dy, ph_life, ph_age;
	std::vector<int> ph_seed;
	std::vector<float> inf_t, inf_ang;
	// What the landing comes to: 0 the cell dies, 1 it cuts the DNA and
	// remembers (first time), 2 it has the memory and cuts it at once, 3 no
	// landing: the phage in its own genes woke (dies the same way). `immune`
	// passes to the daughters.
	std::vector<uint8_t> inf_fate, immune;
	std::vector<uint8_t> carry; // a phage settled in its genes by landing (level 18); passes to the daughters
	// Level 19: giant viruses, a few hundred at most, big enough to see. They
	// drift until a feeding cell takes one for food; the cell then builds a
	// factory for them (inf_fate 4). A virophage (the player's virus here)
	// rides in on one, lands on a factory, or waits in the genes (carry):
	// `hijack` is when it reached the factory, inf_t seconds (-1: it never did).
	// Level 21: what the stream carries, and the shell a colony leaves behind.
	static constexpr int COL_GERMS = 12;
	struct Grit {
		float x, y, px, py, vx, vy, ph;
	};
	struct Ghost {
		float x, y, h, t, ph;
		int s, lin;
		// Eaten down by a hunter: the remains are drawn into it (the eater's
		// id; where the body sat and how it lay in the eater's frame), then
		// handed to its gut. -1: a torn shell left where it died.
		int eater = -1;
		float lx = 0.0f, ly = 0.0f, dh = 0.0f;
		bool handed = false;
	};
	bool ghost_pose(const Ghost &g, float alpha, float &ox, float &oy, float &h, float &sc, float &fade) const;
	std::vector<Grit> grits;
	std::vector<Ghost> ghosts;
	std::vector<float> gest, gwait, emb; // seconds in gestation (-1 = not); a ready embryo's wait; each germ block's embryo 0..1
	// Level 22: what a colony's store blocks hold, and each block's fresh bite
	// mark (1 = just bitten, healing to 0).
	static constexpr int COL_MAXB = 12;
	std::vector<float> store, cmark;
	float col_store_e = 60.0f, col_armor = 0.12f, col_bite_e = 30.0f, col_bite_gap = 1.4f;
	int col_bites = 0, col_blocked = 0, col_eaten = 0;
	bool bite_colony(int i, int j);
	// Level 23: blocks bitten to uselessness grow back. cdmg per block: armour
	// cracks (0..1) while it works; a broken block (cbroken) regrows from 1 to
	// 0 and does nothing until then. col_hurt = 0 leaves blocks unharmed (22).
	std::vector<float> cdmg;
	std::vector<uint8_t> cbroken;
	std::vector<float> cslow; // the share of the rim's flagella broken
	std::vector<float> cspurn; // level 24: seconds the guardian still leaves this body alone
	std::vector<uint8_t> cpiece; // a piece broken off, until it is whole again
	float col_hurt = 0.0f, col_crack = 0.34f, col_regrow = 30.0f, col_regen = 4.0f, col_regrow_e = 40.0f, col_bleed = 0.0f; // bleed: energy a second an open wound costs
	float col_jet = 0.0f; // level 24: how fully a player's current carries a body (0: as anything its size)
	bool col_regen_all = false;
	int col_depth = 1; // level 23: blocks a bite tears into, from the rim inward along the bite
	bool col_dig = false; // level 23: a broken rim block lays the block behind it open to the next bite
	float rot_rage = 1.0f; // level 24: how much angrier the guardian is late in the run (LevelEval "rage") // a working regeneration block speeds every wound in the body, not only its four neighbours
	int col_splits = 0, col_whole = 0, col_broken = 0;
	int col_healed = 0;
	float col_split_x = 0.0f, col_split_y = 0.0f; // where a body last came apart // level 23: broken blocks grown back beside a working regeneration block
	void break_block(int j, int b);
	void split_colony(int j);
	// Level 24: what each rotifer has in its mouth (an id, -1: nothing) and
	// how long it has chewed; a colony being chewed (cheld) does nothing.
	std::vector<int> rot_meal;
	std::vector<float> rot_t;
	// Level 24's irritant: a rotifer touched draws its corona in (no pull, no
	// swallowing; what it chews it goes on chewing). Touched again within
	// ROT_HABIT seconds it draws in for half as long (it gets used to it).
	float rot_retract = 0.0f, rot_retract_last = 0.0f, rot_since = 1e9f;
	int rot_irritated = 0, rot_rescued = 0;
	std::vector<uint8_t> cheld;
	int rot_swallowed = 0, rot_spat = 0, rot_eaten = 0, rot_worn = 0;
	void step_rotifers(float dt);
	float stream_x = 0.0f, stream_y = 0.0f, grit_speed = 1.6f, col_gest = 25.0f, col_wait = 8.0f, col_child = 0.9f;
	int embryos_lost = 0, col_hatched = 0, col_born = 0;
	int colony_drawn = 0;
	void respawn_grit(Grit &g, bool anywhere);
	void step_colonies(float dt);
	void hatch(int i);

	struct Giant {
		float x, y, px, py, vx, vy, dx, dy, life, age;
		int seed;
		int load; // virophages caught in its fibres
	};
	std::vector<Giant> giants;
	// Level 20: starving cells gather into a slug (Dictyostelium). Its cells
	// stop feeding, ageing and burning energy, and are moved as one body:
	// gathering, then crawling to the light, then rising into a fruiting body
	// whose stalk cells die so the rest go out as spores.
	struct Slug {
		float x, y, hx, hy, t, debt, bx, by, grew, mx, my, warm_off;
		int stage; // 0 gathering, 1 crawling, 2 rising, 3 the dead stalk stands, 4 gone
		int n, peak;
		int spores;
	};
	std::vector<Slug> slugs;
	std::vector<int> slug; // the agent's slug, -1 none
	std::vector<float> sl_ox, sl_oy; // its place in the body, unit disc
	std::vector<float> spore; // > 0: seconds to germination; < 0: a stalk cell
	int slug_host = -1;
	float slug_tx = 0.0f, slug_ty = 0.0f, slug_speed = 14.0f, slug_gather = 8.0f, slug_loss = 1.0f, slug_arrive = 180.0f;
	float slug_share = 0.2f, slug_rise = 10.0f, slug_wait = 5.0f, slug_stay = 0.0f;
	int slug_min = 6;
	int slug_formed = 0, slug_lost = 0, slug_stalked = 0, slug_spored = 0, slug_broke = 0;
	std::vector<float> hijack;
	std::vector<int> ghead, gnext; // giants by the organism grid, for the virophages
	int giant_host = -1;
	int next_giant = 1;
	int giant_drawn = 0;
	float giant_life = 120.0f, giant_burst = 30.0f, giant_diffuse = 30.0f, giant_swallow = 2.0f, giant_crispr = 0.25f;
	int giant_yield = 8;
	int giant_taken = 0, giant_hijacked = 0; // over the run: swallowed, factories reached by a virophage
	float giant_saved = 0.0f; // ... and the giants those factories never finished
	bool phage_virophage = false; // the free phages are virophages: they go for giants and factories
	int phage_host = -1; // the species it can infect (-1: no phages in this world)
	int next_phage = 1;
	int phage_drawn = 0;
	float phage_life = 16.0f, phage_burst = 10.0f, phage_rain = 0.0f, phage_rain_from = 0.0f, phage_rain_debt = 0.0f;
	int phage_yield = 30;
	bool phage_temperate = false; // landing settles in the genes instead of starting the burst
	float phage_diffuse = 140.0f; // µm²/s
	float phage_stick = 0.35f; // chance per tick of holding on when touching

	// Spatial grids (organisms, algae, shells share the cell size).
	float acell = 40.0f;
	int agw = 0, agh = 0;
	std::vector<int> ahead, anext, lhead, lnext, shead, snext;

	std::vector<Species> species;
	float max_extent = 6.0f;
	std::vector<Scan> scans;
	std::vector<float> events;
	bool mutated_now = false;
	int analysis_count = 0;

	// Energy ledger.
	double energy_in = 0.0;
	double energy_out = 0.0;

	double sim_time = 0.0;
	double prof[5] = { 0, 0, 0, 0, 0 };
	double prof_pairs = 0, prof_iters = 0;
	int prof_n = 0;
	uint64_t rng = 0x9E3779B97F4A7C15ull;

	float randf();
	float rand_range(float a, float b);
	float gauss();

	float body_energy(int s) const;
	float algae_radius(float e) const;
	Color lineage_color(int s, int lin) const;
	bool inside_dish(float wx, float wy, float margin) const;
	void keep_in_dish(float &wx, float &wy, float r) const;
	void current(float wx, float wy, float &u, float &v) const;
	int nutrient_index(float wx, float wy) const;
	void rebuild_grids();
	void scan_one(int i);
	void emit(int type, float ex, float ey, int s, float a, float b);
	// Distance from a body's centre to its outline in world direction (dx, dy).
	float body_radius(int i, float dx, float dy) const;
	float cell_radius(int i, float dx, float dy) const;
	float infect_swell(int i, float alpha) const;
	float infect_tint(int i) const;
	void set_shape(int i);
	void relax_contacts(int n);
	std::vector<Barrier> barriers;
	std::vector<TempSpot> temp_spots;
	// Lights that come and go (level 11 blooms): no swirl, just the light.
	struct LightPulse {
		float x, y, r, power, life, ttl;
	};
	std::vector<LightPulse> light_pulses;
	void light_profile(float px, float py, float radius, float power);
	std::vector<Jet> jets;
	float temp_rebuild = 0.0f;
	void step_interventions(float dt);
	void enforce_barriers();
	float spot_fade(float life, float ttl) const;

public:
	int add_barrier(Vector2 a, Vector2 b, float seconds);
	int add_temp_spot(Vector2 pos, float radius, float delta, float seconds);
	int add_current(Vector2 pos, float radius, Vector2 velocity, float seconds);
	Array get_interventions() const;

private:
	int spawn_one(int s, float wx, float wy, int parent);
	void move_agent(int to, int from);
	static int slots_for(float neural);
	bool comfort_dir(int i, float &dx, float &dy) const;
	bool signal_dir(int i, int which, float &dx, float &dy) const;
	bool mutate_deck(int i);
	int pick_prey(int i, const Card &cd) const;
	bool card_holds(int i, const Card &cd) const;
	bool cond_ok(int i, const Card &cd, int k) const;
	static Card card_from(const Dictionary &d);
	static Dictionary card_to(const Card &c);
	std::vector<Card> default_deck(int diet) const;
	float divide_energy(int i) const;
	bool cond_true(int i, uint8_t c, float t) const;
	bool act_possible(int i, uint8_t a) const;
	int add_algae(float wx, float wy, float e);
	void add_shell(int i);
	void kill(int i, int cause);
	void compact();
	void step_nutrients(float dt);
	void step_signals(float dt);
	void transport(std::vector<float> &field, float kd, float dt);
	void rebuild_env();
	float temp_at(float wx, float wy) const;
	float temp_dev(int i) const;
	void step_algae(float dt);
	void step_shells(float dt);
	void step_phages(float dt);
	void step_giants(float dt);
	void step_slugs(float dt);
	void set_colony(Dictionary d);
	void set_rot_rage(float r);
	float irritate(Vector2 pos, float radius);
	float get_rot_rage() const { return rot_rage; }
	PackedFloat32Array get_rotifer_retract() const; // (seconds left, how long this one was, how long the next would be)
	Dictionary get_colony_stats() const;
	PackedFloat32Array get_colonies() const;
	PackedFloat32Array get_worn(float alpha) const; // (id, x, y, heading, embryo share 0..1, gestating) per body
	PackedFloat32Array get_rotifers(float alpha) const; // (x, y, heading, fury 0..1, chewing 0..1, energy share) per rotifer
	Dictionary get_rotifer_stats() const;
	PackedFloat32Array build_colony_blocks(Rect2 rect, float alpha, float time, int capacity);
	PackedFloat32Array build_colony_skins(int s, Rect2 rect, float alpha, int capacity);
	int get_colony_drawn() const { return colony_drawn; }
	void join_slug(int i);
	void release_giants(float wx, float wy, float r, int n);
	void burst_factory(int i);
	bool virophage_lands(float wx, float wy);
	float burst_of(int i) const { return inf_fate[i] == 4 ? giant_burst : phage_burst; }
	void release_phages(float wx, float wy, float r, int n);
	void wake_phage(int i, bool by_card);
	bool doomed(int i) const { return inf_fate[i] == 0 || inf_fate[i] == 3 || inf_fate[i] == 4; }
	double world_energy() const;

protected:
	static void _bind_methods();

public:
	SimCore();

	void setup(Vector2 world_size, int seed);
	int add_species(Dictionary params);
	void set_dish(Vector2 center, float radius);
	void add_light(Vector2 pos, float radius, float power);
	// Chapter 6: light from above, full at y_full, none below y_dark.
	void add_light_band(float y_full, float y_dark, float power);
	// Chapter 6 oxygen: {on, decay, diffuse, sulfide, emit, use, tox, harm,
	// need, aero_mult, aero_low, fac_mult, fac_low, fac_harm, start}.
	void set_oxygen(Dictionary params);
	int add_iron(Vector2 pos, float radius, float seconds);
	PackedFloat32Array get_o2_field() const;
	float get_o2_at(Vector2 pos) const;
	// The dish's mean oxygen (0..1), and the share of its water above `above`.
	float get_o2_mean() const;
	float get_o2_share(float above) const;
	// Chapter 6 boss: {on, center, core, radius, need, grow, shrink, drain, slow, use}.
	void set_net(Dictionary params);
	// Chapter 7.
	void add_wall(Vector2 a, Vector2 b);
	void clear_walls() { walls.clear(); }
	PackedVector2Array get_walls() const;
	void set_night(bool on) { night_now = on; }
	void set_divide_min_temp(float t) { divide_min_temp = t; }
	// Chapter 8. Mud: {o2_full (y, full oxygen above), o2_zero (none below),
	// h2s_from (y, none above), h2s_full (y), h2s (max), relax, harm, safe}.
	void set_mud(Dictionary params);
	// The sandbox's terrain editor.
	void reset_lights();
	void clear_zones();
	void remove_food(Vector2 pos, float radius, bool algae_too, bool shells_too);
	int add_stir(Vector2 pos, float radius, float seconds);
	// Acid rain: how hard it rains (0 none .. 1), from the top `top` down.
	void set_rain(float level, float top);
	PackedFloat32Array get_rain_field() const;
	PackedFloat32Array get_tox_field(int which) const;
	// {tox_harm, tox_emit, tox_cost, tox_decay, res_gain, res_loss, symb_mult, symb_speed, symb_upkeep}
	void set_ch8(Dictionary params);
	// Of species s: how many carry a symbiont; mean resistance to toxin A / B.
	int get_symb_count(int s) const;
	PackedVector2Array get_symb_positions() const;
	Vector2 get_res_mean(int s) const;
	int get_swallowed() const { return swallowed; }
	// Dead cells' shells laid out ready (8-1: a swamp full of the dead).
	void add_shells(Vector2 pos, float radius, int n, float energy_each, int s);
	// 8-5: {center, points: [Vector2], energy (0..1 of full), full, burn, len_cost,
	// feed, speed, reach, drain, gain, cut, regrow}.
	void set_slime(Dictionary params);
	Dictionary get_slime() const;
	void set_slime_owner(int k, int owner);
	// {spots: [Vector2], energy, full, burn, reach, body, catch_rate, pull, drain, gain, speed, move_every}
	void set_helio(Dictionary params);
	Dictionary get_helio() const;
	bool get_night() const { return night_now; }
	void set_light_scale(float s);
	void set_spore_times(float form, float germinate) { spore_form = form; spore_germ = germinate; }
	int add_brine(Vector2 pos, float radius, float delta, float seconds);
	PackedFloat32Array get_net_field() const;
	// {coverage (share of the dish's water under the net), caught, fed}.
	Dictionary get_net_stats() const;
	// Environment: base values {temp, acid, radiation} and zones {center,
	// radius, temp, acid, radiation, light, vent}.
	void set_base_environment(Dictionary params);
	int add_zone(Dictionary params);
	Array get_zones() const;
	// Per field cell: temperature, acidity, signal A, signal B.
	PackedFloat32Array get_env_field() const;
	Dictionary get_env_at(Vector2 pos) const;
	static float band_for(float tol) { return 3.0f + 4.0f * (tol - 1.0f); }
	void seed_algae(int n, float energy_each, float dark = 0.02f);
	// Cap on scan threads (background runs use 1 and run side by side).
	int max_threads = 8;
	void set_max_threads(int n) { max_threads = std::max(1, n); }
	void set_algae_cap(int n) { algae_cap = n < MAX_ALGAE ? n : MAX_ALGAE; }
	// A world's algae can grow / decay slower than normal (chapter 1 level 3:
	// a bed that hardly grows and does not rot, so what is eaten is gone).
	void set_algae_rates(float growth, float upkeep) { algae_growth = growth; algae_upkeep = upkeep; }
	// Tough algae (level 13): grazing yields only (1 - tough) of its energy
	// unless the water around holds enough digestive enzyme.
	void set_algae_tough(float tough) { algae_tough = tough; }
	float algae_tough = 0.0f;
	void set_flow_scale(float s) {
		flow_scale = s;
		flow_age = 1000;
	}
	float get_flow_scale() const { return flow_scale; }
	void add_nutrient(Vector2 pos, float radius, float amount);
	// A ready-grown patch of algae (level 11 blooms): n clumps of `each` energy.
	void add_algae_patch(Vector2 pos, float radius, int n, float each);
	// A light that shines for `seconds`, then goes out.
	void light_pulse(Vector2 pos, float radius, float power, float seconds);
	// Phages: {host (species), life, burst (seconds to burst), yield,
	// rain (per second from outside), rain_from (sim time)}.
	void set_phage(Dictionary params);
	int add_phages(Vector2 pos, float radius, int n);
	int get_phage_count() const { return phages; }
	// Per particle in rect: x, y, seed, age.
	PackedFloat32Array get_phages(Rect2 rect, float alpha) const;
	// Per infected cell in rect: x, y, heading, half length, half width,
	// seconds since landing, landing angle (body frame), burst time, species,
	// how much it has swollen, fate (0 dies, 1 remembers, 2 remembered).
	PackedFloat32Array get_infected(Rect2 rect, float alpha) const;
	// Per cell carrying something in its genes, in rect: x, y, heading, half
	// length, half width, kind (0 the memory, 1 a phage).
	PackedFloat32Array get_carriers(Rect2 rect, float alpha) const;
	// The free phages in rect as MultiMesh instances (Transform2D + custom).
	PackedFloat32Array build_phage_buffer(Rect2 rect, float alpha, float side, int capacity);
	int get_phage_drawn() const { return phage_drawn; }
	void set_slug(Dictionary params);
	Array get_slugs() const;
	Dictionary get_slug_stats() const;
	int count_active(int s, Vector2 pos, float radius) const; // out of slugs and spores
	void set_giant(Dictionary params);
	int add_giants(Vector2 pos, float radius, int n);
	Dictionary get_giant_stats() const;
	PackedVector2Array get_giant_positions() const;
	// The giants in rect as MultiMesh instances (Transform2D + custom).
	PackedFloat32Array build_giant_buffer(Rect2 rect, float alpha, float side, int capacity);
	int get_giant_drawn() const { return giant_drawn; }
	int spawn(int s, Vector2 pos, int n, float spread);
	void step(float dt);

	int get_count() const { return count; }
	int get_algae_count() const { return algae; }
	int get_shell_count() const { return shells; }
	double get_time() const { return sim_time; }
	Vector2i get_grid_size() const { return Vector2i(gw, gh); }
	float get_cell_size() const { return cell; }

	// Writes every visible instance into a MultiMesh buffer: algae, then
	// shells, then organisms (cells, multicell modules and envelopes), in that
	// draw order. alpha interpolates between the last two ticks.
	PackedFloat32Array build_render_buffer(float alpha, float time, int capacity);
	int get_render_count() const;
	PackedVector2Array get_positions(int s) const;
	PackedFloat32Array get_nutrient_field() const;
	// Signal A (0) or B (1) per grid cell (gw x gh, row-major, raw concentration).
	PackedFloat32Array get_signal_field(int which) const;
	PackedFloat32Array get_light_field() const;
	PackedFloat32Array get_algae_field() const;
	PackedFloat32Array get_population_field() const;
	PackedFloat32Array get_overlap_stats() const;
	PackedFloat32Array take_events();
	Dictionary get_stats() const;
	Dictionary energy_audit() const;
	int find_agent(Vector2 pos, float radius) const;
	Dictionary get_agent(int agent_id) const;
	// For the analysis view: every organism inside rect as 8 floats
	// (x, y, vision radius, action, target x, target y, species, extent);
	// target is (x, y) itself when the action has no target.
	PackedFloat32Array get_analysis(Rect2 rect, float alpha) const;
	// Per cell in rect: x, y, species, rule state, action, extent (HUD marks).
	PackedFloat32Array get_marks(Rect2 rect, float alpha) const;
	PackedFloat32Array build_analysis_buffer(Rect2 rect, float alpha, int capacity);
	// The analysis view's target lines, grouped by action: one segment list
	// (from, to, from, to ...) per action id; short ones are left out.
	Array get_analysis_lines(Rect2 rect, float alpha) const;
	int get_analysis_count() const { return analysis_count; }
	Array get_species_deck(int s) const;
	Dictionary get_profile();
};

} // namespace godot
VARIANT_ENUM_CAST(SimCore::Event);
