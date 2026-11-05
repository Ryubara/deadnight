# The calling card and emblem beside a seat (#1070), over a real WebSocket on this machine: what
# the ticket says a seat chose is held by the game server to what the seat owns (the tier pieces by
# the level its XP gives, the challenge pieces by the finished challenges), reaches every client in
# the `account_seated` event and, for a late joiner, in the WELCOME's `plates`, and lands in each
# client's HUD; no client message can give a seat a card. The ticket's claims are made as the
# backend makes them (`TicketMaker`).
extends GdUnitTestSuite

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"

var _server: GameServer
var _nights: Array[Night] = []


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	if is_instance_valid(_server):
		_server.get_parent().queue_free()
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


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _start() -> GameServer:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 4
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())
	return _server


func _url() -> String:
	return "ws://127.0.0.1:%d" % _server.listener.port()


## The progression the backend signs for an account: the XP of `level`, what it chose and finished.
func _account(level: int, card := "", emblem := "", done: Array = []) -> Dictionary:
	var account := {"xp": LevelCurve.xp_for(level)}
	if card != "":
		account["card"] = card
	if emblem != "":
		account["emblem"] = emblem
	if not done.is_empty():
		account["done"] = done
	return account


func _client(match_id: String, user: String, account := {}, hud: Hud = null) -> Night:
	var night := Night.new()
	night.hud = hud
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = TicketMaker.make(SECRET, SERVER_ID, match_id, user, user, 60, {}, null, account)
	assert_bool(await night.start_remote(_url(), Night.Mode.MANUAL, 60.0, link)).is_true()
	_nights.append(night)
	return night


func _hud() -> Hud:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	return hud


func _plate(hud: Hud, player_id: int) -> Dictionary:
	return hud.state.plate_of(hud.state.team[player_id])


func test_every_client_shows_every_seats_card_and_emblem_and_a_late_joiner_too() -> void:
	await _start()
	var first := _hud()
	var ann := await _client("plates", "ann", _account(12, "cartoon", "admit_one", []), first)
	var bo_hud := _hud()
	var bo := await _client(
		"plates", "bo", _account(3, "dead_eye", "walk_in", ["f_dead_eye", "f_walk_in"]), bo_hud
	)
	await _ticks(10)
	# Ann owns the second tier's card (level 10) and the starting emblem (level 2); Bo owns both
	# through challenges he finished.
	for hud in [first, bo_hud]:
		var plate := _plate(hud, ann.state.player_id)
		assert_str(plate["card"]).is_equal("cartoon")
		assert_str(plate["emblem"]).is_equal("admit_one")
		plate = _plate(hud, bo.state.player_id)
		assert_str(plate["card"]).is_equal("dead_eye")
		assert_str(plate["emblem"]).is_equal("walk_in")
	# Someone who sits down later reads the others from the WELCOME.
	var late_hud := _hud()
	await _client("plates", "cy", _account(7, "", "", []), late_hud)
	await _ticks(10)
	assert_str(_plate(late_hud, ann.state.player_id)["card"]).is_equal("cartoon")
	assert_str(_plate(late_hud, bo.state.player_id)["emblem"]).is_equal("walk_in")
	var room := _server.room_of_match("plates")
	assert_dict(room._welcome_snapshot()["plates"]).has_size(2)


func test_a_card_the_seat_does_not_own_is_not_worn() -> void:
	await _start()
	var hud := _hud()
	# Level 3 owns no tier card; the challenge for Dead Eye is not in the list; the emblem of the
	# ladder's fourth tier is far above this level; and the named ones that nobody has are nothing.
	var ann := await _client(
		"owned", "ann", _account(3, "doors_open", "second_feature", ["f_ironwork"]), hud
	)
	var bo := await _client("owned", "bo", _account(3, "dead_eye", "nonsense", []))
	await _ticks(10)
	for night in [ann, bo]:
		var plate := _plate(hud, (night as Night).state.player_id)
		assert_str(plate["card"]).is_equal("")
		assert_str(plate["emblem"]).is_equal("")
	assert_dict(_server.room_of_match("owned")._welcome_snapshot()["plates"]).is_empty()


func test_a_seat_with_no_account_and_a_bot_wear_nothing() -> void:
	await _start()
	var hud := _hud()
	var ann := await _client("none", "ann", _account(12, "cartoon", "admit_one"), hud)
	await _ticks(10)
	# A ticket with no claims is an account at level 1 with nothing chosen.
	var bo := await _client("none", "bo", {})
	await _ticks(10)
	assert_str(_plate(hud, bo.state.player_id)["card"]).is_equal("")
	hud.state.team[ann.state.player_id]["bot"] = true
	assert_str(_plate(hud, ann.state.player_id)["card"]).is_equal("")


func test_a_seat_that_leaves_takes_its_card_with_it() -> void:
	await _start()
	var hud := _hud()
	var ann := await _client("leave", "ann", _account(12, "cartoon", ""), hud)
	var bo := await _client("leave", "bo", _account(12, "cartoon", ""))
	var room := _server.room_of_match("leave")
	await _ticks(10)
	assert_dict(room._welcome_snapshot()["plates"]).has_size(2)
	var gone: int = bo.state.player_id
	bo.link.close()
	assert_bool(await _until(func() -> bool: return room.player_count() == 1)).is_true()
	var left := func() -> bool:
		return not hud.state.team.has(gone) or _plate(hud, gone)["card"] == &""
	assert_bool(await _until(left)).is_true()
	assert_str(_plate(hud, ann.state.player_id)["card"]).is_equal("cartoon")


func test_a_client_cannot_give_itself_a_card_whatever_it_sends() -> void:
	await _start()
	var ann := await _client("forge", "ann", _account(3))
	var bo := await _client("forge", "bo", _account(3))
	var room := _server.room_of_match("forge")
	await _ticks(10)
	# The event a server sends, sent up; a WELCOME that says it; a hello with the claim in the wrong
	# place: none of them is read as a seat's card.
	var forged: Array[PackedByteArray] = [
		(
			NetWire
			. tick(
				1,
				[
					{
						"type": &"account_seated",
						"player_id": 1,
						"level": 55,
						"card": &"last_reel",
						"emblem": &"last_reel",
					}
				]
			)
		),
		NetWire.welcome(
			1,
			60,
			PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]),
			{"plates": {1: {"card": &"last_reel", "emblem": &"last_reel"}}}
		),
		PackedByteArray([NetWire.Type.COMMAND, 55, 55, 55, 55]),
	]
	var link := ann.link as WebSocketLink
	for packet in forged:
		link._put(packet)
	await _ticks(40)
	assert_dict(room.plates.to_dict()).is_empty()
	assert_str(room.plates.of_seat(1)["card"]).is_equal("")
	assert_object(bo).is_not_null()
