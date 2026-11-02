extends GdUnitTestSuite
## What a player reads when someone is down (docs/design/hud.md, Revives): the ring on the reviver's
## screen and on the downed player's, the clock on the health card, the prompt, the feed, the
## markers over a body and the player boxes. A real `GameRules` night makes every event; what the
## frame adds (the clock and the hold's progress) is pushed into the state as the binding does.

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func _round(players := 2) -> HudFixture:
	var fixture := HudFixture.make(_host, players)
	fixture.into_round_one()
	return fixture


## What `NightHudBinding` puts into the state from every frame: each player's revive numbers.
func _frame(fixture: HudFixture) -> void:
	var state := fixture.hud.state
	state.hold()
	for id: int in fixture.rules.players:
		state.set_player_revive(
			id,
			fixture.rules.is_dead(id),
			fixture.rules.bleed_left_of(id),
			fixture.rules.revive_fraction_of(id),
			fixture.rules.reviver_of(id)
		)
		state.set_player_stats(
			id,
			fixture.rules.kills_of(id),
			fixture.rules.downs_of(id),
			HudState.NO_PING,
			fixture.rules.revives_of(id)
		)
	state.release()


## One tick of the clock and one of the hold, as the server sends them.
func _hold(fixture: HudFixture, target: int, reviver: int, seconds: float) -> void:
	for _i in ceili(seconds / RulesFixture.STEP - 0.0001):
		fixture.act(RulesAction.tick(RulesFixture.STEP))
		fixture.act(RulesAction.revive_hold(target, reviver, RulesFixture.STEP))
	_frame(fixture)


func test_the_player_downed_event_carries_the_clock_the_hud_shows() -> void:
	var fixture := _round()
	var state := fixture.hud.state
	fixture.act(RulesAction.blow(1, 1000.0))
	assert_bool(state.is_local_downed()).is_true()
	assert_float(state.team[1]["bleed"]).is_equal(fixture.rules.tuning.revive.bleed_out_seconds)
	assert_bool(state.team[1]["dead"]).is_false()
	assert_float(state.bleed_share(state.team[1])).is_equal(1.0)


func test_a_downed_player_reads_the_clock_and_what_to_hope_for() -> void:
	var fixture := _round()
	fixture.act(RulesAction.blow(1, 1000.0))
	fixture.advance(0.1)
	_frame(fixture)
	var health := fixture.hud.health
	assert_str(health.down_text).is_equal("DOWN")
	assert_str(health.hint_text).is_equal("BLEEDING OUT  45 S")
	var ring := fixture.hud.revive
	assert_int(ring.mode).is_equal(HudRevive.Mode.DOWNED)
	assert_str(ring.number_text).is_equal("45")
	assert_str(ring.line_text).is_equal("BLEEDING OUT")
	assert_float(ring.clock_fraction).is_equal_approx(1.0, 0.01)
	assert_float(ring.fraction).is_equal(0.0)
	assert_bool(ring.visible).is_true()


func test_the_clock_on_the_card_and_in_the_ring_runs_down_with_the_rules() -> void:
	var fixture := _round()
	fixture.act(RulesAction.blow(1, 1000.0))
	for _i in ceili(10.0 / RulesFixture.STEP):
		fixture.act(RulesAction.tick(RulesFixture.STEP))
	_frame(fixture)
	var left := ceili(fixture.rules.bleed_left_of(1))
	assert_str(fixture.hud.revive.number_text).is_equal(str(left))
	assert_str(fixture.hud.health.hint_text).is_equal("BLEEDING OUT  %d S" % left)
	assert_float(fixture.hud.revive.clock_fraction).is_less(0.8)


func test_the_reviver_sees_a_ring_fill_and_the_name_of_who_they_pull_up() -> void:
	var fixture := _round()
	fixture.act(RulesAction.blow(2, 1000.0))
	_hold(fixture, 2, 1, 1.75)
	var ring := fixture.hud.revive
	assert_int(ring.mode).is_equal(HudRevive.Mode.REVIVING)
	assert_str(ring.line_text).is_equal("REVIVING MOE")
	assert_float(ring.fraction).is_equal_approx(0.5, 0.05)
	assert_str(ring.number_text).is_equal("2")
	assert_bool(ring.visible).is_true()
	# They are up, so their own card says nothing about being down.
	assert_bool(fixture.hud.health.shown_downed).is_false()


func test_the_downed_player_sees_the_same_ring_with_the_reviver_named() -> void:
	var fixture := _round()
	fixture.act(RulesAction.blow(1, 1000.0))
	_hold(fixture, 1, 2, 1.75)
	var ring := fixture.hud.revive
	assert_int(ring.mode).is_equal(HudRevive.Mode.BEING_REVIVED)
	assert_str(ring.line_text).is_equal("MOE IS PULLING YOU UP")
	assert_float(ring.fraction).is_equal_approx(0.5, 0.05)
	assert_str(fixture.hud.health.hint_text).is_equal("BEING PULLED UP")


func test_the_ring_goes_when_the_hold_does_and_when_the_player_is_up() -> void:
	var fixture := _round()
	fixture.act(RulesAction.blow(2, 1000.0))
	_hold(fixture, 2, 1, 1.0)
	assert_int(fixture.hud.revive.mode).is_equal(HudRevive.Mode.REVIVING)
	# The hold stops being renewed: the rules release it at the next tick.
	fixture.act(RulesAction.tick(RulesFixture.STEP))
	fixture.act(RulesAction.tick(RulesFixture.STEP))
	_frame(fixture)
	assert_int(fixture.hud.revive.mode).is_equal(HudRevive.Mode.NONE)
	_hold(fixture, 2, 1, fixture.rules.tuning.revive.revive_seconds + 0.1)
	assert_int(fixture.hud.revive.mode).is_equal(HudRevive.Mode.NONE)
	assert_bool(fixture.hud.revive.visible).is_false()
	assert_bool(fixture.hud.state.team[2]["downed"]).is_false()


func test_a_player_who_bled_out_reads_dead_until_the_round_ends() -> void:
	var fixture := _round()
	fixture.act(RulesAction.blow(1, 1000.0))
	for _i in ceili((fixture.rules.tuning.revive.bleed_out_seconds + 0.5) / 0.1):
		fixture.act(RulesAction.tick(0.1))
	_frame(fixture)
	var state := fixture.hud.state
	assert_bool(state.is_local_dead()).is_true()
	assert_int(fixture.hud.revive.mode).is_equal(HudRevive.Mode.DEAD)
	assert_str(fixture.hud.revive.line_text).is_equal("YOU BLED OUT")
	assert_str(fixture.hud.health.down_text).is_equal("DEAD")
	assert_str(fixture.hud.health.hint_text).is_equal("BACK NEXT ROUND")
	# And the round's end gets them up, with nothing left of the death.
	fixture.act(RulesAction.set_downed(1, false))
	_frame(fixture)
	assert_bool(state.is_local_dead()).is_false()
	assert_int(fixture.hud.revive.mode).is_equal(HudRevive.Mode.NONE)


func test_the_feed_names_who_revived_whom_and_who_bled_out() -> void:
	var fixture := _round()
	fixture.act(RulesAction.blow(2, 1000.0))
	_hold(fixture, 2, 1, fixture.rules.tuning.revive.revive_seconds + 0.1)
	var texts: Array[String] = []
	for row in fixture.hud.events_feed.rows:
		texts.append((row["label"] as Label).text)
	assert_array(texts).contains(["MOE IS DOWN", "RUBY REVIVED MOE"])
	fixture.act(RulesAction.blow(2, 1000.0))
	for _i in ceili((fixture.rules.tuning.revive.bleed_out_seconds + 0.5) / 0.1):
		fixture.act(RulesAction.tick(0.1))
	texts.clear()
	for row in fixture.hud.events_feed.rows:
		texts.append((row["label"] as Label).text)
	assert_array(texts).contains(["MOE BLED OUT"])


func test_a_round_end_get_up_names_nobody() -> void:
	var fixture := _round()
	fixture.act(RulesAction.blow(2, 1000.0))
	fixture.act(RulesAction.set_downed(2, false))
	var texts: Array[String] = []
	for row in fixture.hud.events_feed.rows:
		texts.append((row["label"] as Label).text)
	assert_array(texts).contains(["MOE IS BACK UP"])


func test_the_player_box_says_down_and_then_dead() -> void:
	var fixture := _round(2)
	fixture.act(RulesAction.blow(2, 1000.0))
	var box := fixture.hud.points.box_of(2)
	assert_bool(box.downed).is_true()
	assert_str(box.name_text).is_equal("DOWN")
	fixture.hud.state.apply_event({"type": &"player_died", "player_id": 2, "cause": &"bleed_out"})
	assert_str(box.name_text).is_equal("DEAD")
	assert_bool(fixture.hud.state.team[2]["downed"]).is_true()
	# Back up, the name is back.
	fixture.act(RulesAction.set_downed(2, false))
	assert_str(box.name_text).is_equal("MOE")


func test_a_late_joiner_reads_the_clocks_and_the_count_from_the_snapshot() -> void:
	var fixture := _round(3)
	fixture.act(RulesAction.blow(2, 1000.0))
	fixture.act(RulesAction.blow(3, 1000.0))
	for _i in ceili(10.0 / RulesFixture.STEP):
		fixture.act(RulesAction.tick(RulesFixture.STEP))
	_hold(fixture, 3, 1, fixture.rules.tuning.revive.revive_seconds + 0.1)
	var late := HudState.new()
	late.local_player_id = 2
	late.load_snapshot(fixture.rules.to_dict())
	assert_bool(late.team[2]["downed"]).is_true()
	assert_float(late.team[2]["bleed"]).is_equal_approx(fixture.rules.bleed_left_of(2), 0.001)
	assert_int(late.team[1]["revives"]).is_equal(1)
	assert_bool(late.team[3]["downed"]).is_false()


func test_the_prompt_for_a_downed_teammate_names_them_and_the_time_they_have() -> void:
	var fixture := _round(2)
	fixture.act(RulesAction.blow(2, 1000.0))
	var binding := NightHudBinding.new(fixture.hud, ClientState.new(), fixture.rules.tuning, null)
	binding.show_prompt({"kind": &"revive", "id": 2, "progress": 0.0, "bleed": 31.2})
	var prompt := fixture.hud.prompt
	assert_str(prompt.title_text).is_equal("REVIVE MOE")
	assert_str(prompt.detail_text).is_equal("HOLD TO REVIVE: DEAD IN 32 S")
	assert_bool(prompt.visible).is_true()


func test_the_marker_over_a_body_is_drawn_red_with_the_clock_and_the_hold() -> void:
	var fixture := _round(2)
	fixture.act(RulesAction.blow(2, 1000.0))
	var state := fixture.hud.state
	(
		state
		. set_markers(
			[
				{
					"id": &"player_2",
					"kind": &"ally",
					"x": 0.5,
					"y": 0.5,
					"distance": 6.0,
					"label": "Moe",
					"important": true,
					"downed": true,
					"dead": false,
					"bleed": 31,
					"revive": 0.4,
				}
			]
		)
	)
	var markers := fixture.hud.markers
	await await_idle_frame()
	var spot := markers.marker_at(&"player_2")
	assert_bool(spot.is_empty()).is_false()
	assert_bool(spot["pinned"]).is_false()
	# A body marker whose owner is off screen stays on the edge (it is important).
	(
		state
		. set_markers(
			[
				{
					"id": &"player_2",
					"kind": &"ally",
					"x": 1.6,
					"y": 0.5,
					"distance": 30.0,
					"label": "Moe",
					"important": true,
					"downed": true,
					"dead": false,
					"bleed": 12,
					"revive": 0.0,
				}
			]
		)
	)
	assert_bool(markers.marker_at(&"player_2")["pinned"]).is_true()


func test_the_ring_fits_the_screen_at_every_size() -> void:
	for canvas: Vector2 in [
		Vector2(1536.0, 864.0), Vector2(1920.0, 1080.0), Vector2(2560.0, 1080.0)
	]:
		var host: Control = auto_free(Control.new())
		host.size = canvas
		add_child(host)
		var fixture := HudFixture.make(host, 2)
		fixture.into_round_one()
		fixture.act(RulesAction.blow(1, 1000.0))
		var ring := fixture.hud.revive
		ring.size = canvas
		var centre := canvas * HudRevive.CENTRE
		var reach := HudRevive.RADIUS + HudRevive.RING + HudRevive.LINE_SIZE * 3.0
		assert_float(centre.y + reach).is_less(canvas.y)
		assert_float(centre.x - reach).is_greater(0.0)
