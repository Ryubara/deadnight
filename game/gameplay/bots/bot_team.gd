class_name BotTeam
extends RefCounted
## What the bots of one night share and no single bot owns: the claims on downed players
## (`BotClaims`), the errand turn (`BotTurn`) and the roles (`BotRoles`). The host makes one and
## hands the same to every bot it seats (like `BotHost.bot_ids`), so a lone `BotClient` in a test
## has a team of its own. Plain data: nothing here reads a frame or the rules.

var claims := BotClaims.new()
## Whose turn it is to go on an errand (one bot at a time).
var turn := BotTurn.new()
## Whether the errands go one bot at a time (off only to measure what the turn costs).
var one_errand_at_a_time := true
## What each bot is for now: anchor, flank or maintainer.
var roles := BotRoles.new()


## A bot left the team (its seat was taken by a person, or it was removed): what it held is open.
func release(bot: int) -> void:
	claims.release(bot)
	turn.release(bot)
