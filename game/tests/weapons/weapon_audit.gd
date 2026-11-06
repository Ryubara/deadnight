class_name WeaponAudit
extends RefCounted
## What a weapon really does to a walker (#972): one run of the real damage path, never a table. A
## night at round N with one walker on the lot, the weapon in the shooter's hands, the shooter's eye
## at the real eye height, a ray to a height on the zombie, the fitted hit zones, the combat server
## and the rules' health for the round. It says how many trigger pulls the kill took, how long, and
## which zones the pulls met (a chest-high aim lands on the head more often than not: the head is
## half the figure). The class targets (`WeaponClassTargets`) and the design page's audit table are
## measured here.

## The rounds the targets are written for.
const ROUNDS: Array[int] = [1, 5, 10, 15, 20]
## Aim heights on the zombie, from the eye: the head, the chest and the legs.
const HEAD := 1.62
const CHEST := 1.1
const LEGS := 0.5
## How far the zombie stands, metres: inside every weapon's full-damage range, and inside a blow's.
const SHOT_REACH := 4.0
const BLOW_REACH := 1.1
const STEP := 1.0 / 60.0
## Longest run, in game seconds, before a weapon is said never to kill.
const LIMIT := 40.0


## One run: the pulls and seconds a walker of `round_number` takes to die to `weapon_id` aimed at
## `aim` metres up the figure, from the weapon's own reach. `seed_value` varies a scatter's pellets.
## `{"pulls", "seconds", "zones", "killed", "damage"}`; `zones` holds the zone of every hit.
static func kill_run(
	weapon_id: StringName, round_number: int, aim: float, seed_value: int = 1, recut: bool = false
) -> Dictionary:
	var def := WeaponCatalog.get_def(weapon_id)
	var reach := BLOW_REACH if def.is_melee() else SHOT_REACH
	var tuning := RulesFixture.tuning()
	tuning.specials.every = 0
	var rules := RulesFixture.make_rules(1, 1234, tuning)
	var server := CombatServer.new(WeaponCatalog.all(), rules, Callable(), seed_value)
	rules.round_number = round_number - 1
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 40.0)
	var walker := -1
	for id in rules.zombie_ids():
		if walker < 0 and rules.zombie_type(id) == &"walker":
			walker = id
		else:
			RulesFixture.kill(rules, 1, id)
	server.apply(CombatAction.give_weapon(1, weapon_id))
	if recut:
		server.apply(CombatAction.upgrade_weapon(1, weapon_id))
	# Rounds are not what is measured here (a magazine and a reserve are `WeaponClassTargets`'
	# own row): the weapon never runs dry, only reloads.
	server.weapon_of(1).reserve = 99999
	var eye := Vector3(0.0, NightTuning.new().eye_height, 0.0)
	var feet := Vector3(0.0, 0.0, -reach)
	var dir := (feet + Vector3(0.0, aim, 0.0) - eye).normalized()
	var positions := {walker: feet}
	var run := {"pulls": 0, "seconds": 0.0, "zones": [], "killed": false, "damage": 0.0}
	var seq := 0
	for tick in int(LIMIT / STEP):
		server.apply(CombatAction.targets(WeaponsFixture.list_of(positions)))
		var events := server.apply(CombatAction.tick(STEP))
		var state := server.weapon_of(1)
		if state.fire_block() == &"empty":
			events.append_array(server.apply(CombatAction.reload_weapon(1)))
		elif state.fire_block() == &"":
			seq += 1
			events.append_array(server.apply(CombatAction.fire(1, seq, eye, dir, eye, server.now)))
		for event in events:
			if event["type"] == &"shot_fired":
				run["pulls"] += 1
			elif event["type"] == &"damage_dealt":
				run["zones"].append(event["zone"])
				run["damage"] += event["damage"]
			elif event["type"] == &"target_killed":
				run["killed"] = true
		if run["killed"]:
			run["seconds"] = float(tick) * STEP
			return run
	run["seconds"] = LIMIT
	return run


## The pulls to kill, the seconds to kill and the zone the pulls met most, for a walker of
## `round_number` aimed at `aim`, over a few seeds (a scatter weapon's pellets differ): the median.
static func measure(
	weapon_id: StringName, round_number: int, aim: float, seeds: int = 5, recut: bool = false
) -> Dictionary:
	var pulls: Array[int] = []
	var seconds: Array[float] = []
	var zone: StringName = &""
	for s in seeds:
		var run := kill_run(weapon_id, round_number, aim, 11 + s, recut)
		pulls.append(run["pulls"] if run["killed"] else 99)
		seconds.append(run["seconds"] if run["killed"] else LIMIT)
		if run["zones"].size() > 0 and zone == &"":
			zone = run["zones"][run["zones"].size() - 1]
	pulls.sort()
	seconds.sort()
	return {"pulls": pulls[seeds / 2], "seconds": seconds[seeds / 2], "zone": zone}
