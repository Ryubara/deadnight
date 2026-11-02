class_name PlayerHealth
extends RefCounted
## What blows, downs and mending do to a `PlayerState`'s health, as plain functions: each changes
## the player and returns the events it caused (the shapes are in `GameRules`' header), which the
## rules append to the action's answer. No state of its own, no clock: time is the `delta` the
## rules' tick passes in.


## A new player: all the health there is, and no recent blow to wait out.
static func start(player: PlayerState, tuning: HealthTuning) -> void:
	player.max_health = tuning.max_health
	player.health = player.max_health
	player.since_blow = tuning.regen_delay


## A blow takes health off (never more than is left), restarts the wait before it mends, and downs
## the player at zero. The caller has checked the player is up and the round is on.
static func hurt(
	player: PlayerState, damage: float, bearing: float, source_id: int
) -> Array[Dictionary]:
	var dealt := minf(damage, player.health)
	player.health -= dealt
	player.since_blow = 0.0
	var events: Array[Dictionary] = [
		{
			"type": &"player_hurt",
			"player_id": player.id,
			"damage": dealt,
			"health": player.health,
			"max_health": player.max_health,
			"bearing": bearing,
			"source_id": source_id,
		}
	]
	if player.health <= 0.0:
		events.append(down(player, &"blow", bearing))
	return events


## The player goes down: no health left. `cause` is `blow` or `forced`.
static func down(player: PlayerState, cause: StringName, bearing: float) -> Dictionary:
	player.downed = true
	player.health = 0.0
	return {"type": &"player_downed", "player_id": player.id, "cause": cause, "bearing": bearing}


## The player gets up with `fraction` of their health (all of it at the end of a round; a
## teammate's revive gives `HealthTuning.revive_fraction`). `reviver_id` is the teammate who did it
## (0 for none: the round ended).
static func revive(
	player: PlayerState, tuning: HealthTuning, fraction: float = 1.0, reviver_id: int = 0
) -> Array[Dictionary]:
	player.downed = false
	player.health = player.max_health * fraction
	# Getting up at a round's end is a fresh start; a teammate's hand leaves the wait for mending
	# to run from the revive.
	player.since_blow = tuning.regen_delay if reviver_id == 0 else 0.0
	var events: Array[Dictionary] = [
		{
			"type": &"player_healed",
			"player_id": player.id,
			"health": player.health,
			"max_health": player.max_health,
			"reason": &"revive",
		},
		{"type": &"player_revived", "player_id": player.id, "reviver_id": reviver_id},
	]
	return events


## Health comes back once the wait since the last blow is over. One `player_healed` for each
## whole unit crossed, not one a tick.
static func mend(
	players: Dictionary[int, PlayerState], tuning: HealthTuning, delta: float
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for player: PlayerState in players.values():
		if player.downed:
			continue
		player.since_blow = minf(player.since_blow + delta, tuning.regen_delay)
		if player.since_blow < tuning.regen_delay or player.health >= player.max_health:
			continue
		var before := floori(player.health)
		player.health = minf(player.health + tuning.regen_per_second * delta, player.max_health)
		if floori(player.health) != before:
			(
				events
				. append(
					{
						"type": &"player_healed",
						"player_id": player.id,
						"health": player.health,
						"max_health": player.max_health,
						"reason": &"regen",
					}
				)
			)
	return events
