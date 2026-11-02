class_name CrowdCeiling
extends RefCounted
## The most zombies a night stands at once, from the weakest client in it: a browser stands fewer
## than a desktop (`RoundTuning.ceiling_for`). A remote client counts as a browser until it says it
## is not, so a client that never says (an older build) gets the safe number. An operator's cap
## (`limit`, `MAX_ALIVE` on a game server) holds whatever the players are on.

## A cap on the crowd whatever the players are on; 0 is none.
var limit := 0

var _web: Dictionary[int, bool] = {}


## A player came: `web` is whether its client is a browser.
func join(player_id: int, web: bool) -> void:
	_web[player_id] = web


func leave(player_id: int) -> void:
	_web.erase(player_id)


## The client said what it is. Players that never joined are ignored.
func set_platform(player_id: int, web: bool) -> void:
	if _web.has(player_id):
		_web[player_id] = web


## The ceiling now: the browser's when any player is on one (with nobody here, this process's own
## platform), at most the operator's cap.
func value(rounds: RoundTuning) -> int:
	var web := OS.has_feature("web") if _web.is_empty() else _web.values().has(true)
	var ceiling := rounds.ceiling_for(web)
	return mini(ceiling, limit) if limit > 0 else ceiling
