# The bot command wheel's drawing (#642): it shows only while the wheel is open, its three tickets
# and the dial fit every canvas a night is played on without touching each other, and it stays on
# the middle of the screen whatever the safe area is (the world's centre is where the shots go).
extends GdUnitTestSuite

## Canvases (canvas units) of a desktop, the smallest the UI scale gives, a phone with the menu's
## phone factor on (a night runs on it) and a wide phone.
const CANVASES: Array[Vector2] = [
	Vector2(1920.0, 1080.0),
	Vector2(1536.0, 864.0),
	Vector2(1168.0, 540.0),
	Vector2(2340.0, 1080.0),
]
const STEP := 1.0 / 60.0

var _fixture: HudFixture
var _host: Control
var _wheel: BotWheel


func before_test() -> void:
	UIMotion.reduced = false
	_wheel = BotWheel.new()


func _build(canvas: Vector2) -> HudBotWheel:
	_host = auto_free(Control.new())
	_host.size = canvas
	add_child(_host)
	_fixture = HudFixture.make(_host, 1)
	var drawn := _fixture.hud.bot_wheel
	drawn.wheel = _wheel
	return drawn


func _open(order: StringName = &"") -> void:
	_wheel.press()
	for _i in 20:
		_wheel.advance(STEP)
	if order != &"":
		_wheel.point_at(BotWheel.direction_of(order))


func test_it_shows_only_while_the_wheel_is_open() -> void:
	var drawn := _build(CANVASES[0])
	await get_tree().process_frame
	assert_bool(drawn.visible).is_false()
	_open()
	await get_tree().process_frame
	assert_bool(drawn.visible).is_true()
	_wheel.cancel()
	for _i in 20:
		_wheel.advance(STEP)
	await get_tree().process_frame
	assert_bool(drawn.visible).is_false()


func test_it_is_one_of_the_huds_full_screen_overlays_at_the_middle() -> void:
	var drawn := _build(CANVASES[0])
	assert_array(_fixture.hud.screen_overlays()).contains([drawn])
	_fixture.hud.set_safe_insets(Vector4(81.0, 0.0, 81.0, 29.0))
	await get_tree().process_frame
	assert_vector(drawn.get_global_rect().get_center()).is_equal_approx(
		CANVASES[0] * 0.5, Vector2(0.01, 0.01)
	)
	_fixture.hud.set_safe_insets(Vector4.ZERO)


func test_the_tickets_and_the_dial_fit_every_canvas_and_miss_each_other() -> void:
	for canvas in CANVASES:
		if is_instance_valid(_host):
			_host.free()
		var drawn := _build(canvas)
		await get_tree().process_frame
		await get_tree().process_frame
		var screen := Rect2(Vector2.ZERO, canvas)
		var rects: Array[Rect2] = []
		for order in BotWheel.ORDERS:
			var rect := drawn.card_rect(order).grow(HudBotWheel.LIFT)
			(
				assert_bool(screen.encloses(rect))
				. override_failure_message("%s leaves %s: %s" % [order, canvas, rect])
				. is_true()
			)
			var nearest := drawn.centre().clamp(rect.position, rect.end)
			assert_float(nearest.distance_to(drawn.centre())).is_greater(HudBotWheel.DIAL)
			rects.append(drawn.card_rect(order))
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				(
					assert_bool(rects[i].intersects(rects[j]))
					. override_failure_message("tickets %d and %d touch on %s" % [i, j, canvas])
					. is_false()
				)


func test_the_tickets_stand_where_the_directions_point() -> void:
	var drawn := _build(CANVASES[0])
	await get_tree().process_frame
	var middle := drawn.centre()
	assert_float(drawn.card_rect(BotWheel.FOLLOW).get_center().y).is_less(middle.y)
	assert_float(drawn.card_rect(BotWheel.ROAM).get_center().x).is_greater(middle.x)
	assert_float(drawn.card_rect(BotWheel.HOLD).get_center().x).is_less(middle.x)
	# The entry a ticket stands at is the one its direction picks.
	for order in BotWheel.ORDERS:
		var offset := drawn.card_rect(order).get_center() - middle
		assert_str(BotWheel.entry_at(offset.normalized())).is_equal(order)


func test_drawing_every_state_makes_no_error() -> void:
	var drawn := _build(CANVASES[2])
	_open()
	for order in [&"", BotWheel.FOLLOW, BotWheel.ROAM, BotWheel.HOLD]:
		if order != &"":
			_wheel.point_at(BotWheel.direction_of(order))
		else:
			_wheel.point_at(Vector2.ZERO)
		_wheel.current = BotWheel.HOLD
		await get_tree().process_frame
		await get_tree().process_frame
		assert_bool(drawn.visible).is_true()
	UIMotion.reduced = true
	await get_tree().process_frame
	UIMotion.reduced = false
