# What a client sees of another player's sprint, crouch and jump, over a real WebSocket on this
# machine (#549): the server and each client live in their own SubViewport world, the clients are
# `Night`s that joined with `start_remote`. Player A sprints, crouches and jumps; B (and a client
# that joins late) must show the sprint carry, the crouch and the jump and fall on A's drawn body,
# the frame names the stance in one small delta-coded field, and a client of the version before
# (that draws the others without it) is refused.
extends GdUnitTestSuite

const A := 1
const B := 2
## The protocol version of main when the stance was added: this build refuses it.
const VERSION_BEFORE := 10

var _host: NightHost
var _nights: Array[Night] = []
var _commands: Dictionary = {}
var _sockets: Array[WebSocketPeer] = []


func after_test() -> void:
	for ws in _sockets:
		ws.close()
	_sockets.clear()
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


func _server() -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


## A hand-driven client (MANUAL): it sends whatever `_commands` holds for it, every tick.
func _client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	assert_bool(await night.start_remote(url, Night.Mode.MANUAL, 30.0)).is_true()
	_nights.append(night)
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void: night.link.send((_commands[night] as NightCommand).to_dict())
	)
	return night


func _motion(night: Night) -> PlayerCommand:
	return (_commands[night] as NightCommand).motion


## The animation that draws player `id` on `night`'s screen, or null.
func _pose(night: Night, id: int) -> PlayerAnimation:
	var body := night.avatars.avatar(id)
	return body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body != null else null


## The state of the legs of player `id` on `night`'s screen (`&"locomotion"`, `&"crouch"`,
## `&"jump"`, `&"fall"`, `&"land"`), `&""` when there is no body.
func _legs(night: Night, id: int) -> StringName:
	var pose := _pose(night, id)
	if pose == null:
		return &""
	var playback := pose.get(&"parameters/body/playback") as AnimationNodeStateMachinePlayback
	return playback.get_current_node()


## The stance the frame B holds names for player A.
func _told(night: Night) -> Variant:
	return night.state.frame["players"][A].get("stance")


func test_b_shows_a_sprinting_with_the_weapon_carried() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return _pose(b, A) != null)).is_true()
	assert_float(_pose(b, A).sprint_carry()).is_equal(0.0)
	# Sprinting forward, and back again when the lot runs out, so the run lasts as long as needed.
	_motion(a).sprint = true
	var carried := false
	var frames := 0
	while not carried and frames < 720:
		# Forward for 50 ticks, then back, so the run lasts as long as needed.
		_motion(a).move = Vector2(0.0, -1.0 if (frames / 50) % 2 == 0 else 1.0)
		carried = _pose(b, A).sprint_carry() > 0.9
		frames += 1
		await get_tree().physics_frame
	(
		assert_bool(carried)
		. override_failure_message(
			(
				"B never showed A's sprint carry (frame stance %s, the server's body sprints %s)"
				% [_told(b), _host.server.body_of(A).state.sprinting]
			)
		)
		. is_true()
	)
	assert_bool(b.avatars.avatar(A).state.sprinting).is_true()
	# B's own seat carries nothing on A's screen: the stance is per player.
	assert_float(_pose(a, B).sprint_carry()).is_equal(0.0)
	# Let go: the carry goes with it.
	_motion(a).sprint = false
	_motion(a).move = Vector2.ZERO
	var rested := await _until(func() -> bool: return _pose(b, A).sprint_carry() < 0.05)
	assert_bool(rested).is_true()
	assert_bool(b.avatars.avatar(A).state.sprinting).is_false()


func test_b_shows_a_crouching_and_standing_up() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return _pose(b, A) != null)).is_true()
	assert_bool(await _until(func() -> bool: return _legs(b, A) == &"locomotion")).is_true()
	_motion(a).crouch = true
	var crouched := await _until(func() -> bool: return _legs(b, A) == &"crouch")
	(
		assert_bool(crouched)
		. override_failure_message(
			"B never showed A crouching (frame stance %s, legs %s)" % [_told(b), _legs(b, A)]
		)
		. is_true()
	)
	assert_bool(b.avatars.avatar(A).state.crouching).is_true()
	assert_str(String(_legs(a, B))).is_equal("locomotion")
	_motion(a).crouch = false
	assert_bool(await _until(func() -> bool: return _legs(b, A) == &"locomotion")).is_true()


func test_b_shows_a_jumping_falling_and_landing() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return _pose(b, A) != null)).is_true()
	var floor_y: float = b.avatars.avatar(A).global_position.y
	var seen := {"jump": false, "fall": false, "land": false, "up": 0.0}
	var watch := func() -> void:
		var body := b.avatars.avatar(A)
		if body == null:
			return
		var legs := _legs(b, A)
		seen["jump"] = seen["jump"] or legs == &"jump"
		seen["fall"] = seen["fall"] or legs == &"fall"
		seen["land"] = seen["land"] or legs == &"land"
		seen["up"] = maxf(seen["up"], body.global_position.y - floor_y)
	get_tree().physics_frame.connect(watch)
	_motion(a).jump = true
	await get_tree().physics_frame
	_motion(a).jump = false
	var landed := await _until(func() -> bool: return seen["land"], 10.0)
	get_tree().physics_frame.disconnect(watch)
	(
		assert_bool(landed)
		. override_failure_message("B showed A's jump as %s (frame stance %s)" % [seen, _told(b)])
		. is_true()
	)
	assert_bool(seen["jump"]).is_true()
	assert_float(seen["up"]).is_greater(0.3)
	assert_bool(await _until(func() -> bool: return b.avatars.avatar(A).state.on_floor)).is_true()


func test_a_client_that_joins_late_sees_the_stance_at_once() -> void:
	await _server()
	var a := await _client()
	_motion(a).crouch = true
	var crouching := await _until(func() -> bool: return _host.server.body_of(A).state.crouching)
	assert_bool(crouching).is_true()
	var late := await _client()
	var crouched := await _until(func() -> bool: return _legs(late, A) == &"crouch")
	assert_bool(crouched).is_true()


func test_the_stance_is_a_few_bits_sent_only_on_a_change() -> void:
	# Four bits in one number; a bit that is not a stance is dropped, a non-number is none.
	assert_int(PlayerStance.MASK).is_equal(15)
	assert_int(PlayerStance.clean(PlayerStance.SPRINT | 64)).is_equal(PlayerStance.SPRINT)
	assert_int(PlayerStance.clean("sprint")).is_equal(0)
	var state := PlayerMotionState.new()
	state.on_floor = true
	assert_int(PlayerStance.pack(state)).is_equal(0)
	state.sprinting = true
	state.crouching = true
	assert_int(PlayerStance.pack(state)).is_equal(PlayerStance.SPRINT | PlayerStance.CROUCH)
	state.on_floor = false
	state.velocity.y = 3.0
	assert_int(PlayerStance.pack(state)).is_equal(
		PlayerStance.SPRINT | PlayerStance.CROUCH | PlayerStance.AIR | PlayerStance.RISING
	)
	state.velocity.y = -3.0
	assert_int(PlayerStance.pack(state) & PlayerStance.RISING).is_equal(0)
	# A player who keeps their stance adds nothing to the frame, and a change under 64 bytes.
	var before := _frame_with(0)
	var quiet := NetWire.tick(1, [FrameDelta.diff(before, _frame_with(0))])
	var changed := NetWire.tick(1, [FrameDelta.diff(before, _frame_with(PlayerStance.SPRINT))])
	# About 40 bytes, nearly all of them the key and the entry of the player: the number is 4.
	assert_int(changed.size() - quiet.size()).is_between(1, 64)


func _frame_with(stance: int) -> Dictionary:
	return {"type": &"frame", "tick": 1, "players": {A: {"stance": stance}}}


func test_a_client_of_the_version_before_the_stance_is_refused() -> void:
	assert_bool(NetWire.accepts(NetWire.VERSION)).is_true()
	assert_int(NetWire.VERSION).is_greater(VERSION_BEFORE)
	assert_bool(NetWire.accepts(VERSION_BEFORE)).is_false()
	# And over a real socket: a hello of that version gets the refusal with the server's version.
	await _server()
	var ws := WebSocketPeer.new()
	_sockets.append(ws)
	ws.connect_to_url("ws://127.0.0.1:%d" % _host.listener.port())
	var open := await _until(
		func() -> bool:
			ws.poll()
			return ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	)
	assert_bool(open).is_true()
	ws.send(
		PackedByteArray([NetWire.Type.HELLO, VERSION_BEFORE, 0]), WebSocketPeer.WRITE_MODE_BINARY
	)
	var found := {"refusal": PackedByteArray()}
	await _until(
		func() -> bool:
			ws.poll()
			while ws.get_available_packet_count() > 0:
				var packet := ws.get_packet()
				if packet[0] == NetWire.Type.REFUSED:
					found["refusal"] = packet
			return not (found["refusal"] as PackedByteArray).is_empty()
	)
	var refusal: PackedByteArray = found["refusal"]
	assert_int(refusal.size()).is_equal(3)
	assert_int(refusal[1]).is_equal(NetWire.Refusal.VERSION)
	assert_int(refusal[2]).is_equal(NetWire.VERSION)
	assert_int(_host.player_count()).is_equal(0)
