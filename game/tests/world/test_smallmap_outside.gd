# The small-map kit's roof and outside pieces and the backdrop past the playable bounds (issue #638,
# docs/research/maps/small-map-art.md). The pieces come from
# tools/blender/build_smallmap_outside.py, their fixtures from
# tools/world/build_smallmap_outside_fixtures.py, the backdrop from
# tools/world/build_smallmap_backdrop.py.
extends GdUnitTestSuite

const REPORT := "res://assets/smallmap/outside_pieces.json"
const FIXTURES := "res://world/smallmap/fixtures/%s.tscn"
const BACKDROP := "res://world/smallmap/backdrop.tscn"
const HAZE := "res://world/smallmap/backdrop_haze.gdshader"
const GLOW := "res://world/drive_in/glow.gdshader"
const SCREEN := "res://world/drive_in/screen.gdshader"
## Pieces with a far level of detail (the issue: the trees and the poles; the wire and the fence
## too).
const FAR := [
	"bare_tree_a", "bare_tree_b", "bare_tree_c", "utility_pole", "utility_wire", "wire_fence"
]
## What the whole backdrop may cost: every triangle of every copy, and the nodes that draw.
const BACKDROP_TRIANGLES := 75000
const BACKDROP_DRAWS := 40
## How far a blocker may stand out of its model's bounds (metres).
const BLOCKER_SLACK := 0.15


func _report() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(REPORT))


func test_every_piece_is_in_its_triangle_budget_and_exported() -> void:
	var report := _report()
	assert_int(report.size()).is_greater_equal(18)
	for name: String in report:
		var piece: Dictionary = report[name]
		(
			assert_int(int(piece["tris"]))
			. override_failure_message(
				"%s has %d triangles, over %d" % [name, piece["tris"], piece["budget"]]
			)
			. is_less_equal(int(piece["budget"]))
		)
		assert_bool(ResourceLoader.exists("res://assets/smallmap/%s.gltf" % name)).is_true()


func test_far_levels_of_detail_are_lighter_and_no_taller() -> void:
	var report := _report()
	for name: String in FAR:
		var near: Dictionary = report[name]
		var far: Dictionary = report[name + "_far"]
		assert_int(int(far["tris"])).is_less(int(near["tris"]))
		assert_float(float(far["size_xyz_blender"][2])).is_less_equal(
			float(near["size_xyz_blender"][2]) + 0.05
		)


func test_every_near_piece_has_a_fixture_whose_blockers_are_hidden_and_inside_the_model() -> void:
	var problems: Array[String] = []
	for name: String in _report():
		if name.ends_with("_far"):
			continue
		if not ResourceLoader.exists(FIXTURES % name):
			problems.append("%s has no fixture" % name)
			continue
		var fixture := auto_free((load(FIXTURES % name) as PackedScene).instantiate()) as Node3D
		add_child(fixture)
		var model := _bounds(fixture.get_node("Model"))
		for blocker: CSGShape3D in fixture.find_children("Blocker*", "CSGShape3D", false, false):
			if blocker.visible or not blocker.use_collision:
				problems.append("%s/%s must be hidden and collide" % [name, blocker.name])
			var box := blocker.global_transform * blocker.get_aabb()
			if not model.grow(BLOCKER_SLACK).encloses(box):
				problems.append(
					"%s/%s %s is outside the model %s" % [name, blocker.name, box, model]
				)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_backdrop_fills_every_multimesh_and_makes_no_light() -> void:
	var backdrop := auto_free((load(BACKDROP) as PackedScene).instantiate()) as Backdrop
	add_child(backdrop)
	var problems: Array[String] = []
	for multi: MultiMeshInstance3D in backdrop.find_children(
		"*", "MultiMeshInstance3D", true, false
	):
		if multi.multimesh.mesh == null:
			problems.append("%s has no mesh" % backdrop.get_path_to(multi))
		if multi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			problems.append("%s casts a shadow" % backdrop.get_path_to(multi))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
	assert_array(backdrop.find_children("*", "Light3D", true, false)).is_empty()
	assert_array(backdrop.find_children("*", "CollisionObject3D", true, false)).is_empty()
	for csg: CSGShape3D in backdrop.find_children("*", "CSGShape3D", true, false):
		assert_bool(csg.use_collision).is_false()


func test_every_backdrop_model_lights_and_hazes_itself() -> void:
	# Unshaded: no light pass, and a lamp inside the building never reaches the drive-in.
	var backdrop := auto_free((load(BACKDROP) as PackedScene).instantiate()) as Backdrop
	for multi: MultiMeshInstance3D in backdrop.find_children(
		"*", "MultiMeshInstance3D", true, false
	):
		var material := multi.material_override as ShaderMaterial
		assert_object(material).is_not_null()
		(
			assert_bool([HAZE, GLOW].has(material.shader.resource_path))
			. override_failure_message("%s wears %s" % [multi.name, material.shader.resource_path])
			. is_true()
		)
	for quad: MeshInstance3D in backdrop.find_children("*", "MeshInstance3D", true, false):
		var material := quad.material_override as ShaderMaterial
		(
			assert_bool([GLOW, SCREEN].has(material.shader.resource_path))
			. override_failure_message("%s wears %s" % [quad.name, material.shader.resource_path])
			. is_true()
		)
	for path: String in [HAZE, GLOW, SCREEN]:
		var code := ""
		for line in (load(path) as Shader).code.split("\n"):
			code += line.get_slice("//", 0) + "\n"  # the code, not its comments
		assert_bool(code.contains("unshaded")).is_true()
		(
			assert_bool(code.contains("TIME"))
			. override_failure_message("%s reads TIME" % path)
			. is_false()
		)


func test_the_backdrop_stands_outside_the_yard() -> void:
	var backdrop := auto_free((load(BACKDROP) as PackedScene).instantiate()) as Backdrop
	add_child(backdrop)
	var yard: Vector2 = backdrop.get_meta(&"yard_half")
	var inside: Array[String] = []
	for multi: MultiMeshInstance3D in backdrop.find_children(
		"*", "MultiMeshInstance3D", true, false
	):
		# The buffer as the scene wrote it: 12 floats a copy, each basis row followed by its
		# origin's coordinate.
		var buffer := multi.multimesh.buffer
		for index in multi.multimesh.instance_count:
			var local := Vector3(
				buffer[index * 12 + 3], buffer[index * 12 + 7], buffer[index * 12 + 11]
			)
			var at := multi.global_transform * local
			if absf(at.x) < yard.x - 0.01 and absf(at.z) < yard.y - 0.01:
				inside.append("%s #%d at %s" % [backdrop.get_path_to(multi), index, at])
	assert_array(inside).override_failure_message("\n".join(inside)).is_empty()


func test_the_backdrop_keeps_to_its_triangle_and_draw_budget() -> void:
	var backdrop := auto_free((load(BACKDROP) as PackedScene).instantiate()) as Backdrop
	add_child(backdrop)
	var triangles := 0
	var draws := 0
	for node: GeometryInstance3D in backdrop.find_children("*", "GeometryInstance3D", true, false):
		draws += 1
		var mesh: Mesh = null
		var copies := 1
		if node is MultiMeshInstance3D:
			mesh = (node as MultiMeshInstance3D).multimesh.mesh
			copies = (node as MultiMeshInstance3D).multimesh.instance_count
		elif node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		elif node is CSGBox3D:
			triangles += 12
			continue
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangles += (
				(indices.size() if not indices.is_empty() else vertices.size()) / 3 * copies
			)
	assert_int(triangles).is_less_equal(BACKDROP_TRIANGLES)
	assert_int(draws).is_less_equal(BACKDROP_DRAWS)


func test_the_haze_follows_the_scene_fog_ambient_and_moon() -> void:
	var world := Node3D.new()
	add_child(world)
	var environment := Environment.new()
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.2, 0.3, 0.5)
	environment.fog_light_energy = 0.5
	environment.fog_density = 0.035
	environment.ambient_light_color = Color(0.3, 0.36, 0.55)
	environment.ambient_light_energy = 0.24
	var holder := WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
	var moon := DirectionalLight3D.new()
	moon.light_energy = 0.36
	moon.rotation_degrees = Vector3(-40, 20, 0)
	world.add_child(moon)
	var backdrop := (load(BACKDROP) as PackedScene).instantiate() as Backdrop
	world.add_child(backdrop)
	backdrop._process(0.1)
	var material := (
		(backdrop.get_node("Woods/BareTreeAFar") as MultiMeshInstance3D).material_override
		as ShaderMaterial
	)
	var haze := environment.fog_light_color * 0.5
	assert_vector(material.get_shader_parameter(&"haze_color") as Vector3).is_equal_approx(
		Vector3(haze.r, haze.g, haze.b), Vector3.ONE * 0.001
	)
	assert_float(material.get_shader_parameter(&"fog_density")).is_equal_approx(0.035, 0.0001)
	var ambient := environment.ambient_light_color * 0.24
	assert_vector(material.get_shader_parameter(&"ambient") as Vector3).is_equal_approx(
		Vector3(ambient.r, ambient.g, ambient.b), Vector3.ONE * 0.001
	)
	assert_vector(material.get_shader_parameter(&"moon_direction") as Vector3).is_equal_approx(
		moon.global_basis.z, Vector3.ONE * 0.001
	)
	# Each copy hazes its own materials: a fresh copy still has the scene's numbers.
	var other := auto_free((load(BACKDROP) as PackedScene).instantiate()) as Backdrop
	var untouched := (
		(other.get_node("Woods/BareTreeAFar") as MultiMeshInstance3D).material_override
		as ShaderMaterial
	)
	assert_that(untouched.get_shader_parameter(&"fog_density")).is_not_equal(0.035)
	world.queue_free()


func test_a_fire_flickers_between_seven_tenths_and_full() -> void:
	for step in 400:
		var f := Backdrop.flicker(step * 0.05)
		assert_float(f).is_between(0.7, 1.0)


## The world bounds of every mesh under `node`.
func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
