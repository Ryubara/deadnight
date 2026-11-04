# A client whose night is over stays through the intermission, reading the server's frames (it
# counts the clock by them, #973), and leaves the server when the server closes the night: it
# closes its link, reads no more frames, and the server frees the seat. (Before #973 it left at the
# game over, #467: left open and unread, a link made a browser log "Buffer payload full".)
extends GdUnitTestSuite

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


func _client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var joined := await night.start_remote(
		"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.MANUAL, 30.0
	)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


func test_a_client_stays_through_the_intermission_then_leaves_and_reads_no_more() -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	_host.server.end_seconds = 1.0
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return a.state.frame["players"].has(2))).is_true()
	assert_int(_host.player_count()).is_equal(2)
	var overs: Array[int] = []
	a.night_over.connect(func(round_reached: int) -> void: overs.append(round_reached))
	# Everyone goes down in a round: the night ends.
	var rules := _host.server.rules
	rules.apply(RulesAction.skip_break())
	# (What `rules.apply` returns goes to the host's outbox, as an applied action's events do.)
	_host._collect(rules.apply(RulesAction.set_downed(1, true)))
	_host._collect(rules.apply(RulesAction.set_downed(2, true)))
	assert_bool(await _until(func() -> bool: return a.state.over and b.state.over)).is_true()
	assert_int(overs.size()).is_equal(1)
	# The intermission: both clients are still in the room and still read what the server says.
	var frames: int = (a.link as WebSocketLink).frames_in
	for _i in 20:
		await get_tree().physics_frame
	assert_bool(a.link.is_open()).is_true()
	assert_bool(b.link.is_open()).is_true()
	assert_int(_host.player_count()).is_equal(2)
	assert_int((a.link as WebSocketLink).frames_in).is_greater(frames)
	assert_int(a.state.over_left()).is_greater_equal(0)
	# The server closes the night: both clients close their link, and the server hears a leave.
	assert_bool(await _until(func() -> bool: return a.state.closed and b.state.closed)).is_true()
	assert_bool(await _until(func() -> bool: return not a.link.is_open())).is_true()
	assert_bool(await _until(func() -> bool: return not b.link.is_open())).is_true()
	assert_bool(await _until(func() -> bool: return _host.player_count() == 0)).is_true()
	# What the server says from now on is not read: the frame the client holds stays as it was.
	var frame_seen: Dictionary = a.state.frame
	frames = (a.link as WebSocketLink).frames_in
	for _i in 30:
		await get_tree().physics_frame
	assert_int((a.link as WebSocketLink).frames_in).is_equal(frames)
	assert_bool(a.state.frame == frame_seen).is_true()
