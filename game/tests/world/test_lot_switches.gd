# The lot's breaker posts (docs/design/map.md, The breaker posts): one for each circuit a player
# can switch, each showing the circuit the rules report, each clear of the doors' prompts.
extends GdUnitTestSuite

const NO_POST := Vector3(0.0, 0.0, -20.0)

var _lot: Node3D
var _switches: LotSwitches
var _rules: GameRules


func before_test() -> void:
	_lot = await LotFixture.make_lot(self)
	auto_free(_lot.get_parent())
	_rules = _lot.get_meta(&"rules")
	_switches = LotSwitches.new(_lot)


func _doors() -> LotDoors:
	return _lot.get_node("Doors") as LotDoors


func test_there_is_a_post_for_every_circuit_the_generator_has() -> void:
	var listed: Array = _rules.tuning.fuel.circuit_drain.keys()
	var found: Array = _switches.circuit_ids()
	listed.sort()
	found.sort()
	assert_array(found).is_equal(listed)
	assert_object(_switches.post(&"mains")).is_null()


func test_a_post_names_the_door_of_the_area_it_lights() -> void:
	assert_str(_switches.door_of(&"screen_lot")).is_equal("")
	var shop: EconomyTuning = _rules.tuning.economy
	for circuit_id: StringName in [&"concession", &"booth", &"back_lot"]:
		var door := _switches.door_of(circuit_id)
		assert_bool(shop.item(door) != null).is_true()
		assert_array(_doors().closed_doors()).contains([door])


func test_a_post_stands_clear_of_every_door_slab() -> void:
	# A door in reach wins the prompt, so a post must be used from where no slab is within reach.
	for circuit_id in _switches.circuit_ids():
		var stand := _switches.standing_point(circuit_id)
		for door in _doors().get_children():
			for slab in door.get_children():
				if slab is CSGShape3D and (slab as CSGShape3D).use_collision:
					var gap := Vector2(stand.x, stand.z).distance_to(
						Vector2(
							(slab as Node3D).global_position.x, (slab as Node3D).global_position.z
						)
					)
					(
						assert_float(gap)
						. override_failure_message("%s near %s" % [circuit_id, slab.get_path()])
						. is_greater(NightTuning.new().use_reach)
					)


func test_a_post_is_reached_from_where_it_is_stood_at_and_not_from_afar() -> void:
	var reach := NightTuning.new().use_reach
	for circuit_id in _switches.circuit_ids():
		var found := _switches.within_reach(_switches.standing_point(circuit_id), reach)
		assert_object(found).is_same(_switches.post(circuit_id))
	assert_object(_switches.within_reach(NO_POST, reach)).is_null()


func test_a_post_shows_its_circuit_as_the_generator_has_it() -> void:
	_switches.show_all(_rules.generator)
	assert_bool(_switches.post(&"screen_lot").is_on()).is_true()
	assert_bool(_switches.post(&"booth").is_on()).is_false()
	_switches.follow({"type": &"circuit_changed", "circuit_id": &"booth", "on": true})
	assert_bool(_switches.post(&"booth").is_on()).is_true()
	assert_bool(_switches.post(&"concession").is_on()).is_false()
	_switches.follow({"type": &"fuel_empty"})
	_switches.follow({"type": &"circuit_changed", "circuit_id": &"nope", "on": true})
	assert_bool(_switches.post(&"booth").is_on()).is_true()


func _lamp_colour(post: CircuitSwitch) -> Color:
	return (
		((post.get_node("Lamp") as MeshInstance3D).material_override as StandardMaterial3D)
		. albedo_color
	)


func _lever(post: CircuitSwitch) -> float:
	return (post.get_node("Lever") as Node3D).rotation.x


func test_a_post_moves_its_lever_and_lamp_and_does_not_share_them() -> void:
	var booth := _switches.post(&"booth")
	var concession := _switches.post(&"concession")
	booth.set_on(false)
	concession.set_on(false)
	var off_lever := _lever(booth)
	var off_lamp := _lamp_colour(booth)
	booth.set_on(true)
	assert_float(_lever(booth)).is_not_equal(off_lever)
	assert_float(_lever(concession)).is_equal(off_lever)
	assert_bool(_lamp_colour(booth).g > _lamp_colour(booth).r).is_true()
	assert_bool(off_lamp.r > off_lamp.g).is_true()
	assert_bool(_lamp_colour(concession).is_equal_approx(off_lamp)).is_true()


func test_a_post_is_no_lamp_of_the_lot() -> void:
	# The lamps the dead's slowdown asks about are the `powered_light` group: a post adds none.
	var posts := _lot.get_node("Switches")
	for lamp in _lot.get_tree().get_nodes_in_group(&"powered_light"):
		assert_bool(posts.is_ancestor_of(lamp)).is_false()
