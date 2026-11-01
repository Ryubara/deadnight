extends GdUnitTestSuite
## Every emitter of a zombie event builds the fields the docs promise (docs/design/rounds.md,
## "Actions and events"), exactly: a shot and a grenade blast agree, so a health bar or a count by
## type can trust any `zombie_damaged`, wherever it came from.

## The documented fields of each zombie event, besides `type`.
const DOCUMENTED := {
	&"zombie_spawn_requested":
	[
		"zombie_id",
		"zombie_type",
		"look",
		"boss",
		"health",
		"speed",
		"point_roll",
		"damage",
		"knockback",
		"telegraph_seconds",
		"barrier_speed",
		"hit_chance",
	],
	&"zombie_damaged":
	["zombie_id", "zombie_type", "player_id", "zone", "damage", "health", "max_health"],
	&"zombie_removed": ["zombie_id", "zombie_type", "boss", "cause", "killer_id", "zone", "melee"],
	&"zombie_crippled":
	["zombie_id", "zombie_type", "look", "player_id", "cause", "health", "speed_scale"],
}

var _t: RulesTuning


func before_test() -> void:
	_t = RulesFixture.tuning()


## Plays every way a zombie event can be caused, and returns what each way emitted, by name.
func _every_emitter() -> Dictionary[String, Array]:
	var by_cause: Dictionary[String, Array] = {}
	var log := RulesFixture.new()
	var shot := RulesFixture.with_one_living(&"walker", _t, log)
	by_cause["spawn"] = log.of(&"zombie_spawn_requested")
	var id: int = shot.zombie_ids()[0]
	by_cause["shot"] = shot.apply(RulesAction.hit(1, id, RulesAction.ZONE_BODY, 1.0))
	by_cause["shot_kill"] = RulesFixture.kill(shot, 1, id, RulesAction.ZONE_HEAD)
	var boss := RulesFixture.with_one_living(&"headliner", _t)
	var boss_id: int = boss.zombie_ids()[0]
	by_cause["weak_spot"] = boss.apply(RulesAction.hit(1, boss_id, RulesAction.ZONE_WEAK, 1.0))
	var brute := RulesFixture.with_one_living(&"brute", _t)
	var brute_id: int = brute.zombie_ids()[0]
	by_cause["blast"] = brute.apply(RulesAction.explosion(1, [_victim(brute, brute_id, 0.1, 0.0)]))
	by_cause["blast_kill"] = brute.apply(
		RulesAction.explosion(1, [_victim(brute, brute_id, 1.0, 0.0)])
	)
	var walker := RulesFixture.with_one_living(&"walker", _t)
	var walker_id: int = walker.zombie_ids()[0]
	by_cause["blast_cripple"] = walker.apply(
		RulesAction.explosion(1, [_victim(walker, walker_id, 0.3, 0.3)])
	)
	by_cause["gone"] = walker.apply(RulesAction.zombie_gone(walker_id))
	return by_cause


## A blast victim that takes `fraction` of the zombie's current health, `legs` of it on the legs.
func _victim(rules: GameRules, zombie_id: int, fraction: float, legs: float) -> Dictionary:
	var health := rules.zombie_health(zombie_id)
	return {"zombie_id": zombie_id, "damage": health * fraction, "leg_damage": health * legs}


func test_every_zombie_event_carries_exactly_the_documented_fields() -> void:
	var seen: Dictionary[StringName, int] = {}
	var by_cause := _every_emitter()
	for cause in by_cause:
		for event: Dictionary in by_cause[cause]:
			var type: StringName = event["type"]
			if not DOCUMENTED.has(type):
				continue
			seen[type] = seen.get(type, 0) + 1
			var keys: Array = event.keys()
			keys.erase("type")
			keys.sort()
			var expected: Array = DOCUMENTED[type].duplicate()
			expected.sort()
			(
				assert_array(keys)
				. override_failure_message("%s from a %s has %s" % [type, cause, keys])
				. is_equal(expected)
			)
	for type: StringName in DOCUMENTED:
		(
			assert_int(seen.get(type, 0))
			. override_failure_message("%s never emitted" % type)
			. is_greater(0)
		)


func test_both_emitters_of_zombie_damaged_are_covered() -> void:
	var by_cause := _every_emitter()
	var zones: Array[StringName] = []
	for cause in ["shot", "weak_spot", "blast", "blast_kill", "blast_cripple"]:
		for event: Dictionary in by_cause[cause]:
			if event["type"] == &"zombie_damaged":
				zones.append(event["zone"])
	assert_array(zones).contains(
		[RulesAction.ZONE_BODY, RulesAction.ZONE_WEAK, RulesAction.ZONE_BLAST]
	)


func test_a_blast_reports_the_type_and_the_full_health_like_a_shot() -> void:
	var rules := RulesFixture.with_one_living(&"brute", _t)
	var id: int = rules.zombie_ids()[0]
	var full := rules.zombie_health(id)
	var events := rules.apply(
		RulesAction.explosion(1, [{"zombie_id": id, "damage": 5.0, "leg_damage": 0.0}])
	)
	var damaged := events.filter(func(e: Dictionary) -> bool: return e["type"] == &"zombie_damaged")
	assert_int(damaged.size()).is_equal(1)
	assert_str(damaged[0]["zombie_type"]).is_equal("brute")
	assert_float(damaged[0]["max_health"]).is_equal(full)
	assert_float(damaged[0]["health"]).is_equal_approx(full - 5.0, 0.001)
