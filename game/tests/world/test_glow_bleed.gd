# No glow and no light shows on the far side of a wall from its lamp (issue #832;
# docs/research/glow-bleed.md). The Compatibility renderer casts no shadow: a halo, a pool or a
# cone is  an additive quad that only the depth test hides, and a lamp is an unshadowed light, so
# each reaches  into the next room as soon as its card or its range does. The first map's SNACKS
# sign did both: a  flat halo that stood over the roof and an omni light 1.2 m outside its wall
# that lit the stand's  floor and roof pink from behind the wall.
extends GdUnitTestSuite

const GREYBOXES: Array[String] = [
	"res://world/drive_in_greybox.tscn",
	"res://world/smallmap/smallmap_greybox.tscn",
]
const SIGN := "Concession/Lamps/NeonSnacks"
## What a lamp still lights through a wall after the room layers (issue #841;
## docs/research/room-lights.md): `[the most it gives a surface, why it stays]`. A lamp lights the
## default layer and its own room's, and a floor, wall or ceiling that must not take it sits on a
## layer the lamp lacks; what stays is a box that is in two places at once (a mask is the whole
## box's), or another issue's lamp. The test fails when a number grows, when a lamp not in the table
## leaks (`GlowBleed.peaks`) and when a listed lamp stops.
const LEAKS := {
	"res://world/drive_in_greybox.tscn":
	{
		"ProjectionBooth/Lamps/Lower":
		[
			0.39,
			"its walls are one box over both storeys: the lamp's light on the upper half is the wall's",
		],
		"ShopProps/ReCut/Glow":
		[0.28, "the booth's east wall is one box over both storeys, like the lower lamp's"],
	},
	# The upper hall's lamp lit the roof terrace through the one slab under both until #917 cut the
	# terrace into its own slab, outdoors.
	"res://world/smallmap/smallmap_greybox.tscn": {},
}
## What the room layers take from a lamp that it could see: `"lamp|surface"` and why it is let go. A
## lamp that loses a surface not listed here is darkening a room it lights; the test fails on it and
## on a line that no longer loses.
const LOST := {
	"res://world/drive_in_greybox.tscn":
	{
		"Concession/Lamps/InteriorW|Midway/Ground1_0":
		"the doorway's spill is the glow cards' job, and the posts light that ground",
		"Concession/Lamps/InteriorE|Midway/Ground1_0":
		"the doorway's spill is the glow cards' job, and the posts light that ground",
		"Concession/Lamps/InteriorN|Field/GroundC1_3":
		"the window's spill: the sign's spot gives that ground 8 and the posts 1.5",
	},
	"res://world/smallmap/smallmap_greybox.tscn":
	{
		"Start/Lamp3/Light|UpperB/WallS0":
		"up the stairwell onto the next hall's wall base, above a slab",
		"Start/Lamp3/Light|Ceilings/SideSlabS":
		"up the stairwell onto the next hall's floor, a room's glow in another room",
		"UpperA/Lamp6/Light|Side/WallS3": "the wall below, seen through the slab: it was a leak",
		"Start/Lamp1/Light|Roof/ParapetS":
		"the terrace's railing, over the hall's roof: it would be a leak",
		"Start/Lamp1/Light|Roof/ParapetW":
		"the terrace's railing, over the hall's roof: it would be a leak",
		"Start/Lamp2/Light|Roof/ParapetS":
		"the terrace's railing, over the hall's roof: it would be a leak",
		"Start/Lamp2/Light|Roof/ParapetE":
		"the terrace's railing, over the hall's roof: it would be a leak",
		"ShopProps/Soda/Glow|Roof/ParapetW":
		"the terrace's railing, over the hall's roof: it would be a leak",
		"UpperA/Lamp6/Light|Ceilings/SideSlabS":
		"the next hall's floor, seen through its own walls: it was a leak",
	},
}


func _instance(path: String) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	add_child(node)
	auto_free(node)
	return node


## A wall 4 m wide and 3 m high along x at z = 0 (its faces at z = -0.1 and 0.1), on its own.
func _wall_box(parent: Node3D) -> CSGBox3D:
	var wall := CSGBox3D.new()
	wall.name = "WallTest"
	wall.size = Vector3(4.0, 3.0, 0.2)
	wall.position = Vector3(0.0, 1.5, 0.0)
	wall.use_collision = true
	parent.add_child(wall)
	return wall


## A pool of glow of `size` metres lying on the floor at `at`, on the lot's glow shader.
func _pool(parent: Node3D, at: Vector3, size: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.orientation = PlaneMesh.FACE_Y
	var pool := MeshInstance3D.new()
	pool.mesh = quad
	pool.material_override = LightCards.glow(Color.WHITE, false, {"falloff": 1.5})
	pool.position = at
	parent.add_child(pool)
	return pool


func test_no_glow_card_of_a_map_shows_behind_a_wall() -> void:
	for path in GREYBOXES:
		var found := GlowBleed.bleeding_cards(_instance(path))
		assert_array(found).override_failure_message("%s: %s" % [path, found]).is_empty()


func test_the_check_sees_a_pool_that_runs_through_a_wall_and_the_clip_cures_it() -> void:
	# A check that never finds a pool passes with the fix off: a 4 m pool a metre from the wall's
	# face  reaches 1 m behind it, and the planes `GlowClip` finds cut it off at the face.
	var root := Node3D.new()
	add_child(root)
	auto_free(root)
	var wall := _wall_box(root)
	var pool := _pool(root, Vector3(0.0, 0.02, -1.1), 4.0)
	var lamp_at := Vector3(0.0, 2.0, -1.1)
	var found := GlowBleed.bleeding_cards(root, [pool] as Array[MeshInstance3D])
	assert_array(found).has_size(1)
	var planes := GlowClip.planes_around(lamp_at, 2.0, GlowClip.walls(root))
	assert_array(planes).has_size(1)
	GlowClip.apply(pool.material_override as ShaderMaterial, planes)
	assert_array(GlowBleed.bleeding_cards(root, [pool] as Array[MeshInstance3D])).is_empty()
	wall.free()


func test_a_clip_plane_is_off_by_default_and_on_in_both_shaders() -> void:
	for path in ["res://world/drive_in/glow.gdshader", "res://world/drive_in/beam.gdshader"]:
		var code := (load(path) as Shader).code
		assert_str(code).override_failure_message(path).contains("uniform vec4 clip_a = vec4(0.0)")
		assert_str(code).override_failure_message(path).contains("uniform vec4 clip_b = vec4(0.0)")
		assert_str(code).override_failure_message(path).contains("discard")


func test_the_sign_light_faces_out_and_lights_nothing_behind_its_wall() -> void:
	var lot := _instance(GREYBOXES[0])
	var sign := lot.get_node(SIGN) as LotNeonSign
	var light := sign.get_node("Light") as Light3D
	# A spot's cone never reaches behind the plane its apex stands in: an omni 1.2 m from the wall
	# lit the  stand's floor (up to 3 energy) and roof (up to 2.3) through it.
	assert_object(light).is_instanceof(SpotLight3D)
	var outward := sign.global_basis.z.normalized()
	assert_float((-light.global_basis.z).dot(outward)).is_greater(0.99)
	assert_float((light as SpotLight3D).spot_angle).is_less(90.0)
	assert_array(GlowBleed.bleeding_lights(lot, [light] as Array[Light3D])).is_empty()


func test_the_sign_halo_stops_at_the_top_of_its_wall() -> void:
	var lot := _instance(GREYBOXES[0])
	var halo := lot.get_node(SIGN + "/Halo") as MeshInstance3D
	var plane: Vector4 = (halo.material_override as ShaderMaterial).get_shader_parameter(&"clip_a")
	var wall_top := 4.0
	assert_float(plane.y).is_equal_approx(1.0, 0.001)
	assert_float(plane.w).is_equal_approx(wall_top, 0.01)
	# The flat card is 4 m high round the sign's 3.3 m: its top would stand over the roof from
	# behind.
	assert_float(halo.global_position.y + 2.0).is_greater(wall_top)


func test_the_check_sees_an_omni_lighting_through_a_wall_and_a_spot_that_does_not() -> void:
	# A check that never finds a lamp passes with the fix off: an omni a metre in front of a wall
	# lights a  floor behind it; a spot facing away from the wall lights nothing there.
	var root := Node3D.new()
	add_child(root)
	auto_free(root)
	_wall_box(root)
	var floor_box := CSGBox3D.new()
	floor_box.name = "Floor0"
	floor_box.size = Vector3(8.0, 0.4, 8.0)
	floor_box.position = Vector3(0.0, -0.2, 0.0)
	floor_box.use_collision = true
	root.add_child(floor_box)
	var omni := OmniLight3D.new()
	omni.omni_range = 6.0
	omni.light_energy = 3.0
	omni.position = Vector3(0.0, 2.0, -1.0)
	root.add_child(omni)
	assert_array(GlowBleed.bleeding_lights(root, [omni] as Array[Light3D])).is_not_empty()
	var spot := SpotLight3D.new()
	spot.spot_range = 6.0
	spot.spot_angle = 80.0
	spot.light_energy = 3.0
	spot.position = Vector3(0.0, 2.0, -1.0)
	root.add_child(spot)  # a spot faces -Z: away from the wall, which is at +Z of it
	assert_array(GlowBleed.bleeding_lights(root, [spot] as Array[Light3D])).is_empty()


func test_no_lamp_of_a_map_lights_through_a_wall_beyond_what_the_table_allows() -> void:
	for path in GREYBOXES:
		var allowed: Dictionary = LEAKS[path]
		var over: Array[String] = []
		var peaks := GlowBleed.peaks(_instance(path))
		for lamp: String in peaks:
			if not allowed.has(lamp):
				over.append(
					"%s lights through a wall (%.2f) and is not in the table" % [lamp, peaks[lamp]]
				)
			elif peaks[lamp] > allowed[lamp][0]:
				over.append(
					(
						"%s lights through a wall up to %.2f, over %.2f"
						% [lamp, peaks[lamp], allowed[lamp][0]]
					)
				)
		for lamp: String in allowed:
			if not peaks.has(lamp):
				over.append("%s no longer leaks: remove it from the table" % lamp)
			elif String(allowed[lamp][1]).length() < 20:
				over.append("%s stays in the table without a reason" % lamp)
		assert_array(over).override_failure_message("%s: %s" % [path, over]).is_empty()


func test_the_room_layers_take_no_light_from_a_lamp_beyond_the_table() -> void:
	# A lamp that names layers must not darken what it lights: every surface it could see and
	# loses to its mask is a line of the table, with its reason.
	for path in GREYBOXES:
		var allowed: Dictionary = LOST[path]
		var found := {}
		for lost in GlowBleed.lost_lights(_instance(path)):
			found["%s|%s" % [lost["lamp"], lost["surface"]]] = lost["peak"]
		var over: Array[String] = []
		for key: String in found:
			if not allowed.has(key):
				over.append("%s loses a light (%.2f) and is not in the table" % [key, found[key]])
		for key: String in allowed:
			if not found.has(key):
				over.append("%s no longer loses: remove it from the table" % key)
			elif String(allowed[key]).length() < 20:
				over.append("%s is let go without a reason" % key)
		assert_array(over).override_failure_message("%s: %s" % [path, over]).is_empty()


func test_a_lamp_that_names_layers_keeps_the_default_one() -> void:
	# The dead, the player and the props are on the default layer: a lamp that dropped it would
	# light a room's floor and leave everyone in it dark.
	for path in GREYBOXES:
		var map := _instance(path)
		var named := 0
		for node in map.find_children("*", "Light3D", true, false):
			var light := node as Light3D
			if light.light_cull_mask == 0xFFFFFFFF or light is DirectionalLight3D:
				continue
			named += 1
			(
				assert_int(light.light_cull_mask & 1)
				. override_failure_message(
					"%s names layers without the default one" % map.get_path_to(light)
				)
				. is_equal(1)
			)
		assert_int(named).override_failure_message("%s: no lamp names layers" % path).is_greater(5)


func test_a_floor_on_a_room_layer_takes_no_light_through_a_wall_and_the_check_says_so() -> void:
	# The synthetic scene: the omni a metre in front of the wall lights the floor behind it; with
	# the floor on layer 2 and the omni on the default layer alone it does not, and the light it
	# could not have seen is not counted as lost; a floor it can see on that layer is.
	var root := Node3D.new()
	add_child(root)
	auto_free(root)
	_wall_box(root)
	var floor_box := CSGBox3D.new()
	floor_box.name = "Floor0"
	floor_box.size = Vector3(8.0, 0.4, 8.0)
	floor_box.position = Vector3(0.0, -0.2, 0.0)
	floor_box.use_collision = true
	root.add_child(floor_box)
	var omni := OmniLight3D.new()
	omni.omni_range = 6.0
	omni.light_energy = 3.0
	omni.position = Vector3(0.0, 2.0, -1.0)
	root.add_child(omni)
	assert_array(GlowBleed.bleeding_lights(root, [omni] as Array[Light3D])).is_not_empty()
	floor_box.layers = 2
	omni.light_cull_mask = 1
	assert_array(GlowBleed.bleeding_lights(root, [omni] as Array[Light3D])).is_empty()
	var lost := GlowBleed.lost_lights(root, [omni] as Array[Light3D])
	assert_array(lost).is_not_empty()
	assert_str(lost[0]["surface"]).is_equal("Floor0")
	omni.light_cull_mask = 3
	assert_array(GlowBleed.lost_lights(root, [omni] as Array[Light3D])).is_empty()
