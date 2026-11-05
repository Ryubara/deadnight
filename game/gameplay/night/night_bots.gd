class_name NightBots
extends RefCounted
## The bots of one live night, seated beside the people: the one place that decides how many, in
## which seats, and what happens when a person comes to a seat a bot holds. Solo (`Night`) and a
## room (`NightHost`) both use it, so the rule is written once.
##
## A bot is a client (`BotClient`): it hears the events a person's client gets, and sends commands
## through `NightServer.apply` like a socket, so nothing here changes how a bot plays. This class
## only seats and unseats them and runs the `BotHost` each tick.
##
## The count: `MatchSettings.bots` (0 to 7) is the most, cut only by the server's own limits
## (`limit`). Bots hold no seat of the room: the 8 of `NightHost.MAX_PLAYERS` are people alone,
## and a bot's id starts at `FIRST_ID`, so it never collides with a person's whatever the number
## of people and however they come and go (#1179). `docs/design/rounds.md#bots`.

## The id of the first bot. A person's id is 1 to `NightHost.MAX_PLAYERS`; the bots are
## `FIRST_ID` to `FIRST_ID + MatchSettings.MAX_BOTS - 1`, the lowest free one first.
const FIRST_ID := 101

var host := BotHost.new()
var server: NightServer
var level: BotLevel
## The most bots this night may seat, whatever the setting asks: a game server's cap per room, its
## share of the bots all rooms may run, or 0 for the kill-switch (`ServerConfig`). A lowered limit
## sends bots away on the next `fill`. Solo has no cap beyond the setting.
var limit := MatchSettings.MAX_BOTS

## Called with the events the server answered a bot's command with (a ping, a callout), for whoever
## carries events to the people.
var _deliver: Callable
var _seed: int
## Seat id -> name of the bot there.
var _names: Dictionary = {}
## Held here: a Callable does not keep its RefCounted alive.
var _probe: WorldProbe


func _init(p_server: NightServer, p_world: NightWorld, p_seed: int, p_deliver: Callable) -> void:
	server = p_server
	_seed = p_seed
	_deliver = p_deliver
	_probe = WorldProbe.new(p_world.get_world_3d().direct_space_state)
	level = BotLevel.new(
		_probe.callable(), p_world.is_lit, server.rules.tuning.rounds, p_world.map()
	)
	# The level gives the bots the shop too: they buy doors, boards and fuel as a person does.
	LotBotData.fill(level, p_world, server.rules.tuning, server.rules.settings)


## How many bots a night seats for the setting `wanted`: never more than the setting (the setting's
## own maximum at most) and never more than the server's `cap` (the room's limit; the setting's own
## maximum when there is none). The people do not change it: a bot takes no one's place.
static func target(wanted: int, cap: int = MatchSettings.MAX_BOTS) -> int:
	var asked := clampi(wanted, MatchSettings.MIN_BOTS, MatchSettings.MAX_BOTS)
	return mini(asked, maxi(cap, 0))


## The id of the `index`th bot (0 to `MatchSettings.MAX_BOTS - 1`).
static func id_at(index: int) -> int:
	return FIRST_ID + index


## Whether `player_id` is in the range bots have, whoever holds it now.
static func is_bot_id(player_id: int) -> bool:
	return player_id >= FIRST_ID


## The name the bot with id `player_id` wears in a room of `skill` (the lobby shows it before the
## night begins): the skill's cast (`BotRoster`), by the bot's number in the night (1 to 7).
static func name_for(player_id: int, skill: int = MatchSettings.DEFAULT_SKILL) -> String:
	return BotRoster.name_for(skill, number_of(player_id))


## The bot's number in the night, 1 for the first bot: what the roster's cast is picked by.
static func number_of(player_id: int) -> int:
	return player_id - FIRST_ID + 1


## The ids the bots hold, lowest first.
func seats() -> Array[int]:
	var out: Array[int] = []
	for bot in host.bots:
		out.append(bot.state.player_id)
	out.sort()
	return out


func count() -> int:
	return host.bots.size()


func holds(player_id: int) -> bool:
	return host.bot_ids.has(player_id)


## The names of the bots' seats, seat id -> name, for a WELCOME.
func names() -> Dictionary:
	return _names.duplicate()


## Seats bots until there are `target(wanted, limit)`, each in the lowest free bot id; sends the
## highest ids' bots away when there are more than that (a limit that was lowered). Returns the
## events it caused, each bot's name first, so the first notice already reads its name.
func fill(wanted: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var goal := target(wanted, limit)
	while count() > goal:
		events.append_array(_send_away(seats().back()))
	while count() < goal:
		events.append_array(_seat(_lowest_free()))
	return events


## What the server said, to every bot (each hears its own share).
func hear(events: Array) -> void:
	host.hear(events)


## One tick of every bot: each decides and sends.
func tick(delta: float) -> void:
	host.tick(delta)


## The bot at `player_id` leaves the night: it stops deciding, what it claimed is open, and its seat
## is gone from the rules.
func _send_away(player_id: int) -> Array[Dictionary]:
	host.release(player_id)
	_names.erase(player_id)
	return server.apply({"type": NightServer.LEAVE, "player_id": player_id})


func _seat(player_id: int) -> Array[Dictionary]:
	var name_text := name_for(player_id, server.rules.settings.bot_skill)
	var events: Array[Dictionary] = [
		{"type": &"player_named", "player_id": player_id, "name": name_text}
	]
	events.append_array(
		server.apply(
			{"type": NightServer.JOIN, "player_id": player_id, "local": false, "bot": true}
		)
	)
	events.append_array(_enlist(player_id))
	return events


## Gives the bot `player_id` (already in the rules, its name told before the join) its client: the
## skill's look and a place in the host.
func _enlist(player_id: int) -> Array[Dictionary]:
	var skill := server.rules.settings.bot_skill
	var events: Array[Dictionary] = []
	_names[player_id] = name_for(player_id, skill)
	# The bot wears its own look the way a person's reaches the server, so every client gets it.
	var packet := LookWire.look(BotRoster.look_for(skill, number_of(player_id)))
	events.append_array(
		server.apply({"type": NightServer.LOOK, "player_id": player_id, "packet": packet})
	)
	var state := ClientState.new()
	state.player_id = player_id
	var bot := BotClient.new(
		state, _profile(), hash([_seed, player_id]), Callable(self, &"_send").bind(player_id), level
	)
	host.add(bot)
	return events


## Every bot of the night plays the room's skill (`MatchSettings.bot_skill`).
func _profile() -> BotProfile:
	return BotProfile.for_skill(server.rules.settings.bot_skill)


## The lowest bot id no bot holds.
func _lowest_free() -> int:
	var id := FIRST_ID
	while holds(id):
		id += 1
	return id


## What a bot sends: plain data, to the server as a connection's message from `player_id`. (A
## callable to a method, not a lambda: a lambda naming a member would keep this object alive.)
func _send(action: Dictionary, player_id: int) -> void:
	var answers := server.apply(action, player_id)
	if not answers.is_empty() and _deliver.is_valid():
		_deliver.call(answers)
