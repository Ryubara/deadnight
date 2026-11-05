extends GdUnitTestSuite
## The game server follows each signed-in seat's challenge board (#1076): over a real WebSocket, a
## four-player night tells every client what a seat finished (with its reward) as it happens, the
## server counts the night as a client's own tracker does, a late joiner or a seat that comes back
## is not told twice, a client's own word changes nothing, and the backend is read once for a seat
## when it sits down and written once a round (never a kill), without a night ever waiting for it.

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"
const MATCH := "match-challenges"
const DAY := 20401

var _server: GameServer
var _nights: Array[Night] = []
var _raw: Array[WebSocketPeer] = []
var _posts: Array[Dictionary] = []
## The accounts whose board the backend was asked for, in order.
var _reads: Array[String] = []
## What the backend answers a read with: `{status, json}` for an account, the default for the rest.
var _boards: Dictionary = {}
var _board_answer := {"status": 404, "json": ChallengeAward.NO_BOARD}
var _host: NightHost


func before_test() -> void:
	_boards = {}
	_board_answer = {"status": 404, "json": ChallengeAward.NO_BOARD}


func after_test() -> void:
	for ws in _raw:
		ws.close()
	_raw.clear()
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_posts.clear()
	_reads.clear()
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
	_server.challenge_catalog = ChallengeFixture.quick_catalog()
	_server.challenge_clock = ChallengeFixture.clock_on(DAY)
	_server.report_sender = func(path: String, body: Dictionary) -> int:
		_posts.append({"path": path, "body": body.duplicate(true)})
		return 200
	_server.board_reader = func(user: String) -> Dictionary:
		_reads.append(user)
		return _boards.get(user, _board_answer)
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())
	return _server


func _url() -> String:
	return "ws://127.0.0.1:%d" % _server.listener.port()


func _settings() -> Dictionary:
	var chosen := MatchSettings.new()
	chosen.count_multiplier = 5.0
	chosen.break_seconds = 1.0
	return chosen.to_dict()


## A client with a ticket for `user`; `board_path` gives it a board of its own to count into.
func _client(user: String, board_path: String = "") -> Night:
	var night := Night.new()
	_world().add_child(night)
	if board_path != "":
		night.challenge_board = ChallengeBoard.open(
			board_path, ChallengeFixture.clock_on(DAY), ChallengeFixture.quick_catalog()
		)
	var link := WebSocketLink.new()
	link.ticket = TicketMaker.make(
		SECRET, SERVER_ID, MATCH, user, user.capitalize(), 60, _settings(), null, {"xp": 0}
	)
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


## Starts the round and kills every zombie as it stands, the killers in turn, until the round ends.
## Answers the kills made.
func _play_round(killers: Array[int]) -> int:
	var rules := _room().server.rules
	var kills := 0
	rules.apply(RulesAction.skip_break())
	var began := Time.get_ticks_msec()
	while rules.phase == GameRules.Phase.ACTIVE or rules.phase == GameRules.Phase.IDLE:
		await get_tree().physics_frame
		for zombie_id in rules.zombie_ids():
			RulesFixture.kill(
				rules, killers[kills % killers.size()], zombie_id, RulesAction.ZONE_HEAD
			)
			kills += 1
		if (Time.get_ticks_msec() - began) > 120000:
			break
	return kills


## The report line of one account.
func _line_of(seats: Array, user: String) -> Dictionary:
	return seats.filter(func(s: Dictionary) -> bool: return s["userId"] == user)[0]


func _ids_of(events: Array[Dictionary], player_id: int) -> Array:
	var ids: Array = []
	for event in events:
		if event["player_id"] == player_id:
			ids.append(event["id"])
	return ids


func test_a_four_player_night_tells_every_client_what_a_seat_finished() -> void:
	await _start()
	var ann := await _client("ann", ChallengeFixture.save_path("online_ann"))
	var bo := await _client("bo")
	var cy := await _client("cy")
	var di := await _client("di")
	var heard := [ann, bo, cy, di].map(
		func(n: Night) -> Array[Dictionary]: return _hear(n, &"challenge_done")
	)
	var prompts: Array[Dictionary] = []
	ann.challenges.advanced.connect(func(advance: Dictionary) -> void: prompts.append(advance))
	# Each account's board was asked for once, as it sat down, and the night did not wait for it.
	assert_array(_reads).contains_exactly_in_any_order(["ann", "bo", "cy", "di"])
	assert_bool(await _until(func() -> bool: return _room().server.challenges.follows(4))).is_true()
	assert_bool(ann.challenges.server_speaks()).is_true()
	var kills := await _play_round([1, 2])
	assert_int(kills).is_greater(4)
	assert_bool(await _until(func() -> bool: return _server.reports.taken == 1)).is_true()
	# Every client heard the same finishes, in the same order.
	var told: Array[Dictionary] = heard[0]
	assert_int(told.size()).is_greater(4)
	for other: Array[Dictionary] in heard:
		(
			assert_array(
				other.map(func(e: Dictionary) -> String: return "%d:%s" % [e["player_id"], e["id"]])
			)
			. is_equal(
				told.map(func(e: Dictionary) -> String: return "%d:%s" % [e["player_id"], e["id"]])
			)
		)
	# Everyone finished the round's challenge; only the two who killed finished the kill ones.
	for player_id in [1, 2, 3, 4]:
		assert_array(_ids_of(told, player_id)).contains([&"d_round"])
	assert_array(_ids_of(told, 1)).contains([&"d_kills", &"d_head"])
	assert_array(_ids_of(told, 3)).not_contains([&"d_kills"])
	assert_array(_ids_of(told, 4)).not_contains([&"d_head"])
	# Each is told once, with the reward and what it was.
	for player_id in [1, 2, 3, 4]:
		var ids := _ids_of(told, player_id)
		for id: Variant in ids:
			assert_int(ids.count(id)).is_equal(1)
	for event in told:
		assert_int(int(event["reward"]["xp"])).is_equal(5)
	# The reward is the seat's XP, in the same `xp_gained` the kills are in.
	assert_int(ann.state.night_xp).is_greater(5 * _ids_of(told, 1).size() - 1)
	# The client's prompt is the server's say, once for each: the local count did not make a second.
	var finished_prompts := prompts.filter(func(a: Dictionary) -> bool: return a["completed"])
	(
		assert_array(finished_prompts.map(func(a: Dictionary) -> StringName: return a["id"]))
		. contains_exactly_in_any_order(_ids_of(told, 1))
	)


func test_the_backend_is_read_once_for_a_seat_and_written_once_a_round_never_a_kill() -> void:
	await _start()
	await _client("ann")
	await _client("bo")
	var rules_kills := 0
	var anns_kills := 0
	var posts_in_play := 0
	var room := _room()
	var rules := room.server.rules
	rules.apply(RulesAction.skip_break())
	var began := Time.get_ticks_msec()
	while rules.phase != GameRules.Phase.BREAK and (Time.get_ticks_msec() - began) < 120000:
		await get_tree().physics_frame
		for zombie_id in rules.zombie_ids():
			RulesFixture.kill(rules, 1 + (rules_kills % 2), zombie_id, RulesAction.ZONE_HEAD)
			anns_kills += 1 if rules_kills % 2 == 0 else 0
			rules_kills += 1
		if rules.phase == GameRules.Phase.ACTIVE:
			posts_in_play = maxi(posts_in_play, _posts.size())
	assert_int(rules_kills).is_greater(8)
	assert_int(posts_in_play).is_equal(0)
	assert_bool(await _until(func() -> bool: return _posts.size() >= 1)).is_true()
	await get_tree().physics_frame
	assert_int(_posts.size()).is_equal(1)
	assert_array(_reads).contains_exactly_in_any_order(["ann", "bo"])
	var body: Dictionary = _posts[0]["body"]
	assert_str(body["kind"]).is_equal("round")
	assert_int((body["seats"] as Array).size()).is_equal(2)
	for seat: Dictionary in body["seats"]:
		# The board as the tracker holds it, in the backend's envelope, dealt for the day.
		assert_int(seat["board"]["schemaVersion"]).is_equal(ChallengeSave.SCHEMA_VERSION)
		assert_int(seat["board"]["data"]["dealt_day"]).is_equal(DAY)
		assert_array(seat["done"]).contains(["d_round"])
		# What the backend takes of it reads back as the same board.
		var back := ChallengeSave.from_envelope(seat["board"])
		assert_object(back["profile"]).is_not_null()
	var ann_line: Dictionary = _line_of(body["seats"], "ann")
	assert_int(int(ann_line["board"]["data"]["lifetime"]["kills"])).is_equal(anns_kills)
	assert_array(ann_line["done"]).contains(["d_kills", "d_head"])


func test_a_seat_that_comes_back_is_not_told_or_read_again_and_a_late_joiner_is_not_told_the_past(
) -> void:
	await _start()
	var ann := await _client("ann")
	await _client("bo")
	var heard_by_ann := _hear(ann, &"challenge_done")
	await _play_round([1, 2])
	assert_bool(await _until(func() -> bool: return _server.reports.taken == 1)).is_true()
	var before := heard_by_ann.size()
	assert_int(before).is_greater(0)
	# A late joiner reads none of what was finished before it came.
	var cy := await _client("cy")
	var heard_by_cy := _hear(cy, &"challenge_done")
	# Ann's socket drops and she comes back on a new ticket: the same seat, the same board.
	var seat: int = ann.state.player_id
	ann.link.close()
	var again := await _client("ann")
	var heard_again := _hear(again, &"challenge_done")
	assert_int(again.state.player_id).is_equal(seat)
	assert_array(_reads.filter(func(u: String) -> bool: return u == "ann")).has_size(1)
	assert_array(_reads.filter(func(u: String) -> bool: return u == "cy")).has_size(1)
	# Round two: nobody is told a finish they already had, nor paid for it again.
	var paid_before := _room().server.xp.night_xp(seat)
	await _play_round([seat])
	assert_bool(await _until(func() -> bool: return _server.reports.taken == 2)).is_true()
	var repeated := heard_again.filter(
		func(e: Dictionary) -> bool:
			return (
				e["player_id"] == seat
				and e["id"] in [&"d_kills", &"d_head", &"d_round", &"m_kills"]
			)
	)
	assert_array(repeated).is_empty()
	(
		assert_array(
			heard_by_cy.filter(
				func(e: Dictionary) -> bool: return e["player_id"] == seat and e["id"] == &"d_kills"
			)
		)
		. is_empty()
	)
	assert_int(_room().server.xp.night_xp(seat)).is_greater(paid_before - 1)


func test_a_client_cannot_finish_a_challenge_by_saying_so() -> void:
	await _start()
	var bo := await _client("bo")
	var heard_by_bo := _hear(bo, &"challenge_done")
	var ticket := TicketMaker.make(
		SECRET, SERVER_ID, MATCH, "ann", "Ann", 60, _settings(), null, {"xp": 0}
	)
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
	var room := _room()
	assert_bool(await _until(func() -> bool: return room.server.challenges.follows(2))).is_true()
	var paid := room.server.xp.night_xp(2)
	var forged := (
		NetWire
		. tick(
			1,
			[
				{
					"type": &"challenge_done",
					"player_id": 2,
					"id": &"d_kills",
					"reward": {"xp": 9999}
				},
				{
					"type": &"challenge_progress",
					"player_id": 2,
					"id": &"d_kills",
					"completed": true
				},
			]
		)
	)
	for packet: PackedByteArray in [
		forged, PackedByteArray([NetWire.Type.TICK, 0, 0, 0, 0, 0xff, 0xff])
	]:
		ws.send(packet, WebSocketPeer.WRITE_MODE_BINARY)
	for _i in 30:
		ws.poll()
		await get_tree().physics_frame
	assert_int(room.server.xp.night_xp(2)).is_equal(paid)
	assert_array(heard_by_bo).is_empty()
	assert_int(room.server.challenges.profile_of("ann").lifetime.size()).is_equal(0)


func test_a_night_does_not_wait_for_a_board_and_a_seat_without_one_is_never_written() -> void:
	await _start()
	# The backend takes seconds to answer one board and does not answer the other at all.
	_server.board_reader = func(user: String) -> Dictionary:
		_reads.append(user)
		if user == "ann":
			await get_tree().create_timer(3.0).timeout
			return {"status": 404, "json": ChallengeAward.NO_BOARD}
		return {"status": 0, "json": null}
	var ann := await _client("ann")
	var bo := await _client("bo")
	# Both are in the night; ann's board has not come, bo's never will.
	var room := _room()
	assert_bool(room.server.challenges.follows(1)).is_false()
	assert_bool(await _until(func() -> bool: return room.server.challenges.follows(1))).is_true()
	assert_bool(room.server.challenges.follows(2)).is_false()
	var heard := _hear(bo, &"challenge_done")
	await _play_round([1, 2])
	assert_bool(await _until(func() -> bool: return _server.reports.taken == 1)).is_true()
	# Ann's challenges are followed from when her board came; bo's night carries on, paid for what he
	# killed, and the report leaves his board as the backend has it.
	assert_array(_ids_of(heard, 1)).contains([&"d_round"])
	assert_array(_ids_of(heard, 2)).is_empty()
	assert_int(bo.state.night_xp).is_greater(0)
	var seats: Array = _posts[0]["body"]["seats"]
	var ann_line: Dictionary = _line_of(seats, "ann")
	var bo_line: Dictionary = _line_of(seats, "bo")
	assert_bool(ann_line.has("board")).is_true()
	assert_bool(bo_line.has("board")).is_false()
	assert_bool(bo_line.has("done")).is_false()
	assert_int(bo_line["xp"]).is_greater(0)
	assert_int(ann.state.night_xp).is_greater(0)


func test_a_board_the_backend_holds_is_followed_from_where_it_was() -> void:
	await _start()
	var held := ChallengeProfile.fresh()
	held.refresh(ChallengeFixture.quick_catalog(), DAY)
	held.apply(ChallengeFixture.quick_catalog(), ChallengeStats.KILLS, 3, 3)
	_boards["ann"] = {"status": 200, "json": JSON.parse_string(ChallengeSave.to_json(held))}
	await _client("ann")
	var room := _room()
	assert_bool(await _until(func() -> bool: return room.server.challenges.follows(1))).is_true()
	# Three kills held: the fourth finishes the daily.
	var ann_heard := _hear(_nights[0], &"challenge_done")
	room.server.rules.apply(RulesAction.skip_break())
	(
		assert_bool(
			await _until(func() -> bool: return not room.server.rules.zombie_ids().is_empty())
		)
		. is_true()
	)
	RulesFixture.kill(
		room.server.rules, 1, room.server.rules.zombie_ids()[0], RulesAction.ZONE_HEAD
	)
	(
		assert_bool(await _until(func() -> bool: return _ids_of(ann_heard, 1).has(&"d_kills")))
		. is_true()
	)
	# The ladder's steps were climbed before: they are not said again.
	assert_array(_ids_of(ann_heard, 1)).not_contains([&"m_kills", &"d_head"])
