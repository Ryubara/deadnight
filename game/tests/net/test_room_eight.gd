# A full room, eight seats over real WebSockets on this machine (#690): the server and its clients
# each live in their own SubViewport world, the clients are hand-driven `Night`s that joined with
# `start_remote`. Eight people, and five people with three bots, join one night and see each other;
# the round runs with a crowd of the dead for a while with everyone walking and shooting, and what
# the server sent and received is counted in bytes per player per second of game time (the 60 Hz
# step counts the time, so a loaded machine does not change the number).
#
# The numbers are `docs/research/multiplayer.md#eight-players-690`. The limits asserted here are
# the budget with room to spare: a client over a phone's link takes a few tens of KB/s down.
extends GdUnitTestSuite

const STEP := Night.STEP
## Game seconds the crowd is given to gather before the bytes are counted, and game seconds counted.
const GATHER_SECONDS := 8.0
const MEASURE_SECONDS := 10.0
## The most a person is sent in a second with eight players and a crowd, bytes (the budget), and
## the most a person sends (a command is 25 bytes, 60 times a second at most).
const DOWN_BUDGET := 30000.0
const UP_BUDGET := 2000.0

var _host: NightHost
var _nights: Array[Night] = []
var _commands: Dictionary = {}


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_commands.clear()
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


func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _server(bots: int) -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 11
	var settings := MatchSettings.new()
	settings.bots = bots
	_host.match_settings = settings
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


## A hand-driven client: it sends whatever `_commands` holds for it, every tick.
func _client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var joined := await night.start_remote(
		"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.MANUAL, 30.0
	)
	assert_bool(joined).is_true()
	_nights.append(night)
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void: night.link.send((_commands[night] as NightCommand).to_dict())
	)
	return night


## Everyone walks a circle of their own and holds the trigger, so every frame changes.
func _drive(night: Night, index: int, tick: int) -> void:
	var command := _commands[night] as NightCommand
	var turn := float(tick) * 0.02 + float(index)
	command.motion.move = Vector2(sin(turn), -cos(turn))
	command.motion.yaw = turn
	command.fire = (tick / 20 + index) % 3 != 0
	command.motion.fire = command.fire


## Runs `seconds` of game time, driving the clients; returns the steps taken.
func _play(people: Array[Night], seconds: float, from_tick: int) -> int:
	var steps := roundi(seconds / STEP)
	for tick in steps:
		for i in people.size():
			_drive(people[i], i, from_tick + tick)
		await get_tree().physics_frame
	return steps


## Joins `more` clients to `joined` and returns them once every one has seen `seats` players.
func _fill(joined: Array[Night], more: int, seats: int) -> Array[Night]:
	for _i in more:
		joined.append(await _client())
	for night in joined:
		var seen := func() -> bool:
			return (night.state.frame["players"] as Dictionary).size() == seats
		var saw: bool = await _until(seen)
		(
			assert_bool(saw)
			. override_failure_message("a client never saw all %d seats" % seats)
			. is_true()
		)
	return joined


func _measure(label: String, people: Array[Night], first := true) -> Dictionary:
	if first:
		_host.server.rules.apply(RulesAction.skip_break())
	var tick := await _play(people, GATHER_SECONDS, 0)
	var steps_before := _host.steps
	var out_before := _host.listener.bytes_out
	var in_before := _host.listener.bytes_in
	var taken := await _play(people, MEASURE_SECONDS, tick)
	var seconds := float(_host.steps - steps_before) * STEP
	var down := float(_host.listener.bytes_out - out_before) / seconds / float(people.size())
	var up := float(_host.listener.bytes_in - in_before) / seconds / float(people.size())
	var alive := _host.server.rules.zombie_ids().size()
	print(
		(
			"EIGHT %s: %d people, %d players, %d zombies alive, %d steps: down %.0f B/s, up %.0f B/s"
			% [label, people.size(), _host.server.rules.players.size(), alive, taken, down, up]
		)
	)
	return {"down": down, "up": up, "alive": alive}


func test_eight_people_share_one_night_and_the_bytes_per_person_stay_in_budget() -> void:
	await _server(0)
	# Four first, for the number to compare with: then four more join the same night.
	var people: Array[Night] = []
	await _fill(people, 4, 4)
	var four := await _measure("4 people", people)
	await _fill(people, NightHost.MAX_PLAYERS - 4, NightHost.MAX_PLAYERS)
	assert_int(_host.player_count()).is_equal(NightHost.MAX_PLAYERS)
	for i in people.size():
		assert_int(people[i].state.player_id).is_equal(i + 1)
	var eight := await _measure("8 people", people, false)
	assert_float(eight["down"]).is_less(DOWN_BUDGET)
	assert_float(eight["up"]).is_less(UP_BUDGET)
	assert_int(eight["alive"]).is_greater(0)
	# A person is sent every player's state, so the bytes grow with the players, about in step with
	# them (twice the players is a little over twice the bytes, never the square).
	assert_float(eight["down"]).is_greater(four["down"])
	assert_float(eight["down"]).is_less(four["down"] * 3.0)
	# Every client agrees on where every seat stands.
	for night in people:
		assert_int((night.state.frame["players"] as Dictionary).size()).is_equal(
			NightHost.MAX_PLAYERS
		)


func test_five_people_and_three_bots_share_one_night_and_the_bytes_per_person_stay_in_budget(
) -> void:
	await _server(3)
	var people: Array[Night] = []
	await _fill(people, 5, NightHost.MAX_PLAYERS)
	assert_int(_host.player_count()).is_equal(5)
	assert_int(_host.bots.count()).is_equal(3)
	assert_array(_host.bots.seats()).is_equal([6, 7, 8])
	var seen := await _measure("people+bots", people)
	assert_float(seen["down"]).is_less(DOWN_BUDGET)
	assert_float(seen["up"]).is_less(UP_BUDGET)
