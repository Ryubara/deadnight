extends GdUnitTestSuite
## The energy weapons' sounds (#791), driven like a client: events in, sounds out, on a clock the
## test steps by hand. The shots are flat for the shooter and from the muzzle for a stranger; the
## bolt hums while it flies and the burst ends it; a freeze creaks until it thaws or shatters.

const OWN := 1
const OTHER := 2
const MUZZLE := Vector3(0.0, 1.5, 0.0)

var _heard: Array[Dictionary] = []
var _sounds: EnergySounds
var _weapons: WeaponSounds
var _state: ClientState
var _loops: Array[StringName] = []


func before_test() -> void:
	_heard = []
	_loops = []
	_state = ClientState.new()
	_state.player_id = OWN
	_sounds = auto_free(EnergySounds.new())
	_sounds.play = func(id: StringName, at: Variant, db: float) -> void:
		_heard.append({"id": id, "at": at, "db": db, "t": _sounds.schedule.now()})
	_sounds.start_loop = func(id: StringName, _parent: Node3D) -> Node:
		_loops.append(id)
		return null
	add_child(_sounds)
	_sounds.setup(_state)
	_weapons = auto_free(WeaponSounds.new())
	_weapons.play = _sounds.play
	add_child(_weapons)
	_weapons.setup(_state)
	_state.apply_events(
		[
			{
				"type": &"frame",
				"players": {OWN: {"pos": Vector3(1, 0, 2)}, OTHER: {"pos": Vector3(8, 0, 0)}},
				"zombies": []
			}
		]
	)


func _tell(event: Dictionary) -> void:
	_state.apply_events([event])


func _ids() -> Array:
	return _heard.map(func(h: Dictionary) -> StringName: return h["id"])


func _shot(weapon: StringName, shooter := OWN) -> Dictionary:
	return {
		"type": &"shot_fired",
		"shooter_id": shooter,
		"weapon_id": weapon,
		"muzzle": MUZZLE,
		"ends": [],
	}


func _equipped(player: int, weapon: StringName) -> Dictionary:
	return {
		"type": &"weapon_equipped",
		"player_id": player,
		"weapon_id": weapon,
		"ammo": 1,
		"reserve": 1
	}


func test_the_shots_are_flat_for_the_shooter_and_from_the_muzzle_for_a_stranger() -> void:
	_tell(_shot(&"ray_gun", OWN))
	_tell(_shot(&"freeze_gun", OTHER))
	assert_array(_ids()).is_equal([&"shot_ray", &"shot_freeze"])
	assert_object(_heard[0]["at"]).is_null()
	assert_vector(_heard[1]["at"]).is_equal(MUZZLE)


func test_the_firearms_shots_are_not_these() -> void:
	_tell(_shot(&"smg"))
	assert_bool(_ids().has(&"shot_ray")).is_false()
	assert_bool(_ids().has(&"shot_freeze")).is_false()


func test_each_weapon_is_raised_with_its_own_sound() -> void:
	_tell(_equipped(OWN, &"ray_gun"))
	_tell(_equipped(OTHER, &"freeze_gun"))
	assert_bool(_ids().has(&"equip_ray")).is_true()
	assert_bool(_ids().has(&"equip_freeze")).is_true()


func test_a_reload_takes_a_cell_out_and_puts_one_in_over_its_time() -> void:
	_tell({"type": &"reload_started", "shooter_id": OWN, "weapon_id": &"ray_gun", "seconds": 2.0})
	assert_array(_ids()).is_empty()
	_sounds.advance(0.5)
	assert_array(_ids()).is_equal([&"reload_ray_cell_out"])
	_sounds.advance(1.5)
	assert_array(_ids()).is_equal([&"reload_ray_cell_out", &"reload_ray_cell_in"])
	_heard.clear()
	_tell(
		{"type": &"reload_started", "shooter_id": OWN, "weapon_id": &"freeze_gun", "seconds": 2.0}
	)
	_sounds.advance(2.0)
	assert_array(_ids()).is_equal([&"reload_freeze_out", &"reload_freeze_in"])


func test_a_weapon_put_away_abandons_its_reload_sounds() -> void:
	_tell({"type": &"reload_started", "shooter_id": OWN, "weapon_id": &"ray_gun", "seconds": 2.0})
	_tell(_equipped(OWN, &"pistol"))
	_sounds.advance(3.0)
	assert_bool(_ids().has(&"reload_ray_cell_in")).is_false()


func test_the_own_reload_is_flat_and_a_teammates_is_at_his_head_and_louder() -> void:
	_tell({"type": &"reload_started", "shooter_id": OWN, "weapon_id": &"ray_gun", "seconds": 1.0})
	_tell({"type": &"reload_started", "shooter_id": OTHER, "weapon_id": &"ray_gun", "seconds": 1.0})
	_sounds.advance(1.0)
	var own := _heard.filter(func(h: Dictionary) -> bool: return h["at"] == null)
	var other := _heard.filter(func(h: Dictionary) -> bool: return h["at"] != null)
	assert_int(own.size()).is_equal(2)
	assert_int(other.size()).is_equal(2)
	assert_float(other[0]["db"]).is_greater(own[0]["db"] + 3.0)


func test_a_bolt_hums_while_it_flies_and_the_burst_ends_it() -> void:
	_tell(
		{
			"type": &"projectile_spawned",
			"projectile_id": 7,
			"shooter_id": OWN,
			"weapon_id": &"ray_gun",
			"position": Vector3(0, 1.5, 0),
			"velocity": Vector3(0, 0, -40),
		}
	)
	assert_array(_loops).is_equal([&"bolt_ray"])
	assert_int(_sounds.bolts_in_flight()).is_equal(1)
	_sounds.advance(0.5)
	# The hum rides the bolt: 40 m a second for half a second.
	assert_float(_sounds.bolt_anchor(7).position.z).is_equal_approx(-20.0, 0.01)
	_tell(
		{
			"type": &"projectile_burst",
			"projectile_id": 7,
			"shooter_id": OWN,
			"weapon_id": &"ray_gun",
			"point": Vector3(0, 1.5, -22),
			"radius": 4.0,
			"kind": &"target",
		}
	)
	assert_int(_sounds.bolts_in_flight()).is_equal(0)
	assert_array(_ids()).is_equal([&"burst_ray"])
	assert_vector(_heard[0]["at"]).is_equal(Vector3(0, 1.5, -22))


func test_a_flares_burst_is_the_flares_and_not_the_rays() -> void:
	var burst := {
		"type": &"projectile_burst",
		"projectile_id": 8,
		"shooter_id": OWN,
		"point": Vector3(0, 0, -5),
		"radius": 4.0,
		"kind": &"world",
	}
	_tell(burst.merged({"weapon_id": &"flare_gun"}))
	assert_array(_ids()).is_equal([&"burst_flare"])
	_heard.clear()
	_tell(burst.merged({"weapon_id": &"ray_gun"}))
	assert_array(_ids()).is_equal([&"burst_ray"])


func test_a_lost_burst_does_not_leave_the_hum_on() -> void:
	_tell(
		{
			"type": &"projectile_spawned",
			"projectile_id": 9,
			"shooter_id": OWN,
			"weapon_id": &"ray_gun",
			"position": Vector3.ZERO,
			"velocity": Vector3(0, 0, -40),
		}
	)
	_sounds.advance(EnergySounds.BOLT_MAX_SECONDS + 0.1)
	assert_int(_sounds.bolts_in_flight()).is_equal(0)


func test_a_freeze_takes_hold_creaks_while_it_holds_and_thaws() -> void:
	var at := Vector3(3, 0, 3)
	_tell({"type": EnergySounds.ZOMBIE_FROZEN, "zombie_id": 4, "point": at, "seconds": 3.0})
	assert_array(_ids()).is_equal([&"freeze_hit"])
	_sounds.advance(2.0)
	var creaks := _ids().filter(func(id: StringName) -> bool: return id == &"freeze_creak")
	assert_int(creaks.size()).is_between(1, 3)
	_sounds.advance(0.99)
	_tell({"type": EnergySounds.ZOMBIE_THAWED, "zombie_id": 4, "point": at})
	assert_array(_ids()).contains([&"freeze_thaw"])
	var count := _heard.size()
	_sounds.advance(5.0)
	assert_int(_heard.size()).is_equal(count)


func test_a_shatter_ends_the_creaks_and_breaks_with_its_own_sound() -> void:
	var at := Vector3(3, 0, 3)
	_tell({"type": EnergySounds.ZOMBIE_FROZEN, "zombie_id": 4, "point": at, "seconds": 3.0})
	_sounds.advance(0.8)
	_tell({"type": EnergySounds.ZOMBIE_SHATTERED, "zombie_id": 4, "point": at})
	assert_str(_ids()[-1]).is_equal("freeze_shatter")
	assert_bool(_ids().has(&"freeze_thaw")).is_false()
	var count := _heard.size()
	_sounds.advance(5.0)
	assert_int(_heard.size()).is_equal(count)


func test_two_frozen_zombies_creak_on_their_own_clocks() -> void:
	_tell(
		{
			"type": EnergySounds.ZOMBIE_FROZEN,
			"zombie_id": 1,
			"point": Vector3(1, 0, 1),
			"seconds": 3.0
		}
	)
	_tell(
		{
			"type": EnergySounds.ZOMBIE_FROZEN,
			"zombie_id": 2,
			"point": Vector3(5, 0, 5),
			"seconds": 3.0
		}
	)
	_tell({"type": EnergySounds.ZOMBIE_SHATTERED, "zombie_id": 1, "point": Vector3(1, 0, 1)})
	_sounds.advance(2.5)
	var creaks := _heard.filter(func(h: Dictionary) -> bool: return h["id"] == &"freeze_creak")
	assert_array(creaks).is_not_empty()
	for creak in creaks:
		assert_vector(creak["at"]).is_equal(Vector3(5, 0, 5))


func test_every_sound_it_plays_is_in_the_catalogue_with_its_files() -> void:
	var ids: Array[StringName] = [
		EnergySounds.BOLT_LOOP,
		EnergySounds.BURST,
		EnergySounds.FREEZE_HIT,
		EnergySounds.FREEZE_CREAK,
		EnergySounds.FREEZE_THAW,
		EnergySounds.FREEZE_SHATTER,
	]
	ids.append_array(EnergySounds.FIRE.values())
	ids.append_array(EnergySounds.EQUIP.values())
	for weapon: StringName in EnergySounds.RELOAD:
		for step: StringName in EnergySounds.RELOAD[weapon]:
			ids.append(EnergySounds.RELOAD[weapon][step][0])
	for id in ids:
		var def := SoundCatalog.get_def(id)
		assert_object(def).override_failure_message("no sound " + id).is_not_null()
		for k in def.variants:
			(
				assert_bool(ResourceLoader.exists(def.path_for(k + 1)))
				. override_failure_message(def.path_for(k + 1))
				. is_true()
			)
	assert_bool(SoundCatalog.get_def(EnergySounds.BOLT_LOOP).loop).is_true()


func test_the_shots_follow_the_firearms_pitch_and_group_rules() -> void:
	for id: StringName in EnergySounds.FIRE.values():
		var def := SoundCatalog.get_def(id)
		assert_float(def.pitch_semitones).is_less_equal(ArmsCatalog.FIREARM_PITCH_SEMITONES)
		assert_str(def.group).is_equal("gun")
		assert_float(def.near_cap_db).is_equal(0.0)
