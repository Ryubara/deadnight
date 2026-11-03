# A flare fired in the night does no damage and calls the dead (#439): the burst starts a lure
# on the server, the zombies near it walk to it instead of to the player, and the client draws
# the flare burning where it landed. A night run by hand: a tick is 1/60 s, nothing waits on time.
extends GdUnitTestSuite

const SETTLE := 30
## Time for the first zombie to finish rising before the shot.
const EMERGE_TICKS := 150
const FLIGHT_LIMIT := 400
## Where the test puts a zombie from the lure, on the lot's open ground (m).
const STANDOFF := 12.0
const WATCH_TICKS := 360

var _night: Night
var _heard: Array[Dictionary] = []


func before_test() -> void:
	_heard = []
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	_night.state.event_received.connect(_hear)
	NightFixture.run(_night, SETTLE)
	_night.server.combat.apply(CombatAction.give_weapon(1, &"flare_gun"))
	_night.server.combat.apply(CombatAction.equip(1, &"flare_gun"))
	NightFixture.run(_night, EMERGE_TICKS)


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


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Pulls the trigger once, level, and runs until the flare has burst.
func _fire_and_wait() -> Dictionary:
	var eye := _night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	var command := NightCommand.new()
	command.origin = eye
	command.aim_along(Vector3(0.0, 0.25, 1.0))
	command.fire = true
	NightFixture.run(_night, 1, command)
	var ticks := 0
	while _of(&"lure_started").is_empty() and ticks < FLIGHT_LIMIT:
		NightFixture.run(_night, 1)
		ticks += 1
	NightFixture.run(_night, 3)
	assert_int(_of(&"lure_started").size()).is_equal(1)
	return _of(&"lure_started")[0]


func test_a_flare_does_no_damage_and_the_server_starts_a_lure_where_it_burst() -> void:
	var lure := _fire_and_wait()
	assert_array(_of(&"damage_dealt")).is_empty()
	var burst := _of(&"projectile_burst")[0]
	assert_bool(lure["point"] == burst["point"]).is_true()
	assert_int(_night.server.sim.lures.size()).is_equal(1)
	assert_float(_night.server.sim.lures[0].left).is_greater(0.0)


func test_a_zombie_in_the_radius_walks_to_the_flare_and_not_to_the_player() -> void:
	var lure := _fire_and_wait()
	var at: Vector3 = lure["point"]
	var zombie_id := NightFixture.first_zombie(_night)
	assert_int(zombie_id).is_greater(0)
	var body: ZombieBody = _night.server.sim.zombies[zombie_id]
	body.enter(ZombieBody.Mode.CHASE)
	body.position = at + Vector3(STANDOFF, 0.0, 0.0)
	# Put down on open ground by hand, so it has no breach it still has to get through.
	body.gate_id = &""
	var player_at := _night.state.position()
	var from_lure := _flat(body.position, at)
	NightFixture.run(_night, WATCH_TICKS)
	assert_int(body.lure_id).is_equal(lure["lure_id"])
	assert_float(_flat(body.position, at)).is_less(from_lure - 3.0)
	# And it is no nearer to the player than it was, unless the flare lies in the player's way.
	assert_float(_flat(body.position, at)).is_less(_flat(body.position, player_at))
	assert_array(_of(&"damage_dealt")).is_empty()


func test_the_view_draws_the_flare_burning_for_as_long_as_the_lure_lasts() -> void:
	var lure := _fire_and_wait()
	var views := _night.view.find_children("*", "LureView", true, false)
	assert_int(views.size()).is_equal(1)
	var view := views[0] as LureView
	assert_float(view.seconds).is_equal(lure["seconds"])
	assert_float(_flat(view.global_position, lure["point"])).is_less(0.01)


func test_the_server_ends_the_lure_after_its_seconds() -> void:
	var lure := _fire_and_wait()
	NightFixture.run(_night, ceili((lure["seconds"] + 1.0) * 60.0))
	assert_int(_night.server.sim.lures.size()).is_equal(0)
