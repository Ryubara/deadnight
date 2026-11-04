extends GdUnitTestSuite
## Every stat a challenge can count, produced from the events the real rules and the real combat
## server send (nothing here writes an event by hand), for one player and for several.

const HEAD := Vector3(0, 1.62, 0)
const CHEST := Vector3(0, 1.1, 0)

var _tally: NightTally


func before_test() -> void:
	_tally = NightTally.new()


func _feed(events: Array) -> void:
	for event: Dictionary in events:
		_tally.observe(event)


## A night in round one with the combat server over it and the first zombie a target.
func _lot(players: int = 1) -> Dictionary:
	var made := ChallengeFixture.night(players)
	var rules: GameRules = made["rules"]
	var log := RulesFixture.record(rules)
	var server := WeaponsFixture.make_server(rules)
	_feed(made["events"])
	for id in range(1, players + 1):
		_feed(server.apply(CombatAction.give_weapon(id, &"pistol")))
	_feed(rules.apply(RulesAction.start()))
	_feed(rules.apply(RulesAction.skip_break()))
	_feed(RulesFixture.advance(rules, 2.0))
	var zombie: int = log.spawned_ids()[0]
	WeaponsFixture.step(server, {zombie: Vector3.ZERO}, 2)
	return {"rules": rules, "server": server, "zombie": zombie, "log": log}


func _shoot(lot: Dictionary, shooter: int, at: Vector3, seq: int = 1) -> void:
	var server: CombatServer = lot["server"]
	_feed(
		server.apply(WeaponsFixture.fire_at(shooter, seq, WeaponsFixture.SHOOTER, at, server.now))
	)


## One server step, its events heard.
func _step(server: CombatServer, positions: Dictionary) -> void:
	_feed(server.apply(CombatAction.targets(WeaponsFixture.list_of(positions))))
	_feed(server.apply(CombatAction.tick(WeaponsFixture.STEP)))


func test_a_headshot_kill_counts_the_kill_the_head_the_weapon_and_the_type() -> void:
	var lot := _lot()
	# The rifle: no start pistol kills a round-one walker with one head shot (#898).
	_feed((lot["server"] as CombatServer).apply(CombatAction.give_weapon(1, &"rifle")))
	_shoot(lot, 1, HEAD)
	assert_int(_tally.count(1, ChallengeStats.KILLS)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.KILLS_HEAD)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.weapon_kills(&"rifle"))).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.type_kills(&"walker"))).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.KILLS_BLAST)).is_equal(0)
	assert_int(_tally.count(1, ChallengeStats.KILLS_MELEE)).is_equal(0)


func test_a_hit_that_does_not_kill_counts_no_kill() -> void:
	var lot := _lot()
	_shoot(lot, 1, CHEST)
	assert_int(_tally.count(1, ChallengeStats.KILLS)).is_equal(0)
	assert_int(_tally.count(1, ChallengeStats.weapon_kills(&"pistol"))).is_equal(0)


func test_a_body_kill_with_another_weapon_counts_that_weapon_and_no_head() -> void:
	var lot := _lot()
	var server: CombatServer = lot["server"]
	_feed(server.apply(CombatAction.give_weapon(1, &"shotgun")))
	_feed(RulesFixture.kill(lot["rules"], 1, lot["zombie"], RulesAction.ZONE_BODY))
	assert_int(_tally.count(1, ChallengeStats.weapon_kills(&"shotgun"))).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.weapon_kills(&"pistol"))).is_equal(0)
	assert_int(_tally.count(1, ChallengeStats.KILLS_HEAD)).is_equal(0)


func test_a_crowbar_kill_counts_melee_and_the_crowbar() -> void:
	var lot := _lot()
	var server: CombatServer = lot["server"]
	_feed(server.apply(CombatAction.give_weapon(1, &"crowbar")))
	WeaponsFixture.step(server, {lot["zombie"]: Vector3(0, 0, -1.2)}, 2)
	for swing in 3:
		var action := CombatAction.fire(1, swing + 1, CHEST, Vector3(0, 0, -1), CHEST, server.now)
		_feed(server.apply(action))
		for _i in 40:
			_step(server, {lot["zombie"]: Vector3(0, 0, -1.2)})
	assert_int(_tally.count(1, ChallengeStats.KILLS_MELEE)).is_greater(0)
	assert_int(_tally.count(1, ChallengeStats.weapon_kills(&"crowbar"))).is_equal(
		_tally.count(1, ChallengeStats.KILLS_MELEE)
	)


func test_a_grenade_kill_counts_the_blast_and_no_weapon() -> void:
	var lot := _lot()
	var victims := [{"zombie_id": lot["zombie"], "damage": 99999.0, "leg_damage": 0.0}]
	_feed(lot["rules"].apply(RulesAction.explosion(1, victims)))
	assert_int(_tally.count(1, ChallengeStats.KILLS)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.KILLS_BLAST)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.weapon_kills(&"pistol"))).is_equal(0)


func test_a_zombie_that_left_alone_is_nobodys_kill() -> void:
	var lot := _lot()
	var rules: GameRules = lot["rules"]
	_feed(rules.apply(RulesAction.zombie_gone(lot["zombie"])))
	assert_int(_tally.count(1, ChallengeStats.KILLS)).is_equal(0)


func test_a_boss_kill_counts_the_boss() -> void:
	var log := RulesFixture.new()
	var rules := RulesFixture.with_one_living(&"headliner", null, log)
	_feed(log.events)
	_feed(RulesFixture.kill(rules, 1, rules.zombie_ids()[0], RulesAction.ZONE_WEAK))
	assert_int(_tally.count(1, ChallengeStats.KILLS_BOSS)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.type_kills(&"headliner"))).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.KILLS_HEAD)).is_equal(1)


func test_boards_doors_buys_and_fuel_cans_count_from_the_rules() -> void:
	var lot := _lot()
	var rules: GameRules = lot["rules"]
	_feed(rules.apply(RulesAction.grant_points(1, 5000)))
	_feed(rules.apply(RulesAction.tear_board(&"w", lot["zombie"])))
	_feed(rules.apply(RulesAction.repair(1, &"w")))
	_feed(rules.apply(RulesAction.buy(1, &"door_concession")))
	rules.generator.fuel = 40.0
	_feed(rules.apply(RulesAction.tick(RulesFixture.STEP)))
	_feed(rules.apply(RulesAction.buy(1, &"fuel_can")))
	assert_int(_tally.count(1, ChallengeStats.BOARDS)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.DOORS)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.FUEL_CANS)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.BUYS)).is_equal(2)


func test_a_refused_purchase_is_not_a_buy() -> void:
	var made := ChallengeFixture.night(1)
	var rules: GameRules = made["rules"]
	_feed(made["events"])
	RulesFixture.into_round_one(rules)
	_feed(rules.apply(RulesAction.buy(1, &"door_road")))
	assert_int(_tally.count(1, ChallengeStats.BUYS)).is_equal(0)
	assert_int(_tally.count(1, ChallengeStats.DOORS)).is_equal(0)


func test_points_earned_leave_out_the_starting_purse_and_what_is_spent() -> void:
	var made := ChallengeFixture.night(1)
	var rules: GameRules = made["rules"]
	_feed(made["events"])
	assert_int(_tally.count(1, ChallengeStats.POINTS)).is_equal(0)
	RulesFixture.into_round_one(rules)
	_feed(rules.apply(RulesAction.grant_points(1, 300)))
	_feed(rules.apply(RulesAction.buy(1, &"door_concession")))
	assert_int(_tally.count(1, ChallengeStats.POINTS)).is_equal(300)


func test_a_round_counts_a_round_and_the_round_reached() -> void:
	var made := ChallengeFixture.night(1)
	var rules: GameRules = made["rules"]
	_feed(made["events"])
	_feed(ChallengeFixture.play_round_one(rules, 1))
	assert_int(_tally.count(1, ChallengeStats.ROUNDS)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.ROUND)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.NIGHTS)).is_equal(0)


func test_the_night_ending_counts_a_night_and_the_best_round() -> void:
	var made := ChallengeFixture.night(1)
	var rules: GameRules = made["rules"]
	_feed(made["events"])
	_feed(ChallengeFixture.play_round_one(rules, 1))
	_feed(rules.apply(RulesAction.skip_break()))
	_feed(rules.apply(RulesAction.set_downed(1, true)))
	assert_int(rules.phase).is_equal(GameRules.Phase.OVER)
	assert_int(_tally.count(1, ChallengeStats.NIGHTS)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.ROUND)).is_equal(2)


func test_a_downed_player_still_has_the_round_counted() -> void:
	var made := ChallengeFixture.night(2)
	var rules: GameRules = made["rules"]
	_feed(made["events"])
	rules.apply(RulesAction.start())
	_feed(rules.apply(RulesAction.set_downed(2, true)))
	_feed(ChallengeFixture.play_round_one(rules, 1))
	assert_int(_tally.count(2, ChallengeStats.ROUNDS)).is_equal(1)


func test_every_player_is_counted_from_the_events_that_name_them() -> void:
	var lot := _lot(2)
	var rules: GameRules = lot["rules"]
	_feed(RulesFixture.kill(rules, 2, lot["zombie"], RulesAction.ZONE_HEAD))
	_feed(rules.apply(RulesAction.grant_points(1, 700)))
	assert_int(_tally.count(2, ChallengeStats.KILLS)).is_equal(1)
	assert_int(_tally.count(1, ChallengeStats.KILLS)).is_equal(0)
	assert_int(_tally.count(1, ChallengeStats.POINTS)).is_equal(700)
	assert_int(_tally.count(2, ChallengeStats.POINTS)).is_greater(0)
	assert_array(_tally.players()).contains_exactly_in_any_order([1, 2])


func test_a_player_who_left_has_no_round_or_night_counted() -> void:
	var made := ChallengeFixture.night(2)
	var rules: GameRules = made["rules"]
	_feed(made["events"])
	rules.apply(RulesAction.start())
	_feed(rules.apply(RulesAction.remove_player(2)))
	_feed(ChallengeFixture.play_round_one(rules, 1))
	assert_int(_tally.count(1, ChallengeStats.ROUNDS)).is_equal(1)
	assert_int(_tally.count(2, ChallengeStats.ROUNDS)).is_equal(0)
	assert_bool(_tally.is_present(2)).is_false()


func test_a_solo_player_counts_the_same_alone_and_in_company() -> void:
	var tallies: Array[NightTally] = [NightTally.new(), NightTally.new()]
	var sizes := [1, 3]
	for i in 2:
		var night := ChallengeFixture.night(sizes[i])
		var rules: GameRules = night["rules"]
		for event: Dictionary in night["events"]:
			tallies[i].observe(event)
		rules.apply(RulesAction.start())
		rules.apply(RulesAction.skip_break())
		var killed := 0
		while killed < 3:
			for event in rules.apply(RulesAction.tick(RulesFixture.STEP)):
				tallies[i].observe(event)
			for zombie_id in rules.zombie_ids():
				if killed < 3:
					killed += 1
					for event in RulesFixture.kill(rules, 1, zombie_id, RulesAction.ZONE_HEAD):
						tallies[i].observe(event)
	for stat in [ChallengeStats.KILLS, ChallengeStats.KILLS_HEAD, ChallengeStats.POINTS]:
		assert_int(tallies[1].count(1, stat)).is_equal(tallies[0].count(1, stat))
	assert_int(tallies[0].count(1, ChallengeStats.KILLS)).is_equal(3)
	assert_int(tallies[1].count(2, ChallengeStats.KILLS)).is_equal(0)


func test_a_frame_makes_a_late_player_present_and_names_their_weapon() -> void:
	var frame := {"type": &"frame", "players": {7: {"weapon": &"rifle"}}}
	_tally.observe(frame)
	assert_bool(_tally.is_present(7)).is_true()
	(
		_tally
		. observe(
			{
				"type": &"zombie_removed",
				"zombie_id": 1,
				"zombie_type": &"walker",
				"boss": false,
				"cause": &"killed",
				"killer_id": 7,
				"zone": &"body",
				"melee": false,
			}
		)
	)
	assert_int(_tally.count(7, ChallengeStats.weapon_kills(&"rifle"))).is_equal(1)


func test_reset_forgets_the_night() -> void:
	_tally.observe({"type": &"player_added", "player_id": 1})
	_tally.observe({"type": &"round_started", "round": 3})
	_tally.reset()
	assert_int(_tally.count(1, ChallengeStats.ROUND)).is_equal(0)
	assert_array(_tally.players()).is_empty()
