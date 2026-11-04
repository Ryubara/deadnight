class_name SpecialRound
extends Resource
## One kind of special round: a boss night or a round of only one type. Data only; `SpecialTuning`
## says which round gets which.

enum Kind {
	## A few headliners with escorts from the normal mix.
	BOSS,
	## Every zombie of the round is `only_type`.
	ONLY,
}

@export var id: StringName = &""
## What the marquee says. The HUD may show this or its own words for the id.
@export var title: String = ""
@export var kind: Kind = Kind.BOSS

@export_group("Boss")
@export var boss_type: StringName = &""
@export_range(1, 10, 1, "or_greater") var boss_count: int = 1
## One more boss for every this many players beyond the first.
@export_range(1, 10, 1, "or_greater") var players_per_extra_boss: int = 3
## Escorts as a fraction of the zombies a normal round of the same number has.
@export_range(0.0, 2.0, 0.05, "or_greater") var escort_fraction: float = 0.35
## The first boss arrives after this fraction of the escorts, the rest spread over the remainder.
@export_range(0.0, 1.0, 0.01) var boss_arrival: float = 0.3

@export_group("Only")
@export var only_type: StringName = &""
## The round's zombies as a fraction of a normal round's count.
@export_range(0.0, 2.0, 0.05, "or_greater") var count_fraction: float = 0.8
## Spawns come this many times as often as a normal round's.
@export_range(0.1, 5.0, 0.05, "or_greater") var spawn_rate: float = 1.0

@export_group("Reward")
## Paid to every player on their feet when the round is cleared, on top of the round bonus.
@export_range(0, 1000, 5, "or_greater", "suffix:pts") var reward_base: int = 200
@export_range(0, 1000, 5, "or_greater", "suffix:pts") var reward_per_round: int = 40


## The fields of `special_round_announced` for this special as round `round_number`, in a break of
## `seconds`, for `players` players.
func announcement(round_number: int, players: int, seconds: float) -> Dictionary:
	var is_boss := kind == Kind.BOSS
	return {
		"round": round_number,
		"special_id": id,
		"title": title,
		"kind": &"boss" if is_boss else &"only",
		"boss_type": boss_type if is_boss else &"",
		"boss_count": bosses_for(maxi(players, 1)) if is_boss else 0,
		"seconds": seconds,
	}


## The fields of `special_round_cleared` for round `round_number`.
func cleared(round_number: int) -> Dictionary:
	return {"round": round_number, "special_id": id, "reward": reward_at(round_number)}


## The types of the round's zombies in the order they spawn: `normal` is the count a normal round
## of this number has. A boss round is escorts with the bosses walked in among them; a round of one
## type is that type.
func plan(
	round_number: int, players: int, normal: int, roster: ZombieRoster, rng: RandomNumberGenerator
) -> Array[StringName]:
	if kind == Kind.ONLY:
		var only: Array[StringName] = []
		only.resize(maxi(1, roundi(float(normal) * count_fraction)))
		only.fill(only_type)
		return only
	var escorts := roster.plan_for_round(
		round_number, maxi(1, roundi(float(normal) * escort_fraction)), rng
	)
	var bosses := bosses_for(players)
	for i in bosses:
		var spread := boss_arrival + (1.0 - boss_arrival) * float(i) / bosses
		escorts.insert(floori(float(escorts.size() - i) * spread) + i, boss_type)
	return escorts


func reward_at(round_number: int) -> int:
	return reward_base + reward_per_round * round_number


func bosses_for(players: int) -> int:
	return boss_count + maxi(players - 1, 0) / maxi(players_per_extra_boss, 1)
