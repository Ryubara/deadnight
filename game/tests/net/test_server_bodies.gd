# What a game server keeps of a player (a body with no model, no skeleton and no animation) and
# what a joined client still takes from it (the facing the server gives while it turns the body to
# repair).
extends GdUnitTestSuite

const STEP := Night.STEP

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


func _server() -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


func _client(mode: Night.Mode) -> Night:
	var night := Night.new()
	_world().add_child(night)
	var joined := await night.start_remote("ws://127.0.0.1:%d" % _host.listener.port(), mode, 30.0)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


func _nodes_under(node: Node) -> int:
	return node.find_children("*", "", true, false).size() + 1


func test_a_game_servers_players_have_no_model_and_no_animation() -> void:
	await _server()
	var ann := await _client(Night.Mode.MANUAL)
	var bo := await _client(Night.Mode.MANUAL)
	for id in [1, 2]:
		var body := _host.server.body_of(id)
		assert_bool(body.has_model).is_false()
		assert_object(body.get_node_or_null("AnimationTree")).is_null()
		assert_array(body.find_children("*", "MeshInstance3D", true, false)).is_empty()
		assert_array(body.find_children("*", "Skeleton3D", true, false)).is_empty()
		assert_object(body.get_node_or_null("CollisionShape3D")).is_not_null()
	# The drawn body of a single-process night still has its Soldier: the nodes of a body are several
	# times what a server keeps.
	var server_nodes := _nodes_under(_host.server.body_of(1))
	var drawn: Player = load("res://gameplay/player/player.tscn").instantiate()
	var drawn_nodes := _nodes_under(drawn)
	drawn.free()
	print("nodes in a player's body: ", server_nodes, " on a server, ", drawn_nodes, " drawn")
	assert_int(server_nodes).is_less(drawn_nodes / 4)
	# And the night plays the same: they see each other walk.
	(
		assert_bool(await _until(func() -> bool: return ann.state.frame.get("players", {}).has(2)))
		. is_true()
	)
	assert_object(bo).is_not_null()


func test_a_server_body_walks_the_same_as_a_drawn_one() -> void:
	# The model has no part in the simulation: the same commands from the same place end in the
	# same one.
	var world := NightWorld.new()
	add_child(world)
	await world.build()
	var bare := world.add_body(world.player_spawn(0), false, false)
	var drawn := world.add_body(world.player_spawn(0), false, true)
	for tick in 120:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, -1.0)
		command.yaw = 0.3
		command.sprint = tick > 40
		bare.tick(command)
		drawn.tick(command)
	assert_vector(bare.global_position).is_equal_approx(drawn.global_position, Vector3.ONE * 0.001)
	assert_float(bare.state.facing).is_equal_approx(drawn.state.facing, 0.001)
	world.queue_free()


func test_the_body_a_player_owns_turns_where_the_server_turns_it() -> void:
	await _server()
	var ann := await _client(Night.Mode.HUMAN)
	var server_body := _host.server.body_of(1)
	var breach: StringName = _host.world.barricade_ids()[0]
	# The server is turning player 1 toward a breach, as it does while it repairs (the client sent
	# nothing about it, and stands still).
	var before := ann.player().state.facing
	_host.server._facing_breach[1] = breach
	_host.server._face_left[1] = 2.0
	var turned := await _until(func() -> bool: return _facing_moved(ann, before))
	assert_bool(turned).is_true()
	# Not only some turn: the client's body is where the server's is.
	var together := await _until(func() -> bool: return _facing_matches(ann, server_body))
	assert_bool(together).is_true()
	var rotation_gap := absf(angle_difference(ann.player().rotation.y, server_body.state.facing))
	assert_float(rotation_gap).is_less(0.1)
	# When the server stops turning the body, the client does not hold it there.
	_host.server._face_left[1] = 0.0
	assert_bool(not _host.server._frame()["players"][1].has("turn")).is_true()


func _facing_moved(night: Night, before: float) -> bool:
	return absf(angle_difference(night.player().state.facing, before)) > 0.3


func _facing_matches(night: Night, server_body: Player) -> bool:
	return absf(angle_difference(night.player().state.facing, server_body.state.facing)) < 0.1
