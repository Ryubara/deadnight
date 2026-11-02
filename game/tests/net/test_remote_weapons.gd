# What a client sees of the other players' weapons, over a real WebSocket on this machine: the
# server and each client live in their own SubViewport world, the clients are `Night`s that joined
# with `start_remote`. Player A equips, swaps, aims, fires, reloads, swings and throws; B (and a
# client that joins late) must show each of them on A's drawn body: the weapon model in the hand,
# the aim pose, the flash on the muzzle, the reload tilt, the swing and the grenade clips (#518).
extends GdUnitTestSuite

const A := 1
const B := 2

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


## Holds `edit` on the client's command for one tick (a press: an edge the server uses once).
func _tap(night: Night, edit: Callable) -> void:
	var command := _commands[night] as NightCommand
	edit.call(command, true)
	await night.ticked
	edit.call(command, false)
	await _ticks(2)


func _swap(command: NightCommand, down: bool) -> void:
	command.swap = down


func _reload(command: NightCommand, down: bool) -> void:
	command.reload = down


## The animation that draws player `id` on `night`'s screen, or null (no body, no clips).
func _pose(night: Night, id: int) -> PlayerAnimation:
	var body := night.avatars.avatar(id)
	return body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body != null else null


## Whether `night` shows player `id` holding `weapon`: its model in the hand (the hold file's own
## scene), visible, in the class's clips.
func _shows(night: Night, id: int, weapon: StringName) -> bool:
	var pose := _pose(night, id)
	var hold := WeaponHoldMap.hold_for(weapon)
	if pose == null or hold == null or pose.weapon() == null or pose.weapon_hold() == null:
		return false
	return (
		pose.weapon_hold().scene == hold.scene
		and pose.weapon().visible
		and pose.weapon_class == WeaponHoldMap.class_of(weapon)
	)


## What player `id`'s body on `night`'s screen is doing: the clip of its upper body, `&""` when none
## (or when there is no body).
func _clip(night: Night, id: int) -> StringName:
	var pose := _pose(night, id)
	return pose.action_clip if pose != null else &""


func _aim_weight(night: Night, id: int) -> float:
	var pose := _pose(night, id)
	return pose.aim_weight() if pose != null else -1.0


func _barrel_pitch(night: Night, id: int) -> float:
	var pose := _pose(night, id)
	return pose.hands().aim_pitch if pose != null else -99.0


func _reload_dip(night: Night, id: int) -> float:
	var pose := _pose(night, id)
	return pose.reload_dip() if pose != null else -1.0


func _held_by_server(id: int) -> StringName:
	return _host.server.combat.weapon_of(id).def.id


## Swaps A's weapon until the server says it holds `weapon` (the carry order is the server's).
func _hold(a: Night, weapon: StringName) -> void:
	for _i in 6:
		if _held_by_server(A) == weapon:
			return
		await _tap(a, _swap)


## Records the names of the events B hears, for the failure messages.
func _listen(night: Night) -> Array[StringName]:
	var heard: Array[StringName] = []
	night.state.event_received.connect(
		func(event: Dictionary) -> void:
			heard.append(
				StringName("%s %s" % [event["type"], event.get("reason", "")]).strip_edges()
			)
	)
	return heard


func test_b_shows_the_weapon_a_holds_and_every_swap() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	var heard := _listen(b)
	assert_bool(await _until(func() -> bool: return b.avatars.ids().has(A))).is_true()
	# What B is told about A: the frame names the weapon (and so does an event).
	var told: StringName = b.state.frame["players"][A]["weapon"]
	assert_str(String(told)).is_equal(String(_held_by_server(A)))
	# What B's drawing of A shows: the same weapon in the hand.
	var shown := await _until(func() -> bool: return _shows(b, A, told))
	(
		assert_bool(shown)
		. override_failure_message(
			(
				"B was told A holds %s (heard %s), but B's body of A has no %s in the hand (animation: %s)"
				% [told, heard.slice(-6), told, _pose(b, A)]
			)
		)
		. is_true()
	)
	# Swap away and back: every swap shows.
	_host.server._combat(CombatAction.give_weapon(A, &"shotgun"))
	for weapon: StringName in [&"crowbar", &"pistol", &"shotgun"]:
		await _hold(a, weapon)
		(
			assert_bool(await _until(func() -> bool: return _shows(b, A, weapon)))
			. override_failure_message("B does not show A holding %s after the swap" % weapon)
			. is_true()
		)
	# Each class has its own model: the three shown were three different scenes.
	(
		assert_bool(
			(
				WeaponHoldMap.hold_for(&"crowbar").scene != WeaponHoldMap.hold_for(&"pistol").scene
				and (
					WeaponHoldMap.hold_for(&"pistol").scene
					!= WeaponHoldMap.hold_for(&"shotgun").scene
				)
			)
		)
		. is_true()
	)


func test_b_shows_a_aiming_and_lowering_the_gun() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return _pose(b, A) != null)).is_true()
	assert_bool(await _until(func() -> bool: return _shows(b, A, &"pistol"))).is_true()
	(_commands[a] as NightCommand).motion.aim = true
	assert_bool(await _until(func() -> bool: return _aim_weight(b, A) > 0.9)).is_true()
	# Aiming up: the barrel follows A's look, not the body's heading alone.
	(_commands[a] as NightCommand).motion.pitch = 0.5
	(
		assert_bool(await _until(func() -> bool: return absf(_barrel_pitch(b, A) - 0.5) < 0.1))
		. is_true()
	)
	(_commands[a] as NightCommand).motion.aim = false
	(_commands[a] as NightCommand).motion.pitch = 0.0
	(
		assert_bool(
			await _until(
				func() -> bool: return _aim_weight(b, A) >= 0.0 and _aim_weight(b, A) < 0.1
			)
		)
		. is_true()
	)


func test_b_shows_a_firing_with_a_flash_on_the_muzzle_and_the_report() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return _shows(b, A, &"pistol"))).is_true()
	var heard: Array = []
	(b.get_node("WeaponSounds") as WeaponSounds).play = func(
		sound: StringName, at: Variant, _db: float
	) -> void:
		heard.append([sound, at])
	(_commands[a] as NightCommand).fire = true
	var fired := await _until(func() -> bool: return String(_clip(b, A)).begins_with("Fire_"))
	(_commands[a] as NightCommand).fire = false
	assert_bool(fired).override_failure_message("B never saw A's fire clip").is_true()
	var muzzle := _pose(b, A).muzzle_point()
	assert_object(muzzle).is_not_null()
	# The flash is on the muzzle of the gun in A's hand (it was lit for this shot).
	assert_object(muzzle.get_node_or_null(NodePath(MuzzleFlash.NODE_NAME))).is_not_null()
	# And B hears the report from where A is.
	var reports := heard.filter(func(entry: Array) -> bool: return entry[0] == &"shot_pistol")
	assert_int(reports.size()).is_greater(0)
	assert_object(reports[0][1]).is_not_null()
	(
		assert_float((reports[0][1] as Vector3).distance_to(b.avatars.avatar(A).global_position))
		. is_less(3.0)
	)


func test_b_shows_a_reloading() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return _shows(b, A, &"pistol"))).is_true()
	# Spend a round so there is something to reload.
	(_commands[a] as NightCommand).fire = true
	await _until(
		func() -> bool:
			return (
				_host.server.combat.weapon_of(A).ammo
				< _host.server.combat.weapon_of(A).def.magazine_size
			)
	)
	(_commands[a] as NightCommand).fire = false
	await _ticks(20)
	await _tap(a, _reload)
	var tilted := await _until(func() -> bool: return _reload_dip(b, A) > 0.3)
	(
		assert_bool(tilted)
		. override_failure_message("B never saw A's gun tilt down for the reload")
		. is_true()
	)


func test_b_shows_a_swinging_the_crowbar() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return _pose(b, A) != null)).is_true()
	await _hold(a, &"crowbar")
	assert_bool(await _until(func() -> bool: return _shows(b, A, &"crowbar"))).is_true()
	(_commands[a] as NightCommand).fire = true
	var swung := await _until(func() -> bool: return _clip(b, A) == &"Swing_Melee")
	(_commands[a] as NightCommand).fire = false
	assert_bool(swung).override_failure_message("B never saw A swing").is_true()
	# A swing makes no muzzle flash.
	var muzzle := _pose(b, A).muzzle_point()
	(
		assert_bool(
			muzzle == null or muzzle.get_node_or_null(NodePath(MuzzleFlash.NODE_NAME)) == null
		)
		. is_true()
	)


func test_b_shows_a_cooking_and_throwing_a_grenade() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	var heard := _listen(b)
	assert_bool(await _until(func() -> bool: return _pose(b, A) != null)).is_true()
	# Grenades are for a round: the night leaves its break.
	_host.server.rules.apply(RulesAction.skip_break())
	(
		assert_bool(
			await _until(func() -> bool: return _host.server.rules.phase == GameRules.Phase.ACTIVE)
		)
		. is_true()
	)
	(_commands[a] as NightCommand).motion.throw_over = true
	var cooked := await _until(func() -> bool: return _clip(b, A) == &"Grenade_Cook")
	(
		assert_bool(cooked)
		. override_failure_message(
			(
				"B never saw A pull the pin (heard %s, phase %s, A has %d grenades)"
				% [
					heard.filter(func(t: StringName) -> bool: return t != &"frame"),
					_host.server.rules.phase,
					_host.server.rules.grenades_of(A)
				]
			)
		)
		. is_true()
	)
	(_commands[a] as NightCommand).motion.throw_over = false
	var thrown := await _until(func() -> bool: return _clip(b, A) == &"Grenade_Throw")
	assert_bool(thrown).override_failure_message("B never saw A throw").is_true()
	assert_bool(await _until(func() -> bool: return b.view.grenades_in_flight() > 0)).is_true()


func test_a_late_joiner_sees_what_everyone_holds_at_once() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return _shows(b, A, &"pistol"))).is_true()
	await _hold(a, &"crowbar")
	assert_bool(await _until(func() -> bool: return _shows(b, A, &"crowbar"))).is_true()
	var c := await _client()
	# No swap happens from here on: what C shows of A and of B is what they hold now.
	var seen := await _until(
		func() -> bool: return _shows(c, A, &"crowbar") and _shows(c, B, &"pistol"), 3.0
	)
	(
		assert_bool(seen)
		. override_failure_message(
			"the late joiner does not show A with the crowbar and B with the pistol"
		)
		. is_true()
	)


func test_the_weapon_is_on_the_wire_only_when_it_changes() -> void:
	var before := _frame_with(&"pistol", false, 0)
	var same := _frame_with(&"pistol", false, 0)
	var quiet := FrameDelta.diff(before, same)
	assert_dict(quiet["players"]).is_empty()
	var swapped := FrameDelta.diff(before, _frame_with(&"crowbar", false, 0))
	assert_bool((swapped["players"][A] as Dictionary).has("weapon")).is_true()
	assert_int((swapped["players"][A] as Dictionary).size()).is_equal(1)
	# A look that moved less than a step is not sent again.
	assert_int(NightServer.pitch_step(0.001)).is_equal(NightServer.pitch_step(0.0))
	assert_int(NightServer.pitch_step(0.5)).is_not_equal(NightServer.pitch_step(0.0))


func test_a_swap_or_a_new_look_costs_a_few_bytes_and_a_still_player_none() -> void:
	var before := _frame_with(&"pistol", false, 0)
	var quiet := NetWire.tick(1, [FrameDelta.diff(before, _frame_with(&"pistol", false, 0))])
	var swapped := NetWire.tick(1, [FrameDelta.diff(before, _frame_with(&"crowbar", false, 0))])
	var aimed := NetWire.tick(1, [FrameDelta.diff(before, _frame_with(&"pistol", true, 0))])
	var looked := NetWire.tick(1, [FrameDelta.diff(before, _frame_with(&"pistol", false, 4))])
	for packet: PackedByteArray in [swapped, aimed, looked]:
		assert_int(packet.size() - quiet.size()).is_less_equal(64)


func _frame_with(weapon: StringName, aim: bool, pitch: int) -> Dictionary:
	return {
		"type": &"frame",
		"tick": 1,
		"players": {A: {"weapon": weapon, "aim": aim, "pitch": pitch}},
	}


func test_a_client_of_the_version_before_is_refused() -> void:
	assert_bool(NetWire.accepts(NetWire.VERSION)).is_true()
	assert_bool(NetWire.accepts(NetWire.VERSION - 1)).is_false()
	# Version 5 drew the others without a weapon, aim or look: a server of this build refuses it.
	assert_bool(NetWire.accepts(5)).is_false()
	assert_int(NetWire.VERSION).is_greater(5)
