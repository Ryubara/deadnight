# Every weapon reaches the player's inventory from every source that can give it (#904): the
# maintainer took weapons from outside the mystery box and they did not end up in the inventory.
# Each weapon of `WeaponCatalog.IDS` is taken the way a player takes it (stand at the wall spot or
# the crane, press use) with every carry there is (one place free, hands full, the third-weapon
# perk, every weapon carried re-cut, after a down that took the perk), and the server's loadout, the
# rules' list, the frame the client reads and the HUD's slots must all say the weapon is carried,
# in hand and loaded. The sources are read from the tuning of each map, not listed here, so a
# weapon given a new source is walked the day it is added. The seat of a player who left is the last
# walk: the next person to take the seat starts with the start weapon and nothing of the one before.
extends GdUnitTestSuite

const PLAYER := 1
## The seconds a crane play spins in this suite, and the ticks that hold it with room to spare.
const SPIN_SECONDS := 0.5
const SPIN_TICKS := 60
const POINTS := 90000
const MAPS: Array[String] = [MapRegistry.DEFAULT, "small_indoor"]
## Weapons a hand is filled with (none of them the one under test).
const FILLERS: Array[StringName] = [&"smg", &"rifle", &"shotgun", &"pistol"]


func _start(map: String) -> Dictionary:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	var night := Night.new()
	night.hud = hud
	night.match_settings.map = map
	add_child(night)
	await night.start(Night.Mode.MANUAL, 7, RulesFixture.steady_crane_tuning())
	# The map's own rules overlay is what plays, so the quick spin goes on that one.
	night.server.rules.tuning.crane.spin_seconds = SPIN_SECONDS
	night.server.rules.tuning.crane.leave_chances = PackedFloat32Array([0.0])
	NightFixture.run(night, 30)
	return {"night": night, "hud": hud}


func _finish(made: Dictionary) -> void:
	(made["night"] as Night).queue_free()
	(made["hud"] as Hud).queue_free()


## Stands at the spot and reads its card for as long as a replacing purchase asks (#908): a press
## that throws a carried weapon away is one made once the card that says so has been up.
func _stand_at(night: Night, spot: Dictionary) -> void:
	night.player().teleport(spot["position"] + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 3 + ceili(night.server.tuning.replace_settle / Night.STEP))


func _use(night: Night) -> void:
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)


func _spots(night: Night, kind: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for spot in night.world.shop_spots():
		if spot["kind"] == kind:
			found.append(spot)
	return found


func _wall_spot(night: Night, shop_id: StringName) -> Dictionary:
	for spot in _spots(night, &"wall"):
		if spot["shop_id"] == shop_id:
			return spot
	return {}


## The crane where it stands now: the spot of the crane's current place.
func _crane_spot(night: Night) -> Dictionary:
	for spot in _spots(night, &"crane"):
		if spot["crane_spot"] == night.server.rules.crane.spot:
			return spot
	return {}


## The weapons (catalogue ids) the walls of this night's map sell, once each.
func _wall_weapons(night: Night) -> Array[StringName]:
	var ids: Array[StringName] = []
	for spot in _spots(night, &"wall"):
		var id := WeaponCatalog.catalog_id(spot["shop_id"])
		if not ids.has(id):
			ids.append(id)
	return ids


## The weapons (catalogue ids) the crane's pool can give.
func _prizes(night: Night) -> Array[StringName]:
	var ids: Array[StringName] = []
	for prize in night.server.rules.tuning.economy.item(&"crane_play").pool:
		ids.append(WeaponCatalog.catalog_id(prize))
	return ids


## Only `id` in the crane's pool, so the play gives it.
func _pool_only(night: Night, id: StringName) -> void:
	var crane := night.server.rules.tuning.economy.item(&"crane_play")
	crane.pool.assign([StringName(WeaponCatalog.SHOP_PREFIX + String(id))])
	crane.pool_weights = PackedFloat32Array([1.0])


## Sets what the player carries: exactly `ids`, in the rules and in the combat server alike (the
## setup only; every take under test is a real use).
func _carry(night: Night, ids: Array[StringName]) -> void:
	var player := night.server.rules.players[PLAYER] as PlayerState
	var gone: Array = []
	for shop_id in player.weapons:
		gone.append(WeaponCatalog.catalog_id(shop_id))
	night.server.combat.apply(CombatAction.remove_weapons(PLAYER, gone))
	player.weapons.clear()
	player.upgraded.clear()
	for id in ids:
		player.weapons.append(StringName(WeaponCatalog.SHOP_PREFIX + String(id)))
		night.server.combat.apply(CombatAction.give_weapon(PLAYER, id))
	NightFixture.run(night, 3)


## Weapons to carry before the take: `count` of them, none of them `id`.
func _others(id: StringName, count: int) -> Array[StringName]:
	var pool: Array[StringName] = FILLERS.duplicate()
	pool.erase(id)
	return pool.slice(0, count)


## Every weapon carried re-cut (the last one equipped is the one in hand).
func _recut_all(night: Night, ids: Array[StringName]) -> void:
	for id in ids:
		night.server.combat.apply(CombatAction.equip(PLAYER, id))
		night.server.buy(PLAYER, &"upgrade_weapon")
		NightFixture.run(night, 2)
		assert_int(night.server.combat.state_of(PLAYER, id).tier()).is_greater(0)


## The player has the third-weapon perk (the tonic is bought, not set).
func _third_holster(night: Night) -> void:
	night.server.buy(PLAYER, &"tonic_third_holster")
	NightFixture.run(night, 2)
	assert_int(PerkEffects.carry_limit(night.server.rules, PLAYER)).is_equal(3)


## What the rules say player `id` carries, as catalogue ids, sorted.
func _rules_ids(night: Night, id: int) -> Array:
	var ids: Array = []
	for shop_id in night.server.rules.players[id].weapons:
		ids.append(WeaponCatalog.catalog_id(shop_id))
	ids.sort()
	return ids


## What the combat server says player `id` carries, sorted.
func _combat_ids(night: Night, id: int) -> Array:
	var ids: Array = night.server.combat.carried(id).duplicate()
	ids.sort()
	return ids


## Everything that must say `id` is carried, in hand and loaded.
func _check_carried(made: Dictionary, id: StringName, tag: String) -> void:
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	var shop_id := StringName(WeaponCatalog.SHOP_PREFIX + String(id))
	var rules_list: Array = night.server.rules.players[PLAYER].weapons
	(
		assert_bool(rules_list.has(shop_id))
		. override_failure_message("%s: not in the rules' list %s" % [tag, rules_list])
		. is_true()
	)
	var carried := night.server.combat.carried(PLAYER)
	(
		assert_bool(carried.has(id))
		. override_failure_message("%s: not in the combat server's loadout %s" % [tag, carried])
		. is_true()
	)
	(
		assert_array(_combat_ids(night, PLAYER))
		. override_failure_message(
			"%s: loadout %s differs from the rules' list %s" % [tag, carried, rules_list]
		)
		. is_equal(_rules_ids(night, PLAYER))
	)
	var me := night.state.me()
	(
		assert_str(String(me["weapon"]))
		. override_failure_message("%s: the frame's weapon in hand is %s" % [tag, me["weapon"]])
		. is_equal(String(id))
	)
	var arms: Dictionary = me["arms"]
	(
		assert_bool(arms.has(id))
		. override_failure_message("%s: not in the frame's arms %s" % [tag, arms.keys()])
		. is_true()
	)
	if night.server.combat.state_of(PLAYER, id).uses_ammo():
		assert_int(int(arms[id][0])).override_failure_message(tag + ": no rounds").is_greater(0)
		assert_int(int(arms[id][1])).override_failure_message(tag + ": no reserve").is_greater(0)
	(
		assert_bool(hud.state.slot_ids.has(id))
		. override_failure_message("%s: not in the HUD's slots %s" % [tag, hud.state.slot_ids])
		. is_true()
	)
	(
		assert_int(hud.state.slot_held)
		. override_failure_message(
			(
				"%s: the HUD's slot in hand is %d of %s"
				% [tag, hud.state.slot_held, hud.state.slot_ids]
			)
		)
		. is_equal(hud.state.slot_ids.find(id) + 1)
	)


## The crane's play and its prize taken at the crane, as a player does.
func _take_from_crane(night: Night, id: StringName) -> void:
	_pool_only(night, id)
	night.server.rules.apply(RulesAction.grant_points(PLAYER, POINTS))
	_stand_at(night, _crane_spot(night))
	_use(night)
	NightFixture.run(night, SPIN_TICKS)
	assert_str(String(night.server.rules.crane.weapon)).is_equal(
		WeaponCatalog.SHOP_PREFIX + String(id)
	)
	_stand_at(night, _crane_spot(night))
	_use(night)


func _take_from_wall(night: Night, id: StringName) -> void:
	night.server.rules.apply(RulesAction.grant_points(PLAYER, POINTS))
	_stand_at(night, _wall_spot(night, StringName(WeaponCatalog.SHOP_PREFIX + String(id))))
	_use(night)


## The carries a take is tried with: the limit (two, or three with the perk), how many weapons are
## carried and whether they are re-cut. The ones of a limit of two come first: the perk stays.
func _hands() -> Array[Dictionary]:
	return [
		{"limit": 2, "carried": 1},
		{"limit": 2, "carried": 2},
		{"limit": 2, "carried": 2, "recut": true},
		{"limit": 3, "carried": 2},
		{"limit": 3, "carried": 3},
		{"limit": 3, "carried": 3, "recut": true},
	]


## Walks every weapon `ids_of` names (a Callable taking the night) from one source (`take`, a
## Callable taking the night and the id) through every carry, on a night of `map`.
func _walk(map: String, source: String, ids_of: Callable, take: Callable) -> void:
	var made := await _start(map)
	var night: Night = made["night"]
	night.server.rules.apply(RulesAction.grant_points(PLAYER, POINTS))
	for hands in _hands():
		if hands["limit"] == 3 and PerkEffects.carry_limit(night.server.rules, PLAYER) < 3:
			_third_holster(night)
		for id: StringName in ids_of.call(night):
			var others := _others(id, hands["carried"])
			_carry(night, others)
			if hands.get("recut", false):
				_recut_all(night, others)
			take.call(night, id)
			_check_carried(made, id, "%s %s on %s with %s" % [source, id, map, hands])
	_finish(made)


func test_the_crane_gives_every_prize_with_every_carry() -> void:
	for map in MAPS:
		await _walk(map, "crane", _prizes, _take_from_crane)


func test_every_wall_gives_its_weapon_with_every_carry() -> void:
	for map in MAPS:
		await _walk(map, "wall", _wall_weapons, _take_from_wall)


func test_every_weapon_has_a_source_a_player_can_stand_at() -> void:
	# A weapon nothing sells and no crane gives is a weapon no test above walks.
	var given := {}
	for map in MAPS:
		var made := await _start(map)
		var night: Night = made["night"]
		for id in _prizes(night) + _wall_weapons(night):
			given[id] = true
		for shop_id in night.server.rules.tuning.economy.start_weapons:
			given[WeaponCatalog.catalog_id(shop_id)] = true
		_finish(made)
	for id in WeaponCatalog.IDS:
		(
			assert_bool(given.has(id))
			. override_failure_message("%s: no source on any map" % id)
			. is_true()
		)


func test_a_re_cut_keeps_every_weapon_carried_and_in_hand() -> void:
	var made := await _start(MapRegistry.DEFAULT)
	var night: Night = made["night"]
	var spec := night.server.rules.tuning.upgrade
	for id in WeaponCatalog.IDS:
		var ids: Array[StringName] = [id]
		_carry(night, ids)
		night.server.rules.apply(RulesAction.grant_points(PLAYER, POINTS))
		night.server.buy(PLAYER, &"upgrade_weapon")
		NightFixture.run(night, 3)
		var tag := "re-cut %s" % id
		_check_carried(made, id, tag)
		if spec.allows(id):
			var state := night.server.combat.state_of(PLAYER, id)
			assert_int(state.tier()).override_failure_message(tag + ": not re-cut").is_equal(1)
			var arms: Dictionary = night.state.me()["arms"]
			assert_int(int(arms[id][2])).override_failure_message(tag + ": frame tier").is_equal(1)
	_finish(made)


func test_a_down_that_takes_the_third_weapon_leaves_the_rest_takeable() -> void:
	for map in MAPS:
		var made := await _start(map)
		var night: Night = made["night"]
		# A teammate is up, so the down is not the end of the night.
		night.server.apply({"type": NightServer.JOIN, "player_id": 2, "local": false})
		night.server.rules.apply(RulesAction.skip_break())
		night.server.rules.apply(RulesAction.grant_points(PLAYER, POINTS))
		NightFixture.run(night, 3)
		var wall := _wall_weapons(night)
		for id in [_prizes(night).back(), wall.back()]:
			_third_holster(night)
			var others: Array[StringName] = [&"smg", &"shotgun", &"pistol"]
			others.erase(id)
			_carry(night, others)
			night.server.rules.apply(RulesAction.set_downed(PLAYER, true))
			NightFixture.run(night, 3)
			night.server.rules.apply(RulesAction.set_downed(PLAYER, false))
			NightFixture.run(night, 3)
			var tag := "after a down, taking %s on %s" % [id, map]
			assert_int(PerkEffects.carry_limit(night.server.rules, PLAYER)).is_equal(2)
			(
				assert_array(_combat_ids(night, PLAYER))
				. override_failure_message(
					(
						"%s: loadout %s, rules %s"
						% [tag, _combat_ids(night, PLAYER), _rules_ids(night, PLAYER)]
					)
				)
				. is_equal(_rules_ids(night, PLAYER))
			)
			if wall.has(id):
				_take_from_wall(night, id)
			else:
				_take_from_crane(night, id)
			_check_carried(made, id, tag)
		_finish(made)


func test_the_next_person_in_a_seat_starts_with_the_start_weapon_and_nothing_of_the_last() -> void:
	# The lowest free id goes to the next person (`NightHost`): the weapons of the one who left,
	# with their rounds and re-cuts, must not come with the seat, and the rules and the combat
	# server must agree on what the newcomer carries.
	var made := await _start(MapRegistry.DEFAULT)
	var night: Night = made["night"]
	var server := night.server
	var seat := 2
	var start: Array = []
	for shop_id in server.rules.tuning.economy.start_weapons:
		start.append(WeaponCatalog.catalog_id(shop_id))
	start.sort()
	for leaver in [[&"mp5", &"m249"], [&"pump_870", &"rifle"], [&"dual_pistols"]]:
		server.apply({"type": NightServer.JOIN, "player_id": seat, "local": false})
		for id: StringName in leaver:
			server.combat.apply(CombatAction.give_weapon(seat, id))
			server.rules.players[seat].weapons.append(
				StringName(WeaponCatalog.SHOP_PREFIX + String(id))
			)
			server.combat.apply(CombatAction.upgrade_weapon(seat, id))
		server.apply({"type": NightServer.LEAVE, "player_id": seat})
		server.apply({"type": NightServer.JOIN, "player_id": seat, "local": false})
		var tag := "the seat after %s" % [leaver]
		(
			assert_array(_combat_ids(night, seat))
			. override_failure_message(
				"%s: the newcomer carries %s" % [tag, _combat_ids(night, seat)]
			)
			. is_equal(start)
		)
		assert_array(_rules_ids(night, seat)).is_equal(start)
		for id in start:
			(
				assert_int(server.combat.state_of(seat, id).tier())
				. override_failure_message(tag + ": the newcomer's start weapon is re-cut")
				. is_equal(0)
			)
		server.apply({"type": NightServer.LEAVE, "player_id": seat})
	_finish(made)
