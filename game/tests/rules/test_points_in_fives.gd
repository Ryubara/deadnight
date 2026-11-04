extends GdUnitTestSuite
## A score and a price are always a multiple of 5 (Deadnight #916): 5, 15, 20, 25, 50, never 31 or
## 34. Full seeded nights through the real rules fail on any points event, total or price that is
## not, and the odd corners (a part purchase, a refund, a penalty, a type's multiplier) are played
## by hand. The rounding rule is `PointSteps`; this suite does not name it, so it asks the rules,
## not the helper.

const NIGHTS := [["weak", 1, 4100], ["average", 2, 4200], ["average", 4, 4300], ["strong", 1, 4400]]
## The reasons a night must have shown, so the test has seen each source of points it guards.
const SOURCES: Array[StringName] = [
	&"hit", &"headshot_hit", &"kill", &"headshot_kill", &"round_bonus", &"purchase"
]


func test_full_scripted_nights_never_show_a_score_or_a_price_off_the_fives() -> void:
	var seen := {}
	var failures: Array[String] = []
	for spec: Array in NIGHTS:
		var sim := NightSim.new(
			RulesFixture.tuning(), SimSkill.named(StringName(spec[0])), spec[1], spec[2], 0.25
		)
		var log := RulesFixture.record(sim.rules)
		sim.run(16)
		failures.append_array(_off_the_fives(log.events, "%s x%d" % [spec[0], spec[1]], seen))
		for player: PlayerState in sim.rules.players.values():
			if player.points % 5 != 0:
				failures.append("%s: ends on %d" % [spec[0], player.points])
	for reason in SOURCES:
		(
			assert_bool(seen.has(reason))
			. override_failure_message("no %s in the nights" % reason)
			. is_true()
		)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_every_kind_of_dead_pays_in_fives_by_every_blow() -> void:
	var failures: Array[String] = []
	var seen := {}
	var tuning := RulesFixture.tuning()
	for type: ZombieType in tuning.roster.types:
		for blow in [
			[RulesAction.ZONE_BODY, false, 1.0],
			[RulesAction.ZONE_HEAD, false, 1.0],
			[RulesAction.ZONE_WEAK, false, 1.0],
			[RulesAction.ZONE_BODY, false, RulesFixture.KILLING_DAMAGE],
			[RulesAction.ZONE_HEAD, false, RulesFixture.KILLING_DAMAGE],
			[RulesAction.ZONE_BODY, true, RulesFixture.KILLING_DAMAGE],
		]:
			var log := RulesFixture.new()
			var rules := RulesFixture.with_one_living(type.id, RulesFixture.tuning(), log)
			var zombie_id := rules.zombie_ids()[0]
			for _i in 3:
				rules.apply(RulesAction.hit(1, zombie_id, blow[0], blow[2], blow[1]))
			failures.append_array(_off_the_fives(log.events, "%s %s" % [type.id, blow], seen))
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_a_blast_pays_in_fives_for_every_kind_of_dead() -> void:
	var failures: Array[String] = []
	for type: ZombieType in RulesFixture.tuning().roster.types:
		var log := RulesFixture.new()
		var rules := RulesFixture.with_one_living(type.id, RulesFixture.tuning(), log)
		var victim := {
			"zombie_id": rules.zombie_ids()[0], "damage": 1.0, "leg_damage": 0.0, "zone": &"body"
		}
		rules.apply(RulesAction.explosion(1, [victim]))
		victim["damage"] = RulesFixture.KILLING_DAMAGE
		rules.apply(RulesAction.explosion(1, [victim]))
		failures.append_array(_off_the_fives(log.events, "blast on %s" % type.id, {}))
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_a_part_purchase_costs_a_multiple_of_five_in_every_round() -> void:
	var failures: Array[String] = []
	for round_number in [1, 2, 3, 7, 12, 25]:
		for item_id in [&"fuel_can", &"grenades", &"ammo_pistol", &"ammo_smg", &"ammo_shotgun"]:
			var rules := RulesFixture.make_rules(1, 5)
			rules.apply(RulesAction.start())
			rules.round_number = round_number
			rules.apply(RulesAction.grant_points(1, 100000))
			rules.generator.fuel = 61.0
			var log := RulesFixture.record(rules)
			for rounds in [1, 3, 7, 13]:
				rules.apply(RulesAction.buy(1, item_id, rounds))
			failures.append_array(
				_off_the_fives(log.events, "%s at %d" % [item_id, round_number], {})
			)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_a_crane_refund_is_a_multiple_of_five() -> void:
	var tuning := RulesFixture.tuning()
	tuning.crane.spin_seconds = 1.0
	tuning.crane.leave_chances = PackedFloat32Array([1.0])
	tuning.crane.safe_plays = 0
	tuning.crane.refund_fraction = 0.35
	var rules := RulesFixture.make_rules(1, 7, tuning)
	rules.doors_open.assign([&"door_concession", &"door_yard"])
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.grant_points(1, 10000))
	var log := RulesFixture.record(rules)
	var caused := RulesFixture.play_crane(rules, 1)
	var down := RulesFixture.first(caused, &"crane_breakdown")
	assert_bool(down.is_empty()).override_failure_message("the crane did not break").is_false()
	assert_int(int(down["refund"]) % 5).is_equal(0)
	assert_int(int(down["refund"])).is_greater(0)
	assert_array(_off_the_fives(log.events, "crane", {})).is_empty()


func test_the_penalty_for_being_down_is_a_multiple_of_five() -> void:
	var failures: Array[String] = []
	for points in [200, 205, 1255, 3790, 45]:
		var rules := RulesFixture.make_rules(2)
		var log := RulesFixture.record(rules)
		RulesFixture.into_round_one(rules)
		rules.apply(RulesAction.grant_points(1, points))
		rules.apply(RulesAction.set_downed(1, true))
		rules._end_round()
		failures.append_array(_off_the_fives(log.events, "down with %d" % points, {}))
		assert_int(rules.points_of(1) % 5).is_equal(0)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_a_repair_pays_in_fives_up_to_its_cap() -> void:
	var rules := RulesFixture.make_rules(1)
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 2.0)
	var zombie_id := log.spawned_ids()[0]
	for id in rules.tuning.barricades.ids:
		for _i in rules.tuning.barricades.boards:
			rules.apply(RulesAction.tear_board(id, zombie_id))
	for id in rules.tuning.barricades.ids:
		for _i in rules.tuning.barricades.boards:
			rules.apply(RulesAction.repair(1, id))
	assert_int(log.count(&"board_repaired")).is_greater(0)
	assert_int(log.count(&"points_changed")).is_greater(0)
	assert_array(_off_the_fives(log.events, "repairs", {})).is_empty()


func test_a_grant_off_the_fives_is_paid_in_fives() -> void:
	var rules := RulesFixture.make_rules(1)
	var log := RulesFixture.record(rules)
	rules.apply(RulesAction.grant_points(1, 33))
	assert_int(rules.points_of(1) % 5).is_equal(0)
	assert_array(_off_the_fives(log.events, "grant", {})).is_empty()


## Every points event, purchase and refund in `events` that is not a multiple of 5, as text. `seen`
## collects the reasons met.
func _off_the_fives(events: Array[Dictionary], what: String, seen: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for event: Dictionary in events:
		match event["type"]:
			&"points_changed":
				seen[event["reason"]] = true
				if int(event["delta"]) % 5 != 0 or int(event["total"]) % 5 != 0:
					found.append(
						(
							"%s: %s moved %d to %d"
							% [what, event["reason"], event["delta"], event["total"]]
						)
					)
			&"purchase_made":
				if int(event["price"]) % 5 != 0:
					found.append("%s: %s bought for %d" % [what, event["item_id"], event["price"]])
			&"crane_breakdown":
				if int(event["refund"]) % 5 != 0:
					found.append("%s: refund %d" % [what, event["refund"]])
			&"special_round_cleared":
				if int(event["reward"]) % 5 != 0:
					found.append("%s: reward %d" % [what, event["reward"]])
	return found
