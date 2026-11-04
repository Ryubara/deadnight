extends GdUnitTestSuite
## The prize crane: a play costs points, spins, then holds the weapon out to its buyer alone; it can
## break down after a few plays, refund the price and move. All on fixed steps and seeded rolls.

const SHOTGUN := &"weapon_shotgun"

var _rules: GameRules


## A night with `count` rich players and a tuning with short stages (1 s spin, 2 s grab, 1 s to
## leave). The crane breaks down on every play (`breaks`) or never.
func _begin(count: int = 2, seed_value: int = 7, breaks: bool = false) -> void:
	var t := RulesFixture.tuning()
	t.crane.spin_seconds = 1.0
	t.crane.grab_seconds = 2.0
	t.crane.breakdown_seconds = 1.0
	t.crane.leave_chances = PackedFloat32Array([1.0 if breaks else 0.0])
	t.crane.safe_plays = 0
	_rules = RulesFixture.make_rules(count, seed_value, t)
	_open_lot(_rules)
	_rules.apply(RulesAction.start())
	for player_id in range(1, count + 1):
		_rules.apply(RulesAction.grant_points(player_id, 10000))


## Every door of the lot open, so every spot is a place the crane can go.
func _open_lot(rules: GameRules) -> void:
	rules.doors_open.assign([&"door_concession", &"door_yard"])


func _price() -> int:
	return _rules.tuning.economy.item(&"crane_play").price


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> StringName: return event["type"])


func test_a_play_takes_the_price_and_starts_the_spin_without_giving_a_weapon() -> void:
	_begin()
	var caused := _rules.apply(RulesAction.buy(1, &"crane_play"))
	assert_int(_rules.points_of(1)).is_equal(10200 - _price())
	assert_array(_types(caused)).is_equal(
		[&"points_changed", &"purchase_made", &"crane_spin_started"]
	)
	assert_int(caused[2]["player_id"]).is_equal(1)
	assert_float(caused[2]["seconds"]).is_equal(1.0)
	assert_int(caused[2]["plays"]).is_equal(1)
	assert_dict(caused[1]["detail"]).is_equal({"crane_spot": 0})
	assert_array((_rules.players[1] as PlayerState).weapons).contains_exactly(
		RulesFixture.start_weapons()
	)


func test_the_crane_serves_one_play_at_a_time() -> void:
	_begin()
	_rules.apply(RulesAction.buy(1, &"crane_play"))
	var before := _rules.points_of(2)
	assert_int(RulesFixture.buy(_rules, 2, &"crane_play")).is_equal(GameRules.BuyResult.CRANE_BUSY)
	assert_int(_rules.points_of(2)).is_equal(before)


func test_the_spin_ends_exactly_when_its_time_is_up() -> void:
	_begin()
	_rules.apply(RulesAction.buy(1, &"crane_play"))
	# Quarter-second steps are exact in floating point: three are not enough, four are.
	var early := RulesFixture.advance(_rules, 0.75, 0.25)
	assert_dict(RulesFixture.first(early, &"crane_prize_ready")).is_empty()
	var last := RulesFixture.advance(_rules, 0.25, 0.25)
	var ready := RulesFixture.first(last, &"crane_prize_ready")
	assert_int(ready["player_id"]).is_equal(1)
	assert_float(ready["seconds"]).is_equal(2.0)
	assert_array(_rules.tuning.economy.item(&"crane_play").pool).contains([ready["weapon"]])
	assert_int(_rules.crane.stage).is_equal(CraneState.Stage.GRAB)


func test_the_grab_window_closes_and_the_prize_is_lost_without_a_refund() -> void:
	_begin()
	RulesFixture.play_crane(_rules, 1)
	var points := _rules.points_of(1)
	# play_crane stopped 0.1 s into the grab window.
	var early := RulesFixture.advance(_rules, 1.75, 0.25)
	assert_dict(RulesFixture.first(early, &"crane_prize_lost")).is_empty()
	var last := RulesFixture.advance(_rules, 0.25, 0.25)
	var lost := RulesFixture.first(last, &"crane_prize_lost")
	assert_str(lost["reason"]).is_equal("expired")
	assert_int(_rules.points_of(1)).is_equal(points)
	assert_array((_rules.players[1] as PlayerState).weapons).contains_exactly(
		RulesFixture.start_weapons()
	)
	assert_bool(_rules.crane.is_ready()).is_true()
	assert_int(RulesFixture.buy(_rules, 2, &"crane_play")).is_equal(GameRules.BuyResult.OK)


func test_only_the_buyer_takes_the_weapon() -> void:
	_begin()
	var ready := RulesFixture.first(RulesFixture.play_crane(_rules, 1), &"crane_prize_ready")
	var stranger := _rules.apply(RulesAction.crane_take(2))
	assert_str(stranger[0]["type"]).is_equal("crane_take_denied")
	assert_str(stranger[0]["reason"]).is_equal("not_buyer")
	assert_array((_rules.players[2] as PlayerState).weapons).contains_exactly(
		RulesFixture.start_weapons()
	)
	assert_int(_rules.crane.stage).is_equal(CraneState.Stage.GRAB)
	var taken := RulesFixture.first(_rules.apply(RulesAction.crane_take(1)), &"crane_prize_taken")
	assert_str(taken["weapon"]).is_equal(ready["weapon"])
	assert_array((_rules.players[1] as PlayerState).weapons).contains([ready["weapon"]])
	assert_bool(_rules.crane.is_ready()).is_true()
	var again := _rules.apply(RulesAction.crane_take(1))
	assert_str(again[0]["reason"]).is_equal("nothing_to_take")


func test_a_downed_buyer_cannot_take_the_weapon_until_up() -> void:
	_begin()
	RulesFixture.play_crane(_rules, 1)
	_rules.apply(RulesAction.set_downed(1, true))
	assert_str(_rules.apply(RulesAction.crane_take(1))[0]["reason"]).is_equal("downed")
	_rules.apply(RulesAction.set_downed(1, false))
	var taken := RulesFixture.first(_rules.apply(RulesAction.crane_take(1)), &"crane_prize_taken")
	assert_dict(taken).is_not_empty()


func test_a_buyer_who_leaves_frees_the_crane() -> void:
	_begin()
	RulesFixture.play_crane(_rules, 1)
	var caused := _rules.apply(RulesAction.remove_player(1))
	assert_str(RulesFixture.first(caused, &"crane_prize_lost")["reason"]).is_equal("left")
	assert_bool(_rules.crane.is_ready()).is_true()
	assert_int(RulesFixture.buy(_rules, 2, &"crane_play")).is_equal(GameRules.BuyResult.OK)


func test_a_breakdown_refunds_the_price_and_the_crane_moves_to_another_spot() -> void:
	_begin(2, 7, true)
	var before := _rules.points_of(1)
	var earned := (_rules.players[1] as PlayerState).points_earned
	var caused := RulesFixture.play_crane(_rules, 1)
	var down := RulesFixture.first(caused, &"crane_breakdown")
	assert_int(down["refund"]).is_equal(_price())
	assert_int(down["spot"]).is_equal(0)
	assert_dict(RulesFixture.first(caused, &"crane_prize_ready")).is_empty()
	assert_int(_rules.points_of(1)).is_equal(before)
	var buyer := _rules.players[1] as PlayerState
	assert_int(buyer.points_spent).is_equal(0)
	assert_array(buyer.weapons).contains_exactly(RulesFixture.start_weapons())
	# The refund is a points_changed marked as one, and is not counted as earned.
	var refunds := caused.filter(
		func(event: Dictionary) -> bool: return event.get("reason", &"") == &"refund"
	)
	assert_int(refunds.size()).is_equal(1)
	assert_int(buyer.points_earned).is_equal(earned)
	# While it is going away nothing can be played or taken.
	assert_int(RulesFixture.buy(_rules, 2, &"crane_play")).is_equal(GameRules.BuyResult.CRANE_BUSY)
	assert_str(_rules.apply(RulesAction.crane_take(1))[0]["reason"]).is_equal("nothing_to_take")
	var moved := RulesFixture.first(RulesFixture.advance(_rules, 1.0, 0.25), &"crane_moved")
	assert_int(moved["from_spot"]).is_equal(0)
	assert_int(moved["to_spot"]).is_not_equal(0)
	assert_int(moved["to_spot"]).is_between(0, _rules.tuning.crane.spot_count() - 1)
	assert_int(_rules.crane.spot).is_equal(moved["to_spot"])
	assert_int(_rules.crane.plays).is_equal(0)
	assert_bool(_rules.crane.is_ready()).is_true()


func test_the_first_plays_at_a_spot_are_safe() -> void:
	_begin(1, 7, true)
	_rules.tuning.crane.safe_plays = 3
	for _play in 3:
		var caused := RulesFixture.play_crane(_rules, 1)
		assert_dict(RulesFixture.first(caused, &"crane_breakdown")).is_empty()
		_rules.apply(RulesAction.crane_take(1))
		(_rules.players[1] as PlayerState).weapons.clear()
	var fourth := RulesFixture.play_crane(_rules, 1)
	assert_dict(RulesFixture.first(fourth, &"crane_breakdown")).is_not_empty()


func test_a_prize_is_never_a_weapon_the_buyer_has() -> void:
	var t := RulesFixture.steady_crane_tuning()
	for seed_value in 60:
		_rules = RulesFixture.make_rules(1, seed_value, t)
		_open_lot(_rules)
		_rules.apply(RulesAction.start())
		_rules.apply(RulesAction.grant_points(1, 10000))
		var owned: Array[StringName] = [SHOTGUN]
		(_rules.players[1] as PlayerState).weapons.assign(owned)
		var ready := RulesFixture.first(RulesFixture.play_crane(_rules, 1), &"crane_prize_ready")
		assert_str(ready["weapon"]).is_not_equal(SHOTGUN)


func test_the_crane_runs_dry_when_the_buyer_carries_every_prize() -> void:
	# A player carries two weapons (#410), so a crane runs dry only for a pool of what they carry.
	var t := RulesFixture.steady_crane_tuning()
	var item := t.economy.item(&"crane_play")
	item.pool = t.economy.start_weapons.duplicate()
	item.pool_weights = PackedFloat32Array([1.0, 1.0])
	_rules = RulesFixture.make_rules(1, 5, t)
	_rules.apply(RulesAction.start())
	_rules.apply(RulesAction.grant_points(1, 10000))
	assert_int(RulesFixture.buy(_rules, 1, &"crane_play")).is_equal(
		GameRules.BuyResult.ALREADY_OWNED
	)


func test_the_crane_never_runs_dry_for_a_player_with_two_hands() -> void:
	_begin(1)
	var item := _rules.tuning.economy.item(&"crane_play")
	var carried: Array[StringName] = (_rules.players[1] as PlayerState).weapons
	# The start pistol is no prize (`test_crane_pool.gd`): only what is in the pool is taken out of it.
	var carried_prizes := carried.filter(func(id: StringName) -> bool: return id in item.pool)
	assert_int(item.pool_without(carried).size()).is_equal(item.pool.size() - carried_prizes.size())
	# Enough points for every play, whatever the pool's size (a play is `crane_play`'s price).
	_rules.apply(RulesAction.grant_points(1, item.price * item.pool.size() * 2))
	for _i in item.pool.size() * 2:
		var ready := RulesFixture.first(RulesFixture.play_crane(_rules, 1), &"crane_prize_ready")
		assert_dict(ready).is_not_empty()
		_rules.apply(RulesAction.crane_take(1))
		assert_int((_rules.players[1] as PlayerState).weapons.size()).is_equal(
			WeaponCatalog.CARRY_LIMIT
		)


func test_the_pool_follows_its_weights_over_many_seeded_plays() -> void:
	var t := RulesFixture.steady_crane_tuning()
	var item := t.economy.item(&"crane_play")
	var total := 0.0
	for weight in item.pool_weights:
		total += weight
	var plays := 2000
	var counts: Dictionary = {}
	for seed_value in plays:
		var rules := RulesFixture.make_rules(1, seed_value, t)
		rules.apply(RulesAction.start())
		rules.apply(RulesAction.grant_points(1, 5000))
		# Empty hands, so the whole pool is on offer (a player carries the revolver and the crowbar).
		(rules.players[1] as PlayerState).weapons.clear()
		var ready := RulesFixture.first(RulesFixture.play_crane(rules, 1), &"crane_prize_ready")
		counts[ready["weapon"]] = counts.get(ready["weapon"], 0) + 1
	for i in item.pool.size():
		var share: float = counts.get(item.pool[i], 0) / float(plays)
		assert_float(share).is_equal_approx(item.pool_weights[i] / total, 0.04)


func test_the_chance_to_break_down_follows_the_table_over_many_seeded_plays() -> void:
	var t := RulesFixture.tuning()
	t.crane.spin_seconds = 0.5
	t.crane.grab_seconds = 0.5
	var nights := 1500
	var broke := PackedInt32Array([0, 0, 0, 0, 0])
	for seed_value in nights:
		var rules := RulesFixture.make_rules(1, seed_value, t)
		_open_lot(rules)
		rules.apply(RulesAction.start())
		rules.apply(RulesAction.grant_points(1, 20000))
		for play in 5:
			var caused := RulesFixture.play_crane(rules, 1)
			if RulesFixture.first(caused, &"crane_breakdown").is_empty():
				rules.apply(RulesAction.crane_take(1))
				(rules.players[1] as PlayerState).weapons.clear()
			else:
				broke[play] += 1
				break
	# Plays 1 to 3 are safe; the fourth and fifth break at 15% of the nights that reached them.
	assert_int(broke[0] + broke[1] + broke[2]).is_equal(0)
	assert_float(broke[3] / float(nights)).is_equal_approx(0.15, 0.03)
	assert_float(broke[4] / float(nights - broke[3])).is_equal_approx(0.15, 0.03)


func test_the_crane_moves_by_the_seed_and_visits_every_other_spot() -> void:
	var seen: Dictionary = {}
	for seed_value in 40:
		_begin(1, seed_value, true)
		RulesFixture.play_crane(_rules, 1)
		RulesFixture.advance(_rules, 1.0, 0.25)
		seen[_rules.crane.spot] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([1, 2, 3])
	var spots: Array[int] = []
	for _i in 2:
		_begin(1, 5, true)
		RulesFixture.play_crane(_rules, 1)
		RulesFixture.advance(_rules, 1.0, 0.25)
		spots.append(_rules.crane.spot)
	assert_int(spots[0]).is_equal(spots[1])


func test_a_snapshot_taken_mid_play_continues_the_same() -> void:
	_begin(2, 11, false)
	_rules.apply(RulesAction.buy(1, &"crane_play"))
	RulesFixture.advance(_rules, 1.0, 0.25)
	var copy := RulesFixture.make_rules(2, 99, _rules.tuning)
	assert_str(copy.from_dict(_rules.to_dict())).is_equal("")
	assert_int(copy.crane.stage).is_equal(CraneState.Stage.GRAB)
	assert_str(copy.crane.weapon).is_equal(_rules.crane.weapon)
	assert_array(RulesFixture.advance(copy, 3.0, 0.25)).is_equal(
		RulesFixture.advance(_rules, 3.0, 0.25)
	)
	assert_dict(copy.to_dict()).is_equal(_rules.to_dict())


func test_a_snapshot_with_a_crane_out_of_range_is_refused() -> void:
	_begin(1)
	var data := _rules.to_dict()
	data["crane"]["spot"] = 9
	assert_str(_rules.from_dict(data)).is_equal("malformed")


func test_the_crane_only_goes_where_a_door_is_open_and_cannot_leave_with_nowhere_to_go() -> void:
	# Only the concession is open: from the stand (0) the open spots are the midway (1) and the
	# field (2), never the yard (3).
	var seen: Dictionary = {}
	for seed_value in 30:
		_begin(1, seed_value, true)
		_rules.doors_open.assign([&"door_concession"])
		RulesFixture.play_crane(_rules, 1)
		RulesFixture.advance(_rules, 1.0, 0.25)
		seen[_rules.crane.spot] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([1, 2])
	# Two spots, each behind a door that is shut: the play cannot break down however sure the table
	# says it is.
	_begin(1, 3, true)
	_rules.tuning.crane.spot_doors.assign([&"door_concession", &"door_yard"])
	_rules.doors_open.assign([&"door_concession"])
	var caused := RulesFixture.play_crane(_rules, 1)
	assert_dict(RulesFixture.first(caused, &"crane_breakdown")).is_empty()
	assert_dict(RulesFixture.first(caused, &"crane_prize_ready")).is_not_empty()
