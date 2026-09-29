class_name SpellwakeDungeonLayout
extends RefCounted
## Deterministic single-floor room graph and A* corridor carving.
## Inspired by the algorithm described at https://vazgriz.com/119/procedurally-generated-dungeons/.
## This is an independent Godot implementation; no source code was copied.

const GRID_SIZE := 31
const CELL_SIZE := 3.0
const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

static func generate(seed_value: int, dungeon_id: String, room_target: int, origin: Vector3, biome: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ dungeon_id.hash()
	var rooms: Array[Rect2i] = [Rect2i(Vector2i(13,13),Vector2i(5,5))]
	for attempt in 180:
		if rooms.size() >= room_target:
			break
		var size := Vector2i(rng.randi_range(3,5),rng.randi_range(3,5))
		var room := Rect2i(Vector2i(rng.randi_range(2,GRID_SIZE-size.x-3),rng.randi_range(2,GRID_SIZE-size.y-3)),size)
		var separated := true
		for existing in rooms:
			if existing.grow(1).intersects(room):
				separated = false
				break
		if separated:
			rooms.append(room)
	var centers: Array[Vector2i] = []
	var open_cells: Dictionary = {}
	var room_cells: Dictionary = {}
	for room in rooms:
		centers.append(room.position+room.size/2)
		for y in range(room.position.y,room.end.y):
			for x in range(room.position.x,room.end.x):
				var cell := Vector2i(x,y)
				open_cells[cell] = true
				room_cells[cell] = true
	var candidate_edges := _delaunay_edges(centers)
	var tree_edges := _minimum_tree(centers,candidate_edges)
	var selected_edges: Array[Vector2i] = tree_edges.duplicate()
	var extra_edges := 0
	for edge in candidate_edges:
		if tree_edges.has(edge) or rng.randf() >= 0.125:
			continue
		selected_edges.append(edge)
		extra_edges += 1
	if extra_edges == 0:
		for edge in candidate_edges:
			if not tree_edges.has(edge):
				selected_edges.append(edge)
				extra_edges = 1
				break
	var corridors: Array = []
	for edge_index in selected_edges.size():
		var edge: Vector2i = selected_edges[edge_index]
		var avoid_reuse := edge_index >= tree_edges.size()
		var cells := _weighted_route(centers[edge.x],centers[edge.y],room_cells,open_cells,avoid_reuse)
		corridors.append(cells)
		for cell in cells:
			open_cells[cell] = true
	var reachable := _flood(centers[0],open_cells)
	if reachable.size() != open_cells.size():
		push_error("Dungeon tile graph disconnected: " + dungeon_id)
	var reward_index := 1
	var longest := -1
	for i in range(1,centers.size()):
		var route := _open_route(centers[0],centers[i],open_cells)
		if route.size() > longest:
			longest = route.size()
			reward_index = i
	var guard_positions: Array[Vector3] = []
	for i in range(1,centers.size()):
		if i == reward_index:
			continue
		guard_positions.append(_world_point(origin,centers[i])+Vector3.UP*0.15)
		if guard_positions.size() >= 2:
			break
	return {
		"id":dungeon_id,"biome":biome,"origin":origin,"floor_y":origin.y,
		"grid_size":GRID_SIZE,"cell_size":CELL_SIZE,"rooms":rooms,"room_centers":centers,
		"room_edges":selected_edges,"corridors":corridors,"open_cells":open_cells,
		"start_cell":centers[0],"reward_cell":centers[reward_index],
		"start_position":_world_point(origin,centers[0])+Vector3.UP*0.15,
		"exit_position":_world_point(origin,centers[0]+Vector2i(-1,0))+Vector3.UP*0.15,
		"reward_position":_world_point(origin,centers[reward_index])+Vector3.UP*0.15,
		"guard_positions":guard_positions,"extra_edges":extra_edges,"reachable_tiles":reachable.size(),
	}

static func world_to_cell(layout: Dictionary, point: Vector3) -> Vector2i:
	var origin: Vector3 = layout.origin
	var center := float(int(layout.grid_size)-1)*0.5
	return Vector2i(roundi((point.x-origin.x)/float(layout.cell_size)+center),roundi((point.z-origin.z)/float(layout.cell_size)+center))

static func cell_to_world(layout: Dictionary, cell: Vector2i) -> Vector3:
	return _world_point(layout.origin,cell)

static func route(layout: Dictionary, from: Vector3, to: Vector3) -> PackedVector3Array:
	var start := world_to_cell(layout,from)
	var goal := world_to_cell(layout,to)
	var cells := _open_route(start,goal,layout.open_cells)
	var points := PackedVector3Array()
	for cell in cells:
		points.append(cell_to_world(layout,cell)+Vector3.UP*0.05)
	return points

static func line_is_open(layout: Dictionary, from: Vector3, to: Vector3) -> bool:
	var step_count := maxi(1,int(ceil(Vector2(to.x-from.x,to.z-from.z).length()/(CELL_SIZE*0.35))))
	for i in range(step_count+1):
		var point := from.lerp(to,float(i)/step_count)
		if not layout.open_cells.has(world_to_cell(layout,point)):
			return false
	return true

static func _world_point(origin: Vector3, cell: Vector2i) -> Vector3:
	var center := float(GRID_SIZE-1)*0.5
	return origin+Vector3((cell.x-center)*CELL_SIZE,0,(cell.y-center)*CELL_SIZE)

static func _delaunay_edges(centers: Array[Vector2i]) -> Array[Vector2i]:
	var points := PackedVector2Array()
	for center in centers:
		points.append(Vector2(center))
	var triangles := Geometry2D.triangulate_delaunay(points)
	var edges: Array[Vector2i] = []
	for i in range(0,triangles.size(),3):
		for pair in [Vector2i(triangles[i],triangles[i+1]),Vector2i(triangles[i+1],triangles[i+2]),Vector2i(triangles[i+2],triangles[i])]:
			var edge := Vector2i(mini(pair.x,pair.y),maxi(pair.x,pair.y))
			if not edges.has(edge):
				edges.append(edge)
	# Collinear points or a degenerate triangulation still receive a connected graph.
	if edges.is_empty():
		for i in range(1,centers.size()):
			edges.append(Vector2i(i-1,i))
	return edges

static func _minimum_tree(centers: Array[Vector2i], candidate_edges: Array[Vector2i]) -> Array[Vector2i]:
	var selected: Array[Vector2i] = []
	var visited: Dictionary = {0:true}
	while visited.size() < centers.size():
		var best := Vector2i(-1,-1)
		var length := INF
		for edge in candidate_edges:
			if visited.has(edge.x) == visited.has(edge.y):
				continue
			var candidate := Vector2(centers[edge.x]-centers[edge.y]).length_squared()
			if candidate < length:
				best = edge
				length = candidate
		if best.x < 0:
			# A disconnected Delaunay result should not strand a room.
			for from_index in visited:
				for to_index in centers.size():
					if visited.has(to_index):
						continue
					var candidate := Vector2(centers[from_index]-centers[to_index]).length_squared()
					if candidate < length:
						best = Vector2i(from_index,to_index)
						length = candidate
		if best.x < 0:
			break
		selected.append(best)
		visited[best.x] = true
		visited[best.y] = true
	return selected

static func _weighted_route(start: Vector2i, goal: Vector2i, room_cells: Dictionary, open_cells: Dictionary, avoid_reuse: bool) -> Array[Vector2i]:
	var frontier: Array[Vector2i] = [start]
	var cost: Dictionary = {start:0.0}
	var previous: Dictionary = {}
	while not frontier.is_empty():
		var best_index := 0
		var best_score := INF
		for i in frontier.size():
			var cell: Vector2i = frontier[i]
			var score: float = cost[cell]+absf(cell.x-goal.x)+absf(cell.y-goal.y)
			if score < best_score:
				best_score = score
				best_index = i
		var current: Vector2i = frontier.pop_at(best_index)
		if current == goal:
			break
		for direction in DIRS:
			var next := current+direction
			if next.x < 1 or next.y < 1 or next.x >= GRID_SIZE-1 or next.y >= GRID_SIZE-1:
				continue
			var step_cost := 10.0 if room_cells.has(next) else (20.0 if avoid_reuse else 1.0) if open_cells.has(next) else 5.0
			var proposal: float = cost[current]+step_cost
			if proposal < float(cost.get(next,INF)):
				cost[next] = proposal
				previous[next] = current
				if not frontier.has(next):
					frontier.append(next)
	var route: Array[Vector2i] = [goal]
	var cursor := goal
	for guard in GRID_SIZE*GRID_SIZE:
		if cursor == start or not previous.has(cursor):
			break
		cursor = previous[cursor]
		route.append(cursor)
	route.reverse()
	return route

static func _open_route(start: Vector2i, goal: Vector2i, open_cells: Dictionary) -> Array[Vector2i]:
	if not open_cells.has(start) or not open_cells.has(goal):
		return []
	var queue: Array[Vector2i] = [start]
	var previous: Dictionary = {start:start}
	var head := 0
	while head < queue.size() and not previous.has(goal):
		var current: Vector2i = queue[head]
		head += 1
		for direction in DIRS:
			var next := current+direction
			if open_cells.has(next) and not previous.has(next):
				previous[next] = current
				queue.append(next)
	var route: Array[Vector2i] = []
	if not previous.has(goal):
		return route
	var cursor := goal
	while cursor != start:
		route.append(cursor)
		cursor = previous[cursor]
	route.append(start)
	route.reverse()
	return route

static func _flood(start: Vector2i, open_cells: Dictionary) -> Dictionary:
	var visited: Dictionary = {start:true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for direction in DIRS:
			var next := cell+direction
			if open_cells.has(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	return visited
