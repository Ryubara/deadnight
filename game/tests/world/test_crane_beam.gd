# The prize crane's beam rises to the first solid over the crane and no further (issue #911).
# It was a 36 m cone that nothing cut: the depth test hides a surface's far side from the camera,
# never the beam's part past it on the camera's side, so from a floor or a roof over the crane the
# column came out of the slab. Its length is one ray up from the crane when it is placed
# (`PrizeCrane.beam_length_over`), and the beam ends in a fade; no draw call or light is added.
extends GdUnitTestSuite

const GREYBOXES: Array[String] = [
	"res://world/drive_in_greybox.tscn",
	"res://world/smallmap/smallmap_greybox.tscn",
]
const SMALLMAP := "res://world/smallmap/smallmap_greybox.tscn"
## Every layer a body or a shot meets, so the check also sees what the beam's own ray ignores.
const EVERYTHING := 0xFFFFF
## The tolerance of a length against the underside it meets (m).
const EDGE := 0.02
const SETTLE := 20


## The crane's places on a map, as the night reads them (`NightWorld.shop_spots`): the crane's
## stand for each marker of kind `crane`, as `{spot, stand}`.
func _places(root: Node) -> Array[Dictionary]:
	var places: Array[Dictionary] = []
	for marker in root.get_node("ShopSpots").get_children():
		if StringName(marker.get_meta("kind")) != &"crane":
			continue
		var node := marker as Node3D
		var forward := node.global_basis.z
		var stand := CraneView.stand_at(node.global_position, atan2(forward.x, forward.z))
		places.append({"spot": int(marker.get_meta("crane_spot", 0)), "stand": stand.origin})
	return places


func _map(path: String) -> Node3D:
	var root := (load(path) as PackedScene).instantiate() as Node3D
	add_child(root)
	auto_free(root)
	for _i in SETTLE:
		await get_tree().physics_frame
	return root


## The crane's beam: its one cone mesh.
func _beam_node(crane: PrizeCrane) -> MeshInstance3D:
	var found: Array[MeshInstance3D] = []
	for node in crane.find_children("*", "MeshInstance3D", false, false):
		if (node as MeshInstance3D).mesh is CylinderMesh:
			found.append(node as MeshInstance3D)
	assert_int(found.size()).is_equal(1)
	return found[0]


func _above(root: Node3D, from: Vector3, to_y: float, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, to_y, from.z), mask)
	return root.get_world_3d().direct_space_state.intersect_ray(query)


func test_every_crane_spot_of_both_maps_has_a_beam_that_ends_at_the_first_solid_over_it() -> void:
	var ended := 0
	var open := 0
	for path in GREYBOXES:
		var root := await _map(path)
		var places := _places(root)
		assert_int(places.size()).is_greater(0)
		for place: Dictionary in places:
			var stand: Vector3 = place["stand"]
			var space := root.get_world_3d().direct_space_state
			var length := PrizeCrane.beam_length_over(space, stand)
			var foot := stand + Vector3.UP * PrizeCrane.MARQUEE_TOP
			var label := "%s spot %d" % [path.get_file(), place["spot"]]
			# The beam never runs into a solid of any kind (a ray with every layer, as a shot).
			var through := _above(root, foot, foot.y + length - EDGE, EVERYTHING)
			(
				assert_bool(through.is_empty())
				. override_failure_message(
					"%s: the beam of %.2f m reaches %s" % [label, length, through.get("collider")]
				)
				. is_true()
			)
			# And it stops at the first one: nothing but sky over a full-length beam, and a solid
			# at the end of a shorter one.
			var top := foot.y + PrizeCrane.BEAM_HEIGHT + 1.0
			var above := _above(root, foot, top, PhysicsLayers.WORLD)
			if length >= PrizeCrane.BEAM_HEIGHT:
				open += 1
				(
					assert_bool(above.is_empty())
					. override_failure_message(
						"%s: a full beam under %s" % [label, above.get("collider")]
					)
					. is_true()
				)
			else:
				ended += 1
				assert_bool(above.is_empty()).is_false()
				var met: float = (above["position"] as Vector3).y - foot.y
				assert_float(met).is_equal_approx(length, EDGE)
	# Both kinds of place are in the map set: a spot under a roof and a spot in the open.
	assert_int(ended).is_greater(0)
	assert_int(open).is_greater(0)


func test_a_roof_over_the_crane_cuts_the_beam_to_the_roofs_underside() -> void:
	var root := await _map(SMALLMAP)
	var stand: Vector3 = _places(root)[0]["stand"]
	var space := root.get_world_3d().direct_space_state
	var length := PrizeCrane.beam_length_over(space, stand)
	# The side room's ceiling slab (3.2 m under its 3.4 m top) is 0.39 m over the marquee.
	assert_float(length).is_between(0.2, 0.6)
	assert_float(length).is_less(PrizeCrane.BEAM_HEIGHT)


func test_a_beam_with_nothing_over_it_runs_to_its_full_height() -> void:
	var space := get_viewport().world_3d.direct_space_state
	var length := PrizeCrane.beam_length_over(space, Vector3(300.0, 0.0, 300.0))
	assert_float(length).is_equal(PrizeCrane.BEAM_HEIGHT)


func test_a_cut_beam_is_the_same_cone_shorter_on_the_same_shader_with_a_soft_end() -> void:
	var crane: PrizeCrane = auto_free(PrizeCrane.new())
	add_child(crane)
	crane.configure(load(GameRules.DEFAULT_TUNING_PATH).crane, [])
	var beam := _beam_node(crane)
	var material := beam.material_override as ShaderMaterial
	var program := material.shader
	assert_float(crane.beam_length()).is_equal(PrizeCrane.BEAM_HEIGHT)
	crane.set_beam_length(4.0)
	var cone := beam.mesh as CylinderMesh
	assert_float(cone.height).is_equal(4.0)
	# Its foot stays on the marquee and its taper is the open beam's.
	var foot := beam.position.y - cone.height / 2.0
	assert_float(foot).is_equal_approx(PrizeCrane.MARQUEE_TOP, 0.001)
	assert_float(cone.bottom_radius).is_equal_approx(PrizeCrane.BEAM_FOOT_RADIUS, 0.001)
	var taper := PrizeCrane.BEAM_FOOT_RADIUS - PrizeCrane.BEAM_TOP_RADIUS
	var slope := taper / PrizeCrane.BEAM_HEIGHT
	assert_float(cone.bottom_radius - cone.top_radius).is_equal_approx(slope * 4.0, 0.001)
	# The same material and program, a cut and a soft end of its own, drawn with one surface.
	assert_object(beam.material_override).is_same(material)
	assert_object(material.shader).is_same(program)
	assert_float(material.get_shader_parameter(&"cut")).is_equal(4.0)
	var soft: float = material.get_shader_parameter(&"soft_end")
	assert_float(soft).is_between(0.5, PrizeCrane.BEAM_SOFT_END)
	assert_str(program.code).contains("smoothstep(cut, cut - soft_end, rise)")
	assert_int(cone.get_surface_count()).is_equal(1)
	# A very short beam's soft end is a share of it, and a roof that touches the marquee leaves the
	# shortest beam, not none and not a negative height.
	crane.set_beam_length(0.4)
	var short: float = material.get_shader_parameter(&"soft_end")
	assert_float(short).is_equal_approx(0.4 * PrizeCrane.BEAM_SOFT_SHARE, 0.001)
	crane.set_beam_length(-1.0)
	assert_float(crane.beam_length()).is_equal(PrizeCrane.BEAM_MIN)
	# The beam added no light to the crane's one lamp.
	assert_int(crane.find_children("*", "Light3D", true, false).size()).is_equal(1)


func test_the_crane_view_fits_the_beam_where_it_stands_and_where_it_moves() -> void:
	var tuning := RulesFixture.tuning()
	tuning.crane.safe_plays = 0
	tuning.crane.leave_chances = PackedFloat32Array([1.0])
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.grant_points(1, 5000))
	night.server.rules.doors_open.assign([&"door_concession", &"door_yard"])
	NightFixture.run(night, 3)
	var prop := night.view.crane.crane
	var space := night.get_world_3d().direct_space_state
	# Spot 0 is in the concession stand, under its roof.
	var first := PrizeCrane.beam_length_over(space, prop.global_position)
	assert_float(first).is_less(PrizeCrane.BEAM_HEIGHT)
	assert_float(prop.beam_length()).is_equal(first)
	# Read off the drawn mesh itself, not the crane's own number: its top stays under the roof.
	var cone := _beam_node(prop)
	var top := cone.global_position.y + (cone.mesh as CylinderMesh).height / 2.0
	var foot := prop.global_position + Vector3.UP * PrizeCrane.MARQUEE_TOP
	var roof := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(foot, foot + Vector3.UP * 60.0, PhysicsLayers.WORLD)
	)
	assert_bool(roof.is_empty()).is_false()
	assert_float(top).is_less_equal((roof["position"] as Vector3).y + EDGE)
	# A breakdown moves it to another spot, and the beam is fitted there.
	night.server.buy(1, &"crane_play")
	NightFixture.run(night, 700)
	var spot: int = night.server.rules.crane.spot
	assert_int(spot).is_not_equal(0)
	NightFixture.run(night, 120)
	var there := PrizeCrane.beam_length_over(space, prop.global_position)
	assert_float(prop.beam_length()).is_equal(there)
	night.queue_free()
