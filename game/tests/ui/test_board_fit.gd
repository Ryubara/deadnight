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
	assert_float(found[&"drop"]).is_equal(0.0)


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
	var found := BoardFit.fit(
		ROOM, TICKET, [_box(1100.0, 200.0, 100.0, 700.0), _box(400.0, 200.0, 100.0, 700.0)]
	)
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
	var found := BoardFit.fit(
		ROOM, TICKET, [_box(1000.0, 200.0, 100.0, 700.0), _box(800.0, 200.0, 100.0, 700.0)]
	)
	assert_float(found[&"scale"]).is_equal_approx(BoardFit.SMALLEST, 0.001)


func test_a_ticket_taller_than_the_room_is_made_smaller_to_the_page() -> void:
	var found := BoardFit.fit(ROOM, Vector2(896.0, 1300.0), [])
	assert_float(1300.0 * float(found[&"scale"])).is_less_equal(1080.0)


func test_a_box_beside_the_room_s_middle_is_a_left_or_a_right_one_by_its_own_middle() -> void:
	# A box that straddles the middle is a left one when its middle is: its right edge bounds it.
	var found := BoardFit.fit(ROOM, TICKET, [_box(900.0, 200.0, 100.0, 700.0)])
	var edges := _edges(found, TICKET)
	assert_float(edges.x).is_greater_equal(1000.0 + BoardFit.GAP - 0.01)


## The ticket's rectangle for a fit: along by `shift`, down by `drop`, `scale` of its size, about
## the middle of ROOM.
func _card(found: Dictionary, size: Vector2) -> Rect2:
	var shown := size * float(found[&"scale"])
	var middle := ROOM.get_center() + Vector2(float(found[&"shift"]), float(found[&"drop"]))
	return Rect2(middle - shown * 0.5, shown)


func test_a_button_beside_its_top_rows_moves_it_down_when_that_clears_it() -> void:
	# Ping under Pause: a small button on the left at the ticket's top rows, with a tall column
	# below it and a button on the right, so that the strip is a hair too narrow where it is.
	var ping := _box(400.0, 300.0, 100.0, 100.0)
	var column := _box(36.0, 400.0, 316.0, 400.0)
	var right := _box(1300.0, 200.0, 100.0, 700.0)
	var avoid: Array[Rect2] = [ping, column, right]
	var found := BoardFit.fit(ROOM, TICKET, avoid)
	assert_float(found[&"scale"]).is_equal(1.0)
	assert_float(found[&"drop"]).is_greater(0.0)
	var card := _card(found, TICKET)
	assert_float(card.position.y).is_equal_approx(ping.end.y + BoardFit.GAP + BoardFit.EDGE, 0.01)
	for box in avoid:
		assert_bool(card.grow(BoardFit.GAP - 0.01).intersects(box)).is_false()
	assert_bool(ROOM.encloses(card)).is_true()


func test_it_stands_where_it_is_when_moving_up_or_down_would_not_help() -> void:
	var tall := _box(400.0, 200.0, 100.0, 700.0)
	var found := BoardFit.fit(ROOM, TICKET, [tall, _box(1300.0, 200.0, 100.0, 700.0)])
	assert_float(found[&"drop"]).is_equal(0.0)
	assert_float(found[&"scale"]).is_less(1.0)


func test_a_ticket_that_moves_takes_the_place_nearest_the_middle_and_stays_in_the_room() -> void:
	# Boxes in the way up and down the strip of its rows: above and below both clear them, the
	# one below is a shorter way.
	var avoid: Array[Rect2] = [_box(400.0, 100.0, 100.0, 440.0), _box(1300.0, 200.0, 100.0, 700.0)]
	var found := BoardFit.fit(ROOM, TICKET, avoid)
	var card := _card(found, TICKET)
	assert_bool(ROOM.encloses(card)).is_true()
	assert_float(absf(float(found[&"drop"]))).is_less(300.0)
	for box in avoid:
		assert_bool(card.grow(BoardFit.GAP - 0.01).intersects(box)).is_false()


func test_the_full_room_on_the_smallest_page_is_readable_with_ping_under_pause() -> void:
	# The 667 x 375 page at the biggest interface size, the right hand, a full room (measured
	# in the touch suite): the ticket is 896 x 838 in a room of 1537 x 864, and Ping stands
	# in its top rows beside the column.
	var room := Rect2(0.0, 0.0, 1536.768, 864.0)
	var ticket := Vector2(896.0, 838.0)
	var avoid: Array[Rect2] = [
		Rect2(1231.768, 414.0, 200.0, 200.0),
		Rect2(1059.768, 419.0, 132.0, 132.0),
		Rect2(1139.768, 265.0, 144.0, 144.0),
		Rect2(1312.768, 238.0, 140.0, 140.0),
		Rect2(1113.768, 583.0, 124.0, 124.0),
		Rect2(943.768, 144.0, 96.0, 96.0),
		Rect2(1432.768, 510.0, 88.0, 88.0),
		Rect2(1436.768, 419.0, 80.0, 80.0),
		Rect2(406.0, 44.0, 72.0, 72.0),
		Rect2(406.0, 194.0, 72.0, 72.0),
		Rect2(36.0, 726.0, 128.0, 102.0),
		Rect2(170.0, 726.0, 128.0, 102.0),
		Rect2(304.0, 726.0, 102.0, 102.0),
		Rect2(36.0, 242.0, 316.0, 397.0),
	]
	var found := BoardFit.fit(room, ticket, avoid)
	assert_float(found[&"scale"]).is_greater_equal(0.6)
	var shown := ticket * float(found[&"scale"])
	var middle := room.get_center() + Vector2(float(found[&"shift"]), float(found[&"drop"]))
	var card := Rect2(middle - shown * 0.5, shown)
	assert_bool(room.encloses(card)).is_true()
	for box in avoid:
		assert_bool(card.grow(BoardFit.GAP - 0.01).intersects(box)).is_false()


func test_a_button_in_the_middle_of_its_rows_leaves_the_least_step_and_is_still_cleared() -> void:
	# The same room with Strike up (a box 910 to 1014 across and 472 to 576 down): the strip
	# between the column and Strike is 510 wide, Ping and the weapon strip take the rest of the
	# page's height, so the ticket is at the least step, and clear of every box.
	var room := Rect2(0.0, 0.0, 1536.768, 864.0)
	var ticket := Vector2(896.0, 838.0)
	var avoid: Array[Rect2] = [
		Rect2(909.768, 472.0, 104.0, 104.0),
		Rect2(1231.768, 414.0, 200.0, 200.0),
		Rect2(1059.768, 419.0, 132.0, 132.0),
		Rect2(1139.768, 265.0, 144.0, 144.0),
		Rect2(1312.768, 238.0, 140.0, 140.0),
		Rect2(1113.768, 583.0, 124.0, 124.0),
		Rect2(943.768, 144.0, 96.0, 96.0),
		Rect2(1436.768, 419.0, 80.0, 80.0),
		Rect2(406.0, 44.0, 72.0, 72.0),
		Rect2(406.0, 194.0, 72.0, 72.0),
		Rect2(36.0, 726.0, 128.0, 102.0),
		Rect2(170.0, 726.0, 128.0, 102.0),
		Rect2(304.0, 726.0, 102.0, 102.0),
		Rect2(36.0, 242.0, 316.0, 397.0),
	]
	var found := BoardFit.fit(room, ticket, avoid)
	assert_float(found[&"scale"]).is_equal_approx(BoardFit.SMALLEST, 0.001)
	var shown := ticket * float(found[&"scale"])
	var middle := room.get_center() + Vector2(float(found[&"shift"]), float(found[&"drop"]))
	var card := Rect2(middle - shown * 0.5, shown)
	assert_bool(room.encloses(card)).is_true()
	for box in avoid:
		assert_bool(card.grow(BoardFit.GAP - 0.01).intersects(box)).is_false()
