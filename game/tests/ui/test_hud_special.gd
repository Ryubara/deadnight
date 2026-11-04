# The special rounds on the HUD: the marquee in the break before one, the banner that names the
# round, the reward line when it is cleared, the boss bar, and a late joiner who sees all of it from
# the snapshot. Driven by the real rules' events.
extends GdUnitTestSuite

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func after_test() -> void:
	UIMotion.reduced = false


func _clear_round(fx: HudFixture) -> void:
	var guard := 0
	while fx.rules.phase == GameRules.Phase.ACTIVE and guard < 20000:
		fx.act(RulesAction.tick(RulesFixture.STEP * 6.0))
		for zombie_id in fx.rules.zombie_ids():
			fx.act(RulesAction.hit(1, zombie_id, RulesAction.ZONE_BODY, HudFixture.KILLING))
		guard += 1


## The night played to the break before `round_number`, every zombie killed on the way.
func _to_break_before(fx: HudFixture, round_number: int) -> void:
	fx.act(RulesAction.start())
	while fx.rules.round_number < round_number - 1 or fx.rules.phase != GameRules.Phase.BREAK:
		if fx.rules.phase == GameRules.Phase.BREAK:
			fx.act(RulesAction.skip_break())
		else:
			_clear_round(fx)


## Plays on into the special round until its headliner stands on the lot.
func _until_boss(fx: HudFixture) -> void:
	fx.act(RulesAction.skip_break())
	for _i in 2000:
		fx.act(RulesAction.tick(RulesFixture.STEP * 6.0))
		for zombie_id in fx.rules.zombie_ids():
			if fx.rules.zombie_type(zombie_id) == &"headliner":
				return


func test_the_marquee_comes_up_in_the_break_before_a_special_round() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 5)
	var marquee := fx.hud.marquee
	assert_bool(marquee.visible).is_true()
	assert_str(marquee.title_text).is_equal("DOUBLE FEATURE")
	assert_str(marquee.caption_text).contains("ROUND 5")
	assert_str(marquee.detail_text).is_equal("THE HEADLINER ARRIVES")


func test_the_announcement_of_a_round_of_one_type_names_the_type() -> void:
	# The rules' announcement carries no `only_type`; the marquee takes it from the schedule.
	var fx := HudFixture.make(_host)
	var state := fx.hud.state
	state.apply_event({"type": &"break_started", "next_round": 10, "seconds": 30.0})
	(
		state
		. apply_event(
			{
				"type": &"special_round_announced",
				"round": 10,
				"special_id": &"stampede",
				"title": "Midnight Stampede",
				"kind": &"only",
				"boss_type": &"",
				"boss_count": 0,
				"seconds": 30.0,
			}
		)
	)
	assert_str(fx.hud.marquee.detail_text).is_equal("ONLY RUNNERS")


func test_the_break_before_an_ordinary_round_has_no_marquee() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 3)
	assert_bool(fx.hud.marquee.visible).is_false()


func test_the_marquee_counts_the_break_down_and_goes_when_the_round_starts() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 5)
	var before := fx.hud.marquee.caption_text
	fx.hud.state.tick(2.0)
	assert_str(fx.hud.marquee.caption_text).is_not_equal(before)
	fx.act(RulesAction.skip_break())
	assert_bool(fx.hud.marquee.visible).is_false()


func test_more_players_bring_more_headliners_to_the_marquee() -> void:
	var fx := HudFixture.make(_host, 4)
	_to_break_before(fx, 5)
	assert_str(fx.hud.marquee.detail_text).is_equal("2 HEADLINERS ARRIVE")


func test_a_round_of_one_type_says_so() -> void:
	var fx := HudFixture.make(_host)
	var state := fx.hud.state
	state.apply_event({"type": &"round_started", "round": 9, "zombie_count": 30, "special_id": &""})
	state.apply_event({"type": &"round_ended", "round": 9, "special_id": &""})
	state.apply_event({"type": &"break_started", "next_round": 10, "seconds": 30.0})
	assert_str(fx.hud.marquee.title_text).is_equal("MIDNIGHT STAMPEDE")
	assert_str(fx.hud.marquee.detail_text).is_equal("ONLY RUNNERS")
	assert_str(fx.hud.marquee.caption_text).contains("ROUND 10")


func test_the_round_banner_names_the_special_round() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 5)
	fx.act(RulesAction.skip_break())
	assert_bool(fx.hud.banner.showing).is_true()
	assert_str(fx.hud.banner.title).is_equal("DOUBLE FEATURE")
	assert_str(fx.hud.banner.subtitle).is_equal("THE HEADLINER ARRIVES")


func test_the_line_under_the_name_stays_on_one_line() -> void:
	var fx := HudFixture.make(_host)
	for special in fx.rules.tuning.specials.rounds:
		fx.hud.state.apply_event(
			{"type": &"round_started", "round": 5, "zombie_count": 9, "special_id": special.id}
		)
		var banner := fx.hud.banner
		assert_float(banner.subtitle_width).is_less_equal(banner.subtitle_room)
		fx.hud.state.apply_event({"type": &"round_ended", "round": 5, "special_id": special.id})
		fx.hud.state.apply_event(
			{"type": &"special_round_cleared", "special_id": special.id, "reward": 1440}
		)
		banner.show_banner(
			"ROUND 5 SURVIVED", "%s CLEARED  +1440" % special.title.to_upper(), HudBanner.Rank.ROUND
		)
		assert_float(banner.subtitle_width).is_less_equal(banner.subtitle_room)


func test_clearing_the_round_shows_the_reward() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 5)
	fx.act(RulesAction.skip_break())
	_clear_round(fx)
	var reward := fx.rules.tuning.specials.special_for(5).reward_at(5)
	assert_array(fx.hud.events_feed.texts()).contains(["DOUBLE FEATURE CLEARED  +%d EACH" % reward])
	assert_str(fx.hud.banner.title).is_equal("ROUND 5 SURVIVED")
	assert_str(fx.hud.banner.subtitle).is_equal("DOUBLE FEATURE CLEARED  +%d" % reward)


func test_an_ordinary_round_keeps_its_old_words() -> void:
	var fx := HudFixture.make(_host)
	fx.into_round_one()
	assert_str(fx.hud.banner.title).is_equal("ROUND 1")
	_clear_round(fx)
	assert_str(fx.hud.banner.subtitle).is_equal("CATCH YOUR BREATH")


func test_the_letters_flicker_and_hold_still_with_reduced_motion() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 5)
	var lights := {}
	for _i in 40:
		fx.hud.marquee.advance(HudMarquee.FLICKER_STEP)
		lights[snappedf(fx.hud.marquee.letter_light, 0.01)] = true
	assert_int(lights.size()).is_greater(1)
	UIMotion.reduced = true
	lights.clear()
	for _i in 40:
		fx.hud.marquee.advance(HudMarquee.FLICKER_STEP)
		lights[snappedf(fx.hud.marquee.letter_light, 0.01)] = true
	assert_int(lights.size()).is_equal(1)


# The bulbs are polygons the Compatibility renderer builds into buffers of their own, and the web
# page keeps their ids for good: the board is drawn when the chase steps on, not every frame (#883).
func test_the_marquee_is_redrawn_when_the_bulbs_step_not_every_frame() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 5)
	await get_tree().process_frame
	var draws := [0]
	fx.hud.marquee.draw.connect(func() -> void: draws[0] += 1)
	for _i in 60:
		fx.hud.marquee.advance(1.0 / 60.0)
		await get_tree().process_frame
	# A second of frames, and the marquee also moves itself on in real time: some steps of the chase
	# and a few of the engine's own, never one for each of the sixty frames.
	assert_int(draws[0]).is_between(1, 20)


# --- A late joiner ---


## A HUD that joins now, from the snapshot of `fx`.
func _late_hud(fx: HudFixture) -> Hud:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	_host.add_child(hud)
	hud.state.special_schedule = HudSpecials.schedule_of(fx.rules.tuning.specials)
	hud.state.load_snapshot(fx.rules.to_dict())
	return hud


func test_a_late_joiner_mid_boss_night_sees_the_banner_the_bar_and_the_round() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 5)
	_until_boss(fx)
	var late := _late_hud(fx)
	assert_str(String(late.state.special_id)).is_equal("double_feature")
	assert_bool(late.banner.showing).is_true()
	assert_str(late.banner.title).is_equal("DOUBLE FEATURE")
	assert_bool(late.boss_bar.visible).is_true()
	assert_int(late.state.bosses.size()).is_equal(1)
	assert_float(late.boss_bar.fractions[0]).is_equal(1.0)
	assert_bool(late.marquee.visible).is_false()
	# What the HUD that saw every event shows.
	assert_str(late.banner.title).is_equal(fx.hud.banner.title)
	assert_int(late.state.bosses.size()).is_equal(fx.hud.state.bosses.size())


func test_a_boss_spawn_in_flight_when_the_snapshot_was_taken_gets_no_second_bar() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 5)
	_until_boss(fx)
	var late := _late_hud(fx)
	for zombie_id in fx.rules.zombie_ids():
		if fx.rules.zombie_type(zombie_id) == &"headliner":
			(
				late
				. state
				. apply_event(
					{
						"type": &"zombie_spawn_requested",
						"zombie_id": zombie_id,
						"zombie_type": &"headliner",
						"boss": true,
						"health": fx.rules.zombie_health(zombie_id),
					}
				)
			)
	assert_int(late.state.bosses.size()).is_equal(1)
	assert_str(late.boss_bar.caption_text).is_equal("THE PROJECTIONIST")


func test_a_late_joiner_sees_a_wounded_boss_wounded() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 5)
	_until_boss(fx)
	var boss_id := -1
	for zombie_id in fx.rules.zombie_ids():
		if fx.rules.zombie_type(zombie_id) == &"headliner":
			boss_id = zombie_id
	var health := fx.rules.zombie_health(boss_id)
	fx.act(RulesAction.hit(1, boss_id, RulesAction.ZONE_BODY, health * 0.5))
	var late := _late_hud(fx)
	assert_float(late.boss_bar.fractions[0]).is_equal_approx(0.5, 0.01)
	assert_float(late.boss_bar.fractions[0]).is_equal_approx(fx.hud.boss_bar.fractions[0], 0.01)


func test_a_late_joiner_in_the_break_before_a_special_round_sees_the_marquee() -> void:
	var fx := HudFixture.make(_host)
	_to_break_before(fx, 5)
	var late := _late_hud(fx)
	assert_bool(late.marquee.visible).is_true()
	assert_str(late.marquee.title_text).is_equal(fx.hud.marquee.title_text)
	assert_str(late.marquee.detail_text).is_equal(fx.hud.marquee.detail_text)


func test_a_snapshot_of_an_ordinary_round_shows_none_of_it() -> void:
	var fx := HudFixture.make(_host)
	fx.into_round_one()
	var late := _late_hud(fx)
	assert_bool(late.marquee.visible).is_false()
	assert_bool(late.boss_bar.visible).is_false()
	assert_bool(late.banner.showing).is_false()
