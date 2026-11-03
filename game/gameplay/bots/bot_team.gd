class_name BotTeam
extends RefCounted
## What the bots of one night share and no single bot owns: the claims on downed players
## (`BotClaims`), the errand turn (`BotTurn`) and the roles (`BotRoles`). The host makes one and
## hands the same to every bot it seats (like `BotHost.bot_ids`), so a lone `BotClient` in a test
## has a team of its own. Plain data: nothing here reads a frame or the rules.

var claims := BotClaims.new()
## The flares burning now, as `{point, radius, until, shooter}` (the clock of the bots, all the same
## step): the dead within a flare's radius walk to it, so a bot judging a revive counts them as far.
var lures: Array[Dictionary] = []
## Whose turn it is to go on an errand (one bot at a time).
var turn := BotTurn.new()
## Whether the errands go one bot at a time (off only to measure what the turn costs).
var one_errand_at_a_time := true
## What each bot is for now: anchor, flank or maintainer.
var roles := BotRoles.new()


## A flare began to burn (a bot fired it and heard it burst).
func add_lure(point: Vector3, radius: float, until: float, shooter: int) -> void:
	lures.append({"point": point, "radius": radius, "until": until, "shooter": shooter})


## The flares still burning at `now`; the ones that went out are forgotten.
func active_lures(now: float) -> Array[Dictionary]:
	lures = lures.filter(func(lure: Dictionary) -> bool: return float(lure["until"]) > now)
	return lures


## A bot left the team (its seat was taken by a person, or it was removed): what it held is open.
func release(bot: int) -> void:
	claims.release(bot)
	turn.release(bot)
