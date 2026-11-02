class_name RulesFixture
extends RefCounted
## Shared helpers for the rules suites: a fresh GameRules, a private copy of the tuning, and an
## event recorder.

const TUNING_PATH := "res://gameplay/rules/default_tuning.tres"
const STEP := 1.0 / 60.0
## More than any zombie has.
const KILLING_DAMAGE := 99999.0

## Every event the rules emitted since `record`, in order.
var events: Array[Dictionary] = []


## The shipped tuning table, copied so a test can change numbers without touching other suites.
static func tuning() -> RulesTuning:
	return (load(TUNING_PATH) as RulesTuning).duplicate(true)


## What the shipped tuning says a round holds: the zombies for `players`, and each one's health.
static func round_count(round_number: int, players: int = 1) -> int:
	return tuning().rounds.zombies_for_round(round_number, players)


static func round_health(round_number: int) -> float:
	return tuning().rounds.health_for_round(round_number)


## A night with `player_count` players (ids 1..n), not started.
static func make_rules(
	player_count: int = 1,
	seed_value: int = 1234,
	t: RulesTuning = null,
	settings: MatchSettings = null
) -> GameRules:
	var rules := GameRules.new(t if t != null else tuning(), seed_value, settings)
	for player_id in range(1, player_count + 1):
		rules.apply(RulesAction.add_player(player_id))
	return rules


## Ticks the fixed step until `seconds` have passed.
static func run(rules: GameRules, seconds: float) -> void:
	for _i in ceili(seconds / STEP):
		rules.apply(RulesAction.tick(STEP))


## Ticks `seconds` in steps of `step` and returns every event they caused.
static func advance(rules: GameRules, seconds: float, step: float = STEP) -> Array[Dictionary]:
	var caused: Array[Dictionary] = []
	for _i in ceili(seconds / step - 0.0001):
		caused.append_array(rules.apply(RulesAction.tick(step)))
	return caused


## The first event of `type` in `events`, or an empty dictionary.
static func first(events: Array[Dictionary], type: StringName) -> Dictionary:
	for event in events:
		if event["type"] == type:
			return event
	return {}


## Buys a crane play for `player_id` and spins it out. Returns the events from the purchase to the
## end of the spin: the prize is in `crane_prize_ready`, a breakdown in `crane_breakdown`.
static func play_crane(rules: GameRules, player_id: int) -> Array[Dictionary]:
	var caused := rules.apply(RulesAction.buy(player_id, &"crane_play"))
	var spin := rules.tuning.crane.spin_seconds
	caused.append_array(advance(rules, spin + 0.1, 0.1))
	return caused


## A tuning where the crane never breaks down (the odds are not what the suite tests).
static func steady_crane_tuning() -> RulesTuning:
	var t := tuning()
	t.crane.leave_chances = PackedFloat32Array([0.0])
	return t


## Starts the night and plays through the intro so round 1 is active.
static func into_round_one(rules: GameRules) -> void:
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.skip_break())


## Buys and returns the GameRules.BuyResult the events report.
static func buy(rules: GameRules, player_id: int, item_id: StringName) -> int:
	for event in rules.apply(RulesAction.buy(player_id, item_id)):
		if event["type"] == &"purchase_denied":
			return event["result"]
	return GameRules.BuyResult.OK


## One hit that is sure to kill whatever it lands on (a zombie in the rules has finite health).
static func kill(
	rules: GameRules,
	player_id: int,
	zombie_id: int,
	zone: StringName = RulesAction.ZONE_BODY,
	melee: bool = false
) -> Array[Dictionary]:
	return rules.apply(RulesAction.hit(player_id, zombie_id, zone, KILLING_DAMAGE, melee))


## Records every event of `rules` from now on.
static func record(rules: GameRules) -> RulesFixture:
	var recorder := RulesFixture.new()
	rules.event_emitted.connect(func(event: Dictionary) -> void: recorder.events.append(event))
	return recorder


## A night in round 1 with one living zombie of `type_id` (spawned from a forced plan). Pass a
## `RulesFixture.new()` as `recorder` to also get every event from the start, spawn included.
static func with_one_living(
	type_id: StringName, t: RulesTuning = null, recorder: RulesFixture = null
) -> GameRules:
	var night := make_rules(1, 11, t)
	if recorder != null:
		night.event_emitted.connect(func(event: Dictionary) -> void: recorder.events.append(event))
	into_round_one(night)
	night._plan.assign([type_id])
	run(night, 2.0)
	assert(night.zombie_ids().size() == 1, "expected exactly one living zombie")
	return night


## The ids of the zombies the rules asked for so far.
func spawned_ids() -> Array[int]:
	var ids: Array[int] = []
	for event in of(&"zombie_spawn_requested"):
		ids.append(event["zombie_id"])
	return ids


func of(event_type: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in events:
		if event["type"] == event_type:
			found.append(event)
	return found


func count(event_type: StringName) -> int:
	return of(event_type).size()


## Plays the round out: ticks the fixed step and kills every zombie the moment it stands, until the
## round ends (or `limit` seconds pass). Returns the seconds it took.
static func clear_round(rules: GameRules, limit: float = 600.0) -> float:
	var began_round := rules.round_number
	var spent := 0.0
	while rules.phase == GameRules.Phase.ACTIVE and rules.round_number == began_round:
		if spent > limit:
			break
		rules.apply(RulesAction.tick(STEP))
		spent += STEP
		for zombie_id in rules.zombie_ids():
			kill(rules, 1, zombie_id)
	return spent
