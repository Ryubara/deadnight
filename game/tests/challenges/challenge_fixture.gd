class_name ChallengeFixture
extends RefCounted
## Helpers for the challenge suites: a clock on a chosen day, a small catalogue whose numbers a
## test can count by hand, a tracker following players, and a real night's events to feed it.

## A minute past midnight of `day` (UTC), so the day does not turn under a test by accident.
const MINUTE := 60.0
const SAVE_DIR := "user://test_challenges/"


static func clock_on(day: int, offset_seconds: int = 0) -> ChallengeClock:
	return ChallengeClock.fixed(float(day) * ChallengeClock.DAY_SECONDS + MINUTE, offset_seconds)


## A path for a save of one test, removed first.
static func save_path(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + name + ".json"
	for leftover in [path, path + ".tmp", path + ".broken"]:
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(leftover)
	return path


## Three dailies (one a tier), two orders and one ladder, with round numbers.
static func small_catalog() -> ChallengeCatalog:
	var catalog := ChallengeCatalog.new()
	(
		catalog
		. add_all(
			[
				_record("d_kills", "kills", 8, "short", "kills"),
				_record("d_head", "kills:head", 4, "medium", "aim"),
				_record("d_round", "round", 3, "long", "survive", "night"),
			],
			ChallengeDef.Family.DAILY
		)
	)
	(
		catalog
		. add_all(
			[
				_record("o_boards", "boards_repaired", 5, "short", "", "total", "light"),
				_record("o_doors", "doors_bought", 2, "short", "", "night", "night"),
				_record("o_shotgun", "kills:weapon:shotgun", 6, "medium", "", "total", "craft"),
				_record("o_cans", "fuel_cans", 3, "medium", "", "total", "light"),
			],
			ChallengeDef.Family.ORDER
		)
	)
	(
		catalog
		. add_all(
			[
				{"id": "m_kills", "text": "Put down {n}", "stat": "kills", "steps": [5, 20, 50]},
				{"id": "m_round", "text": "Reach round {n}", "stat": "round", "steps": [2, 4]},
			],
			ChallengeDef.Family.MILESTONE
		)
	)
	return catalog


## A catalogue a round of three zombies can finish: a daily of each tier, an order and a ladder.
static func quick_catalog() -> ChallengeCatalog:
	var catalog := ChallengeCatalog.new()
	(
		catalog
		. add_all(
			[
				_quick("d_kills", "kills", 4, "short", "kills"),
				_quick("d_head", "kills:head", 2, "medium", "aim"),
				_quick("d_round", "round", 1, "long", "survive", "night"),
			],
			ChallengeDef.Family.DAILY
		)
	)
	catalog.add_all(
		[_quick("o_points", "points_earned", 100, "short", "", "total", "night")],
		ChallengeDef.Family.ORDER
	)
	catalog.add_all(
		[
			{
				"id": "m_kills",
				"text": "Put down {n}",
				"stat": "kills",
				"steps": [1, 3],
				"reward": {"xp": 5}
			}
		],
		ChallengeDef.Family.MILESTONE
	)
	return catalog


static func _quick(
	id: String,
	stat: String,
	target: int,
	tier: String,
	group: String,
	mode := "total",
	pillar := ""
) -> Dictionary:
	var record := _record(id, stat, target, tier, group, mode, pillar)
	record["reward"] = {"xp": 5}
	return record


static func _record(
	id: String,
	stat: String,
	target: int,
	tier: String,
	group: String,
	mode := "total",
	pillar := ""
) -> Dictionary:
	return {
		"id": id,
		"text": "Do %s {n}" % stat,
		"stat": stat,
		"target": target,
		"tier": tier,
		"group": group,
		"mode": mode,
		"pillar": pillar,
		"reward": {"xp": 1},
	}


## A tracker on `catalog` at `day` following each id with a fresh profile (in `profiles`).
static func tracker_for(
	catalog: ChallengeCatalog, day: int, ids: Array[int], profiles: Dictionary
) -> ChallengeTracker:
	var tracker := ChallengeTracker.new(catalog, clock_on(day))
	for id in ids:
		var profile := ChallengeProfile.fresh(id)
		profiles[id] = profile
		tracker.follow(id, profile)
	return tracker


## Gives every event to the tracker, in order; answers every advance.
static func feed(tracker: ChallengeTracker, events: Array) -> Array[Dictionary]:
	var moved: Array[Dictionary] = []
	for event: Dictionary in events:
		moved.append_array(tracker.observe(event))
	return moved


## A night of `count` players (ids 1 to count), not started, and the events that added them.
static func night(count: int, seed_value: int = 1234) -> Dictionary:
	var rules := GameRules.new(RulesFixture.tuning(), seed_value)
	var events: Array[Dictionary] = []
	for id in range(1, count + 1):
		events.append_array(rules.apply(RulesAction.add_player(id)))
	return {"rules": rules, "events": events}


## Starts the night, plays round one through with every zombie killed by `killer` (a headshot
## each) and answers all the events, up to and including the round's end.
static func play_round_one(rules: GameRules, killer: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	events.append_array(rules.apply(RulesAction.start()))
	events.append_array(rules.apply(RulesAction.skip_break()))
	for _i in 4000:
		events.append_array(rules.apply(RulesAction.tick(RulesFixture.STEP)))
		for zombie_id in rules.zombie_ids():
			events.append_array(RulesFixture.kill(rules, killer, zombie_id, RulesAction.ZONE_HEAD))
		if rules.phase == GameRules.Phase.BREAK:
			break
	return events
