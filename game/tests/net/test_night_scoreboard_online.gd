# The scoreboard in a night with two players over a real WebSocket: the server counts, every client
# reads the same numbers from its frames (and a late joiner from the welcome snapshot), and the
# ping column is each player's own measured round trip, reported to the server and shown to all.
# The counts are checked against an independent count of the events each client heard.
extends GdUnitTestSuite

const GIVE_UP_SECONDS := 90.0

var _host: NightHost
var _nights: Array[Night] = []
var _huds: Dictionary = {}
## Per client: {"kills": {player: n}, "downs": {player: n}}, counted from the events it heard.
var _heard: Dictionary = {}


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_huds.clear()
	_heard.clear()
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


func _server() -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


## A client with a HUD, in `mode` (a bot plays; a manual one stands still).
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
	_huds[night] = hud
	var heard := {"kills": {}, "downs": {}}
	_heard[night] = heard
	night.state.event_received.connect(
		func(event: Dictionary) -> void:
			match event["type"]:
				&"zombie_removed":
					if event["cause"] == &"killed" and int(event["killer_id"]) >= 0:
						var killer := int(event["killer_id"])
						heard["kills"][killer] = int(heard["kills"].get(killer, 0)) + 1
				&"player_downed":
					var player := int(event["player_id"])
					heard["downs"][player] = int(heard["downs"].get(player, 0)) + 1
	)
	return night


func _rules() -> GameRules:
	return _host.server.rules


## The server's own events, sent on to every client as the game server sends the rules' answers.
func _act(action: Dictionary) -> void:
	_host._collect(_rules().apply(action))


## Every client's HUD, its recorded events and the server's rules say the same count for `player`.
func _agree_on(night: Night, player_id: int) -> bool:
	var member: Dictionary = _huds[night].state.team.get(player_id, {})
	if member.is_empty():
		return false
	var rules := _rules()
	var heard: Dictionary = _heard[night]
	return (
		member["kills"] == rules.kills_of(player_id)
		and member["downs"] == rules.downs_of(player_id)
		and int(heard["kills"].get(player_id, 0)) == rules.kills_of(player_id)
		and int(heard["downs"].get(player_id, 0)) == rules.downs_of(player_id)
	)


func _everyone_agrees() -> bool:
	for night in _nights:
		for player_id in [1, 2]:
			if not _agree_on(night, player_id):
				return false
	return true


func test_two_bots_and_a_late_joiner_all_read_the_servers_kills_and_downs() -> void:
	await _server()
	var a := await _client(Night.Mode.AUTOPILOT)
	var b := await _client(Night.Mode.AUTOPILOT)
	var rules := _rules()
	_act(RulesAction.skip_break())
	# The bots play the first round for real; the scoreboard is tested on what they did.
	var played := await _until(
		func() -> bool: return rules.kills_of(1) + rules.kills_of(2) >= 4, GIVE_UP_SECONDS
	)
	assert_bool(played).is_true()
	# Each player is also taken down in the way the night does it (a blow), so both counts are
	# there to read, and the second player twice.
	# Never both at once: that ends the night.
	_act(RulesAction.blow(1, 99999.0))
	_act(RulesAction.set_downed(1, false))
	_act(RulesAction.blow(2, 99999.0))
	_act(RulesAction.set_downed(2, false))
	_act(RulesAction.blow(2, 99999.0))
	var kills_1 := rules.kills_of(1)
	var kills_2 := rules.kills_of(2)
	assert_int(rules.downs_of(1)).is_equal(1)
	assert_int(rules.downs_of(2)).is_equal(2)
	# Let them read it: every count settles and the three views agree (the bots go on shooting, a
	# count may still move, so the check is that they meet).
	assert_bool(await _until(_everyone_agrees, 20.0)).is_true()
	assert_int(rules.kills_of(1)).is_greater_equal(kills_1)
	assert_int(rules.kills_of(2)).is_greater_equal(kills_2)
	# Every screen draws the same board: the names, kills and downs (points arrive by events and
	# the ping column is each screen's own view of the others, so they are not compared).
	for night: Night in [a, b]:
		_huds[night].scoreboard.set_shown(true)
	await get_tree().physics_frame
	var board_a: HudScoreboard = _huds[a].scoreboard
	var board_b: HudScoreboard = _huds[b].scoreboard
	assert_int(board_a.rows_text.size()).is_equal(2)
	assert_array(board_a.row_ids).is_equal([1, 2])
	for row in 2:
		for column in 3:
			assert_str(board_a.rows_text[row][column]).is_equal(board_b.rows_text[row][column])
	assert_int(_huds[a].state.night_clock).is_greater(0)
	assert_int(absi(_huds[a].state.night_clock - _huds[b].state.night_clock)).is_less_equal(1)
	# A third player joins in the middle and reads the same counts from the welcome snapshot.
	var late := await _client(Night.Mode.MANUAL)
	var late_hud: Hud = _huds[late]
	assert_int(late_hud.state.team[2]["downs"]).is_greater_equal(2)
	assert_bool(late_hud.state.team.has(1)).is_true()
	assert_int(late_hud.state.team[1]["kills"]).is_greater_equal(kills_1)
	assert_int(late_hud.state.team[2]["kills"]).is_greater_equal(kills_2)


func test_each_player_sees_every_players_ping() -> void:
	await _server()
	var a := await _client(Night.Mode.MANUAL)
	var b := await _client(Night.Mode.MANUAL)
	var seen := func() -> bool:
		for night in [a, b]:
			var team: Dictionary = _huds[night].state.team
			for player_id in [1, 2]:
				if not team.has(player_id) or int(team[player_id]["ping"]) < 0:
					return false
		return true
	# A ping goes up twice a second and the answer comes back at once: a second or two is enough.
	assert_bool(await _until(seen, 10.0)).is_true()
	var server_view := _host.server.pings
	assert_array(server_view.keys()).contains_exactly_in_any_order([1, 2])
	for night: Night in [a, b]:
		var board: HudScoreboard = _huds[night].scoreboard
		board.set_shown(true)
		assert_bool(board.has_ping).is_true()
		assert_array(board.headings).is_equal(["PLAYER", "KILLS", "DOWNS", "POINTS", "PING"])
		for row in board.rows_text:
			# On this machine a round trip is a few milliseconds; the point is that it is a number
			# a client measured and the server passed on, not a default.
			assert_int(int(row[4])).is_between(0, 500)
	# The ping on the board is the one in the server's frame, and the server holds what was reported.
	assert_int(_huds[b].state.team[1]["ping"]).is_equal(
		_nights[1].state.frame["players"][1]["ping"]
	)
	# A player who leaves takes their ping off the server and the board.
	_nights[0].link.close()
	assert_bool(await _until(func() -> bool: return not _host.server.pings.has(1), 10.0)).is_true()
	(
		assert_bool(await _until(func() -> bool: return not _huds[_nights[1]].state.team.has(1)))
		. is_true()
	)
