# The way back for a player who leaves the playable space (issue #862), the server's own rule: the
# real body of a player, a downed player and a bot is put past each wall of both maps (every door
# sold), and within a second the server has put it back on its start marker, at rest; nobody inside
# is touched, the rules' state (the ground, the bleed-out) is kept as it is, and the grace
# (`NightTuning.out_of_bounds_seconds`) is a real wait. `PlayBounds` is tested on its own in
# `tests/world/test_play_bounds.gd`, the client's side in `tests/net/test_out_of_bounds_online.gd`.
extends GdUnitTestSuite

const LOT := "res://world/drive_in_greybox.tscn"
const SMALL := "res://world/smallmap/smallmap_greybox.tscn"
const SEED := 11
const TICKS_PER_SECOND := 60
## The rule fires within this many seconds of a body being past a wall.
const WITHIN_SECONDS := 1.0
## How close to its start marker a returned body is, flat.
const AT_START := 0.3
## A step of a body longer than this (metres) in one tick is a move the server made.
const JUMP := 10.0
## One place past each wall of the lot: its north fence and aprons, both sides, the back lot and the
## yard, the road's sides and its end, the far corners.
const LOT_OUTSIDE: Array[Vector3] = [
	Vector3(0.0, 0.0, -57.0),
	Vector3(-36.0, 0.0, -64.0),
	Vector3(36.0, 0.0, -64.0),
	Vector3(-74.0, 0.0, -46.0),
	Vector3(74.0, 0.0, -46.0),
	Vector3(-66.0, 0.0, -34.0),
	Vector3(66.0, 0.0, -34.0),
	Vector3(-66.0, 0.0, 20.0),
	Vector3(66.0, 0.0, 20.0),
	Vector3(-40.0, 0.0, 42.0),
	Vector3(40.0, 0.0, 42.0),
	Vector3(20.0, 0.0, 50.0),
	Vector3(-20.0, 0.0, 50.0),
	Vector3(0.0, 0.0, 62.0),
	Vector3(120.0, 0.0, 120.0),
	Vector3(-120.0, 0.0, -120.0),
]
## The same for the second map: each side of its yard, a far corner and a fall.
const SMALL_OUTSIDE: Array[Vector3] = [
	Vector3(36.0, 0.5, 0.0),
	Vector3(-36.0, 0.5, 0.0),
	Vector3(0.0, 0.5, 32.0),
	Vector3(0.0, 0.5, -32.0),
	Vector3(90.0, 0.5, 90.0),
	Vector3(7.0, -30.0, 10.5),
]
## Places in the lot and in the second map where people play, none of them to be touched.
const LOT_INSIDE: Array[Vector3] = [
	Vector3(0.0, 0.1, -30.0),
	Vector3(-66.0, 0.1, -46.0),
	Vector3(66.0, 0.1, -46.0),
	Vector3(-40.0, 0.1, 20.0),
	Vector3(40.0, 0.1, 20.0),
	Vector3(0.0, 0.1, 5.0),
	Vector3(0.0, 0.1, 56.0),
	Vector3(61.0, 0.1, 37.0),
]
const SMALL_INSIDE: Array[Vector3] = [
	Vector3(7.0, 0.1, 10.5),
	Vector3(0.0, 0.1, 0.0),
	Vector3(-20.0, 0.1, 10.0),
	Vector3(20.0, 0.1, 21.0),
]

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


## A night on `scene_path` with `players` seated and every door sold, where no zombie comes for ten
## minutes: the rule is the only thing happening.
func _night(scene_path: String, players: int, bots := 0) -> SeatedNight:
	var scene := load(scene_path) as PackedScene
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	var night := await NightFixture.seat(self, players, tuning, SEED, false, scene)
	night.stand_still = true
	for id in range(players - bots + 1, players + 1):
		night.seat(id, BotProfile.regular(), SEED + id)
	for door in night.world.door_ids():
		night.open_door(door)
	await night.settle(30)
	night.server.rules.apply(RulesAction.skip_break())
	night.run(10)
	return night


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Runs `seconds` of ticks; returns the longest step the body made in one tick and the tick the
## body was put back on (0 when it never was).
func _watch(night: SeatedNight, id: int, seconds: float) -> Dictionary:
	var body := night.server.body_of(id)
	var biggest := 0.0
	var back_at := 0
	var was := body.global_position
	for tick in int(seconds * TICKS_PER_SECOND):
		night.tick()
		var now := body.global_position
		var step := was.distance_to(now)
		if step > biggest:
			biggest = step
			if step > JUMP:
				back_at = tick + 1
		was = now
	return {"biggest": biggest, "back_at": back_at}


func _start_of(night: SeatedNight, id: int) -> Vector3:
	return night.world.player_spawn(id - 1)


func _is_back(night: SeatedNight, id: int) -> bool:
	var body := night.server.body_of(id)
	return (
		_flat(body.global_position, _start_of(night, id)) < AT_START
		and not night.world.bounds.is_out(body.global_position)
	)


func _past_every_wall(scene_path: String, places: Array[Vector3]) -> void:
	var night := await _night(scene_path, 2)
	var missed: Array[String] = []
	for place in places:
		night.server.body_of(1).teleport(place)
		var seen := _watch(night, 1, WITHIN_SECONDS)
		if not _is_back(night, 1) or seen["back_at"] == 0:
			missed.append("%s ended at %s" % [place, night.server.body_of(1).global_position])
	assert_array(missed).override_failure_message("\n".join(missed)).is_empty()
	night.dispose()


func test_a_player_past_each_wall_of_the_lot_is_back_at_the_start_within_a_second() -> void:
	await _past_every_wall(LOT, LOT_OUTSIDE)


func test_a_player_past_each_wall_of_the_second_map_is_back_at_the_start_within_a_second() -> void:
	await _past_every_wall(SMALL, SMALL_OUTSIDE)


func test_the_rule_waits_its_grace_and_a_return_resets_the_wait() -> void:
	var night := await _night(LOT, 1)
	var grace := NightTuning.shipped().out_of_bounds_seconds
	var body := night.server.body_of(1)
	var out := Vector3(0.0, 0.0, -57.0)
	body.teleport(out)
	# Just short of the grace: still out there, not touched.
	for _i in int(grace * TICKS_PER_SECOND) - 6:
		night.tick()
	assert_bool(night.world.bounds.is_out(body.global_position)).is_true()
	# A step back in (a hop that came back on its own) starts the count again.
	body.teleport(Vector3(0.0, 0.1, -30.0))
	night.run(6)
	body.teleport(out)
	for _i in int(grace * TICKS_PER_SECOND) - 6:
		night.tick()
	assert_bool(night.world.bounds.is_out(body.global_position)).is_true()
	night.run(30)
	assert_bool(_is_back(night, 1)).is_true()
	night.dispose()


func test_nobody_inside_is_touched_in_either_map() -> void:
	for pair in [[LOT, LOT_INSIDE], [SMALL, SMALL_INSIDE]]:
		var places: Array[Vector3] = []
		places.assign(pair[1])
		var night := await _night(pair[0], 4)
		var held: Dictionary[int, Vector3] = {}
		for i in places.size():
			var id := 1 + i % 4
			night.server.body_of(id).teleport(places[i])
			night.run(2 * TICKS_PER_SECOND)
			held[id] = night.server.body_of(id).global_position
			assert_bool(night.world.bounds.is_out(held[id])).is_false()
			# Two more seconds with nothing sent: where it settled is where it stays.
			night.run(2 * TICKS_PER_SECOND)
			assert_float(night.server.body_of(id).global_position.distance_to(held[id])).is_less(
				0.01
			)
			# A prop may push a body a step aside; it is not sent to the start.
			(
				assert_float(_flat(held[id], places[i]))
				. override_failure_message("%s moved to %s" % [places[i], held[id]])
				. is_less(1.0)
			)
		night.dispose()


func test_a_downed_player_is_returned_and_stays_downed_with_the_bleed_running() -> void:
	var night := await _night(LOT, 3)
	var rules := night.server.rules
	rules.apply(RulesAction.blow(2, 99999.0))
	assert_bool(rules.players[2].downed).is_true()
	night.run(30)
	var bleed := rules.bleed_left_of(2)
	night.server.body_of(2).teleport(Vector3(66.0, 0.0, 20.0))
	_watch(night, 2, WITHIN_SECONDS)
	assert_bool(_is_back(night, 2)).is_true()
	assert_bool(rules.players[2].downed).is_true()
	assert_bool(rules.is_dead(2)).is_false()
	# The bleed-out kept running: it was neither reset nor stopped by the move.
	assert_float(rules.bleed_left_of(2)).is_less(bleed)
	assert_float(rules.bleed_left_of(2)).is_greater(0.0)
	# The others are where they were.
	assert_bool(_is_back(night, 1)).is_true()
	night.dispose()


func test_a_standing_player_keeps_their_health_and_a_bot_is_returned_like_a_person() -> void:
	var night := await _night(LOT, 3, 1)
	var rules := night.server.rules
	var health := rules.health_of(1)
	night.server.body_of(1).teleport(Vector3(-66.0, 0.0, 20.0))
	night.server.body_of(3).teleport(Vector3(66.0, 0.0, 20.0))
	# Two seconds: the bot may walk (it is a bot) but it is back at the start, not on the far slab.
	var seen := _watch(night, 3, 2.0)
	assert_int(seen["back_at"]).is_greater(0)
	assert_bool(night.world.bounds.is_out(night.server.body_of(3).global_position)).is_false()
	assert_bool(night.world.bounds.is_out(night.server.body_of(1).global_position)).is_false()
	assert_bool(_is_back(night, 1)).is_true()
	assert_float(rules.health_of(1)).is_equal(health)
	assert_bool(rules.players[1].downed).is_false()
	night.dispose()


func test_the_second_player_is_returned_to_their_own_marker() -> void:
	var night := await _night(LOT, 3)
	night.server.body_of(2).teleport(Vector3(0.0, 0.0, -57.0))
	_watch(night, 2, WITHIN_SECONDS)
	assert_vector(night.server.body_of(2).global_position).is_equal_approx(
		night.world.player_spawn(1), Vector3(AT_START, 0.5, AT_START)
	)
	assert_bool(_flat(night.world.player_spawn(1), night.world.player_spawn(0)) > 1.0).is_true()
	night.dispose()
