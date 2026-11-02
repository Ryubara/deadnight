# A client whose own game loop freezes for a moment (the first flare shot loading its effect is
# one) comes back where the server has the player, and stays with it (#483). The server runs as a
# process of its own, so the freeze stops only the client, as it does for a player; the link has
# the delay of a real connection (100 ms each way) and the client is a person walking to and fro
# with the keys. After each freeze the player stops and must settle on the server's position, and
# at no time may the body leave the lot.
extends GdUnitTestSuite

const WALK_SECONDS := 2.0
const STOP_SECONDS := 3.0
## Each freeze, in milliseconds.
const FREEZES_MS := [0, 500, 2000, 5000]
const ONE_WAY_DELAY := 0.1
## How far a body may be from where the server has it, once the player stopped.
const SETTLED := 0.3
## How far from the first spot a body may be, the lot being a few dozen metres across.
const MOST_AWAY := 60.0
## How far the body may be from the server's position while the player walks after a freeze: the
## lead a 200 ms round trip gives a sprint (1.8 m), and the half second the server goes on with the
## last command of a client that went quiet (`NightTuning.command_ticks`, 3 m), then it snaps back.
## Before the fix this grew without bound.
const MOST_OFF := 8.0

var _pid := 0
var _night: Night
var _log_path := ""
## `FREEZE_CSV=path` writes where both sides had the player, each frame (for a plot).
var _rows := PackedStringArray(["frame,freeze_ms,client_x,client_z,server_x,server_z,gap"])


func after_test() -> void:
	_write_rows()
	for action in [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint"]:
		Input.action_release(action)
	if is_instance_valid(_night):
		_night.get_parent().queue_free()
	if _pid > 0:
		OS.kill(_pid)
		_pid = 0
	if _log_path != "":
		DirAccess.remove_absolute(_log_path)


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _free_port() -> int:
	var tcp := TCPServer.new()
	tcp.listen(0)
	var port := tcp.get_local_port()
	tcp.stop()
	return port


## Starts a game server in a process of its own and waits for it to say it listens.
func _start_server(port: int) -> bool:
	_log_path = OS.get_user_data_dir().path_join("freeze_server_%d.log" % port)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	_pid = (
		OS
		. create_process(
			OS.get_executable_path(),
			[
				"--headless",
				"--log-file",
				_log_path,
				"--path",
				ProjectSettings.globalize_path("res://"),
				"--quit-after",
				"20000",
				"--",
				"--server",
				"--port",
				str(port),
				"--seed",
				"7",
			]
		)
	)
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 60000:
		if (
			FileAccess.file_exists(_log_path)
			and FileAccess.get_file_as_string(_log_path).contains('"listening"')
		):
			return true
		await get_tree().create_timer(0.25).timeout
	return false


## The keys of a person walking left for a second, then right, and so on; none if not `walking`.
func _walk(frame: int, walking: bool) -> void:
	var left := walking and (frame / 60) % 2 == 0
	var right := walking and not left
	for pair in [[&"move_left", left], [&"move_right", right]]:
		if pair[1]:
			Input.action_press(pair[0])
		else:
			Input.action_release(pair[0])
	if walking:
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")


func _server_position() -> Vector3:
	return _night.state.position()


func _gap() -> float:
	return _night.player().state.position.distance_to(_server_position())


func test_a_client_that_freezes_comes_back_to_the_server_and_stays_with_it() -> void:
	var port := _free_port()
	assert_bool(await _start_server(port)).is_true()
	var link := WebSocketLink.new()
	link.conditioner_in = LinkConditioner.new(ONE_WAY_DELAY, 0.0, 1)
	link.conditioner_out = LinkConditioner.new(ONE_WAY_DELAY, 0.0, 2)
	_night = Night.new()
	_world().add_child(_night)
	var joined := await _night.start_remote(
		"ws://127.0.0.1:%d" % port, Night.Mode.HUMAN, 30.0, link
	)
	assert_bool(joined).is_true()
	var start := _night.player().state.position
	var frame := 0
	var report: Array[String] = []
	for freeze_ms: int in FREEZES_MS:
		var worst := 0.0
		for _i in int(WALK_SECONDS * 60.0):
			await get_tree().physics_frame
			frame += 1
			_walk(frame, true)
			_note(frame, freeze_ms)
		OS.delay_msec(freeze_ms)
		# The seconds after the freeze, still walking: the body may be corrected, never thrown.
		for _i in int(WALK_SECONDS * 60.0):
			await get_tree().physics_frame
			frame += 1
			_walk(frame, true)
			worst = maxf(worst, _gap())
			_note(frame, freeze_ms)
			assert_bool(_night.player().state.position.is_finite()).is_true()
			assert_float(_night.player().state.position.distance_to(start)).is_less(MOST_AWAY)
		for _i in int(STOP_SECONDS * 60.0):
			await get_tree().physics_frame
			frame += 1
			_walk(frame, false)
			_note(frame, freeze_ms)
		var settled := _gap()
		report.append(
			"freeze %d ms: worst gap %.2f m, settled %.2f m" % [freeze_ms, worst, settled]
		)
		print("client freeze: ", report[-1])
		_write_rows()
		(
			assert_float(worst)
			. override_failure_message(
				"after a %d ms freeze the body was %s m from the server" % [freeze_ms, worst]
			)
			. is_less(MOST_OFF)
		)
		(
			assert_float(settled)
			. override_failure_message(
				(
					"after a %d ms freeze and a stop the body is %s m from the server"
					% [freeze_ms, settled]
				)
			)
			. is_less(SETTLED)
		)
		assert_float(_night.player().state.position.distance_to(start)).is_less(MOST_AWAY)


func _write_rows() -> void:
	var csv_path := OS.get_environment("FREEZE_CSV")
	if csv_path != "":
		var file := FileAccess.open(csv_path, FileAccess.WRITE)
		file.store_string("\n".join(_rows))


func _note(frame: int, freeze_ms: int) -> void:
	var body := _night.player().state.position
	var server := _server_position()
	_rows.append(
		(
			"%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f"
			% [frame, freeze_ms, body.x, body.z, server.x, server.z, body.distance_to(server)]
		)
	)
