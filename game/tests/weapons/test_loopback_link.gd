extends GdUnitTestSuite
## The stand-in transport: what crosses is bytes, and latency delays each direction.

var _server: CombatServer
var _link: LoopbackLink
var _received: Array[Dictionary] = []


func before_test() -> void:
	_server = WeaponsFixture.make_server()
	_server.apply(CombatAction.register_target(1, 60.0))
	_server.apply(CombatAction.give_weapon(1, &"pistol"))
	WeaponsFixture.step(_server, {1: Vector3.ZERO}, 2)
	_received = []


func _connect(latency: int) -> void:
	_link = LoopbackLink.new(_server, latency)
	_link.delivered.connect(
		func(events: Array) -> void:
			for event: Dictionary in events:
				_received.append(event)
	)


func _fire() -> void:
	_link.send(
		WeaponsFixture.fire_at(1, 1, WeaponsFixture.SHOOTER, Vector3(0, 1.1, 0), _server.now)
	)


func test_an_action_goes_over_and_its_events_come_back() -> void:
	_connect(0)
	_fire()
	_link.pump()
	assert_array(WeaponsFixture.of(_received, &"damage_dealt")).has_size(1)
	assert_bool(_server.is_target_alive(1)).is_true()
	assert_float(_server.health_of(1)).is_equal_approx(36.0, 0.01)


func test_latency_delays_the_request_and_the_answer() -> void:
	_connect(3)
	_fire()
	for _i in 2:
		_link.pump()
	assert_float(_server.health_of(1)).is_equal(60.0)
	_link.pump()
	assert_float(_server.health_of(1)).is_equal_approx(36.0, 0.01)
	for _i in 2:
		_link.pump()
	assert_array(_received).is_empty()
	_link.pump()
	assert_array(WeaponsFixture.of(_received, &"damage_dealt")).has_size(1)


func test_what_the_server_does_alone_reaches_the_client_too() -> void:
	_connect(0)
	_server.weapon_of(1).ammo = 0
	_link.send(CombatAction.reload_weapon(1))
	_link.pump()
	var finished: Array[Dictionary] = []
	for _i in 120:
		_link.broadcast(_server.apply(CombatAction.tick(WeaponsFixture.STEP)))
		_link.pump()
	finished = WeaponsFixture.of(_received, &"reload_finished")
	assert_array(finished).has_size(1)
