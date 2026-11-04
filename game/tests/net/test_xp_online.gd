extends GdUnitTestSuite
## The game server awards XP a kill at a time (#1059): over a real WebSocket, a GameServer with
## tickets that carry the account's XP tells every client the `xp_gained`, `level_up` and
## `unlock_earned` events as they happen, a late joiner reads every level in its WELCOME, a client's
## own word changes nothing, and the backend is written once a round (never a kill). A Guest account
## earns like any other; a night with no account at all earns nothing.

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"
const MATCH := "match-xp"

var _server: GameServer
var _nights: Array[Night] = []
var _raw: Array[WebSocketPeer] = []
var _posts: Array[Dictionary] = []
var _host: NightHost


func after_test() -> void:
	for ws in _raw:
		ws.close()
	_raw.clear()
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_posts.clear()
	if is_instance_valid(_server):
		_server.get_parent().queue_free()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()
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


func _start() -> GameServer:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 2
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_server.report_sender = func(path: String, body: Dictionary) -> int:
		_posts.append({"path": path, "body": body})
		return 200
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())
	return _server


func _url() -> String:
	return "ws://127.0.0.1:%d" % _server.listener.port()


func _ticket(user: String, account: Dictionary, settings: Dictionary = {}) -> String:
	return TicketMaker.make(
		SECRET, SERVER_ID, MATCH, user, user.capitalize(), 60, settings, account
	)


## A client with a ticket for `user` whose account holds `xp`.
func _client(user: String, xp: int, settings: Dictionary = {}, extra: Dictionary = {}) -> Night:
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	var account := {"xp": xp}
	account.merge(extra)
	link.ticket = _ticket(user, account, settings)
	var joined := await night.start_remote(_url(), Night.Mode.MANUAL, 60.0, link)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


func _room() -> NightHost:
	return _server.room_of_match(MATCH)


## The events of `type` this client has heard, kept by listening from now on.
func _hear(night: Night, type: StringName) -> Array[Dictionary]:
	var heard: Array[Dictionary] = []
	night.state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] == type:
				heard.append(event)
	)
	return heard


func test_every_client_hears_a_kills_xp_and_the_level_it_crosses() -> void:
	await _start()
	var ann := await _client("ann", 84)
	var bo := await _client("bo", 0)
	var cy := await _client("cy", 3200)
	var heard_by_bo := _hear(bo, &"xp_gained")
	var levels_heard := _hear(cy, &"level_up")
	# Ann is level 1 with 84 XP; Bo level 1; Cy joined last and reads the others' levels in its
	# WELCOME.
	assert_int(ann.state.player_id).is_equal(1)
	assert_dict(cy.state.levels).is_equal({1: 1, 2: 1, 3: LevelCurve.level_of(3200)})
	# The two who were there first learn the late joiner's level from the event that seated it.
	assert_bool(await _until(func() -> bool: return ann.state.levels.has(3))).is_true()
	assert_int(ann.state.levels[3]).is_equal(LevelCurve.level_of(3200))
	# Each client's own bar starts from its ticket.
	assert_int(ann.state.account_xp).is_equal(84)
	assert_int(cy.state.account_xp).is_equal(3200)
	# A hundred points Ann earns is a hundredth of a hundredth... one XP: level 2 for the whole room.
	_room().server.rules.apply(RulesAction.grant_points(1, 100))
	assert_bool(await _until(func() -> bool: return cy.state.levels.get(1, 1) == 2)).is_true()
	assert_int(levels_heard.size()).is_equal(1)
	assert_int(levels_heard[0]["player_id"]).is_equal(1)
	assert_int(levels_heard[0]["level"]).is_equal(2)
	# Every client heard Ann's gain, with the new total; only Ann's own bar moved.
	assert_bool(await _until(func() -> bool: return ann.state.account_xp == 85)).is_true()
	assert_bool(heard_by_bo.any(func(e: Dictionary) -> bool: return e["player_id"] == 1)).is_true()
	assert_int(bo.state.account_xp).is_equal(0)
	assert_int(cy.state.account_xp).is_equal(3200)


## A bare socket that says hello with `ticket` and has its seat; the socket is kept to send more.
func _raw_seat(ticket: String) -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.connect_to_url(_url())
	_raw.append(ws)
	var welcomed := {"yes": false, "sent": false}
	await _until(
		func() -> bool:
			ws.poll()
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not welcomed["sent"]:
				welcomed["sent"] = true
				ws.send(NetWire.hello(PackedByteArray(), ticket), WebSocketPeer.WRITE_MODE_BINARY)
			while ws.get_available_packet_count() > 0:
				if ws.get_packet()[0] == NetWire.Type.WELCOME:
					welcomed["yes"] = true
			return welcomed["yes"]
	)
	return ws


func test_a_client_cannot_change_a_tally() -> void:
	await _start()
	var ws := await _raw_seat(_ticket("ann", {"xp": 0}))
	var room := _room()
	assert_array(room.server.xp.seats()).is_equal([1])
	assert_int(room.server.xp.night_xp(1)).is_equal(0)
	# Everything a client can send that is not a plain command: the server's own messages with
	# numbers of its own making (a TICK carrying an `xp_gained`), a short one, an unknown type.
	var forged := NetWire.tick(1, [{"type": &"xp_gained", "player_id": 1, "total": 99999}])
	for packet: PackedByteArray in [
		forged,
		PackedByteArray([NetWire.Type.TICK, 0, 0, 0, 0, 0xff, 0xff]),
		PackedByteArray([200, 1, 2, 3]),
		NetWire.pong(1, 99999),
	]:
		ws.send(packet, WebSocketPeer.WRITE_MODE_BINARY)
	for _i in 30:
		ws.poll()
		await get_tree().physics_frame
	assert_int(room.server.xp.night_xp(1)).is_equal(0)
	assert_int(room.server.xp.total_of(1)).is_equal(0)
	# The server's own word is the one that counts.
	room.server.rules.apply(RulesAction.grant_points(1, 300))
	for _i in 5:
		await get_tree().physics_frame
	assert_int(room.server.xp.night_xp(1)).is_equal(3)


func test_a_ticket_with_a_forged_xp_is_refused_and_one_without_it_is_level_one() -> void:
	await _start()
	var good := _ticket("ann", {"xp": 50})
	var parts := good.split(".")
	var claims: Dictionary = JSON.parse_string(
		TicketVerifier._decode(parts[1]).get_string_from_utf8()
	)
	assert_int(int(claims["xp"])).is_equal(50)
	claims["xp"] = 17000
	var tampered := (
		"%s.%s.%s"
		% [
			parts[0],
			(
				Marshalls
				. raw_to_base64(JSON.stringify(claims).to_utf8_buffer())
				. replace("+", "-")
				. replace("/", "_")
				. trim_suffix("=")
			),
			parts[2]
		]
	)
	var verifier := TicketVerifier.new(SECRET, SERVER_ID)
	assert_bool(verifier.admit(tampered, int(Time.get_unix_time_from_system()))["ok"]).is_false()
	var plain := TicketMaker.make(SECRET, SERVER_ID, MATCH, "bo", "Bo", 60)
	var admitted := verifier.admit(plain, int(Time.get_unix_time_from_system()))
	assert_dict(admitted["account"]).is_equal({"xp": 0})


func test_a_horde_makes_no_backend_write_until_a_round_ends_and_then_one() -> void:
	await _start()
	var chosen := MatchSettings.new()
	chosen.count_multiplier = 5.0
	chosen.break_seconds = 1.0
	var settings := chosen.to_dict()
	var ann := await _client("ann", 0, settings)
	var bo := await _client("bo", 0, settings)
	var room := _room()
	var rules := room.server.rules
	var kills := 0
	var posts_in_play := 0
	rules.apply(RulesAction.skip_break())
	var began := Time.get_ticks_msec()
	# Kill every zombie the moment it stands, until round one ends (or it takes too long).
	while rules.round_number < 1 or rules.phase == GameRules.Phase.ACTIVE:
		await get_tree().physics_frame
		for zombie_id in rules.zombie_ids():
			RulesFixture.kill(rules, 1 + (kills % 2), zombie_id, RulesAction.ZONE_HEAD)
			kills += 1
		if rules.phase == GameRules.Phase.ACTIVE:
			posts_in_play = maxi(posts_in_play, _posts.size())
		if (Time.get_ticks_msec() - began) > 120000:
			break
		if rules.phase == GameRules.Phase.BREAK:
			break
	assert_int(rules.phase).is_equal(GameRules.Phase.BREAK)
	assert_int(kills).is_greater(20)
	assert_int(posts_in_play).is_equal(0)
	# Hundreds of events later, the backend has heard of the round exactly once: one report, a line
	# for each seat, keyed by the match and the round.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(await _until(func() -> bool: return _posts.size() >= 1)).is_true()
	assert_int(_posts.size()).is_equal(1)
	var body: Dictionary = _posts[0]["body"]
	assert_str(_posts[0]["path"]).is_equal("/internal/matches/%s/report" % MATCH)
	assert_str(body["kind"]).is_equal("round")
	assert_int(body["round"]).is_equal(1)
	assert_int((body["seats"] as Array).size()).is_equal(2)
	var users: Array = (body["seats"] as Array).map(
		func(seat: Dictionary) -> String: return seat["userId"]
	)
	assert_array(users).contains_exactly_in_any_order(["ann", "bo"])
	# The reports are the tallies: what the clients were told adds up to what was reported.
	var reported := 0
	for seat: Dictionary in body["seats"]:
		if seat["userId"] == "ann":
			reported = int(seat["xp"])
	assert_int(reported).is_equal(room.server.xp.night_xp(1))
	# A seat that finished the round claims the two one-offs; the backend pays them from its profile.
	var is_bo := func(seat: Dictionary) -> bool: return seat["userId"] == "bo"
	var bo_line: Dictionary = (body["seats"] as Array).filter(is_bo)[0]
	assert_bool(bo_line["openingNight"]).is_true()
	assert_int(bo_line["bonusDay"]).is_greater(20000)
	assert_int(bo_line["lines"]["round"]).is_equal(1)
	assert_int(bo.state.account_xp).is_greater(0)
	assert_int(_server.reports.taken).is_equal(1)


func test_a_night_with_no_account_at_all_earns_nothing() -> void:
	# A room whose server asks for no ticket: nobody has a user, so nobody has an account.
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving)
	var night := Night.new()
	_world().add_child(night)
	var joined := await night.start_remote(
		"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.MANUAL, 30.0
	)
	assert_bool(joined).is_true()
	_nights.append(night)
	var rules := _host.server.rules
	rules.apply(RulesAction.skip_break())
	rules.apply(RulesAction.grant_points(night.state.player_id, 5000))
	for _i in 30:
		await get_tree().physics_frame
	assert_array(_host.server.xp.seats()).is_empty()
	assert_int(night.state.xp_events).is_equal(0)
	assert_dict(night.state.levels).is_empty()
	assert_int(_host.reports_made).is_equal(0)


func test_a_guest_account_earns_like_any_other() -> void:
	await _start()
	# The backend gives a Guest a ticket like anyone's; its account id is all that tells them apart.
	var guest := await _client("guest-7f3a", 0)
	_room().server.rules.apply(RulesAction.grant_points(guest.state.player_id, 400))
	assert_bool(await _until(func() -> bool: return guest.state.account_xp == 4)).is_true()
	assert_int(guest.state.levels[guest.state.player_id]).is_equal(1)


func test_a_report_the_backend_did_not_take_is_sent_again_the_same_until_it_is() -> void:
	await _start()
	var answers: Array[int] = [503, 0, 200]
	_server.reports.retry_after = [0.2]
	_server.report_sender = func(path: String, body: Dictionary) -> int:
		_posts.append({"path": path, "body": body.duplicate(true)})
		return answers.pop_front() if not answers.is_empty() else 200
	var ann := await _client("ann", 0)
	var room := _room()
	room.server.rules.apply(RulesAction.grant_points(ann.state.player_id, 700))
	room.server.xp.observe({"type": &"round_ended", "round": 1})
	assert_bool(await _until(func() -> bool: return _server.reports.taken == 1)).is_true()
	# Three sends of one report: the same path and the same body each time.
	assert_int(_posts.size()).is_equal(3)
	assert_str(_posts[1]["path"]).is_equal(_posts[0]["path"])
	assert_dict(_posts[2]["body"]).is_equal(_posts[0]["body"])
	assert_int(_posts[0]["body"]["seats"][0]["xp"]).is_equal(7)
	assert_bool(_server.reports.is_idle()).is_true()


func test_the_night_ends_with_a_report_of_its_own_listing_every_seat() -> void:
	await _start()
	var ann := await _client("ann", 0)
	await _client("bo", 0)
	var room := _room()
	room.server.rules.apply(RulesAction.grant_points(ann.state.player_id, 250))
	room.server.xp.observe({"type": &"game_over", "reason": &"all_down", "round_reached": 4})
	assert_bool(await _until(func() -> bool: return _posts.size() == 1)).is_true()
	assert_str(_posts[0]["path"]).is_equal("/internal/matches/%s/report" % MATCH)
	assert_str(_posts[0]["body"]["kind"]).is_equal("night")
	assert_int(_posts[0]["body"]["round"]).is_equal(4)
	assert_int(_posts[0]["body"]["seats"].size()).is_equal(2)
	# Leaving afterwards reports nothing more: it was all in the night's report.
	for night in _nights:
		night.link.close()
	assert_bool(await _until(func() -> bool: return _server.match_ids().is_empty())).is_true()
	assert_int(_posts.size()).is_equal(1)


func test_everyone_leaving_in_the_middle_of_a_round_reports_what_they_had_earned() -> void:
	await _start()
	var ann := await _client("ann", 0)
	var room := _room()
	room.server.rules.apply(RulesAction.grant_points(ann.state.player_id, 900))
	for _i in 5:
		await get_tree().physics_frame
	assert_int(_posts.size()).is_equal(0)
	ann.link.close()
	assert_bool(await _until(func() -> bool: return _posts.size() == 1)).is_true()
	assert_str(_posts[0]["body"]["kind"]).is_equal("night")
	assert_int(_posts[0]["body"]["seats"][0]["xp"]).is_equal(9)
	assert_str(_posts[0]["body"]["seats"][0]["userId"]).is_equal("ann")
