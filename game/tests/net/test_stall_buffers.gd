# A client whose loop froze reads nothing for seconds, and what the server sent meanwhile must not
# be lost, and when it is lost the next frame is whole (#483). The engine's default buffers (64 KB)
# dropped the newest ticks after a few seconds, and the frame deltas that followed were against
# frames the client never had.
extends GdUnitTestSuite

## A second of a busy night is some 15 to 35 KB in 30 ticks; this is 20 s of it.
const TICKS := 1200
const PAYLOAD := 450

var _host: NightHost
var _link: WebSocketLink
var _listener: WsListener


func after_test() -> void:
	if _link != null:
		_link.close()
		_link = null
	if _listener != null:
		_listener.close()
		_listener = null
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


func test_ticks_sent_to_a_client_that_is_not_reading_are_all_there_when_it_reads() -> void:
	var ids: Array[int] = []
	_listener = WsListener.new()
	_listener.peer_connected.connect(func(id: int) -> void: ids.append(id))
	assert_int(_listener.listen(0)).is_equal(OK)
	_link = WebSocketLink.new()
	_link.connect_to("ws://127.0.0.1:%d" % _listener.port())
	var connected := await _until(
		func() -> bool:
			_listener.poll()
			_link.pump()
			return not ids.is_empty() and _link.is_open()
	)
	assert_bool(connected).is_true()
	var sent := 0
	for i in TICKS:
		# Bytes that do not pack: the ticks are as big as a night's.
		var pad := Crypto.new().generate_random_bytes(PAYLOAD)
		var frame := {"type": &"frame", "players": {}, "pad": pad}
		if _listener.send(ids[0], NetWire.tick(i, [frame])):
			sent += 1
		if i % 20 == 0:
			_listener.poll()
	assert_int(sent).is_equal(TICKS)
	# The link did not read all that time. Now it does.
	var got_all := await _until(
		func() -> bool:
			_listener.poll()
			_link.pump()
			return _link.ticks_in >= TICKS,
		20.0
	)
	(
		assert_bool(got_all)
		. override_failure_message(
			"only %d of %d ticks reached the client" % [_link.ticks_in, TICKS]
		)
		. is_true()
	)


## A listener that can be told to take nothing for a while, as a full socket would not.
class FullListener:
	extends WsListener
	var full := false

	func send(peer_id: int, data: PackedByteArray) -> bool:
		if full:
			return false
		return super.send(peer_id, data)


func test_after_ticks_the_socket_would_not_take_the_next_frame_is_whole() -> void:
	var listener := FullListener.new()
	_host = NightHost.new()
	_host.listener = listener
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	assert_bool(await _until(func() -> bool: return _host.serving, 30.0)).is_true()
	_link = WebSocketLink.new()
	var last := {"frame": {}}
	_link.delivered.connect(
		func(events: Array) -> void:
			if (
				not events.is_empty()
				and events[-1] is Dictionary
				and events[-1]["type"] == &"frame"
			):
				last["frame"] = events[-1]
	)
	_link.connect_to("ws://127.0.0.1:%d" % listener.port())
	var walk := NightCommand.new()
	var seq := [0]
	var step := func(push: Vector2) -> void:
		await get_tree().physics_frame
		_link.pump()
		if _link.is_welcomed():
			seq[0] += 1
			walk.seq = seq[0]
			walk.motion.move = push
			_link.send(walk.to_dict())
	for _i in 120:
		await step.call(Vector2.LEFT)
	assert_bool(_link.is_welcomed()).is_true()
	# The socket takes nothing for a second while the player walks the other way, then the player
	# stops: where it stopped is in a tick that was lost.
	listener.full = true
	for _i in 60:
		await step.call(Vector2.RIGHT)
	for _i in 30:
		await step.call(Vector2.ZERO)
	listener.full = false
	for _i in 120:
		await step.call(Vector2.ZERO)
	var server_at: Vector3 = _host.server.body_of(_link.player_id).global_position
	var client_at: Vector3 = last["frame"]["players"][_link.player_id]["pos"]
	(
		assert_float(client_at.distance_to(server_at))
		. override_failure_message(
			(
				"the client has the player %s m from where the server has it"
				% client_at.distance_to(server_at)
			)
		)
		. is_less(0.05)
	)
