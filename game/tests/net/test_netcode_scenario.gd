# The scenario of #56: a game server and two bots (the autopilot, each driving its own predicted
# body from its own shoulder camera) over a real WebSocket on a bad network (100 ms each way with
# 20 ms jitter and stalls), for twenty seconds of play. They must stay close to the server while
# they play, never be snapped far, and come back together with it when they stop. An engine error
# anywhere in it fails the CI job (it reads the log), like any other test.
extends GdUnitTestSuite

const PLAY_SECONDS := 20.0
## How far a predicted body may be from the server's while a bot sprints on a 200 ms round trip:
## the length of a sprint in that time, and some room.
const MOST_AHEAD := 2.5
const SETTLED := 0.12

var _host: NightHost
var _nights: Array[Night] = []


func after_test() -> void:
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


func _bot(seed_value: int) -> Night:
	var link := WebSocketLink.new()
	link.conditioner_in = LinkConditioner.new(0.1, 0.02, seed_value)
	link.conditioner_out = LinkConditioner.new(0.1, 0.02, seed_value + 100)
	link.conditioner_in.stall_chance = 0.01
	link.conditioner_out.stall_chance = 0.01
	var night := Night.new()
	night.shoulder_camera = true
	_world().add_child(night)
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	var joined := await night.start_remote(url, Night.Mode.AUTOPILOT, 40.0, link)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


func _distance_to_server(night: Night) -> float:
	var id := night.state.player_id
	return night.player().state.position.distance_to(_host.server.body_of(id).global_position)


func test_two_bots_on_a_bad_network_stay_with_the_server_and_settle_when_they_stop() -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	var one := await _bot(11)
	var two := await _bot(22)
	var worst := 0.0
	var began := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - began) / 1000.0 < PLAY_SECONDS:
		await get_tree().physics_frame
		worst = maxf(worst, maxf(_distance_to_server(one), _distance_to_server(two)))
	var moved: Vector3 = _host.server.body_of(1).global_position
	print(
		"scenario: worst gap to the server ",
		snappedf(worst, 0.01),
		" m; corrections ",
		one.reconciler.corrections,
		"/",
		two.reconciler.corrections,
		"; worst error ",
		snappedf(maxf(one.reconciler.worst_error, two.reconciler.worst_error), 0.01),
		" m; round trip ",
		snappedf(one.link.rtt_ms, 1.0),
		" ms; held back ",
		(one.link as WebSocketLink).conditioner_in.stalled
	)
	# They played (the night ran, they walked), the network was as bad as asked, and the predicted
	# bodies were never far from the server's, nor snapped far.
	assert_float(moved.distance_to(_host.server.world.player_spawn(0))).is_greater(1.0)
	assert_float(one.link.rtt_ms).is_greater(150.0)
	assert_float(worst).is_less(MOST_AHEAD)
	assert_float(one.reconciler.worst_error).is_less(MOST_AHEAD)
	assert_float(two.reconciler.worst_error).is_less(MOST_AHEAD)
	# They stop sending (the sender of a command is the autopilot of the mode): a MANUAL client sends
	# nothing, the server's bodies stand still and each client's body comes to where the server's is.
	one.mode = Night.Mode.MANUAL
	two.mode = Night.Mode.MANUAL
	var settled := await _until(
		func() -> bool:
			return _distance_to_server(one) < SETTLED and _distance_to_server(two) < SETTLED,
		8.0
	)
	assert_bool(settled).is_true()
