# The re-cut bench online (#909): a client at the bench is offered a re-cut at 5000 for the first,
# the second and the third weapon, pays it on the server, and is told on the next press that a
# weapon is re-cut once and is charged nothing. Over a real WebSocket on this machine; the server
# and the client live in their own SubViewport world; the client is a `Night` that joined with
# `start_remote`.
extends GdUnitTestSuite

const A := 1
## What a re-cut costs, every time.
const RECUT_PRICE := 5000

var _host: NightHost
var _nights: Array[Night] = []
var _commands: Dictionary = {}


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
	# A hand-driven client sends its (empty) command every tick, as the server expects.
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void: night.link.send((_commands[night] as NightCommand).to_dict())
	)
	return night


func _bench() -> Vector3:
	for spot in _host.server.world.shop_spots():
		if spot["kind"] == &"upgrade":
			return spot["position"]
	return Vector3.INF


func _prompt(night: Night) -> Dictionary:
	return night.state.me().get("prompt", {})


func _press_use(night: Night) -> void:
	var command := _commands[night] as NightCommand
	command.use = true
	for _i in 3:
		await get_tree().physics_frame
	command.use = false
	for _i in 6:
		await get_tree().physics_frame


func test_a_client_pays_5000_for_each_of_three_weapons_and_is_refused_a_second_re_cut() -> void:
	await _server()
	var a := await _client()
	var server := _host.server
	# Wait for the night's first frame to reach the client, then stand the server's body at the bench.
	assert_bool(await _until(func() -> bool: return a.avatars.ids().has(A))).is_true()
	assert_bool(_bench() != Vector3.INF).is_true()
	server.rules.apply(RulesAction.grant_points(A, 30000))
	(server._bodies[A] as Player).teleport(_bench() + Vector3(0.0, 0.1, 0.0))
	var held: Array[StringName] = [&"pistol", &"smg", &"shotgun"]
	for weapon in held:
		server._combat(CombatAction.give_weapon(A, weapon))
		var offered := await _until(
			func() -> bool: return String(_prompt(a).get("kind", "")) == "recut"
		)
		assert_bool(offered).override_failure_message("no re-cut offer for " + weapon).is_true()
		assert_int(_prompt(a)["price"]).is_equal(RECUT_PRICE)
		var before := server.rules.points_of(A)
		await _press_use(a)
		assert_int(before - server.rules.points_of(A)).is_equal(RECUT_PRICE)
		assert_int(server.combat.state_of(A, weapon).tier()).is_equal(1)
		var told := await _until(
			func() -> bool: return String(_prompt(a).get("kind", "")) == "recut_done"
		)
		assert_bool(told).is_true()
	# The shotgun is re-cut: pressing again costs nothing, and the server's rules say why.
	var paid := server.rules.points_of(A)
	await _press_use(a)
	await _press_use(a)
	assert_int(server.rules.points_of(A)).is_equal(paid)
	var denied := RulesFixture.first(server.buy(A, &"upgrade_weapon"), &"purchase_denied")
	assert_int(denied["result"]).is_equal(GameRules.BuyResult.ALREADY_OWNED)
	assert_array(server.rules.players[A].upgraded).contains_exactly([&"pistol", &"smg", &"shotgun"])
