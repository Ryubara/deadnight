# A HUD that joins late (or reconnects) from `GameRules.to_dict()` must show what the HUD that saw
# every event shows (#143): round, zombies left and total, points, down states and grenades; and the
# names already set stay.
extends GdUnitTestSuite

const NAMES := ["Ruby", "Moe", "Dee"]

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


## A mid-round night for three players: kills made, points earned and spent, one player down, a
## grenade thrown. Returns the fixture; its HUD saw every event.
func _mid_round() -> HudFixture:
	var fixture := HudFixture.make(_host, 3)
	fixture.into_round_one()
	var ids := fixture.spawn(5)
	for id in ids.slice(0, 3):
		fixture.act(RulesAction.hit(1, id, RulesAction.ZONE_HEAD, HudFixture.KILLING))
	fixture.act(RulesAction.set_downed(2, true))
	fixture.act(RulesAction.use_grenade(1))
	return fixture


## A HUD that arrives now: it knows the names (a lobby told it) and loads the snapshot.
func _late_joiner(fixture: HudFixture, local_id := 1) -> HudState:
	var late := HudState.new()
	late.local_player_id = local_id
	for i in NAMES.size():
		late.set_player_name(i + 1, NAMES[i])
	late.configure(
		fixture.hud.state.fuel_capacity,
		fixture.hud.state.circuits.keys(),
		fixture.hud.state.circuits.keys().filter(
			func(id: StringName) -> bool: return fixture.hud.state.circuits[id]
		)
	)
	late.load_snapshot(fixture.rules.to_dict())
	return late


func test_a_late_joiner_shows_the_same_night_as_the_hud_that_saw_every_event() -> void:
	var fixture := _mid_round()
	var live := fixture.hud.state
	var late := _late_joiner(fixture)
	# The round and the zombies still to kill, from the snapshot's own counts.
	assert_int(late.round_number).is_equal(live.round_number)
	assert_int(late.phase).is_equal(live.phase)
	assert_int(late.zombies_total).is_equal(live.zombies_total)
	assert_int(late.zombies_left).is_equal(live.zombies_left)
	assert_int(late.zombies_left).is_equal(fixture.rules.zombies_remaining())
	assert_int(late.zombies_left).is_less(late.zombies_total)
	# The local player's readings.
	assert_int(late.points).is_equal(live.points)
	assert_int(late.grenades).is_equal(live.grenades)
	assert_int(late.grenades).is_equal(fixture.rules.grenades_of(1))
	# Everyone's down state, points and grenades.
	for player_id in live.team:
		assert_bool(late.team[player_id]["downed"]).is_equal(live.team[player_id]["downed"])
		assert_int(late.team[player_id]["points"]).is_equal(live.team[player_id]["points"])
		assert_int(late.team[player_id]["grenades"]).is_equal(live.team[player_id]["grenades"])
	assert_bool(late.team[2]["downed"]).is_true()


func test_the_names_set_before_a_snapshot_survive_it() -> void:
	var fixture := _mid_round()
	var late := _late_joiner(fixture)
	for i in NAMES.size():
		assert_str(late.team[i + 1]["name"]).is_equal(NAMES[i])
	assert_str(late.local_name()).is_equal("Ruby")


func test_a_player_the_snapshot_does_not_have_is_gone_and_a_new_one_gets_a_default_name() -> void:
	var fixture := _mid_round()
	var late := HudState.new()
	late.set_player_name(7, "Ghost")
	late.load_snapshot(fixture.rules.to_dict())
	assert_bool(late.team.has(7)).is_false()
	assert_str(late.team[2]["name"]).is_equal("PLAYER 2")


func test_the_late_joiner_sees_the_same_after_the_night_goes_on() -> void:
	# Snapshot first, then the same events the live HUD sees from here on: they stay equal.
	var fixture := _mid_round()
	var late := _late_joiner(fixture, 2)
	var ids := fixture.spawn(2)
	var events: Array[Dictionary] = []
	for id in ids:
		events.append_array(
			fixture.act(RulesAction.hit(1, id, RulesAction.ZONE_BODY, HudFixture.KILLING))
		)
	events.append_array(fixture.act(RulesAction.use_grenade(2)))
	late.apply_events(events)
	assert_int(late.zombies_left).is_equal(fixture.rules.zombies_remaining())
	assert_int(late.grenades).is_equal(fixture.rules.grenades_of(2))


func test_a_snapshot_between_rounds_keeps_the_last_totals() -> void:
	var fixture := HudFixture.make(_host, 2)
	fixture.into_round_one()
	for id in fixture.spawn(40):
		fixture.act(RulesAction.hit(1, id, RulesAction.ZONE_BODY, HudFixture.KILLING))
	var live := fixture.hud.state
	assert_int(live.phase).is_equal(HudState.PHASE_BREAK)
	var late := HudState.new()
	late.load_snapshot(fixture.rules.to_dict())
	assert_int(late.zombies_left).is_equal(0)
	assert_int(late.zombies_total).is_equal(live.zombies_total)
	assert_float(late.break_left).is_equal_approx(live.break_left, 0.01)


func test_the_grenade_count_follows_every_event_that_changes_it() -> void:
	var fixture := HudFixture.make(_host, 2)
	var state := fixture.hud.state
	# The starting count comes with the player, before any grenade event.
	assert_int(fixture.rules.grenades_of(1)).is_greater(0)
	assert_int(state.grenades).is_equal(fixture.rules.grenades_of(1))
	# The round's refill and a throw are grenade events too.
	fixture.into_round_one()
	assert_int(state.grenades).is_equal(fixture.rules.grenades_of(1))
	var before := state.grenades
	fixture.act(RulesAction.use_grenade(1))
	assert_int(state.grenades).is_equal(before - 1)
	assert_int(state.team[1]["grenades"]).is_equal(before - 1)
	# Another player's grenade changes their entry, not the local count.
	fixture.act(RulesAction.use_grenade(2))
	assert_int(state.grenades).is_equal(before - 1)
	assert_int(state.team[2]["grenades"]).is_equal(fixture.rules.grenades_of(2))
	assert_int(state.team[2]["grenades"]).is_equal(before - 1)


func test_the_health_card_shows_the_grenades() -> void:
	var fixture := HudFixture.make(_host, 1)
	fixture.into_round_one()
	fixture.act(RulesAction.use_grenade(1))
	assert_str(fixture.hud.health.grenade_text).is_equal(
		"GRENADES x%d" % fixture.rules.grenades_of(1)
	)
