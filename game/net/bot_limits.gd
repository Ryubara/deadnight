class_name BotLimits
extends RefCounted
## What a game server lets its rooms do with bots, whatever the hosts' settings ask
## (`ServerConfig`: `MAX_BOTS`, `BOTS_OFF`, `BOT_BUDGET`). Three levers, one answer per room: how
## many bots it may seat now. A bot costs a share of the 60 Hz tick (about 0.1 ms:
## `docs/research/bots.md#server-cost`), and the process runs its rooms in one thread, so the
## operator can cap them per room, share a budget of bots among the open rooms, or switch them
## all off without touching a ticket.

## The most bots one room may seat (0 to `MatchSettings.MAX_BOTS`).
var per_room := MatchSettings.MAX_BOTS
## The kill-switch: no room seats a bot, and the bots standing leave on the room's next fill.
var off := false
## The most bots in all the rooms of the process together; 0 is no budget.
var budget := 0


## The limits an environment asks for.
static func from_config(config: ServerConfig) -> BotLimits:
	var out := BotLimits.new()
	out.per_room = clampi(config.max_bots, 0, MatchSettings.MAX_BOTS)
	out.off = config.bots_off
	out.budget = maxi(config.bot_budget, 0)
	return out


## How many bots a room may seat while `rooms` rooms are open: the kill-switch is zero, else the
## per-room cap, cut to the room's share of the budget (the budget over the rooms, rounded down).
func for_room(rooms: int) -> int:
	if off:
		return 0
	if budget <= 0:
		return per_room
	return mini(per_room, budget / maxi(rooms, 1))
