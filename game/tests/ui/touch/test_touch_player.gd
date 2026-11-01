# The touch controls driving the real player: a drag on the right turns the camera, the stick
# walks the player. Its own suite because the scene runner changes how input is delivered.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"

var _fixture: TouchFixture


func before_test() -> void:
	_fixture = TouchFixture.make(self)


func after_test() -> void:
	_fixture.free_all()


func test_a_drag_turns_the_player_through_the_real_input_path() -> void:
	var runner := scene_runner("res://world/test_room.tscn")
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	var rig := player.camera_rig
	var yaw := rig.yaw
	await _fixture.touch(0, Vector2(1700.0, 300.0))
	await _fixture.drag(0, Vector2(1800.0, 300.0), Vector2(100.0, 0.0))
	await _fixture.lift(0)
	# Dragging right turns the view right (mouse convention): the yaw falls. A drag of 100 units
	# on a 1080 unit tall canvas turns 100 / 1080 of the full-height swipe, at sensitivity 1.
	var turned := angle_difference(yaw, rig.yaw)
	assert_float(turned).is_equal_approx(-TouchLook.RADIANS_PER_HEIGHT * 100.0 / 1080.0, 0.02)
