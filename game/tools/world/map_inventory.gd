extends SceneTree
## Lists what a map scene holds, for a design review (#833): every collider (CSG with collision,
## static bodies, areas), every drawn mesh, every light, with world bounds and materials, as JSON
## lines in a file. Nothing is judged here; `docs/research/map-review.md` says how the lists are
## read.
##
##   godot --headless --path game -s res://tools/world/map_inventory.gd -- \
##     --scene=res://world/drive_in_greybox.tscn --out=<absolute>.json

var _rows: Array = []


func _initialize() -> void:
	var scene_path := ""
	var out := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	var root_node := (load(scene_path) as PackedScene).instantiate() as Node3D
	root.add_child(root_node)
	for _i in 6:
		await physics_frame
	_walk(root_node, root_node)
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(_rows, "\t"))
	file.close()
	print("inventory rows: ", _rows.size(), " -> ", out)
	quit()


func _walk(node: Node, base: Node) -> void:
	var path := String(base.get_path_to(node))
	if node is CSGShape3D:
		var csg := node as CSGShape3D
		if csg.get_parent() is CSGShape3D:
			pass
		else:
			(
				_rows
				. append(
					{
						"kind": "csg",
						"path": path,
						"type": node.get_class(),
						"visible": csg.is_visible_in_tree(),
						"collide": csg.use_collision,
						"layer": csg.collision_layer,
						"mask": csg.collision_mask,
						"aabb": _aabb(csg.global_transform * csg.get_aabb()),
						"size": _size(csg),
						"material": _material_name(csg.material),
					}
				)
			)
	elif node is CollisionObject3D:
		var body := node as CollisionObject3D
		for child in body.get_children():
			if child is CollisionShape3D and child.shape != null:
				var shape := child as CollisionShape3D
				var box := shape.global_transform * shape.shape.get_debug_mesh().get_aabb()
				(
					_rows
					. append(
						{
							"kind": "body",
							"path": path,
							"type": node.get_class(),
							"shape": shape.shape.get_class(),
							"layer": body.collision_layer,
							"mask": body.collision_mask,
							"disabled": shape.disabled,
							"visible": _visible(node),
							"aabb": _aabb(box),
						}
					)
				)
	elif node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var materials: Array = []
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_active_material(surface)
				materials.append(_material_name(material))
			(
				_rows
				. append(
					{
						"kind": "mesh",
						"path": path,
						"visible": mesh_node.is_visible_in_tree(),
						"mesh": mesh_node.mesh.resource_name,
						"override": _material_name(mesh_node.material_override),
						"materials": materials,
						"aabb": _aabb(mesh_node.global_transform * mesh_node.get_aabb()),
						"cast": mesh_node.cast_shadow,
					}
				)
			)
	elif node is Light3D:
		var light := node as Light3D
		(
			_rows
			. append(
				{
					"kind": "light",
					"path": path,
					"type": node.get_class(),
					"visible": light.is_visible_in_tree(),
					"pos": _vec(light.global_position),
					"range":
					(
						light.omni_range
						if light is OmniLight3D
						else (light.spot_range if light is SpotLight3D else 0.0)
					),
					"energy": light.light_energy,
					"color": light.light_color.to_html(false),
					"shadow": light.shadow_enabled,
					"circuit": _circuit(node),
				}
			)
		)
	for child in node.get_children():
		_walk(child, base)


func _circuit(node: Node) -> String:
	var at := node
	while at != null:
		if at.has_meta(&"circuit"):
			return String(at.get_meta(&"circuit"))
		at = at.get_parent()
	return ""


func _visible(node: Node) -> bool:
	if node is Node3D:
		return (node as Node3D).is_visible_in_tree()
	return true


func _size(csg: CSGShape3D) -> Array:
	if csg is CSGBox3D:
		return _vec((csg as CSGBox3D).size)
	return []


func _material_name(material: Material) -> String:
	if material == null:
		return ""
	if material.resource_path != "":
		return material.resource_path
	return material.get_class() + ":" + material.resource_name


func _aabb(box: AABB) -> Array:
	return [_vec(box.position), _vec(box.end)]


func _vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
