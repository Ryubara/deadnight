class_name RevivePlay
extends RefCounted
## A downed player's bleed-out, as the rules settle it: the clock that runs while nobody holds the
## revive on them, and the death when it reaches zero. Static functions that take the rules (so no
## reference cycle is made), like `CranePlay`. Who holds a revive and for how long is the server's
## `ReviveChannel`; the rules act on the `revive` action it sends once the hold is complete. The
## design is `docs/design/revive.md`.
##
## The revive perk's self-revive lives here too: a player with it who is down with nobody on their
## feet counts `PerkTuning.self_revive_seconds` and gets themselves up, a few times a night.
##
## Events: `player_died` (player_id, cause); `self_revive_started` (player_id, seconds); the revive
## itself is the usual `player_revived` with `self` true.


## One tick of the clock: every downed player who nobody is holding loses the tick from their
## bleed-out; at zero they are dead. `held` is the ids of the players a teammate holds the revive
## on this tick.
static func tick(rules: GameRules, delta: float, held: Array = []) -> void:
	var revive := rules.tuning.revive
	for player: PlayerState in rules.players.values():
		if not player.downed or player.dead:
			continue
		if _self_revive(rules, player, delta):
			continue
		if revive.bleed_stops_while_held and held.has(player.id):
			continue
		player.bleed_left = maxf(player.bleed_left - delta, 0.0)
		if player.bleed_left <= 0.0:
			_die(rules, player)


static func _die(rules: GameRules, player: PlayerState) -> void:
	player.dead = true
	player.bleed_left = 0.0
	rules._emit(&"player_died", {"player_id": player.id, "cause": &"bleed_out"})


## Whether the revive perk would get this downed player up by themselves now: they have it, a use
## left, and no teammate is on their feet to do it.
static func can_self_revive(rules: GameRules, player: PlayerState) -> bool:
	var tuning := rules.tuning
	if not player.downed or player.dead:
		return false
	if player.self_revives >= tuning.perks.self_revive_uses:
		return false
	if not PerkEffects.has_in(tuning, player, ShopItem.Effect.REVIVE):
		return false
	for other: PlayerState in rules.players.values():
		if other != player and not other.downed:
			return false
	return true


## One tick of a downed player's own revive. True while it is running (the bleed-out clock stands
## still meanwhile, so the perk is never beaten by a hair).
static func _self_revive(rules: GameRules, player: PlayerState, delta: float) -> bool:
	if not can_self_revive(rules, player):
		player.self_revive_left = 0.0
		return false
	var seconds := rules.tuning.perks.self_revive_seconds
	if player.self_revive_left <= 0.0:
		player.self_revive_left = seconds
		rules._emit(&"self_revive_started", {"player_id": player.id, "seconds": seconds})
		return true
	player.self_revive_left -= delta
	if player.self_revive_left > 0.0:
		return true
	player.self_revive_left = 0.0
	player.self_revives += 1
	var events := PlayerHealth.revive(
		player, rules.tuning.health, rules.tuning.health.revive_fraction
	)
	events[1]["self"] = true
	rules._events.append_array(events)
	return true
