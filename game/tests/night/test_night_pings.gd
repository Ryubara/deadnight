# Pings in the night (bots plan, phase 0): a player marks a place, a door, an ammunition spot, an
# enemy or a downed teammate; the server checks the claim, puts the mark in the frame for everyone
# and tells the feed. A person sends the `ping` action, a bot the same one.
extends GdUnitTestSuite

const SETTLE := 30

var _events: Array[Dictionary] = []


func _start(spawn_delay := 600.0) -> Night:
	_events = []
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = spawn_delay
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	night.state.event_received.connect(func(event: Dictionary) -> void: _events.append(event))
	NightFixture.run(night, SETTLE)
	night.server.apply({"type": NightServer.JOIN, "player_id": 2, "local": false})
	night.server.rules.apply(RulesAction.skip_break())
	NightFixture.run(night, 2)
	return night


func _ask(kind: StringName, pos: Vector3, subject: Variant = 0) -> Dictionary:
	return {"type": NightServer.PING, "kind": kind, "pos": pos, "subject": subject}


func _ping(night: Night, action: Dictionary, from := 1) -> StringName:
	return night.server.ping(from, action)


func _placed() -> Array[Dictionary]:
	return _events.filter(func(e: Dictionary) -> bool: return e["type"] == &"ping_placed")


func _gap_ticks(night: Night) -> int:
	return roundi((night.server.tuning.ping_gap + 0.1) * 60.0)


func test_a_place_is_marked_for_everyone() -> void:
	var night := await _start()
	var spot := night.state.position() + Vector3(5.0, 0.0, 0.0)
	night.link.send(_ask(PingBoard.HERE, spot))
	NightFixture.run(night, 3)
	assert_int(_placed().size()).is_equal(1)
	assert_int(_placed()[0]["player_id"]).is_equal(1)
	var marks: Dictionary = night.state.frame["pings"]
	assert_vector(marks[1]["pos"]).is_equal_approx(spot, Vector3.ONE * 0.01)
	assert_str(marks[1]["kind"]).is_equal("here")
	night.queue_free()


func test_a_mark_is_taken_down_after_its_time() -> void:
	var night := await _start()
	assert_str(_ping(night, _ask(PingBoard.HERE, night.state.position()))).is_equal("")
	NightFixture.run(night, roundi((night.server.tuning.ping_seconds + 1.0) * 60.0))
	assert_dict(night.state.frame["pings"]).is_empty()
	var cleared := _events.filter(func(e: Dictionary) -> bool: return e["type"] == &"ping_cleared")
	assert_int(cleared.size()).is_equal(1)
	night.queue_free()


func test_a_flood_is_cut_to_one_mark_a_second() -> void:
	var night := await _start()
	var here := night.state.position()
	assert_str(_ping(night, _ask(PingBoard.HERE, here))).is_equal("")
	assert_str(_ping(night, _ask(PingBoard.HERE, here))).is_equal("too_soon")
	NightFixture.run(night, _gap_ticks(night))
	assert_str(_ping(night, _ask(PingBoard.HERE, here))).is_equal("")
	night.queue_free()


func test_a_place_far_away_or_not_a_place_is_refused() -> void:
	var night := await _start()
	var here := night.state.position()
	assert_str(_ping(night, _ask(PingBoard.HERE, here + Vector3(500, 0, 0)))).is_equal("too_far")
	assert_str(_ping(night, _ask(PingBoard.HERE, Vector3(NAN, 0, 0)))).is_equal("bad_position")
	assert_str(_ping(night, _ask(&"order", here))).is_equal("unknown_kind")
	var wrong := _ask(PingBoard.HERE, here)
	wrong["pos"] = "there"
	assert_str(_ping(night, wrong)).is_equal("bad_position")
	assert_str(_ping(night, _ask(PingBoard.HERE, here), 9)).is_equal("unknown_player")
	assert_dict(night.server.pings.marks()).is_empty()
	night.queue_free()


func test_a_door_is_marked_by_its_index_and_only_while_shut() -> void:
	var night := await _start()
	var ids := night.world.door_ids()
	assert_str(_ping(night, _ask(PingBoard.DOOR, Vector3.ZERO, 99))).is_equal("no_such_door")
	night.server.body_of(1).teleport(night.world.door_points(ids[0])[0] + Vector3(0, 0.1, -2.0))
	NightFixture.run(night, 2)
	assert_str(_ping(night, _ask(PingBoard.DOOR, Vector3.ZERO, 0))).is_equal("")
	assert_str(night.server.pings.marks()[1]["subject"]).is_equal(str(ids[0]))
	# Open, it is nothing to buy.
	night.server.rules.apply(RulesAction.grant_points(1, 5000))
	night.server.buy(1, ids[0])
	NightFixture.run(night, _gap_ticks(night))
	assert_str(_ping(night, _ask(PingBoard.DOOR, Vector3.ZERO, 0))).is_equal("no_such_door")
	night.queue_free()


func test_an_ammunition_spot_is_marked_where_it_is() -> void:
	var night := await _start()
	var spots := night.world.shop_spots().filter(
		func(s: Dictionary) -> bool: return s["kind"] == &"ammo"
	)
	assert_array(spots).is_not_empty()
	var spot: Vector3 = spots[0]["position"]
	night.server.body_of(1).teleport(spot + Vector3(2, 0, 0))
	NightFixture.run(night, 2)
	assert_str(_ping(night, _ask(PingBoard.AMMO, spot + Vector3(1, 0, 1)))).is_equal("")
	assert_vector(night.server.pings.marks()[1]["pos"]).is_equal_approx(spot, Vector3.ONE * 0.01)
	NightFixture.run(night, _gap_ticks(night))
	var far := _ask(PingBoard.AMMO, spot + Vector3(30, 0, 0))
	assert_str(_ping(night, far)).is_equal("no_such_spot")
	night.queue_free()


func test_an_enemy_must_be_a_live_zombie_and_the_mark_sits_on_it() -> void:
	var night := await _start(1.0)
	assert_str(_ping(night, _ask(PingBoard.ENEMY, Vector3.ZERO, 12345))).is_equal("no_such_zombie")
	var zombie_id := NightFixture.first_zombie(night)
	assert_int(zombie_id).is_greater(0)
	var zombie: ZombieBody = night.server.sim.zombies[zombie_id]
	night.server.body_of(1).teleport(zombie.position + Vector3(4, 0, 0))
	NightFixture.run(night, 2)
	assert_str(_ping(night, _ask(PingBoard.ENEMY, Vector3.ZERO, zombie_id))).is_equal("")
	assert_int(night.server.pings.marks()[1]["subject"]).is_equal(zombie_id)
	night.queue_free()


func test_a_downed_teammate_is_marked_and_a_standing_one_is_not() -> void:
	var night := await _start()
	night.server.body_of(2).teleport(night.state.position() + Vector3(3, 0, 0))
	NightFixture.run(night, 2)
	assert_str(_ping(night, _ask(PingBoard.DOWNED, Vector3.ZERO, 2))).is_equal("not_downed")
	night.server.rules.apply(RulesAction.blow(2, 500.0))
	assert_str(_ping(night, _ask(PingBoard.DOWNED, Vector3.ZERO, 2))).is_equal("")
	night.queue_free()


func test_the_ping_key_makes_one_edge_a_press() -> void:
	var night := await _start()
	var human := HumanController.new()
	Input.action_press(&"ping")
	assert_bool(human.ping_pressed(night.player())).is_true()
	assert_bool(human.ping_pressed(night.player())).is_false()
	Input.action_release(&"ping")
	assert_bool(human.ping_pressed(night.player())).is_false()
	night.queue_free()


func test_a_player_who_leaves_takes_their_mark_with_them() -> void:
	var night := await _start()
	assert_str(_ping(night, _ask(PingBoard.HERE, night.state.position()), 2)).is_equal("")
	night.server.apply({"type": NightServer.LEAVE, "player_id": 2})
	assert_dict(night.server.pings.marks()).is_empty()
	night.queue_free()
