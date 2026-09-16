class_name Archipelago
extends Node3D
## Seeded island manifests, grade-aware path graphs and actual Terrain3D terrain.
## Logical records remain available on a headless host. Decoration never changes them.

const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const FALL_SHADER = preload("res://shaders/waterfall.gdshader")
const GENERATOR_VERSION := 1
const MAP_ORIGIN := Vector2(-512, -512)
const MAP_SIZE := 1024
const BIOME_COLORS := {
	"Saltgrass Coast": Color("819b40"), "Mangrove Orchard": Color("557e35"),
	"Basalt Heath": Color("8a8050"), "Glass Dunes": Color("c7b775"),
	"Cloud Meadow": Color("8fa44f"), "Stormglass Reef": Color("88bab0"),
	"Astral Orchard": Color("8c9847"),
}

var world_seed: int = 7319
var island_records: Array[Dictionary] = []
var pois: Array[Dictionary] = []
var waterfall_volumes: Array[Dictionary] = []
var navigation_graphs: Dictionary = {}
var terrain: Node3D
var height_image: Image
var shore_texture: ImageTexture
var built := false
var _noise := FastNoiseLite.new()
var _island_images: Dictionary = {}
var _island_origins: Dictionary = {}
var _ground_material: StandardMaterial3D
var _building_footprints: Array[Dictionary] = []
var _nature_mesh_cache: Dictionary = {}

func configure(seed_value: int) -> void:
	world_seed = seed_value
	_noise.seed = world_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.035
	_noise.fractal_octaves = 3

func build() -> void:
	if built:
		return
	configure(world_seed)
	_plan_regions()
	for island in island_records:
		_plan_pois(island)
		_build_local_heightfield(island)
		_plan_paths(island)
		_grade_paths(island)
		_finalize_pois(island)
	_build_terrain()
	for island in island_records:
		if island.sky:
			_build_sky_island(island)
		_build_navigation(island)
		_build_natural_dressing(island)
	_build_seafloor_flora()
	built = true
	add_to_group("archipelago")

func _plan_regions() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	island_records = [
		{"id":"hearthharbour", "name":"Hearthharbour", "center":Vector3(-72,0,-77), "radius":77.0, "height":29.0, "biome":"Saltgrass Coast", "sky":false, "safe":true},
		{"id":"rootwatch", "name":"Rootwatch", "center":Vector3(180,0,-180), "radius":68.0, "height":24.0, "biome":"Mangrove Orchard", "sky":false, "safe":false},
		{"id":"cinder_crown", "name":"Cinder Crown", "center":Vector3(-240,0,-306), "radius":84.0, "height":50.0, "biome":"Basalt Heath", "sky":false, "safe":false},
		{"id":"glasswake", "name":"Glasswake", "center":Vector3(293,0,96), "radius":56.0, "height":18.0, "biome":"Glass Dunes", "sky":false, "safe":false},
		{"id":"needle_cay", "name":"Needle Cay", "center":Vector3(-315,0,140), "radius":34.0, "height":28.0, "biome":"Saltgrass Coast", "sky":false, "safe":false},
		{"id":"tide_vault", "name":"The Tide Vault", "center":Vector3(22,0,-375), "radius":46.0, "height":27.0, "biome":"Basalt Heath", "sky":false, "safe":false},
		{"id":"cloud_meadow", "name":"Cloud Meadow", "center":Vector3(140,64,-320), "radius":25.0, "height":10.0, "biome":"Cloud Meadow", "sky":true, "safe":false},
		{"id":"stormglass", "name":"Stormglass Reef", "center":Vector3(345,92,-284), "radius":31.0, "height":9.0, "biome":"Stormglass Reef", "sky":true, "safe":false},
		{"id":"astral_orchard", "name":"Astral Orchard", "center":Vector3(-354,79,-154), "radius":34.0, "height":12.0, "biome":"Astral Orchard", "sky":true, "safe":false},
	]
	for i in island_records.size():
		var island := island_records[i]
		island["variation"] = rng.randf_range(-PI, PI)
		if i > 0:
			island.center += Vector3(rng.randf_range(-15,15),0,rng.randf_range(-15,15))
			island.radius *= rng.randf_range(0.91,1.08)
		island["paths"] = []
		island["pois"] = []

func _add_poi(island: Dictionary, kind: String, offset: Vector2, title: String, desired_height: float, footprint := 4.0) -> void:
	var center: Vector3 = island.center
	var position_value := center + Vector3(offset.x,desired_height,offset.y)
	var record := {"id":island.id+"/"+kind,"island_id":island.id,"kind":kind,"name":title,"position":position_value,"radius":footprint,"height":position_value.y}
	pois.append(record)
	island.pois.append(record)

func _plan_pois(island: Dictionary) -> void:
	var r: float = island.radius
	if island.id == "hearthharbour":
		_add_poi(island,"dock",Vector2(54,46),"Hearthharbour Quay",2.4,5.0)
		_add_poi(island,"shop",Vector2(35,29),"Mara's Chandlery",8.0,8.0)
		_add_poi(island,"spawn",Vector2(43,35),"Hearthstone Landing",6.6,3.8)
		_add_poi(island,"lighthouse",Vector2(-10,-13),"Hearthlight",29.0,7.0)
		_add_poi(island,"tutorial_ruin",Vector2(-27,25),"First Tide Reliquary",13.0,6.0)
		_add_poi(island,"apprentice_cache",Vector2(-28,25),"Apprentice's Wind Cache",13.0,2.0)
	elif island.sky:
		_add_poi(island,"waterfall",Vector2(r*0.74,r*0.3),"Waterfall Landing",2.0,4.5)
		_add_poi(island,"dungeon",Vector2(-r*0.16,-r*0.16),"The Storm Observatory" if island.id=="astral_orchard" else "Windward Reliquary",island.height*0.6,6.0)
	else:
		_add_poi(island,"landing",Vector2(r*0.72,r*0.39),"Beach Landing",2.1,4.0)
		_add_poi(island,"dungeon",Vector2(-r*0.19,-r*0.16),"The Root Archive" if island.id=="rootwatch" else "The Tide Vault" if island.id=="tide_vault" else "Wayfarer's Ruin",island.height*0.55,7.0)

func _raw_height(island: Dictionary, x: float, z: float) -> float:
	var center: Vector3 = island.center
	var q := Vector2(x-center.x,z-center.z)
	var angle := atan2(q.y,q.x)
	var r: float = island.radius
	var perimeter := r*(1.0+sin(angle*5.0+island.variation)*0.082+cos(angle*8.0-island.variation)*0.045)
	var radial := q.length()/perimeter
	if radial > 1.2:
		return center.y-19.0 if island.sky else -22.0
	var shelf := (1.0-smoothstep(0.87,1.2,radial))*10.0-9.0
	var inland := pow(maxf(0.0,1.0-radial),0.62)*float(island.height)
	var noise_value := _noise.get_noise_2d(x,z)*3.8*(1.0-smoothstep(0.76,1.0,radial))
	var h := center.y+shelf+inland+noise_value
	for poi in island.pois:
		var p: Vector3 = poi.position
		var distance_value := Vector2(x-p.x,z-p.z).length()
		var strength := 1.0-smoothstep(poi.radius,poi.radius+7.0,distance_value)
		h = lerpf(h,poi.height,strength)
	return h

func _build_local_heightfield(island: Dictionary) -> void:
	var radius: float = island.radius
	var size := int(ceil(radius*2.5))+4
	var origin := Vector2(floor(island.center.x-size*0.5),floor(island.center.z-size*0.5))
	var local := Image.create(size,size,false,Image.FORMAT_RF)
	for z in size:
		for x in size:
			local.set_pixel(x,z,Color(_raw_height(island,origin.x+x,origin.y+z),0,0,1))
	_island_images[island.id] = local
	_island_origins[island.id] = origin

func _local_height(island: Dictionary, x: float, z: float) -> float:
	var img: Image = _island_images[island.id]
	var origin: Vector2 = _island_origins[island.id]
	var q := Vector2(x,z)-origin
	var ix := clampi(int(floor(q.x)),0,img.get_width()-2)
	var iz := clampi(int(floor(q.y)),0,img.get_height()-2)
	var f := q-Vector2(ix,iz)
	return lerpf(lerpf(img.get_pixel(ix,iz).r,img.get_pixel(ix+1,iz).r,f.x),lerpf(img.get_pixel(ix,iz+1).r,img.get_pixel(ix+1,iz+1).r,f.x),f.y)

func _plan_paths(island: Dictionary) -> void:
	var list: Array = island.pois
	# Each required destination joins the already-connected route network.
	for i in range(1,list.size()):
		var from: Vector3 = list[0].position
		var to: Vector3 = list[i].position
		var path := _slope_path(island,from,to)
		island.paths.append(path)

func _slope_path(island: Dictionary, from: Vector3, to: Vector3) -> PackedVector3Array:
	const STEP := 4.0
	var center: Vector3 = island.center
	var extent := int(ceil(island.radius/STEP))+2
	var start := Vector2i(round((from.x-center.x)/STEP),round((from.z-center.z)/STEP))
	var goal := Vector2i(round((to.x-center.x)/STEP),round((to.z-center.z)/STEP))
	var open: Array[Vector2i] = [start]
	var cost: Dictionary = {start:0.0}
	var previous: Dictionary = {}
	var closed: Dictionary = {}
	var offsets := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]
	while not open.is_empty():
		var best := 0
		var best_cost := INF
		for i in open.size():
			var estimate: float = cost[open[i]]+Vector2(open[i]-goal).length()*STEP
			if estimate < best_cost:
				best_cost = estimate
				best = i
		var current: Vector2i = open.pop_at(best)
		if current == goal:
			break
		closed[current] = true
		var p := center+Vector3(current.x*STEP,0,current.y*STEP)
		var height := _local_height(island,p.x,p.z)
		for offset in offsets:
			var next: Vector2i = current+offset
			if closed.has(next) or abs(next.x)>extent or abs(next.y)>extent:
				continue
			var q := center+Vector3(next.x*STEP,0,next.y*STEP)
			var nh := _local_height(island,q.x,q.z)
			if nh < center.y+0.8:
				continue
			var distance_value := Vector2(offset).length()*STEP
			var slope := absf(nh-height)/distance_value
			# Superlinear slope penalty: detouring is preferable to a steep shortcut.
			var next_cost: float = cost[current]+distance_value*(1.0+pow(slope*3.5,3.0))
			if next_cost < float(cost.get(next,INF)):
				cost[next] = next_cost
				previous[next] = current
				if not open.has(next):
					open.append(next)
	var reverse: Array[Vector2i] = [goal]
	var cursor := goal
	for guard in 4096:
		if cursor==start or not previous.has(cursor):
			break
		cursor = previous[cursor]
		reverse.append(cursor)
	reverse.reverse()
	var path := PackedVector3Array([from])
	if cursor != start:
		# Bounded fallback: a fully graded straight connection, never an absent route.
		var steps := maxi(2,int(from.distance_to(to)/STEP))
		for i in range(1,steps):
			path.append(from.lerp(to,float(i)/steps))
	else:
		for cell in reverse:
			var p := center+Vector3(cell.x*STEP,0,cell.y*STEP)
			p.y = _local_height(island,p.x,p.z)
			path.append(p)
	path.append(to)
	# Grade overlength routes forward/backward, preserving endpoints at flat POIs.
	for pass_index in 3:
		for i in range(1,path.size()-1):
			var max_delta := Vector2(path[i].x-path[i-1].x,path[i].z-path[i-1].z).length()*0.42
			path[i].y = clampf(path[i].y,path[i-1].y-max_delta,path[i-1].y+max_delta)
		for i in range(path.size()-2,0,-1):
			var max_delta := Vector2(path[i].x-path[i+1].x,path[i].z-path[i+1].z).length()*0.42
			path[i].y = clampf(path[i].y,path[i+1].y-max_delta,path[i+1].y+max_delta)
	return path

func _grade_paths(island: Dictionary) -> void:
	var img: Image = _island_images[island.id]
	var origin: Vector2 = _island_origins[island.id]
	for path in island.paths:
		for i in range(path.size()-1):
			var a: Vector3 = path[i]
			var b: Vector3 = path[i+1]
			var v := Vector2(b.x-a.x,b.z-a.z)
			var minx := maxi(0,int(minf(a.x,b.x)-origin.x-5))
			var maxx := mini(img.get_width()-1,int(maxf(a.x,b.x)-origin.x+5))
			var minz := maxi(0,int(minf(a.z,b.z)-origin.y-5))
			var maxz := mini(img.get_height()-1,int(maxf(a.z,b.z)-origin.y+5))
			for z in range(minz,maxz+1):
				for x in range(minx,maxx+1):
					var q := origin+Vector2(x,z)-Vector2(a.x,a.z)
					var t := clampf(q.dot(v)/maxf(0.001,v.length_squared()),0,1)
					var distance_value := (q-v*t).length()
					var strength := 1.0-smoothstep(1.6,4.8,distance_value)
					var h := lerpf(img.get_pixel(x,z).r,lerpf(a.y,b.y,t),strength)
					img.set_pixel(x,z,Color(h,0,0,1))

func _finalize_pois(island: Dictionary) -> void:
	for poi in island.pois:
		var p: Vector3 = poi.position
		p.y = _local_height(island,p.x,p.z)
		poi.position = p
		if poi.kind=="waterfall":
			var outward := Vector3(p.x-island.center.x,0,p.z-island.center.z).normalized()
			var base := p+outward*4.8
			var landing:=p-outward*3.5
			landing.y=_local_height(island,landing.x,landing.z)+0.10
			waterfall_volumes.append({"id":island.id+"/fall","island_id":island.id,"center":Vector3(base.x,(p.y-2.0)*0.5,base.z),"radius":4.2,"bottom":-2.0,"top":p.y+2.5,"exit":landing})

func sample_ground_height(x: float, z: float) -> float:
	var result := -24.0+_noise.get_noise_2d(x*0.4,z*0.4)*4.5
	for island in island_records:
		if island.sky:
			continue
		var q := Vector2(x-island.center.x,z-island.center.z)
		if q.length() < island.radius*1.22:
			result = maxf(result,_local_height(island,x,z))
	return result

func sample_surface_at(point: Vector3) -> float:
	var result := sample_ground_height(point.x,point.z)
	for island in island_records:
		if island.sky and point.y>island.center.y-4.0 and Vector2(point.x-island.center.x,point.z-island.center.z).length()<island.radius:
			result=maxf(result,_local_height(island,point.x,point.z))
	return result

func get_spawn_position() -> Vector3:
	for poi in pois:
		if poi.kind=="spawn":
			return poi.position+Vector3.UP*1.15
	return Vector3(-29,8,-42)

func is_safe_zone(point: Vector3) -> bool:
	for island in island_records:
		if island.safe and Vector2(point.x-island.center.x,point.z-island.center.z).length()<island.radius+13.0 and point.y<50.0:
			return true
	return false

func waterfall_at(point: Vector3) -> Dictionary:
	for volume in waterfall_volumes:
		if point.y>=volume.bottom and point.y<=volume.top and Vector2(point.x-volume.center.x,point.z-volume.center.z).length()<=volume.radius:
			return volume
	return {}

func biome_at(point: Vector3) -> String:
	for island in island_records:
		if Vector2(point.x-island.center.x,point.z-island.center.z).length()<island.radius*1.5 and (not island.sky or point.y>island.center.y-10):
			return island.biome
	if point.z < -260:
		return "Lantern Trench"
	if point.x > 150:
		return "Kelp Channels"
	if point.x < -200:
		return "Storm Reach"
	return "Sunlit Shoals"

func _distance_to_paths(island: Dictionary, point: Vector2) -> float:
	var nearest := INF
	for path in island.paths:
		for i in range(path.size()-1):
			var a := Vector2(path[i].x,path[i].z)
			var v := Vector2(path[i+1].x,path[i+1].z)-a
			var t := clampf((point-a).dot(v)/maxf(0.001,v.length_squared()),0,1)
			nearest=minf(nearest,(point-a-v*t).length())
	return nearest

func _terrain_color(x: float, z: float, h: float) -> Color:
	var color := Color("b5b995") if h<0 else Color("809342")
	for island in island_records:
		if island.sky or Vector2(x-island.center.x,z-island.center.z).length()>island.radius*1.15:
			continue
		color=BIOME_COLORS.get(island.biome,Color("809342"))
		if h<2.6:
			color=Color("cfca9f")
		elif _distance_to_paths(island,Vector2(x,z))<1.9:
			color=Color("b6a978")
		break
	var n := _noise.get_noise_2d(x*2.1,z*2.1)*0.11
	return Color(color.r+n,color.g+n,color.b+n*0.7,1)

func _build_terrain() -> void:
	height_image = Image.create(MAP_SIZE,MAP_SIZE,false,Image.FORMAT_RF)
	var colors := Image.create(MAP_SIZE,MAP_SIZE,false,Image.FORMAT_RGBA8)
	for z in MAP_SIZE:
		for x in MAP_SIZE:
			var wx := MAP_ORIGIN.x+x
			var wz := MAP_ORIGIN.y+z
			var h := sample_ground_height(wx,wz)
			height_image.set_pixel(x,z,Color(h,0,0,1))
			colors.set_pixel(x,z,_terrain_color(wx,wz,h))
	shore_texture = ImageTexture.create_from_image(height_image)
	if ClassDB.class_exists("Terrain3D"):
		terrain=ClassDB.instantiate("Terrain3D")
		terrain.name="Terrain3DArchipelago"
		terrain.set("region_size",256)
		terrain.set("mesh_size",48)
		terrain.set("mesh_lods",7)
		terrain.set("vertex_spacing",1.0)
		# Runtime-generated assets have no resource path to reload on entering tree.
		terrain.set("free_editor_textures",false)
		var material_resource = ClassDB.instantiate("Terrain3DMaterial")
		material_resource.set("world_background",0)
		material_resource.set("shader_override",TERRAIN_SHADER)
		material_resource.set("shader_override_enabled",true)
		terrain.set("material",material_resource)
		add_child(terrain)
		# All six crews need ground collision, including far from the host camera.
		# Terrain3D FULL_GAME uses compact static heightfields for this bounded map.
		terrain.set("collision_mode",3)
		var maps: Array[Image] = [height_image,null,colors]
		terrain.get("data").call("import_images",maps,Vector3(MAP_ORIGIN.x,0,MAP_ORIGIN.y),0.0,1.0)
		material_resource.set("show_checkered",false)
	else:
		push_error("Terrain3D extension missing: terrain rendering and collision require installed addon.")

func _build_navigation(island: Dictionary) -> void:
	# Shared grid vertices create genuinely joined polygons (separate path ribbons
	# would leave cracks at turns). All heights come from the final graded surface.
	var vertices := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	var center: Vector3=island.center
	const CELL:=2.0
	var extent:=int(ceil(island.radius/CELL))+1
	var width:=extent*2+1
	var blocked: Array=[]
	if navigation_graphs.has(island.id):
		blocked=navigation_graphs[island.id].blocked
	for z in width:
		for x in width:
			var p:=center+Vector3((x-extent)*CELL,0,(z-extent)*CELL)
			p.y=_local_height(island,p.x,p.z)+0.06
			vertices.append(p)
	for z in width-1:
		for x in width-1:
			var ids:=PackedInt32Array([z*width+x,(z+1)*width+x,(z+1)*width+x+1,z*width+x+1])
			var p:=vertices[ids[0]]
			var traversable: bool=p.y>center.y+0.85 and Vector2(p.x-center.x,p.z-center.z).length()<island.radius*0.96
			for i in 4:
				if absf(vertices[ids[i]].y-vertices[ids[(i+1)%4]].y)>CELL*0.67:
					traversable=false
			for block in blocked:
				if Vector2(p.x-block.position.x,p.z-block.position.z).length()<block.radius+1.2:
					traversable=false
			if traversable:
				polygons.append(ids)
	var navmesh:=NavigationMesh.new()
	navmesh.set_vertices(vertices)
	for polygon in polygons:
		navmesh.add_polygon(polygon)
	if navigation_graphs.has(island.id):
		navigation_graphs[island.id].region.navigation_mesh=navmesh
	else:
		var region:=NavigationRegion3D.new()
		region.name="Navigation_"+island.id
		region.navigation_mesh=navmesh
		add_child(region)
		navigation_graphs[island.id]={"paths":island.paths,"region":region,"revision":0,"blocked":[]}

func set_path_obstruction(island_id: String, position_value: Vector3, radius: float, enabled: bool) -> void:
	if not navigation_graphs.has(island_id):
		return
	var graph: Dictionary=navigation_graphs[island_id]
	graph.revision+=1
	if enabled:
		graph.blocked.append({"position":position_value,"radius":radius})
	else:
		for i in range(graph.blocked.size()-1,-1,-1):
			if graph.blocked[i].position.distance_to(position_value)<radius:
				graph.blocked.remove_at(i)
	for island in island_records:
		if island.id==island_id:
			_build_navigation(island)
	# Replacing only this island's polygons updates real navigation connectivity.

func route_is_clear(island_id: String, from: Vector3, to: Vector3) -> bool:
	if not navigation_graphs.has(island_id):
		return false
	for block in navigation_graphs[island_id].blocked:
		var point: Vector3=Geometry3D.get_closest_point_to_segment(block.position,from,to)
		if point.distance_to(block.position)<block.radius+0.6:
			return false
	return true

func _build_sky_island(island: Dictionary) -> void:
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center: Vector3=island.center
	var r: float=island.radius
	var fall_center:=Vector2(INF,INF)
	for volume in waterfall_volumes:
		if volume.island_id==island.id:
			fall_center=Vector2(volume.center.x,volume.center.z)
	var step:=2.0
	var extent:=int(ceil(r/step))
	for z in range(-extent,extent):
		for x in range(-extent,extent):
			if Vector2(x+0.5,z+0.5).length()*step>r*0.93:
				continue
			var cell_center:=Vector2(center.x+(x+0.5)*step,center.z+(z+0.5)*step)
			# Reserve a real open notch through the rim and underside. A visible
			# waterfall without this aperture can trap swimmers against sky rock.
			if cell_center.distance_to(fall_center)<5.4:
				continue
			var verts: Array[Vector3]=[]
			for offset in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var p:=center+Vector3((x+offset.x)*step,0,(z+offset.y)*step)
				p.y=_local_height(island,p.x,p.z)
				verts.append(p)
			# Godot's front faces use clockwise winding. Up-facing caps must use
			# this order so players land on them instead of passing through below.
			for index in [0,1,2,0,2,3]:
				surface.set_color(BIOME_COLORS[island.biome])
				surface.add_vertex(verts[index])
	# Faceted cliff skirt and pointed underside belong to the island geometry.
	var rng:=RandomNumberGenerator.new()
	rng.seed=world_seed+int(island.id.hash())
	for i in 32:
		var angle:=TAU*i/32.0
		var next:=TAU*(i+1)/32.0
		var a:=center+Vector3(cos(angle)*r*0.93,0,sin(angle)*r*0.93)
		var b:=center+Vector3(cos(next)*r*0.93,0,sin(next)*r*0.93)
		if Vector2(a.x,a.z).distance_to(fall_center)<7.6 or Vector2(b.x,b.z).distance_to(fall_center)<7.6:
			continue
		a.y=_local_height(island,a.x,a.z)
		b.y=_local_height(island,b.x,b.z)
		var c:=center+Vector3(cos(next)*r*0.69,-r*(0.35+sin(next*3.0)*0.06)-rng.randf()*2.0,sin(next)*r*0.64)
		var d:=center+Vector3(cos(angle)*r*0.69,-r*(0.35+sin(angle*3.0)*0.06)-rng.randf()*2.0,sin(angle)*r*0.64)
		var cluster_angle: float=floorf(float(i)/8.0)*PI*0.5+0.35
		var tip:=center+Vector3(cos(cluster_angle)*r*0.24,-r*(0.66+0.12*sin(cluster_angle*3.0)),sin(cluster_angle)*r*0.22)
		for p in [a,b,c,a,c,d,c,tip,d]:
			surface.set_color(Color("66756e").lightened(rng.randf()*0.16).srgb_to_linear())
			surface.add_vertex(p)
	surface.generate_normals()
	var mesh:=surface.commit()
	var instance:=MeshInstance3D.new()
	instance.name="SkyIsland_"+island.id
	instance.mesh=mesh
	var mat:=StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo=true
	mat.roughness=0.94
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	instance.material_override=mat
	add_child(instance)
	instance.create_trimesh_collision()
	for volume in waterfall_volumes:
		if volume.island_id==island.id:
			_build_waterfall(volume)

func _build_waterfall(volume: Dictionary) -> void:
	var waterfall:=MeshInstance3D.new()
	waterfall.name="SwimmableWaterfall_"+volume.island_id
	var mesh:=CylinderMesh.new()
	mesh.top_radius=2.0
	mesh.bottom_radius=3.15
	mesh.height=volume.top-volume.bottom
	mesh.radial_segments=12
	mesh.rings=30
	var mat:=ShaderMaterial.new()
	mat.shader=FALL_SHADER
	waterfall.mesh=mesh
	waterfall.material_override=mat
	waterfall.position=Vector3(volume.center.x,(volume.top+volume.bottom)*0.5,volume.center.z)
	waterfall.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(waterfall)
	var area:=Area3D.new()
	area.name="WaterfallVolume_"+volume.island_id
	area.position=waterfall.position
	area.collision_layer=0
	area.collision_mask=2
	area.set_meta("waterfall",volume)
	area.add_to_group("waterfalls")
	var shape:=CollisionShape3D.new()
	var cylinder:=CylinderShape3D.new()
	cylinder.radius=volume.radius
	cylinder.height=volume.top-volume.bottom
	shape.shape=cylinder
	area.add_child(shape)
	add_child(area)

func _load_nature_mesh(asset: String) -> Mesh:
	if _nature_mesh_cache.has(asset):
		return _nature_mesh_cache[asset]
	var path: String="res://assets/models/nature/"+asset+".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene=load(path)
	var instance: Node=scene.instantiate()
	var meshes: Array[Node]=instance.find_children("*","MeshInstance3D",true,false)
	if instance is MeshInstance3D:
		meshes.push_front(instance)
	var result: Mesh=null
	if not meshes.is_empty():
		result=meshes[0].mesh
		# Every original nature asset uses the same generated atlas. Imported GLBs
		# may create per-file image copies; bind one shared runtime texture instead.
		if ResourceLoader.exists("res://assets/textures/nature-atlas.png"):
			var atlas: Texture2D=load("res://assets/textures/nature-atlas.png")
			for i in result.get_surface_count():
				var mat: Material=result.surface_get_material(i)
				if mat is StandardMaterial3D:
					var shared: StandardMaterial3D=mat.duplicate()
					shared.albedo_texture=atlas
					shared.vertex_color_use_as_albedo=true
					result.surface_set_material(i,shared)
	_nature_mesh_cache[asset]=result
	instance.free()
	return result

func _place_nature_instances(asset: String, transforms: Array[Transform3D], label: String) -> void:
	var mesh:=_load_nature_mesh(asset)
	if not mesh or transforms.is_empty():
		return
	var multimesh:=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.mesh=mesh
	multimesh.instance_count=transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i,transforms[i])
	var instance:=MultiMeshInstance3D.new()
	instance.name=label
	instance.multimesh=multimesh
	instance.visibility_range_end=780.0
	instance.visibility_range_end_margin=100.0
	add_child(instance)
	if label.begins_with("FacetedCoast_") or label.begins_with("Trees_"):
		var body:=StaticBody3D.new()
		body.name=label+"_Collision"
		var collision: Shape3D
		if label.begins_with("FacetedCoast_"):
			collision=mesh.create_convex_shape(false,false)
		else:
			var trunk:=CapsuleShape3D.new()
			trunk.radius=0.38
			trunk.height=3.5
			collision=trunk
		for placement in transforms:
			var shape:=CollisionShape3D.new()
			shape.shape=collision
			shape.transform=placement
			if label.begins_with("Trees_"):
				shape.position+=placement.basis*Vector3(0.3,1.7,0)
			body.add_child(shape)
		add_child(body)

func _build_natural_dressing(island: Dictionary) -> void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=world_seed+int(island.id.hash())+7041
	var trees: Array[Transform3D]=[]
	var crags: Array[Transform3D]=[]
	var center: Vector3=island.center
	var radius: float=island.radius
	# Reserve every route and POI footprint before placing authored vegetation.
	for attempt in 120 if not island.sky else 30:
		var angle:=rng.randf()*TAU
		var r:=sqrt(rng.randf())*radius*0.85
		var point:=center+Vector3(cos(angle)*r,0,sin(angle)*r)
		point.y=_local_height(island,point.x,point.z)
		if point.y<center.y+3.8 or _distance_to_paths(island,Vector2(point.x,point.z))<4.5:
			continue
		var reserved:=false
		for poi in island.pois:
			if Vector2(point.x-poi.position.x,point.z-poi.position.z).length()<poi.radius+3.0:
				reserved=true
		for volume in waterfall_volumes:
			if volume.island_id==island.id and Vector2(point.x-volume.center.x,point.z-volume.center.z).length()<9.0:
				reserved=true
		if reserved:
			continue
		var slope:=absf(point.y-_local_height(island,point.x+2.0,point.z))+absf(point.y-_local_height(island,point.x,point.z+2.0))
		if slope>2.8:
			continue
		var scale_value:=rng.randf_range(0.82,1.42)
		if island.biome in ["Basalt Heath","Glass Dunes","Stormglass Reef"]:
			if attempt%4!=0: continue
			scale_value*=0.65
		trees.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_value),point))
	# Rocks are individually authored cliff wedges; scaled placement follows the
	# generated perimeter, preserving beach and dock approach corridors.
	for i in 65 if not island.sky else 20:
		var angle:=TAU*i/(65.0 if not island.sky else 20.0)+rng.randf_range(-0.045,0.045)
		var r:=radius*rng.randf_range(0.76,1.01)
		var p:=center+Vector3(cos(angle)*r,0,sin(angle)*r)
		p.y=_local_height(island,p.x,p.z)-0.55
		if _distance_to_paths(island,Vector2(p.x,p.z))<6.0:
			continue
		var obstructs_fall:=false
		for volume in waterfall_volumes:
			if volume.island_id==island.id and Vector2(p.x-volume.center.x,p.z-volume.center.z).length()<10.0:
				obstructs_fall=true
		if obstructs_fall: continue
		var scales:=Vector3(rng.randf_range(2.0,4.7),rng.randf_range(1.4,4.8),rng.randf_range(2.0,4.4))
		if island.sky:
			scales*=0.55
		crags.append(Transform3D(Basis(Vector3.UP,angle).scaled(scales),p))
	_place_nature_instances("mangrove" if island.biome=="Mangrove Orchard" else "wind_tree",trees,"Trees_"+island.id)
	_place_nature_instances("coastal_crag_0",crags,"FacetedCoast_"+island.id)

func _build_seafloor_flora() -> void:
	# The biome-specific instanced plant geometry is a shader-animated ribbon mesh.
	# Authored flora meshes can replace it without changing placement or ecology.
	for biome_index in 4:
		var st:=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var colors: Array[Color]=[Color("629970"),Color("4d794a"),Color("cead5d"),Color("517977")]
		var blade_height:=2.0 if biome_index!=1 else 6.0
		for segment in 5:
			var y:=blade_height*segment/5.0
			var next_y:=blade_height*(segment+1)/5.0
			var w:=0.4*(1.0-float(segment)/6.0)
			var offset:=sin(segment*0.8)*0.55
			for p in [Vector3(-w+offset,y,0),Vector3(w+offset,y,0),Vector3(offset+0.2,next_y,0),Vector3(-w+offset,y,0),Vector3(offset+0.2,next_y,0),Vector3(-w+offset,next_y,0)]:
				st.add_vertex(p)
		st.generate_normals()
		var mesh: Mesh=st.commit()
		var material_value:=StandardMaterial3D.new()
		material_value.albedo_color=colors[biome_index]
		material_value.cull_mode=BaseMaterial3D.CULL_DISABLED
		material_value.roughness=0.86
		mesh.surface_set_material(0,material_value)
		var modeled_mesh:=_load_nature_mesh("kelp_fan" if biome_index==1 else "shoal_seagrass" if biome_index==0 else "amber_coral")
		if modeled_mesh:
			mesh=modeled_mesh
		var placements: Array[Transform3D]=[]
		var rng:=RandomNumberGenerator.new()
		rng.seed=world_seed+1827+biome_index
		for index in 400:
			var x:=rng.randf_range(-420,420)
			var z:=rng.randf_range(-450,260)
			var h:=sample_ground_height(x,z)
			if h>-2.5 or h< -28:
				continue
			var domain:=0
			if z< -260: domain=2
			elif x>150: domain=1
			elif x< -200: domain=3
			if domain!=biome_index:
				continue
			var basis_value:=Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(0.8,1.8))
			placements.append(Transform3D(basis_value,Vector3(x,h,z)))
		# Dense readable reef gardens near each landing, plus the sparse open seabed.
		for island in island_records:
			if island.sky: continue
			var expected_domain:=0
			if island.center.z< -260: expected_domain=2
			elif island.center.x>150: expected_domain=1
			elif island.center.x< -200: expected_domain=3
			if expected_domain!=biome_index: continue
			for index in 95:
				var angle:=rng.randf()*TAU
				var radius:float=island.radius*rng.randf_range(1.05,1.36)
				var x:float=island.center.x+cos(angle)*radius
				var z:float=island.center.z+sin(angle)*radius
				var h:=sample_ground_height(x,z)
				if h> -1.7: continue
				var basis_value:=Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(0.8,1.7))
				placements.append(Transform3D(basis_value,Vector3(x,h,z)))
		var multi:=MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=mesh
		multi.instance_count=placements.size()
		for i in placements.size():
			multi.set_instance_transform(i,placements[i])
		var node:=MultiMeshInstance3D.new()
		node.name="UnderwaterFlora_%d"%biome_index
		node.multimesh=multi
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
