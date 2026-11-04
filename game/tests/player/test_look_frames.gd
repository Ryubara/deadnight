# The view stays one to one with the hand at any frame rate (#905): one recorded mouse path is
# replayed through the real input path (`Input.parse_input_event`, the player's own
# `_unhandled_input`) over frames of 1/144, 1/60, 1/30 and 1/15 s and over a seeded uneven run with
# hitches, and what the camera DRAWS is compared with what the hand did. The frames are stepped by
# hand on a clock the test keeps (the rig's `step`), so no real frame length is in it.
#
# The fault it holds: `ThirdPersonCamera._place` set the lens and then moved the rig above it, so
# the lens, a child, was drawn one more step of the turn ahead: a long frame overshot, and a frame
# with no mouse in it turned the view back. The rig's own yaw was always right, which is why every
# earlier look test (they read `yaw`) passed. This reads the Camera3D's transform.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const PATH_SECONDS := 2.0
const PATH_SEED := 905
## The frame lengths the path is replayed over.
const FRAME_LENGTHS: Array[float] = [1.0 / 144.0, 1.0 / 60.0, 1.0 / 30.0, 1.0 / 15.0]
## A drawn view within this of the rig's yaw (radians) is the same view.
const SAME_VIEW := 0.0005
## The shipped turn of one mouse pixel (`PlayerTuning.mouse_radians_per_pixel`).
const RADIANS_PER_PIXEL := 0.0022

var _server: NightHost
var _nights: Array[Night] = []


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.queue_free()
	_nights.clear()
	if is_instance_valid(_server):
		_server.get_parent().queue_free()
	await get_tree().process_frame
	Audio.stop_all()


func test_the_drawn_view_is_the_rigs_yaw_at_every_frame_rate_alone() -> void:
	var player := _test_room_player()
	for length in FRAME_LENGTHS:
		var run := _replay(player.camera_rig, _lengths(length))
		(
			assert_float(run["worst"])
			. override_failure_message(
				(
					"frames of %.1f ms: the drawn view was %.4f rad from the rig's yaw"
					% [length * 1000.0, run["worst"]]
				)
			)
			. is_less(SAME_VIEW)
		)


func test_a_frame_without_mouse_never_turns_the_drawn_view_back() -> void:
	var player := _test_room_player()
	for length in FRAME_LENGTHS:
		var run := _replay(player.camera_rig, _lengths(length))
		(
			assert_int(run["back"])
			. override_failure_message(
				(
					"frames of %.1f ms: %d frames turned the drawn view against the hand"
					% [length * 1000.0, run["back"]]
				)
			)
			. is_equal(0)
		)
		(
			assert_int(run["phantom"])
			. override_failure_message(
				(
					"frames of %.1f ms: %d frames turned the drawn view with no mouse"
					% [length * 1000.0, run["phantom"]]
				)
			)
			. is_equal(0)
		)


func test_the_same_path_turns_the_same_total_at_every_frame_rate_and_with_hitches() -> void:
	var player := _test_room_player()
	var totals: Array[float] = []
	var schedules: Array = []
	for length in FRAME_LENGTHS:
		schedules.append(_lengths(length))
	schedules.append(_uneven_lengths())
	for lengths in schedules:
		var run := _replay(player.camera_rig, lengths)
		totals.append(run["drawn_total"])
		assert_float(run["worst"]).is_less(SAME_VIEW)
	for total in totals:
		assert_float(total).is_equal_approx(totals[0], 0.001)
	# The path is not an empty one.
	assert_float(absf(totals[0])).is_greater(0.5)


func test_an_uneven_run_with_hitches_draws_what_the_rig_holds() -> void:
	var player := _test_room_player()
	var run := _replay(player.camera_rig, _uneven_lengths())
	assert_float(run["worst"]).is_less(SAME_VIEW)
	assert_int(run["back"]).is_equal(0)
	assert_int(run["phantom"]).is_equal(0)


## The right stick turns the view at a rate, per second, whatever the frames: the drawn view is the
## rig's yaw and the total of a second is the same over short and long frames.
func test_the_stick_turns_the_drawn_view_the_same_total_at_every_frame_rate() -> void:
	var player := _test_room_player()
	var rig := player.camera_rig
	var totals: Array[float] = []
	for length in FRAME_LENGTHS:
		rig.yaw = 0.0
		rig.set_stick(Vector2(0.8, 0.0))
		var clock := 0.0
		var worst := 0.0
		while clock < 1.0 - 0.0001:
			rig.step(length, 0.5)
			clock += length
			worst = maxf(worst, absf(angle_difference(rig.yaw, _drawn_yaw(rig))))
		rig.set_stick(Vector2.ZERO)
		totals.append(rig.yaw)
		(
			assert_float(worst)
			. override_failure_message(
				"frames of %.1f ms: drawn %.4f rad from the rig's yaw" % [length * 1000.0, worst]
			)
			. is_less(SAME_VIEW)
		)
	for total in totals:
		assert_float(total).is_equal_approx(totals[0], 0.002)


## An online client: its body is the one it moves itself and predicts, on a game server over a real
## socket. The look path is the same one, and the drawn view must be as true there.
func test_a_client_of_a_game_server_draws_the_hand_too() -> void:
	var world := SubViewport.new()
	world.own_world_3d = true
	world.size = Vector2i(64, 64)
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(world)
	_server = NightHost.new()
	_server.port = 0
	_server.log_enabled = false
	_server.seed_value = 7
	world.add_child(_server)
	for _i in 1800:
		if _server.serving:
			break
		await get_tree().physics_frame
	assert_bool(_server.serving).is_true()
	# In the window's own tree: the mouse reaches the player there, as in the game.
	var night := Night.new()
	add_child(night)
	_nights.append(night)
	var url := "ws://127.0.0.1:%d" % _server.listener.port()
	assert_bool(await night.start_remote(url, Night.Mode.HUMAN, 30.0)).is_true()
	var player := night.player()
	assert_object(player).is_not_null()
	player.capture_mouse = false
	var rig := player.camera_rig
	rig.set_process(false)
	var run_60 := _replay(rig, _lengths(1.0 / 60.0))
	var run_15 := _replay(rig, _lengths(1.0 / 15.0))
	var run_uneven := _replay(rig, _uneven_lengths())
	for run in [run_60, run_15, run_uneven]:
		assert_float(run["worst"]).is_less(SAME_VIEW)
		assert_int(run["back"]).is_equal(0)
		assert_int(run["phantom"]).is_equal(0)
	assert_float(run_15["drawn_total"]).is_equal_approx(run_60["drawn_total"], 0.001)
	assert_float(run_uneven["drawn_total"]).is_equal_approx(run_60["drawn_total"], 0.001)


func _test_room_player() -> Player:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	player.camera_rig.set_process(false)
	return player


## Frames of `length` seconds over the whole path.
func _lengths(length: float) -> Array[float]:
	var lengths: Array[float] = []
	var clock := 0.0
	while clock < PATH_SECONDS:
		lengths.append(length)
		clock += length
	return lengths


## 60 Hz frames that vary by a third, with a hitch of 120 ms every 25th frame and a pair of 8 ms
## frames after it: seeded.
func _uneven_lengths() -> Array[float]:
	var random := RandomNumberGenerator.new()
	random.seed = PATH_SEED
	var lengths: Array[float] = []
	var clock := 0.0
	var count := 0
	while clock < PATH_SECONDS:
		count += 1
		var length := clampf(random.randfn(1.0 / 60.0, 1.0 / 180.0), 0.004, 0.04)
		if count % 25 == 0:
			length = 0.12
		elif count % 25 in [1, 2]:
			length = 0.008
		lengths.append(length)
		clock += length
	return lengths


## The path, one whole-pixel motion per millisecond: flicks, tracking and pauses (seeded).
func _path() -> PackedVector2Array:
	var random := RandomNumberGenerator.new()
	random.seed = PATH_SEED
	var total := int(PATH_SECONDS * 1000.0)
	var path := PackedVector2Array()
	path.resize(total)
	var carry := Vector2.ZERO
	var ms := 0
	while ms < total:
		var kind := random.randi_range(0, 2)
		var length := random.randi_range(60, 200)
		var velocity := Vector2.ZERO
		if kind == 0:
			velocity = Vector2(random.randf_range(-300.0, 900.0), random.randf_range(-60.0, 60.0))
		elif kind == 1:
			velocity = Vector2(random.randf_range(-100.0, 300.0), 0.0)
		velocity /= float(length)
		for i in length:
			if ms >= total:
				break
			var bell := 1.5 * sin(PI * float(i) / float(length)) if kind == 0 else 1.0
			var want := velocity * bell + carry
			var whole := Vector2(roundf(want.x), roundf(want.y))
			carry = want - whole
			path[ms] = whole
			ms += 1
	return path


## The yaw of the Camera3D as the renderer sees it.
func _drawn_yaw(rig: ThirdPersonCamera) -> float:
	return rig.camera().global_transform.basis.get_euler(EULER_ORDER_YXZ).y


## How much the window's stretch scales a motion's `relative` (the test window is not 1920 wide, and
## the engine hands the player the motion in the 1920 x 1080 canvas's units): one motion of 10
## pixels says. The path is sent divided by it, so the turn is the same whatever the window.
func _stretch(rig: ThirdPersonCamera) -> float:
	var before := rig.yaw
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(10.0, 0.0)
	event.position = Vector2(640.0, 360.0)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	var turned := absf(angle_difference(before, rig.yaw))
	return turned / (10.0 * RADIANS_PER_PIXEL * rig.sensitivity)


## Replays the path over frames of the given lengths. Before each frame the motions that fell
## inside the previous one reach the player the way the system's do (parsed, then handled at once),
## then the rig is stepped by the frame's length. Returns the biggest distance between the drawn
## view and the rig's yaw, the frames that turned the drawn view against the hand or with no hand,
## and the drawn view's turn.
func _replay(rig: ThirdPersonCamera, lengths: Array[float]) -> Dictionary:
	var path := _path()
	var stretch := _stretch(rig)
	assert_float(stretch).override_failure_message("the player did not hear the mouse").is_greater(
		0.0
	)
	rig.yaw = 0.0
	rig.pitch = 0.0
	rig.step(0.0, 0.5)
	var start := _drawn_yaw(rig)
	var clock := 0.0
	var posted := 0
	var worst := 0.0
	var back := 0
	var phantom := 0
	var last_drawn := start
	var drawn_total := 0.0
	var hand := Vector2.ZERO
	for length in lengths:
		var until := mini(int(round((clock + length) * 1000.0)), path.size())
		var before := hand
		while posted < until:
			var step := path[posted]
			posted += 1
			if step == Vector2.ZERO:
				continue
			hand += step
			var event := InputEventMouseMotion.new()
			event.relative = step / stretch
			event.position = Vector2(640.0, 360.0)
			Input.parse_input_event(event)
		Input.flush_buffered_events()
		clock += length
		rig.step(length, 0.5)
		var drawn := _drawn_yaw(rig)
		worst = maxf(worst, absf(angle_difference(rig.yaw, drawn)))
		var drawn_step := angle_difference(last_drawn, drawn)
		drawn_total += drawn_step
		var hand_x := hand.x - before.x
		if hand_x != 0.0 and drawn_step * -hand_x < 0.0 and absf(drawn_step) > 0.0005:
			back += 1
		if hand_x == 0.0 and absf(drawn_step) > 0.0005:
			phantom += 1
		last_drawn = drawn
	return {
		"worst": worst,
		"back": back,
		"phantom": phantom,
		"drawn_total": drawn_total,
	}
