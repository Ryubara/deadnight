class_name CrowdCeiling
extends RefCounted
## The most zombies a night stands at once, from the weakest client in it: a browser stands fewer
## than a desktop (`RoundTuning.ceiling_for`). A remote client counts as a browser until it says it
## is not, so a client that never says (an older build) gets the safe number. An operator's cap
## (`limit`, `MAX_ALIVE` on a game server) holds whatever the players are on. Bound to the night's
## rules and zombie sim, it sets their cap and hard cap, one number, whenever anything changes.

## A cap on the crowd whatever the players are on; 0 is none. Setting it applies at once.
var limit := 0:
	set(count):
		limit = maxi(count, 0)
		apply()

var _web: Dictionary[int, bool] = {}
var _rules: GameRules
var _sim: ZombieSim


func bind(rules: GameRules, sim: ZombieSim) -> void:
	_rules = rules
	_sim = sim
	apply()


## A player came: `web` is whether its client is a browser.
func join(player_id: int, web: bool) -> void:
	_web[player_id] = web
	apply()


func leave(player_id: int) -> void:
	_web.erase(player_id)
	apply()


## The client said what it is. Players that never joined are ignored.
func set_platform(player_id: int, web: bool) -> void:
	if _web.has(player_id):
		_web[player_id] = web
		apply()


## The ceiling now: the browser's when any player is on one (with nobody here, this process's own
## platform), at most the operator's cap.
func value(rounds: RoundTuning) -> int:
	var web := OS.has_feature("web") if _web.is_empty() else _web.values().has(true)
	var ceiling := rounds.ceiling_for(web)
	return mini(ceiling, limit) if limit > 0 else ceiling


## Gives the rules and the sim the ceiling.
func apply() -> void:
	if _rules == null:
		return
	var ceiling := value(_rules.tuning.rounds)
	_rules.crowd_ceiling = ceiling
	_sim.tuning.hard_cap = ceiling
