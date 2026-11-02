# A bot throws a grenade in the real server (bots plan, phase 3): at a pack, to where the pack
# stands, and never with a teammate within 4 m of the blast. The rules of choosing are in
# `tests/bots/test_bot_grenadier.gd`; this is the whole throw: the turn, the pin, the arm, the arc
# the server flies and the blast it makes.
extends GdUnitTestSuite

const STEP := Night.STEP
const TICKS_PER_SECOND := 60
## Where the pack stands: ten metres down the field from the bot at home.
const PACK_AT := Vector3(0.0, 0.0, -10.0)
const PACK_SIZE := 4
## The longest the test waits for a blast.
const WAIT_SECONDS := 8.0


func _home() -> Vector3:
	return Autopilot.HOME


## A night with a bot at seat 1 and a person standing at seat 2 (`mate_at`, from home), a pack of
## zombies that stand still `PACK_AT` from home, and the round begun.
func _night(mate_at: Vector3) -> SeatedNight:
	var night := await NightFixture.seat(self, 2, SeatedNight.one_a_round(), 21)
	var profile := BotProfile.regular()
	profile.follows = false
	night.seat(1, profile, 21)
	night.human(2)
	night.start_round()
	night.server.body_of(1).teleport(_home() + Vector3(0.0, 0.1, 0.0))
	night.server.body_of(2).teleport(_home() + mate_at + Vector3(0.0, 0.1, 0.0))
	for i in PACK_SIZE:
		var at := _home() + PACK_AT + Vector3(float(i % 2) * 1.2, 0.0, float(i / 2) * 1.2)
		var zombie := night.server.sim.spawn(1000 + i, 0.0, at)
		zombie.enter(ZombieBody.Mode.CHASE)
	night.run(5)
	return night


## The blast points (those the bot threw) of the next `WAIT_SECONDS`.
func _blasts(night: SeatedNight) -> Array[Vector3]:
	var blasts: Array[Vector3] = []
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"grenade_exploded" and event["thrower_id"] == 1:
			blasts.append(event["point"])
	for _i in int(WAIT_SECONDS * TICKS_PER_SECOND):
		night.tick()
		if not blasts.is_empty():
			break
	night.on_event = Callable()
	return blasts


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_a_pack_ten_metres_off_is_hit_by_a_grenade_the_bot_throws() -> void:
	var night := await _night(Vector3(-12.0, 0.0, 6.0))
	var health_before: float = night.frame["players"][1]["health"]
	var blasts := _blasts(night)
	assert_array(blasts).has_size(1)
	var centre := _home() + PACK_AT + Vector3(0.6, 0.0, 0.6)
	assert_float(_flat(blasts[0], centre)).is_less(3.5)
	# The thrower stood well outside the blast.
	assert_float(night.frame["players"][1]["health"]).is_equal(health_before)
	assert_int(night.host.bots[0].motor.throws).is_equal(1)
	night.dispose()


func test_no_grenade_goes_off_within_four_metres_of_a_person_wherever_they_stand() -> void:
	# The person stands round the pack at several distances; whenever a grenade does go off, they
	# are 4 m or more from it. (The pack stands still, so the blast is where the pack is.)
	var centre := PACK_AT + Vector3(0.6, 0.0, 0.6)
	var thrown := 0
	var held_back := 0
	for ring in [1.5, 3.0, 3.9, 4.4, 6.0]:
		for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
			var mate_at: Vector3 = centre + Vector3(sin(angle), 0.0, cos(angle)) * ring
			var night := await _night(mate_at)
			var blasts := _blasts(night)
			var mate := night.server.body_of(2).global_position
			if blasts.is_empty():
				held_back += 1
			for blast in blasts:
				thrown += 1
				assert_float(_flat(blast, mate)).is_greater_equal(4.0)
			night.dispose()
	# Both happened: the person near the pack stopped the throw, and a person far enough did not.
	assert_int(held_back).is_greater(0)
	assert_int(thrown).is_greater(0)
