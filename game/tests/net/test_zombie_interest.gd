# A joined client gets the zombies as deltas, and only the ones near its player when the host has an
# interest radius: over a real WebSocket, against the server's own list.
extends GdUnitTestSuite

var _host: NightHost
var _night: Night


func after_test() -> void:
	if is_instance_valid(_night):
		_night.get_parent().queue_free()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _start(radius: float) -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.interest_radius = radius
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	_night = Night.new()
	_world().add_child(_night)
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	assert_bool(await _night.start_remote(url, Night.Mode.MANUAL, 30.0)).is_true()
	# Begin the night's first round and let the dead come.
	_host.server.rules.apply(RulesAction.skip_break())
	var crowd := await _until(func() -> bool: return _host.server.sim.zombies.size() >= 3, 60.0)
	assert_bool(crowd).is_true()


func test_every_zombie_the_server_has_reaches_the_client_by_deltas() -> void:
	await _start(0.0)
	await _until(
		func() -> bool: return _night.state.zombies.size() == _host.server.sim.zombies.size()
	)
	var ids: Array = []
	for entry in _night.state.zombies:
		ids.append(entry["id"])
	ids.sort()
	var server_ids: Array = _host.server.sim.zombies.keys()
	server_ids.sort()
	assert_array(ids).is_equal(server_ids)


func test_a_client_is_told_only_of_the_zombies_within_the_interest_radius() -> void:
	await _start(6.0)
	var body := _host.server.body_of(1)
	# Wait until the server has dead further than the radius from the player.
	var spread := await _until(
		func() -> bool:
			for zombie: ZombieBody in _host.server.sim.zombies.values():
				if _flat(zombie.position, body.global_position) > 12.0:
					return true
			return false,
		60.0
	)
	assert_bool(spread).is_true()
	await _until(func() -> bool: return _night.state.has_frame())
	for _i in 30:
		await get_tree().physics_frame
	assert_int(_night.state.zombies.size()).is_less(_host.server.sim.zombies.size())
	for entry in _night.state.zombies:
		var at: Vector3 = entry["position"]
		# The radius, as the server measured it a step or two before, and a step of walking.
		assert_float(_flat(at, body.global_position)).is_less(6.0 + 2.0)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
