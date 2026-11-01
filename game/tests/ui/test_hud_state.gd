# The HUD's mirror of the night: a scripted feed of real rules events moves every value, a snapshot
# restores a late joiner, events for other players leave the local readings alone.
extends GdUnitTestSuite

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func test_the_round_and_zombie_count_follow_the_rules() -> void:
	var fixture := HudFixture.make(_host)
	var state := fixture.hud.state
	assert_int(state.round_number).is_equal(0)
	fixture.into_round_one()
	assert_int(state.round_number).is_equal(1)
	assert_int(state.phase).is_equal(HudState.PHASE_ACTIVE)
	assert_int(state.zombies_total).is_equal(fixture.rules.zombies_remaining())
	var ids := fixture.spawn(2)
	fixture.act(RulesAction.hit(1, ids[0], RulesAction.ZONE_BODY, HudFixture.KILLING))
	assert_int(state.zombies_left).is_equal(state.zombies_total - 1)


func test_points_follow_the_local_player_only() -> void:
	var fixture := HudFixture.make(_host, 2)
	var state := fixture.hud.state
	assert_int(state.points).is_equal(200)
	fixture.act(RulesAction.grant_points(2, 500))
	assert_int(state.points).is_equal(200)
	assert_int(state.team[2]["points"]).is_equal(700)
	fixture.act(RulesAction.grant_points(1, 50))
	assert_int(state.points).is_equal(250)


func test_the_break_counts_down() -> void:
	var fixture := HudFixture.make(_host)
	fixture.act(RulesAction.start())
	var state := fixture.hud.state
	assert_int(state.phase).is_equal(HudState.PHASE_BREAK)
	var before := state.break_left
	assert_float(before).is_greater(0.0)
	state.tick(2.0)
	assert_float(state.break_left).is_equal_approx(before - 2.0, 0.001)
	assert_str(fixture.hud.round_part.detail_text).starts_with("NEXT IN")


func test_fuel_flags_and_circuits_follow_the_generator() -> void:
	var fixture := HudFixture.make(_host)
	var state := fixture.hud.state
	assert_bool(state.fuel_low).is_false()
	fixture.act(RulesAction.set_circuit(&"booth", true))
	assert_bool(state.circuits[&"booth"]).is_true()
	state.apply_events(
		[{"type": &"fuel_changed", "fuel": 20.0, "delta": -5.0}, {"type": &"fuel_low"}]
	)
	assert_bool(state.fuel_low).is_true()
	assert_float(state.fuel_fraction()).is_equal_approx(0.2, 0.001)
	state.apply_event({"type": &"fuel_changed", "fuel": 0.0, "delta": -20.0})
	assert_bool(state.fuel_empty).is_true()
	assert_bool(state.fuel_low).is_false()
	state.apply_event({"type": &"fuel_changed", "fuel": 60.0, "delta": 60.0})
	assert_bool(state.fuel_empty).is_false()
	assert_bool(state.fuel_low).is_false()


func test_team_states_follow_down_and_up() -> void:
	var fixture := HudFixture.make(_host, 3)
	var state := fixture.hud.state
	fixture.into_round_one()
	fixture.act(RulesAction.set_downed(2, true))
	assert_bool(state.team[2]["downed"]).is_true()
	assert_bool(state.is_local_downed()).is_false()
	fixture.act(RulesAction.set_downed(1, true))
	assert_bool(state.is_local_downed()).is_true()
	fixture.act(RulesAction.set_downed(1, false))
	assert_bool(state.is_local_downed()).is_false()
	fixture.act(RulesAction.remove_player(3))
	assert_bool(state.team.has(3)).is_false()
	assert_str(state.left_name).is_equal("Dee")


func test_unknown_events_are_ignored() -> void:
	var fixture := HudFixture.make(_host)
	var state := fixture.hud.state
	var points := state.points
	state.apply_event({"type": &"something_new", "x": 1})
	state.apply_event({})
	assert_int(state.points).is_equal(points)


func test_a_snapshot_restores_a_late_joiner() -> void:
	var fixture := HudFixture.make(_host, 2)
	fixture.into_round_one()
	fixture.act(RulesAction.grant_points(1, 300))
	fixture.act(RulesAction.set_downed(2, true))
	fixture.act(RulesAction.set_circuit(&"concession", true))
	var late := HudState.new()
	late.load_snapshot(fixture.rules.to_dict())
	assert_int(late.round_number).is_equal(1)
	assert_int(late.points).is_equal(500)
	assert_bool(late.team[2]["downed"]).is_true()
	assert_bool(late.circuits[&"concession"]).is_true()
	assert_float(late.fuel).is_equal_approx(fixture.rules.generator.fuel, 0.001)


func test_a_name_is_kept_to_the_limit() -> void:
	var state := HudState.new()
	state.set_player_name(1, "  " + "W".repeat(HudStyle.NAME_LIMIT * 3) + "  ")
	assert_int(state.team[1]["name"].length()).is_equal(HudStyle.NAME_LIMIT)
	state.set_player_name(2, "Ruby")
	assert_str(state.team[2]["name"]).is_equal("Ruby")


## The topics each change marks, read by the part that listens, so a change wakes only its readers.
func _topics_of(state: HudState, change: Callable) -> Array[StringName]:
	var seen: Array[StringName] = []
	var listen := func() -> void:
		for topic: StringName in [
			HudState.ROUND,
			HudState.OBJECTIVE,
			HudState.TEAM,
			HudState.FUEL,
			HudState.HEALTH,
			HudState.AMMO,
			HudState.POINTS,
			HudState.PROMPT,
			HudState.MARKERS
		]:
			if state.is_dirty(topic) and not seen.has(topic):
				seen.append(topic)
	state.changed.connect(listen)
	change.call()
	state.changed.disconnect(listen)
	return seen


func test_each_change_names_the_part_of_the_state_it_touched() -> void:
	var fixture := HudFixture.make(_host, 3)
	fixture.act(RulesAction.start())
	var state := fixture.hud.state
	(
		assert_array(_topics_of(state, func() -> void: state.tick(1.5)))
		. contains_exactly([HudState.ROUND])
	)
	(
		assert_array(
			_topics_of(state, func() -> void: fixture.act(RulesAction.set_downed(2, true)))
		)
		. contains_exactly([HudState.TEAM])
	)
	(
		assert_array(_topics_of(state, func() -> void: state.set_ammo(5, 20, "Rifle")))
		. contains_exactly([HudState.AMMO])
	)
	(
		assert_array(_topics_of(state, func() -> void: state.set_health(50.0)))
		. contains_exactly([HudState.HEALTH])
	)
	# A teammate's points are on their box (the party), yours on yours.
	(
		assert_array(
			_topics_of(state, func() -> void: fixture.act(RulesAction.grant_points(2, 10)))
		)
		. contains_exactly([HudState.TEAM])
	)
	(
		assert_array(
			_topics_of(state, func() -> void: fixture.act(RulesAction.grant_points(1, 10)))
		)
		. contains_exactly([HudState.POINTS])
	)
	(
		assert_array(_topics_of(state, func() -> void: state.set_prompt(&"repair", "Boards", 0)))
		. contains_exactly([HudState.PROMPT])
	)


func test_a_held_state_announces_once_and_only_what_changed() -> void:
	var state := HudState.new()
	var changes := [0]
	state.changed.connect(func() -> void: changes[0] += 1)
	state.hold()
	state.hold()
	state.set_ammo(3, 9, "Pistol")
	state.set_health(10.0)
	state.release()
	assert_int(changes[0]).is_equal(0)
	state.release()
	assert_int(changes[0]).is_equal(1)
	# A reading that did not change announces nothing at all.
	state.set_ammo(3, 9, "Pistol")
	assert_int(changes[0]).is_equal(1)


func test_the_hud_state_is_plain_data_only() -> void:
	# Network-first: the state holds numbers, strings and plain containers, never a node or the rules.
	var state := HudFixture.make(_host).hud.state
	for property in state.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = state.get(property["name"])
			assert_bool(value is Object).is_false()
