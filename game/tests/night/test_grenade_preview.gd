extends GdUnitTestSuite
## The arc of the grenade in the hand (#357): while a grenade button is held the player sees where
## the throw would go, and it goes there. A night run by hand: a tick is 1/60 s.

## Long enough for the player to drop from the spawn onto the ground.
const SETTLE := 150
const FLIGHT_STEPS := 24

var _night: Night


func before() -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 1.0
	_night = await NightFixture.start(self, Night.Mode.MANUAL, tuning, 7)
	NightFixture.run(_night, SETTLE)
	_night.server.rules.apply(RulesAction.skip_break())


## Every test starts with no button held, so no cook is running in the preview.
func before_test() -> void:
	_night.preview.grenades_left = -1
	_night.show_throw(_holding(0.3, false))


func after() -> void:
	# Gone before the next suite builds its night: its player would stand on this one's body.
	_night.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


## A command holding the overarm button, looking `pitch` radians up from along +Z (into the lot,
## away from the wall behind the player).
func _holding(pitch: float = 0.3, over: bool = true, under: bool = false) -> NightCommand:
	var command := NightCommand.new()
	command.motion.throw_over = over
	command.motion.throw_under = under
	command.dir = Vector3(0.0, sin(pitch), cos(pitch))
	return command


func _tick(command: NightCommand) -> void:
	_night.show_throw(command)
	NightFixture.run(_night, 1, command)


func test_nothing_is_shown_until_a_button_is_held() -> void:
	_tick(_holding(0.3, false))
	assert_bool(_night.preview.visible).is_false()
	assert_int(_night.preview.points().size()).is_equal(0)
	_tick(_holding())
	assert_bool(_night.preview.visible).is_true()
	assert_int(_night.preview.points().size()).is_greater(3)


func test_it_goes_away_when_the_button_comes_up() -> void:
	_tick(_holding())
	_tick(_holding(0.3, false))
	assert_bool(_night.preview.visible).is_false()


func test_it_starts_at_the_hand_the_throw_leaves_from() -> void:
	var command := _holding()
	for _i in 10:
		_tick(command)
	var start := _night.preview.points()[0]
	var thrown: Array[Dictionary] = []
	_night.state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] == &"grenade_thrown":
				thrown.append(event)
	)
	var released := _holding(0.3, false)
	for _i in 40:
		_tick(released)
	assert_array(thrown).has_size(1)
	assert_vector(thrown[0]["position"]).is_equal_approx(start, Vector3.ONE * 0.02)


func test_the_line_is_where_the_grenade_flies() -> void:
	var command := _holding()
	for _i in 10:
		_tick(command)
	var line := _night.preview.points()
	var thrown_id := []
	_night.state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] == &"grenade_thrown":
				thrown_id.append(event["grenade_id"])
	)
	var released := _holding(0.3, false)
	var ticks := 0
	while thrown_id.is_empty() and ticks < 60:
		_tick(released)
		ticks += 1
	assert_array(thrown_id).has_size(1)
	# The grenade was stepped once in the tick it left.
	NightFixture.run(_night, FLIGHT_STEPS - 1)
	var flying := _night.server.grenades.grenade(thrown_id[0])
	assert_object(flying).is_not_null()
	# On the line: the preview samples every few steps, so the real position is near a segment.
	var nearest := INF
	for index in line.size() - 1:
		var on_segment := Geometry3D.get_closest_point_to_segment(
			flying.position, line[index], line[index + 1]
		)
		nearest = minf(nearest, on_segment.distance_to(flying.position))
	assert_float(nearest).is_less(0.05)


func test_looking_higher_throws_farther_up_to_the_high_arc() -> void:
	_tick(_holding(0.2))
	var flat := _night.preview.landing()
	_tick(_holding(0.7))
	var high := _night.preview.landing()
	var hand := _night.player().global_position
	assert_float(Vector2(high.x - hand.x, high.z - hand.z).length()).is_greater(
		Vector2(flat.x - hand.x, flat.z - hand.z).length()
	)


func test_the_underarm_toss_lands_nearer_than_the_overarm_throw() -> void:
	_tick(_holding(0.3))
	var over := _night.preview.landing()
	_tick(_holding(0.3, false, true))
	var under := _night.preview.landing()
	var hand := _night.player().global_position
	assert_float(Vector2(under.x - hand.x, under.z - hand.z).length()).is_less(
		Vector2(over.x - hand.x, over.z - hand.z).length()
	)


func test_a_long_cook_shows_the_grenade_going_off_nearer_the_hand() -> void:
	var command := _holding(0.2)
	_tick(command)
	var fresh := _night.preview.landing()
	for _i in 150:
		_tick(command)
	var hand := _night.player().global_position
	var later := _night.preview.landing()
	assert_float(Vector2(later.x - hand.x, later.z - hand.z).length()).is_less(
		Vector2(fresh.x - hand.x, fresh.z - hand.z).length()
	)


func test_nothing_is_shown_with_no_grenades_left_or_when_downed() -> void:
	_night.preview.grenades_left = 0
	_tick(_holding())
	assert_bool(_night.preview.visible).is_false()
	_night.preview.grenades_left = 2
	_night.preview.follow(_holding(), _night.player(), Night.STEP, true)
	assert_bool(_night.preview.visible).is_false()
	_night.preview.follow(_holding(), _night.player(), Night.STEP, false)
	assert_bool(_night.preview.visible).is_true()
