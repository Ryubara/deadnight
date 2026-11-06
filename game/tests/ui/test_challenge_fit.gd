extends GdUnitTestSuite
## Where the challenge prompt's card stands (`ChallengeFit`, #1299): its usual place when nothing is
## in the way, the nearest free place beside it when something is, narrower when the ground is,
## and the least bad place when there is none.

const ROOM := Rect2(0.0, 0.0, 800.0, 600.0)
const WIDTHS: Array[float] = [300.0, 250.0, 200.0]
const LEFTS: Array[float] = [40.0, 360.0]


func _height(width: float) -> float:
	# A narrower card has one more line.
	return 100.0 if width >= 300.0 else 130.0


func _place(hard: Array[Rect2], soft: Array[Rect2] = []) -> Rect2:
	return ChallengeFit.place(ROOM, 300.0, LEFTS, WIDTHS, _height, hard, soft)


func test_the_usual_place_when_nothing_is_in_the_way() -> void:
	assert_that(_place([])).is_equal(Rect2(40.0, 300.0, 300.0, 100.0))


func test_a_column_grown_up_to_the_card_sends_it_beside_the_column() -> void:
	var column: Array[Rect2] = [Rect2(0.0, 350.0, 340.0, 250.0)]
	var found := _place(column)
	assert_that(found).is_equal(Rect2(360.0, 300.0, 300.0, 100.0))
	assert_bool(found.intersects(column[0])).is_false()


func test_a_narrow_ground_takes_a_narrower_card_that_is_taller() -> void:
	var column: Array[Rect2] = [Rect2(0.0, 350.0, 340.0, 250.0), Rect2(580.0, 0.0, 220.0, 600.0)]
	var found := _place(column)
	assert_float(found.size.x).is_equal(200.0)
	assert_float(found.size.y).is_equal(130.0)
	for box in column:
		assert_bool(found.intersects(box)).is_false()


func test_the_nearest_height_wins_and_a_place_below_comes_before_one_above() -> void:
	# Free only from 340 down and from 260 up: both 40 away, below first.
	var block: Array[Rect2] = [
		Rect2(0.0, 0.0, 800.0, 340.0 - 100.0 - 1.0), Rect2(0.0, 300.0, 340.0, 50.0)
	]
	var found := ChallengeFit.place(
		ROOM, 300.0, [40.0] as Array[float], [300.0] as Array[float], _height, block, []
	)
	assert_bool(found.intersects(block[0])).is_false()
	assert_bool(found.intersects(block[1])).is_false()
	assert_float(found.position.y).is_greater_equal(350.0)


func test_what_comes_and_goes_is_kept_off_while_there_is_room_and_met_when_there_is_none() -> void:
	var hard: Array[Rect2] = [Rect2(0.0, 340.0, 340.0, 260.0), Rect2(340.0, 0.0, 460.0, 600.0)]
	# With one soft box over the only free band of hard-clear ground, the card has no place that
	# misses both: it takes the one that misses the hard boxes and meets the soft one.
	var soft: Array[Rect2] = [Rect2(0.0, 0.0, 340.0, 300.0)]
	var found := _place(hard, soft)
	for box in hard:
		assert_bool(found.intersects(box)).is_false()
	assert_bool(found.intersects(soft[0])).is_true()


func test_with_no_place_at_all_it_stays_where_it_always_stood() -> void:
	var wall: Array[Rect2] = [ROOM]
	assert_that(_place(wall)).is_equal(Rect2(40.0, 300.0, 300.0, 100.0))
