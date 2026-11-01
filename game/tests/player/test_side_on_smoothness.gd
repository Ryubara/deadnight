# The soldier seen from the side while strafing must not step: the body is drawn where the
# engine's physics interpolation puts it, the camera where its own blend puts it, and the two
# agree to a fraction of a pixel at any frame rate (docs/research/physics-interpolation.md).
#
# Frames here run as fast as the machine allows, many per physics tick, so every fraction of a tick
# is drawn. A body that is steady at a constant lag from the camera stays at one screen position;
# one drawn at its last tick instead swings by the tick's travel (8 to 10 pixels at 1280x720, 12 to
# 50 here). A long frame (a loaded machine) moves the body by more than a tick at once, for the
# camera as much as for the body, and the camera's spring takes half a second to follow, so the
# measure waits for a stretch with no such frame.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const START := Vector3(-13.0, 0.05, 10.0)
const TICK := 1.0 / 60.0
## Ticks of strafing before the soldier and the camera are at their steady pace.
const SETTLE_TICKS := 84
## The room holds this many ticks of strafing at the run's pace.
const GIVE_UP_TICKS := 330
## Ticks after a long frame before the camera's spring has caught up with it.
const RECOVER_TICKS := 36
## Ticks of untroubled frames that make a measure.
const WINDOW_TICKS := 36
## A frame longer than this many seconds is a long one (1.45 ticks).
const LONG_FRAME := 0.024
## The most the soldier may wander on the screen in a window, in pixels of a 1920x1080 view (the
## engine's own blend adds up to half a pixel at the tick where a frame crosses it).
const MAX_WANDER := 2.0

var _player: Player
var _model: Node3D
var _camera: Camera3D


## Reads `read` at the end of every drawn frame (after the camera rig, which runs earlier) and
## keeps it with the physics tick it was drawn in and the frame's length.
class LateSampler:
	extends Node

	var read: Callable
	var recording := false
	var ticks: Array[int] = []
	var lengths := PackedFloat64Array()
	var samples := PackedFloat64Array()

	func _process(delta: float) -> void:
		if recording:
			lengths.append(delta)
			ticks.append(Engine.get_physics_frames())
			samples.append(read.call())


func before_test() -> void:
	var runner := scene_runner(TEST_ROOM)
	_player = runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_player.teleport(START)
	_model = _player.get_node("Model") as Node3D
	_camera = _player.camera_rig.camera()


## The screen x of the soldier's chest as the renderer draws it this frame.
func _chest_x() -> float:
	var chest := _model.get_global_transform_interpolated() * Vector3(0.0, 1.0, 0.0)
	return _camera.unproject_position(chest).x


func _strafe() -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = Vector2(1.0, 0.0)
	return command


## The samples of the first `WINDOW_TICKS` in which no frame was long, nor was one in the
## `RECOVER_TICKS` before; empty when there is none yet.
func _first_calm_window(sampler: LateSampler) -> PackedFloat64Array:
	var ticks := sampler.ticks
	var samples := sampler.samples
	var run_start := -1
	var last_long := -RECOVER_TICKS * 2
	for i in range(1, ticks.size()):
		if ticks[i] - ticks[i - 1] >= 2 or sampler.lengths[i] > LONG_FRAME:
			last_long = ticks[i]
		if ticks[i] - last_long < RECOVER_TICKS:
			run_start = -1
			continue
		if run_start < 0:
			run_start = i
		if ticks[i] - ticks[run_start] >= WINDOW_TICKS:
			return samples.slice(run_start, i + 1)
	return PackedFloat64Array()


func test_the_soldier_holds_still_on_the_screen_while_strafing_at_any_frame_rate() -> void:
	var sampler := LateSampler.new()
	sampler.process_priority = 1000
	sampler.read = _chest_x
	add_child(sampler)
	var first_tick := Engine.get_physics_frames()
	var window := PackedFloat64Array()
	var ticks_run := 0
	while ticks_run < GIVE_UP_TICKS and window.is_empty():
		await get_tree().process_frame
		ticks_run = Engine.get_physics_frames() - first_tick
		_player.submit_command(_strafe())
		sampler.recording = ticks_run >= SETTLE_TICKS
		if sampler.recording and ticks_run % 6 == 0:
			window = _first_calm_window(sampler)
	var frames_per_tick := float(sampler.samples.size()) / float(maxi(ticks_run - SETTLE_TICKS, 1))
	sampler.recording = false
	sampler.free()
	assert_bool(window.is_empty()).is_false()
	# The measure only means something with several drawn frames in each tick.
	assert_float(frames_per_tick).is_greater(1.5)
	assert_float(FrameJudder.peak_to_peak(window)).is_less(MAX_WANDER)


func test_second_differences_of_a_steady_series_are_zero_and_of_a_sawtooth_are_not() -> void:
	var steady := PackedFloat64Array([0.0, 2.0, 4.0, 6.0, 8.0])
	assert_float(FrameJudder.peak(FrameJudder.second_differences(steady))).is_equal(0.0)
	var steps := PackedFloat64Array([0.0, 10.0, 10.0, 20.0, 20.0, 30.0])
	assert_float(FrameJudder.peak(FrameJudder.second_differences(steps))).is_equal(10.0)
	assert_float(FrameJudder.peak_to_peak(steps)).is_equal(30.0)
