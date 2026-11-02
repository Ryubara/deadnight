# The shot waits for the body (#477), on the server, the authority: a press while the body faces
# away from the view turns it and the shot leaves when the body faces the centre of the screen
# within the tolerance, once per press; a tap made during the turn is kept; a view still turning
# delays the shot until the body has caught up. The aim button is unchanged. The client's side of
# the same rule (the simulation both run) is in tests/player/test_hip_fire_turn.gd.
extends GdUnitTestSuite

const TICK := 1.0 / 60.0

var _night: Night
var _player: Player
var _tuning: PlayerTuning
## The ticks (counted from the first tick of a run) the server fired a shot of player 1 on.
var _shots: Array[int] = []
## The body's distance from the view (radians) at each of those shots.
var _errors: Array[float] = []
## The body's distance from the view after each tick.
var _gaps: Array[float] = []
var _tick := 0
var _view := 0.0
var _buffer := 0.0


func before_test() -> void:
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(_night, 30)
	_player = _night.player()
	_tuning = _player.tuning
	_buffer = _tuning.hip_fire_buffer
	_shots = []
	_errors = []
	_gaps = []
	_tick = 0
	_night.state.event_received.connect(_on_event)


func after_test() -> void:
	_tuning.hip_fire_buffer = _buffer
	_night.queue_free()


## The link hands the events of a tick over in the next one, so a shot is counted on the tick the
## server made it (the one before) and measured against the body as that tick left it.
func _on_event(event: Dictionary) -> void:
	if event["type"] == &"shot_fired" and event["shooter_id"] == 1:
		_shots.append(_tick - 1)
		_errors.append(_gaps[_tick - 1])


## A command looking along `yaw` with the trigger as given and the body not told to move.
func _command(yaw: float, fire: bool, aim: bool = false) -> NightCommand:
	var command := NightCommand.new()
	command.fire = fire
	command.motion.yaw = yaw
	command.motion.aim = aim
	var head := _night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	command.origin = head
	command.dir = Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -1.0)
	return command


## One tick with `command`, counting it.
func _step(command: NightCommand) -> void:
	_view = command.motion.yaw
	NightFixture.run(_night, 1, command)
	_gaps.append(_player.state.view_error)
	_tick += 1


## The tick after the last one, so the link has handed over the last tick's events.
func _flush() -> void:
	_step(_command(_view, false))


func _tolerance() -> float:
	return deg_to_rad(_tuning.hip_fire_align_degrees)


## The ticks the body needs to be within the tolerance of a view `angle` away.
func _turn_ticks(angle: float) -> int:
	return ceili((angle - _tolerance()) / (_tuning.aim_turn_speed * TICK))


func test_a_press_facing_the_view_shoots_on_that_tick() -> void:
	var yaw := _player.state.facing
	_step(_command(yaw, true))
	_flush()
	assert_array(_shots).is_equal([0])


func test_a_press_with_the_body_facing_away_holds_the_shot_until_it_turned() -> void:
	var back := _player.state.facing + PI
	for i in 60:
		_step(_command(back, true))
	assert_int(_shots.size()).is_greater(0)
	# Nothing leaves while the body is still turning, whatever the weapon is ready for.
	assert_int(_shots[0]).is_greater_equal(_turn_ticks(PI) - 1)
	assert_float(_errors[0]).is_less_equal(_tolerance() + 0.001)
	for error in _errors:
		assert_float(error).is_less_equal(_tolerance() + 0.001)


func test_a_tap_during_the_turn_is_kept_and_fires_exactly_once() -> void:
	var back := _player.state.facing + PI
	for i in 3:
		_step(_command(back, true))
	for i in 70:
		_step(_command(back, false))
	assert_int(_shots.size()).is_equal(1)
	assert_int(_shots[0]).is_greater_equal(_turn_ticks(PI) - 1)
	assert_float(_errors[0]).is_less_equal(_tolerance() + 0.001)


func test_a_tap_that_the_turn_outlasts_is_dropped_when_its_buffer_runs_out() -> void:
	# A press is kept for `hip_fire_buffer`; a turn that takes longer (a short buffer here, a half
	# circle needs 23 ticks) leaves nothing behind: the spent tap is not fired late.
	_tuning.hip_fire_buffer = 0.1
	var back := _player.state.facing + PI
	for i in 3:
		_step(_command(back, true))
	for i in 70:
		_step(_command(back, false))
	assert_int(_shots.size()).is_equal(0)


func test_a_view_still_turning_delays_the_shot_until_the_body_caught_up() -> void:
	var yaw := _player.state.facing
	# The view runs ahead of the body for a few ticks (no trigger: the body stays), then the press.
	for i in 5:
		yaw += 0.3
		_step(_command(yaw, false))
	var turning := 12
	for i in turning:
		yaw += 0.2  # 11.5 degrees a tick: faster than the body's 7.6
		_step(_command(yaw, true))
	assert_array(_shots).is_empty()
	# The view holds still: the shot follows within the few ticks the body needs.
	for i in 30:
		_step(_command(yaw, true))
	assert_int(_shots.size()).is_greater(0)
	assert_int(_shots[0]).is_greater_equal(5 + turning)
	assert_float(_errors[0]).is_less_equal(_tolerance() + 0.001)


func test_a_held_trigger_keeps_firing_once_the_body_is_there() -> void:
	var back := _player.state.facing + PI
	for i in 150:
		_step(_command(back, true))
	assert_int(_shots.size()).is_greater(1)
	var weapon := _night.server.combat.weapon_of(1)
	var interval := ceili(weapon.def.fire_interval / TICK)
	for i in range(1, _shots.size()):
		assert_int(_shots[i] - _shots[i - 1]).is_greater_equal(interval - 1)


func test_the_aim_button_is_unchanged_and_shoots_at_once() -> void:
	var back := _player.state.facing + PI
	_step(_command(back, true, true))
	_flush()
	assert_array(_shots).is_equal([0])
