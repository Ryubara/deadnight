class_name ReviveChannel
extends RefCounted
## A teammate raising a downed player: the held `use` button beside them, for the rules'
## `revive_seconds`. The channel goes on while the button stays down and the teammate is in reach;
## a release, a step away or a fall ends it and the time starts over. Two helpers at once do not
## speed it up (the lowest id of the tick holds the downed player; the other waits). At the full
## time the rules are asked for the `revive` action; they own what it does.
##
## The server owns one. It reads the bodies' places and the rules, and tells the clients through
## `announce` (`revive_started`, `revive_stopped`).

## Set by the server, and again when a test swaps its tuning.
var tuning: NightTuning

var _rules: GameRules
## Player id to body, the server's own dictionary.
var _bodies: Dictionary
var _announce: Callable
## The teammate each player is raising, and the seconds each downed player has been held on to.
var _holding: Dictionary[int, int] = {}
var _time: Dictionary[int, float] = {}
## Downed player id to the teammate holding on to them this tick.
var _seen: Dictionary[int, int] = {}


func _init(
	p_tuning: NightTuning, p_rules: GameRules, p_bodies: Dictionary, p_announce: Callable
) -> void:
	tuning = p_tuning
	_rules = p_rules
	_bodies = p_bodies
	_announce = p_announce


## Starts a tick: who holds whom is read again from this tick's commands.
func begin_tick() -> void:
	_seen.clear()


## The downed teammate nearest to this player within `revive_reach` (lowest id on a tie), or 0.
## Nobody when the player is down themselves or the round is not on; a teammate who bled out is
## past reviving.
func in_reach(player_id: int) -> int:
	if _is_down(player_id) or _rules.phase != GameRules.Phase.ACTIVE:
		return 0
	var here: Vector3 = _bodies[player_id].global_position
	var best := 0
	var best_apart := INF
	for other_id: int in _bodies:
		if other_id == player_id or not _is_down(other_id) or _rules.is_dead(other_id):
			continue
		var there: Vector3 = _bodies[other_id].global_position
		var apart := Vector2(here.x - there.x, here.z - there.z).length()
		if apart > tuning.revive_reach:
			continue
		if apart < best_apart or (apart == best_apart and other_id < best):
			best = other_id
			best_apart = apart
	return best


## The downed players a teammate is holding on to now: the rules stand their bleed-out clock still
## for them (`RulesAction.tick`'s `held`).
func held_targets() -> Array:
	return _holding.values()


## The teammate holding on to this downed player now, or 0.
func holder_of(target_id: int) -> int:
	for holder: int in _holding:
		if _holding[holder] == target_id:
			return holder
	return 0


## How far a downed player's revive has got, 0 to 1.
func progress(target_id: int) -> float:
	var seconds := _rules.tuning.health.revive_seconds
	return clampf(_time.get(target_id, 0.0) / seconds, 0.0, 1.0)


## The downed player this player is raising now, or 0.
func target_of(player_id: int) -> int:
	return _holding.get(player_id, 0)


## Whether this player is holding on to a downed teammate now.
func is_reviving(player_id: int) -> bool:
	return _holding.has(player_id)


## This player's held `use` this tick: begins, goes on with, or ends their hold.
func hold(player_id: int, use_held: bool) -> void:
	var target := in_reach(player_id) if use_held else 0
	if target == 0:
		stop(player_id, &"released")
		return
	if _holding.get(player_id, 0) != target:
		stop(player_id, &"moved")
		_holding[player_id] = target
		_announce.call({"type": &"revive_started", "player_id": player_id, "target_id": target})
	if not _seen.has(target):
		_seen[target] = player_id


## Ends this player's hold, telling the clients why (`released`, `moved`, `down` or `done`).
func stop(player_id: int, reason: StringName) -> void:
	if not _holding.has(player_id):
		return
	var target: int = _holding[player_id]
	_holding.erase(player_id)
	_announce.call(
		{"type": &"revive_stopped", "player_id": player_id, "target_id": target, "reason": reason}
	)


## A player left: nothing of theirs is held or waited on any more.
func forget(player_id: int) -> void:
	_holding.erase(player_id)
	_time.erase(player_id)


## Ends a tick: adds it to each downed player someone held; one that nobody held starts over. At
## the full time the rules are asked to raise them.
func finish_tick(delta: float) -> void:
	for target_id in _time.keys():
		if not _seen.has(target_id):
			_time.erase(target_id)
	for target_id in _seen:
		_time[target_id] = _time.get(target_id, 0.0) + delta
		if _time[target_id] < _rules.tuning.health.revive_seconds:
			continue
		var reviver: int = _seen[target_id]
		_time.erase(target_id)
		_rules.apply(RulesAction.revive(reviver, target_id))
		for holder in _holding.keys():
			if _holding[holder] == target_id:
				stop(holder, &"done")


func _is_down(player_id: int) -> bool:
	var state: PlayerState = _rules.players.get(player_id)
	return state == null or state.downed
