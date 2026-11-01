# The lot's doors follow the rules (docs/design/map.md): a bought door loses its slabs and label,
# so a player walks through and shots pass. The zombies' mesh follows in
# test_door_navigation.gd.
extends GdUnitTestSuite

var _lot: Node3D
var _rules: GameRules
var _doors: LotDoors


func before_test() -> void:
	_lot = await LotFixture.make_lot(self)
	auto_free(_lot.get_parent())
	_rules = _lot.get_meta(&"rules")
	_doors = _lot.get_node("Doors")


func _door(name: String) -> Node:
	return _lot.get_node("Doors/%s" % name)


func _slabs(door: Node) -> Array[Node]:
	return door.get_children().filter(func(n: Node) -> bool: return n is CSGShape3D)


## True when something solid stands between two points at head height.
func _blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return not _lot.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func test_every_door_starts_closed() -> void:
	assert_array(_doors.closed_doors()).has_size(5)
	for door in _doors.get_children():
		assert_int(_slabs(door).size()).override_failure_message(door.name).is_greater(0)


func test_buying_a_door_removes_its_slabs_and_label() -> void:
	var door := _door("Door_Concession")
	assert_bool(_blocked(Vector3(0, 1, -5), Vector3(0, 1, -2))).is_true()
	assert_int(RulesFixture.buy(_rules, 1, &"door_concession")).is_equal(GameRules.BuyResult.OK)
	await get_tree().physics_frame
	assert_array(_slabs(door)).is_empty()
	assert_bool(door.get_children().any(func(n: Node) -> bool: return n is Label3D)).is_false()
	assert_bool(_blocked(Vector3(0, 1, -5), Vector3(0, 1, -2))).is_false()


func test_only_the_bought_door_opens() -> void:
	RulesFixture.buy(_rules, 1, &"door_concession")
	RulesFixture.buy(_rules, 1, &"door_yard")
	await get_tree().physics_frame
	assert_array(_doors.closed_doors()).contains_exactly_in_any_order(
		[&"door_booth", &"door_back_lot", &"door_road"]
	)
	assert_array(_slabs(_door("Door_ProjectionBooth"))).has_size(1)
	assert_array(_slabs(_door("Door_GeneratorYard"))).is_empty()


func test_a_door_with_two_ways_in_loses_both_slabs() -> void:
	RulesFixture.buy(_rules, 1, &"door_concession")
	assert_array(_slabs(_door("Door_BackLot"))).has_size(2)
	RulesFixture.buy(_rules, 1, &"door_booth")
	RulesFixture.buy(_rules, 1, &"door_back_lot")
	assert_array(_slabs(_door("Door_BackLot"))).is_empty()


func test_a_refused_purchase_opens_nothing() -> void:
	# The booth needs the concession first.
	assert_int(RulesFixture.buy(_rules, 1, &"door_booth")).is_equal(GameRules.BuyResult.LOCKED)
	assert_array(_doors.closed_doors()).has_size(5)


func test_the_signal_names_the_door() -> void:
	var opened: Array[StringName] = []
	_doors.door_opened.connect(func(id: StringName) -> void: opened.append(id))
	RulesFixture.buy(_rules, 1, &"door_concession")
	assert_array(opened).is_equal([&"door_concession"])


func test_a_door_opens_once() -> void:
	assert_bool(_doors.open(&"door_concession")).is_true()
	assert_bool(_doors.open(&"door_concession")).is_false()
	assert_bool(_doors.open(&"door_nowhere")).is_false()


func test_binding_to_rules_with_doors_already_open_opens_them() -> void:
	# A restored night: the rules know two doors the scene has not been told about.
	var rules := RulesFixture.make_rules(1)
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.grant_points(1, 5000))
	RulesFixture.buy(rules, 1, &"door_concession")
	RulesFixture.buy(rules, 1, &"door_booth")
	var fresh := load(LotFixture.SCENE).instantiate() as Node3D
	auto_free(fresh)
	(fresh.get_node("Doors") as LotDoors).bind(rules)
	(
		assert_array((fresh.get_node("Doors") as LotDoors).closed_doors())
		. contains_exactly_in_any_order([&"door_yard", &"door_back_lot", &"door_road"])
	)
