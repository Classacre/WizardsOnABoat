class_name SpellwakeIslandGenerator
extends RefCounted
## Pure sector manifest. No node state or traversal order affects an island.

const SECTOR_SIZE := 480.0
const SECTOR_LIMIT := 200
const BIOMES_GROUND := ["Saltgrass Coast","Mangrove Orchard","Basalt Heath","Glass Dunes"]
const BIOMES_SKY := ["Cloud Meadow","Stormglass Reef","Astral Orchard"]
const NAME_START := ["Windward","Seabright","Grey","Moonwake","Kelp","Amber","North","Salt","Mist","Ember","Star","Drift"]
const NAME_END := ["Reach","Cay","Haven","Spire","Atoll","Watch","Isle","Crown","Shoal","Refuge","Point","Garden"]

static func sector_manifest(seed_value: int, version: int, sector_x: int, sector_z: int) -> Dictionary:
	if absi(sector_x)>SECTOR_LIMIT or absi(sector_z)>SECTOR_LIMIT:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ (version*83492791) ^ ((sector_x+4096)*73856093) ^ ((sector_z+4096)*19349663)
	if rng.randf()>0.78:
		return {}
	var x := (float(sector_x)+0.5)*SECTOR_SIZE+rng.randf_range(-105.0,105.0)
	var z := (float(sector_z)+0.5)*SECTOR_SIZE+rng.randf_range(-105.0,105.0)
	var reserve := 650.0 if version==1 else 260.0
	if Vector2(x+72.0,z+77.0).length()<reserve:
		return {}
	var sky := rng.randf()<0.16
	var biomes: Array = BIOMES_SKY if sky else BIOMES_GROUND
	var biome: String = biomes[rng.randi_range(0,biomes.size()-1)]
	var radius := rng.randf_range(27.0,45.0) if sky else rng.randf_range(45.0,89.0)
	var center_y := rng.randf_range(63.0,102.0) if sky else 0.0
	var height := rng.randf_range(8.0,13.0) if sky else rng.randf_range(18.0,48.0)
	var name_value := str(NAME_START[rng.randi_range(0,NAME_START.size()-1)])+" "+str(NAME_END[rng.randi_range(0,NAME_END.size()-1)])
	return {
		"id":"proc_%d_%d" % [sector_x,sector_z],"name":name_value,
		"center":Vector3(x,center_y,z),"radius":radius,"height":height,
		"biome":biome,"sky":sky,"safe":false,"procedural":true,
		"sector":Vector2i(sector_x,sector_z),"variation":rng.randf_range(-PI,PI),
		"poi_angle":rng.randf_range(-PI,PI),"paths":[],"pois":[],
	}
