# The bot command wheel's model (#642), stepped by hand: when it opens, which entry a direction
# picks, what a release gives, and what a tap, the middle and a cancel give.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0


func _hold_open(wheel: BotWheel) -> void:
	wheel.press()
	for _i in roundi(BotWheel.OPEN_AFTER / STEP) + 2:
		wheel.advance(STEP)


func test_every_direction_picks_the_entry_standing_that_way() -> void:
	assert_str(BotWheel.entry_at(Vector2(0.0, -1.0))).is_equal(BotWheel.FOLLOW)
	assert_str(BotWheel.entry_at(Vector2(0.9, 0.5))).is_equal(BotWheel.ROAM)
	assert_str(BotWheel.entry_at(Vector2(-0.9, 0.5))).is_equal(BotWheel.HOLD)
	for order in BotWheel.ORDERS:
		assert_str(BotWheel.entry_at(BotWheel.direction_of(order))).is_equal(order)


func test_a_sector_is_a_third_of_the_circle_and_no_direction_is_left_out() -> void:
	var seen := {}
	for degrees in range(0, 360, 3):
		var at := Vector2.from_angle(deg_to_rad(float(degrees))) * 0.9
		var order := BotWheel.entry_at(at)
		assert_str(order).is_not_equal("")
		seen[order] = int(seen.get(order, 0)) + 1
	assert_array(seen.keys()).contains_exactly_in_any_order(BotWheel.ORDERS)
	for order in BotWheel.ORDERS:
		assert_int(seen[order]).is_between(38, 42)


func test_the_middle_picks_nothing() -> void:
	assert_str(BotWheel.entry_at(Vector2.ZERO)).is_equal("")
	assert_str(BotWheel.entry_at(Vector2(0.0, -BotWheel.CENTRE * 0.9))).is_equal("")
	assert_str(BotWheel.entry_at(Vector2(0.0, -BotWheel.CENTRE * 1.1))).is_equal(BotWheel.FOLLOW)


func test_it_opens_only_after_it_has_been_held() -> void:
	var wheel := BotWheel.new()
	wheel.press()
	wheel.advance(BotWheel.OPEN_AFTER * 0.5)
	assert_bool(wheel.is_holding()).is_true()
	assert_bool(wheel.is_open()).is_false()
	wheel.advance(BotWheel.OPEN_AFTER)
	assert_bool(wheel.is_open()).is_true()


func test_a_tap_gives_nothing_even_with_the_pointer_out() -> void:
	var wheel := BotWheel.new()
	wheel.press()
	wheel.advance(BotWheel.OPEN_AFTER * 0.5)
	wheel.point_at(Vector2(0.0, -1.0))
	assert_str(wheel.release()).is_equal("")
	assert_str(wheel.current).is_equal(BotWheel.DEFAULT_ORDER)


func test_letting_go_on_an_entry_gives_it_and_it_stands() -> void:
	for order in BotWheel.ORDERS:
		var wheel := BotWheel.new()
		_hold_open(wheel)
		wheel.point_at(BotWheel.direction_of(order))
		assert_str(wheel.hovered()).is_equal(order)
		assert_str(wheel.release()).is_equal(order)
		assert_str(wheel.current).is_equal(order)
		assert_bool(wheel.is_holding()).is_false()


func test_letting_go_in_the_middle_or_cancelling_gives_nothing() -> void:
	var wheel := BotWheel.new()
	_hold_open(wheel)
	assert_str(wheel.release()).is_equal("")
	_hold_open(wheel)
	wheel.point_at(Vector2(0.0, -1.0))
	wheel.cancel()
	assert_str(wheel.release()).is_equal("")
	assert_str(wheel.current).is_equal(BotWheel.DEFAULT_ORDER)


func test_the_mouse_moves_the_pointer_and_stops_at_the_rim() -> void:
	var wheel := BotWheel.new()
	_hold_open(wheel)
	wheel.move_by(Vector2(0.0, -BotWheel.MOUSE_REACH * 0.5))
	assert_vector(wheel.pointer).is_equal_approx(Vector2(0.0, -0.5), Vector2.ONE * 0.001)
	wheel.move_by(Vector2(0.0, -BotWheel.MOUSE_REACH * 5.0))
	assert_float(wheel.pointer.length()).is_equal_approx(1.0, 0.001)


func test_a_pointer_before_the_press_is_not_kept() -> void:
	var wheel := BotWheel.new()
	wheel.move_by(Vector2(100.0, 0.0))
	wheel.point_at(Vector2(1.0, 0.0))
	assert_vector(wheel.pointer).is_equal(Vector2.ZERO)
	_hold_open(wheel)
	assert_vector(wheel.pointer).is_equal(Vector2.ZERO)


func test_the_wheel_grows_while_open_and_shrinks_after() -> void:
	var wheel := BotWheel.new()
	_hold_open(wheel)
	for _i in 20:
		wheel.advance(STEP)
	assert_float(wheel.growth).is_equal(1.0)
	wheel.cancel()
	for _i in 20:
		wheel.advance(STEP)
	assert_float(wheel.growth).is_equal(0.0)


func test_the_link_gives_the_order_to_the_nights_bot_orders() -> void:
	var night: NightWithBotOrdersDouble = auto_free(NightWithBotOrdersDouble.new())
	var link := BotOrderLink.for_night(night)
	var sent := link.issue(BotWheel.HOLD, 4, Vector3(1.0, 2.0, 3.0))
	assert_str(sent[&"order"]).is_equal(BotWheel.HOLD)
	var heard := night.bot_orders.heard
	assert_int(heard.size()).is_equal(1)
	assert_int(heard[0][&"issuer"]).is_equal(4)
	assert_vector(heard[0][&"at"]).is_equal(Vector3(1.0, 2.0, 3.0))
	# The whole team's bots, not one: the wheel gives no bot id.
	assert_int(heard[0][&"bot"]).is_equal(0)


func test_a_link_with_nothing_behind_it_sends_nothing_and_reads_nothing() -> void:
	var link := BotOrderLink.new()
	assert_dict(link.issue(BotWheel.FOLLOW, 1, Vector3.ZERO)).is_empty()
	assert_str(link.current({"tick": 1})).is_equal("")


func test_a_night_without_bot_orders_yet_sends_nothing() -> void:
	# The night of a build that has no `bot_orders` (before #641): the link answers {} and the
	# wheel keeps its own order.
	var night := Node.new()
	var link := BotOrderLink.for_night(night)
	assert_dict(link.issue(BotWheel.ROAM, 1, Vector3.ZERO)).is_empty()
	night.free()


func test_the_wheels_orders_are_the_ones_bot_orders_takes() -> void:
	# `BotOrders` (#641) names the orders the wheel gives; once it is in the build, the two lists
	# must be the same names in the same order (the wire order).
	var path := "res://gameplay/bots/bot_orders.gd"
	if not ResourceLoader.exists(path):
		return
	var constants := (load(path) as Script).get_script_constant_map()
	assert_array(constants["ORDERS"]).is_equal(BotWheel.ORDERS)
	assert_str(constants["ROAM"]).is_equal(BotWheel.DEFAULT_ORDER)
