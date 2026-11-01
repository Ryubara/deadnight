# A night on a game server, over a real WebSocket on this machine, in one process: the server and
# its clients each live in their own SubViewport world (their own physics and navigation), the
# clients are `Night`s that joined with `start_remote`. Both players see each other move, shots and
# zombies agree, and a player who joins or leaves in the middle of the night is handled.
extends GdUnitTestSuite

const STEP := Night.STEP

var _host: NightHost
var _nights: Array[Night] = []
var _commands: Dictionary = {}


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_commands.clear()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


## Waits for `condition` up to `seconds`, a physics frame at a time; true if it came.
func _until(condition: Callable, seconds: float = 10.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _server() -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


func _url() -> String:
	return "ws://127.0.0.1:%d" % _host.listener.port()


## A hand-driven client (MANUAL): it sends whatever `_commands` holds for it, every tick.
func _client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var joined := await night.start_remote(_url(), Night.Mode.MANUAL, 30.0)
	assert_bool(joined).is_true()
	_nights.append(night)
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void: night.link.send((_commands[night] as NightCommand).to_dict())
	)
	night.link.send_look(CharacterLook.from_preset(night.state.player_id + 3))
	return night


func _position_of(night: Night, player_id: int) -> Vector3:
	return night.state.frame["players"][player_id]["pos"]


func test_two_clients_join_one_night_and_see_each_other_move() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_int(a.state.player_id).is_equal(1)
	assert_int(b.state.player_id).is_equal(2)
	assert_bool(await _until(func() -> bool: return b.state.frame["players"].has(1))).is_true()
	assert_bool(await _until(func() -> bool: return a.state.frame["players"].has(2))).is_true()
	# They were not put in the same spot.
	assert_float(_position_of(a, 1).distance_to(_position_of(a, 2))).is_greater(0.5)
	var start := _position_of(b, 1)
	(_commands[a] as NightCommand).motion.move = Vector2(0.0, -1.0)
	await _ticks(90)
	# B hears that A walked, and what it hears is what the server has.
	var seen_by_b := _position_of(b, 1)
	assert_float(seen_by_b.distance_to(start)).is_greater(2.0)
	assert_float(seen_by_b.distance_to(_host.server.body_of(1).global_position)).is_less(1.0)
	assert_float(_position_of(a, 1).distance_to(seen_by_b)).is_less(1.0)
	# And draws them there (an avatar for the other player, none for the one that has no body of
	# its own to hide: in MANUAL both are avatars).
	b.avatars.advance(0.5)
	assert_object(b.avatars.avatar(1)).is_not_null()
	assert_float(b.avatars.avatar(1).position.distance_to(seen_by_b)).is_less(1.5)
	assert_bool(b.avatars.ids().has(2)).is_true()


func test_a_clients_look_reaches_the_other_client() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	(
		assert_bool(
			await _until(
				func() -> bool: return b.link.looks.looks.has(1) and a.link.looks.looks.has(2)
			)
		)
		. is_true()
	)
	var sent := CharacterLook.from_preset(a.state.player_id + 3)
	(
		assert_bool(
			await _until(
				func() -> bool: return (b.link.looks.looks[1] as CharacterLook).equals(sent)
			)
		)
		. is_true()
	)
	assert_int(b.link.looks.seats[1]).is_equal(0)
	assert_int(b.link.looks.seats[2]).is_equal(1)


func test_shots_and_zombies_agree_on_both_clients() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	var rules := _host.server.rules
	rules.apply(RulesAction.skip_break())
	(
		assert_bool(await _until(func() -> bool: return _host.server.sim.zombies.size() > 0, 30.0))
		. is_true()
	)
	var zombie_id: int = _host.server.sim.zombies.keys()[0]
	# The same dead on the lot as the server has, on each client.
	var same := func(night: Night) -> bool:
		var ids: Array = []
		for entry in night.state.zombies:
			ids.append(entry["id"])
		var server_ids: Array = _host.server.sim.zombies.keys()
		ids.sort()
		server_ids.sort()
		return ids == server_ids
	assert_bool(await _until(func() -> bool: return same.call(a) and same.call(b), 10.0)).is_true()
	# A shoots one: hold it in front of A and pull the trigger.
	var heard_a: Array[Dictionary] = []
	var heard_b: Array[Dictionary] = []
	a.state.event_received.connect(func(e: Dictionary) -> void: heard_a.append(e))
	b.state.event_received.connect(func(e: Dictionary) -> void: heard_b.append(e))
	var body: ZombieBody = _host.server.sim.zombies[zombie_id]
	var spot := _host.server.body_of(1).global_position + Vector3(0.0, 0.0, -6.0)
	var shoot := NightFixture.shoot_at(a, spot)
	_commands[a] = shoot
	for _i in 12:
		body.position = spot
		body.velocity = Vector3.ZERO
		await _ticks(1)
	await _ticks(20)
	for heard in [heard_a, heard_b]:
		var shots: Array = heard.filter(
			func(e: Dictionary) -> bool: return e["type"] == &"shot_fired"
		)
		var hits: Array = heard.filter(
			func(e: Dictionary) -> bool: return e["type"] == &"damage_dealt"
		)
		assert_bool(shots.size() > 0).is_true()
		assert_bool(hits.size() > 0).is_true()
		assert_int(shots[0]["shooter_id"]).is_equal(1)
	# Both heard the same shots, and A was paid for them: the points in the frame are the server's.
	var count := func(heard: Array[Dictionary]) -> int:
		return heard.filter(func(e: Dictionary) -> bool: return e["type"] == &"shot_fired").size()
	assert_int(count.call(heard_a)).is_equal(count.call(heard_b))
	assert_int(a.state.points()).is_equal(rules.points_of(1))
	assert_int(b.state.frame["players"][1]["points"]).is_equal(rules.points_of(1))
	assert_int(rules.points_of(1)).is_greater(200)


func test_a_player_who_joins_in_the_middle_gets_the_night_as_it_is() -> void:
	await _server()
	var a := await _client()
	var rules := _host.server.rules
	rules.apply(RulesAction.skip_break())
	rules.apply(RulesAction.grant_points(1, 1000))
	_host.server.buy(1, &"door_concession")
	await _ticks(30)
	var late := await _client()
	# The door is open on the newcomer's lot, the round is the server's, and A is there to see.
	assert_bool(late.world.doors.closed_doors().has(&"door_concession")).is_false()
	assert_bool(late.world.doors.closed_doors().has(&"door_yard")).is_true()
	assert_int(late.state.round_number()).is_equal(rules.round_number)
	assert_bool(await _until(func() -> bool: return late.state.frame["players"].has(1))).is_true()
	assert_bool(await _until(func() -> bool: return a.state.frame["players"].has(2))).is_true()
	assert_int(late.state.points()).is_equal(rules.points_of(2))


func test_a_player_who_leaves_disappears_for_the_others_and_the_seat_is_reused() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return a.state.frame["players"].has(2))).is_true()
	assert_int(_host.player_count()).is_equal(2)
	b.link.close()
	assert_bool(await _until(func() -> bool: return _host.player_count() == 1)).is_true()
	assert_bool(await _until(func() -> bool: return not a.state.frame["players"].has(2))).is_true()
	assert_object(_host.server.body_of(2)).is_null()
	await _ticks(10)
	assert_bool(a.avatars.ids().has(2)).is_false()
	# The night goes on for A, and the next to come takes the free seat.
	var c := await _client()
	assert_int(c.state.player_id).is_equal(2)


## Reads the sockets of links nobody else drives.
func _pump(links: Array[WebSocketLink]) -> void:
	for link in links:
		link.pump()


func test_a_fifth_player_is_turned_away() -> void:
	await _server()
	var links: Array[WebSocketLink] = []
	for _i in 4:
		var link := WebSocketLink.new()
		link.connect_to(_url())
		links.append(link)
	var four := false
	for _i in 600:
		_pump(links)
		if _host.player_count() == 4:
			four = true
			break
		await get_tree().physics_frame
	assert_bool(four).is_true()
	var fifth := WebSocketLink.new()
	var why := {"reason": -1}
	fifth.refused.connect(func(reason: int) -> void: why["reason"] = reason)
	fifth.connect_to(_url())
	for _i in 600:
		_pump(links)
		fifth.pump()
		if why["reason"] != -1:
			break
		await get_tree().physics_frame
	assert_int(why["reason"]).is_equal(NetWire.Refusal.FULL)
	assert_int(_host.player_count()).is_equal(4)
	for link in links:
		link.close()


func test_a_server_nobody_is_on_says_so() -> void:
	var night := Night.new()
	_world().add_child(night)
	var why := {"text": ""}
	night.connect_failed.connect(func(text: String) -> void: why["text"] = text)
	# Port 1 has nothing listening.
	var joined := await night.start_remote("ws://127.0.0.1:1", Night.Mode.MANUAL, 5.0)
	assert_bool(joined).is_false()
	assert_str(why["text"]).is_not_empty()
	night.get_parent().queue_free()


func test_the_numbers_of_a_run_are_small() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	var rules := _host.server.rules
	rules.apply(RulesAction.skip_break())
	(_commands[a] as NightCommand).motion.move = Vector2(0.0, -1.0)
	await _until(func() -> bool: return _host.server.sim.zombies.size() >= 3, 60.0)
	var before: int = a.link.bytes_in
	var frames: int = a.link.frames_in
	await _ticks(180)
	var per_frame := float(a.link.bytes_in - before) / maxf(a.link.frames_in - frames, 1)
	print(
		(
			"online numbers: %.0f B per tick to a client, round trip %.0f ms, %d zombies"
			% [per_frame, a.link.rtt_ms, _host.server.sim.zombies.size()]
		)
	)
	# One tick to a client is a few hundred bytes: well under a kilobyte at this size.
	assert_float(per_frame).is_less(1500.0)
	assert_float(a.link.rtt_ms).is_less(500.0)
