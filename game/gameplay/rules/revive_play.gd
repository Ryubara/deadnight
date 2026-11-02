class_name RevivePlay
extends RefCounted
## A downed player's bleed-out, as the rules settle it: the clock that runs while nobody holds the
## revive on them, and the death when it reaches zero. Static functions that take the rules (so no
## reference cycle is made), like `CranePlay`. Who holds a revive and for how long is the server's
## `ReviveChannel`; the rules act on the `revive` action it sends once the hold is complete. The
## design is `docs/design/revive.md`.
##
## Event: `player_died` (player_id, cause).


## One tick of the clock: every downed player who nobody is holding loses the tick from their
## bleed-out; at zero they are dead. `held` is the ids of the players a teammate holds the revive
## on this tick.
static func tick(rules: GameRules, delta: float, held: Array = []) -> void:
	var revive := rules.tuning.revive
	for player: PlayerState in rules.players.values():
		if not player.downed or player.dead:
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
