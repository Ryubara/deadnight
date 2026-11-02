# Teammate revives in a night with two players over a real WebSocket (docs/design/revive.md): the
# server decides who is in reach and counts the hold; both screens draw the same ring from the
# frames; a hold is broken by walking away, by firing and by the reviver going down; a player nobody
# reaches bleeds out and is dead; the count is the server's and a late joiner reads it from the
# welcome; and a bot pulls a bot up with the commands a player sends. The rules' own checks are
# `tests/rules/test_revive.gd`; the HUD's parts are `tests/ui/test_hud_revive.gd`.
extends GdUnitTestSuite

var _host: NightHost
var _nights: Array[Night] = []
var _huds: Dictionary = {}
var _commands: Dictionary = {}
## Per client, the events of these types it heard, in order.
var _heard: Dictionary = {}


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_huds.clear()
	_commands.clear()
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


## A night where no zombie comes for ten minutes: the revive is the only thing happening.
func _quiet_tuning(bleed_seconds := -1.0) -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	if bleed_seconds > 0.0:
		tuning.revive.bleed_out_seconds = bleed_seconds
	return tuning


func _server(tuning: RulesTuning = null) -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.rules_tuning = tuning
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


## A client with a HUD. A MANUAL one sends whatever `_commands` holds for it, every tick.
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
	var heard: Array[Dictionary] = []
	_heard[night] = heard
	night.state.event_received.connect(
		func(event: Dictionary) -> void:
			if (
				event["type"]
				in [
					&"player_downed",
					&"player_revived",
					&"player_died",
					&"revive_started",
					&"revive_stopped",
				]
			):
				heard.append(event)
	)
	if mode == Night.Mode.MANUAL:
		_commands[night] = NightCommand.new()
		night.ticked.connect(
			func() -> void:
				# A night freed after the test may tick once more, with nothing left to send.
				var command: NightCommand = _commands.get(night)
				if command != null:
					night.link.send(command.to_dict())
		)
	return night


func _rules() -> GameRules:
	return _host.server.rules


## The server's own action, sent on to every client as the game server sends the rules' answers.
func _act(action: Dictionary) -> void:
	_host._collect(_rules().apply(action))


func _count(night: Night, type: StringName, reason := &"") -> int:
	var found := 0
	for event: Dictionary in _heard[night]:
		if event["type"] == type and (reason == &"" or event.get("reason", &"") == reason):
			found += 1
	return found


func _first_heard(night: Night, type: StringName) -> Dictionary:
	for event: Dictionary in _heard[night]:
		if event["type"] == type:
			return event
	return {}


func _player_in(night: Night, player_id: int) -> Dictionary:
	return night.state.frame.get("players", {}).get(player_id, {})


## The reviver's server body is put `metres` from the patient's, on the same ground.
func _stand_beside(reviver: int, patient: int, metres := 1.0) -> void:
	var at := _host.server.body_of(patient).global_position + Vector3(metres, 0.0, 0.0)
	_host.server.body_of(reviver).teleport(at)


func _hold(night: Night, press := true) -> void:
	var command: NightCommand = _commands[night]
	command.use_held = true
	command.use = press


func _let_go(night: Night) -> void:
	var command: NightCommand = _commands[night]
	command.use_held = false
	command.use = false
	command.fire = false


## Two manual players in round one with nobody to fight, the first on the ground.
func _scene(bleed_seconds := -1.0, a_mode := Night.Mode.MANUAL) -> Array[Night]:
	var tuning := _quiet_tuning(bleed_seconds)
	await _server(tuning)
	var a := await _client(a_mode)
	var b := await _client(Night.Mode.MANUAL)
	_act(RulesAction.skip_break())
	_act(RulesAction.blow(1, 99999.0))
	(
		assert_bool(await _until(func() -> bool: return _player_in(b, 1).get("downed", false)))
		. is_true()
	)
	return [a, b]


func test_a_hold_beside_a_downed_teammate_shows_the_ring_on_both_screens_and_gets_them_up() -> void:
	var pair := await _scene()
	var a := pair[0]
	var b := pair[1]
	var rules := _rules()
	# Out of reach nothing is offered and nothing happens.
	_hold(b)
	await get_tree().create_timer(0.5).timeout
	assert_int(_host.server.revive().holder_of(1)).is_equal(0)
	assert_int(_host.server.revive().in_reach(2)).is_equal(0)
	# Beside the body the prompt names the teammate and the hold starts.
	_stand_beside(2, 1, 1.0)
	(
		assert_bool(await _until(func() -> bool: return _host.server.revive().holder_of(1) == 2))
		. is_true()
	)
	var offered := func() -> bool:
		return _player_in(b, 2).get("prompt", {}).get("kind", &"") == &"revive"
	assert_bool(await _until(offered, 10.0)).is_true()
	assert_int(_player_in(b, 2)["prompt"]["id"]).is_equal(1)
	# Both screens draw the ring from the frames: the reviver's and the downed player's.
	var ring_on_both := func() -> bool:
		return (
			_huds[a].revive.mode == HudRevive.Mode.BEING_REVIVED
			and _huds[b].revive.mode == HudRevive.Mode.REVIVING
			and _huds[a].revive.fraction > 0.1
			and _huds[b].revive.fraction > 0.1
		)
	assert_bool(await _until(ring_on_both, 10.0)).is_true()
	assert_str(_huds[b].revive.line_text).is_equal(
		"REVIVING %s" % _huds[b].state.team[1]["name"].to_upper()
	)
	assert_bool(_huds[a].health.hint_text.begins_with("BEING PULLED UP")).is_true()
	# The server's number is the one on the frame.
	assert_float(_player_in(a, 1)["revive"]).is_between(0.0, 1.0)
	assert_int(_player_in(a, 1)["reviver"]).is_equal(2)
	# It is over after the hold's time and says who did it, to everyone.
	assert_bool(await _until(func() -> bool: return not rules.players[1].downed, 10.0)).is_true()
	_let_go(b)
	assert_int(rules.revives_of(2)).is_equal(1)
	assert_int(rules.revives_of(1)).is_equal(0)
	assert_bool(await _until(func() -> bool: return _count(a, &"player_revived") == 1)).is_true()
	assert_bool(await _until(func() -> bool: return _count(b, &"player_revived") == 1)).is_true()
	for night: Night in [a, b]:
		var revived: Dictionary = _first_heard(night, &"player_revived")
		assert_int(revived["player_id"]).is_equal(1)
		assert_int(revived["reviver_id"]).is_equal(2)
	# Both HUDs count it for the reviver, and the ring is gone.
	var counted := func() -> bool:
		return (
			_huds[a].state.team[2]["revives"] == 1
			and _huds[b].state.team[2]["revives"] == 1
			and _huds[a].revive.mode == HudRevive.Mode.NONE
			and _huds[b].revive.mode == HudRevive.Mode.NONE
		)
	assert_bool(await _until(counted, 10.0)).is_true()
	# The scoreboard's column shows it on both screens.
	for night: Night in [a, b]:
		_huds[night].scoreboard.set_shown(true)
	await get_tree().physics_frame
	for night: Night in [a, b]:
		var board: HudScoreboard = _huds[night].scoreboard
		assert_str(board.headings[3]).is_equal("REVIVES")
		assert_str(board.rows_text[1][3]).is_equal("1")
		assert_str(board.rows_text[0][3]).is_equal("0")
	# A third player who joins now reads the count from the welcome snapshot.
	var late := await _client(Night.Mode.MANUAL)
	assert_int(_huds[late].state.team[2]["revives"]).is_equal(1)
	assert_int(_huds[late].state.team[1]["revives"]).is_equal(0)
	assert_bool(_huds[late].state.team[1]["downed"]).is_false()


## What each screen draws of a person on the ground and of the one kneeling at them (#504): the
## player's own body and the other client's drawn avatar of them, through the server's events and
## frames, not through a call on the animation.
func test_the_downed_pose_and_the_kneel_show_on_both_screens_and_ease_back() -> void:
	# The downed player is a played body (a human's own, with the camera); the other is a seat.
	var pair := await _scene(-1.0, Night.Mode.HUMAN)
	var a := pair[0]
	var b := pair[1]
	var weight := func(night: Night, player_id: int, kind: StringName) -> float:
		var animation := night._animation_of(player_id)
		if animation == null:
			return -1.0
		return animation.downed_weight() if kind == &"downed" else animation.kneel_weight()
	assert_object(a.player()).is_not_null()
	assert_object(a._body_of(1)).is_same(a.player())
	# Down: the player's own body and the other client's avatar of them lie in the pose, eased.
	var down_on_both := func() -> bool:
		return weight.call(a, 1, &"downed") > 0.99 and weight.call(b, 1, &"downed") > 0.99
	assert_bool(await _until(down_on_both)).is_true()
	assert_float(weight.call(a, 2, &"downed")).is_equal(0.0)
	assert_float(weight.call(b, 2, &"downed")).is_equal(0.0)
	# The hold: the reviver kneels on their own screen and on the downed player's; the patient stays
	# down.
	_stand_beside(2, 1, 1.0)
	_hold(b)
	var kneel_on_both := func() -> bool:
		return weight.call(a, 2, &"kneel") > 0.99 and weight.call(b, 2, &"kneel") > 0.99
	assert_bool(await _until(kneel_on_both)).is_true()
	assert_float(weight.call(a, 1, &"kneel")).is_equal(0.0)
	assert_float(weight.call(a, 1, &"downed")).is_greater(0.99)
	# Walking away drops the kneel on both screens and leaves the patient on the ground.
	_stand_beside(2, 1, 6.0)
	var up_again := func() -> bool:
		return weight.call(a, 2, &"kneel") < 0.01 and weight.call(b, 2, &"kneel") < 0.01
	assert_bool(await _until(up_again)).is_true()
	assert_float(weight.call(b, 1, &"downed")).is_greater(0.99)
	# A hold that is finished gets the patient up (the weight eases, it does not flip) and the
	# reviver off their knee, on both screens.
	_stand_beside(2, 1, 1.0)
	var finished := func() -> bool: return not _rules().players[1].downed
	assert_bool(await _until(finished, 15.0)).is_true()
	_let_go(b)
	var standing := func() -> bool:
		return (
			weight.call(a, 1, &"downed") < 0.01
			and weight.call(b, 1, &"downed") < 0.01
			and weight.call(a, 2, &"kneel") < 0.01
			and weight.call(b, 2, &"kneel") < 0.01
		)
	assert_bool(await _until(standing, 15.0)).is_true()


func test_a_hold_is_broken_by_walking_away_and_by_the_reviver_going_down() -> void:
	var pair := await _scene()
	var a := pair[0]
	var b := pair[1]
	var rules := _rules()
	_stand_beside(2, 1)
	_hold(b)
	(
		assert_bool(await _until(func() -> bool: return _host.server.revive().progress(1) > 0.25))
		. is_true()
	)
	# Walks away: out of reach the hold breaks, on both screens, and the progress is lost.
	_stand_beside(2, 1, 6.0)
	(
		assert_bool(await _until(func() -> bool: return _host.server.revive().holder_of(1) == 0))
		. is_true()
	)
	assert_float(_host.server.revive().progress(1)).is_equal(0.0)
	(
		assert_bool(
			await _until(func() -> bool: return _count(a, &"revive_stopped", &"released") == 1)
		)
		. is_true()
	)
	(
		assert_bool(
			await _until(func() -> bool: return _count(b, &"revive_stopped", &"released") == 1)
		)
		. is_true()
	)
	assert_bool(rules.players[1].downed).is_true()
	(
		assert_bool(
			await _until(func() -> bool: return _huds[a].revive.mode == HudRevive.Mode.DOWNED)
		)
		. is_true()
	)
	assert_float(_player_in(a, 1)["revive"]).is_equal(0.0)
	# Back beside the body it starts from nothing, not from where it stopped.
	_stand_beside(2, 1)
	(
		assert_bool(await _until(func() -> bool: return _host.server.revive().holder_of(1) == 2))
		. is_true()
	)
	assert_float(_host.server.revive().progress(1)).is_less(0.2)
	(
		assert_bool(await _until(func() -> bool: return _host.server.revive().progress(1) > 0.25))
		. is_true()
	)
	# The reviver goes down mid-hold: the hold is over and says so.
	(
		assert_bool(await _until(func() -> bool: return _host.server.revive().holder_of(1) == 2))
		. is_true()
	)
	(
		assert_bool(await _until(func() -> bool: return _host.server.revive().progress(1) > 0.1))
		. is_true()
	)
	_act(RulesAction.blow(2, 99999.0))
	(
		assert_bool(await _until(func() -> bool: return _count(a, &"revive_stopped", &"down") == 1))
		. is_true()
	)
	assert_int(_host.server.revive().holder_of(1)).is_equal(0)
	assert_int(rules.revives_of(2)).is_equal(0)


func test_a_player_nobody_reaches_bleeds_out_and_cannot_be_revived() -> void:
	var pair := await _scene(3.0)
	var a := pair[0]
	var b := pair[1]
	var rules := _rules()
	assert_bool(await _until(func() -> bool: return rules.is_dead(1), 20.0)).is_true()
	assert_bool(await _until(func() -> bool: return _count(a, &"player_died") == 1)).is_true()
	assert_bool(await _until(func() -> bool: return _count(b, &"player_died") == 1)).is_true()
	assert_bool(await _until(func() -> bool: return _player_in(b, 1).get("dead", false))).is_true()
	(
		assert_bool(
			await _until(func() -> bool: return _huds[a].revive.mode == HudRevive.Mode.DEAD)
		)
		. is_true()
	)
	assert_str(_huds[a].revive.line_text).is_equal("YOU BLED OUT")
	# A player on the ground can use nothing, so the frame offers them nothing.
	assert_dict(_player_in(a, 1)["prompt"]).is_empty()
	_huds[a].scoreboard.set_shown(true)
	await get_tree().physics_frame
	assert_str(_huds[a].scoreboard.rows_text[0][0]).contains("(DEAD)")
	# Beside the body, holding for as long as it takes, changes nothing: dead is dead.
	_stand_beside(2, 1)
	_hold(b)
	await get_tree().create_timer(rules.tuning.health.revive_seconds + 1.0).timeout
	assert_int(_host.server.revive().in_reach(2)).is_equal(0)
	assert_bool(rules.players[1].downed).is_true()
	assert_bool(rules.is_dead(1)).is_true()
	assert_int(rules.revives_of(2)).is_equal(0)
	assert_str(String(_player_in(b, 2)["prompt"].get("kind", &""))).is_not_equal("revive")


func test_a_bot_pulls_a_downed_bot_up_with_the_commands_a_player_sends() -> void:
	var tuning := _quiet_tuning()
	await _server(tuning)
	var one := await _client(Night.Mode.AUTOPILOT)
	var two := await _client(Night.Mode.AUTOPILOT)
	var rules := _rules()
	_act(RulesAction.skip_break())
	_act(RulesAction.blow(1, 99999.0))
	assert_bool(rules.players[1].downed).is_true()
	# The other bot walks to the body, holds Use, and the server gets the first one up.
	(
		assert_bool(await _until(func() -> bool: return rules.players[1].downed == false, 80.0))
		. is_true()
	)
	assert_bool(rules.is_dead(1)).is_false()
	assert_int(rules.revives_of(2)).is_equal(1)
	assert_int(rules.revives_of(1)).is_equal(0)
	assert_bool(await _until(func() -> bool: return _count(one, &"player_revived") == 1)).is_true()
	assert_bool(await _until(func() -> bool: return _count(two, &"revive_started") >= 1)).is_true()
	# It took about the hold's time, with the walk before it, and the clock never ran out.
	assert_int(_count(one, &"player_died")).is_equal(0)
	(
		assert_bool(
			await _until(func() -> bool: return _huds[one].state.team[2]["revives"] == 1, 10.0)
		)
		. is_true()
	)
