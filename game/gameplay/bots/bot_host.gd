class_name BotHost
extends RefCounted
## The bots of one night, run together: each tick the server's events go to every bot (each hears
## its own allow-listed share), then every bot decides and sends. It knows nothing of the server:
## a caller hands it the events and each bot a callable to send with, so the same host runs a
## night in the game server, a headless test and a soak.

var bots: Array[BotClient] = []


func add(bot: BotClient) -> BotClient:
	bots.append(bot)
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
