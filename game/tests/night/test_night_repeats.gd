extends GdUnitTestSuite
## A night of one seed plays the same every time it is played (#1350). The nightly's round count and
## the leak job's rounds were one draw of a spread of 9 to 19 rounds because two runs of one commit,
## seed and command did not repeat: the lot waited a number of physics frames for its navigation map
## that changed from run to run (3 to 9), and until the lot was about 17 frames old the ground's
## contacts played a body's first steps differently by its age. The first body to differ was a bot
## standing a millimetre up or on the floor; the chase after it made the hair a different night.

const SEED := 1958
const STEPS := 900
## The ticks between two hashes (half a second).
const EVERY := 30


func test_scenario_1_the_lot_is_old_enough_when_its_build_returns() -> void:
	for _i in 3:
		var world := NightWorld.new()
		add_child(world)
		var began := Engine.get_physics_frames()
		await world.build()
		assert_int(Engine.get_physics_frames() - began).is_greater_equal(NightWorld.LOT_MIN_FRAMES)
		world.queue_free()
		await get_tree().physics_frame


func test_scenario_2_a_night_started_a_few_frames_later_plays_the_same_one() -> void:
	# Before the fix a night seated 0 to 2 frames after its lot was built played one night and a night
	# seated 3 or more frames after it played another.
	var now := await _hashes(0)
	var later := await _hashes(3)
	var again := await _hashes(0)
	assert_array(now).has_size(STEPS / EVERY)
	assert_array(later).is_equal(now)
	assert_array(again).is_equal(now)


## The hash, every half second of a night of walking bots among a crowd, of the places of every body
## and of every dead as the server holds them (no grid: a hair of difference is a different hash).
## The night's first tick comes `extra` physics frames later than the build asks.
func _hashes(extra: int) -> Array[int]:
	var night := await NightFixture.seat(self, 3, SeatedNight.brisk(), SEED)
	for _i in extra:
		await get_tree().physics_frame
	for id in range(1, 4):
		night.seat(id, BotProfile.regular(), SEED + id)
	night.server.rules.apply(RulesAction.skip_break())
	var hashes: Array[int] = []
	for step in STEPS:
		night.tick()
		if (step + 1) % EVERY == 0:
			hashes.append(_state_of(night))
	night.dispose()
	await get_tree().physics_frame
	return hashes


static func _state_of(night: SeatedNight) -> int:
	var parts: Array = [night.server.tick_count, night.server.rules.round_number]
	var seats: Array = night.server.rules.players.keys()
	seats.sort()
	for id: int in seats:
		parts.append(night.server.body_of(id).global_position)
	var ids: Array = night.server.sim.zombies.keys()
	ids.sort()
	for id: int in ids:
		var zombie: ZombieBody = night.server.sim.zombies[id]
		parts.append_array([id, zombie.mode, zombie.position])
	return hash(var_to_bytes(parts))
