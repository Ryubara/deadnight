# What another client sees of a player's perk drink (#912), over a real WebSocket on this machine:
# A presses `use` at a perk machine; B must show A's body drinking (the clip, the bottle in the
# perk's colour) and A's gun back at the end, and a client that joins mid-drink is not left with a
# stuck bottle. Built like `test_remote_weapons.gd`.
extends GdUnitTestSuite

const A := 1
const B := 2
const PERK := &"tonic_double_shot"

var _host: NightHost
var _nights: Array[Night] = []
var _commands: Dictionary = {}


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_commands.clear()
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


## Waits for `condition` up to `seconds` of the game's own time: physics frames at 60 a second,
## never the wall clock (a loaded machine ran at 3 frames a second once, and a wait in wall
## seconds then failed a drink that was on time in frames).
func _until(condition: Callable, seconds: float = 10.0) -> bool:
	for _i in ceili(seconds * 60.0):
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func _server() -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


func _client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	assert_bool(await night.start_remote(url, Night.Mode.MANUAL, 30.0)).is_true()
	_nights.append(night)
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void: night.link.send((_commands[night] as NightCommand).to_dict())
	)
	return night


func _pose(night: Night, id: int) -> PlayerAnimation:
	var body := night.avatars.avatar(id)
	return body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body != null else null


func _drinking(night: Night, id: int) -> bool:
	var pose := _pose(night, id)
	return pose != null and pose.is_drinking()


func _machine() -> Vector3:
	for spot in _host.world.shop_spots():
		if spot["shop_id"] == PERK:
			return spot["position"]
	return Vector3.INF


## A walks up to the machine (its server body is put there) and presses `use` once.
func _buy(a: Night) -> void:
	_host.server.rules.apply(RulesAction.grant_points(A, 30000))
	_host.server.body_of(A).teleport(_machine() + Vector3(0.0, 0.1, 0.0))
	for _i in 10:
		await get_tree().physics_frame
	var command := _commands[a] as NightCommand
	for _try in 20:
		command.use = true
		await a.ticked
		command.use = false
		await get_tree().physics_frame
		if _host.server.is_drinking(A):
			return


func test_b_shows_a_drinking_the_perk_with_its_bottle_and_the_gun_back_after() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	await _buy(a)
	assert_bool(_host.server.is_drinking(A)).override_failure_message("A never bought").is_true()
	(
		assert_bool(await _until(func() -> bool: return _drinking(b, A)))
		. override_failure_message("B does not show A drinking")
		. is_true()
	)
	assert_bool(_drinking(b, B)).is_false()
	var pose := _pose(b, A)
	assert_bool(await _until(func() -> bool: return pose.bottle().visible, 3.0)).is_true()
	assert_object(pose.bottle().drink_colour()).is_equal(PerkBottle.colours_of(PERK)["drink"])
	assert_bool(pose.weapon() == null or not pose.weapon().visible).is_true()
	# A's own screen shows it too, on A's own body.
	var own := (a.view.bodies.call(A) as Node3D).get_node("AnimationTree") as PlayerAnimation
	assert_bool(await _until(func() -> bool: return own.is_drinking(), 3.0)).is_true()
	assert_bool(await _until(func() -> bool: return not _drinking(b, A), 6.0)).is_true()
	assert_bool(pose.bottle().visible).is_false()
	assert_bool(pose.weapon() == null or pose.weapon().visible).is_true()
	# The server's drink is on its own ticks; the perk is had at its end.
	var had := func() -> bool: return _host.server.rules.players[A].tonics.has(PERK)
	assert_bool(await _until(had, 3.0)).is_true()
