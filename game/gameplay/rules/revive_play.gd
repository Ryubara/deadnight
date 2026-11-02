class_name RevivePlay
extends RefCounted
## Getting a downed player back up, as the rules settle it: a teammate's hold, the downed player's
## bleed-out clock, and the death when it runs out. Static functions that take the rules (so no
## reference cycle is made), like `CranePlay`. The server decides who is in reach and who holds
## their hands free; this checks who is down and who is up, and keeps every number.
##
## Events: `revive_started` (player_id, reviver_id, seconds), `revive_interrupted` (player_id,
## reviver_id, reason), `player_revived` (player_id, reviver_id) with `player_healed`, `player_died`
## (player_id, cause). The design is `docs/design/revive.md`.


## One tick of a hold. Rejects what cannot be revived or cannot revive.
static func hold(rules: GameRules, target_id: int, reviver_id: int, delta: float) -> void:
	var problem := hold_problem(rules, target_id, reviver_id)
	if problem != &"":
		rules._reject(problem, RulesAction.REVIVE_HOLD)
		return
	var target: PlayerState = rules.players[target_id]
	var revive := rules.tuning.revive
	var began := target.reviver_id == 0
	target.reviver_id = reviver_id
	target.revive_progress += delta
	target.held = true
	if began:
		(
			rules
			. _emit(
				&"revive_started",
				{
					"player_id": target_id,
					"reviver_id": reviver_id,
					"seconds": revive.revive_seconds,
				}
			)
		)
	if target.revive_progress >= revive.revive_seconds:
		_complete(rules, target, rules.players[reviver_id])


## Why a hold cannot go on, or `&""` when it can (the rules' own checks; reach and hands are the
## server's).
static func hold_problem(rules: GameRules, target_id: int, reviver_id: int) -> StringName:
	var target := rules.players.get(target_id) as PlayerState
	var reviver := rules.players.get(reviver_id) as PlayerState
	if rules.phase != GameRules.Phase.ACTIVE:
		return &"wrong_phase"
	if target == null or reviver == null:
		return &"unknown_player"
	if target_id == reviver_id:
		return &"self_revive"
	if reviver.downed:
		return &"reviver_downed"
	if target.dead:
		return &"target_dead"
	if not target.downed:
		return &"not_downed"
	if target.reviver_id != 0 and target.reviver_id != reviver_id:
		return &"busy"
	return &""


## The hold on this player is over, if there is one.
static func release(rules: GameRules, target_id: int, reason: StringName) -> void:
	var target := rules.players.get(target_id) as PlayerState
	if target == null:
		rules._reject(&"unknown_player", RulesAction.REVIVE_RELEASE)
		return
	interrupt(rules, target, reason)


## Clears a hold in progress and says so; nothing when there is none.
static func interrupt(rules: GameRules, target: PlayerState, reason: StringName) -> void:
	if target.reviver_id == 0 and target.revive_progress <= 0.0:
		return
	var reviver_id := target.reviver_id
	target.revive_progress = 0.0
	target.reviver_id = 0
	target.held = false
	rules._emit(
		&"revive_interrupted", {"player_id": target.id, "reviver_id": reviver_id, "reason": reason}
	)


## A player who was holding a revive has gone down or left: the hold on their patient is over.
static func reviver_gone(rules: GameRules, reviver_id: int, reason: StringName) -> void:
	for player: PlayerState in rules.players.values():
		if player.reviver_id == reviver_id:
			interrupt(rules, player, reason)


## One tick of the clock: a hold that was not renewed since the last tick is over, and every downed
## player who nobody is holding loses the tick from their bleed-out; at zero they are dead.
static func tick(rules: GameRules, delta: float) -> void:
	var revive := rules.tuning.revive
	for player: PlayerState in rules.players.values():
		if not player.downed or player.dead:
			continue
		if player.reviver_id != 0 and not player.held:
			interrupt(rules, player, &"released")
		player.held = false
		if player.reviver_id != 0 and revive.bleed_stops_while_held:
			continue
		player.bleed_left = maxf(player.bleed_left - delta, 0.0)
		if player.bleed_left <= 0.0:
			_die(rules, player)


static func _complete(rules: GameRules, target: PlayerState, reviver: PlayerState) -> void:
	var revive := rules.tuning.revive
	rules._events.append_array(
		PlayerHealth.revive(target, rules.tuning.health, revive.health_fraction, reviver.id)
	)
	reviver.revives += 1
	rules._award(reviver.id, revive.reviver_points, &"revive")


static func _die(rules: GameRules, player: PlayerState) -> void:
	interrupt(rules, player, &"died")
	player.dead = true
	player.bleed_left = 0.0
	rules._emit(&"player_died", {"player_id": player.id, "cause": &"bleed_out"})
