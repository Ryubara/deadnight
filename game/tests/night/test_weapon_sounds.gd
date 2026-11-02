extends GdUnitTestSuite
## The guns' sounds, driven like a client: events in, sounds out, on a clock the test steps by
## hand. Every shot is a report and a late tail, a reload sounds on its clip's event frames, an
## empty trigger clicks, and a round that hits the lot ricochets while one that hits a zombie
## thumps.

const OWN := 1
const MUZZLE := Vector3(0.0, 1.5, 0.0)

var _heard: Array[Dictionary] = []
var _sounds: WeaponSounds
var _state: ClientState


func before_test() -> void:
	_heard = []
	_state = ClientState.new()
	_state.player_id = OWN
	_sounds = auto_free(WeaponSounds.new())
	_sounds.play = func(id: StringName, at: Variant, db: float) -> void:
		_heard.append({"id": id, "at": at, "db": db, "t": _sounds.schedule.now()})
	add_child(_sounds)
	_sounds.setup(_state, 5)
	_state.apply_events(
		[{"type": &"frame", "players": {OWN: {"pos": Vector3(1, 0, 2)}}, "zombies": []}]
	)


func _tell(event: Dictionary) -> void:
	_state.apply_events([event])


func _ids() -> Array:
	return _heard.map(func(h: Dictionary) -> StringName: return h["id"])


func _shot(weapon: StringName, ends: Array[Vector3] = []) -> Dictionary:
	return {
		"type": &"shot_fired",
		"shooter_id": OWN,
		"weapon_id": weapon,
		"muzzle": MUZZLE,
		"ends": ends,
	}


func _hit(point: Vector3, headshot := false, melee := false) -> Dictionary:
	return {
		"type": &"damage_dealt",
		"shooter_id": OWN,
		"target_id": 3,
		"zone": &"head" if headshot else &"body",
		"damage": 30.0,
		"headshot": headshot,
		"melee": melee,
		"pellets": 1,
		"health": 10.0,
		"point": point,
	}


func test_every_firearm_shot_is_a_report_and_a_late_tail() -> void:
	for weapon: StringName in [&"pistol", &"smg", &"rifle", &"shotgun"]:
		_heard.clear()
		var start := _sounds.schedule.now()
		_tell(_shot(weapon))
		assert_array(_ids()).is_equal([StringName("shot_%s" % weapon)])
		_sounds.schedule.advance(0.2)
		assert_array(_ids()).contains([StringName("tail_%s" % weapon)])
		assert_float(_heard[-1]["t"] - start).is_between(
			WeaponSounds.TAIL_DELAY, WeaponSounds.TAIL_DELAY + WeaponSounds.TAIL_SPREAD + 0.001
		)


func test_the_flare_gun_pops_and_the_burst_sizzles_where_it_lands() -> void:
	_tell(_shot(&"flare_gun"))
	assert_array(_ids()).is_equal([&"shot_flare"])
	_tell({"type": &"projectile_burst", "point": Vector3(9, 0, 9)})
	assert_array(_ids()).is_equal([&"shot_flare", &"burst_flare"])


func test_the_crowbar_is_left_to_the_melee_sounds() -> void:
	_tell(_shot(&"crowbar"))
	_sounds.schedule.advance(1.0)
	assert_array(_heard).is_empty()


func test_repeats_differ_in_level() -> void:
	for i in 12:
		_tell(_shot(&"rifle"))
	var levels := {}
	for h in _heard:
		levels[snappedf(h["db"], 0.001)] = true
	assert_int(levels.size()).is_greater(6)


func test_a_reload_sounds_on_the_frames_of_its_clip() -> void:
	for weapon: StringName in [&"pistol", &"smg", &"rifle", &"shotgun", &"flare_gun"]:
		_heard.clear()
		_sounds.schedule.clear()
		_tell({"type": &"reload_started", "shooter_id": OWN, "weapon_id": weapon, "seconds": 2.0})
		assert_array(_heard).is_empty()
		var table: Dictionary = WeaponSounds.RELOAD[weapon]
		var expected: Array[Dictionary] = []
		for step: StringName in table["steps"]:
			for seconds in ClipEvents.times(table["clip"], step):
				expected.append({"id": table["steps"][step], "t": seconds})
		expected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
		assert_int(expected.size()).is_greater(1)
		# Just before each frame nothing new has sounded; just after, exactly that step has.
		var now := 0.0
		for entry in expected:
			var before := _heard.size()
			_sounds.schedule.advance(entry["t"] - now - 0.001)
			assert_int(_heard.size()).override_failure_message("early: %s" % entry["id"]).is_equal(
				before
			)
			_sounds.schedule.advance(0.002)
			assert_int(_heard.size()).override_failure_message("late: %s" % entry["id"]).is_equal(
				before + 1
			)
			assert_str(_heard[-1]["id"]).is_equal(entry["id"])
			now = entry["t"] + 0.001
		assert_int(_heard.size()).is_equal(expected.size())


func test_the_rifle_loads_three_rounds_then_throws_the_lever() -> void:
	_tell({"type": &"reload_started", "shooter_id": OWN, "weapon_id": &"rifle", "seconds": 2.2})
	_sounds.schedule.advance(5.0)
	assert_array(_ids()).is_equal(
		[&"reload_rifle_round", &"reload_rifle_round", &"reload_rifle_round", &"reload_rifle_lever"]
	)
	# Frames 20, 32 and 44, then the lever at 56, at 24 frames a second.
	assert_float(_heard[0]["t"]).is_equal_approx(20.0 / 24.0, 0.001)
	assert_float(_heard[1]["t"]).is_equal_approx(32.0 / 24.0, 0.001)
	assert_float(_heard[3]["t"]).is_equal_approx(56.0 / 24.0, 0.001)


func test_putting_the_weapon_away_abandons_the_reload() -> void:
	_tell({"type": &"reload_started", "shooter_id": OWN, "weapon_id": &"shotgun", "seconds": 2.4})
	_sounds.schedule.advance(0.1)
	var before := _heard.size()
	_tell(
		{
			"type": &"weapon_equipped",
			"player_id": OWN,
			"weapon_id": &"pistol",
			"ammo": 8,
			"reserve": 8
		}
	)
	_sounds.schedule.advance(5.0)
	assert_array(_ids().slice(before)).is_equal([&"weapon_swap"])


func test_an_empty_trigger_clicks_where_the_shooter_stands() -> void:
	_tell({"type": &"fire_rejected", "shooter_id": OWN, "seq": 1, "reason": &"empty"})
	assert_array(_ids()).is_equal([&"dry_fire"])
	assert_vector(_heard[0]["at"]).is_equal(Vector3(1.0, 1.6, 2.0))
	_heard.clear()
	_tell({"type": &"fire_rejected", "shooter_id": OWN, "seq": 2, "reason": &"reloading"})
	assert_array(_heard).is_empty()


func test_a_round_into_the_lot_ricochets_and_one_into_a_zombie_thumps() -> void:
	var wall := Vector3(0.0, 1.5, -20.0)
	var zombie := Vector3(5.0, 1.0, 0.0)
	_tell(_shot(&"rifle", [wall, zombie]))
	_tell(_hit(zombie + Vector3(0.1, 0.0, 0.0)))
	_sounds.schedule.advance(0.0)
	var world := _heard.filter(func(h: Dictionary) -> bool: return h["id"] == &"impact_world")
	assert_array(world).has_size(1)
	assert_vector(world[0]["at"]).is_equal(wall)
	assert_array(_ids()).contains([&"impact_flesh"])


func test_a_headshot_cracks_and_a_shot_into_the_sky_makes_no_impact() -> void:
	var sky := MUZZLE + Vector3(0.0, 0.0, -500.0)
	_tell(_shot(&"rifle", [sky]))
	_tell(_hit(Vector3(4, 1.7, 0), true))
	_sounds.schedule.advance(0.0)
	assert_array(_ids()).contains([&"impact_head"])
	assert_array(_ids()).not_contains([&"impact_world"])


func test_a_shotgun_blast_into_a_wall_ricochets_at_most_a_few_times() -> void:
	var ends: Array[Vector3] = []
	for i in 8:
		ends.append(Vector3(-2.0 + i * 0.5, 1.0, -15.0))
	_tell(_shot(&"shotgun", ends))
	_sounds.schedule.advance(0.0)
	var world := _heard.filter(func(h: Dictionary) -> bool: return h["id"] == &"impact_world")
	assert_int(world.size()).is_equal(WeaponSounds.MAX_WORLD_IMPACTS)


func test_a_melee_blow_is_not_an_impact_of_ours() -> void:
	_tell(_hit(Vector3(1, 1, 1), false, true))
	assert_array(_heard).is_empty()


func test_every_sound_these_tables_name_exists_with_its_files() -> void:
	var names: Array[StringName] = []
	for weapon: StringName in WeaponSounds.FIRE:
		names.append_array(WeaponSounds.FIRE[weapon].values())
	for weapon: StringName in WeaponSounds.RELOAD:
		names.append_array(WeaponSounds.RELOAD[weapon]["steps"].values())
	names.append_array(
		[
			&"dry_fire",
			&"weapon_swap",
			&"burst_flare",
			&"impact_flesh",
			&"impact_head",
			&"impact_world"
		]
	)
	for id in names:
		var def := SoundCatalog.get_def(id)
		assert_object(def).override_failure_message(String(id)).is_not_null()
		for variant in range(1, def.variants + 1):
			(
				assert_bool(ResourceLoader.exists(def.path_for(variant)))
				. override_failure_message(def.path_for(variant))
				. is_true()
			)
