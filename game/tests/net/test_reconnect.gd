# A client that loses its socket gets its player back: the same seat, body, points and looks, within
# a time; and a seat nobody comes back for is given up. Over a real WebSocket, with the socket cut
# on purpose.
extends GdUnitTestSuite

const STEP := Night.STEP

var _host: NightHost
var _nights: Array[Night] = []
var _raw: Array[WebSocketPeer] = []
var _commands: Dictionary = {}


func after_test() -> void:
	for ws in _raw:
		ws.close()
	_raw.clear()
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
		func() -> void:
			var command: NightCommand = _commands[night]
			command.seq += 1
			night.link.send(command.to_dict())
	)
	return night


func _position_of(night: Night, player_id: int) -> Vector3:
	return night.state.frame["players"][player_id]["pos"]


func _link(night: Night) -> WebSocketLink:
	return night.link as WebSocketLink


## A bare socket that has said hello with `token` (empty for a new player); the WELCOME it gets.
func _hello(token: PackedByteArray) -> Dictionary:
	var ws := WebSocketPeer.new()
	ws.connect_to_url(_url())
	_raw.append(ws)
	var got := {"welcome": {}, "socket": ws, "sent": false}
	await _until(
		func() -> bool:
			ws.poll()
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not got["sent"]:
				got["sent"] = true
				ws.send(NetWire.hello(token), WebSocketPeer.WRITE_MODE_BINARY)
			while ws.get_available_packet_count() > 0:
				var packet := ws.get_packet()
				if packet[0] == NetWire.Type.WELCOME:
					got["welcome"] = NetWire.read_welcome(packet)
			return not (got["welcome"] as Dictionary).is_empty()
	)
	return got


func test_a_client_that_loses_its_socket_gets_its_player_back() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	await _until(func() -> bool: return b.state.frame["players"].has(1))
	var body := _host.server.body_of(1)
	(_commands[a] as NightCommand).motion.move = Vector2(0.0, -1.0)
	await _ticks(60)
	(_commands[a] as NightCommand).motion.move = Vector2.ZERO
	await _ticks(10)
	var before := _position_of(b, 1)
	var points: int = a.state.frame["players"][1]["points"]
	var lost := {"count": 0, "resumed": 0}
	a.connection_lost.connect(func() -> void: lost["count"] += 1)
	a.connection_resumed.connect(func() -> void: lost["resumed"] += 1)
	var old_token := _link(a).token.duplicate()
	_link(a).retry_every = 0.2
	_link(a).drop()
	# The seat is held and the body stays in the lot; the other player still sees it.
	assert_bool(await _until(func() -> bool: return _host.away_count() == 1)).is_true()
	assert_bool(await _until(func() -> bool: return lost["count"] == 1)).is_true()
	assert_int(_host.player_count()).is_equal(1)
	assert_bool(is_instance_valid(_host.server.body_of(1))).is_true()
	assert_bool(b.state.frame["players"].has(1)).is_true()
	# It comes back as the same player, the same body, with a new token.
	assert_bool(await _until(func() -> bool: return lost["resumed"] == 1, 15.0)).is_true()
	assert_int(_link(a).player_id).is_equal(1)
	assert_int(a.state.player_id).is_equal(1)
	assert_bool(_host.server.body_of(1) == body).is_true()
	assert_int(_host.away_count()).is_equal(0)
	assert_int(_host.player_count()).is_equal(2)
	assert_array(_link(a).token).is_not_equal(old_token)
	# It hears the night again, whole: its frame, its own player where it was, and its points.
	assert_bool(await _until(func() -> bool: return a.state.frame["players"].has(2))).is_true()
	assert_float(_position_of(a, 1).distance_to(before)).is_less(0.5)
	assert_int(a.state.frame["players"][1]["points"]).is_equal(points)
	# And the looks of everyone again: the new connection had none.
	assert_bool(await _until(func() -> bool: return a.looks.seats.has(2))).is_true()
	# It can move again and the other player sees it.
	(_commands[a] as NightCommand).motion.move = Vector2(0.0, -1.0)
	await _ticks(60)
	assert_float(_position_of(b, 1).distance_to(before)).is_greater(1.0)


func test_a_seat_nobody_comes_back_for_is_given_up() -> void:
	await _server()
	_host.resume_within = 0.5
	var a := await _client()
	var b := await _client()
	await _until(func() -> bool: return b.state.frame["players"].has(1))
	_link(a).reconnect = false
	_link(a).drop()
	assert_bool(await _until(func() -> bool: return _host.away_count() == 1)).is_true()
	assert_bool(await _until(func() -> bool: return _host.away_count() == 0)).is_true()
	assert_bool(await _until(func() -> bool: return not b.state.frame["players"].has(1))).is_true()
	# The seat is free for someone new.
	var c := await _client()
	assert_int(c.state.player_id).is_equal(1)


func test_a_held_seat_is_not_given_to_a_newcomer() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	var c := await _client()
	var d := await _client()
	assert_int(d.state.player_id).is_equal(4)
	_link(a).reconnect = false
	_link(a).drop()
	assert_bool(await _until(func() -> bool: return _host.away_count() == 1)).is_true()
	# Four seats: one held, three used. A newcomer after b, c, d leave gets the free ones, not 1.
	_link(b).close()
	assert_bool(await _until(func() -> bool: return _host.player_count() == 2)).is_true()
	var e := await _client()
	assert_int(e.state.player_id).is_equal(2)
	assert_object(c).is_not_null()


func test_a_token_that_is_nobodys_is_a_new_player_not_a_hijack() -> void:
	await _server()
	var a := await _client()
	_link(a).reconnect = false
	_link(a).drop()
	assert_bool(await _until(func() -> bool: return _host.away_count() == 1)).is_true()
	var forged := PackedByteArray([9, 9, 9, 9, 9, 9, 9, 9])
	var stranger := await _hello(forged)
	var welcome: Dictionary = stranger["welcome"]
	assert_int(welcome["player_id"]).is_not_equal(1)
	assert_int(_host.away_count()).is_equal(1)


func test_a_client_back_before_the_server_saw_the_old_socket_die_takes_it_over() -> void:
	await _server()
	var first := await _hello(PackedByteArray())
	var welcome: Dictionary = first["welcome"]
	assert_int(welcome["player_id"]).is_equal(1)
	var second := await _hello(welcome["token"])
	var again: Dictionary = second["welcome"]
	assert_int(again["player_id"]).is_equal(1)
	assert_array(again["token"]).is_not_equal(welcome["token"])
	# The old socket is hung up on; the seat is the new one's.
	var old: WebSocketPeer = first["socket"]
	var closed := await _until(
		func() -> bool:
			old.poll()
			return old.get_ready_state() == WebSocketPeer.STATE_CLOSED
	)
	assert_bool(closed).is_true()
	assert_int(_host.player_count()).is_equal(1)
	assert_int(_host.away_count()).is_equal(0)


func test_a_used_token_does_not_work_twice() -> void:
	await _server()
	var first := await _hello(PackedByteArray())
	var welcome: Dictionary = first["welcome"]
	var second := await _hello(welcome["token"])
	assert_int((second["welcome"] as Dictionary)["player_id"]).is_equal(1)
	# The first socket's token was replaced by the take-over: it is nobody's now.
	var third := await _hello(welcome["token"])
	assert_int((third["welcome"] as Dictionary)["player_id"]).is_not_equal(1)


func test_the_night_is_not_rebuilt_while_a_seat_is_held() -> void:
	await _server()
	var a := await _client()
	_link(a).reconnect = false
	var nights_before := _host.nights
	_link(a).drop()
	assert_bool(await _until(func() -> bool: return _host.away_count() == 1)).is_true()
	await _ticks(60)
	assert_int(_host.nights).is_equal(nights_before)
	assert_bool(_host.serving).is_true()
