extends GdUnitTestSuite
## The prize crane as the player sees it (`CraneView`, `PrizeCrane`): it stands at the spot the
## rules name, shows the weapons cycling during the spin and the chosen one in the grab window,
## the dud on a breakdown, and moves to the next spot when the rules do. Driven by hand ticks.

const SPIN_TICKS := 300
const GRAB_TICKS := 750


func _start(breaks: bool = false) -> Night:
	var tuning := RulesFixture.tuning()
	if breaks:
		tuning.crane.safe_plays = 0
		tuning.crane.leave_chances = PackedFloat32Array([1.0])
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.grant_points(1, 5000))
	night.server.rules.doors_open.assign([&"door_concession", &"door_yard"])
	NightFixture.run(night, 3)
	return night


func _marker(night: Night, index: int) -> Dictionary:
	for spot in night.world.shop_spots():
		if spot["kind"] == &"crane" and spot["crane_spot"] == index:
			return spot
	return {}


func test_the_crane_stands_set_back_from_the_marker_of_its_spot_with_its_beam_on() -> void:
	var night := await _start()
	var prop := night.view.crane.crane
	assert_bool(prop.visible).is_true()
	var marker := _marker(night, 0)
	var apart := Vector2(
		prop.global_position.x - marker["position"].x, prop.global_position.z - marker["position"].z
	)
	assert_float(apart.length()).is_equal_approx(CraneView.SET_BACK, 0.01)
	assert_bool(prop.beam_visible()).is_true()
	night.queue_free()


func test_the_weapons_cycle_while_it_spins_and_the_chosen_one_floats() -> void:
	var night := await _start()
	night.server.buy(1, &"crane_play")
	var seen: Dictionary = {}
	for _i in SPIN_TICKS - 20:
		NightFixture.run(night, 1)
		seen[night.view.crane.crane.shown_weapon()] = true
	assert_int(seen.size()).is_greater(2)
	NightFixture.run(night, 40)
	var prize: StringName = night.server.rules.crane.weapon
	assert_str(prize).is_not_empty()
	assert_str(night.view.crane.crane.shown_weapon()).is_equal(prize)
	assert_bool(night.view.crane.crane.dud_visible()).is_false()
	night.queue_free()


func test_the_cycling_slows_down() -> void:
	var night := await _start()
	night.server.buy(1, &"crane_play")
	var changes: Array[int] = []
	var last := &"?"
	for tick in SPIN_TICKS - 40:
		NightFixture.run(night, 1)
		var shown := night.view.crane.crane.shown_weapon()
		if shown != last:
			changes.append(tick)
			last = shown
	assert_int(changes.size()).is_greater(8)
	var early := changes[2] - changes[1]
	var late := changes[changes.size() - 1] - changes[changes.size() - 2]
	assert_int(late).is_greater(early)
	night.queue_free()


func test_a_breakdown_shows_the_dud_then_the_crane_moves_to_its_next_spot() -> void:
	var night := await _start(true)
	night.server.buy(1, &"crane_play")
	NightFixture.run(night, SPIN_TICKS + 30)
	var prop := night.view.crane.crane
	assert_bool(prop.dud_visible()).is_true()
	assert_str(prop.shown_weapon()).is_empty()
	NightFixture.run(night, 300)
	var spot: int = night.server.rules.crane.spot
	assert_int(spot).is_not_equal(0)
	NightFixture.run(night, 90)
	var marker := _marker(night, spot)
	var apart := Vector2(
		prop.global_position.x - marker["position"].x, prop.global_position.z - marker["position"].z
	)
	assert_float(apart.length()).is_equal_approx(CraneView.SET_BACK, 0.05)
	assert_bool(prop.dud_visible()).is_false()
	night.queue_free()


func test_every_prize_the_crane_can_give_has_a_model_of_its_own() -> void:
	var item := RulesFixture.tuning().economy.item(&"crane_play")
	assert_array(item.pool).is_not_empty()
	for prize: StringName in item.pool:
		assert_bool(PrizeCrane.MODELS.has(prize)).is_true()
		assert_bool(load(PrizeCrane.MODELS[prize]) is PackedScene).is_true()
