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


## A night with `player_count` players (ids 1..n), not started.
static func make_rules(
	player_count: int = 1, seed_value: int = 1234, t: RulesTuning = null
) -> GameRules:
	var rules := GameRules.new(t if t != null else tuning(), seed_value)
	for player_id in range(1, player_count + 1):
		rules.apply(RulesAction.add_player(player_id))
	return rules


## Ticks the fixed step until `seconds` have passed.
static func run(rules: GameRules, seconds: float) -> void:
	for _i in ceili(seconds / STEP):
		rules.apply(RulesAction.tick(STEP))


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
