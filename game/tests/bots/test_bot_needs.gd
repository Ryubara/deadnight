# gdlint:disable=max-public-methods
# The table of needs against orders (#692): every cell of `BotNeeds.RULES` for rounds, the level of
# a bot's need read from its guns, what counts as near the people, and the walk that picks the
# nearest locker. The scenarios in the lot are in `test_bot_own_ammo.gd`.
extends GdUnitTestSuite

const PISTOL := &"pistol"
const SHOTGUN := &"shotgun"
const CROWBAR := &"crowbar"
const AMMO := BotNeeds.Need.AMMO
const NONE := BotNeeds.Level.NONE
const LOW := BotNeeds.Level.LOW
const SHORT := BotNeeds.Level.SHORT
const EMPTY := BotNeeds.Level.EMPTY
const GO := BotNeeds.Verdict.GO
const STAY := BotNeeds.Verdict.STAY
const SAY := BotNeeds.Verdict.STAY_AND_SAY

## The leader, a bot beside them, and a place far from both.
const LEADER := Vector3(0.0, 0.0, 0.0)
const BOT := Vector3(4.0, 0.0, 0.0)
const FAR := Vector3(40.0, 0.0, 30.0)


func _verdict(order: StringName, level: BotNeeds.Level, near: bool) -> BotNeeds.Verdict:
	return BotNeeds.verdict(AMMO, order, level, near)


# --- The table, one test for each row ---


func test_roam_goes_freely_at_every_level_it_has_a_need() -> void:
	for near in [true, false]:
		assert_int(_verdict(BotOrders.ROAM, NONE, near)).is_equal(STAY)
		assert_int(_verdict(BotOrders.ROAM, LOW, near)).is_equal(GO)
		assert_int(_verdict(BotOrders.ROAM, SHORT, near)).is_equal(GO)
		assert_int(_verdict(BotOrders.ROAM, EMPTY, near)).is_equal(GO)


func test_follow_goes_when_the_source_is_near_the_leader() -> void:
	assert_int(_verdict(BotOrders.FOLLOW, NONE, true)).is_equal(STAY)
	assert_int(_verdict(BotOrders.FOLLOW, LOW, true)).is_equal(GO)
	assert_int(_verdict(BotOrders.FOLLOW, SHORT, true)).is_equal(GO)
	assert_int(_verdict(BotOrders.FOLLOW, EMPTY, true)).is_equal(GO)


func test_follow_stays_and_says_so_when_the_source_is_far_and_the_gun_is_not_empty() -> void:
	assert_int(_verdict(BotOrders.FOLLOW, NONE, false)).is_equal(STAY)
	assert_int(_verdict(BotOrders.FOLLOW, LOW, false)).is_equal(SAY)
	assert_int(_verdict(BotOrders.FOLLOW, SHORT, false)).is_equal(SAY)


func test_follow_goes_anyway_with_an_empty_gun() -> void:
	assert_int(_verdict(BotOrders.FOLLOW, EMPTY, false)).is_equal(GO)


func test_hold_keeps_its_spot_while_the_reserve_is_a_magazine_or_more() -> void:
	for near in [true, false]:
		assert_int(_verdict(BotOrders.HOLD, NONE, near)).is_equal(STAY)
		assert_int(_verdict(BotOrders.HOLD, LOW, near)).is_equal(STAY)


func test_hold_goes_when_the_reserve_is_under_a_magazine_or_the_gun_is_empty() -> void:
	for near in [true, false]:
		assert_int(_verdict(BotOrders.HOLD, SHORT, near)).is_equal(GO)
		assert_int(_verdict(BotOrders.HOLD, EMPTY, near)).is_equal(GO)


func test_an_order_or_a_need_the_table_does_not_know_is_no_reason_to_go() -> void:
	assert_int(_verdict(&"fan_out", EMPTY, true)).is_equal(STAY)
	assert_dict(BotNeeds.row_of(AMMO, &"fan_out")).is_empty()


func test_every_order_has_a_row_for_every_need() -> void:
	for need in BotNeeds.RULES:
		for order in BotOrders.ORDERS:
			var row := BotNeeds.row_of(need, order)
			assert_bool(row.has_all(["go", "near", "say"])).is_true()
			# A bot never goes only when it is far and not when it is near.
			assert_int(int(row["near"])).is_less_equal(int(row["go"]))


# --- What is near the people ---


func test_a_source_within_the_leash_of_the_leader_is_near() -> void:
	assert_bool(BotNeeds.is_near(Vector3(0.0, 0.0, 11.0), BOT, LEADER)).is_true()
	assert_bool(BotNeeds.is_near(Vector3(0.0, 0.0, 13.0), BOT, LEADER)).is_false()


func test_a_source_on_the_way_to_the_leader_is_near_however_far_the_leader_is() -> void:
	var leader := Vector3(60.0, 0.0, 0.0)
	var here := Vector3(0.0, 0.0, 0.0)
	assert_bool(BotNeeds.is_near(Vector3(30.0, 0.0, 2.0), here, leader)).is_true()
	assert_bool(BotNeeds.is_near(Vector3(30.0, 0.0, 9.0), here, leader)).is_false()
	# Behind the bot is not on the way.
	assert_bool(BotNeeds.is_near(Vector3(-20.0, 0.0, 0.0), here, leader)).is_false()


func test_a_trip_begun_is_given_more_leash() -> void:
	var at := Vector3(0.0, 0.0, 14.0)
	assert_bool(BotNeeds.is_near(at, BOT, LEADER)).is_false()
	assert_bool(BotNeeds.is_near(at, BOT, LEADER, BotNeeds.UNDERWAY_SLACK)).is_true()


func test_with_nobody_to_stay_with_every_source_is_near() -> void:
	assert_bool(BotNeeds.is_near(FAR, BOT, Vector3.INF)).is_true()


# --- The level of the need, from the guns ---


func test_no_gun_short_is_no_need() -> void:
	var arms := {PISTOL: [10, 80, 0], CROWBAR: [0, 0, 0]}
	assert_int(BotNeeds.ammo_level(arms, 3)).is_equal(NONE)


func test_a_reserve_under_the_floor_of_magazines_is_low() -> void:
	var arms := {PISTOL: [10, 25, 0], CROWBAR: [0, 0, 0]}
	assert_int(BotNeeds.ammo_level(arms, 3)).is_equal(LOW)
	# The rookie keeps a floor of two: the same reserve is enough.
	assert_int(BotNeeds.ammo_level(arms, 2)).is_equal(NONE)


func test_a_reserve_under_one_magazine_is_short() -> void:
	var arms := {PISTOL: [4, 6, 0], CROWBAR: [0, 0, 0]}
	assert_int(BotNeeds.ammo_level(arms, 3)).is_equal(SHORT)


func test_only_a_gun_with_no_round_anywhere_is_empty() -> void:
	assert_int(BotNeeds.ammo_level({PISTOL: [0, 0, 0], CROWBAR: [0, 0, 0]}, 3)).is_equal(EMPTY)
	# One round in the magazine is a round: short, not empty.
	assert_int(BotNeeds.ammo_level({PISTOL: [1, 0, 0]}, 3)).is_equal(SHORT)


func test_a_bot_with_a_second_gun_that_still_has_rounds_is_not_empty() -> void:
	# One spare round for the shotgun: under a magazine whatever size the catalogue gives it.
	var arms := {PISTOL: [0, 0, 0], SHOTGUN: [1, 1, 0]}
	assert_int(BotNeeds.ammo_level(arms, 3)).is_equal(SHORT)


func test_a_blade_alone_has_no_need_for_rounds() -> void:
	assert_int(BotNeeds.ammo_level({CROWBAR: [0, 0, 0]}, 3)).is_equal(NONE)


# --- The need for a gun ---


func test_only_the_starting_pistol_and_a_blade_is_a_need_for_a_gun() -> void:
	assert_int(BotNeeds.gun_level({PISTOL: [10, 80, 0]})).is_equal(SHORT)
	assert_int(BotNeeds.gun_level({PISTOL: [0, 0, 0], CROWBAR: [0, 0, 0]})).is_equal(SHORT)
	assert_int(BotNeeds.gun_level({PISTOL: [10, 80, 0], SHOTGUN: [2, 8, 0]})).is_equal(NONE)
	assert_int(BotNeeds.gun_level({SHOTGUN: [2, 8, 0], CROWBAR: [0, 0, 0]})).is_equal(NONE)


func test_a_bot_that_holds_a_spot_goes_for_a_gun_near_or_far() -> void:
	for near in [true, false]:
		assert_int(BotNeeds.verdict(BotNeeds.Need.GUN, BotOrders.HOLD, SHORT, near)).is_equal(GO)
		assert_int(BotNeeds.verdict(BotNeeds.Need.GUN, BotOrders.ROAM, SHORT, near)).is_equal(GO)
		assert_int(BotNeeds.verdict(BotNeeds.Need.GUN, BotOrders.HOLD, NONE, near)).is_equal(STAY)


func test_a_bot_that_follows_goes_for_a_gun_only_when_the_shop_is_near_the_leader() -> void:
	assert_int(BotNeeds.verdict(BotNeeds.Need.GUN, BotOrders.FOLLOW, SHORT, true)).is_equal(GO)
	assert_int(BotNeeds.verdict(BotNeeds.Need.GUN, BotOrders.FOLLOW, SHORT, false)).is_equal(STAY)


# --- The nearest source, by the walk ---


func _spot(at: Vector3) -> Dictionary:
	return {"kind": &"ammo", "shop_id": &"", "position": at}


func test_the_source_nearest_by_the_walk_beats_the_nearer_by_the_straight_line() -> void:
	var view := BotEconomy.View.new()
	view.here = Vector3.ZERO
	var across := Vector3(0.0, 0.0, 10.0)
	var round_the_fence := Vector3(20.0, 0.0, 0.0)
	# Ten metres off, behind a fence that is forty metres to walk round; the other is twenty.
	view.walk = func(at: Vector3) -> float: return 40.0 if at == across else 20.0
	var found := BotEconomy.nearest_by_walk(view, [_spot(across), _spot(round_the_fence)])
	assert_vector(found).is_equal(round_the_fence)


func test_a_source_the_walk_does_not_reach_is_not_chosen() -> void:
	var view := BotEconomy.View.new()
	var shut := Vector3(0.0, 0.0, 5.0)
	var open := Vector3(30.0, 0.0, 0.0)
	view.walk = func(at: Vector3) -> float: return INF if at == shut else 30.0
	assert_vector(BotEconomy.nearest_by_walk(view, [_spot(shut), _spot(open)])).is_equal(open)
	view.walk = func(_at: Vector3) -> float: return INF
	assert_vector(BotEconomy.nearest_by_walk(view, [_spot(shut), _spot(open)])).is_equal(
		Vector3.INF
	)


func test_without_legs_to_ask_the_straight_line_decides() -> void:
	var view := BotEconomy.View.new()
	var near := Vector3(0.0, 0.0, 5.0)
	var far := Vector3(30.0, 0.0, 0.0)
	assert_vector(BotEconomy.nearest_by_walk(view, [_spot(far), _spot(near)])).is_equal(near)


func test_the_source_the_bot_is_heading_to_keeps_it_against_one_a_little_nearer() -> void:
	var view := BotEconomy.View.new()
	var going := Vector3(0.0, 0.0, 20.0)
	var other := Vector3(20.0, 0.0, 0.0)
	view.walk = func(at: Vector3) -> float: return 22.0 if at == going else 18.0
	assert_vector(BotEconomy.nearest_by_walk(view, [_spot(going), _spot(other)])).is_equal(other)
	view.heading = going
	assert_vector(BotEconomy.nearest_by_walk(view, [_spot(going), _spot(other)])).is_equal(going)
