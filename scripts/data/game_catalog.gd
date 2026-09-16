class_name GameCatalog
extends RefCounted

## The shop deliberately excludes every glyph and spell modifier.
const SHOP: Dictionary = {
	"healing_potion": {"name": "Healing potion", "buy": 18, "sell": 7},
	"hearthstone": {"name": "Harbour hearthstone", "buy": 35, "sell": 12},
	"reef_compass": {"name": "Reef compass", "buy": 24, "sell": 8},
	"storm_compass": {"name": "Storm compass", "buy": 45, "sell": 15},
	"driftwood_staff": {"name": "Driftwood staff", "buy": 40, "sell": 15},
	"sailcloth_coat": {"name": "Sailcloth coat", "buy": 25, "sell": 9},
}
const SELL_VALUES: Dictionary = {"shell": 3, "pearl": 20, "ancient_coin": 12, "kelp": 2, "crystal": 9}
const STAFF_AFFIXES: Array = [
	{"id": "billowing", "name": "Billowing", "stat": "impulse_multiplier", "min": 1.15, "max": 1.35},
	{"id": "keen", "name": "Keen", "stat": "speed_multiplier", "min": 1.12, "max": 1.28},
	{"id": "farseeing", "name": "Farseeing", "stat": "range_multiplier", "min": 1.15, "max": 1.40},
	{"id": "resonant", "name": "Resonant", "stat": "power_multiplier", "min": 1.10, "max": 1.25},
]
const STARTING_GLYPHS: Array = ["projectile", "touch", "self", "wind", "push", "spark"]
const GLYPHS: Dictionary = {
	"projectile": "form", "touch": "form", "self": "form",
	"wind": "effect", "push": "effect", "spark": "effect", "heal": "effect",
	"power": "modifier", "range": "modifier", "split": "modifier",
}
const BIOME_LOOT: Dictionary = {
	"reefback": [{"item": "shell", "chance": 1.0, "min": 1, "max": 3}, {"item": "pearl", "chance": 0.18, "min": 1, "max": 1}],
	"kelp_stalker": [{"item": "kelp", "chance": 1.0, "min": 1, "max": 3}, {"item": "crystal", "chance": 0.25, "min": 1, "max": 1}],
}
const RARITY_WEIGHTS: Dictionary = {"common": 0.70, "uncommon": 0.24, "rare": 0.055, "mythic": 0.005}
const RARITY_HEALTH: Dictionary = {"common": 1.0, "uncommon": 1.25, "rare": 1.60, "mythic": 2.0, "boss": 1.0}
const SPECIES: Dictionary = {
	"ribbonwake": {"name": "Ribbonwake Glider", "biomes": ["sunlit_shoals"], "hours": [[5.0, 19.0]], "health": 28.0, "domain": "sea", "loot": [{"item": "glider_scale", "chance": 0.65, "min": 1, "max": 2}, {"item": "ribbon_membrane", "chance": 0.20, "min": 1, "max": 1}]},
	"kettleback": {"name": "Kettleback Crab", "biomes": ["basalt_heath", "storm_reach"], "hours": [[0.0, 24.0]], "health": 70.0, "domain": "shore", "loot": [{"item": "shell", "chance": 0.85, "min": 1, "max": 3}, {"item": "kettle_valve", "chance": 0.25, "min": 1, "max": 1}, {"item": "pearl", "chance": 0.05, "min": 1, "max": 1}]},
	"lanternjaw": {"name": "Lanternjaw Skulker", "biomes": ["kelp_channels", "lantern_trench"], "hours": [[18.0, 24.0], [0.0, 6.0]], "health": 100.0, "domain": "sea", "loot": [{"item": "tough_hide", "chance": 0.80, "min": 1, "max": 2}, {"item": "lantern_gland", "chance": 0.30, "min": 1, "max": 1}, {"item": "luminous_lens", "chance": 0.06, "min": 1, "max": 1}]},
	"tidebell": {"name": "Tidebell Colossus", "biomes": ["lantern_trench"], "hours": [[0.0, 24.0]], "health": 700.0, "domain": "sea", "boss": true, "encounter": "tide_vault", "glyph": "range", "loot": [{"item": "bell_shell_plate", "chance": 1.0, "min": 2, "max": 4}, {"item": "resonant_pearl", "chance": 0.35, "min": 1, "max": 1}]},
	"brinecap": {"name": "Brinecap Browser", "biomes": ["saltgrass_coast", "mangrove_orchard", "glass_dunes"], "hours": [[5.0, 19.0]], "health": 50.0, "domain": "land", "loot": [{"item": "crystal", "chance": 0.80, "min": 1, "max": 3}, {"item": "capstone_salt", "chance": 0.15, "min": 1, "max": 1}]},
	"knuckler": {"name": "Basalt Knuckler", "biomes": ["basalt_heath"], "hours": [[8.0, 21.0]], "health": 130.0, "domain": "land", "loot": [{"item": "basalt_plate", "chance": 0.85, "min": 1, "max": 3}, {"item": "knuckle_geode", "chance": 0.18, "min": 1, "max": 1}, {"item": "warm_heartstone", "chance": 0.04, "min": 1, "max": 1}]},
	"reliquary": {"name": "Orchard Reliquary", "biomes": ["mangrove_orchard"], "hours": [[0.0, 24.0]], "health": 550.0, "domain": "land", "boss": true, "encounter": "root_archive", "glyph": "power", "loot": [{"item": "living_bark_plate", "chance": 1.0, "min": 2, "max": 4}, {"item": "elder_seed", "chance": 0.40, "min": 1, "max": 1}]},
	"threadwing": {"name": "Threadwing Skater", "biomes": ["cloud_meadow", "stormglass_reef"], "hours": [[6.0, 19.0]], "health": 24.0, "domain": "sky", "loot": [{"item": "wing_thread", "chance": 0.60, "min": 1, "max": 2}, {"item": "balancing_quill", "chance": 0.12, "min": 1, "max": 1}]},
	"cumulus": {"name": "Cumulus Grazer", "biomes": ["astral_orchard", "cloud_meadow"], "hours": [[4.0, 18.0]], "health": 80.0, "domain": "sky", "loot": [{"item": "buoyant_fiber", "chance": 0.75, "min": 1, "max": 2}, {"item": "cloud_bladder", "chance": 0.20, "min": 1, "max": 1}, {"item": "dew_bead", "chance": 0.07, "min": 1, "max": 1}]},
	"stormglass_roc": {"name": "Stormglass Roc", "biomes": ["stormglass_reef"], "hours": [[16.0, 24.0]], "health": 220.0, "domain": "sky", "rarities": ["rare", "mythic"], "loot": [{"item": "stormglass_feather", "chance": 0.90, "min": 1, "max": 3}, {"item": "thunder_crest", "chance": 0.12, "min": 1, "max": 1}]},
}

static func item_sell_value(item_id: String) -> int:
	if SHOP.has(item_id):
		return int(SHOP[item_id].sell)
	if SELL_VALUES.has(item_id):
		return int(SELL_VALUES[item_id])
	for species in SPECIES.values():
		for entry in species.loot:
			if entry.item == item_id:
				return 5 if float(entry.chance) >= 0.5 else 18
	return 0

static func spawn_allowed(species_id: String, biome: String, hour: float) -> bool:
	if not SPECIES.has(species_id) or not is_finite(hour) or hour < 0.0 or hour >= 24.0:
		return false
	var definition: Dictionary = SPECIES[species_id]
	if not definition.biomes.has(biome.to_lower().replace(" ", "_")):
		return false
	for window in definition.hours:
		if hour >= float(window[0]) and hour < float(window[1]):
			return true
	return false

static func valid_recipe(recipe: Array, learned: Array) -> bool:
	if recipe.size() < 2 or recipe.size() > 6:
		return false
	if not recipe[0] is String or GLYPHS.get(recipe[0], "") != "form":
		return false
	var effects := 0
	for index in range(recipe.size()):
		var glyph = recipe[index]
		if not glyph is String or not learned.has(glyph):
			return false
		var kind: String = GLYPHS.get(glyph, "")
		if index > 0 and kind == "form":
			return false
		if kind == "effect":
			effects += 1
		elif kind == "modifier" and effects == 0:
			return false
	return effects > 0
