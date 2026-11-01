extends GdUnitTestSuite
## Two (and four) clients through a loopback hub: each sees the other's look, the server never
## trusts what it is sent, seats are fixed, and two identical looks are told apart the same way on
## every client.


func test_messages_round_trip() -> void:
	var look := CharacterLook.from_preset(6)
	var up := LookWire.decode(LookWire.look(look))
	assert_int(up["type"]).is_equal(LookWire.Type.LOOK)
	assert_bool((up["look"] as CharacterLook).equals(look)).is_true()
	var down := LookWire.decode(LookWire.player_look(7, 2, look))
	assert_int(down["player_id"]).is_equal(7)
	assert_int(down["seat"]).is_equal(2)
	assert_bool((down["look"] as CharacterLook).equals(look)).is_true()


func test_the_messages_are_small() -> void:
	var look := CharacterLook.new()
	assert_int(LookWire.look(look).size()).is_less_equal(16)
	assert_int(LookWire.player_look(1, 0, look).size()).is_less_equal(18)


func test_malformed_packets_decode_to_nothing() -> void:
	assert_dict(LookWire.decode(PackedByteArray())).is_empty()
	assert_dict(LookWire.decode(PackedByteArray([LookWire.Type.LOOK, 1, 2]))).is_empty()
	assert_dict(LookWire.decode(PackedByteArray([LookWire.Type.PLAYER_LOOK]))).is_empty()
	assert_dict(LookWire.decode(PackedByteArray([200, 1, 2, 3]))).is_empty()


func test_each_of_two_clients_sees_the_others_look() -> void:
	var hub := LoopbackHub.new()
	var a := hub.connect_client()
	var b := hub.connect_client()
	var look_a := CharacterLook.from_preset(2)
	var look_b := CharacterLook.from_preset(5)
	hub.send_look(a, look_a)
	hub.send_look(b, look_b)
	hub.pump()
	for id in [a, b]:
		var seen := (hub.clients[id] as LookRegistry).resolved()
		assert_int(seen.size()).is_equal(2)
		assert_bool((seen[a] as CharacterLook).equals(look_a)).is_true()
		assert_bool((seen[b] as CharacterLook).equals(look_b)).is_true()


func test_a_player_who_joins_late_learns_who_is_already_there() -> void:
	var hub := LoopbackHub.new()
	var a := hub.connect_client()
	hub.send_look(a, CharacterLook.from_preset(3))
	hub.pump()
	var b := hub.connect_client()
	hub.send_look(b, CharacterLook.from_preset(4))
	hub.pump()
	var seen := (hub.clients[b] as LookRegistry).resolved()
	assert_bool((seen[a] as CharacterLook).equals(CharacterLook.from_preset(3))).is_true()
	var earlier := (hub.clients[a] as LookRegistry).resolved()
	assert_bool((earlier[b] as CharacterLook).equals(CharacterLook.from_preset(4))).is_true()


func test_the_other_players_model_is_built_from_what_arrived() -> void:
	var hub := LoopbackHub.new()
	var a := hub.connect_client()
	var b := hub.connect_client()
	hub.send_look(b, CharacterLook.from_preset(1))
	hub.pump()
	var model := (hub.clients[a] as LookRegistry).assemble(b)
	add_child(model)
	auto_free(model)
	var band := model.find_child(CharacterAssembler.ARMBAND_NAME, true, false) as MeshInstance3D
	var material := (band.mesh as TorusMesh).material as StandardMaterial3D
	# The second to join sits in the second seat.
	assert_that(material.albedo_color).is_equal(LookCatalog.ARMBAND_COLOURS[1])


func test_seats_are_the_lowest_free_and_kept_while_others_leave() -> void:
	var hub := LoopbackHub.new()
	var a := hub.connect_client()
	var b := hub.connect_client()
	var c := hub.connect_client()
	assert_int(hub.server.seats[a]).is_equal(0)
	assert_int(hub.server.seats[b]).is_equal(1)
	assert_int(hub.server.seats[c]).is_equal(2)
	hub.disconnect_client(a)
	assert_int(hub.server.seats[b]).is_equal(1)
	var d := hub.connect_client()
	assert_int(hub.server.seats[d]).is_equal(0)
	hub.connect_client()
	assert_int(hub.server.join(99)).is_equal(-1)


func test_the_server_replaces_a_look_that_is_broken_or_wears_something_locked() -> void:
	var hub := LoopbackHub.new()
	var a := hub.connect_client()
	var b := hub.connect_client()
	# A look of another version arrives as the default look.
	var bytes := CharacterLook.from_preset(3).to_bytes()
	bytes[0] = 99
	hub.send_raw(a, PackedByteArray([LookWire.Type.LOOK]) + bytes)
	# Gold is locked for a level 1 account.
	var greedy := CharacterLook.from_preset(3)
	greedy.colours[&"primary"] = 11
	hub.send_look(b, greedy)
	hub.pump()
	var seen := (hub.clients[a] as LookRegistry).resolved()
	assert_bool((seen[a] as CharacterLook).equals(CharacterLook.new())).is_true()
	assert_int((seen[b] as CharacterLook).colours[&"primary"]).is_equal(0)
	assert_int((seen[b] as CharacterLook).colours[&"skin"]).is_equal(greedy.colours[&"skin"])


func test_junk_from_a_client_is_ignored() -> void:
	var hub := LoopbackHub.new()
	var a := hub.connect_client()
	var b := hub.connect_client()
	hub.send_look(a, CharacterLook.from_preset(2))
	hub.pump()
	var before := hub.downlink.size()
	for junk in [
		PackedByteArray(),
		PackedByteArray([8]),
		PackedByteArray([8, 1, 2, 3]),
		PackedByteArray([77])
	]:
		hub.send_raw(b, junk)
	hub.pump()
	assert_int(hub.downlink.size()).is_equal(before)
	# A packet from a player who never joined does nothing either.
	assert_bool(hub.server.receive(42, LookWire.look(CharacterLook.new()))).is_false()


func test_identical_looks_are_told_apart_the_same_way_on_every_client() -> void:
	var hub := LoopbackHub.new()
	var ids: Array[int] = []
	for i in 4:
		ids.append(hub.connect_client())
	for id in ids:
		hub.send_look(id, CharacterLook.from_preset(2))
	hub.pump()
	var first := (hub.clients[ids[0]] as LookRegistry).resolved()
	var keys := {}
	for id in ids:
		keys[(first[id] as CharacterLook).key()] = true
	assert_int(keys.size()).is_equal(4)
	for client_id in ids:
		var seen := (hub.clients[client_id] as LookRegistry).resolved()
		for id in ids:
			assert_str((seen[id] as CharacterLook).key()).is_equal(
				(first[id] as CharacterLook).key()
			)


func test_a_leaving_player_disappears_from_the_others() -> void:
	var hub := LoopbackHub.new()
	var a := hub.connect_client()
	var b := hub.connect_client()
	hub.pump()
	hub.disconnect_client(b)
	assert_bool((hub.clients[a] as LookRegistry).looks.has(b)).is_false()


func test_a_join_costs_a_handful_of_bytes() -> void:
	var hub := LoopbackHub.new()
	var a := hub.connect_client()
	hub.connect_client()
	hub.send_look(a, CharacterLook.from_preset(2))
	hub.pump()
	var up := 0
	for packet in hub.uplink:
		up += packet.size()
	assert_int(up).is_less_equal(16)
