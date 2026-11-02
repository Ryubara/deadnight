extends GdUnitTestSuite
## The scoreboard's numbers in a played night, alone: a bot plays rounds through the loopback, and
## what the HUD holds (the server's counts, read from its frames) is checked against an independent
## count of the events the client heard, against the rules, and against what the board draws.

const TICKS_PER_FRAME := 40
const ROUNDS := 3
const GIVE_UP_SECONDS := 900.0
## Cheap enough that the bot buys the first door and so reaches more zombies.
const CHEAP_DOOR := 250

var _killed_by: Dictionary = {}
var _downed: Dictionary = {}


func before_test() -> void:
	_killed_by.clear()
	_downed.clear()


func _count(event: Dictionary) -> void:
	match event["type"]:
		&"zombie_removed":
			if event["cause"] == &"killed" and int(event["killer_id"]) >= 0:
				var killer := int(event["killer_id"])
				_killed_by[killer] = int(_killed_by.get(killer, 0)) + 1
		&"player_downed":
			var player := int(event["player_id"])
			_downed[player] = int(_downed.get(player, 0)) + 1


func test_a_played_night_alone_counts_kills_and_downs_for_the_player() -> void:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.economy.item(&"door_concession").price = CHEAP_DOOR
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT, tuning, 7, hud)
	night.ticks_per_frame = TICKS_PER_FRAME
	var state := night.state
	state.event_received.connect(_count)
	var ticks := 0
	while state.rounds_started < ROUNDS and not state.over and ticks < GIVE_UP_SECONDS / Night.STEP:
		await get_tree().physics_frame
		ticks = night.server.tick_count
	assert_bool(state.over).is_false()
	var me := state.player_id
	var rules := night.server.rules
	assert_int(rules.kills_of(me)).is_greater_equal(RulesFixture.round_count(1))
	# Three counts of the same kills agree: the events the client heard, the server's rules, and the
	# HUD, which reads the server's frame (one tick behind the rules at most).
	night.tick()
	assert_int(int(_killed_by.get(me, 0))).is_equal(rules.kills_of(me))
	assert_int(hud.state.team[me]["kills"]).is_equal(rules.kills_of(me))
	assert_int(hud.state.team[me]["downs"]).is_equal(0)
	assert_int(hud.state.team[me]["ping"]).is_equal(HudState.NO_PING)
	assert_int(hud.state.night_clock).is_equal(floori(rules.night_time))
	assert_int(hud.state.night_clock).is_greater(30)
	# The board draws them, and has no ping column alone.
	hud.scoreboard.set_shown(true)
	assert_int(hud.scoreboard.rows_text.size()).is_equal(1)
	assert_str(hud.scoreboard.rows_text[0][1]).is_equal(str(rules.kills_of(me)))
	assert_str(hud.scoreboard.rows_text[0][2]).is_equal("0")
	assert_str(hud.scoreboard.rows_text[0][3]).is_equal(str(rules.points_of(me)))
	assert_bool(hud.scoreboard.has_ping).is_false()
	assert_str(hud.scoreboard.round_text).is_equal("ROUND %02d" % state.round_number())
	# Going down is counted once, and shows on the next frame.
	night.state.apply_events(rules.apply(RulesAction.blow(me, 99999.0)))
	night.tick()
	night.tick()
	assert_int(int(_downed.get(me, 0))).is_equal(1)
	assert_int(rules.downs_of(me)).is_equal(1)
	assert_int(hud.state.team[me]["downs"]).is_equal(1)
	assert_str(hud.scoreboard.rows_text[0][2]).is_equal("1")
	await NightFixture.settle_bake(night)
	night.queue_free()
	hud.queue_free()


func test_a_snapshot_for_a_hud_that_joins_late_carries_the_counts_and_the_clock() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	var rules := night.server.rules
	var ids := _two_zombies(night)
	RulesFixture.kill(rules, night.state.player_id, ids[0])
	RulesFixture.kill(rules, night.state.player_id, ids[1])
	rules.apply(RulesAction.blow(night.state.player_id, 99999.0))
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	hud.state.load_snapshot(rules.to_dict())
	var me := night.state.player_id
	assert_int(hud.state.team[me]["kills"]).is_equal(rules.kills_of(me))
	assert_int(hud.state.team[me]["downs"]).is_equal(1)
	assert_int(hud.state.night_clock).is_equal(floori(rules.night_time))
	await NightFixture.settle_bake(night)
	night.queue_free()
	hud.queue_free()


## Ends the break and runs until two zombies are on the lot; returns their ids.
func _two_zombies(night: Night) -> Array:
	night.server.rules.apply(RulesAction.skip_break())
	for _i in 1800:
		night.tick()
		if night.server.sim.zombies.size() >= 2:
			break
	var ids: Array = night.server.sim.zombies.keys()
	ids.sort()
	return ids.slice(0, 2)
