# The HUD's health and damage arcs come from the rules' own events (#132): a real `GameRules`
# night is blown on, mended and revived, and the HUD follows without any HUD-only event.
extends GdUnitTestSuite

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func _round(players := 1) -> HudFixture:
	var fixture := HudFixture.make(_host, players)
	fixture.into_round_one()
	return fixture


func test_health_starts_full_from_the_player_added_event() -> void:
	var fixture := HudFixture.make(_host)
	var state := fixture.hud.state
	assert_float(state.max_health).is_equal(fixture.rules.max_health_of(1))
	assert_float(state.health).is_equal(fixture.rules.health_of(1))


func test_a_blow_in_the_rules_lowers_health_and_swings_an_arc() -> void:
	var fixture := _round()
	var state := fixture.hud.state
	var events := fixture.act(RulesAction.blow(1, 35.0, 1.0, 4))
	assert_str(events[0]["type"]).is_equal(HudState.PLAYER_HURT)
	assert_float(state.health).is_equal(65.0)
	assert_int(fixture.hud.damage.arcs.size()).is_equal(1)
	assert_float(fixture.hud.damage.arcs[0]["angle"]).is_equal_approx(1.0, 0.001)
	assert_float(fixture.hud.health.fraction()).is_equal_approx(0.65, 0.001)


func test_the_arc_turns_with_where_the_player_faces() -> void:
	var fixture := _round()
	fixture.hud.state.facing = 0.5
	fixture.act(RulesAction.blow(1, 5.0, 1.0))
	# Wraps to the short way round: 3.0 + 0.5 is past half a turn.
	fixture.act(RulesAction.blow(1, 5.0, 3.0))
	assert_float(fixture.hud.damage.arcs[0]["angle"]).is_equal_approx(1.5, 0.001)
	assert_float(fixture.hud.damage.arcs[1]["angle"]).is_equal_approx(3.5 - TAU, 0.001)


func test_a_teammates_blow_leaves_my_health_and_my_arcs_alone() -> void:
	var fixture := _round(2)
	var state := fixture.hud.state
	fixture.act(RulesAction.blow(2, 40.0, 0.3))
	assert_float(state.health).is_equal(100.0)
	assert_array(fixture.hud.damage.arcs).is_empty()


func test_health_mends_in_the_hud_as_the_rules_mend_it() -> void:
	var fixture := _round()
	var state := fixture.hud.state
	fixture.act(RulesAction.blow(1, 60.0))
	for _i in 300:
		fixture.act(RulesAction.tick(0.0166))
	assert_float(state.health).is_equal(40.0)
	for _i in 120:
		fixture.act(RulesAction.tick(0.0166))
	assert_float(state.health).is_greater(40.0)
	assert_float(state.health).is_equal_approx(fixture.rules.health_of(1), 1.0)


func test_going_down_and_getting_up_show_in_the_bar_and_the_party() -> void:
	var fixture := _round(2)
	var state := fixture.hud.state
	fixture.act(RulesAction.blow(1, 500.0, 2.0))
	assert_float(state.health).is_equal(0.0)
	assert_bool(state.is_local_downed()).is_true()
	assert_float(fixture.hud.damage.frame_strength).is_greater(0.0)
	fixture.act(RulesAction.set_downed(1, false))
	assert_bool(state.is_local_downed()).is_false()
	assert_float(state.health).is_equal(state.max_health)


func test_a_late_joiner_loads_the_health_from_the_snapshot() -> void:
	var fixture := _round()
	fixture.act(RulesAction.blow(1, 45.0))
	var late := HudState.new()
	late.load_snapshot(fixture.rules.to_dict())
	assert_float(late.health).is_equal(55.0)
	assert_float(late.max_health).is_equal(100.0)
