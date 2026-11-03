# A bot's way over the lot with every set of doors the shop can have sold (bots plan, phase 2): the
# opening-order test's areas, asked through `BotPath` over the mesh the game itself swaps in when a
# door opens. An area a door opens is reached, an area it keeps shut is marked unreachable (no path
# into it, no question asked twice), and the engine prints no navigation error on the way.
extends GdUnitTestSuite

const SEED := 61
## Most physics frames the test waits for the map to answer over the doors' mesh. The map takes a
## new mesh in on worker threads, so how many frames that needs depends on how busy the machine
## is (a fixed number of frames failed about one run in three: the first area the doors open was
## still answered as shut): the test waits for the answer itself, as the zombies' bake test does,
## and not for a count of frames.
const SETTLE_MAX := 1200
## Metres from its sample that a path to an open area may end.
const REACHED := 1.0

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


func test_the_map_does_not_answer_for_a_door_the_frame_it_is_bought() -> void:
	# What the other test waits for is real: the mesh a door swaps in reaches the map over the
	# next physics frames, so a path asked at once still takes the doors as shut.
	var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), SEED)
	var sold := ["door_concession"]
	assert_bool(_answers_for_open_areas(night.world.map(), sold)).is_false()
	night.open_door(&"door_concession")
	assert_bool(_answers_for_open_areas(night.world.map(), sold)).is_false()
	await _wait_for_the_doors_mesh(night, sold)
	assert_bool(_answers_for_open_areas(night.world.map(), sold)).is_true()
	night.dispose()
	await get_tree().process_frame


func test_a_bot_reaches_every_area_its_doors_open_and_marks_the_others() -> void:
	var sets := LotFixture.sold_sets()
	assert_int(sets.size()).is_equal(9)
	_catcher.start()
	for sold: Array in sets:
		var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), SEED)
		for door in LotFixture.in_buying_order(sold):
			night.open_door(door)
		await _wait_for_the_doors_mesh(night, sold)
		var path := BotPath.new(night.world.map(), night.level)
		var clock := 0.0
		for area: String in LotFixture.AREA_POINTS:
			for point: Vector3 in LotFixture.AREA_POINTS[area]:
				clock += 1.0
				path.forget()
				var status := path.ask(LotFixture.START, point, clock)
				var message := "sold %s, area %s at %s: status %d" % [sold, area, point, status]
				if LotFixture.is_open(area, sold):
					assert_int(status).override_failure_message(message).is_equal(BotPath.Status.OK)
					if path.points.is_empty():
						continue
					var end := path.points[path.points.size() - 1]
					assert_float(Vector2(end.x - point.x, end.z - point.z).length()).is_less(
						REACHED
					)
				else:
					assert_int(status).override_failure_message(message).is_equal(
						BotPath.Status.UNREACHABLE
					)
					assert_bool(path.is_blocked(point, clock)).is_true()
		assert_int(path.empty_answers).is_equal(0)
		night.dispose()
		await get_tree().process_frame
	assert_array(_catcher.lines).is_empty()


## Gives the engine physics frames until the map answers for every area `sold` opens: a path from
## the start to the area's first sample ends within `REACHED` of it. The last door's mesh is the
## only one that opens the last door's area, so an answer for every open area means the map has
## taken the mesh of all of them in (a door only ever opens more). Returns the frames waited, and
## fails the test when the map never answers.
func _wait_for_the_doors_mesh(night: SeatedNight, sold: Array) -> int:
	var map := night.world.map()
	for frames in SETTLE_MAX:
		if not night.world.navigation.is_busy() and _answers_for_open_areas(map, sold):
			return frames
		await get_tree().physics_frame
	(
		assert_bool(false)
		. override_failure_message(
			"the map never answered for the areas %s open in %d frames" % [sold, SETTLE_MAX]
		)
		. is_true()
	)
	return SETTLE_MAX


func _answers_for_open_areas(map: RID, sold: Array) -> bool:
	if NavigationServer3D.map_get_iteration_id(map) < 1:
		return false
	var start := NavigationServer3D.map_get_closest_point(map, LotFixture.START)
	for area: String in LotFixture.AREA_POINTS:
		if not LotFixture.is_open(area, sold):
			continue
		var point: Vector3 = LotFixture.AREA_POINTS[area][0]
		var found := NavigationServer3D.map_get_path(map, start, point, true)
		if found.is_empty():
			return false
		var end := found[found.size() - 1]
		if Vector2(end.x - point.x, end.z - point.z).length() >= REACHED:
			return false
	return true
