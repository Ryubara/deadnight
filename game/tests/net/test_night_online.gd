# A night on a game server, over a real WebSocket on this machine, in one process: the server and
# its clients each live in their own SubViewport world (their own physics and navigation), the
# clients are `Night`s that joined with `start_remote`. Both players see each other move, shots and
# zombies agree, and a player who joins or leaves in the middle of the night is handled.
extends GdUnitTestSuite

const STEP := Night.STEP

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
	# A freed night only fades its beds out, and a bed still sounding at quit holds its stream:
	# the engine reports it as "resources still in use at exit". Stop them once the nights are gone.
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	# A voice stopped on the main thread stays in the audio server for a few mixer steps.
	await Audio.wait_for_mixer()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


## Waits for `condition` up to `seconds`, a physics frame at a time; true if it came.
func _until(condition: Callable, seconds: float = 10.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _server() -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


func _url() -> String:
	return "ws://127.0.0.1:%d" % _host.listener.port()


## A hand-driven client (MANUAL): it sends whatever `_commands` holds for it, every tick.
func _client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var joined := await night.start_remote(_url(), Night.Mode.MANUAL, 30.0)
	assert_bool(joined).is_true()
	_nights.append(night)
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void: night.link.send((_commands[night] as NightCommand).to_dict())
	)
	return night


func _position_of(night: Night, player_id: int) -> Vector3:
	return night.state.frame["players"][player_id]["pos"]


func test_two_clients_join_one_night_and_see_each_other_move() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_int(a.state.player_id).is_equal(1)
	assert_int(b.state.player_id).is_equal(2)
	assert_bool(await _until(func() -> bool: return b.state.frame["players"].has(1))).is_true()
	assert_bool(await _until(func() -> bool: return a.state.frame["players"].has(2))).is_true()
	# They were not put in the same spot.
	assert_float(_position_of(a, 1).distance_to(_position_of(a, 2))).is_greater(0.5)
	var start := _position_of(b, 1)
	(_commands[a] as NightCommand).motion.move = Vector2(0.0, -1.0)
	await _ticks(90)
	# B hears that A walked, and what it hears is what the server has.
	var seen_by_b := _position_of(b, 1)
	assert_float(seen_by_b.distance_to(start)).is_greater(2.0)
	assert_float(seen_by_b.distance_to(_host.server.body_of(1).global_position)).is_less(1.0)
	assert_float(_position_of(a, 1).distance_to(seen_by_b)).is_less(1.0)
	# And draws them there (an avatar for the other player, none for the one that has no body of
	# its own to hide: in MANUAL both are avatars).
	b.avatars.advance(0.5)
	assert_object(b.avatars.avatar(1)).is_not_null()
	assert_float(b.avatars.avatar(1).position.distance_to(seen_by_b)).is_less(1.5)
	assert_bool(b.avatars.ids().has(2)).is_true()


## The part meshes a model shows, sorted.
func _shown(model: Node) -> Array[String]:
	var out: Array[String] = []
	var meshes := SoldierLook.part_meshes(model)
	for mesh_name: String in meshes:
		if (meshes[mesh_name] as MeshInstance3D).visible:
			out.append(mesh_name)
	out.sort()
	return out


## The colour painted into the model's atlas for `channel`.
func _atlas_colour(model: Node, channel: StringName) -> Color:
	var mesh: MeshInstance3D = SoldierLook.part_meshes(model).values()[0]
	var material := mesh.material_override as StandardMaterial3D
	var image := material.albedo_texture.get_image()
	var cell: Array = SoldierLook.catalog()["atlas"]["cells"][String(channel)]
	var swatch: int = SoldierLook.catalog()["atlas"]["swatch_px"]
	return image.get_pixel(int(cell[0]) * swatch + swatch / 2, int(cell[1]) * swatch + swatch / 2)


## A human client that wears `look`, whatever the settings file says.
func _wearing(look: CharacterLook) -> Night:
	var night := Night.new()
	night.own_look = look
	_world().add_child(night)
	var joined := await night.start_remote(_url(), Night.Mode.HUMAN, 30.0)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


## Whether `night`'s table has `look` for player `id`.
func _sees_look(night: Night, id: int, look: CharacterLook) -> bool:
	return night.looks.looks.has(id) and (night.looks.looks[id] as CharacterLook).equals(look)


## Waits until `night` has heard that player `id` wears `look`.
func _until_sees(night: Night, id: int, look: CharacterLook) -> bool:
	for _i in 600:
		if _sees_look(night, id, look):
			return true
		await get_tree().physics_frame
	return false


func test_every_player_looks_the_same_on_every_screen() -> void:
	await _server()
	var look_a := CharacterLook.from_preset(2)
	var look_b := CharacterLook.from_preset(5)
	var a := await _wearing(look_a)
	var b := await _wearing(look_b)
	assert_bool(await _until_sees(a, 2, look_b)).is_true()
	assert_bool(await _until_sees(b, 1, look_a)).is_true()
	assert_bool(await _until_sees(a, 1, look_a)).is_true()
	assert_bool(await _until_sees(b, 2, look_b)).is_true()
	# The server's table is the truth; every client's table has the same two looks and seats.
	var server_looks: Dictionary = _host.server.looks.looks
	assert_bool((server_looks[1] as CharacterLook).equals(look_a)).is_true()
	assert_bool((server_looks[2] as CharacterLook).equals(look_b)).is_true()
	for night: Night in [a, b]:
		for id in [1, 2]:
			assert_bool((night.looks.looks[id] as CharacterLook).equals(server_looks[id])).is_true()
			assert_int(night.looks.seats[id]).is_equal(_host.server.looks.seats[id])
	await _ticks(10)
	var resolved := LookResolver.resolve(server_looks)
	# Each client's own body wears its saved look; the other player's avatar wears theirs.
	var models := {
		[1, 1]: a._body.get_node("Model"),
		[1, 2]: a.avatars.avatar(2).get_node("Model"),
		[2, 2]: b._body.get_node("Model"),
		[2, 1]: b.avatars.avatar(1).get_node("Model"),
	}
	for key: Array in models:
		var shown_id: int = key[1]
		var look: CharacterLook = resolved[shown_id]
		var model: Node = models[key]
		var expected: Array[String] = SoldierLook.visible_meshes(look.to_soldier_look())
		expected.sort()
		assert_array(_shown(model)).is_equal(expected)
		for slot: StringName in LookCatalog.colour_slots():
			var want := look.colour(slot)
			assert_bool(_atlas_colour(model, slot).is_equal_approx(want)).is_true()
	# So player 1 is the same on both screens, and different from player 2.
	assert_array(_shown(models[[1, 1]])).is_equal(_shown(models[[2, 1]]))
	var on_a := _atlas_colour(models[[1, 1]], &"primary")
	var on_b := _atlas_colour(models[[2, 1]], &"primary")
	assert_bool(on_a.is_equal_approx(on_b)).is_true()


## The character choice (#678) is part of the look: the other client draws her as her, both
## screens' voices know she has none yet, and his body beside her stays his.
func test_her_character_is_seen_by_the_other_player_and_has_her_voice() -> void:
	await _server()
	var hers := CharacterLook.from_preset(8)  # Carhop
	var his := CharacterLook.from_preset(5)
	assert_str(String(hers.body())).is_equal("female")
	var a := await _wearing(hers)
	var b := await _wearing(his)
	assert_bool(await _until_sees(b, 1, hers)).is_true()
	assert_bool(await _until_sees(a, 2, his)).is_true()
	assert_str(String((_host.server.looks.looks[1] as CharacterLook).body())).is_equal("female")
	await _ticks(10)
	# On the other screen her avatar shows her face, torso and legs and none of his.
	var avatar := b.avatars.avatar(1).get_node("Model")
	var shown := _shown(avatar)
	for mesh in [
		"head__plain__female", "torso__shirt__female", "legs__cuffed__female", "hair__bob"
	]:
		assert_array(shown).contains([mesh])
	for mesh in ["head__plain", "torso__shirt", "legs__cuffed"]:
		assert_array(shown).not_contains([mesh])
	# Her own screen draws her the same way.
	var resolved := LookResolver.resolve(_host.server.looks.looks)
	var expected: Array[String] = SoldierLook.visible_meshes(
		(resolved[1] as CharacterLook).to_soldier_look()
	)
	expected.sort()
	assert_array(_shown(a._body.get_node("Model"))).is_equal(expected)
	assert_array(shown).is_equal(expected)
	# The voice each screen picks: hers has no lines yet (#679), his is his.
	for night: Night in [a, b]:
		var voice := SoldierVoice.new()
		voice.looks = night.looks
		assert_str(String(voice.voice_of(1))).is_equal("female")
		assert_str(String(voice.voice_of(2))).is_equal("male")
		assert_bool(SoldierVoiceCatalog.has_voice(voice.voice_of(1))).is_false()
		voice.free()


## How tall the character is in the world: the highest bone of its skeleton at rest above the
## model's own origin (the feet), and its global scale.
func _stature(model: Node3D) -> Dictionary:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var top := -INF
	for bone in skeleton.get_bone_count():
		var at := skeleton.global_transform * skeleton.get_bone_global_rest(bone).origin
		top = maxf(top, at.y)
	return {
		"height": top - model.global_position.y,
		"scale": model.global_basis.get_scale(),
		"basis": model.global_basis,
	}


func test_a_player_is_as_tall_on_every_screen() -> void:
	await _server()
	var a := await _wearing(CharacterLook.from_preset(2))
	var b := await _wearing(CharacterLook.from_preset(5))
	(
		assert_bool(
			await _until(func() -> bool: return a.avatars.ids().has(2) and b.avatars.ids().has(1))
		)
		. is_true()
	)
	await _ticks(10)
	for id in [1, 2]:
		var own: Night = a if id == 1 else b
		var other: Night = b if id == 1 else a
		var on_own_screen := _stature(own._body.get_node("Model"))
		var on_other_screen := _stature(other.avatars.avatar(id).get_node("Model"))
		# The server draws nothing: its body has no skeleton to measure (`test_server_bodies.gd`).
		assert_bool(_host.server.body_of(id).has_model).is_false()
		assert_float(on_other_screen["height"]).is_equal_approx(on_own_screen["height"], 0.001)
		for stature: Dictionary in [on_other_screen]:
			var scale: Vector3 = stature["scale"]
			var want: Vector3 = on_own_screen["scale"]
			assert_float(scale.x).is_equal_approx(want.x, 0.001)
			assert_float(scale.y).is_equal_approx(want.y, 0.001)
			assert_float(scale.z).is_equal_approx(want.z, 0.001)
			# Turned the same way too: the model of a drawn avatar faces where its player faces.
			var turned: Basis = stature["basis"]
			assert_bool(turned.is_equal_approx(on_own_screen["basis"])).is_true()
	# And the two players are as tall as each other (one skeleton, one scale).
	var tall_1 := _stature(a._body.get_node("Model"))
	var tall_2 := _stature(b._body.get_node("Model"))
	assert_float(tall_1["height"]).is_equal_approx(tall_2["height"], 0.001)


func test_a_player_who_joins_late_sees_the_looks_already_there() -> void:
	await _server()
	var look_a := CharacterLook.from_preset(3)
	var look_late := CharacterLook.from_preset(6)
	var a := await _wearing(look_a)
	await _ticks(20)
	var late := await _wearing(look_late)
	assert_bool(await _until_sees(late, 1, look_a)).is_true()
	assert_bool(await _until_sees(late, 2, look_late)).is_true()
	assert_bool(await _until_sees(a, 2, look_late)).is_true()
	# A new connection says again how it looks: a different look in the same seat replaces the old.
	late.link.close()
	assert_bool(await _until(func() -> bool: return _host.player_count() == 1)).is_true()
	var look_again := CharacterLook.from_preset(7)
	var again := await _wearing(look_again)
	assert_int(again.state.player_id).is_equal(2)
	assert_bool(await _until_sees(a, 2, look_again)).is_true()


func test_shots_and_zombies_agree_on_both_clients() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	var rules := _host.server.rules
	rules.apply(RulesAction.skip_break())
	(
		assert_bool(await _until(func() -> bool: return _host.server.sim.zombies.size() > 0, 30.0))
		. is_true()
	)
	var zombie_id: int = _host.server.sim.zombies.keys()[0]
	# The same dead on the lot as the server has, on each client.
	var same := func(night: Night) -> bool:
		var ids: Array = []
		for entry in night.state.zombies:
			ids.append(entry["id"])
		var server_ids: Array = _host.server.sim.zombies.keys()
		ids.sort()
		server_ids.sort()
		return ids == server_ids
	assert_bool(await _until(func() -> bool: return same.call(a) and same.call(b), 10.0)).is_true()
	# A shoots one: hold it in front of A and pull the trigger.
	var heard_a: Array[Dictionary] = []
	var heard_b: Array[Dictionary] = []
	a.state.event_received.connect(func(e: Dictionary) -> void: heard_a.append(e))
	b.state.event_received.connect(func(e: Dictionary) -> void: heard_b.append(e))
	var body: ZombieBody = _host.server.sim.zombies[zombie_id]
	var spot := _host.server.body_of(1).global_position + Vector3(0.0, 0.0, -6.0)
	var shoot := NightFixture.shoot_at(a, spot)
	_commands[a] = shoot
	for _i in 12:
		body.position = spot
		body.velocity = Vector3.ZERO
		await _ticks(1)
	await _ticks(20)
	for heard in [heard_a, heard_b]:
		var shots: Array = heard.filter(
			func(e: Dictionary) -> bool: return e["type"] == &"shot_fired"
		)
		var hits: Array = heard.filter(
			func(e: Dictionary) -> bool: return e["type"] == &"damage_dealt"
		)
		assert_bool(shots.size() > 0).is_true()
		assert_bool(hits.size() > 0).is_true()
		assert_int(shots[0]["shooter_id"]).is_equal(1)
	# Both heard the same shots, and A was paid for them: the points in the frame are the server's.
	var count := func(heard: Array[Dictionary]) -> int:
		return heard.filter(func(e: Dictionary) -> bool: return e["type"] == &"shot_fired").size()
	assert_int(count.call(heard_a)).is_equal(count.call(heard_b))
	assert_int(a.state.points()).is_equal(rules.points_of(1))
	assert_int(b.state.frame["players"][1]["points"]).is_equal(rules.points_of(1))
	assert_int(rules.points_of(1)).is_greater(200)


func test_a_player_who_joins_in_the_middle_gets_the_night_as_it_is() -> void:
	await _server()
	var a := await _client()
	var rules := _host.server.rules
	rules.apply(RulesAction.skip_break())
	rules.apply(RulesAction.grant_points(1, 1000))
	_host.server.buy(1, &"door_concession")
	await _ticks(30)
	var late := await _client()
	# The door is open on the newcomer's lot, the round is the server's, and A is there to see.
	assert_bool(late.world.doors.closed_doors().has(&"door_concession")).is_false()
	assert_bool(late.world.doors.closed_doors().has(&"door_yard")).is_true()
	assert_int(late.state.round_number()).is_equal(rules.round_number)
	assert_bool(await _until(func() -> bool: return late.state.frame["players"].has(1))).is_true()
	assert_bool(await _until(func() -> bool: return a.state.frame["players"].has(2))).is_true()
	assert_int(late.state.points()).is_equal(rules.points_of(2))


func test_a_player_who_leaves_disappears_for_the_others_and_the_seat_is_reused() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return a.state.frame["players"].has(2))).is_true()
	assert_int(_host.player_count()).is_equal(2)
	b.link.close()
	assert_bool(await _until(func() -> bool: return _host.player_count() == 1)).is_true()
	assert_bool(await _until(func() -> bool: return not a.state.frame["players"].has(2))).is_true()
	assert_object(_host.server.body_of(2)).is_null()
	await _ticks(10)
	assert_bool(a.avatars.ids().has(2)).is_false()
	# The night goes on for A, and the next to come takes the free seat.
	var c := await _client()
	assert_int(c.state.player_id).is_equal(2)


## Reads the sockets of links nobody else drives.
func _pump(links: Array[WebSocketLink]) -> void:
	for link in links:
		link.pump()


func test_a_fifth_player_is_turned_away() -> void:
	await _server()
	var links: Array[WebSocketLink] = []
	for _i in 4:
		var link := WebSocketLink.new()
		link.connect_to(_url())
		links.append(link)
	var four := false
	for _i in 600:
		_pump(links)
		if _host.player_count() == 4:
			four = true
			break
		await get_tree().physics_frame
	assert_bool(four).is_true()
	var fifth := WebSocketLink.new()
	var why := {"reason": -1}
	fifth.refused.connect(func(reason: int) -> void: why["reason"] = reason)
	fifth.connect_to(_url())
	for _i in 600:
		_pump(links)
		fifth.pump()
		if why["reason"] != -1:
			break
		await get_tree().physics_frame
	assert_int(why["reason"]).is_equal(NetWire.Refusal.FULL)
	assert_int(_host.player_count()).is_equal(4)
	for link in links:
		link.close()


func test_a_server_nobody_is_on_says_so() -> void:
	var night := Night.new()
	_world().add_child(night)
	var why := {"text": ""}
	night.connect_failed.connect(func(text: String) -> void: why["text"] = text)
	# Port 1 has nothing listening.
	var joined := await night.start_remote("ws://127.0.0.1:1", Night.Mode.MANUAL, 5.0)
	assert_bool(joined).is_false()
	assert_str(why["text"]).is_not_empty()
	night.get_parent().queue_free()


func test_the_numbers_of_a_run_are_small() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	var rules := _host.server.rules
	rules.apply(RulesAction.skip_break())
	(_commands[a] as NightCommand).motion.move = Vector2(0.0, -1.0)
	await _until(func() -> bool: return _host.server.sim.zombies.size() >= 3, 60.0)
	var before: int = a.link.bytes_in
	var frames: int = a.link.frames_in
	await _ticks(180)
	var per_frame := float(a.link.bytes_in - before) / maxf(a.link.frames_in - frames, 1)
	print(
		(
			"online numbers: %.0f B per tick to a client, round trip %.0f ms, %d zombies"
			% [per_frame, a.link.rtt_ms, _host.server.sim.zombies.size()]
		)
	)
	# One tick to a client is a few hundred bytes: well under a kilobyte at this size.
	assert_float(per_frame).is_less(1500.0)
	assert_float(a.link.rtt_ms).is_less(500.0)


func test_a_client_that_warms_up_goes_on_reading_the_server_meanwhile() -> void:
	await _server()
	var night := Night.new()
	night.warm_up = true
	_world().add_child(night)
	var joined := await night.start_remote(_url(), Night.Mode.MANUAL, 30.0)
	assert_bool(joined).is_true()
	_nights.append(night)
	assert_bool(night.running).is_true()
	# The warm-up took many frames; what the server said meanwhile was read as it came, so the
	# client is not seconds behind (a frame arrives every few ticks, and the lag is the last).
	var behind: int = _host.server.tick_count - int(night.state.frame["tick"])
	assert_int(behind).is_less(NightHost.SEND_EVERY * 4)
