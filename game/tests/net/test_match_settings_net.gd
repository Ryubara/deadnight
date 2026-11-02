# The match settings are the server's: they ride the rules' snapshot, so the WELCOME every client
# gets (the first, a late joiner, one that came back) carries them, and the host's hook
# (`NightHost.configure_match`) sets them before the night starts and not after. Over a real
# WebSocket.
extends GdUnitTestSuite

const SETTINGS_FIELDS := ["count_multiplier", "max_alive", "break_seconds", "round_time_limit"]

var _host: NightHost
var _nights: Array[Night] = []
var _raw: Array[WebSocketPeer] = []


func after_test() -> void:
	for ws in _raw:
		ws.close()
	_raw.clear()
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()


func _settings() -> MatchSettings:
	var s := MatchSettings.new()
	s.count_multiplier = 3.0
	s.max_alive = 9
	s.break_seconds = 11.0
	s.round_time_limit = 90.0
	return s


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


func _client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var joined := await night.start_remote(
		"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.MANUAL, 30.0
	)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


## A bare socket that has said hello; the WELCOME it gets.
func _hello() -> Dictionary:
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % _host.listener.port())
	_raw.append(ws)
	var got := {"welcome": {}, "sent": false}
	await _until(
		func() -> bool:
			ws.poll()
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not got["sent"]:
				got["sent"] = true
				ws.send(NetWire.hello(PackedByteArray()), WebSocketPeer.WRITE_MODE_BINARY)
			while ws.get_available_packet_count() > 0:
				var packet := ws.get_packet()
				if packet[0] == NetWire.Type.WELCOME:
					got["welcome"] = NetWire.read_welcome(packet)
			return not (got["welcome"] as Dictionary).is_empty()
	)
	return got["welcome"]


func _assert_same(got: MatchSettings, wanted: MatchSettings) -> void:
	for field in SETTINGS_FIELDS:
		assert_float(float(got.to_dict()[field])).override_failure_message(field).is_equal(
			float(wanted.to_dict()[field])
		)


func test_a_welcome_built_by_hand_carries_the_settings() -> void:
	var rules := GameRules.new(null, 3, _settings())
	var bytes := NetWire.welcome(2, 30, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]), rules.to_dict())
	var welcome := NetWire.read_welcome(bytes)
	_assert_same(MatchSettings.from_snapshot(welcome["snapshot"]), _settings())


func test_a_snapshot_without_settings_reads_as_the_defaults() -> void:
	assert_bool(MatchSettings.from_snapshot({}).is_default()).is_true()
	assert_bool(MatchSettings.from_snapshot({"match_settings": 5}).is_default()).is_true()
	(
		assert_bool(MatchSettings.from_snapshot({"match_settings": {"max_alive": 4}}).is_default())
		. is_true()
	)


func test_a_default_server_welcomes_with_the_default_rules() -> void:
	await _server()
	var welcome := await _hello()
	assert_bool(MatchSettings.from_snapshot(welcome["snapshot"]).is_default()).is_true()
	var night := await _client()
	assert_bool(night.match_settings.is_default()).is_true()


func test_a_host_that_configures_before_the_night_starts_sets_it_for_everyone() -> void:
	await _server()
	assert_bool(_host.configure_match(_settings())).is_true()
	var first := await _client()
	_assert_same(first.match_settings, _settings())
	_assert_same(_host.server.rules.settings, _settings())
	# A player who comes in after the night began reads the same rules from its WELCOME.
	await _until(func() -> bool: return _host.server.rules.phase != GameRules.Phase.IDLE)
	var late := await _client()
	_assert_same(late.match_settings, _settings())
	var bare := await _hello()
	_assert_same(MatchSettings.from_snapshot(bare["snapshot"]), _settings())


func test_a_host_cannot_change_a_night_that_began() -> void:
	await _server()
	var first := await _client()
	assert_bool(first.match_settings.is_default()).is_true()
	assert_bool(_host.configure_match(_settings())).is_false()
	# The running night keeps its rules; the settings wait for the next one.
	assert_bool(_host.server.rules.settings.is_default()).is_true()
	_assert_same(_host.match_settings, _settings())
	var late := await _client()
	assert_bool(late.match_settings.is_default()).is_true()


func test_a_host_started_with_settings_builds_its_night_under_them() -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.match_settings = _settings()
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	_assert_same(_host.server.rules.settings, _settings())
	var night := await _client()
	_assert_same(night.match_settings, _settings())
	# The rounds it plays are the scaled ones.
	_host.server.rules.apply(RulesAction.skip_break())
	var tuned := _host.server.rules.tuning.rounds.zombies_for_round(1, 1)
	assert_int(_host.server.rules._round_total).is_equal(maxi(1, roundi(tuned * 3.0)))
