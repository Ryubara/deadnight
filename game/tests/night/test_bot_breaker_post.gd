# A Roam bot held at the breaker post by the booth (Deadnight #1325). The walk from the lot's west
# side to the east midway's barricade stand runs along the booth's north wall, round the booth's
# north-east corner, and the post of the `booth` circuit (a `StaticBody3D`, so it is not in the
# walking mesh) stands on that line: the bot walks into its west face and stands. The stuck ladder
# climbs, and at its second rung repaths to a goal moved by up to 1.5 m, which can land behind the
# boards of the barricade: that goal is called unreachable, the bot is no longer commanded to walk,
# the ladder lets go of it, and the place the roam chose is never marked (the mark is on the moved
# goal's cell). The soak counted 16 of its 19 `idle under Roam over 8 s` breaks of 2026-11-05 at
# (4.8, 21.4).
#
# The test sets a roaming bot down west of the booth with the stand as its place, and reads that it
# never stands for the soak's 8 s, whatever the ladder's jitter draws.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
## Seeds of the bot's own stream: the ladder's jitter is drawn from it. Of 16 seeds (8 to 23) 13
## stood against the post to the end of the watch before the fix, 22.4 s at (4.85, 21.45), and none
## after it; the first, 8, walks round the post on its own, and 9 to 11 stood.
const SEEDS: Array[int] = [8, 9, 10, 11]
const NIGHT_SEED := 8
## Where the soak's bot came from (west of the booth, on the line to its corner), and the east
## midway's barricade stand, the place the roam chose.
const WEST := Vector3(-3.8, 0.1, 20.6)
const STAND := Vector3(12.5, 0.4, 31.6)
## Seconds the bot is watched, and the longest it may stand with the Roam note (the soak's gate).
const WATCH_SECONDS := 25.0
const GATE_SECONDS := 8.0
const STANDING := 0.05
const LONG_BREAK := 3000.0
const SETTLE_FRAMES := 60

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


func _night() -> SeatedNight:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await NightFixture.seat(self, 1, tuning, NIGHT_SEED)
	night.open_door(&"door_concession")
	night.open_door(&"door_booth")
	await night.settle(SETTLE_FRAMES)
	assert_bool(await night.settle_doors()).is_true()
	_catcher.start()
	return night


## The seconds the bot of `bot_seed` stood with the note of a bot with nothing to do, longest run,
## and where it was when the watch ended, from the west of the booth to the stand.
func _longest_stand(bot_seed: int) -> Array:
	var night := await _night()
	var bot := night.seat(1, BotProfile.regular(), bot_seed)
	var body := night.server.body_of(1)
	var brain := bot.brain as BotFightBrain
	body.teleport(WEST)
	night.run(2)
	brain._roam.spot = STAND
	var still := 0
	var longest := 0
	for _t in int(WATCH_SECONDS * TICKS_PER_SECOND):
		night.tick()
		var standing := Vector2(body.velocity.x, body.velocity.z).length() < STANDING
		var idle := standing and SoakWatch.IDLE_NOTES.has(bot.intent.note)
		still = still + 1 if idle else 0
		longest = maxi(longest, still)
	var at := body.global_position
	night.dispose()
	await get_tree().process_frame
	return [float(longest) / TICKS_PER_SECOND, at]


func test_a_roam_bot_walking_round_the_booths_corner_never_stands_for_the_gates_8_seconds() -> void:
	var worst := 0.0
	var worst_seed := -1
	for bot_seed in SEEDS:
		var seen := await _longest_stand(bot_seed)
		if float(seen[0]) > worst:
			worst = float(seen[0])
			worst_seed = bot_seed
	(
		assert_float(worst)
		. override_failure_message("the bot of seed %d stood %.1f s" % [worst_seed, worst])
		. is_less(GATE_SECONDS)
	)
	assert_array(_catcher.lines).is_empty()
