# A hostile or broken client against a real game server over a real WebSocket: a flood, an
# oversized frame, silence, the wrong version, a closed door. The server keeps serving the others.
extends GdUnitTestSuite

var _host: NightHost
var _raw: Array[WebSocketPeer] = []
var _nights: Array[Night] = []


func after_test() -> void:
	for ws in _raw:
		ws.close()
	_raw.clear()
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
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


## A bare socket: the test sends it whatever bytes it likes.
func _socket() -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.outbound_buffer_size = 1 << 20
	ws.connect_to_url(_url())
	_raw.append(ws)
	var open := await _until(
		func() -> bool:
			ws.poll()
			return ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	)
	assert_bool(open).is_true()
	return ws


func _is_closed(ws: WebSocketPeer) -> bool:
	ws.poll()
	return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED


## Says hello the honest way and waits until the server has welcomed the socket.
func _join(ws: WebSocketPeer) -> void:
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


func _command(seq: int) -> PackedByteArray:
	var command := NightCommand.new()
	command.seq = seq
	return NetWire.command(command)


func _refusal_of(ws: WebSocketPeer) -> PackedByteArray:
	var found := {"packet": PackedByteArray()}
	await _until(
		func() -> bool:
			ws.poll()
			while ws.get_available_packet_count() > 0:
				var packet := ws.get_packet()
				if packet[0] == NetWire.Type.REFUSED:
					found["packet"] = packet
			return not (found["packet"] as PackedByteArray).is_empty()
	)
	return found["packet"]


func _honest_client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var joined := await night.start_remote(_url(), Night.Mode.MANUAL, 30.0)
	assert_bool(joined).is_true()
	_nights.append(night)
	night.ticked.connect(func() -> void: night.link.send(NightCommand.new().to_dict()))
	return night


func test_a_flood_of_commands_gets_the_client_hung_up_on_and_the_others_play_on() -> void:
	await _server()
	var honest := await _honest_client()
	var flooder := await _socket()
	await _join(flooder)
	for i in 3000:
		flooder.send(_command(i + 1), WebSocketPeer.WRITE_MODE_BINARY)
	assert_bool(await _until(func() -> bool: return _is_closed(flooder))).is_true()
	assert_int(_host.kicked_count).is_equal(1)
	assert_bool(await _until(func() -> bool: return _host.player_count() == 1)).is_true()
	var before: int = honest.state.frame.get("tick", 0)
	var moving := await _until(
		func() -> bool: return int(honest.state.frame.get("tick", 0)) > before + 10
	)
	assert_bool(moving).is_true()


func test_an_oversized_frame_is_never_taken() -> void:
	await _server()
	var sender := await _socket()
	await _join(sender)
	var big := PackedByteArray()
	big.resize(200_000)
	big[0] = NetWire.Type.COMMAND
	sender.send(big, WebSocketPeer.WRITE_MODE_BINARY)
	assert_bool(await _until(func() -> bool: return _is_closed(sender))).is_true()
	assert_bool(await _until(func() -> bool: return _host.player_count() == 0)).is_true()
	# The night with nobody in it is built afresh, and the server serves again.
	assert_bool(await _until(func() -> bool: return _host.serving, 30.0)).is_true()


func test_junk_before_hello_ends_in_a_hang_up() -> void:
	await _server()
	var ws := await _socket()
	for i in 40:
		ws.send(PackedByteArray([200, 1, 2, 3]), WebSocketPeer.WRITE_MODE_BINARY)
	assert_bool(await _until(func() -> bool: return _is_closed(ws))).is_true()
	assert_int(_host.kicked_count).is_equal(1)


func test_a_connection_that_never_says_hello_is_dropped() -> void:
	await _server()
	_host.hello_within = 0.5
	var ws := await _socket()
	assert_bool(await _until(func() -> bool: return _is_closed(ws), 5.0)).is_true()


func test_another_version_is_refused_with_the_servers_own() -> void:
	await _server()
	for version in [NetWire.VERSION + 1, 1, 0, 255]:
		var ws := await _socket()
		ws.send(PackedByteArray([NetWire.Type.HELLO, version]), WebSocketPeer.WRITE_MODE_BINARY)
		var refusal := await _refusal_of(ws)
		assert_int(refusal.size()).is_equal(3)
		assert_int(refusal[1]).is_equal(NetWire.Refusal.VERSION)
		assert_int(refusal[2]).is_equal(NetWire.VERSION)
	assert_int(_host.player_count()).is_equal(0)


func test_the_admit_hook_decides_who_comes_in() -> void:
	await _server()
	var asked: Array[int] = []
	_host.admit = func(_transport_id: int, version: int) -> int:
		asked.append(version)
		return NetWire.Refusal.DENIED if asked.size() == 1 else 0
	var denied := await _socket()
	denied.send(NetWire.hello(), WebSocketPeer.WRITE_MODE_BINARY)
	var refusal := await _refusal_of(denied)
	assert_int(refusal[1]).is_equal(NetWire.Refusal.DENIED)
	assert_int(_host.player_count()).is_equal(0)
	var allowed := await _socket()
	await _join(allowed)
	assert_int(_host.player_count()).is_equal(1)
	assert_array(asked).is_equal([NetWire.VERSION, NetWire.VERSION])


func test_connections_past_the_cap_are_hung_up_on() -> void:
	await _server()
	for i in NightHost.MAX_CONNECTIONS:
		await _socket()
	var extra := WebSocketPeer.new()
	extra.connect_to_url(_url())
	_raw.append(extra)
	var closed := await _until(func() -> bool: return _is_closed(extra))
	assert_bool(closed).is_true()
	assert_bool(_host.serving).is_true()
