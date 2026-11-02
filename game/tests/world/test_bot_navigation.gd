# A bot's way over the lot with every set of doors the shop can have sold (bots plan, phase 2): the
# opening-order test's areas, asked through `BotPath` over the mesh the game itself swaps in when a
# door opens. An area a door opens is reached, an area it keeps shut is marked unreachable (no path
# into it, no question asked twice), and the engine prints no navigation error on the way.
extends GdUnitTestSuite

const SEED := 61
## Frames the engine is given to take a new mesh in after a door.
const SETTLE := 12
## Metres from its sample that a path to an open area may end.
const REACHED := 1.0

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


func test_a_bot_reaches_every_area_its_doors_open_and_marks_the_others() -> void:
	var sets := LotFixture.sold_sets()
	assert_int(sets.size()).is_equal(9)
	_catcher.start()
	for sold: Array in sets:
		var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), SEED)
		for door in LotFixture.in_buying_order(sold):
			night.open_door(door)
		await night.settle(SETTLE)
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
