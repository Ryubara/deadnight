# A flare fired in the night is drawn: the view makes a body when the server says a projectile
# spawned, flies it with the server's own code on every frame, and ends it on the burst (#257).
# A night run by hand: a tick is 1/60 s and nothing waits on the clock.
extends GdUnitTestSuite

const SETTLE := 30
## From the trigger to the flare leaving: the server's shot is instant, the frames carry it.
const FIRE_TICKS := 6
## Ticks the body may take to turn to the view before the flare leaves (#477): a half turn is 24.
const TURN_LIMIT := 60
const FLIGHT_LIMIT := 400
## The copy stops a step short of the server's wall or ground hit, or stands on it: it may differ by
## the length of one step of the flare's flight (m), and a little for the fall.
const BURST_REACH := 0.7

var _night: Night
var _heard: Array[Dictionary] = []


func before_test() -> void:
	_heard = []
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	_night.state.event_received.connect(_hear)
	NightFixture.run(_night, SETTLE)
	_night.server.combat.apply(CombatAction.give_weapon(1, &"flare_gun"))
	_night.server.combat.apply(CombatAction.equip(1, &"flare_gun"))
	NightFixture.run(_night, 3)


func after_test() -> void:
	_night.state.event_received.disconnect(_hear)
	_night.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _hear(event: Dictionary) -> void:
	_heard.append(event)


func _of(type: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in _heard:
		if event["type"] == type:
			found.append(event)
	return found


## Pulls the trigger once, looking level and away from the lot's buildings: behind the body, so the
## press waits for the turn (#477) and the flare leaves when the body faces the view.
func _fire() -> void:
	var eye := _night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	var command := NightCommand.new()
	command.origin = eye
	command.aim_along(Vector3(0.0, 0.25, 1.0))
	command.fire = true
	NightFixture.run(_night, 1, command)
	var ticks := 0
	while _of(&"projectile_spawned").is_empty() and ticks < TURN_LIMIT:
		NightFixture.run(_night, 1)
		ticks += 1
	(
		assert_int(_of(&"projectile_spawned").size())
		. override_failure_message("no flare left within %d ticks of the press" % TURN_LIMIT)
		. is_equal(1)
	)
	NightFixture.run(_night, FIRE_TICKS)


func test_a_flare_in_the_air_is_drawn_and_gone_when_it_bursts() -> void:
	_fire()
	assert_int(_of(&"projectile_spawned").size()).is_equal(1)
	assert_int(_night.view.projectiles_in_flight()).is_equal(1)
	var ticks := 0
	while _of(&"projectile_burst").is_empty() and ticks < FLIGHT_LIMIT:
		NightFixture.run(_night, 1)
		ticks += 1
	assert_int(_of(&"projectile_burst").size()).is_equal(1)
	assert_int(_night.view.projectiles_in_flight()).is_equal(0)
	await get_tree().process_frame  # a freed body leaves the tree at the frame's end
	assert_int(_night.view.find_children("*", "ProjectileView", true, false).size()).is_equal(0)


func test_the_drawn_flare_flies_where_the_server_says_and_follows_it_to_the_burst() -> void:
	_fire()
	if _of(&"projectile_spawned").is_empty():
		return
	var spawned := _of(&"projectile_spawned")[0]
	var views := _night.view.find_children("*", "ProjectileView", true, false)
	assert_int(views.size()).is_equal(1)
	var view := views[0] as ProjectileView
	assert_int(view.state.id).is_equal(spawned["projectile_id"])
	var start: Vector3 = view.global_position
	NightFixture.run(_night, 20)
	assert_bool(view.global_position.is_equal_approx(start)).is_false()
	assert_bool(view.global_position.is_equal_approx(view.state.position)).is_true()
	var ticks := 0
	while _of(&"projectile_burst").is_empty() and ticks < FLIGHT_LIMIT:
		NightFixture.run(_night, 1)
		ticks += 1
	var burst := _of(&"projectile_burst")[0]
	assert_float(view.state.position.distance_to(burst["point"])).is_less(BURST_REACH)


func test_a_burst_with_no_body_is_harmless() -> void:
	_night.view.draw_event({"type": &"projectile_burst", "point": Vector3(3, 0, 3)})
	assert_int(_night.view.projectiles_in_flight()).is_equal(0)


func test_each_flare_is_drawn_on_its_own() -> void:
	for id in [11, 12]:
		(
			_night
			. view
			. draw_event(
				{
					"type": &"projectile_spawned",
					"projectile_id": id,
					"shooter_id": 1,
					"weapon_id": &"flare_gun",
					"position": Vector3(0, 2, 0),
					"velocity": Vector3(0, 0, 10),
				}
			)
		)
	assert_int(_night.view.projectiles_in_flight()).is_equal(2)
	_night.view.draw_event(
		{"type": &"projectile_burst", "projectile_id": 11, "point": Vector3(0, 0, 5)}
	)
	assert_int(_night.view.projectiles_in_flight()).is_equal(1)
