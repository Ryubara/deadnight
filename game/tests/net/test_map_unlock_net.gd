# The host's level decides which map a hosted night is on (#1067), over a real WebSocket to a real
# `GameServer`: the server reads the host's level from the ticket the backend signed (`hostLevel`),
# never from the rules a client sends, so a level-3 host who asks for the back rooms (level 10) has
# the drive-in lot, a level-12 host has the back rooms, and a guest of either level plays the host's
# map: a guest below a map's level still plays a hosted night there as a visitor, and a guest above
# it cannot lift a host below it. Every ticket of a match carries the host's level, so the order the
# players arrive in decides nothing.
extends GdUnitTestSuite

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"
const BACK_ROOMS := "small_indoor"

var _server: GameServer
var _nights: Array[Night] = []


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	if is_instance_valid(_server):
		_server.get_parent().queue_free()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _until(condition: Callable, seconds: float = 30.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _start() -> void:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 4
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())


## A player entering `match_id` with a ticket that says the host is `host_level` and carries the
## host's rules (the backend signs the same rules and the same host level into every ticket).
func _enter(match_id: String, user: String, host_level: Variant, map_id: String) -> Night:
	var rules := {"count_multiplier": 1.0, "max_alive": 0, "break_seconds": 0.0, "map": map_id}
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = TicketMaker.make(SECRET, SERVER_ID, match_id, user, user, 60, rules, host_level)
	var url := "ws://127.0.0.1:%d" % _server.listener.port()
	var joined := await night.start_remote(url, Night.Mode.MANUAL, 60.0, link)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


func test_a_level_3_host_asking_for_the_back_rooms_gets_the_lot_for_everyone() -> void:
	await _start()
	var host := await _enter("low-host", "host", 3, BACK_ROOMS)
	var room := _server.room_of_match("low-host")
	assert_str(room.world.map_info.id).is_equal("drive_in")
	assert_str(room.server.rules.settings.map).is_equal("drive_in")
	assert_str(host.match_settings.map).is_equal("drive_in")
	# A level-12 guest of that host cannot lift it: the ticket says whose level decides.
	var guest := await _enter("low-host", "guest", 3, BACK_ROOMS)
	assert_str(guest.match_settings.map).is_equal("drive_in")
	assert_str(guest.world.map_info.id).is_equal("drive_in")


func test_a_level_12_host_has_the_back_rooms_and_a_level_3_guest_plays_there() -> void:
	await _start()
	var host := await _enter("high-host", "host", 12, BACK_ROOMS)
	var room := _server.room_of_match("high-host")
	assert_str(room.world.map_info.id).is_equal(BACK_ROOMS)
	assert_str(host.world.map_info.id).is_equal(BACK_ROOMS)
	# The guest's own level is nowhere in the ticket: it is a visitor on the host's map.
	var guest := await _enter("high-host", "guest", 12, BACK_ROOMS)
	assert_str(guest.match_settings.map).is_equal(BACK_ROOMS)
	assert_str(guest.world.map_info.id).is_equal(BACK_ROOMS)


func test_the_order_the_players_arrive_in_decides_nothing() -> void:
	await _start()
	# The guest's ticket reaches the server first: it opens the room, with the host's level.
	var guest := await _enter("order", "guest", 4, BACK_ROOMS)
	assert_str(guest.world.map_info.id).is_equal("drive_in")
	var host := await _enter("order", "host", 4, BACK_ROOMS)
	assert_str(host.world.map_info.id).is_equal("drive_in")


func test_a_ticket_that_says_no_level_leaves_the_hosts_choice() -> void:
	await _start()
	var night := await _enter("no-level", "host", null, BACK_ROOMS)
	assert_str(night.world.map_info.id).is_equal(BACK_ROOMS)
