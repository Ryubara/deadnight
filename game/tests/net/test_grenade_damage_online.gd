# A grenade that goes off in a player's hand, in a night of two players over a real WebSocket
# (#805): the server judges the blast (all the holder's health, part of a teammate's by distance),
# and both screens show it from the events: the holder is down and the feed says they blew
# themselves up, the teammate is hurt and their HUD names whose grenade it was. The curve is
# `tests/rules/ test_player_blast.gd`; the server's blast is `tests/grenades/test_blast.gd`.
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
				in [&"player_hurt", &"player_downed", &"player_blasted", &"grenade_exploded"]
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


func _feed(night: Night) -> Array[String]:
	return _huds[night].events_feed.history


## Two manual players in round one with nobody to fight; the teammate stands `apart` metres from the
## holder. The holder presses the throw button, and keeps it down until the grenade goes off in
## hand.
func _scene(apart: float) -> Array[Night]:
	await _server(_quiet_tuning())
	var a := await _client(Night.Mode.MANUAL)
	var b := await _client(Night.Mode.MANUAL)
	_act(RulesAction.skip_break())
	(
		assert_bool(await _until(func() -> bool: return _rules().phase == GameRules.Phase.ACTIVE))
		. is_true()
	)
	var holder := _host.server.body_of(1)
	_host.server.body_of(2).teleport(holder.global_position + Vector3(apart, 0.0, 0.0))
	return [a, b]


func test_a_grenade_in_the_hand_downs_the_holder_and_hurts_the_teammate_on_both_screens() -> void:
	var pair := await _scene(2.0)
	var a := pair[0]
	var b := pair[1]
	var command: NightCommand = _commands[a]
	command.motion.throw_over = true
	var downed := func() -> bool: return _rules().players[1].downed
	assert_bool(await _until(downed, 15.0)).is_true()
	command.motion.throw_over = false
	# The server judged it: all of the holder's health, part of the teammate's.
	var max_health: float = _rules().players[2].max_health
	assert_float(_rules().health_of(1)).is_equal(0.0)
	assert_float(_rules().health_of(2)).is_between(1.0, max_health - 10.0)
	# Both screens heard the blast and the blows, with whose grenade it was.
	for night: Night in [a, b]:
		(
			assert_bool(await _until(func() -> bool: return _count(night, &"player_downed") == 1))
			. is_true()
		)
		var down := _first_heard(night, &"player_downed")
		assert_str(String(down["harm"])).is_equal("grenade")
		assert_int(down["by_id"]).is_equal(1)
		assert_bool(_player_in(night, 1).get("downed", false)).is_true()
	assert_bool(await _until(func() -> bool: return _count(b, &"player_hurt") >= 1)).is_true()
	var mate_hurt: Dictionary = {}
	for event: Dictionary in _heard[b]:
		if event["type"] == &"player_hurt" and event["player_id"] == 2:
			mate_hurt = event
	assert_str(String(mate_hurt["harm"])).is_equal("grenade")
	assert_int(mate_hurt["by_id"]).is_equal(1)
	assert_float(mate_hurt["health"]).is_equal_approx(_rules().health_of(2), 0.01)
	# The teammate's HUD says whose grenade hurt them, and the feed says what happened to the holder.
	var name_of_holder: String = _huds[b].state.team[1]["name"].to_upper()
	assert_array(_feed(b)).contains(
		["%s'S GRENADE HIT YOU  -%d" % [name_of_holder, roundi(mate_hurt["damage"])]]
	)
	assert_array(_feed(b)).contains(["%s BLEW THEMSELVES UP" % name_of_holder])
	assert_array(_feed(a)).contains(["%s BLEW THEMSELVES UP" % name_of_holder])
	# Both screens show the same health for the teammate: the server's.
	assert_float(_huds[b].state.health).is_equal_approx(_rules().health_of(2), 0.6)


func test_a_teammate_far_from_the_blast_is_not_touched() -> void:
	var pair := await _scene(20.0)
	var a := pair[0]
	var command: NightCommand = _commands[a]
	command.motion.throw_over = true
	assert_bool(await _until(func() -> bool: return _rules().players[1].downed, 15.0)).is_true()
	command.motion.throw_over = false
	assert_float(_rules().health_of(2)).is_equal(_rules().players[2].max_health)
