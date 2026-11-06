extends GdUnitTestSuite
## A slow dead beside the drive-in's west ticket booth leaves the plaza (#1347). The booth (a 2.4 m
## box at (-6, 45.2)) has the way round it north and the way round it south at nearly the same
## length, and the walking mesh's search picks the north way in a diagonal strip beside its west
## face and the south way on both sides of the strip. A crawler (1.2 m/s, 0.3 m between two repaths)
## that took the north way walked out of the strip, was told the south way and walked back into it:
## it stood at (-8.5, 45.2) for six minutes while the soak's round waited for its last dead
## (`regular_3_hold_person`: 13 nights of 100 on 2026-11-06). Walkers up to 1.8 m/s did the same.
##
## The plaza is open (the road door bought), a person stands in the field far to the north, and
## each dead is put on a 0.3 m grid beside the booth's west face; every one must be on its way north
## (past the plaza's gate at z = 38) within the time a stroll takes.

const STARTS_X_FROM := -9.4
const STARTS_X_TO := -7.3
const STARTS_Z_FROM := 44.2
const STARTS_Z_TO := 46.4
const STARTS_STEP := 0.3
## Metres per second: a crawler (the soak's) and a slow walker.
const SPEEDS: Array[float] = [1.2, 1.8]
## The person, far north of the plaza in the field.
const PERSON := Vector3(0.0, 0.0, -33.0)
## It is past the gate when it is north of this (the gate's slab stands at z = 38).
const PAST_THE_GATE_Z := 38.0
## Seconds: 22 m of the way to the gate at a crawl is 18 s; twice that is the slack.
const SECONDS := 40.0

var _seated: SeatedNight


func after_test() -> void:
	if _seated != null:
		_seated.dispose()
		_seated = null


func _plaza_open() -> void:
	var tuning := RulesFixture.tuning()
	tuning.health.max_health = 1000000.0
	_seated = await SeatedNight.start(self, 1, tuning, 5, false)
	for item in _seated.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			_seated.open_door(item.id)
	assert_bool(await _seated.settle_doors()).is_true()
	await _seated.settle(30)


## The starts beside the booth where a dead of `speed` was still south of the gate after `SECONDS`.
func _stuck_starts(speed: float, profile: ZombieProfile) -> PackedStringArray:
	var sim := _seated.server.sim
	var stuck := PackedStringArray()
	var x := STARTS_X_FROM
	while x <= STARTS_X_TO + 0.001:
		var z := STARTS_Z_FROM
		while z <= STARTS_Z_TO + 0.001:
			sim.zombies.clear()
			var zombie := sim.spawn(900, speed, Vector3(x, 0.0, z), 0.0, profile)
			zombie.enter(ZombieBody.Mode.CHASE)
			for _i in ceili(SECONDS / ZombieSim.STEP):
				sim.tick(ZombieSim.STEP, {1: PERSON})
			if zombie.position.z > PAST_THE_GATE_Z:
				stuck.append(
					(
						"(%.1f, %.1f) ended at (%.1f, %.1f)"
						% [x, z, zombie.position.x, zombie.position.z]
					)
				)
			z += STARTS_STEP
		x += STARTS_STEP
	sim.zombies.clear()
	return stuck


func test_a_crawler_beside_the_booth_goes_on_north() -> void:
	await _plaza_open()
	var sim := _seated.server.sim
	var type := _seated.server.rules.tuning.roster.type_of(&"crawler")
	var crawler := ZombieProfile.from_type(type, &"crawler", sim.tuning)
	var stuck := _stuck_starts(SPEEDS[0], crawler)
	(
		assert_array(stuck)
		. override_failure_message(
			"%d crawlers stayed south of the gate: %s" % [stuck.size(), ", ".join(stuck)]
		)
		. is_empty()
	)


func test_a_slow_walker_beside_the_booth_goes_on_north() -> void:
	await _plaza_open()
	var plain := ZombieProfile.plain(_seated.server.sim.tuning)
	for speed in SPEEDS.slice(1):
		var stuck := _stuck_starts(speed, plain)
		(
			assert_array(stuck)
			. override_failure_message(
				(
					"%d walkers at %.1f m/s stayed south of the gate: %s"
					% [stuck.size(), speed, ", ".join(stuck)]
				)
			)
			. is_empty()
		)
