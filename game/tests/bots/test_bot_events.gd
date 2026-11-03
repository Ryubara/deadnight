# What a bot may hear (bots plan, phase 1): the events a person's feed and HUD already show, and
# its own; nothing with server-side detail. The allow-list is a constant, and this asserts what
# it drops.
extends GdUnitTestSuite

const ME := 3
const OTHER := 2
## Events that carry what a person could not know: they must never reach a bot.
const DROPPED: Array[StringName] = [
	&"zombie_spawn_requested",
	&"zombie_damaged",
	&"zombie_crippled",
	&"damage_dealt",
	&"target_killed",
	&"headshot_hit",
	&"projectile_spawned",
	&"projectile_burst",
	&"blast_hit",
	&"player_damaged",
	&"look_packet",
	&"player_blasted",
	&"cook_started",
]


func test_the_public_events_reach_every_bot() -> void:
	for type in BotEvents.PUBLIC:
		assert_bool(BotEvents.allows({"type": type}, ME)).is_true()


func test_the_crane_is_public_whatever_the_event_is_called() -> void:
	assert_bool(BotEvents.allows({"type": &"crane_prize_ready"}, ME)).is_true()
	assert_bool(BotEvents.allows({"type": &"crane_spin_started"}, ME)).is_true()


func test_an_own_event_reaches_only_the_bot_it_is_about() -> void:
	for type in BotEvents.OWN:
		assert_bool(BotEvents.allows({"type": type, "player_id": ME}, ME)).is_true()
		assert_bool(BotEvents.allows({"type": type, "player_id": OTHER}, ME)).is_false()
	# A shot names its shooter, not a player.
	assert_bool(BotEvents.allows({"type": &"shot_fired", "shooter_id": ME}, ME)).is_true()
	assert_bool(BotEvents.allows({"type": &"shot_fired", "shooter_id": OTHER}, ME)).is_false()
	# An own event that names nobody is nobody's.
	assert_bool(BotEvents.allows({"type": &"points_changed"}, ME)).is_false()


func test_what_a_person_could_not_know_is_dropped() -> void:
	for type in DROPPED:
		assert_bool(BotEvents.allows({"type": type, "player_id": ME}, ME)).is_false()
		assert_bool(BotEvents.PUBLIC.has(type) or BotEvents.OWN.has(type)).is_false()


func test_an_event_nobody_listed_is_dropped() -> void:
	assert_bool(BotEvents.allows({"type": &"something_new", "player_id": ME}, ME)).is_false()
	assert_bool(BotEvents.allows({}, ME)).is_false()


func test_filter_keeps_order_and_the_state_never_hears_the_rest() -> void:
	var rig := BotRig.new()
	var heard: Array[StringName] = []
	rig.bot.state.event_received.connect(
		func(event: Dictionary) -> void: heard.append(event["type"])
	)
	(
		rig
		. bot
		. hear(
			[
				{"type": &"zombie_spawn_requested", "zombie_id": 9, "health": 400.0},
				{"type": &"round_started", "round": 1},
				{"type": &"zombie_damaged", "zombie_id": 9, "health": 10.0},
				{"type": &"points_changed", "player_id": OTHER, "delta": 60},
				{"type": &"points_changed", "player_id": BotRig.ME, "delta": 60},
			]
		)
	)
	assert_array(heard).is_equal([&"round_started", &"points_changed"])
	assert_int(rig.bot.state.points_earned).is_equal(60)


func test_a_landed_blow_turns_into_a_direction_to_look_toward() -> void:
	var rig := BotRig.new()
	rig.bot.hear([{"type": &"player_hurt", "player_id": BotRig.ME, "damage": 12.0, "bearing": 0.5}])
	assert_int(rig.bot.perception.beliefs.blows.size()).is_equal(1)
	# The rules' bearing is clockwise from -z; a view yaw is counter-clockwise.
	assert_float(rig.bot.perception.beliefs.blows[0]["yaw"]).is_equal_approx(-0.5, 0.0001)
	assert_float(rig.bot.damage_taken()).is_equal(12.0)


func test_a_flare_is_heard_by_the_bot_that_fired_it_and_by_no_other() -> void:
	var burst := {
		"type": &"lure_started",
		"shooter_id": ME,
		"point": Vector3.ZERO,
		"radius": 25.0,
		"seconds": 8.0
	}
	assert_bool(BotEvents.allows(burst, ME)).is_true()
	assert_bool(BotEvents.allows(burst, OTHER)).is_false()
	var rig := BotRig.new()
	var fired := burst.duplicate()
	fired["shooter_id"] = BotRig.ME
	rig.bot.hear([fired])
	assert_int(rig.bot.team.active_lures(0.0).size()).is_equal(1)
	assert_int(rig.bot.telemetry.counters.get(&"flares_fired", 0)).is_equal(1)
	var others := burst.duplicate()
	others["shooter_id"] = 9
	rig.bot.hear([others])
	assert_int(rig.bot.team.active_lures(0.0).size()).is_equal(1)
