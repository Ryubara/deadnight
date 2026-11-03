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
	player: PlayerState, damage: float, bearing: float, source_id: int, bleed_seconds: float = 0.0
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
		events.append(down(player, &"blow", bearing, bleed_seconds))
	return events


## The player goes down: no health left, and `bleed_seconds` to live unless a teammate gets them
## up. `cause` is `blow` or `forced`.
static func down(
	player: PlayerState, cause: StringName, bearing: float, bleed_seconds: float = 0.0
) -> Dictionary:
	player.downed = true
	player.dead = false
	player.health = 0.0
	player.downs += 1
	player.bleed_left = bleed_seconds
	return {
		"type": &"player_downed",
		"player_id": player.id,
		"cause": cause,
		"bearing": bearing,
		"bleed_seconds": bleed_seconds,
	}


## A tonic raises the most the player can have by `bonus` and gives them the same health now (a
## player who is down gets the room only, and stands up to all of it). The `player_healed` event.
static func raise_max(player: PlayerState, bonus: float) -> Dictionary:
	player.max_health += bonus
	if not player.downed:
		player.health += bonus
	return {
		"type": &"player_healed",
		"player_id": player.id,
		"health": player.health,
		"max_health": player.max_health,
		"reason": &"tonic",
	}


## The player gets up with `fraction` of their health (all of it at the end of a round; a
## teammate's revive gives `HealthTuning.revive_fraction`). `reviver_id` is the teammate who did it
## (0 for none: the round ended). A player who bled out gets up the same way.
static func revive(
	player: PlayerState, tuning: HealthTuning, fraction: float = 1.0, reviver_id: int = 0
) -> Array[Dictionary]:
	player.downed = false
	player.dead = false
	player.bleed_left = 0.0
	player.self_revive_left = 0.0
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
