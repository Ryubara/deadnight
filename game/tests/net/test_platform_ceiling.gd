# The crowd a match stands depends on the weakest client in it (issue #453): a browser holds the
# web budget, a desktop client the desktop's, and the server follows who is in the room.
extends GdUnitTestSuite

var _host: NightHost
var _raw: Array[WebSocketPeer] = []


func after_test() -> void:
	for ws in _raw:
		ws.close()
	_raw.clear()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()


func _until(condition: Callable, seconds: float = 10.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _server(max_alive := 0) -> NightHost:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.max_alive = max_alive
	viewport.add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


## A socket that has said hello and been welcomed, without a word about what it is.
func _joined() -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % _host.listener.port())
	_raw.append(ws)
	await _until(
		func() -> bool:
			ws.poll()
			return ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	)
	ws.send(NetWire.hello(), WebSocketPeer.WRITE_MODE_BINARY)
	var welcomed := await _until(
		func() -> bool:
			ws.poll()
			while ws.get_available_packet_count() > 0:
				if ws.get_packet()[0] == NetWire.Type.WELCOME:
					return true
			return false
	)
	assert_bool(welcomed).is_true()
	return ws


func test_the_platform_message_round_trips_and_is_taken_by_the_limits() -> void:
	assert_int(NetWire.read_platform(NetWire.platform(true))).is_equal(1)
	assert_int(NetWire.read_platform(NetWire.platform(false))).is_equal(0)
	assert_int(NetWire.read_platform(PackedByteArray([NetWire.Type.PLATFORM, 2]))).is_equal(-1)
	assert_int(NetWire.read_platform(PackedByteArray([NetWire.Type.PLATFORM]))).is_equal(-1)
	assert_bool(PeerLimits.fits(NetWire.Type.PLATFORM, NetWire.PLATFORM_SIZE)).is_true()
	assert_bool(PeerLimits.fits(NetWire.Type.PLATFORM, 3)).is_false()
	assert_int(NetWire.VERSION).is_equal(5)


func test_the_desktops_crowd_and_the_browsers_are_two_numbers_the_tuning_names() -> void:
	var rounds := RoundTuning.new()
	assert_int(rounds.ceiling_for(true)).is_equal(40)
	assert_int(rounds.ceiling_for(false)).is_greater_equal(100)
	# The web number is the crowd the web build was measured at (docs/research/crowd-budget.md).
	assert_int(rounds.web_alive_cap_ceiling).is_equal(ZombieTuning.new().hard_cap)
	# A ceiling for the browser never exceeds the desktop's, whatever the tuning says.
	rounds.alive_cap_ceiling = 30
	assert_int(rounds.ceiling_for(true)).is_equal(30)


func test_a_client_that_says_nothing_is_taken_for_a_browser() -> void:
	await _server()
	await _joined()
	assert_bool(await _until(func() -> bool: return _host.player_count() == 1)).is_true()
	assert_int(_host.server.crowd_ceiling()).is_equal(RoundTuning.new().web_alive_cap_ceiling)
	assert_int(_host.server.sim.tuning.hard_cap).is_equal(_host.server.crowd_ceiling())


func test_a_desktop_client_lifts_the_crowd_and_a_browser_in_the_room_takes_it_back() -> void:
	await _server()
	var desktop := await _joined()
	desktop.send(NetWire.platform(false), WebSocketPeer.WRITE_MODE_BINARY)
	var native := RoundTuning.new().alive_cap_ceiling
	var web := RoundTuning.new().web_alive_cap_ceiling
	(
		assert_bool(await _until(func() -> bool: return _host.server.crowd_ceiling() == native))
		. is_true()
	)
	assert_int(_host.server.sim.tuning.hard_cap).is_equal(native)
	assert_int(_host.server.rules.crowd_ceiling).is_equal(native)
	# A second client that has not said what it is: the room goes down to the browser's number.
	var other := await _joined()
	assert_bool(await _until(func() -> bool: return _host.server.crowd_ceiling() == web)).is_true()
	assert_int(_host.server.sim.tuning.hard_cap).is_equal(web)
	# It says it is a desktop too, and the room is up again.
	other.send(NetWire.platform(false), WebSocketPeer.WRITE_MODE_BINARY)
	(
		assert_bool(await _until(func() -> bool: return _host.server.crowd_ceiling() == native))
		. is_true()
	)
	# It leaves as a browser would have been: say so, then go.
	other.send(NetWire.platform(true), WebSocketPeer.WRITE_MODE_BINARY)
	assert_bool(await _until(func() -> bool: return _host.server.crowd_ceiling() == web)).is_true()
	other.close()
	(
		assert_bool(
			await _until(func() -> bool: return _host.server.crowd_ceiling() == native, 15.0)
		)
		. is_true()
	)


func test_the_match_stands_the_crowd_of_its_ceiling_and_no_more() -> void:
	await _server()
	var desktop := await _joined()
	desktop.send(NetWire.platform(false), WebSocketPeer.WRITE_MODE_BINARY)
	var native := RoundTuning.new().alive_cap_ceiling
	(
		assert_bool(await _until(func() -> bool: return _host.server.crowd_ceiling() == native))
		. is_true()
	)
	var settings := MatchSettings.new()
	settings.max_alive = 999
	assert_int(settings.clamped().max_alive).is_less_equal(native)
	var rounds := _host.server.rules.tuning.rounds
	assert_int(settings.alive_cap(rounds, 1, 1, _host.server.crowd_ceiling())).is_equal(native)
	assert_int(settings.alive_cap(rounds, 1, 1, rounds.web_alive_cap_ceiling)).is_equal(
		rounds.web_alive_cap_ceiling
	)


func test_an_operators_cap_holds_whatever_the_players_are_on() -> void:
	await _server(30)
	var desktop := await _joined()
	desktop.send(NetWire.platform(false), WebSocketPeer.WRITE_MODE_BINARY)
	# The desktop's number is above the cap, so the cap is the crowd; nothing the clients say lifts it.
	assert_bool(await _until(func() -> bool: return _host.player_count() == 1)).is_true()
	await get_tree().create_timer(0.3).timeout
	assert_int(_host.server.crowd_ceiling()).is_equal(30)
	assert_int(_host.server.sim.tuning.hard_cap).is_equal(30)
	# A cap above the ceiling of the match changes nothing.
	_host.server.crowd_limit = 500
	assert_int(_host.server.crowd_ceiling()).is_equal(RoundTuning.new().alive_cap_ceiling)
