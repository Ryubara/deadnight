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


## What a player's body can bump into under `root`, one line each: kind, layer and place.
func _solids(root: Node, mask: int) -> Array[String]:
	var found: Array[String] = []
	for node in root.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if body is CharacterBody3D or body is Area3D or body.collision_layer & mask == 0:
			continue
		found.append(_line(body, body.collision_layer))
	for node in root.find_children("*", "CSGShape3D", true, false):
		var csg := node as CSGShape3D
		if csg.use_collision and csg.is_visible_in_tree() and csg.collision_layer & mask != 0:
			found.append(_line(csg, csg.collision_layer))
	found.sort()
	return found


func _line(node: Node3D, layer: int) -> String:
	var at := node.global_position
	return "%s layer %d at (%.2f, %.2f, %.2f)" % [node.get_class(), layer, at.x, at.y, at.z]


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
	var server := _solids(_host.get_parent(), mask)
	var client := _solids(_night.get_parent(), mask)
	assert_array(client).is_not_empty()
	assert_array(client).contains_exactly(server)
