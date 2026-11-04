extends GdUnitTestSuite
## Every client hears a teammate's progression (#1063): over a real WebSocket, four clients sit in
## one night of a game server whose tickets carry each account's XP; when the server tells that a
## player crossed a level, every one of the four plays that player's cheer (the player at the
## screen flat, the others where the soldier stands), once, and a level that also opens a tier
## and gives an item is one cheer, the tier's. A challenge the server tells done (#1076, #1135) is
## cheered the same way, by every client, as the player who finished it.

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"
const MATCH := "match-voice"
## Raw XP one point of score short of level 2 and of level 6, the first of the second tier (85 XP a
## level up to level 6), which also gives the usher's cap.
const BELOW_LEVEL_2 := 84
const BELOW_LEVEL_6 := 424
const CLIENTS := 4
## The day the challenge clock stands on (any day: the quick catalogue's dailies are fixed by it).
const DAY := 20401

var _server: GameServer
var _nights: Array[Night] = []
var _lines: Dictionary[int, Array] = {}


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_lines.clear()
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


## A server for the night; with `challenges` it follows each seat's challenge board (a small
## catalogue a few kills finish, no board at the backend).
func _start(challenges := false) -> void:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = CLIENTS
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_server.report_sender = func(_path: String, _body: Dictionary) -> int: return 200
	if challenges:
		_server.challenge_catalog = ChallengeFixture.quick_catalog()
		_server.challenge_clock = ChallengeFixture.clock_on(DAY)
		_server.board_reader = func(_user: String) -> Dictionary:
			return {"status": 404, "json": ChallengeAward.NO_BOARD}
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())


## A client whose account holds `xp`; whatever its soldier voice plays is kept in `_lines[id]`
## (`{id, at, db}`) instead of going to the speakers.
func _client(user: String, xp: int, settings := {}) -> Night:
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = TicketMaker.make(
		SECRET, SERVER_ID, MATCH, user, user.capitalize(), 60, settings, null, {"xp": xp}
	)
	var url := "ws://127.0.0.1:%d" % _server.listener.port()
	assert_bool(await night.start_remote(url, Night.Mode.MANUAL, 60.0, link)).is_true()
	_nights.append(night)
	var id := night.state.player_id
	_lines[id] = []
	var voice := night.get_node("SoldierVoice") as SoldierVoice
	voice.play = func(sound: StringName, at: Variant, db: float) -> bool:
		_lines[id].append({"id": sound, "at": at, "db": db})
		return true
	return night


func _room() -> NightHost:
	return _server.room_of_match(MATCH)


## Four clients seated, player 1 the one about to cross a level.
func _four(first_xp: int) -> void:
	await _start()
	await _client("ann", first_xp)
	for user in ["bo", "cy", "di"]:
		await _client(user, 0)


func _said(listener: int, moment: StringName) -> Array:
	var prefix := "_%s_" % moment
	return _lines[listener].filter(
		func(line: Dictionary) -> bool: return String(line["id"]).contains(prefix)
	)


func _every_client_said(moment: StringName) -> bool:
	for listener in _lines:
		if _said(listener, moment).is_empty():
			return false
	return true


func test_every_client_plays_the_line_of_a_teammates_level_up() -> void:
	await _four(BELOW_LEVEL_2)
	assert_int(_nights.size()).is_equal(CLIENTS)
	# Ann's point of score is her second level; the server tells all four clients.
	_room().server.rules.apply(RulesAction.grant_points(1, 100))
	assert_bool(await _until(func() -> bool: return _every_client_said(&"level_up"))).is_true()
	for listener in _lines:
		var said := _said(listener, &"level_up")
		assert_int(said.size()).override_failure_message("client %d" % listener).is_equal(1)
		assert_bool(SoldierVoiceCatalog.is_take(said[0]["id"])).is_true()
		if listener == 1:
			# Her own cheer is in her head: flat, with the own-voice trim.
			assert_object(said[0]["at"]).is_null()
			assert_float(said[0]["db"]).is_equal(SoundCatalog.mix().own_voice_db)
		else:
			# A teammate hears it from where she stands.
			assert_object(said[0]["at"]).is_not_null()
			assert_float(said[0]["db"]).is_equal(0.0)


func test_a_level_that_opens_a_tier_is_one_cheer_for_every_client() -> void:
	await _four(BELOW_LEVEL_6)
	_room().server.rules.apply(RulesAction.grant_points(1, 100))
	assert_bool(await _until(func() -> bool: return _every_client_said(&"tier_up"))).is_true()
	# The level, the tier and the colour it gives came together: one line, the tier's.
	for _i in 60:
		await get_tree().physics_frame
	for listener in _lines:
		(
			assert_int(_lines[listener].size())
			. override_failure_message("client %d" % listener)
			. is_equal(1)
		)
		assert_int(_said(listener, &"tier_up").size()).is_equal(1)


func test_every_client_plays_the_line_of_a_teammates_finished_challenge() -> void:
	await _start(true)
	var chosen := MatchSettings.new()
	chosen.count_multiplier = 5.0
	for user in ["ann", "bo", "cy", "di"]:
		await _client(user, 0, chosen.to_dict())
	(
		assert_bool(await _until(func() -> bool: return _room().server.challenges.follows(CLIENTS)))
		. is_true()
	)
	# Ann puts down the four dead of the round: her daily "put down 4" is done, and the server
	# tells all four clients.
	var rules := _room().server.rules
	rules.apply(RulesAction.skip_break())
	var kills := 0
	while kills < 4:
		await get_tree().physics_frame
		for zombie_id in rules.zombie_ids():
			if kills < 4:
				RulesFixture.kill(rules, 1, zombie_id)
				kills += 1
	(
		assert_bool(await _until(func() -> bool: return _every_client_said(&"challenge_done")))
		. is_true()
	)
	for _i in 60:
		await get_tree().physics_frame
	for listener in _lines:
		var said := _said(listener, &"challenge_done")
		assert_int(said.size()).override_failure_message("client %d" % listener).is_equal(1)
		assert_bool(SoldierVoiceCatalog.is_take(said[0]["id"])).is_true()
		# Hers, whoever hears it: flat at her screen, where she stands for the others.
		assert_bool(said[0]["at"] == null).is_equal(listener == 1)
