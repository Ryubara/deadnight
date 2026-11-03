extends GdUnitTestSuite
## A client predicts its body against its own copy of the lot, the server moves the real body
## against the server's: any solid thing that only one of them holds is a wall one side walks
## through and the other cannot (#748: the prize crane's cabinet was solid on the client only, and a
## sprint past it drifted 2.2 m from the server). So every solid thing a player can bump into is in
## both worlds, at the same place.

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


func test_the_client_and_the_server_hold_the_same_solid_things() -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	assert_bool(await _until(func() -> bool: return _host.serving, 30.0)).is_true()
	_night = Night.new()
	_world().add_child(_night)
	var joined := await _night.start_remote(
		"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.MANUAL, 30.0
	)
	assert_bool(joined).is_true()
	# The first frames have shown the crane to the client.
	assert_bool(await _until(func() -> bool: return _night.view.crane.crane.visible)).is_true()
	for _i in 30:
		await get_tree().physics_frame
	var mask := _host.server.body_of(1).collision_mask
	var server := WorldSolids.of(_host.get_parent(), mask)
	var client := WorldSolids.of(_night.get_parent(), mask)
	assert_array(client).is_not_empty()
	assert_array(WorldSolids.differences(client, server)).is_empty()


## The other players on a client are drawings that stop nobody, so on the server they must stop
## nobody either: a body the server blocks and the client walks through ends metres apart
## (#760: a sprint into a teammate or a bot standing in the way).
func test_a_player_walks_through_another_player_as_on_the_clients_screen() -> void:
	var world := NightWorld.new()
	add_child(world)
	await world.build()
	var spawn := world.player_spawn(0)
	var walker := world.add_body(spawn, false, false)
	var standing := world.add_body(spawn + Vector3(0.0, 0.0, -1.5), false, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for tick in 90:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, -1.0)
		command.sprint = true
		walker.tick(command)
		standing.tick(PlayerCommand.new())
	var travelled := spawn.distance_to(walker.global_position)
	assert_float(travelled).is_greater(5.0)
	world.queue_free()


func test_the_layer_of_a_body_is_not_one_a_body_collides_with() -> void:
	var body: Player = load("res://gameplay/player/player.tscn").instantiate()
	assert_int(body.collision_layer).is_equal(PhysicsLayers.BODY)
	assert_int(body.collision_layer & body.collision_mask).is_equal(0)
	body.free()


func test_a_ray_still_meets_a_body_though_no_body_collides_with_one() -> void:
	var world := NightWorld.new()
	add_child(world)
	await world.build()
	var spawn := world.player_spawn(0)
	var body := world.add_body(spawn, false, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var lift := Vector3(0.0, 1.0, 0.0)
	var shot := WorldProbe.new(world.get_world_3d().direct_space_state)
	assert_float(shot.distance(spawn + lift + Vector3(1.5, 0.0, 0.0), spawn + lift)).is_greater(0.0)
	body.free()
	world.queue_free()
