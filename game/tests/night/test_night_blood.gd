# Blood in a real night (#618): a zombie that is shot or struck bleeds where the server says it was
# hit, on the client that draws it. The event the server sends carries the point, the shot's way
# and the weapon, so every client can draw the same splash without a protocol change.
extends GdUnitTestSuite

const SETTLE := 30

var _night: Night
var _heard: Array[Dictionary] = []


func before_test() -> void:
	_heard = []
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	_night.state.event_received.connect(func(event: Dictionary) -> void: _heard.append(event))
	NightFixture.run(_night, SETTLE)


func after_test() -> void:
	_night.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _shoot_first_zombie() -> Dictionary:
	var id := NightFixture.first_zombie(_night)
	assert_int(id).is_greater(0)
	var body: ZombieBody = _night.server.sim.zombies[id]
	var ahead := Vector3(0.0, 0.0, -4.0)
	body.position = _night.state.position() + ahead
	body.velocity = Vector3.ZERO
	_night.server.sim.touch()
	var spot := body.position
	for _i in 12:
		body.position = spot
		body.velocity = Vector3.ZERO
		_night.server.sim.touch()
		NightFixture.run(_night, 1, NightFixture.shoot_at(_night, spot))
		for event in _heard:
			if event["type"] == &"damage_dealt":
				return event
	return {}


func test_the_hit_event_carries_the_point_the_way_and_the_weapon() -> void:
	var event := _shoot_first_zombie()
	assert_bool(event.is_empty()).override_failure_message("no zombie was hit").is_false()
	assert_str(String(event["weapon_id"])).is_equal(String(_night.state.me()["weapon"]))
	var dir: Vector3 = event["dir"]
	assert_float(dir.length()).is_equal_approx(1.0, 0.01)
	# The way points from the player toward the zombie.
	var toward: Vector3 = (event["point"] as Vector3) - _night.state.position()
	assert_float(dir.dot(toward.normalized())).is_greater(0.9)


func test_the_view_splashes_at_the_point_the_server_sent() -> void:
	var event := _shoot_first_zombie()
	assert_bool(event.is_empty()).is_false()
	var origins := _night.view.effects.blood.splash_origins()
	assert_int(origins.size()).is_greater(0)
	(
		assert_bool(origins.any(func(p: Vector3) -> bool: return p.is_equal_approx(event["point"])))
		. is_true()
	)


func test_a_blow_with_the_crowbar_bleeds_as_a_melee_hit() -> void:
	_night.server.combat.apply(CombatAction.give_weapon(1, &"crowbar"))
	NightFixture.run(_night, 3)
	var id := NightFixture.first_zombie(_night)
	var body: ZombieBody = _night.server.sim.zombies[id]
	var spot := _night.state.position() + Vector3(0.0, 0.0, -1.1)
	for _i in 12:
		body.position = spot
		body.velocity = Vector3.ZERO
		_night.server.sim.touch()
		NightFixture.run(_night, 1, NightFixture.shoot_at(_night, spot))
	var hits := _heard.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"damage_dealt" and e["melee"]
	)
	assert_int(hits.size()).is_greater(0)
	assert_int(_night.view.effects.blood.splashes_alive()).is_greater(0)
