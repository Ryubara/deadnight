extends GdUnitTestSuite
## Where the scoreboard's ticket stands among the touch buttons (`BoardFit`, Deadnight #1287): where
## it is when nothing is under it, along the screen when something is, smaller when that is not
## enough, never smaller than the least, and the other way for a left hand.

const ROOM := Rect2(0.0, 0.0, 1920.0, 1080.0)
## 340 to 740 up and down in the middle of ROOM, 896 wide.
const TICKET := Vector2(896.0, 400.0)


func _box(x: float, y: float, w := 100.0, h := 100.0) -> Rect2:
	return Rect2(x, y, w, h)


## The ticket's left and right edge for a fit.
func _edges(found: Dictionary, size: Vector2) -> Vector2:
	var middle := ROOM.get_center().x + float(found[&"shift"])
	var wide := size.x * float(found[&"scale"])
	return Vector2(middle - wide * 0.5, middle + wide * 0.5)


func test_a_clear_middle_keeps_the_ticket_whole_in_the_middle() -> void:
	var found := BoardFit.fit(ROOM, TICKET, [_box(1700.0, 500.0), _box(36.0, 900.0)])
	assert_float(found[&"scale"]).is_equal(1.0)
	assert_float(found[&"shift"]).is_equal(0.0)


func test_a_button_on_the_right_moves_it_left_and_one_on_the_left_moves_it_right() -> void:
	var right := BoardFit.fit(ROOM, TICKET, [_box(1300.0, 500.0)])
	assert_float(right[&"scale"]).is_equal(1.0)
	# Its right edge is a gap short of the button.
	assert_float(_edges(right, TICKET).y).is_equal_approx(1300.0 - BoardFit.GAP, 0.01)
	var left := BoardFit.fit(ROOM, TICKET, [_box(400.0, 500.0)])
	assert_float(left[&"scale"]).is_equal(1.0)
	assert_float(_edges(left, TICKET).x).is_equal_approx(500.0 + BoardFit.GAP, 0.01)


func test_boxes_above_or_below_its_rows_do_not_count() -> void:
	var found := BoardFit.fit(ROOM, TICKET, [_box(1300.0, 100.0), _box(1300.0, 900.0)])
	assert_float(found[&"scale"]).is_equal(1.0)
	assert_float(found[&"shift"]).is_equal(0.0)


func test_a_strip_too_narrow_makes_it_the_largest_step_that_fits() -> void:
	var found := BoardFit.fit(ROOM, TICKET, [_box(1100.0, 500.0), _box(400.0, 500.0)])
	var strip := (1100.0 - BoardFit.GAP) - (500.0 + BoardFit.GAP)
	var shown := TICKET.x * float(found[&"scale"])
	assert_float(shown).is_less(TICKET.x)
	assert_float(shown).is_less_equal(strip)
	# One step more would have been too wide for it.
	assert_float(TICKET.x * (float(found[&"scale"]) + BoardFit.STEP)).is_greater(strip)
	var edges := _edges(found, TICKET)
	assert_float(edges.x).is_greater_equal(500.0 + BoardFit.GAP - 0.01)
	assert_float(edges.y).is_less_equal(1100.0 - BoardFit.GAP + 0.01)


func test_it_is_never_smaller_than_the_least() -> void:
	var found := BoardFit.fit(ROOM, TICKET, [_box(1000.0, 500.0), _box(800.0, 500.0)])
	assert_float(found[&"scale"]).is_equal_approx(BoardFit.SMALLEST, 0.001)


func test_a_ticket_taller_than_the_room_is_made_smaller_to_the_page() -> void:
	var found := BoardFit.fit(ROOM, Vector2(896.0, 1300.0), [])
	assert_float(1300.0 * float(found[&"scale"])).is_less_equal(1080.0)


func test_a_box_beside_the_room_s_middle_is_a_left_or_a_right_one_by_its_own_middle() -> void:
	# A box that straddles the middle is a left one when its middle is: its right edge bounds it.
	var found := BoardFit.fit(ROOM, TICKET, [_box(900.0, 500.0, 100.0, 100.0)])
	var edges := _edges(found, TICKET)
	assert_float(edges.x).is_greater_equal(1000.0 + BoardFit.GAP - 0.01)
