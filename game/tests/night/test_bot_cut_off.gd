# The scrap of mesh a Rookie was cut off on (Deadnight #1041). A piece next to the west midway's
# boards (the polygons across a barricade's line are the dead's alone, `NavmeshSplit`) was joined to
# nothing: a path from there ended two metres on. A Rookie in the soak stepped out of another bot's
# way onto it and stood there for minutes, every place it asked about "unreachable" (and banned, for
# ten minutes), the break going by under `idle under Roam over 8 s`.
#
# #1051 took the piece off the walking mesh, so a path from there now starts on walking ground and
# the bot is no longer cut off here: `BotRoam`'s walk back is tested in `test_bot_roam.gd`. The test
# still sets a roaming bot down beside the spot, lets it choose a place, puts it on the spot (the
# step aside), and reads that it is walking again, off the spot, within seconds.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SEED := 8
## Where the piece of mesh was, and a point of the main mesh a metre or two from it.
const CUT_OFF := Vector3(-14.3, 0.0, 31.6)
const BESIDE := Vector3(-12.6, 0.0, 30.6)
## Ticks the bot is given to choose a place from beside the spot, and seconds to get off it.
const CHOOSE_TICKS := 20
const GET_OUT_SECONDS := 15.0
## Metres from the spot at which a bot counts as out of it.
const OUT := 4.0
## Metres a path may end short of the point it is asked about and still reach it.
const EXACT_SHORT := 0.5
const LONG_BREAK := 3000.0
const SETTLE_FRAMES := 60

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


func _night() -> SeatedNight:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await NightFixture.seat(self, 1, tuning, SEED)
	night.open_door(&"door_concession")
	await night.settle(SETTLE_FRAMES)
	assert_bool(await night.settle_doors()).is_true()
	_catcher.start()
	return night


func test_a_bot_on_the_scrap_by_the_boards_walks_off_it() -> void:
	var night := await _night()
	var bot := night.seat(1, BotProfile.rookie(), SEED + 1)
	var body := night.server.body_of(1)
	var path := bot.legs.path
	# Nothing cuts the spot off any more: the walk from it reaches the ground a metre or two away.
	assert_bool(path.probe(CUT_OFF, BESIDE, 0.0, EXACT_SHORT)).is_true()
	body.teleport(BESIDE + Vector3(0.0, 0.1, 0.0))
	night.run(CHOOSE_TICKS)
	body.teleport(CUT_OFF + Vector3(0.0, 0.1, 0.0))
	var longest_still := 0
	var still := 0
	var last := body.global_position
	for _t in int(GET_OUT_SECONDS * TICKS_PER_SECOND):
		night.tick()
		var moved := Vector2(body.global_position.x - last.x, body.global_position.z - last.z)
		still = still + 1 if moved.length() < 0.005 else 0
		longest_still = maxi(longest_still, still)
		last = body.global_position
	var at := body.global_position
	var apart := Vector2(at.x - CUT_OFF.x, at.z - CUT_OFF.z).length()
	(
		assert_float(apart)
		. override_failure_message("the bot is still on the spot, at %s" % at)
		. is_greater(OUT)
	)
	# It never stood for the 8 s of the soak's gate (a look about at a place lasts 2 to 5 s).
	assert_int(longest_still).is_less(int(8.0 * TICKS_PER_SECOND))
	assert_array(_catcher.lines).is_empty()
	night.dispose()
	await get_tree().process_frame
