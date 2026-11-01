# The autopilot plays whole rounds headless: nothing errors, rounds advance, points are earned
# and spent. It sends the same commands a person does, through the loopback to the server. The
# HUD listens to the same events a client does, and what it shows is checked against the night:
# the round, the points, the prompt at the door and the purchase.
extends GdUnitTestSuite

## Ticks run in each physics frame, so the run takes seconds, not minutes.
const TICKS_PER_FRAME := 40
## A door the bot can afford in round two, so spending shows without a long run.
const CHEAP_DOOR := 250
const ROUNDS := 3
## Game seconds after which a run gives up (a bot that stops advancing fails the test).
const GIVE_UP_SECONDS := 900.0

var _prompts_seen: Array[Dictionary] = []
var _feed_at_purchase: Array[String] = []
var _points_at_purchase := -1


func test_the_bot_plays_rounds_earns_and_spends() -> void:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.economy.item(&"door_concession").price = CHEAP_DOOR
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT, tuning, 7, hud)
	night.ticks_per_frame = TICKS_PER_FRAME
	var state := night.state
	night.ticked.connect(func() -> void: _watch_prompt(hud))
	state.event_received.connect(func(event: Dictionary) -> void: _watch_purchase(hud, event))
	var ticks := 0
	while state.rounds_started < ROUNDS and not state.over and ticks < GIVE_UP_SECONDS / Night.STEP:
		await get_tree().physics_frame
		ticks = night.server.tick_count
	assert_bool(state.over).is_false()
	assert_int(state.rounds_started).is_greater_equal(ROUNDS)
	assert_int(state.kills).is_greater(10)
	assert_int(state.points_earned).is_greater(200)
	assert_int(state.points_spent).is_greater_equal(CHEAP_DOOR)
	assert_int(state.doors_bought).is_greater_equal(1)
	assert_bool(night.server.rules.is_door_open(&"door_concession")).is_true()
	_assert_the_hud_shows_the_night(hud, night)
	_assert_the_door_was_offered_then_bought(hud)
	night.queue_free()
	hud.queue_free()


func _watch_prompt(hud: Hud) -> void:
	var prompt := hud.state.prompt
	if prompt.get("kind") == &"buy_door" and _prompts_seen.is_empty():
		_prompts_seen.append(prompt.duplicate())


func _watch_purchase(hud: Hud, event: Dictionary) -> void:
	if event["type"] == &"purchase_made" and event["item_id"] == &"door_concession":
		_feed_at_purchase = hud.events_feed.texts()
		_points_at_purchase = hud.state.points


func _assert_the_hud_shows_the_night(hud: Hud, night: Night) -> void:
	var state := night.state
	var me := state.me()
	assert_int(hud.state.round_number).is_equal(state.round_number())
	assert_str(hud.round_part.number_text).is_equal(str(state.round_number()).pad_zeros(2))
	assert_int(hud.state.round_number).is_greater_equal(ROUNDS)
	assert_int(hud.state.points).is_equal(state.points())
	assert_str(hud.points.number_text).is_equal(str(state.points()))
	assert_float(hud.state.health).is_equal_approx(me["health"], 0.01)
	assert_int(hud.state.ammo_magazine).is_equal(me["ammo"])
	assert_int(hud.state.ammo_reserve).is_equal(me["reserve"])
	assert_str(hud.state.weapon_name).is_not_empty()
	assert_bool(hud.state.team.has(night.PLAYER_ID)).is_true()


func _assert_the_door_was_offered_then_bought(hud: Hud) -> void:
	assert_array(_prompts_seen).is_not_empty()
	assert_str(_prompts_seen[0]["label"]).is_equal("Concession stand")
	assert_int(_prompts_seen[0]["cost"]).is_equal(CHEAP_DOOR)
	assert_array(_feed_at_purchase).contains(["%s OPENED THE CONCESSION STAND" % "PLAYER 1"])
	assert_int(_points_at_purchase).is_greater_equal(0)
	# The card is gone once the door is.
	assert_bool(hud.state.prompt.get("kind") == &"buy_door").is_false()
