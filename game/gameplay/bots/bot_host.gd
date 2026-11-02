class_name BotHost
extends RefCounted
## The bots of one night, run together: each tick the server's events go to every bot (each hears
## its own allow-listed share), then every bot decides and sends. It knows nothing of the server:
## a caller hands it the events and each bot a callable to send with, so the same host runs a
## night in the game server, a headless test and a soak.

var bots: Array[BotClient] = []
## The seats that are bots by player id, shared with every bot (the roster labels them).
var bot_ids: Dictionary = {}


## Seats a bot. A client that is run on the host but stands for a person (a test's stand-in for a
## human player) is added with `is_bot` false: the others take it for a person.
func add(bot: BotClient, is_bot: bool = true) -> BotClient:
	bots.append(bot)
	bot.bot_ids = bot_ids
	if is_bot:
		bot_ids[bot.state.player_id] = true
	return bot


## The events of one server step, to every bot.
func hear(events: Array) -> void:
	for bot in bots:
		bot.hear(events)


## One tick of every bot, in seat order; each sends its command.
func tick(delta: float) -> void:
	for bot in bots:
		bot.tick(delta)


## The hash of everything every bot has sent: one number for a night's worth of commands.
func command_hash() -> int:
	var all: Array[int] = []
	for bot in bots:
		all.append(bot.telemetry.command_hash)
	return hash(all)
