# The perk limit setting (#913) over a real WebSocket: the host's choice rides the WELCOME, so the
# first player and one who joins later both read it; the server's rules apply it at the perk
# machines to a client that presses use (the limit holds on Default and lifts on Unlimited), and the
# late joiner's own machine prompt agrees. The rules' checks are `tests/rules/test_perk_limit.gd`.
extends GdUnitTestSuite

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


func _until(condition: Callable, seconds: float = 10.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


## A host with nobody to fight for ten minutes, the perk limit chosen before the night.
func _server(unlimited: bool) -> NightHost:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.rules_tuning = tuning
	if unlimited:
		_host.match_settings.perk_limit = MatchSettings.PERKS_UNLIMITED
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


## A client that sends the command held for it every tick, as a player's input would.
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
		func() -> void:
			var command: NightCommand = _commands.get(night)
			if command != null:
				night.link.send(command.to_dict())
	)
	return night


func _me(night: Night) -> Dictionary:
	return night.state.frame.get("players", {}).get(night.state.player_id, {})


func _spot(item: StringName) -> Vector3:
	for spot in _host.world.shop_spots():
		if spot["shop_id"] == item:
			return spot["position"]
	return Vector3.INF


## The player's server body is put at the machine of `item`; the answer is the prompt its client
## is shown.
func _stand_at(night: Night, item: StringName) -> Dictionary:
	_host.server.body_of(night.state.player_id).teleport(_spot(item) + Vector3(0.0, 0.1, 0.0))
	var shown := func() -> bool: return _me(night).get("prompt", {}).get("id", &"") == item
	assert_bool(await _until(shown)).is_true()
	return _me(night)["prompt"]


## A press of use from the client; the purchase is the server's.
func _press_use(night: Night) -> void:
	var command: NightCommand = _commands[night]
	command.use = true
	await get_tree().create_timer(0.3).timeout
	command.use = false
	await get_tree().create_timer(0.3).timeout
	# A perk bought is had when its drink ends (#912), and a purchase meanwhile is refused.
	var id := night.state.player_id
	var drunk := func() -> bool: return not _host.server.is_drinking(id)
	assert_bool(await _until(drunk)).is_true()
	await get_tree().create_timer(0.1).timeout


func _rich(player_id: int) -> void:
	_host._collect(_host.server.rules.apply(RulesAction.grant_points(player_id, 50000)))


func _perks_held(player_id: int) -> int:
	return _host.server.rules.players[player_id].tonics.size()


func test_on_default_a_client_at_the_fifth_machine_is_refused_by_the_server() -> void:
	await _server(false)
	var night := await _client()
	assert_int(night.match_settings.perk_limit).is_equal(MatchSettings.PERKS_DEFAULT)
	_host._collect(_host.server.rules.apply(RulesAction.skip_break()))
	_rich(night.state.player_id)
	var ids := PerkEffects.tonic_ids(_host.server.rules.tuning.economy)
	var limit := _host.server.rules.tuning.economy.max_tonics
	for i in limit:
		var prompt := await _stand_at(night, ids[i])
		assert_str(String(prompt["kind"])).is_equal("tonic")
		await _press_use(night)
	assert_int(_perks_held(night.state.player_id)).is_equal(limit)
	var full := await _stand_at(night, ids[limit])
	assert_str(String(full["kind"])).is_equal("tonic_full")
	await _press_use(night)
	assert_int(_perks_held(night.state.player_id)).is_equal(limit)


func test_on_unlimited_a_client_buys_a_fifth_and_a_sixth_and_a_late_joiner_reads_the_setting(
) -> void:
	await _server(true)
	var first := await _client()
	assert_int(first.match_settings.perk_limit).is_equal(MatchSettings.PERKS_UNLIMITED)
	_host._collect(_host.server.rules.apply(RulesAction.skip_break()))
	_rich(first.state.player_id)
	var ids := PerkEffects.tonic_ids(_host.server.rules.tuning.economy)
	for id in ids:
		var prompt := await _stand_at(first, id)
		assert_str(String(prompt["kind"])).override_failure_message(String(id)).is_equal("tonic")
		await _press_use(first)
	assert_int(_perks_held(first.state.player_id)).is_equal(ids.size())
	# A player who comes in after the night began reads the same setting from its WELCOME, and the
	# server's machines treat it the same way.
	var late := await _client()
	assert_int(late.match_settings.perk_limit).is_equal(MatchSettings.PERKS_UNLIMITED)
	_rich(late.state.player_id)
	for id in ids:
		var prompt := await _stand_at(late, id)
		assert_str(String(prompt["kind"])).override_failure_message(String(id)).is_equal("tonic")
		await _press_use(late)
	assert_int(_perks_held(late.state.player_id)).is_equal(ids.size())
	var bare := MatchSettings.from_snapshot(_host.server.rules.to_dict())
	assert_int(bare.perk_limit).is_equal(MatchSettings.PERKS_UNLIMITED)
