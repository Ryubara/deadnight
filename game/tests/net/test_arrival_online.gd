# The arrival by helicopter on a game server (#1057), over a real WebSocket in one process: a client
# that
# comes in late sees the show on its own screen and nobody else's does, the server shields it and
# keeps it out of the night while it plays and never waits for it, the others do not see its body
# until
# it has landed, and a client that never asks for a drop is never shielded.
extends GdUnitTestSuite

const MAPS: Array[String] = ["drive_in", "small_indoor"]

var _host: NightHost
var _nights: Array[Night] = []


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
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


func _server(map_id: String) -> NightHost:
	NightArrival.reset()
	var settings := MatchSettings.new()
	settings.map = map_id
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.rules_tuning = tuning
	_host.match_settings = settings
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


func _url() -> String:
	return "ws://127.0.0.1:%d" % _host.listener.port()


## A client: `human` plays a body of its own and, with `arrival`, the show; the other is
## hand-driven.
func _client(map_id: String, human := false, arrival := false) -> Night:
	var night := Night.new()
	night.map_id = map_id
	night.arrival = arrival
	_world().add_child(night)
	var joined := await night.start_remote(
		_url(), Night.Mode.HUMAN if human else Night.Mode.MANUAL, 30.0
	)
	assert_bool(joined).is_true()
	_nights.append(night)
	if human:
		night.player().local_input = false
		night.player().capture_mouse = false
	else:
		night.ticked.connect(func() -> void: night.link.send(NightCommand.new().to_dict()))
	return night


func _press(night: Night) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	night.arrival_show._input(event)


func _player(id: int) -> PlayerState:
	return _host.server.rules.players[id]


func test_a_late_join_sees_the_show_and_nobody_else_does() -> void:
	for map_id in MAPS:
		await _server(map_id)
		var first := await _client(map_id)
		_host.server.rules.apply(RulesAction.skip_break())
		await _ticks(30)
		var late := await _client(map_id, true, true)
		# It is a night already going: the shorter show, on the new client's screen only.
		assert_object(late.arrival_show).is_not_null()
		assert_bool(late.arrival_show.plan.fresh).is_false()
		assert_float(late.arrival_show.plan.seconds()).is_equal(
			late.rules_tuning.arrival.late_seconds
		)
		assert_object(first.arrival_show).is_null()
		assert_bool(first.is_arriving()).is_false()
		# The server shields the one who is dropping and nobody else.
		assert_bool(await _until(func() -> bool: return _player(2).is_dropping())).is_true()
		assert_bool(_player(1).is_shielded()).is_false()
		_host.get_parent().queue_free()
		for night in _nights:
			night.get_parent().queue_free()
		_nights.clear()
		await get_tree().process_frame


func test_the_others_do_not_see_the_body_until_it_has_landed() -> void:
	await _server("drive_in")
	var first := await _client("drive_in")
	_host.server.rules.apply(RulesAction.skip_break())
	var late := await _client("drive_in", true, true)
	assert_bool(await _until(func() -> bool: return _player(2).is_dropping())).is_true()
	assert_bool(await _until(func() -> bool: return first.state.frame["players"].has(2))).is_true()
	await _until(func() -> bool: return first.state.frame["players"][2].get("dropping", false))
	first.avatars.advance(0.5)
	assert_bool(first.state.frame["players"][2]["dropping"]).is_true()
	assert_bool(first.avatars.avatar(2).visible).is_false()
	# The marker over their head is not there either.
	assert_bool(first.state.frame["players"][2].get("dropping", false)).is_true()
	await _ticks(ceili(late.rules_tuning.arrival.skip_after * 60.0) + 10)
	_press(late)
	assert_bool(await _until(func() -> bool: return not _player(2).is_dropping(), 5.0)).is_true()
	await _ticks(12)
	first.avatars.advance(0.5)
	assert_bool(first.state.frame["players"][2]["dropping"]).is_false()
	assert_bool(first.avatars.avatar(2).visible).is_true()


func test_the_server_neither_waits_for_the_show_nor_lets_a_blow_in_during_it() -> void:
	await _server("drive_in")
	var first := await _client("drive_in")
	_host.server.rules.apply(RulesAction.skip_break())
	var late := await _client("drive_in", true, true)
	assert_bool(await _until(func() -> bool: return _player(2).is_dropping())).is_true()
	var ticks := _host.server.tick_count
	var health := _host.server.health_of(2)
	var round_before := _host.server.rules.round_number
	await _ticks(90)
	# The night went on at its own pace for everyone, the dropper's screen aside.
	assert_int(_host.server.tick_count - ticks).is_greater_equal(80)
	assert_int(first.state.frame["tick"]).is_greater(ticks)
	assert_int(_host.server.rules.round_number).is_greater_equal(round_before)
	# Nothing reached the dropper: not a blow, not a blast, not a chase.
	_host.server.rules.apply(RulesAction.blow(2, 50.0))
	_host.server._blast_player(2, 50.0, Vector3.ZERO, &"grenade", 2)
	assert_float(_host.server.health_of(2)).is_equal(health)
	assert_bool(_host.server._chase_targets().has(2)).is_false()
	assert_bool(_host.server._chase_targets().has(1)).is_true()
	assert_bool(late.is_arriving()).is_true()


func test_a_client_that_never_asks_for_a_drop_is_never_shielded() -> void:
	await _server("drive_in")
	await _client("drive_in")
	await _client("drive_in")
	await _ticks(30)
	assert_bool(_player(1).is_shielded()).is_false()
	assert_bool(_player(2).is_shielded()).is_false()
	assert_bool(_player(2).dropped).is_false()


func test_a_seat_that_has_dropped_cannot_ask_again() -> void:
	await _server("drive_in")
	await _client("drive_in")
	_host.server.rules.apply(RulesAction.skip_break())
	var late := await _client("drive_in", true, true)
	assert_bool(await _until(func() -> bool: return _player(2).is_dropping())).is_true()
	await _ticks(ceili(late.rules_tuning.arrival.skip_after * 60.0) + 10)
	_press(late)
	assert_bool(await _until(func() -> bool: return not _player(2).is_dropping(), 5.0)).is_true()
	await _ticks(ceili((late.rules_tuning.arrival.grace_seconds + 0.2) * 60.0))
	late.link.send({"type": NightServer.ARRIVAL, "player_id": 2, "begin": true})
	await _ticks(10)
	assert_bool(_player(2).is_shielded()).is_false()


func test_a_malformed_arrival_is_a_strike_not_a_shield() -> void:
	await _server("drive_in")
	var first := await _client("drive_in")
	var peer := _host.peer_of(_host._by_player[1].transport_id)
	var before := peer.limits.malformed + peer.limits.dropped
	_host.receive(peer.transport_id, PackedByteArray([NetWire.Type.ARRIVAL, 7]))
	_host.receive(peer.transport_id, PackedByteArray([NetWire.Type.ARRIVAL]))
	await _ticks(2)
	assert_bool(_player(1).is_shielded()).is_false()
	(
		assert_bool(peer.limits.malformed + peer.limits.dropped + int(peer.limits.strikes) > before)
		. is_true()
	)
	assert_object(first).is_not_null()
