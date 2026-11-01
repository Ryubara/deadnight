extends GdUnitTestSuite
## The lot's machines and shop from the server's events: the generator's hum follows its load,
## coughs when the tank is low, winds down when it is dry and roars back on a refuel; the breakers
## clunk; every purchase has its sound and a refusal buzzes; points tick; a tense bed lives under
## each round. The clock is stepped by hand.

const OWN := 1

var _heard: Array[Dictionary] = []
var _sounds: WorldSounds
var _state: ClientState
var _tuning: RulesTuning
var _generator: Node3D


func before_test() -> void:
	_heard = []
	_tuning = load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning
	_state = ClientState.new()
	_state.player_id = OWN
	_generator = auto_free(Node3D.new())
	add_child(_generator)
	_generator.global_position = Vector3(30, 0, 5)
	_sounds = auto_free(WorldSounds.new())
	_sounds.play = func(id: StringName, at: Variant, db: float) -> void:
		_heard.append({"id": id, "at": at, "db": db})
	add_child(_sounds)
	_sounds.setup(
		_state,
		_tuning.fuel,
		_tuning.economy,
		_generator,
		func(circuit: StringName) -> Variant:
			return Vector3(7, 0, 7) if circuit == &"booth" else null,
		func(spot: int) -> Variant: return Vector3(20 + spot * 10, 0, 0) if spot < 2 else null,
		3
	)
	_state.apply_events(
		[{"type": &"frame", "players": {OWN: {"pos": Vector3(1, 0, 2)}}, "zombies": []}]
	)


func after_test() -> void:
	Audio.stop_all()


func _tell(event: Dictionary) -> void:
	_state.apply_events([event])


func _ids() -> Array:
	return _heard.map(func(h: Dictionary) -> StringName: return h["id"])


func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		_sounds.advance(minf(left, 0.1))
		Audio.advance(minf(left, 0.1))
		left -= 0.1


func _fuel(amount: float) -> void:
	_tell({"type": &"fuel_changed", "fuel": amount, "delta": -1.0})


func test_the_hum_runs_from_the_generator_and_louder_with_more_circuits_on() -> void:
	assert_object(_sounds.hum_player()).is_not_null()
	assert_object(_sounds.engine_player()).is_not_null()
	assert_object(_sounds.hum_player().get_parent()).is_same(_generator)
	_run(1.0)
	var quiet := _sounds.hum_player().volume_db
	var slow := _sounds.hum_player().pitch_scale
	for circuit in _tuning.fuel.circuit_drain:
		_tell({"type": &"circuit_changed", "circuit_id": circuit, "on": true})
	_run(2.0)
	assert_float(_sounds.hum_player().volume_db).is_greater(quiet + 3.0)
	assert_float(_sounds.hum_player().pitch_scale).is_greater(slow)
	for circuit in _tuning.fuel.circuit_drain:
		_tell({"type": &"circuit_changed", "circuit_id": circuit, "on": false})
	_run(3.0)
	assert_float(_sounds.hum_player().volume_db).is_less(quiet)


func test_a_low_tank_sputters_and_it_coughs_more_as_it_dries() -> void:
	_run(10.0)
	(
		assert_array(_ids().filter(func(id: StringName) -> bool: return id == &"generator_sputter"))
		. is_empty()
	)
	var low := _tuning.fuel.capacity * _tuning.fuel.low_fraction
	_fuel(low * 0.9)
	_tell({"type": &"fuel_low"})
	_run(0.2)
	assert_array(_ids()).contains([&"generator_sputter"])
	var near := _count(&"generator_sputter")
	_run(20.0)
	var gaps_near := _count(&"generator_sputter") - near
	_fuel(low * 0.1)
	_heard.clear()
	_run(20.0)
	assert_int(_count(&"generator_sputter")).is_greater(gaps_near)


func test_a_dry_tank_powers_down_and_silences_the_hum_and_a_refuel_brings_it_back() -> void:
	_tell({"type": &"fuel_empty"})
	assert_array(_ids()).is_equal([&"generator_down", &"generator_down_air"])
	_run(4.0)
	assert_bool(_sounds.hum_player().playing).is_false()
	assert_bool(_sounds.engine_player().playing).is_false()
	_heard.clear()
	_fuel(20.0)
	_tell({"type": &"fuel_restored"})
	assert_array(_ids()).is_equal([&"generator_start", &"generator_up"])
	_run(4.0)
	assert_bool(_sounds.hum_player().playing).is_true()
	# Dry, it does not sputter either.
	_heard.clear()
	_tell({"type": &"fuel_empty"})
	_heard.clear()
	_run(10.0)
	assert_int(_count(&"generator_sputter")).is_equal(0)


func test_a_breaker_clunks_at_its_post_and_differently_on_and_off() -> void:
	_tell({"type": &"circuit_changed", "circuit_id": &"booth", "on": true})
	_tell({"type": &"circuit_changed", "circuit_id": &"booth", "on": false})
	assert_array(_ids()).is_equal([&"breaker_on", &"breaker_off"])
	assert_vector(_heard[0]["at"]).is_equal(Vector3(7, 0, 7))
	# A circuit with no post is heard at the generator.
	_tell({"type": &"circuit_changed", "circuit_id": &"concession", "on": true})
	assert_vector(_heard[2]["at"]).is_equal(_generator.global_position)


func test_each_kind_of_purchase_has_its_sound() -> void:
	var expected := {
		ShopItem.Kind.WEAPON: [&"buy_weapon"],
		ShopItem.Kind.AMMO: [&"buy_ammo"],
		ShopItem.Kind.FUEL: [&"buy_fuel"],
		ShopItem.Kind.TONIC: [&"buy_tonic"],
		ShopItem.Kind.DOOR: [&"door_unlock", &"door_buy"],
	}
	for kind: ShopItem.Kind in expected:
		var item: ShopItem
		for candidate in _tuning.economy.items:
			if candidate.kind == kind:
				item = candidate
				break
		assert_object(item).override_failure_message("no item of kind %d" % kind).is_not_null()
		_heard.clear()
		_tell(
			{
				"type": &"purchase_made",
				"player_id": OWN,
				"item_id": item.id,
				"price": 1,
				"detail": {}
			}
		)
		_run(1.0)
		assert_array(_ids()).override_failure_message(String(item.id)).is_equal(expected[kind])
		assert_vector(_heard[0]["at"]).is_equal(Vector3(1.0, 1.6, 2.0))


func test_the_crane_plays_its_moments_where_it_stands() -> void:
	_tell({"type": &"crane_spin_started", "player_id": OWN, "spot": 1, "seconds": 4.5, "plays": 1})
	assert_array(_ids()).is_equal([&"crane_claw_drop", &"crane_spin"])
	assert_vector(_heard[0]["at"]).is_equal(Vector3(30.0, 1.0, 0.0))
	_heard.clear()
	_tell(
		{
			"type": &"crane_prize_ready",
			"player_id": OWN,
			"spot": 1,
			"weapon": &"weapon_rifle",
			"seconds": 8.0
		}
	)
	assert_array(_ids()).is_equal([&"crane_claw_lift"])
	_run(WorldSounds.PRIZE_DING_DELAY + 0.1)
	assert_array(_ids()).is_equal([&"crane_claw_lift", &"crane_prize"])
	_heard.clear()
	_tell({"type": &"crane_prize_taken", "player_id": OWN, "spot": 1, "weapon": &"weapon_rifle"})
	assert_array(_ids()).is_equal([&"buy_weapon"])
	_heard.clear()
	_tell({"type": &"crane_breakdown", "player_id": OWN, "spot": 0, "refund": 950, "seconds": 3.0})
	_tell({"type": &"crane_moved", "from_spot": 0, "to_spot": 1})
	assert_array(_ids()).is_equal([&"crane_break", &"crane_move"])
	assert_vector(_heard[1]["at"]).is_equal(Vector3(20.0, 1.0, 0.0))


func test_a_crane_the_lot_cannot_place_is_heard_at_its_buyer_and_a_refused_take_buzzes() -> void:
	_tell({"type": &"crane_spin_started", "player_id": OWN, "spot": 9, "seconds": 4.5, "plays": 1})
	assert_vector(_heard[0]["at"]).is_equal(Vector3(1.0, 1.6, 2.0))
	_heard.clear()
	_tell({"type": &"crane_moved", "from_spot": 9, "to_spot": 1})
	assert_array(_heard).is_empty()
	_tell({"type": &"crane_take_denied", "player_id": OWN, "reason": &"not_buyer"})
	assert_array(_ids()).is_equal([&"deny"])


func test_a_refusal_buzzes_for_the_one_refused_only() -> void:
	_tell(
		{"type": &"purchase_denied", "player_id": OWN, "item_id": &"door_concession", "result": 4}
	)
	assert_array(_ids()).is_equal([&"deny"])
	assert_object(_heard[0]["at"]).is_null()
	_heard.clear()
	_tell({"type": &"purchase_denied", "player_id": 2, "item_id": &"door_concession", "result": 4})
	assert_array(_heard).is_empty()


func test_points_tick_for_a_hit_ring_for_a_kill_and_stay_quiet_for_spending() -> void:
	_tell({"type": &"points_changed", "player_id": OWN, "total": 14, "delta": 4, "reason": &"hit"})
	_tell(
		{"type": &"points_changed", "player_id": OWN, "total": 74, "delta": 60, "reason": &"kill"}
	)
	_tell(
		{
			"type": &"points_changed",
			"player_id": OWN,
			"total": 24,
			"delta": -50,
			"reason": &"purchase"
		}
	)
	_tell({"type": &"points_changed", "player_id": 2, "total": 4, "delta": 4, "reason": &"hit"})
	_tell(
		{"type": &"points_changed", "player_id": OWN, "total": 0, "delta": 500, "reason": &"start"}
	)
	assert_array(_ids()).is_equal([&"points_tick", &"points_kill"])


func test_the_tense_bed_fades_in_after_the_sting_and_out_when_the_round_ends() -> void:
	assert_float(Audio.bed_fade_db(WorldSounds.BED)).is_equal(AudioService.BED_SILENT_DB)
	_tell(
		{
			"type": &"round_started",
			"round": 1,
			"zombie_count": 6,
			"special_id": &"",
			"boss_count": 0
		}
	)
	_run(WorldSounds.BED_DELAY - 0.3)
	assert_float(Audio.bed_fade_db(WorldSounds.BED)).is_equal(AudioService.BED_SILENT_DB)
	_run(0.5)
	_run(6.0)
	assert_float(Audio.bed_fade_db(WorldSounds.BED)).is_equal(0.0)
	_tell({"type": &"round_ended", "round": 1, "special_id": &""})
	_run(4.0)
	assert_float(Audio.bed_fade_db(WorldSounds.BED)).is_equal(AudioService.BED_SILENT_DB)


func _count(id: StringName) -> int:
	return _ids().filter(func(x: StringName) -> bool: return x == id).size()
