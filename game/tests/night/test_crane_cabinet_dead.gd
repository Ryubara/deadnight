extends GdUnitTestSuite
## The prize crane's cabinet is a solid box that moves to another spot when the crane breaks down
## (`CraneBlock`), and the dead are not physics bodies: one that stands where the cabinet lands is
## inside a wall that every sight line and shot ends on, swinging at whoever stands beside it, and
## nobody can see it or hit it (Deadnight #1352: two dead for 1 040 s in the autopilot's round 10 at
## the crane's third spot, `(-24.0, -12.5)`, three bots 0.8 to 2.6 m off with no contact). On
## the real lot and the real server, with the dead where that night's were.

const SEED := 8
const TICKS_PER_SECOND := 60
const LONG_BREAK := 3000.0
## The crane's third spot: no door shuts it, so the first move from the start is there.
const SPOT := 2
## Where the two dead of that night stood, in the cabinet's footprint at the third spot.
const DEAD_AT: Array[Vector3] = [Vector3(-23.44, -0.05, -12.52), Vector3(-24.05, -0.05, -11.99)]
## The person stands 1 m from the cabinet's face and the dead swing at them (a body with no
## brain does not step away, as the bots that stood there did not); the bot is 2 m east of it,
## out of the person's line.
const PERSON_AT := Vector3(-24.0, 0.1, -10.8)
const BOT_AT := Vector3(-21.8, 0.1, -11.0)
const PLAYER_HEALTH := 1.0e6

var _night: SeatedNight
var _bot: BotClient
## The two dead put in the third spot's footprint (the round has more, far away).
var _pair: Array[int] = []


func after_test() -> void:
	if _night != null:
		_night.dispose()
		_night = null
		await get_tree().process_frame


## A night with a person beside the third spot, a bot near, two dead standing in that spot's
## footprint (held fire: nobody shoots yet) and the crane about to break down on the person's play.
func _setup() -> void:
	var tuning := RulesFixture.tuning()
	tuning.health.max_health = PLAYER_HEALTH
	tuning.rounds.count_base = 2.0
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	tuning.crane.spin_seconds = 1.0
	tuning.crane.breakdown_seconds = 1.0
	tuning.crane.leave_chances = PackedFloat32Array([1.0])
	tuning.crane.safe_plays = 0
	_night = await NightFixture.seat(self, 2, tuning, SEED)
	_night.stand_still = true
	_night.hold_fire = true
	await _night.settle(60)
	_bot = _night.seat(1, BotProfile.regular(), SEED + 1)
	_night.human(2)
	_night.server.body_of(1).teleport(BOT_AT)
	_night.server.body_of(2).teleport(PERSON_AT)
	_night.run(10)
	_night.start_round()
	var guard := 0
	while _night.server.sim.zombies.size() < 2 and guard < 60 * TICKS_PER_SECOND:
		_night.tick()
		guard += 1
	var ids: Array = _night.server.sim.zombies.keys()
	ids.sort()
	_pair.assign(ids.slice(0, 2))
	for at in 2:
		var zombie: ZombieBody = _night.server.sim.zombies[_pair[at]]
		zombie.position = DEAD_AT[at]
		zombie.enter(ZombieBody.Mode.ATTACK)
	_night.server.sim.touch()


## The person plays the crane, which breaks down at the end of the spin and moves at the end of the
## breakdown: three seconds, with a margin. The engine takes two physics frames to put the moved
## cabinet's shape into its space (a hand-ticked night does not run them).
func _break_the_crane() -> void:
	var rules := _night.server.rules
	rules.apply(RulesAction.grant_points(2, 10000))
	rules.apply(RulesAction.buy(2, &"crane_play"))
	for _t in 5 * TICKS_PER_SECOND:
		_night.tick()
		if rules.crane.spot == SPOT:
			break
	assert_int(rules.crane.spot).is_equal(SPOT)
	_night.run(10)
	await _night.settle(3)
	_night.run(5)


## The two dead put in the footprint, the ones still standing.
func _alive() -> Array[ZombieBody]:
	var found: Array[ZombieBody] = []
	for id in _pair:
		var zombie: ZombieBody = _night.server.sim.zombies.get(id)
		if zombie != null and zombie.is_alive():
			found.append(zombie)
	return found


func _eye() -> Vector3:
	return _night.server.body_of(1).global_position + Vector3(0.0, BotLevel.EYE_HEIGHT, 0.0)


func test_the_crane_lands_on_the_dead_and_they_are_put_outside_it() -> void:
	await _setup()
	var solid := _night.world.crane_block.solid
	await _break_the_crane()
	assert_int(_alive().size()).is_equal(2)
	for zombie in _alive():
		(
			assert_bool(solid.contains(zombie.position))
			. override_failure_message(
				"dead %d stands inside the cabinet at %s" % [zombie.id, zombie.position]
			)
			. is_false()
		)


func test_a_bot_beside_the_cabinet_has_a_line_to_the_dead_it_landed_on() -> void:
	await _setup()
	await _break_the_crane()
	for zombie in _alive():
		var chest := zombie.position + Vector3(0.0, 1.1, 0.0)
		(
			assert_bool(_night.level.clear(_eye(), chest))
			. override_failure_message(
				(
					"no line from the bot to dead %d at %s: %s metres to a wall"
					% [zombie.id, zombie.position, _night.level.sight.call(_eye(), chest)]
				)
			)
			. is_true()
		)


func test_the_bot_kills_the_dead_the_crane_landed_on() -> void:
	await _setup()
	await _break_the_crane()
	_night.hold_fire = false
	var ticks := 0
	while not _alive().is_empty() and ticks < 30 * TICKS_PER_SECOND:
		_night.tick()
		ticks += 1
	(
		assert_int(_alive().size())
		. override_failure_message(
			(
				"%d of the two dead the crane landed on still stand after %d s of fire"
				% [_alive().size(), ticks / TICKS_PER_SECOND]
			)
		)
		. is_equal(0)
	)


func test_a_dead_that_swings_inside_the_standing_cabinet_is_put_outside_it() -> void:
	await _setup()
	await _break_the_crane()
	var solid := _night.world.crane_block.solid
	var zombie := _alive()[0]
	zombie.position = _night.world.crane_block.global_position + Vector3(0.2, 0.0, 0.1)
	zombie.enter(ZombieBody.Mode.ATTACK)
	assert_bool(solid.contains(zombie.position)).is_true()
	_night.run(5)
	assert_bool(solid.contains(zombie.position)).is_false()
	assert_float(_flat(zombie.position, PERSON_AT)).is_less(3.0)


func test_a_dead_that_walks_through_the_cabinet_is_left_to_walk() -> void:
	await _setup()
	await _break_the_crane()
	var solid := _night.world.crane_block.solid
	var zombie := _alive()[0]
	zombie.enter(ZombieBody.Mode.CHASE)
	zombie.position = _night.world.crane_block.global_position
	_night.server.sim.touch()
	# One step: a walking dead is not moved (only one that stands, or one a cabinet landed on).
	var before := zombie.position
	_night.server.sim.tick(ZombieSim.STEP, {})
	assert_bool(solid.contains(before)).is_true()
	assert_float(_flat(zombie.position, before)).is_less(0.5)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
