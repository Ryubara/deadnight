class_name BossNight
extends RefCounted
## The first boss night (round 5, Double Feature) played by four hosted bots in the real server, for
## the parity check against the balance simulator (bots plan, phase 3). The economy is the plan's
## phase 4, so the bots cannot shop their way to round 5; they begin it instead with what the
## simulator's player of the matching skill carries at that point, bought through the shop with
## points the test grants, the magazines full and the reserve at what a player prepares for a
## special round. The night starts at the round: the rules are set to the end of round 4 and the
## break is skipped, which is the only liberty taken with them. A night passes when the round ends
## with a bot on its feet; it fails when every bot is down or `seconds` of play pass.

const STEP := Night.STEP
const ROUND := 5
## Longest a boss night is played (seconds of play): the simulator's longest is a few minutes.
const DEFAULT_SECONDS := 420

## The outcome of the last night: `{passed, seconds, kills, downs, boss_down}`.
var result := {}


## Plays one night with four bots of `profile_maker` (a Callable making a `BotProfile`), the seed
## and the shop items each bot is given (in order). `parent` is the node the world is added to.
static func play(
	parent: Node,
	profile_maker: Callable,
	seed_value: int,
	loadout: Array[StringName],
	seconds: int = DEFAULT_SECONDS,
	reserve_share := 1.0
) -> Dictionary:
	var night := await NightFixture.seat(parent, 4, null, seed_value)
	night.server.rules.round_number = ROUND - 1
	for id in range(1, 5):
		night.seat(id, profile_maker.call(), seed_value * 10 + id)
		night.server.rules.apply(RulesAction.grant_points(id, 100000))
		for item in loadout:
			night.server.buy(id, item)
		_fill_reserves(night, id, reserve_share)
	night.gather()
	var outcome := {
		"passed": false,
		"seconds": 0.0,
		"kills": 0,
		"boss_down": false,
		"downs": 0,
		"blows": {},
		"boss_hits": {},
	}
	var events: Array[Dictionary] = []
	night.on_event = func(event: Dictionary) -> void: events.append(event)
	night.start_round()
	var ticks := 0
	var over := false
	var dry_since := {}
	while ticks < seconds * 60 and not over:
		night.tick()
		ticks += 1
		_resupply(night, dry_since, ticks, reserve_share)
		if ticks % 3600 == 0:
			print(
				"TRACE ",
				ticks / 60,
				" remaining ",
				night.frame.get("remaining", -1),
				" zombies ",
				night.server.sim.zombies.size()
			)
		for event in events:
			match event["type"]:
				&"round_ended":
					if event["round"] == ROUND:
						outcome["passed"] = true
						over = true
				&"game_over":
					over = true
				&"player_downed":
					outcome["downs"] += 1
				&"player_damaged":
					var taken: Array = outcome["blows"].get(event["zombie_type"], [0, 0.0])
					taken[0] += 1
					taken[1] += event["damage"]
					outcome["blows"][event["zombie_type"]] = taken
				&"zombie_damaged":
					if event["zombie_type"] == &"headliner":
						outcome["boss_hits"][event["zone"]] = (
							outcome["boss_hits"].get(event["zone"], 0) + 1
						)
				&"zombie_removed":
					if event["cause"] == &"killed":
						outcome["kills"] += 1
						outcome["boss_down"] = outcome["boss_down"] or event["boss"]
		events.clear()
	outcome["seconds"] = float(ticks) / 60.0
	outcome["remaining"] = night.frame.get("remaining", -1)
	var left: Array = []
	for zombie: ZombieBody in night.server.sim.zombies.values():
		left.append(
			[
				zombie.profile.type,
				zombie.mode,
				snappedf(zombie.position.x, 0.1),
				snappedf(zombie.position.z, 0.1),
				zombie.gate_id
			]
		)
	outcome["left"] = left.slice(0, 6)
	var bots: Array = []
	for id in range(1, 5):
		var p: Dictionary = night.frame["players"][id]
		(
			bots
			. append(
				[
					id,
					snappedf(p["pos"].x, 0.1),
					snappedf(p["pos"].z, 0.1),
					roundi(p["health"]),
					p["downed"],
					p["weapon"],
					p["ammo"],
					p["reserve"],
					night.host.bots[id - 1].state.shots,
				]
			)
		)
	outcome["bots"] = bots
	night.on_event = Callable()
	night.dispose()
	return outcome


## Gives a bot its rounds back once it has been without a round in any firearm for the time of a
## trip to the locker.
static func _resupply(
	night: SeatedNight, dry_since: Dictionary, ticks: int, reserve_share: float
) -> void:
	for id in range(1, 5):
		var rounds := 0
		for weapon_id: StringName in night.server.combat.carried(id):
			var state := night.server.combat.state_of(id, weapon_id)
			if state.uses_ammo():
				rounds += state.ammo + state.reserve
		if rounds > 0:
			dry_since.erase(id)
		elif not dry_since.has(id):
			dry_since[id] = ticks
		elif float(ticks - dry_since[id]) * STEP >= NightSim.RESUPPLY_SECONDS:
			dry_since.erase(id)
			_fill_reserves(night, id, reserve_share)


## Every carried firearm's reserve to what a player brings into a special round: `share` of the
## weapon's limit (the simulator's `SimSkill.ammo_topoff`: a weak player tops up to half).
static func _fill_reserves(night: SeatedNight, id: int, share: float) -> void:
	for weapon_id: StringName in night.server.combat.carried(id):
		var state := night.server.combat.state_of(id, weapon_id)
		state.reserve = roundi(float(state.def.reserve_max) * share)
		state.ammo = state.def.magazine_size
