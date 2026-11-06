# A slow, steady drag keeps turning the view to its end (#1320). The aim assist's browser run drags
# like a thumb that aims: a move every 100 ms that gets shorter as the crosshair nears the target,
# the first ones inside the tap's slop and its 250 ms. Its `off` run once seemed to lose the look
# after three steps; the layer was not at fault (the finger had landed while the helicopter drop
# kept the layer down). This pins that a finger the layer owns never loses its look: no move is
# swallowed, the held ones included, and each adds at least what a still finger's drag of that
# length turns (a quicker finger turns more: `TouchTuning.max_gain`).
extends GdUnitTestSuite

const START := Vector2(1638.0, 324.0)
## The drag's pace: a move every 100 ms, as the browser run sends them.
const PERIOD := 0.1

var _fixture: TouchFixture
var _looks := Vector2.ZERO


func before_test() -> void:
	_fixture = TouchFixture.make(self)
	# Only this test's own seconds: the double tap's 250 ms is read against this clock.
	_fixture.controls.clock = func() -> float: return _fixture.now
	_looks = Vector2.ZERO
	_fixture.controls.looked.connect(func(look: Vector2) -> void: _looks += look)


func after_test() -> void:
	_fixture.free_all()


## What `units` of finger travel turn the view in mouse pixels at a still finger's gain.
func _look_for(units: Vector2) -> Vector2:
	return units * TouchLook.tuning.radians_per_height / 1080.0 / TouchLook.mouse_radians_per_pixel


## Drags `steps` moves of `first` canvas units, each `share` of the one before, a move per `PERIOD`;
## returns the look the layer had made after each move.
func _drag_shrinking(first: Vector2, share: float, steps: int) -> Array[Vector2]:
	var at := START
	var step := first
	var seen: Array[Vector2] = []
	for _i in steps:
		at += step
		_fixture.pass_time(PERIOD)
		await _fixture.drag(0, at, step)
		seen.append(_looks)
		step *= share
	return seen


## No move after the tap's window (and the slop) went unturned: each added its own length at least.
func _assert_every_move_turned(
	seen: Array[Vector2], first: Vector2, share: float, from: int
) -> void:
	var step := first * pow(share, from)
	for i in range(from, seen.size()):
		var added := seen[i] - seen[i - 1]
		var wanted := _look_for(step)
		assert_float(added.x * signf(wanted.x)).is_greater_equal(absf(wanted.x) * 0.95)
		assert_float(added.y * signf(wanted.y)).is_greater_equal(absf(wanted.y) * 0.95)
		step *= share


func test_a_steady_slow_drag_turns_every_move() -> void:
	var first := Vector2(-14.0, -6.0)
	await _fixture.touch(0, START)
	var seen := await _drag_shrinking(first, 1.0, 40)
	await _fixture.lift(0)
	# The first moves are held for the tap (28 units of slop): from the third, each one turns.
	_assert_every_move_turned(seen, first, 1.0, 3)
	assert_float(absf(_looks.x)).is_greater_equal(absf(_look_for(first * 40.0).x) * 0.95)


func test_a_drag_that_slows_as_it_nears_its_target_turns_every_move() -> void:
	# 60 % of the move before, as the browser run's thumb closes in: the first moves are inside the
	# slop and the tap's 250 ms, the last a fifth of a unit (a finger's position is read to a
	# thousandth of one, so the tail is not asked for further).
	var first := Vector2(-21.0, 8.0)
	await _fixture.touch(0, START)
	var seen := await _drag_shrinking(first, 0.6, 10)
	await _fixture.lift(0)
	_assert_every_move_turned(seen, first, 0.6, 3)


func test_the_view_keeps_turning_after_the_tap_window_has_passed() -> void:
	var first := Vector2(-10.0, 0.0)
	await _fixture.touch(0, START)
	var seen := await _drag_shrinking(first, 1.0, 12)
	await _fixture.lift(0)
	assert_float(seen[-1].x).is_less(seen[4].x)
	_assert_every_move_turned(seen, first, 1.0, 4)
