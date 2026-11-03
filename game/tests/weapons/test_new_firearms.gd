extends GdUnitTestSuite
## The six firearms of #793 (the PPSh, MP5, M4A1, M249, .50 calibre rifle and 870 pump): their
## numbers are #785's table (docs/design/weapons.md, "The nine new weapons"), the .50's shot goes
## through a line of the dead, the M249 shoots wider on the move, and the pump loads a round at a
## time and gives way to a shot (docs/design/weapons.md, "The six firearms").

const IDS: Array[StringName] = [&"ppsh", &"mp5", &"m4a1", &"m249", &"fifty_cal", &"pump_870"]
## id: [per hit, pellets, interval, magazine, reserve, reserve max, reload, spread, head, pierces]
const TABLE := {
	&"mp5": [15.0, 1, 0.10, 30, 120, 180, 1.9, 1.4, 2.0, 0],
	&"ppsh": [10.0, 1, 0.055, 50, 100, 200, 2.8, 3.2, 1.5, 0],
	&"m4a1": [20.0, 1, 0.11, 30, 90, 150, 2.1, 1.0, 1.75, 0],
	&"m249": [15.0, 1, 0.09, 100, 150, 250, 5.0, 2.6, 1.75, 1],
	&"fifty_cal": [220.0, 1, 0.9, 5, 20, 40, 3.4, 0.15, 2.0, 4],
	&"pump_870": [22.0, 6, 0.65, 6, 42, 66, 2.8, 5.0, 1.5, 0],
}
## id: its range and the falloff's start, end and floor.
const REACH := {
	&"mp5": [55.0, 12.0, 34.0, 0.55],
	&"ppsh": [40.0, 8.0, 24.0, 0.45],
	&"m4a1": [90.0, 22.0, 55.0, 0.65],
	&"m249": [70.0, 14.0, 40.0, 0.55],
	&"fifty_cal": [150.0, 150.0, 151.0, 1.0],
	&"pump_870": [35.0, 10.0, 26.0, 0.45],
}

var _server: CombatServer


func before_test() -> void:
	_server = WeaponsFixture.make_server()


func _wait(seconds: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _i in int(ceil(seconds / WeaponsFixture.STEP)):
		events.append_array(_server.apply(CombatAction.tick(WeaponsFixture.STEP)))
	return events


func _pump_pull(seq: int) -> Array[Dictionary]:
	return _server.apply(WeaponsFixture.fire_at(1, seq, WeaponsFixture.SHOOTER, Vector3(0, 1.1, 0)))


# --- The definitions ---


func test_the_six_are_in_the_catalogue_with_their_numbers() -> void:
	for id in IDS:
		assert_bool(id in WeaponCatalog.IDS).override_failure_message(String(id)).is_true()
		var def := WeaponCatalog.get_def(id)
		var row: Array = TABLE[id]
		var tag := String(id)
		assert_str(String(def.id)).is_equal(tag)
		assert_bool(def.is_hitscan()).override_failure_message(tag).is_true()
		assert_float(def.damage).override_failure_message(tag + " damage").is_equal(row[0])
		assert_int(def.pellets).override_failure_message(tag + " pellets").is_equal(row[1])
		assert_float(def.fire_interval).override_failure_message(tag + " interval").is_equal(row[2])
		assert_int(def.magazine_size).override_failure_message(tag + " magazine").is_equal(row[3])
		assert_int(def.reserve_start).override_failure_message(tag + " reserve").is_equal(row[4])
		assert_int(def.reserve_max).override_failure_message(tag + " reserve max").is_equal(row[5])
		assert_float(def.reload_time).override_failure_message(tag + " reload").is_equal(row[6])
		assert_float(def.spread_deg).override_failure_message(tag + " spread").is_equal(row[7])
		(
			assert_float(def.zone_multiplier(Hitbox.HEAD))
			. override_failure_message(tag + " head")
			. is_equal(row[8])
		)
		assert_int(def.penetration).override_failure_message(tag + " pierces").is_equal(row[9])
		var reach: Array = REACH[id]
		assert_float(def.max_range).override_failure_message(tag + " range").is_equal(reach[0])
		assert_float(def.falloff_start).is_equal(reach[1])
		assert_float(def.falloff_end).is_equal(reach[2])
		assert_float(def.min_damage_fraction).is_equal(reach[3])
		assert_bool(def.automatic).override_failure_message(tag + " automatic").is_equal(
			id in [&"mp5", &"ppsh", &"m4a1", &"m249"]
		)


func test_only_the_pump_loads_by_the_round_and_only_the_saw_widens_on_the_move() -> void:
	for id in IDS:
		var def := WeaponCatalog.get_def(id)
		assert_bool(def.reload_by_round).override_failure_message(String(id)).is_equal(
			id == &"pump_870"
		)
		assert_bool(def.moving_spread_deg > 0.0).override_failure_message(String(id)).is_equal(
			id == &"m249"
		)


func test_each_can_be_re_cut_once_by_the_shop_rule() -> void:
	var spec := UpgradeTuning.shipped()
	for id in IDS:
		assert_bool(spec.allows(id)).override_failure_message(String(id)).is_true()
		var def := WeaponCatalog.get_def(id)
		var cut := def.upgraded(spec)
		assert_float(cut.damage).is_equal_approx(def.damage * 1.75, 0.001)
		assert_int(cut.magazine_size).is_equal(ceili(def.magazine_size * 1.5))
		assert_int(cut.reserve_max).is_equal(ceili(def.reserve_max * 1.5))
		assert_str(cut.display_name).is_equal("Re-Cut " + def.display_name)
		# What is not a number of the cut stays: the pump still loads by the round.
		assert_bool(cut.reload_by_round).is_equal(def.reload_by_round)


func test_no_wall_sells_the_six_and_the_box_draws_all_of_them() -> void:
	# The maintainer's rule (#858): a wall sells only the weaker guns; these come from the box.
	var economy := RulesFixture.tuning().economy
	for id in IDS:
		assert_object(economy.item(StringName("weapon_" + String(id)))).is_null()
	var pool := economy.item(&"crane_play").pool
	for id in IDS:
		assert_array(pool).override_failure_message(String(id)).contains(
			[StringName("weapon_" + String(id))]
		)
		assert_object(economy.ammo_item_for(id)).override_failure_message(String(id)).is_not_null()


# --- The .50 calibre and the M249: a shot through the line ---


func test_the_fifty_goes_through_four_and_stops_in_the_fifth() -> void:
	var def := WeaponCatalog.get_def(&"fifty_cal")
	var targets := WeaponsFixture.targets_of(
		{
			1: Vector3(0, 0, 0),
			2: Vector3(0, 0, -1.5),
			3: Vector3(0, 0, -3),
			4: Vector3(0, 0, -4.5),
			5: Vector3(0, 0, -6),
			6: Vector3(0, 0, -7.5)
		}
	)
	var from := Vector3(0, 1.1, 8)
	var pellet := AimResolver.trace_one(def, from, Vector3(0, 0, -1), from, targets, Callable())
	var hits: Array = pellet["hits"]
	assert_int(hits.size()).is_equal(5)
	for i in range(1, hits.size()):
		assert_float(hits[i]["damage"]).is_equal_approx(
			hits[i - 1]["damage"] * def.penetration_falloff, 0.01
		)
	# The last of five still hurts: 220 x 0.7^4 = 52.8 on the body.
	assert_float(hits[4]["damage"]).is_greater(50.0)


func test_one_fifty_shot_hurts_every_zombie_of_the_line_at_the_rules() -> void:
	_server.apply(CombatAction.give_weapon(1, &"fifty_cal"))
	var line := {
		1: Vector3(0, 0, 0), 2: Vector3(0, 0, -1.5), 3: Vector3(0, 0, -3), 4: Vector3(0, 0, -4.5)
	}
	WeaponsFixture.step(_server, line, 2)
	var events := _server.apply(
		WeaponsFixture.fire_at(1, 1, WeaponsFixture.SHOOTER, Vector3(0, 1.1, 0), _server.now)
	)
	var hurt := WeaponsFixture.of(events, &"damage_dealt")
	assert_int(hurt.size()).is_greater_equal(2)
	var shot := WeaponsFixture.of(events, &"shot_fired")[0]
	assert_int(shot["ammo"]).is_equal(4)


func test_the_saw_goes_through_one_and_stops_in_the_second() -> void:
	var def := WeaponCatalog.get_def(&"m249")
	var targets := WeaponsFixture.targets_of(
		{1: Vector3(0, 0, 0), 2: Vector3(0, 0, -1.5), 3: Vector3(0, 0, -3)}
	)
	var from := Vector3(0, 1.1, 6)
	var pellet := AimResolver.trace_one(def, from, Vector3(0, 0, -1), from, targets, Callable())
	assert_int(pellet["hits"].size()).is_equal(2)


# --- The M249: wider on the move ---


func _widest(def: WeaponDef, move: float) -> float:
	var widest := 0.0
	for seed_value in 400:
		for dir in AimResolver.spread_dirs(def, Vector3(0, 0, -1), seed_value, move):
			widest = maxf(widest, rad_to_deg(dir.angle_to(Vector3(0, 0, -1))))
	return widest


func test_the_saw_shoots_wider_on_the_move_and_the_others_do_not() -> void:
	var saw := WeaponCatalog.get_def(&"m249")
	assert_float(saw.spread_at(0.0)).is_equal(saw.spread_deg)
	assert_float(saw.spread_at(1.0)).is_equal(saw.spread_deg + saw.moving_spread_deg)
	assert_float(saw.spread_at(0.5)).is_equal_approx(
		saw.spread_deg + saw.moving_spread_deg / 2, 0.001
	)
	# Standing: inside the cone; running: inside the wider cone and past the standing one.
	assert_float(_widest(saw, 0.0)).is_less_equal(saw.spread_deg + 0.01)
	assert_float(_widest(saw, 1.0)).is_less_equal(saw.spread_at(1.0) + 0.01)
	assert_float(_widest(saw, 1.0)).is_greater(saw.spread_deg * 1.4)
	var mp5 := WeaponCatalog.get_def(&"mp5")
	assert_float(mp5.spread_at(1.0)).is_equal(mp5.spread_deg)


func test_the_running_shooter_scatters_the_same_way_on_a_second_server() -> void:
	var other := WeaponsFixture.make_server()
	var from := Vector3(0, 1.1, 12)
	var shots: Array = []
	for server in [_server, other]:
		server.apply(CombatAction.give_weapon(1, &"m249"))
		WeaponsFixture.step(server, {1: Vector3.ZERO}, 2)
		var fire := CombatAction.fire(1, 5, from, Vector3(0, 0, -1), from, server.now, 1.0)
		shots.append(WeaponsFixture.of(server.apply(fire), &"shot_fired")[0]["ends"])
	assert_array(shots[0]).is_equal(shots[1])
	# And it is not the standing shot: the same number standing ends somewhere else.
	var standing := CombatAction.fire(1, 5, from, Vector3(0, 0, -1), from, other.now + 1.0, 0.0)
	_wait(0.2)
	var still := WeaponsFixture.of(_server.apply(standing), &"shot_fired")
	if not still.is_empty():
		assert_array(still[0]["ends"]).is_not_equal(shots[0])


func test_the_move_share_is_part_of_a_fire_action_only_when_there_is_one() -> void:
	var from := Vector3.ZERO
	assert_bool(CombatAction.fire(1, 1, from, Vector3.FORWARD, from, 0.0).has("move")).is_false()
	assert_float(CombatAction.fire(1, 1, from, Vector3.FORWARD, from, 0.0, 0.6)["move"]).is_equal(
		0.6
	)


# --- The pump: a round at a time, a shot ends it ---


func _empty_pump() -> WeaponState:
	_server.apply(CombatAction.give_weapon(1, &"pump_870"))
	var state := _server.state_of(1, &"pump_870")
	state.ammo = 0
	return state


func test_the_pump_loads_one_round_each_round_time_and_says_so() -> void:
	var def := WeaponCatalog.get_def(&"pump_870")
	var state := _empty_pump()
	var started := WeaponsFixture.of(
		_server.apply(CombatAction.reload_weapon(1)), &"reload_started"
	)
	assert_array(started).has_size(1)
	assert_int(started[0]["rounds"]).is_equal(def.magazine_size)
	assert_float(started[0]["seconds"]).is_equal_approx(def.reload_time, 0.001)
	var loaded := 0
	var steps_to_first := -1
	var events: Array[Dictionary] = []
	for i in int(ceil((def.reload_time + 0.2) / WeaponsFixture.STEP)):
		var caused := _server.apply(CombatAction.tick(WeaponsFixture.STEP))
		events.append_array(caused)
		var rounds := WeaponsFixture.of(caused, &"reload_round")
		loaded += rounds.size()
		if steps_to_first < 0 and state.ammo == 1:
			steps_to_first = i + 1
		# The magazine never jumps by more than one round a tick.
		assert_int(state.ammo).is_less_equal(loaded + 1)
	assert_int(state.ammo).is_equal(def.magazine_size)
	assert_int(state.reserve).is_equal(def.reserve_start - def.magazine_size)
	# One round each `reload_time / magazine_size`, the last one finishing the reload.
	assert_int(loaded).is_equal(def.magazine_size - 1)
	assert_array(WeaponsFixture.of(events, &"reload_finished")).has_size(1)
	assert_float(float(steps_to_first) * WeaponsFixture.STEP).is_equal_approx(
		def.round_seconds(), 0.04
	)


func test_a_pump_missing_two_rounds_loads_two_in_two_round_times() -> void:
	var def := WeaponCatalog.get_def(&"pump_870")
	var state := _empty_pump()
	state.ammo = def.magazine_size - 2
	var started := WeaponsFixture.of(
		_server.apply(CombatAction.reload_weapon(1)), &"reload_started"
	)
	assert_int(started[0]["rounds"]).is_equal(2)
	assert_float(started[0]["seconds"]).is_equal_approx(2.0 * def.round_seconds(), 0.001)
	_wait(2.0 * def.round_seconds() + 0.1)
	assert_int(state.ammo).is_equal(def.magazine_size)
	assert_bool(state.is_reloading()).is_false()


func test_a_shot_ends_the_pump_reload_and_keeps_the_rounds_loaded() -> void:
	var def := WeaponCatalog.get_def(&"pump_870")
	var state := _empty_pump()
	_server.apply(CombatAction.reload_weapon(1))
	# Nothing loaded yet: a shot is refused (the weapon is empty and reloading).
	var early := _pump_pull(1)
	assert_str(WeaponsFixture.of(early, &"fire_rejected")[0]["reason"]).is_equal("reloading")
	_wait(def.round_seconds() * 2.5)
	assert_int(state.ammo).is_equal(2)
	assert_bool(state.is_reloading()).is_true()
	var reserve := state.reserve
	var events := _pump_pull(2)
	assert_array(WeaponsFixture.of(events, &"shot_fired")).has_size(1)
	var stopped := WeaponsFixture.of(events, &"reload_interrupted")
	assert_array(stopped).has_size(1)
	assert_int(stopped[0]["ammo"]).is_equal(1)
	assert_bool(state.is_reloading()).is_false()
	assert_int(state.ammo).is_equal(1)
	assert_int(state.reserve).is_equal(reserve)
	# No round is loaded afterwards: the reload is over.
	var later := _wait(def.round_seconds() * 3.0)
	assert_array(WeaponsFixture.of(later, &"reload_round")).is_empty()
	assert_int(state.ammo).is_equal(1)


func test_a_magazine_gun_still_cannot_fire_while_it_reloads() -> void:
	_server.apply(CombatAction.give_weapon(1, &"mp5"))
	var state := _server.state_of(1, &"mp5")
	state.ammo = 10
	_server.apply(CombatAction.reload_weapon(1))
	var events := _server.apply(
		WeaponsFixture.fire_at(1, 1, WeaponsFixture.SHOOTER, Vector3(0, 1.1, 0))
	)
	assert_str(WeaponsFixture.of(events, &"fire_rejected")[0]["reason"]).is_equal("reloading")
	assert_bool(state.is_reloading()).is_true()


func test_the_reload_perk_quickens_each_round_of_the_pump() -> void:
	var def := WeaponCatalog.get_def(&"pump_870")
	var state := WeaponState.new(def)
	state.ammo = 0
	state.start_reload(0.5)
	assert_float(state.reload_left).is_equal_approx(def.reload_time * 0.5, 0.001)
	assert_float(state.round_time).is_equal_approx(def.round_seconds() * 0.5, 0.001)


func test_a_swap_abandons_the_pump_reload() -> void:
	var state := _empty_pump()
	_server.apply(CombatAction.give_weapon(1, &"pistol"))
	_server.apply(CombatAction.equip(1, &"pump_870"))
	_server.apply(CombatAction.reload_weapon(1))
	assert_bool(state.is_reloading()).is_true()
	_server.apply(CombatAction.equip(1, &"pistol"))
	assert_bool(state.is_reloading()).is_false()


# --- The sounds, and the bench's models, wait until they are needed ---


func test_the_guns_sounds_are_in_a_deferred_bank() -> void:
	# `test_load_cost.gd` caps what the night decodes behind the loading bar: the six guns' sounds
	# wait in the line (`firearms_2` is a deferred bank).
	for id in IDS:
		for sound in WeaponSounds.FIRE[id].values():
			(
				assert_bool(SoundCatalog.get_def(sound).deferred)
				. override_failure_message(String(sound))
				. is_true()
			)
		for sound in WeaponSounds.RELOAD[id].values():
			if sound != &"reload_pouch":
				(
					assert_bool(SoundCatalog.get_def(sound).deferred)
					. override_failure_message(String(sound))
					. is_true()
				)


func test_each_gun_is_carried_through_its_own_sprint_clip() -> void:
	var file := FileAccess.get_file_as_string("res://assets/characters/soldier/sprint/clips.json")
	for id in IDS:
		var clip := StringName(SprintCarry.PREFIX + String(id))
		assert_array(SprintCarry.CLIPS).override_failure_message(String(clip)).contains([clip])
		assert_bool(file.contains(String(clip))).override_failure_message(String(clip)).is_true()
	# A gun held as another's model (until its own lands) is carried as that model is.
	var hold := WeaponHoldMap.hold_for(&"mp5")
	var own := StringName(SprintCarry.PREFIX + hold.scene.get_file().get_basename())
	assert_array(SprintCarry.CLIPS).contains([own])
