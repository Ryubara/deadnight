class_name BotTeam
extends RefCounted
## What the bots of one night share and no single bot owns: the claims on downed players
## (`BotClaims`), and later the roles and the errand turn. The host makes one and hands the same to
## every bot it seats (like `BotHost.bot_ids`), so a lone `BotClient` in a test has a team of its
## own. Plain data: nothing here reads a frame or the rules.

var claims := BotClaims.new()
## The place each roaming bot is walking to (`BotRoam`), by player id, so two do not pick one.
var roam: Dictionary = {}


## A bot left the team (its seat was taken by a person, or it was removed): what it held is open.
func release(bot: int) -> void:
	claims.release(bot)
	roam.erase(bot)
