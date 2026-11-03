# A player who leaves the playable space is put back at the start by the server, and the clients
# follow it (issue #862), over a real WebSocket on both maps: the frame names the new place within
# a second, the other client draws the avatar there and never gliding across the map between, and a
# played body is brought back at once with its camera (the correction snaps, the camera does not
# trail). The rule itself is `tests/night/test_out_of_bounds.gd`, the bounds are
# `tests/world/test_play_bounds.gd`.
extends GdUnitTestSuite

const SMALL_ID := "small_indoor"
## The server puts the body back within the grace and a tick; the frame reaches the client a few
## ticks later. The issue asks for a second.
const WITHIN_SECONDS := 1.0
## How close to the start marker a body is when it is back.
const AT_START := 0.5
## An avatar or camera sample farther than this from both ends of the trip is a glide.
const GLIDE_FREE := 3.0
## The most a camera sits from its body (the arm, the shoulder and the aim pull-in).
const CAMERA_ARM := 8.0
## The grace the played-body test gives the server, to let the walk out settle first.
const SETTLE_GRACE := 1.5

var _host: NightHost
var _nights: Array[Night] = []


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _until(condition: Callable, seconds: float = 10.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


## A night where no zombie comes for ten minutes, on the map `map_id`.
func _server(map_id: String) -> NightHost:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.rules_tuning = tuning
	_host.match_settings = MatchSettings.new()
	_host.match_settings.map = map_id
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


func _client(mode: Night.Mode) -> Night:
	var world := _world()
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	world.add_child(hud)
	var night := Night.new()
	night.hud = hud
	world.add_child(night)
	var joined := await night.start_remote("ws://127.0.0.1:%d" % _host.listener.port(), mode, 30.0)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


func _frame_pos(night: Night, player_id: int) -> Vector3:
	return night.state.frame.get("players", {}).get(player_id, {}).get("pos", Vector3.INF)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _scene(map_id: String) -> Array[Night]:
	await _server(map_id)
	var a := await _client(Night.Mode.HUMAN)
	var b := await _client(Night.Mode.MANUAL)
	_host._collect(_host.server.rules.apply(RulesAction.skip_break()))
	# Both are in the world and standing at their markers.
	var ready := func() -> bool: return _frame_pos(a, 2) != Vector3.INF and a.player() != null
	assert_bool(await _until(ready)).is_true()
	await get_tree().create_timer(0.5).timeout
	return [a, b]


## The other client's player leaves the map: the server's body of player 2 is put at `out`. The
## first client's drawn avatar of them is sampled every drawn frame until it is back at the start.
func _someone_else_leaves(map_id: String, out: Vector3) -> void:
	var pair := await _scene(map_id)
	var a := pair[0]
	var start := _host.world.player_spawn(1)
	var avatar := a.avatars.avatar(2)
	assert_object(avatar).is_not_null()
	assert_float(_flat(avatar.global_position, start)).is_less(AT_START)
	_host.server.body_of(2).teleport(out)
	var began := Time.get_ticks_msec()
	var farthest_from_both := 0.0
	var seen_out := false
	var gone := false
	while true:
		await get_tree().process_frame
		gone = gone or _flat(_frame_pos(a, 2), out) < AT_START
		var at := avatar.global_position
		seen_out = seen_out or _flat(at, out) < AT_START
		farthest_from_both = maxf(farthest_from_both, minf(_flat(at, out), _flat(at, start)))
		if gone and _flat(_frame_pos(a, 2), start) < AT_START and _flat(at, start) < AT_START:
			break
		(
			assert_float((Time.get_ticks_msec() - began) / 1000.0)
			. override_failure_message(
				"avatar at %s, frame at %s, a second later" % [at, _frame_pos(a, 2)]
			)
			. is_less(WITHIN_SECONDS + 1.0)
		)
	assert_bool(gone).is_true()
	# It was drawn out there until the server moved it, then at the start, nowhere between.
	assert_bool(seen_out).is_true()
	(
		assert_float(farthest_from_both)
		. override_failure_message(
			"the avatar glided: %.1f m from both ends of the trip" % farthest_from_both
		)
		. is_less(GLIDE_FREE)
	)


func test_the_other_screen_sees_the_player_back_at_the_start_in_the_lot_without_a_glide() -> void:
	await _someone_else_leaves(MapRegistry.DEFAULT, Vector3(66.0, 0.0, 20.0))


func test_the_other_screen_sees_the_player_back_at_the_start_on_the_second_map() -> void:
	await _someone_else_leaves(SMALL_ID, Vector3(40.0, 0.5, 0.0))


## The played body walked out: the client's body and the server's are both past the wall, as they
## are after a walk (the client's record of its commands says so). The server's answer is the
## start, and the body and the camera are there at once.
func _own_body_leaves(map_id: String, out: Vector3) -> void:
	var pair := await _scene(map_id)
	var a := pair[0]
	# A longer wait than the shipped one, so the walk out settles on both sides before the return.
	_host.server.tuning = _host.server.tuning.duplicate()
	_host.server.tuning.out_of_bounds_seconds = SETTLE_GRACE
	var start := _host.world.player_spawn(0)
	var body := a.player()
	assert_float(_flat(body.global_position, start)).is_less(AT_START)
	body.teleport(out)
	_host.server.body_of(1).teleport(out)
	a.reconciler.reset()
	var cameras := body.camera_rig.find_children("*", "Camera3D", true, false)
	assert_int(cameras.size()).is_greater(0)
	var camera := cameras[0] as Camera3D
	var settled := func() -> bool:
		return (
			_flat(_frame_pos(a, 1), out) < AT_START
			and _flat(body.global_position, out) < AT_START
			and camera.global_position.distance_to(body.global_position) < CAMERA_ARM
		)
	(
		assert_bool(await _until(settled, 5.0))
		. override_failure_message(
			"out there: body %s, frame %s" % [body.global_position, _frame_pos(a, 1)]
		)
		. is_true()
	)
	for _i in 10:
		await get_tree().physics_frame
	assert_float(_flat(body.global_position, out)).is_less(AT_START)
	# The server's turn: the body is put at the start; the camera is never left behind.
	var began := Time.get_ticks_msec()
	var farthest_camera := 0.0
	var returned := false
	var moved_to := body.global_position
	while true:
		await get_tree().process_frame
		farthest_camera = maxf(farthest_camera, _camera_lag(camera, body, moved_to))
		moved_to = body.global_position
		returned = returned or _flat(_frame_pos(a, 1), start) < AT_START
		if returned and _flat(body.global_position, start) < AT_START:
			break
		(
			assert_float((Time.get_ticks_msec() - began) / 1000.0)
			. override_failure_message(
				"body at %s, frame at %s" % [body.global_position, _frame_pos(a, 1)]
			)
			. is_less(SETTLE_GRACE + WITHIN_SECONDS)
		)
	for _i in 10:
		await get_tree().process_frame
		farthest_camera = maxf(farthest_camera, _camera_lag(camera, body, moved_to))
		moved_to = body.global_position
	(
		assert_float(farthest_camera)
		. override_failure_message("the camera was %.1f m from its body" % farthest_camera)
		. is_less(CAMERA_ARM)
	)
	assert_float(a.reconciler.worst_error).is_greater(Reconciler.SNAP)


## How far the camera is from the body, as the player sees it: the camera is placed after the
## frame's physics, so the frame the body was moved in is not judged (it is drawn after the move).
func _camera_lag(camera: Camera3D, body: Player, was_at: Vector3) -> float:
	if body.global_position.distance_to(was_at) > 1.0:
		return 0.0
	return camera.global_position.distance_to(body.global_position)


func test_a_played_body_is_brought_back_in_the_lot_with_its_camera() -> void:
	await _own_body_leaves(MapRegistry.DEFAULT, Vector3(-66.0, 0.0, 20.0))


func test_a_played_body_is_brought_back_on_the_second_map_with_its_camera() -> void:
	await _own_body_leaves(SMALL_ID, Vector3(0.0, 0.5, 32.0))
