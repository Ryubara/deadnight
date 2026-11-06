# A Roam bot that stood for good in the corner of the west midway (Deadnight #1339). The soak's
# `idle under Roam over 8 s` samples of 2026-11-05 and 06 put a bot at (-15.4, 32.4): 0.4 m from the
# pocket's wall (z 32.8) and 0.4 m from the fence (x -15.8), by the jamb of the window of `mid_w`.
#
# How it got there, from a night on `main` (veteran, 4 bots, round 8): the bot walked to the
# barricade's stand (-12.5, 31.6), looked about there, and was walked west along the wall at a run
# by the step a bot makes out of a person's, or a lower seat's, way (`BotLegs._give_way`, 0.6 s of a
# heading chosen by `BotSteering`): the heading's end, 2.5 m on at (-14.8, 32.3), is on a scrap of
# the walking mesh that only the dead walk (`NavmeshSplit`, #1051) and `BotLevel.project` finds the
# nearest point of the whole mesh, so the scrap counted as mesh.
# Why it stayed: a path asked from the scrap starts on the nearest walking ground, and that lies
# across the wall (first point (-15.0, 33.7)); the bot is walked into the wall, the ladder only
# drops its goals, and the next goal starts the same way, for as long as the night goes on.
#
# The tests stand for both halves: a person walks at a bot at the stand (the bot must not be
# stepped onto the scrap), and a bot set down in the corner (it must walk out).
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const NIGHT_SEED := 8
const LONG_BREAK := 3000.0
const SETTLE_FRAMES := 60
const DOORS: Array[StringName] = [
	&"door_concession", &"door_booth", &"door_back_lot", &"door_yard", &"door_road"
]
## The corner the soak's samples stood in, and the stand of `mid_w`'s barricade.
const CORNER := Vector3(-15.4, 0.1, 32.4)
const STAND := Vector3(-12.3, 0.1, 32.3)
## Where the person who walks at the bot starts: east of the stand, along the pocket's wall.
const PERSON_FROM := Vector3(-6.0, 0.1, 32.3)
## The corner as a box on the ground: x -15.9 to -14.6, z 31.4 to 32.9.
const CORNER_BOX := Rect2(-15.9, 31.4, 1.3, 1.5)
## Roam places the bot set down in the corner is sent to: all on ground the walking mesh holds.
const PLACES: Array[Vector3] = [
	Vector3(-12.5, 0.4, 20.0), Vector3(0.0, 0.4, 36.5), Vector3(-24.0, 0.4, 19.1)
]
const BOT_SEEDS: Array[int] = [9, 10, 11]
## Seconds the bot is given to walk out, and the metres from the corner that count as out.
const OUT_SECONDS := 5.0
const OUT_METRES := 3.0
## Seconds the bot is watched after a person has walked at it, and the longest it may spend in the
## corner (it has no business there at all; the soak's gate is 8 s of standing anywhere).
const WATCH_SECONDS := 20.0
const IN_THE_CORNER_SECONDS := 1.0

var _catcher := ErrorCatcher.new()
var _night: SeatedNight


func after_test() -> void:
	_catcher.stop()
	if _night != null:
		_night.dispose()
		_night = null
		await get_tree().process_frame


func _seat(players: int) -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	_night = await NightFixture.seat(self, players, tuning, NIGHT_SEED)
	for door in DOORS:
		_night.open_door(door)
	await _night.settle(SETTLE_FRAMES)
	assert_bool(await _night.settle_doors()).is_true()
	_catcher.start()


func _in_corner(at: Vector3) -> bool:
	return CORNER_BOX.has_point(Vector2(at.x, at.z))


## Metres from `at` to the nearest point of the walking mesh the bot can walk (a path starts there).
func _off_the_walking_ground(at: Vector3) -> float:
	var map := _night.world.map()
	var near := NavigationServer3D.map_get_closest_point(map, at)
	var owner := NavigationServer3D.map_get_closest_point_owner(map, at)
	if NavigationServer3D.region_get_navigation_layers(owner) & NavLayers.WALK == 0:
		return INF
	return Vector2(near.x - at.x, near.z - at.z).length()


func test_the_corner_is_not_walking_ground() -> void:
	# What the rest rests on: the corner is a place the walking mesh leaves out, so the checks
	# below read the lot as it is.
	await _seat(1)
	assert_float(_off_the_walking_ground(CORNER)).is_equal(INF)
	assert_bool(_night.level.on_walking_ground(_night.level.project(CORNER))).is_false()


func test_a_bot_set_down_in_the_corner_walks_out_whatever_its_place() -> void:
	await _seat(1)
	var body := _night.server.body_of(1)
	var worst := 0.0
	var worst_case := ""
	for place in PLACES:
		for bot_seed in BOT_SEEDS:
			var bot := _night.seat(1, BotProfile.regular(), bot_seed)
			var brain := bot.brain as BotFightBrain
			body.teleport(CORNER)
			_night.run(2)
			brain._roam.spot = place
			var out := -1.0
			for t in int(OUT_SECONDS * TICKS_PER_SECOND):
				_night.tick()
				if (
					(
						Vector2(
							body.global_position.x - CORNER.x, body.global_position.z - CORNER.z
						)
						. length()
					)
					>= OUT_METRES
				):
					out = float(t) / TICKS_PER_SECOND
					break
			var seen := OUT_SECONDS if out < 0.0 else out
			if seen > worst:
				worst = seen
				worst_case = "place %s seed %d at %s" % [place, bot_seed, body.global_position]
			_night.host.release(1)
	(
		assert_float(worst)
		. override_failure_message(
			"a bot did not walk %.0f m out in %.0f s: %s" % [OUT_METRES, OUT_SECONDS, worst_case]
		)
		. is_less(OUT_SECONDS)
	)
	assert_array(_catcher.lines).is_empty()


## A person walks east to west along the pocket's wall at a bot that looks about at the stand; the
## bot gives way. Returns the seconds the bot spent in the corner and where it was at the end.
func _seconds_in_the_corner(bot_seed: int) -> Array:
	var body := _night.server.body_of(1)
	var bot := _night.seat(1, BotProfile.regular(), bot_seed)
	var person := _night.human(2)
	body.teleport(STAND)
	_night.server.body_of(2).teleport(PERSON_FROM)
	_night.run(2)
	(bot.brain as BotFightBrain)._roam.spot = STAND
	person.goto(STAND + Vector3(0.0, 0.0, 0.2))
	var ticks := 0
	for _t in int(WATCH_SECONDS * TICKS_PER_SECOND):
		person.tick()
		_night.tick()
		if person.arrived():
			person.stop()
		ticks += 1 if _in_corner(body.global_position) else 0
	return [float(ticks) / TICKS_PER_SECOND, body.global_position]


func test_a_bot_that_gives_way_to_a_person_at_the_stand_is_not_stepped_into_the_corner() -> void:
	await _seat(2)
	var worst := 0.0
	var where := Vector3.ZERO
	for bot_seed in BOT_SEEDS:
		var seen := await _seconds_in_the_corner(bot_seed)
		if float(seen[0]) > worst:
			worst = float(seen[0])
			where = seen[1]
		_night.host.release(1)
	(
		assert_float(worst)
		. override_failure_message("a bot spent %.1f s in the corner, at %s" % [worst, where])
		. is_less(IN_THE_CORNER_SECONDS)
	)
	assert_array(_catcher.lines).is_empty()
