# How a repair is shown (#245): the body turns to the boards it puts back, and the repair clip
# reaches the body of the player the event names, through the view (every client draws every
# player's repair from the same event). Driven like a client; a tick is 1/60 s.
extends GdUnitTestSuite

const BREACH := &"nw"
const TICKS_PER_SECOND := 60
const SETTLE := 30


func _start(torn: int) -> Night:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 60.0
	tuning.rounds.first_spawn_delay = 600.0
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	NightFixture.run(night, SETTLE)
	for _i in torn:
		night.server.rules.barricades.tear(BREACH)
	night.world.barricade(BREACH).set_boards(night.server.rules.barricades.boards_of(BREACH))
	night.player().teleport(night.world.repair_spot(BREACH))
	NightFixture.run(night, 2)
	return night


## The yaw (the body's `facing`) that looks from the player at the breach.
func _yaw_to_breach(night: Night) -> float:
	var to := night.world.barricade(BREACH).global_position - night.player().global_position
	return atan2(-to.x, -to.z)


func _tap(night: Night) -> void:
	var tap := NightCommand.new()
	tap.use = true
	tap.use_held = true
	NightFixture.run(night, 1, tap)


func test_the_body_turns_to_the_boards_it_puts_back() -> void:
	var night := await _start(3)
	var toward := _yaw_to_breach(night)
	night.player().state.facing = wrapf(toward + PI, -PI, PI)  # his back to the boards
	var before := night.server.rules.barricades.boards_of(BREACH)
	_tap(night)
	assert_int(night.server.rules.barricades.boards_of(BREACH)).is_equal(before + 1)
	NightFixture.run(night, TICKS_PER_SECOND / 2)
	var off := absf(rad_to_deg(angle_difference(night.player().state.facing, toward)))
	assert_float(off).override_failure_message("%.1f degrees off the breach" % off).is_less(3.0)
	night.queue_free()


func test_a_board_put_back_starts_the_players_repair_clip() -> void:
	var night := await _start(3)
	var animation := night.player().get_node("AnimationTree") as PlayerAnimation
	assert_bool(animation.is_repairing()).is_false()
	_tap(night)
	NightFixture.run(night, 2)  # the event reaches the client a tick behind
	assert_bool(animation.is_repairing()).is_true()
	night.queue_free()


func test_the_clip_goes_to_the_player_the_event_names() -> void:
	var night := await _start(0)
	var other := night.world.add_body(night.world.player_spawn(1), false)
	var drawn: Dictionary[int, Node3D] = {1: night.player(), 2: other}
	night.view.bodies = func(player_id: int) -> Node3D: return drawn.get(player_id)
	night.view.show_repair(2)
	var mine := night.player().get_node("AnimationTree") as PlayerAnimation
	var theirs := other.get_node("AnimationTree") as PlayerAnimation
	assert_bool(theirs.is_repairing()).is_true()
	assert_bool(mine.is_repairing()).is_false()
	# An id with no drawn body is ignored, not an error.
	night.view.show_repair(7)
	night.queue_free()
