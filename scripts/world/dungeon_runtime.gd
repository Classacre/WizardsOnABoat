class_name SpellwakeDungeonRuntime
extends Node3D
## Small batched structural geometry for a generated dungeon layout.

const LAYOUT = preload("res://scripts/world/dungeon_layout.gd")
const STONE_SHADER = preload("res://shaders/dungeon_stone.gdshader")

var layout: Dictionary

func configure(value: Dictionary) -> void:
	layout = value
	name = ("Dungeon_"+str(value.id)).validate_node_name()
	position = value.origin

func _ready() -> void:
	if layout.is_empty():
		return
	_build_floor_and_ceiling()
	_build_walls()
	_build_room_decor()
	_build_lights()
	_place_furnishing("ruin_arch",layout.exit_position,0.64)
	_place_furnishing("loot_chest",layout.reward_position)

func _build_floor_and_ceiling() -> void:
	var floor_tool := SurfaceTool.new()
	floor_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ceiling_tool := SurfaceTool.new()
	ceiling_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = float(layout.cell_size)*0.5
	for cell in layout.open_cells:
		var p: Vector3 = LAYOUT.cell_to_world(layout,cell)-position
		var color_value := Color("82908b") if int(cell.x+cell.y)%3==0 else Color("a7afa0")
		var a := p+Vector3(-half,0,-half)
		var b := p+Vector3(half,0,-half)
		var c := p+Vector3(half,0,half)
		var d := p+Vector3(-half,0,half)
		_add_quad(floor_tool,a,b,c,d,color_value)
		var roof_color := Color("43585b")
		_add_quad(ceiling_tool,a+Vector3.UP*3.6,d+Vector3.UP*3.6,c+Vector3.UP*3.6,b+Vector3.UP*3.6,roof_color)
	floor_tool.generate_normals()
	ceiling_tool.generate_normals()
	var floor_mesh := floor_tool.commit()
	var ceiling_mesh := ceiling_tool.commit()
	var floor_node := MeshInstance3D.new()
	floor_node.name = "DungeonFloor"
	floor_node.mesh = floor_mesh
	floor_node.material_override = _stone_material(true)
	add_child(floor_node)
	floor_node.create_trimesh_collision()
	var ceiling_node := MeshInstance3D.new()
	ceiling_node.name = "DungeonCeiling"
	ceiling_node.mesh = ceiling_mesh
	ceiling_node.material_override = _stone_material(true)
	add_child(ceiling_node)
	var roof := StaticBody3D.new()
	roof.name = "DungeonRoofCollision"
	var roof_shape := CollisionShape3D.new()
	var roof_box := BoxShape3D.new()
	roof_box.size = Vector3(float(layout.grid_size)*float(layout.cell_size),0.3,float(layout.grid_size)*float(layout.cell_size))
	roof_shape.shape = roof_box
	roof_shape.position.y = 3.75
	roof.add_child(roof_shape)
	add_child(roof)

func _build_walls() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(layout.cell_size),3.6,0.24)
	mesh.material = _stone_material(false)
	var transforms: Array[Transform3D] = []
	for cell in layout.open_cells:
		var p: Vector3 = LAYOUT.cell_to_world(layout,cell)-position
		for direction in LAYOUT.DIRS:
			if layout.open_cells.has(cell+direction):
				continue
			var angle := PI*0.5 if direction.x != 0 else 0.0
			var basis_value := Basis(Vector3.UP,angle)
			var center := p+Vector3(direction.x*float(layout.cell_size)*0.5,1.8,direction.y*float(layout.cell_size)*0.5)
			transforms.append(Transform3D(basis_value,center))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i,transforms[i])
	var walls := MultiMeshInstance3D.new()
	walls.name = "DungeonWalls"
	walls.multimesh = multi
	add_child(walls)
	var body := StaticBody3D.new()
	body.name = "DungeonWallCollision"
	var wall_shape := BoxShape3D.new()
	wall_shape.size = mesh.size
	for transform_value in transforms:
		var shape := CollisionShape3D.new()
		shape.shape = wall_shape
		shape.transform = transform_value
		body.add_child(shape)
	add_child(body)

func _build_lights() -> void:
	var points: Array[Vector3] = [layout.start_position,layout.reward_position]
	for guard in layout.guard_positions:
		points.append(guard)
	for point in points:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("cde4ca")
		lamp.light_energy = 1.0
		lamp.omni_range = 15.0
		lamp.shadow_enabled = false
		lamp.position = point-position+Vector3.UP*2.2
		add_child(lamp)

func _build_room_decor() -> void:
	var kit := "root_kit" if layout.biome == "Mangrove Orchard" else "tide_kit" if layout.biome in ["Basalt Heath","Glass Dunes"] else "coastal_kit"
	var parts := ["root_column","root_lintel"] if kit == "root_kit" else ["tide_pillar","tide_block"] if kit == "tide_kit" else ["coastal_pillar","coastal_moss"]
	for room in layout.rooms:
		var near_corner: Vector2i = room.position
		var far_corner: Vector2i = room.end-Vector2i.ONE
		_place_kit_piece(kit,parts[0],LAYOUT.cell_to_world(layout,near_corner),0.8,PI*0.25)
		_place_kit_piece(kit,parts[1],LAYOUT.cell_to_world(layout,far_corner),0.7,-PI*0.75)

func _place_kit_piece(kit: String, module_name: String, world_point: Vector3, scale_value: float, angle: float) -> void:
	var path := "res://assets/models/supplied/%s.glb" % kit
	if not ResourceLoader.exists(path):
		return
	var source: Node3D = load(path).instantiate()
	var original: Node3D = source.find_child(module_name,true,false) as Node3D
	if original == null:
		source.free()
		return
	var model: Node3D = original.duplicate()
	source.free()
	model.position = world_point-position
	model.rotation.y = angle
	model.scale = Vector3.ONE*scale_value
	add_child(model)

func _place_furnishing(asset: String, world_point: Vector3, scale_value := 1.0) -> void:
	var path := "res://assets/models/supplied/%s.glb" % asset
	if not ResourceLoader.exists(path):
		return
	var model: Node3D = load(path).instantiate()
	model.position = world_point-position
	model.scale = Vector3.ONE*scale_value
	add_child(model)

func _stone_material(floor_mode: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = STONE_SHADER
	var biome: String = str(layout.biome)
	var tone := Color("84918a")
	var moss := 0.11
	if biome == "Mangrove Orchard":
		tone = Color("82918b")
		moss = 0.20
	elif biome == "Basalt Heath":
		tone = Color("777c7b")
		moss = 0.05
	elif biome == "Glass Dunes":
		tone = Color("ad9f88")
		moss = 0.03
	elif biome == "Saltgrass Coast":
		tone = Color("a39f87")
		moss = 0.08
	material.set_shader_parameter("base_color",tone)
	material.set_shader_parameter("floor_mode",floor_mode)
	material.set_shader_parameter("moss_amount",moss)
	return material

func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color_value: Color) -> void:
	for point in [a,b,c,a,c,d]:
		tool.set_color(color_value)
		tool.add_vertex(point)
