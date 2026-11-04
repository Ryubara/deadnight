# A press that carries on a repair buys nothing, and a weapon that would replace the one in hand is
# bought only by a press made once its card has been read (#908). The maintainer, boarding a window:
# "I'll accidentally interact with a weapon on the wall or a perk or something else next to it ...
# losing your weapons". Driven like a client on the lot: commands through the link (`use` the
# press, `use_held` the level), a tick is 1/60 s.
extends GdUnitTestSuite

const BREACH := &"nw"
const TICKS_PER_SECOND := 60


func _start(tuning: RulesTuning) -> Night:
	tuning.rounds.intro_seconds = 60.0
	tuning.rounds.first_spawn_delay = 600.0
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	NightFixture.run(night, 30)
	night.server.rules.apply(RulesAction.grant_points(1, 50000))
	for _i in 3:
		night.server.rules.barricades.tear(BREACH)
	night.world.barricade(BREACH).set_boards(night.server.rules.barricades.boards_of(BREACH))
	NightFixture.run(night, 2)
	return night


func _ticks(seconds: float) -> int:
	return roundi(seconds * TICKS_PER_SECOND)


func _spot(night: Night, shop_id: StringName) -> Vector3:
	for spot in night.world.shop_spots():
		if spot["shop_id"] == shop_id:
			return spot["position"]
	return Vector3.INF


## One tick with the button down (`press`: it went down this tick) or up.
func _tick(night: Night, held: bool, press := false) -> void:
	var command := NightCommand.new()
	command.use = press
	command.use_held = held
	NightFixture.run(night, 1, command)


func _boards(night: Night) -> int:
	return night.server.rules.barricades.boards_of(BREACH)


func test_a_press_right_after_a_repair_does_not_buy_the_wall_weapon() -> void:
	var night := await _start(RulesFixture.tuning())
	night.player().teleport(night.world.repair_spot(BREACH))
	NightFixture.run(night, 2)
	var boards := _boards(night)
	_tick(night, true, true)
	assert_int(_boards(night)).is_equal(boards + 1)
	_tick(night, false)
	# The taps that go on mending land on the wall weapon: still buys nothing.
	night.player().teleport(_spot(night, &"weapon_shotgun") + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 3)
	assert_str(String(night.state.me()["prompt"].get("kind", ""))).is_equal("weapon")
	var points := night.state.points()
	for _i in 3:
		_tick(night, true, true)
		_tick(night, false)
	assert_int(night.state.points()).is_equal(points)
	assert_bool(night.server.combat.state_of(1, &"shotgun") == null).is_true()
	# Once the grace is over, the same press buys.
	NightFixture.run(night, _ticks(night.server.tuning.repair_grace))
	_tick(night, true, true)
	_tick(night, false)
	assert_int(night.state.points()).is_less(points)
	assert_bool(night.server.combat.state_of(1, &"shotgun") != null).is_true()
	night.queue_free()


func test_a_held_repair_never_buys_even_when_a_press_lands_on_a_weapon() -> void:
	var night := await _start(RulesFixture.tuning())
	night.player().teleport(night.world.repair_spot(BREACH))
	NightFixture.run(night, 2)
	_tick(night, true, true)
	_tick(night, true)
	assert_bool(night.server.is_repairing(1)).is_true()
	# Still holding, the body is at the weapon and a press (a merged edge) arrives with it.
	night.player().teleport(_spot(night, &"weapon_shotgun") + Vector3(0.0, 0.1, 0.0))
	var points := night.state.points()
	_tick(night, true, true)
	for _i in _ticks(0.5):
		_tick(night, true)
	assert_int(night.state.points()).is_equal(points)
	assert_bool(night.server.combat.state_of(1, &"shotgun") == null).is_true()
	night.queue_free()


func test_a_weapon_that_replaces_the_one_in_hand_needs_its_card_read_first() -> void:
	var night := await _start(RulesFixture.full_hands())
	night.player().teleport(_spot(night, &"weapon_shotgun") + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 2)
	var prompt: Dictionary = night.state.me()["prompt"]
	assert_str(String(prompt.get("kind", ""))).is_equal("weapon")
	assert_str(String(prompt.get("replaces", ""))).is_not_empty()
	var points := night.state.points()
	# A press the moment the card shows (stepping into the spot with the finger on use) keeps the
	# revolver.
	_tick(night, true, true)
	_tick(night, false)
	assert_int(night.state.points()).is_equal(points)
	assert_array(night.server.combat.carried(1)).contains([&"pistol"])
	# The card has been up `replace_settle`: the press is meant, and it buys.
	NightFixture.run(night, _ticks(night.server.tuning.replace_settle))
	_tick(night, true, true)
	_tick(night, false)
	assert_int(night.state.points()).is_less(points)
	assert_array(night.server.combat.carried(1)).contains([&"shotgun"])
	night.queue_free()


func test_a_weapon_bought_with_a_hand_free_is_one_press_as_before() -> void:
	var night := await _start(RulesFixture.tuning())
	night.player().teleport(_spot(night, &"weapon_shotgun") + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 2)
	assert_str(String(night.state.me()["prompt"].get("replaces", ""))).is_empty()
	var points := night.state.points()
	_tick(night, true, true)
	_tick(night, false)
	assert_int(night.state.points()).is_less(points)
	night.queue_free()


func test_where_two_offers_meet_the_one_looked_at_wins() -> void:
	var door := {"offer": {"kind": &"door", "id": &"a"}, "at": Vector3(0.0, 0.0, -2.0)}
	var gun := {"offer": {"kind": &"weapon", "id": &"b"}, "at": Vector3(2.0, 0.0, 0.0)}
	var both: Array[Dictionary] = [door, gun]
	var here := Vector3.ZERO
	assert_str(String(UseOffers.faced(both, here, Vector3(0.0, 0.0, -1.0))["id"])).is_equal("a")
	assert_str(String(UseOffers.faced(both, here, Vector3(1.0, 0.0, 0.0))["id"])).is_equal("b")
	# No view: the nearer.
	var near_gun := {"offer": gun["offer"], "at": Vector3(1.0, 0.0, 0.0)}
	var pair: Array[Dictionary] = [door, near_gun]
	assert_str(String(UseOffers.faced(pair, here, Vector3.ZERO)["id"])).is_equal("b")
