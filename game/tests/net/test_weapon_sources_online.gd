# A teammate on a real WebSocket takes every weapon the crane can give and every weapon a wall
# sells (#904): the server's loadout, and the frame and the events the client hears, must say the
# weapon is carried, in hand and loaded. The offline matrix is `test_weapon_sources.gd`.
extends GdUnitTestSuite

const A := 1
const B := 2
## The seconds a crane play spins in this suite (the shipped 4.5 is real time over a socket).
const SPIN := 0.5

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


func _server() -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	var tuning := RulesFixture.steady_crane_tuning()
	tuning.crane.spin_seconds = SPIN
	_host.rules_tuning = tuning
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)


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


## A press at a spot, made once its card has been up for as long as a replacing purchase asks
## (#908: a press that throws a carried weapon away is a meant one).
func _use(night: Night) -> void:
	var read_until := (
		_host.server.tick_count + ceili(_host.server.tuning.replace_settle / Night.STEP)
	)
	await _until(func() -> bool: return _host.server.tick_count > read_until)
	var command := _commands[night] as NightCommand
	command.use = true
	await night.ticked
	command.use = false
	await night.ticked
	await night.ticked


func _spot(kind: StringName, shop_id: StringName = &"") -> Dictionary:
	for spot in _host.server.world.shop_spots():
		if spot["kind"] != kind:
			continue
		if kind == &"crane" and spot["crane_spot"] != _host.server.rules.crane.spot:
			continue
		if shop_id == &"" or spot["shop_id"] == shop_id:
			return spot
	return {}


func _stand(id: int, spot: Dictionary) -> void:
	_host.server.body_of(id).teleport(spot["position"] + Vector3(0.0, 0.1, 0.0))


## What `night` was told about its own player: in hand `id`, among the arms with rounds.
func _told_carried(night: Night, id: StringName) -> bool:
	var me := night.state.me()
	var arms: Dictionary = me.get("arms", {})
	if me.get("weapon", &"") != id or not arms.has(id):
		return false
	return int(arms[id][0]) + int(arms[id][1]) > 0 or WeaponCatalog.get_def(id).is_melee()


func _report(night: Night, how: String) -> String:
	var me := night.state.me()
	return (
		"%s: the server carries %s (rules %s), the client was told weapon %s, arms %s"
		% [
			how,
			_host.server.combat.carried(B),
			_host.server.rules.players[B].weapons,
			me.get("weapon"),
			me.get("arms", {}).keys(),
		]
	)


func test_a_teammate_takes_every_crane_prize_and_wall_weapon() -> void:
	await _server()
	await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return b.state.me().has("arms"))).is_true()
	var crane := _host.server.rules.tuning.economy.item(&"crane_play")
	var prizes: Array[StringName] = []
	for prize in crane.pool:
		prizes.append(WeaponCatalog.catalog_id(prize))
	for id in prizes:
		if _host.server.combat.carried(B).has(id):
			continue
		crane.pool.assign([StringName(WeaponCatalog.SHOP_PREFIX + String(id))])
		crane.pool_weights = PackedFloat32Array([1.0])
		_host.server.rules.apply(RulesAction.grant_points(B, 5000))
		_stand(B, _spot(&"crane"))
		await _until(func() -> bool: return _host.server.rules.crane.is_ready(), 10.0)
		await _use(b)
		var ready := await _until(
			func() -> bool: return _host.server.rules.crane.stage == CraneState.Stage.GRAB, 10.0
		)
		assert_bool(ready).override_failure_message("crane %s: no prize held out" % id).is_true()
		await _use(b)
		var told := await _until(func() -> bool: return _told_carried(b, id), 5.0)
		assert_bool(told).override_failure_message(_report(b, "crane " + String(id))).is_true()
	for shop_id in [&"weapon_shotgun", &"weapon_rifle"]:
		var id := WeaponCatalog.catalog_id(shop_id)
		_host.server.combat.apply(CombatAction.remove_weapons(B, [id]))
		_host.server.rules.players[B].weapons.erase(shop_id)
		_host.server.rules.apply(RulesAction.grant_points(B, 5000))
		_stand(B, _spot(&"wall", shop_id))
		await _use(b)
		var told := await _until(func() -> bool: return _told_carried(b, id), 5.0)
		assert_bool(told).override_failure_message(_report(b, "wall " + String(id))).is_true()


func test_a_teammate_who_takes_the_seat_of_one_who_left_starts_with_the_start_weapon() -> void:
	# The lowest free id goes to the next person who joins: what the one before carried, re-cut
	# and loaded, is gone with them, and the newcomer's weapons are the rules' and the server's
	# alike (the rules sell and refuse by their list, the combat server gives by its own).
	await _server()
	_host.resume_within = 0.0
	await _client()
	var leaver := await _client()
	assert_bool(await _until(func() -> bool: return leaver.state.me().has("arms"))).is_true()
	for id: StringName in [&"m249", &"mp5"]:
		_host.server.combat.apply(CombatAction.give_weapon(B, id))
		_host.server.rules.players[B].weapons.append(
			StringName(WeaponCatalog.SHOP_PREFIX + String(id))
		)
		_host.server.combat.apply(CombatAction.upgrade_weapon(B, id))
	leaver.get_parent().queue_free()
	_nights.erase(leaver)
	(
		assert_bool(await _until(func() -> bool: return not _host.server.rules.players.has(B)))
		. is_true()
	)
	var newcomer := await _client()
	assert_bool(await _until(func() -> bool: return newcomer.state.me().has("arms"))).is_true()
	assert_int(newcomer.state.player_id).is_equal(B)
	var start: Array = []
	for shop_id in _host.server.rules.tuning.economy.start_weapons:
		start.append(WeaponCatalog.catalog_id(shop_id))
	var carried := _host.server.combat.carried(B)
	(
		assert_array(carried)
		. override_failure_message(
			"the newcomer on seat %d carries %s, the rules say %s" % [B, carried, start]
		)
		. is_equal(start)
	)
	assert_array(newcomer.state.me()["arms"].keys()).is_equal(start)
