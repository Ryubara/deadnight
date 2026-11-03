# A person's order reaches the server's bots over a real WebSocket (#641): a game server, a person's
# client (`Night.start_remote`), and two bots that are clients of the same server too (a
# `WebSocketLink` each, fed to a `BotClient` as a socket feeds a person's screen), so the order
# travels the whole way: the wheel's call, the ORDER message, the server's judge, the frame (as a
# delta) and the bot's beliefs. The bots then do what the order says.
extends GdUnitTestSuite

const STEP := Night.STEP
## Metres the order promises for a hold.
const HOLD_RADIUS := 3.0

var _host: NightHost
var _person: Night
var _links: Array[WebSocketLink] = []
var _bots: Array[BotClient] = []


func after_test() -> void:
	for link in _links:
		link.close()
	_links.clear()
	_bots.clear()
	if is_instance_valid(_person):
		_person.get_parent().queue_free()
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


func _url() -> String:
	return "ws://127.0.0.1:%d" % _host.listener.port()


func _server() -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)


## The person: a client with no body to drive (the order does not need one), seat 1.
func _join_person() -> void:
	_person = Night.new()
	_world().add_child(_person)
	var joined := await _person.start_remote(_url(), Night.Mode.MANUAL, 30.0)
	assert_bool(joined).is_true()
	# Standing still, but speaking: a seat that sends nothing is closed after a while.
	_person.ticked.connect(func() -> void: _person.link.send(NightCommand.new().to_dict()))


## A bot seated through the door a person uses: its own connection, its own `ClientState`, the
## server's lot for the eyes and the walking mesh it was given.
func _join_bot() -> BotClient:
	var link := WebSocketLink.new()
	var welcome := {}
	link.welcomed.connect(func(snapshot: Dictionary) -> void: welcome["snapshot"] = snapshot)
	assert_int(link.connect_to(_url())).is_equal(OK)
	_links.append(link)
	var early: Array = []
	link.delivered.connect(func(events: Array) -> void: early.append_array(events))
	(
		assert_bool(
			await _until(
				func() -> bool:
					link.pump()
					return welcome.has("snapshot") and not early.is_empty(),
				20.0
			)
		)
		. is_true()
	)
	var state := ClientState.new()
	state.player_id = link.player_id
	var probe := WorldProbe.new(_host.world.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		probe.callable(), _host.world.is_lit, _host.server.rules.tuning.rounds, _host.world.map()
	)
	LotBotData.fill(level, _host.world)
	var bot := BotClient.new(state, BotProfile.regular(), 900 + link.player_id, link.send, level)
	link.delivered.connect(func(events: Array) -> void: bot.hear(events))
	bot.hear(early)
	_bots.append(bot)
	return bot


func _run(frames: int) -> void:
	for _i in frames:
		for link in _links:
			link.pump()
		for bot in _bots:
			bot.tick(STEP)
		await get_tree().physics_frame


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _position_of(bot: BotClient) -> Vector3:
	return _host.server.body_of(bot.state.player_id).global_position


## Runs the bots until each believes the standing order is `order` (up to ten seconds).
func _bots_believe(order: StringName) -> bool:
	for _i in 600:
		await _run(1)
		if _believes(order):
			return true
	return false


func _believes(order: StringName) -> bool:
	for bot in _bots:
		if bot.perception.beliefs.order["order"] != order:
			return false
	return true


func test_a_remote_persons_order_reaches_the_bots_and_they_keep_it() -> void:
	await _server()
	await _join_person()
	assert_int(_person.state.player_id).is_equal(1)
	var bots: Array[BotClient] = [await _join_bot(), await _join_bot()]
	assert_int(bots.size()).is_equal(2)
	await _run(60)
	# Nothing was said: the bots roam.
	assert_bool(_believes(BotOrders.ROAM)).is_true()
	assert_str(str(BotOrders.current(_person.state.frame)["order"])).is_equal("roam")
	# The person holds where they stand.
	var spot: Vector3 = _person.state.frame["players"][1]["pos"]
	var sent := _person.give_bot_order(BotOrders.HOLD)
	assert_str(str(sent["order"])).is_equal("hold")
	var arrived := await _bots_believe(BotOrders.HOLD)
	assert_bool(arrived).override_failure_message("the order did not reach the bots").is_true()
	# The server has it, as the person's, at the place they stood, and the person's screen too.
	var kept := _host.server.bot_orders.order_for(0)
	assert_str(str(kept["order"])).is_equal("hold")
	assert_int(kept["issuer_id"]).is_equal(1)
	assert_float(_flat(kept["at"], spot)).is_less(1.5)
	assert_str(str(BotOrders.current(_person.state.frame)["order"])).is_equal("hold")
	# And the bots go there and stay.
	await _run(60 * 30)
	for bot in bots:
		(
			assert_float(_flat(_position_of(bot), kept["at"]))
			. override_failure_message(
				(
					"bot %d is %.1f m from the spot"
					% [bot.state.player_id, _flat(_position_of(bot), kept["at"])]
				)
			)
			. is_less(HOLD_RADIUS)
		)
	# A second order replaces the first: Follow, then Roam.
	await _run(40)
	_person.give_bot_order(BotOrders.FOLLOW)
	assert_bool(await _bots_believe(BotOrders.FOLLOW)).is_true()
	await _run(40)
	_person.give_bot_order(BotOrders.ROAM)
	assert_bool(await _bots_believe(BotOrders.ROAM)).is_true()
