# The map a room is on is the room's: a host that starts with it builds the lot from it, the WELCOME
# every client gets carries it (it rides the rules' snapshot, so the protocol layout and its
# version are unchanged), and a client that built the lot before it knew the map builds it again on
# the right one. A stub second map stands for the one that ships later, over a real WebSocket.
extends GdUnitTestSuite

var _host: NightHost
var _nights: Array[Night] = []


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()
	StubMaps.remove()


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


func _server(map_id: String) -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.match_settings = MatchSettings.new()
	_host.match_settings.map = map_id
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


func _client(built_on: String = "") -> Night:
	var night := Night.new()
	night.map_id = built_on
	_world().add_child(night)
	var joined := await night.start_remote(
		"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.MANUAL, 30.0
	)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


func test_a_host_builds_its_room_on_the_map_its_settings_name() -> void:
	StubMaps.install()
	await _server(StubMaps.ID)
	assert_bool(StubMaps.built_from_stub(_host.world)).is_true()
	assert_str(_host.server.rules.settings.map).is_equal(StubMaps.ID)


func test_a_host_on_the_usual_settings_builds_the_lot() -> void:
	StubMaps.install()
	await _server(MapRegistry.DEFAULT)
	assert_bool(StubMaps.built_from_stub(_host.world)).is_false()
	assert_str(_host.world.map_info.id).is_equal(MapRegistry.DEFAULT)


func test_the_welcome_names_the_map() -> void:
	StubMaps.install()
	await _server(StubMaps.ID)
	var client := await _client(StubMaps.ID)
	assert_str(client.match_settings.map).is_equal(StubMaps.ID)
	assert_bool(StubMaps.built_from_stub(client.world)).is_true()


func test_a_client_that_built_the_wrong_lot_builds_it_again_on_the_welcomed_map() -> void:
	StubMaps.install()
	await _server(StubMaps.ID)
	# Joined by an address: the client knew nothing of the map and built the default lot first.
	var client := await _client("")
	assert_str(client.match_settings.map).is_equal(StubMaps.ID)
	assert_str(client.world.map_info.id).is_equal(StubMaps.ID)
	assert_bool(StubMaps.built_from_stub(client.world)).is_true()
	# Only one lot is left in the client: the first was freed.
	await get_tree().process_frame
	assert_int(client.find_children("*", "NightWorld", false, false).size()).is_equal(1)


func test_a_client_on_the_lot_of_a_lot_night_builds_it_once() -> void:
	StubMaps.install()
	await _server(MapRegistry.DEFAULT)
	var client := await _client(MapRegistry.DEFAULT)
	var first := client.world
	assert_str(client.match_settings.map).is_equal(MapRegistry.DEFAULT)
	assert_bool(StubMaps.built_from_stub(client.world)).is_false()
	assert_object(client.world).is_same(first)


func test_a_running_room_keeps_its_map_when_the_host_configures_another() -> void:
	StubMaps.install()
	await _server(MapRegistry.DEFAULT)
	var wanted := MatchSettings.new()
	wanted.map = StubMaps.ID
	wanted.count_multiplier = 2.0
	assert_bool(_host.configure_match(wanted)).is_true()
	# The lot is built already: the other settings apply, the map stays the room's.
	assert_str(_host.server.rules.settings.map).is_equal(MapRegistry.DEFAULT)
	assert_float(_host.server.rules.settings.count_multiplier).is_equal(2.0)


func test_the_second_map_is_a_room_s_map_and_a_client_builds_it_from_the_welcome() -> void:
	await _server("small_indoor")
	assert_str(_host.world.map_info.id).is_equal("small_indoor")
	assert_str(_host.server.rules.settings.map).is_equal("small_indoor")
	# The room plays by the map's own rules overlay (its three links), and so does the client that
	# builds the map.
	assert_object(_host.server.rules.tuning.economy.item(&"door_side")).is_not_null()
	# Joined by an address: the client built the lot first, then builds the second map the WELCOME
	# names.
	var client := await _client("")
	assert_str(client.match_settings.map).is_equal("small_indoor")
	assert_str(client.world.map_info.id).is_equal("small_indoor")
	assert_object(client.rules_tuning.economy.item(&"door_side")).is_not_null()
	await get_tree().process_frame
	assert_int(client.find_children("*", "NightWorld", false, false).size()).is_equal(1)
	# A client that knew the map from its lobby builds it once.
	var known := await _client("small_indoor")
	assert_str(known.world.map_info.id).is_equal("small_indoor")
