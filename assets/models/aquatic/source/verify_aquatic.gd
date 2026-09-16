extends SceneTree

func _initialize() -> void:
	var failures := 0
	for species in ["ribbonwake", "lanternjaw", "tidebell"]:
		var packed := load("res://assets/models/aquatic/%s.glb" % species) as PackedScene
		if packed == null:
			failures += 1
			continue
		var actor := packed.instantiate()
		var meshes := actor.find_children("*", "MeshInstance3D", true, false)
		if actor is MeshInstance3D:
			meshes.append(actor)
		var textured := 0
		var colored := 0
		var luminous := 0
		for mesh in meshes:
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if material == null:
					failures += 1
					continue
				if material.albedo_texture != null:
					textured += 1
				if material.albedo_color.b > material.albedo_color.r * 1.5:
					colored += 1
				if material.emission_enabled and material.emission.r > 0.4:
					luminous += 1
		if meshes.size() != 1 or textured < 7 or colored < 5 or (species == "lanternjaw" and luminous == 0):
			failures += 1
		print("AQUATIC_IMPORTED ",species," meshes=",meshes.size()," textured=",textured," blue=",colored," amber_emission=",luminous)
		actor.free()
	print("AQUATIC_IMPORT_FAILURES ",failures)
	quit(failures)
