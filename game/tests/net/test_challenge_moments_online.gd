extends GdUnitTestSuite
## The odd and together stats from a real game server and real clients (#1074): signed-in seats
## over a real WebSocket, the shipped challenges, a night the rules play and the clients watch.
## Each stat is counted by the server from the events and the frames it makes (`NightMoments`), told
## to every client as `challenge_done`, and written in the seat's board; the test counts it again
## from what a client heard, with code of its own. The rare ones are reached the way a night
## reaches them (a window mended by two, the last round in the dark, a down in a round's first
## seconds, a booth held), by the rules' own actions and the players' own commands, not by saying
## a count.

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"
const MATCH := "match-moments"
const DAY := 20401
## The booth of the lot (`data/areas.json`) and a point on the road outside it.
const IN_BOOTH := Vector3(0.0, 0.2, 27.0)
const OUT_OF_BOOTH := Vector3(0.0, 0.2, 14.0)

var _server: GameServer
var _nights: Array[Night] = []
var _commands: Dictionary = {}
## Per client, every event but frames, in the order heard.
var _heard: Dictionary = {}
var _tuning: RulesTuning
var _map := "drive_in"
## How many dead a round brings: a quarter, so a round is a few of them, unless a test says more.
var _count := MatchSettings.MIN_COUNT_MULTIPLIER
## The level of the host the tickets name (the back rooms open at 10).
var _host_level := 12


func before_test() -> void:
	_tuning = null
	_count = MatchSettings.MIN_COUNT_MULTIPLIER
	_map = "drive_in"


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_commands.clear()
	_heard.clear()
	if is_instance_valid(_server):
		_server.get_parent().queue_free()
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _until(condition: Callable, seconds: float = 30.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


## A game server on the shipped challenges; the dead come few at a time and the breaks are short.
func _start(map := "drive_in") -> GameServer:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 4
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.rules_tuning = _tuning
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_server.challenge_catalog = ChallengeCatalog.load_default()
	_server.challenge_clock = ChallengeFixture.clock_on(DAY)
	_server.report_sender = func(_path: String, _body: Dictionary) -> int: return 200
	_server.board_reader = func(_user: String) -> Dictionary:
		return {"status": 404, "json": ChallengeAward.NO_BOARD}
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())
	_map = map
	return _server


func _settings() -> Dictionary:
	var chosen := MatchSettings.new()
	chosen.count_multiplier = _count
	chosen.break_seconds = 1.0
	chosen.map = _map
	return chosen.to_dict()


## A signed-in client that sends the command held for it every tick.
func _client(user: String) -> Night:
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = TicketMaker.make(
		SECRET, SERVER_ID, MATCH, user, user.capitalize(), 60, _settings(), _host_level, {"xp": 0}
	)
	var joined := await night.start_remote(
		"ws://127.0.0.1:%d" % _server.listener.port(), Night.Mode.MANUAL, 60.0, link
	)
	assert_bool(joined).is_true()
	_nights.append(night)
	var heard: Array[Dictionary] = []
	_heard[night] = heard
	night.state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] != &"frame":
				heard.append(event)
	)
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void:
			var command: NightCommand = _commands.get(night)
			if command != null:
				night.link.send(command.to_dict())
	)
	return night


## Signed-in clients in the order of `users`, each followed by the server (seats 1, 2, ...).
func _crew(users: Array[String]) -> Array[Night]:
	var crew: Array[Night] = []
	for user in users:
		crew.append(await _client(user))
	for seat in users.size():
		(
			assert_bool(
				await _until(func() -> bool: return _room().server.challenges.follows(seat + 1))
			)
			. is_true()
		)
	return crew


func _room() -> NightHost:
	return _server.room_of_match(MATCH)


func _rules() -> GameRules:
	return _room().server.rules


## An action of the server's own (a kill, a purchase, a blow), whose events go on to every client
## as the game server sends the rules' answers between two steps.
func _act(action: Dictionary) -> Array[Dictionary]:
	var events := _rules().apply(action)
	_room()._collect(events)
	return events


func _kill(killer: int, zombie_id: int, melee := false) -> void:
	_act(
		RulesAction.hit(
			killer, zombie_id, RulesAction.ZONE_BODY, RulesFixture.KILLING_DAMAGE, melee
		)
	)


## The board the server keeps for this account.
func _board(user: String) -> ChallengeProfile:
	return _room().server.challenges.profile_of(user)


func _stat(user: String, stat: StringName) -> int:
	return int(_board(user).lifetime.get(stat, 0))


## The ids of the challenges the server told this client were done for `seat`.
func _done(night: Night, seat: int) -> Array:
	var ids: Array = []
	for event: Dictionary in _heard[night]:
		if event["type"] == ChallengeAward.DONE and event["player_id"] == seat:
			ids.append(event["id"])
	return ids


## How many events of `type` this client has heard; of one `field` equal to `value` when given.
func _heard_count(night: Night, type: StringName, field := &"", value := 0) -> int:
	var found := 0
	for event: Dictionary in _heard[night]:
		if event["type"] == type and (field == &"" or event.get(field, 0) == value):
			found += 1
	return found


## Starts the round and ticks until it is over, killing the dead as they stand; `kill_with` is
## called with each zombie id and answers the killer's seat.
func _clear_round(killer: Callable, on_start := Callable()) -> void:
	var rules := _rules()
	var round_before := rules.round_number
	_act(RulesAction.skip_break())
	if on_start.is_valid():
		await on_start.call()
	var began := Time.get_ticks_msec()
	while (
		rules.round_number == round_before + 1
		and (rules.phase == GameRules.Phase.ACTIVE or rules.phase == GameRules.Phase.IDLE)
	):
		await get_tree().physics_frame
		for zombie_id in rules.zombie_ids():
			_kill(killer.call(zombie_id), zombie_id)
		if Time.get_ticks_msec() - began > 120000:
			break
	assert_int(rules.phase).is_equal(GameRules.Phase.BREAK)


## One frame of the server, so the tallies have heard what the last action did.
func _settle(frames := 3) -> void:
	for _i in frames:
		await get_tree().physics_frame


# --- A crew's rounds: no shots, no kills, the whole crew ---


## Counts, with code of its own, what a client heard of each round: who fired a gun, who killed,
## who stood at the end. The server's lifetime numbers must be these.
func _witness(night: Night, seat: int, melee_ids: Array) -> Dictionary:
	var fired := false
	var killed := false
	var out := {"unfired": 0, "no_kills": 0, "rounds": 0}
	for event: Dictionary in _heard[night]:
		match event["type"]:
			&"round_started":
				fired = false
				killed = false
			&"shot_fired":
				if event["shooter_id"] == seat and not melee_ids.has(event["weapon_id"]):
					fired = true
			&"zombie_removed":
				if event["killer_id"] == seat and event["cause"] == &"killed":
					killed = true
			&"round_ended":
				if (event["standing"] as Array).has(seat):
					out["rounds"] += 1
					out["unfired"] += 0 if fired else 1
					out["no_kills"] += 0 if killed else 1
	return out


func test_a_crew_round_with_no_gun_fired_and_one_killer_is_counted_for_each_seat() -> void:
	await _start()
	var crew := await _crew(["ann", "bo", "cy"])
	var ann := crew[0]
	await _clear_round(func(_zombie: int) -> int: return 1)
	(
		assert_bool(await _until(func() -> bool: return _stat("cy", ChallengeStats.ROUNDS) == 1))
		. is_true()
	)
	# Round one: nobody fired a gun (the rules played it), only ann killed, all three stood.
	for user in ["ann", "bo", "cy"]:
		assert_int(_stat(user, ChallengeStats.ROUNDS_UNFIRED)).is_equal(1)
		assert_int(_stat(user, ChallengeStats.ROUNDS_WHOLE)).is_equal(1)
	assert_int(_stat("ann", ChallengeStats.ROUNDS_NO_KILLS)).is_equal(0)
	assert_int(_stat("bo", ChallengeStats.ROUNDS_NO_KILLS)).is_equal(1)
	assert_int(_stat("cy", ChallengeStats.ROUNDS_NO_KILLS)).is_equal(1)
	# Every client was told the same finishes, to the right seats.
	for night in crew:
		var told_all := func() -> bool: return _done(night, 3).has(&"f_nobody_home")
		assert_bool(await _until(told_all)).is_true()
	for night in crew:
		assert_array(_done(night, 1)).contains([&"f_hands_in_pockets", &"f_whole_crew"])
		assert_array(_done(night, 1)).not_contains([&"f_nobody_home"])
		assert_array(_done(night, 2)).contains(
			[&"f_hands_in_pockets", &"f_whole_crew", &"f_nobody_home"]
		)
		assert_array(_done(night, 3)).contains([&"f_nobody_home"])
	for id in [&"f_hands_in_pockets", &"f_nobody_home", &"f_whole_crew"]:
		assert_int(int(_board("bo").feats.get(id, 0))).is_equal(1)
	assert_int(int(_board("ann").feats.get(&"f_nobody_home", 0))).is_equal(0)
	# Round two: bo fires a real shot with the gun in his hands.
	var bo := crew[1]
	var command: NightCommand = _commands[bo]
	command.aim_along(Vector3(0.0, 0.0, -1.0))
	var shots_before := _heard_count(bo, &"shot_fired", &"shooter_id", 2)
	_act(RulesAction.skip_break())
	var fired := func() -> bool:
		command.fire = true
		return _heard_count(bo, &"shot_fired", &"shooter_id", 2) > shots_before
	assert_bool(await _until(fired, 20.0)).is_true()
	command.fire = false
	var rules := _rules()
	var began := Time.get_ticks_msec()
	while rules.phase == GameRules.Phase.ACTIVE and Time.get_ticks_msec() - began < 120000:
		await get_tree().physics_frame
		for zombie_id in rules.zombie_ids():
			_kill(3, zombie_id)
	(
		assert_bool(await _until(func() -> bool: return _stat("cy", ChallengeStats.ROUNDS) == 2))
		. is_true()
	)
	assert_int(_stat("ann", ChallengeStats.ROUNDS_UNFIRED)).is_equal(2)
	assert_int(_stat("bo", ChallengeStats.ROUNDS_UNFIRED)).is_equal(1)
	assert_int(_stat("cy", ChallengeStats.ROUNDS_UNFIRED)).is_equal(2)
	assert_int(_stat("ann", ChallengeStats.ROUNDS_NO_KILLS)).is_equal(1)
	assert_int(_stat("cy", ChallengeStats.ROUNDS_NO_KILLS)).is_equal(1)
	# The count made again from what ann's client heard.
	var told_round_two := func() -> bool: return _heard_count(ann, &"round_ended") == 2
	assert_bool(await _until(told_round_two)).is_true()
	var melee: Array = WeaponCatalog.IDS.filter(
		func(id: StringName) -> bool: return WeaponCatalog.get_def(id).is_melee()
	)
	for seat in [1, 2, 3]:
		var user: String = ["ann", "bo", "cy"][seat - 1]
		var counted := _witness(ann, seat, melee)
		assert_int(_stat(user, ChallengeStats.ROUNDS_UNFIRED)).is_equal(counted["unfired"])
		assert_int(_stat(user, ChallengeStats.ROUNDS_NO_KILLS)).is_equal(counted["no_kills"])
		assert_int(_stat(user, ChallengeStats.ROUNDS)).is_equal(counted["rounds"])


# --- The stand: early doors, every door, the seat that never spent ---


func _prices_paid(night: Night, seat: int) -> int:
	var paid := 0
	for event: Dictionary in _heard[night]:
		if event["type"] == &"purchase_made" and event["player_id"] == seat:
			paid += int(event["price"])
	return paid


func test_doors_bought_early_the_lot_opened_and_a_seat_that_never_spent_reaches_round_six() -> void:
	_tuning = RulesFixture.tuning()
	_tuning.rounds.intro_seconds = 120.0
	await _start()
	var crew := await _crew(["ann", "bo", "cy"])
	var rules := _rules()
	# The night is young: the doors are bought in its first half minute, by the rules' own clock.
	assert_float(rules.night_time).is_less(25.0)
	var doors: Array[StringName] = []
	for item in rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			doors.append(item.id)
	for seat in [1, 2]:
		_act(RulesAction.grant_points(seat, 6000))
	for door in doors:
		var buyer := 1 if door == &"door_concession" else 2
		var events := _act(RulesAction.buy(buyer, door))
		assert_bool(RulesFixture.first(events, &"purchase_made").is_empty()).is_false()
	assert_float(rules.night_time).is_less(30.0)
	var all_open := func() -> bool: return _stat("cy", ChallengeStats.DOORS_ALL_EARLY) == 1
	assert_bool(await _until(all_open)).is_true()
	assert_int(_stat("ann", ChallengeStats.DOORS_EARLY)).is_equal(1)
	assert_int(_stat("bo", ChallengeStats.DOORS_EARLY)).is_equal(doors.size() - 1)
	for user in ["ann", "bo", "cy"]:
		assert_int(_stat(user, ChallengeStats.DOORS_ALL_EARLY)).is_equal(1)
	# What the stand took is what a client heard it cost.
	var looking := crew[2]
	assert_bool(await _until(func() -> bool: return _prices_paid(looking, 2) > 0)).is_true()
	assert_int(_stat("ann", ChallengeStats.POINTS_SPENT)).is_equal(_prices_paid(looking, 1))
	assert_int(_stat("bo", ChallengeStats.POINTS_SPENT)).is_equal(_prices_paid(looking, 2))
	assert_int(_stat("cy", ChallengeStats.POINTS_SPENT)).is_equal(0)
	# Five rounds, and the sixth begins: only the seat that spent nothing reached it unspent.
	for _round in 5:
		await _clear_round(func(_zombie: int) -> int: return 1)
	_act(RulesAction.skip_break())
	var unspent := func() -> bool: return _stat("cy", ChallengeStats.ROUND_UNSPENT) == 6
	assert_bool(await _until(unspent)).is_true()
	assert_int(_stat("ann", ChallengeStats.ROUND_UNSPENT)).is_equal(0)
	assert_int(_stat("bo", ChallengeStats.ROUND_UNSPENT)).is_equal(0)
	for night in crew:
		assert_bool(await _until(func() -> bool: return _done(night, 3).has(&"f_stingy"))).is_true()
		assert_array(_done(night, 3)).contains([&"f_door_to_door"])
		assert_array(_done(night, 1)).contains([&"f_early_bird", &"f_door_to_door"])
		assert_array(_done(night, 1)).not_contains([&"f_stingy"])
		assert_array(_done(night, 2)).not_contains([&"f_stingy"])


# --- The generator: a round in the dark ---


func test_a_round_of_three_or_later_cleared_with_every_circuit_off_is_a_round_in_the_dark() -> void:
	await _start()
	var crew := await _crew(["ann"])
	var circuits: Array = _rules().generator.circuits.keys()
	assert_array(circuits).is_not_empty()
	var lights := func(on: bool) -> void:
		for circuit: StringName in circuits:
			_act(RulesAction.set_circuit(circuit, on))
		await _settle(4)
	await lights.call(false)
	await _clear_round(func(_zombie: int) -> int: return 1)
	(
		assert_bool(
			await _until(func() -> bool: return _stat("ann", ChallengeStats.ROUND_DARK) == 1)
		)
		. is_true()
	)
	# Round two is lit: it is no round in the dark, and the best stays where it was.
	await lights.call(true)
	await _clear_round(func(_zombie: int) -> int: return 1)
	(
		assert_bool(await _until(func() -> bool: return _stat("ann", ChallengeStats.ROUNDS) == 2))
		. is_true()
	)
	assert_int(_stat("ann", ChallengeStats.ROUND_DARK)).is_equal(1)
	# Round three begins dark and a circuit is switched on in it: not that one either.
	await lights.call(false)
	await _clear_round(
		func(_zombie: int) -> int: return 1,
		func() -> void:
			_act(RulesAction.set_circuit(circuits[0], true))
			await _settle(2)
	)
	(
		assert_bool(await _until(func() -> bool: return _stat("ann", ChallengeStats.ROUNDS) == 3))
		. is_true()
	)
	assert_int(_stat("ann", ChallengeStats.ROUND_DARK)).is_equal(1)
	# Round four, dark from start to end, is round three or later in the dark.
	await lights.call(false)
	await _clear_round(func(_zombie: int) -> int: return 1)
	(
		assert_bool(
			await _until(func() -> bool: return _stat("ann", ChallengeStats.ROUND_DARK) == 4)
		)
		. is_true()
	)
	(
		assert_bool(await _until(func() -> bool: return _done(crew[0], 1).has(&"f_lights_out")))
		. is_true()
	)


# --- The booth, and a down in a round's first seconds ---


func test_a_round_held_in_the_booth_and_a_down_in_the_first_seconds_are_seen_by_the_server(
) -> void:
	await _start()
	var crew := await _crew(["ann", "bo"])
	var server := _room().server
	server.body_of(1).teleport(IN_BOOTH)
	await _settle(5)
	assert_float(server.body_of(1).global_position.z).is_between(22.0, 32.0)
	await _clear_round(
		func(_zombie: int) -> int: return 1,
		func() -> void:
			await _settle(30)
			_act(RulesAction.blow(2, 99999.0))
	)
	(
		assert_bool(await _until(func() -> bool: return _stat("ann", ChallengeStats.ROUNDS) == 1))
		. is_true()
	)
	assert_int(_stat("ann", ChallengeStats.ROUNDS_BOOTH)).is_equal(1)
	assert_int(_stat("bo", ChallengeStats.ROUNDS_BOOTH)).is_equal(0)
	assert_int(_stat("bo", ChallengeStats.DOWNS_EARLY)).is_equal(1)
	assert_int(_stat("ann", ChallengeStats.DOWNS_EARLY)).is_equal(0)
	# The one got up at the round's end is nobody's rescue.
	assert_int(_stat("ann", ChallengeStats.REVIVES)).is_equal(0)
	assert_int(_stat("bo", ChallengeStats.REVIVES)).is_equal(0)
	# Round two: ann steps out of the booth in it.
	await _clear_round(
		func(_zombie: int) -> int: return 1,
		func() -> void:
			await _settle(10)
			server.body_of(1).teleport(OUT_OF_BOOTH)
	)
	(
		assert_bool(await _until(func() -> bool: return _stat("ann", ChallengeStats.ROUNDS) == 2))
		. is_true()
	)
	assert_int(_stat("ann", ChallengeStats.ROUNDS_BOOTH)).is_equal(1)
	for night in crew:
		(
			assert_bool(await _until(func() -> bool: return _done(night, 2).has(&"f_fell_asleep")))
			. is_true()
		)
		assert_array(_done(night, 1)).contains([&"f_booth_holder"])
		assert_array(_done(night, 1)).not_contains([&"f_fell_asleep"])
		assert_array(_done(night, 2)).not_contains([&"f_booth_holder"])


# --- The last bullet ---


func test_the_last_bullet_fired_by_a_real_command_leaves_a_dry_gun_at_the_round_end() -> void:
	await _start()
	var crew := await _crew(["ann", "bo"])
	var server := _room().server
	var gun := server.combat.weapon_of(1)
	gun.ammo = 1
	gun.reserve = 0
	await _settle(4)
	var command: NightCommand = _commands[crew[0]]
	command.aim_along(Vector3(0.0, 0.0, -1.0))
	var rules := _rules()
	_act(RulesAction.skip_break())
	var shot := func() -> bool:
		command.fire = true
		return crew[0].state.frame.get("players", {}).get(1, {}).get("ammo", 1) == 0
	assert_bool(await _until(shot, 20.0)).is_true()
	command.fire = false
	assert_int(gun.reserve).is_equal(0)
	var began := Time.get_ticks_msec()
	while rules.phase == GameRules.Phase.ACTIVE and Time.get_ticks_msec() - began < 120000:
		await get_tree().physics_frame
		for zombie_id in rules.zombie_ids():
			_kill(1, zombie_id)
	(
		assert_bool(await _until(func() -> bool: return _stat("bo", ChallengeStats.ROUNDS) == 1))
		. is_true()
	)
	assert_int(_stat("ann", ChallengeStats.ROUNDS_DRY)).is_equal(1)
	assert_int(_stat("bo", ChallengeStats.ROUNDS_DRY)).is_equal(0)
	# She fired a real shot, so her hands were not in her pockets; his were.
	assert_int(_stat("ann", ChallengeStats.ROUNDS_UNFIRED)).is_equal(0)
	assert_int(_stat("bo", ChallengeStats.ROUNDS_UNFIRED)).is_equal(1)
	(
		assert_bool(await _until(func() -> bool: return _done(crew[1], 1).has(&"f_last_bullet")))
		. is_true()
	)


# --- Crawlers with the crowbar ---


func test_five_crawlers_put_down_with_the_crowbar_in_half_a_minute_are_a_run() -> void:
	# The dead come as fast as the count says: a quarter would spread five over a minute.
	_count = 2.0
	await _start()
	var crew := await _crew(["ann"])
	var server := _room().server
	server._combat(CombatAction.give_weapon(1, &"crowbar"))
	server._combat(CombatAction.equip(1, &"crowbar"))
	var in_hand := func() -> bool:
		return crew[0].state.frame.get("players", {}).get(1, {}).get("weapon", &"") == &"crowbar"
	assert_bool(await _until(in_hand)).is_true()
	await _settle(4)
	var rules := _rules()
	_act(RulesAction.skip_break())
	rules._plan.assign([&"crawler", &"crawler", &"crawler", &"crawler", &"crawler"])
	var began := Time.get_ticks_msec()
	var put_down := 0
	while rules.phase == GameRules.Phase.ACTIVE and Time.get_ticks_msec() - began < 120000:
		await get_tree().physics_frame
		for zombie_id in rules.zombie_ids():
			_kill(1, zombie_id, true)
			put_down += 1
	assert_int(put_down).is_greater_equal(5)
	(
		assert_bool(
			await _until(func() -> bool: return _stat("ann", ChallengeStats.CRAWLER_RUNS) == 1)
		)
		. is_true()
	)
	(
		assert_bool(await _until(func() -> bool: return _done(crew[0], 1).has(&"f_whack_a_mole")))
		. is_true()
	)


# --- Boards ---


func test_three_boards_by_one_and_a_board_beside_a_teammates_are_a_rush_and_a_pit_crew() -> void:
	await _start()
	var crew := await _crew(["ann", "bo"])
	var rules := _rules()
	var window: StringName = rules.barricades.boards.keys()[0]
	rules.barricades.boards[window] = 0
	await _settle(2)
	for seat in [1, 1, 1, 2, 2]:
		var events := _act(RulesAction.repair(seat, window))
		assert_bool(RulesFixture.first(events, &"board_repaired").is_empty()).is_false()
	(
		assert_bool(
			await _until(func() -> bool: return _stat("bo", ChallengeStats.BOARDS_SHARED) == 2)
		)
		. is_true()
	)
	assert_int(_stat("ann", ChallengeStats.BOARD_RUSHES)).is_equal(1)
	assert_int(_stat("bo", ChallengeStats.BOARD_RUSHES)).is_equal(0)
	# Ann put hers up with no one at the window; both of bo's had her beside.
	assert_int(_stat("ann", ChallengeStats.BOARDS_SHARED)).is_equal(0)
	for night in crew:
		(
			assert_bool(await _until(func() -> bool: return _done(night, 2).has(&"f_pit_crew")))
			. is_true()
		)
		assert_array(_done(night, 1)).contains([&"f_carpenters_rush"])
		assert_array(_done(night, 1)).not_contains([&"f_pit_crew"])
		assert_array(_done(night, 2)).not_contains([&"f_carpenters_rush"])


# --- A blast ---


func test_a_blast_that_kills_three_is_the_best_of_three_for_one() -> void:
	_tuning = RulesFixture.tuning()
	_tuning.rounds.first_spawn_delay = 0.2
	await _start()
	var crew := await _crew(["ann", "bo"])
	var rules := _rules()
	_act(RulesAction.skip_break())
	rules._plan.assign([&"walker", &"walker", &"walker", &"walker"])
	var gathered := func() -> bool: return rules.zombie_ids().size() >= 3
	assert_bool(await _until(gathered, 60.0)).is_true()
	var victims := rules.zombie_ids().slice(0, 3).map(
		func(id: int) -> Dictionary:
			return {"zombie_id": id, "damage": RulesFixture.KILLING_DAMAGE, "leg_damage": 0.0}
	)
	var events := _act(RulesAction.explosion(1, victims))
	assert_int(RulesFixture.first(events, &"blast_resolved")["kills"]).is_equal(3)
	(
		assert_bool(
			await _until(func() -> bool: return _stat("ann", ChallengeStats.BLAST_BEST) == 3)
		)
		. is_true()
	)
	assert_int(_stat("bo", ChallengeStats.BLAST_BEST)).is_equal(0)
	# A later blast of one does not take it back.
	(
		assert_bool(await _until(func() -> bool: return not rules.zombie_ids().is_empty(), 60.0))
		. is_true()
	)
	var left := rules.zombie_ids()[0]
	var one := {"zombie_id": left, "damage": RulesFixture.KILLING_DAMAGE, "leg_damage": 0.0}
	_act(RulesAction.explosion(1, [one]))
	await _settle(4)
	assert_int(_stat("ann", ChallengeStats.BLAST_BEST)).is_equal(3)
	for night in crew:
		(
			assert_bool(
				await _until(func() -> bool: return _done(night, 1).has(&"f_three_for_one"))
			)
			. is_true()
		)
		assert_array(_done(night, 2)).not_contains([&"f_three_for_one"])


# --- Weapons ---


func test_five_different_weapons_each_with_a_kill_finish_try_the_lot() -> void:
	_tuning = RulesFixture.tuning()
	_tuning.rounds.first_spawn_delay = 0.2
	await _start()
	var crew := await _crew(["ann"])
	var server := _room().server
	var rules := _rules()
	_act(RulesAction.skip_break())
	var plan: Array[StringName] = []
	for _i in 8:
		plan.append(&"walker")
	rules._plan.assign(plan)
	var weapons: Array[StringName] = [
		&"pistol", &"smg", &"shotgun", &"rifle", &"crowbar", &"pistol"
	]
	var used: Array[StringName] = []
	for weapon in weapons:
		for carried in server.combat.carried(1):
			server._combat(CombatAction.remove_weapons(1, [carried]))
		server._combat(CombatAction.give_weapon(1, weapon))
		server._combat(CombatAction.equip(1, weapon))
		var in_hand := func() -> bool:
			return crew[0].state.frame.get("players", {}).get(1, {}).get("weapon", &"") == weapon
		assert_bool(await _until(in_hand)).is_true()
		await _settle(3)
		var standing := func() -> bool: return not rules.zombie_ids().is_empty()
		assert_bool(await _until(standing, 60.0)).is_true()
		_kill(1, rules.zombie_ids()[0])
		if not used.has(weapon):
			used.append(weapon)
		await _settle(3)
		assert_int(_stat("ann", ChallengeStats.weapon_kills(weapon))).is_greater(0)
		# The board holds as many weapons as the test has put a kill into.
		assert_int(int(_board("ann").feats.get(&"f_try_the_lot", 0))).is_equal(mini(used.size(), 5))
	(
		assert_bool(await _until(func() -> bool: return _done(crew[0], 1).has(&"f_try_the_lot")))
		. is_true()
	)


# --- Rescues ---


func test_five_rescues_by_a_real_hold_in_one_night_are_a_hand_up_and_holding_the_line() -> void:
	_tuning = RulesFixture.tuning()
	_tuning.rounds.first_spawn_delay = 600.0
	_tuning.health.revive_seconds = 0.5
	await _start()
	var crew := await _crew(["ann", "bo"])
	var rules := _rules()
	var server := _room().server
	_act(RulesAction.skip_break())
	var helper: NightCommand = _commands[crew[1]]
	for _rescue in 5:
		_act(RulesAction.blow(1, 99999.0))
		assert_bool(await _until(func() -> bool: return rules.players[1].downed)).is_true()
		server.body_of(2).teleport(server.body_of(1).global_position + Vector3(1.0, 0.0, 0.0))
		helper.use_held = true
		helper.use = true
		(
			assert_bool(await _until(func() -> bool: return not rules.players[1].downed, 20.0))
			. is_true()
		)
		helper.use_held = false
		helper.use = false
		await _settle(2)
	assert_int(rules.revives_of(2)).is_equal(5)
	var told := crew[0]
	var rescues_heard := func() -> int:
		return _heard_count(told, &"player_revived", &"reviver_id", 2)
	assert_bool(await _until(func() -> bool: return rescues_heard.call() == 5)).is_true()
	assert_int(_stat("bo", ChallengeStats.REVIVES)).is_equal(5)
	assert_int(_stat("ann", ChallengeStats.REVIVES)).is_equal(0)
	for night in crew:
		(
			assert_bool(
				await _until(func() -> bool: return _done(night, 2).has(&"f_hold_the_line"))
			)
			. is_true()
		)
		assert_array(_done(night, 2)).contains([&"f_hand_up"])
		assert_array(_done(night, 1)).not_contains([&"f_hand_up"])


# --- The night's end: the map and the company ---


func test_a_night_ended_on_the_back_rooms_with_two_people_is_both_of_those() -> void:
	await _start("small_indoor")
	var crew := await _crew(["ann", "bo"])
	var rules := _rules()
	assert_str(rules.settings.map).is_equal("small_indoor")
	_act(RulesAction.skip_break())
	_act(RulesAction.blow(1, 99999.0))
	_act(RulesAction.blow(2, 99999.0))
	assert_bool(await _until(func() -> bool: return rules.phase == GameRules.Phase.OVER)).is_true()
	for user in ["ann", "bo"]:
		(
			assert_bool(
				await _until(func() -> bool: return _stat(user, ChallengeStats.NIGHTS) == 1)
			)
			. is_true()
		)
		assert_int(_stat(user, ChallengeStats.map_nights(&"small_indoor"))).is_equal(1)
		assert_int(_stat(user, ChallengeStats.map_nights(&"drive_in"))).is_equal(0)
		assert_int(_stat(user, ChallengeStats.NIGHTS_TOGETHER)).is_equal(1)
	for night in crew:
		for seat in [1, 2]:
			(
				assert_bool(
					await _until(func() -> bool: return _done(night, seat).has(&"f_twos_company"))
				)
				. is_true()
			)
			assert_array(_done(night, seat)).contains([&"f_out_the_back", &"f_walk_in"])
