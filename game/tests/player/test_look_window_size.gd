# One mouse pixel turns the view the same at every window size and stretch setting (#928).
#
# The project stretches the canvas to a 1920 x 1080 base (`canvas_items`, aspect `expand`), and the
# engine hands a mouse motion to the game in the CANVAS's units: `relative` is the screen motion
# times `1920 / window width`. The player used to turn by `relative`, so a 1280 pixel window turned
# 1.5 times as far per pixel of the hand as a 1920 one. It turns by `screen_relative` now.
#
# The same hand (a seeded path of whole pixels, sent the way the system sends it: both fields in
# window pixels, through `Input.parse_input_event`, which maps `relative` through the stretch)
# is replayed at several window sizes and stretch settings, and what the player's rig turned is
# compared with `pixels * mouse_radians_per_pixel * sensitivity`.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const PATH_SEED := 928
const PATH_STEPS := 40
## The shipped turn of one mouse pixel (`PlayerTuning.mouse_radians_per_pixel`).
const RADIANS_PER_PIXEL := 0.0022
const CANVAS := Vector2i(1920, 1080)
## Window sizes: the web canvas of a laptop, the base, a 1440p monitor, a tall window (aspect
## `expand` grows the canvas), a small floating window, and the 64 pixel headless default.
const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(1000, 1400),
	Vector2i(800, 450),
	Vector2i(64, 64),
]
const MODES: Array[int] = [
	Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
	Window.CONTENT_SCALE_MODE_VIEWPORT,
	Window.CONTENT_SCALE_MODE_DISABLED,
]

var _window_size: Vector2i
var _window_mode: int
var _window_scale_size: Vector2i
var _fixture: TouchFixture


func before_test() -> void:
	var window := get_tree().root
	_window_size = window.size
	_window_mode = window.content_scale_mode
	_window_scale_size = window.content_scale_size


func after_test() -> void:
	var window := get_tree().root
	window.content_scale_mode = _window_mode as Window.ContentScaleMode
	window.content_scale_size = _window_scale_size
	window.size = _window_size
	if _fixture != null:
		_fixture.free_all()
		_fixture = null


func test_the_same_hand_turns_the_same_at_every_window_size_and_stretch() -> void:
	var player := _test_room_player()
	var path := _path()
	var pixels := Vector2.ZERO
	for step in path:
		pixels += step
	var expected := -pixels.x * RADIANS_PER_PIXEL * player.camera_rig.sensitivity
	assert_float(absf(expected)).is_between(0.5, 3.0)  # inside one half turn: yaw wraps
	for mode in MODES:
		for size in SIZES:
			_set_window(size, mode)
			var turned := _replay(player.camera_rig, path)
			(
				assert_float(turned)
				. override_failure_message(
					(
						"stretch mode %d, window %dx%d (canvas scale %.3f): turned %.4f rad, the hand asked for %.4f"
						% [mode, size.x, size.y, _scale(), turned, expected]
					)
				)
				. is_equal_approx(expected, 0.0005)
			)


## The test must bite: with the canvas stretch on, the engine really does hand the game a `relative`
## that depends on the window (so a player reading it fails the test above).
func test_the_stretch_changes_relative_but_not_screen_relative() -> void:
	var probe := MotionProbe.new()
	get_tree().root.add_child(probe)
	var relatives: Array[float] = []
	for size in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		_set_window(size, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
		probe.seen.clear()
		_post(Vector2(100.0, 0.0))
		Input.flush_buffered_events()
		assert_int(probe.seen.size()).is_equal(1)
		assert_float(probe.seen[0].screen_relative.x).is_equal(100.0)
		relatives.append(probe.seen[0].relative.x)
	probe.queue_free()
	assert_float(relatives[0] / relatives[1]).is_equal_approx(2.0, 0.01)


## The fingers' look is in mouse pixels already (the canvas is the unit it is measured in): it
## turns the same at every window size, and as much as it did before.
func test_the_touch_look_turns_the_same_at_every_window_size() -> void:
	var player := _test_room_player()
	var rig := player.camera_rig
	_fixture = TouchFixture.make(self)
	var turns: Array[float] = []
	for size in SIZES:
		_set_window(size, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
		rig.yaw = 0.0
		_fixture.controls.look_smoother.add(Vector2(100.0, 0.0))
		_fixture.controls.flush_look()
		turns.append(rig.yaw)
	for turned in turns:
		assert_float(turned).is_equal_approx(-100.0 * RADIANS_PER_PIXEL * rig.sensitivity, 0.0005)


## On the web the runtime reports a pointer move in device pixels, so a screen with a pixel ratio
## of 2 sends twice the pixels for the same hand: the look divides the ratio out. The touch layer's
## own motion is in mouse pixels already and is not divided.
func test_the_web_pixel_ratio_is_divided_out_of_the_mouse_but_not_of_the_touch_look() -> void:
	var mouse := InputEventMouseMotion.new()
	mouse.screen_relative = Vector2(30.0, -10.0)
	assert_vector(MouseMotion.pixels(mouse, 1.0)).is_equal(Vector2(30.0, -10.0))
	assert_vector(MouseMotion.pixels(mouse, 2.0)).is_equal(Vector2(15.0, -5.0))
	assert_vector(MouseMotion.pixels(mouse, 0.0)).is_equal(Vector2(30.0, -10.0))
	var finger := InputEventMouseMotion.new()
	finger.device = TouchLook.DEVICE
	finger.screen_relative = Vector2(30.0, -10.0)
	assert_vector(MouseMotion.pixels(finger, 2.0)).is_equal(Vector2(30.0, -10.0))
	# Off the web the ratio is 1, whatever the desktop's own scaling.
	assert_float(MouseMotion.device_pixel_ratio()).is_equal(1.0)


func _test_room_player() -> Player:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	player.camera_rig.set_process(false)
	return player


func _set_window(size: Vector2i, mode: int) -> void:
	var window := get_tree().root
	window.content_scale_mode = mode as Window.ContentScaleMode
	window.content_scale_size = CANVAS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.size = size


## How many canvas units a window pixel is (the stretch).
func _scale() -> float:
	return 1.0 / get_tree().root.get_final_transform().get_scale().x


## Replays the path and returns how far the rig turned (yaw).
func _replay(rig: ThirdPersonCamera, path: PackedVector2Array) -> float:
	rig.yaw = 0.0
	rig.pitch = 0.0
	for step in path:
		_post(step)
		Input.flush_buffered_events()
	return rig.yaw


## A motion as the system sends it: window pixels in both fields; the viewport maps `relative`.
func _post(step: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = step
	event.screen_relative = step
	event.position = Vector2(30.0, 30.0)
	event.global_position = event.position
	Input.parse_input_event(event)


## Whole-pixel steps, flicks and slow ones (seeded).
func _path() -> PackedVector2Array:
	var random := RandomNumberGenerator.new()
	random.seed = PATH_SEED
	var path := PackedVector2Array()
	for _i in PATH_STEPS:
		path.append(Vector2(random.randi_range(-40, 90), random.randi_range(-3, 3)))
	return path


## Keeps the motions the window hands to the game.
class MotionProbe:
	extends Node
	var seen: Array[InputEventMouseMotion] = []

	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			seen.append(event as InputEventMouseMotion)
