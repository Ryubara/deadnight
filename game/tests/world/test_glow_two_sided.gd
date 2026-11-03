# A lit window reads from both sides (issue #701): the glow meshes a player can stand behind are
# drawn on both faces, so from inside a building the pane is lit glass, not a hole. And a pane
# lies in its opening, never inside a wall: with both faces drawn, a pane that overlapped a wall
# would shine through it. See `docs/research/glow-two-sided.md`.
extends GdUnitTestSuite

const GREYBOXES: Array[String] = [
	"res://world/drive_in_greybox.tscn",
	"res://world/smallmap/smallmap_greybox.tscn",
]
const GLOW_SCENES: Array[String] = [
	"res://world/drive_in/glow_pane.tscn",
	"res://world/smallmap/lights/door_glow.tscn",
]
## A shader whose render mode blends over what is behind it is see-through: a glow, a haze or a
## window, and culling its back face hides it from a player standing behind.
const BLENDING := "blend_add|blend_sub|blend_mul"
## How far inside a pane's edge the wall check samples, so a pane filling its opening exactly (its
## edge on the wall's face) is not counted as inside the wall.
const EDGE_INSET := 0.03
## A mesh thinner than this on one axis is a flat pane or card: one a player can walk round to its
## back. A closed vessel (the soda fountain's glass and tonic) shows its far wall through its near
## one, so culling its back faces is right.
const FLAT := 0.05


## A transparent or blending standard material, or a shader that blends.
func _is_see_through(material: Material) -> bool:
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		return (
			standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			or standard.blend_mode != BaseMaterial3D.BLEND_MODE_MIX
		)
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader == null:
			return false
		var regex := RegEx.create_from_string("render_mode[^;]*(%s)" % BLENDING)
		return regex.search(shader.code) != null
	return false


## A closed primitive (a box, cylinder, sphere or torus: the perk coolers' thin glass front, the
## re-cut bench's ring of light) has a near face from every side, so culling its back faces is right
## even when it is thin.
func _is_closed(mesh: Mesh) -> bool:
	return (
		mesh is BoxMesh
		or mesh is CylinderMesh
		or mesh is SphereMesh
		or mesh is CapsuleMesh
		or mesh is PrismMesh
		or mesh is TorusMesh
	)


func _is_double_sided(material: Material) -> bool:
	if material is StandardMaterial3D:
		return (material as StandardMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED
	if material is ShaderMaterial:
		var regex := RegEx.create_from_string("render_mode[^;]*cull_disabled")
		return regex.search((material as ShaderMaterial).shader.code) != null
	return false


## The see-through meshes under `root` that are not double-sided, as "path: material".
func _one_sided_glows(root: Node) -> Array[String]:
	var found: Array[String] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or _is_closed(instance.mesh):
			continue
		var size := instance.mesh.get_aabb().size
		if minf(size.x, minf(size.y, size.z)) > FLAT:
			continue
		var materials: Array[Material] = []
		if instance.material_override != null:
			materials.append(instance.material_override)
		else:
			for surface in instance.mesh.get_surface_count():
				materials.append(instance.get_active_material(surface))
		for material in materials:
			if material != null and _is_see_through(material) and not _is_double_sided(material):
				found.append("%s: %s" % [root.get_path_to(instance), material])
	return found


func _instance(path: String) -> Node:
	var node := (load(path) as PackedScene).instantiate()
	add_child(node)
	auto_free(node)
	return node


func test_every_glow_piece_a_player_can_stand_behind_is_drawn_on_both_faces() -> void:
	for path in GLOW_SCENES:
		assert_array(_one_sided_glows(_instance(path))).override_failure_message(path).is_empty()


func test_no_see_through_mesh_of_a_map_is_one_sided() -> void:
	for path in GREYBOXES:
		var found := _one_sided_glows(_instance(path))
		assert_array(found).override_failure_message("%s: %s" % [path, found]).is_empty()


func test_the_check_sees_a_one_sided_pane() -> void:
	# A check that never finds a pane passes with the fix off: a one-sided additive quad is caught.
	var instance := MeshInstance3D.new()
	instance.mesh = QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	instance.material_override = material
	var root := Node3D.new()
	root.add_child(instance)
	auto_free(root)
	assert_array(_one_sided_glows(root)).has_size(1)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	assert_array(_one_sided_glows(root)).is_empty()


func test_a_glow_pane_lies_in_its_opening_and_not_inside_a_wall() -> void:
	var lot := _instance("res://world/drive_in_greybox.tscn") as Node3D
	var panes := lot.find_children("*", "GlowPane", true, false)
	assert_int(panes.size()).is_greater(0)
	var walls: Array[CSGBox3D] = []
	for node in lot.find_children("Wall*", "CSGBox3D", true, false):
		walls.append(node as CSGBox3D)
	assert_int(walls.size()).is_greater(0)
	for node in panes:
		var pane := node as GlowPane
		var quad := (pane.get_node("Pane") as MeshInstance3D).mesh as QuadMesh
		for sample in _pane_samples(pane, quad.size):
			for wall in walls:
				(
					assert_bool(_inside_box(wall, sample))
					. override_failure_message(
						"%s at %s is inside %s" % [pane.name, sample, wall.name]
					)
					. is_false()
				)


## Points over a pane's face, `EDGE_INSET` in from its edge.
func _pane_samples(pane: Node3D, size: Vector2) -> Array[Vector3]:
	var samples: Array[Vector3] = []
	var half := size * 0.5 - Vector2.ONE * EDGE_INSET
	for x in [-half.x, 0.0, half.x]:
		for y in [-half.y, 0.0, half.y]:
			samples.append(pane.to_global(Vector3(x, y, 0.0)))
	return samples


func _inside_box(box: CSGBox3D, point: Vector3) -> bool:
	var local := box.to_local(point)
	var half := box.size * 0.5
	return absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z
