# The HUD parts: each reads the state and shows it. Driven by real rules events and hand-made
# events, time moved by fixed steps, input simulated.
extends GdUnitTestSuite

var _host: Control
var _fixture: HudFixture
var _hud: Hud


func before_test() -> void:
	UIMotion.reduced = false
	UIInputMode.reset()
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func after_test() -> void:
	UIMotion.reduced = false
	UIInputMode.reset()
	Input.action_release(&"interact")


func _start(players := 1) -> void:
	_fixture = HudFixture.make(_host, players)
	_hud = _fixture.hud


# --- Round, points, ammo, health ---


func test_the_round_shows_on_reel_digits() -> void:
	_start()
	assert_str(_hud.round_part.number_text).is_equal("00")
	_fixture.into_round_one()
	assert_str(_hud.round_part.number_text).is_equal("01")
	_hud.state.apply_event({"type": &"round_started", "round": 12, "zombie_count": 40})
	assert_str(_hud.round_part.number_text).is_equal("12")
	_hud.state.apply_event({"type": &"round_started", "round": 100, "zombie_count": 400})
	assert_str(_hud.round_part.number_text).is_equal("100")
	assert_str(_hud.round_part.detail_text).is_equal("400 LEFT")


func test_points_show_the_number() -> void:
	_start()
	assert_str(_hud.points.number_text).is_equal("200")
	_fixture.act(RulesAction.grant_points(1, 60, &"kill"))
	assert_str(_hud.points.number_text).is_equal("260")


func test_ammo_goes_hot_and_asks_for_a_reload() -> void:
	_start()
	_hud.state.set_ammo(30, 150, "Rifle")
	assert_str(_hud.ammo.magazine_text).is_equal("30")
	assert_str(_hud.ammo.reserve_text).is_equal("/ 150")
	assert_bool(_hud.ammo.is_low).is_false()
	assert_str(_hud.ammo.hint_text).is_equal("")
	_hud.state.set_ammo(6, 150)
	assert_bool(_hud.ammo.is_low).is_true()
	assert_str(_hud.ammo.hint_text).is_equal("LOW")
	_hud.state.set_ammo(0, 150)
	assert_str(_hud.ammo.hint_text).is_equal("RELOAD")
	_hud.state.set_ammo(0, 0)
	assert_str(_hud.ammo.hint_text).is_equal("NO AMMO")


func test_down_replaces_the_health_bar() -> void:
	_start()
	_hud.state.set_equipment("Flare", 2)
	assert_bool(_hud.health.shown_downed).is_false()
	assert_str(_hud.health.equipment_text).is_equal("FLARE")
	_fixture.act(RulesAction.set_downed(1, true))
	assert_bool(_hud.health.shown_downed).is_true()
	assert_str(_hud.health.down_text).is_equal("DOWN")
	_fixture.act(RulesAction.set_downed(1, false))
	assert_bool(_hud.health.shown_downed).is_false()


# --- Gains, hits, damage ---


func test_gains_stack_oldest_first_and_never_overlap() -> void:
	_start()
	_fixture.into_round_one()
	var ids := _fixture.spawn(3)
	_fixture.act(RulesAction.hit(1, ids[0], RulesAction.ZONE_HEAD, HudFixture.KILLING))
	_fixture.advance(0.2)
	_fixture.act(RulesAction.hit(1, ids[1], RulesAction.ZONE_BODY, HudFixture.KILLING))
	var texts := _hud.gains.texts()
	assert_array(texts).has_size(2)
	assert_str(texts[0]).contains("HEADSHOT KILL")
	assert_str(texts[1]).contains("KILL")
	await await_idle_frame()
	var first := (_hud.gains.rows[0]["label"] as Label).get_global_rect()
	var second := (_hud.gains.rows[1]["label"] as Label).get_global_rect()
	assert_bool(first.intersects(second)).is_false()
	_fixture.advance(HudTuning.current().gains_life - 0.2 + 0.05)
	assert_array(_hud.gains.texts()).has_size(1)
	_fixture.advance(1.0)
	assert_array(_hud.gains.texts()).is_empty()


func test_gains_are_capped_and_small_hits_merge() -> void:
	_start()
	for i in 12:
		_hud.gains.add_gain(&"kill", 60 + i)
	assert_int(_hud.gains.rows.size()).is_equal(HudGains.MAX_ROWS)
	var gains := HudGains.new()
	_host.add_child(gains)
	gains.bind(_hud.state)
	for _i in 6:
		gains.add_gain(&"hit", 4)
	assert_array(gains.texts()).has_size(1)
	assert_str(gains.texts()[0]).starts_with("+24")


func test_a_purchase_shows_as_a_dim_spend() -> void:
	_start()
	_fixture.into_round_one()
	_fixture.act(RulesAction.grant_points(1, 400))
	_fixture.act(RulesAction.buy(1, &"door_concession"))
	assert_str(_hud.gains.texts().back()).is_equal("-350  BOUGHT")


func test_hit_markers_and_damage_numbers_follow_hits_and_are_capped() -> void:
	_start()
	_fixture.into_round_one()
	var ids := _fixture.spawn(1)
	_fixture.act(RulesAction.hit(1, ids[0], RulesAction.ZONE_HEAD, 25.0))
	var crosshair := _hud.crosshair
	assert_int(crosshair.markers.size()).is_equal(1)
	assert_int(crosshair.markers[0]["kind"]).is_equal(HudCrosshair.Kind.HEAD)
	assert_str(crosshair.numbers[0]["text"]).is_equal("25")
	crosshair.advance(HudTuning.current().hit_number_life + 0.1)
	assert_array(crosshair.numbers).is_empty()
	assert_array(crosshair.markers).is_empty()
	for i in 20:
		_hud.state.apply_event(
			{"type": &"zombie_damaged", "player_id": 1, "zone": &"body", "damage": 10.0 + i}
		)
	assert_int(crosshair.numbers.size()).is_equal(HudCrosshair.MAX_NUMBERS)
	_hud.state.apply_event(
		{"type": &"zombie_damaged", "player_id": 2, "zone": &"body", "damage": 9.0}
	)
	assert_str(crosshair.numbers.back()["text"]).is_equal("29")


func test_a_kill_flashes_the_kill_marker_for_the_killer_only() -> void:
	_start(2)
	var other := {"type": &"zombie_removed", "zombie_id": 1, "cause": &"killed", "killer_id": 2}
	_hud.state.apply_event(other)
	assert_array(_hud.crosshair.markers).is_empty()
	var mine := {"type": &"zombie_removed", "zombie_id": 2, "cause": &"killed", "killer_id": 1}
	_hud.state.apply_event(mine)
	assert_int(_hud.crosshair.markers[0]["kind"]).is_equal(HudCrosshair.Kind.KILL)


func test_a_blow_draws_an_arc_toward_the_attacker_and_low_health_a_frame() -> void:
	_start()
	_hud.state.apply_event(HudFixture.hurt(1.0, 80.0))
	assert_int(_hud.damage.arcs.size()).is_equal(1)
	assert_float(_hud.state.health).is_equal(80.0)
	assert_float(_hud.damage.frame_strength).is_equal(0.0)
	_hud.state.apply_event(HudFixture.hurt(-2.0, 20.0))
	_hud.damage.advance(0.0)
	assert_float(_hud.damage.frame_strength).is_greater(0.0)
	_hud.damage.advance(HudTuning.current().damage_arc_life + 0.1)
	assert_array(_hud.damage.arcs).is_empty()
	for i in 20:
		_hud.state.apply_event(HudFixture.hurt(float(i), 20.0))
	assert_int(_hud.damage.arcs.size()).is_equal(HudDamage.MAX_ARCS)


func test_the_low_health_frame_is_steady_with_reduced_motion() -> void:
	_start()
	_hud.state.set_health(15.0)
	var seen: Array[float] = []
	for _i in 8:
		_hud.damage.advance(0.1)
		seen.append(_hud.damage.frame_strength)
	assert_bool(seen.min() != seen.max()).is_true()
	UIMotion.reduced = true
	seen.clear()
	for _i in 8:
		_hud.damage.advance(0.1)
		seen.append(_hud.damage.frame_strength)
	assert_float(seen.min()).is_equal(seen.max())


# --- Banner, feed, notices ---


func test_the_round_banner_runs_in_holds_and_out() -> void:
	_start()
	_fixture.into_round_one()
	var banner := _hud.banner
	assert_bool(banner.showing).is_true()
	assert_str(banner.title).is_equal("ROUND 1")
	assert_float(banner.presence()).is_less(1.0)
	_fixture.advance(HudTuning.current().banner_in + 0.2)
	assert_float(banner.presence()).is_equal(1.0)
	_fixture.advance(HudTuning.current().banner_hold)
	assert_float(banner.presence()).is_less(1.0)
	_fixture.advance(HudTuning.current().banner_out + 0.1)
	assert_bool(banner.showing).is_false()
	assert_bool(banner.visible).is_false()


func test_round_end_and_game_over_banners() -> void:
	_start()
	_hud.state.apply_event({"type": &"round_ended", "round": 4})
	assert_str(_hud.banner.title).is_equal("ROUND 4 SURVIVED")
	_hud.state.apply_event({"type": &"game_over", "reason": &"all_down", "round_reached": 4})
	assert_str(_hud.banner.title).is_equal("THE LIGHTS GO OUT")
	assert_str(_hud.banner.subtitle).is_equal("YOU LASTED TO ROUND 4")
	_fixture.advance(60.0)
	assert_bool(_hud.banner.showing).is_true()


func test_an_area_name_shows_but_never_replaces_a_round_banner() -> void:
	_start()
	_hud.state.set_area("The Lot", "Find the concession stand")
	assert_str(_hud.banner.title).is_equal("THE LOT")
	_hud.state.apply_event({"type": &"round_started", "round": 2, "zombie_count": 9})
	assert_str(_hud.banner.title).is_equal("ROUND 2")
	_hud.state.set_area("The Booth")
	assert_str(_hud.banner.title).is_equal("ROUND 2")
	assert_str(_hud.objective.area_text).is_equal("THE BOOTH")
	_hud.state.set_area("The Booth")
	assert_str(_hud.banner.title).is_equal("ROUND 2")


func test_the_event_feed_says_who_did_what_and_fades() -> void:
	_start(2)
	_fixture.into_round_one()
	_fixture.act(RulesAction.grant_points(2, 900))
	_fixture.act(RulesAction.buy(2, &"door_concession"))
	assert_array(_hud.events_feed.texts()).contains(["MOE OPENED THE CONCESSION STAND"])
	_fixture.act(RulesAction.set_downed(2, true))
	assert_str(_hud.events_feed.texts().back()).is_equal("MOE IS DOWN")
	_fixture.advance(HudTuning.current().feed_life + 0.1)
	assert_array(_hud.events_feed.texts()).is_empty()


func test_join_and_leave_notices_use_the_name() -> void:
	_start()
	_hud.state.set_player_name(2, "Moe")
	_fixture.act(RulesAction.add_player(2))
	_fixture.act(RulesAction.remove_player(2))
	assert_array(_hud.notices.texts()).contains_exactly(["MOE LEFT"])
	_hud.state.set_player_name(2, "Moe")
	_fixture.act(RulesAction.add_player(2))
	assert_array(_hud.notices.texts()).has_size(1)
	assert_str(_hud.notices.texts()[0]).is_equal("MOE JOINED")
	# The history keeps what a row no longer shows (a browser probe reads it).
	assert_array(_hud.notices.history).contains(["MOE LEFT", "MOE JOINED"])
	for i in 5:
		_hud.notices.push("X%d" % i)
	assert_int(_hud.notices.rows.size()).is_equal(HudFeed.MAX_NOTICES)


# --- Fuel, team ---


func test_the_tank_and_the_circuits_show() -> void:
	_start()
	var fuel := _hud.fuel
	assert_int(fuel.lit_segments).is_equal(HudFuel.SEGMENTS)
	assert_array(fuel.lit_circuits).contains_exactly([&"screen_lot"])
	_hud.state.apply_event({"type": &"fuel_changed", "fuel": 50.0, "delta": -50.0})
	assert_int(fuel.lit_segments).is_equal(10)
	assert_str(fuel.status_text).is_equal("50%")
	_hud.state.apply_events(
		[{"type": &"fuel_changed", "fuel": 20.0, "delta": -30.0}, {"type": &"fuel_low"}]
	)
	assert_str(fuel.status_text).is_equal("LOW")
	_hud.state.apply_event({"type": &"fuel_changed", "fuel": 0.0, "delta": -20.0})
	assert_str(fuel.status_text).is_equal("NO POWER")
	assert_array(fuel.lit_circuits).is_empty()


func test_teammates_are_listed_after_you_with_their_state() -> void:
	_start()
	assert_array(_hud.points.shown).has_size(1)
	_hud.state.set_player_name(2, "Moe")
	_hud.state.set_player_name(3, "Dee")
	_fixture.act(RulesAction.add_player(2))
	_fixture.act(RulesAction.add_player(3))
	assert_array(_hud.points.shown).has_size(3)
	assert_bool(_hud.points.shown[0]["local"]).is_true()
	assert_str(_hud.points.shown[1]["name"]).is_equal("Moe")
	assert_bool(_hud.points.shown[1]["downed"]).is_false()
	_fixture.into_round_one()
	_fixture.act(RulesAction.set_downed(3, true))
	assert_bool(_hud.points.shown[2]["downed"]).is_true()
	assert_str(_hud.points.box_of(3).name_text).is_equal("DOWN")
