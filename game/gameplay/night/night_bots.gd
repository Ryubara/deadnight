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
## The count: `MatchSettings.bots` (0 to 3) is the most; in a room it is also bounded by the seats
## the people leave free (`target`). Bots take the highest free seat numbers, so the people's
## lowest-numbered seats stay theirs, and a person who finds no free seat takes the lowest bot's
## seat as it stands (`hand_over`): the same body, points and weapons, the round goes on.
## `docs/design/rounds.md#bots`.

## Seats in a night: the room's capacity (`NightHost.MAX_PLAYERS`, which a test holds equal; the
## host's script is not named here so the two do not need each other to load).
const SEATS := 4

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
	LotBotData.fill(level, p_world, server.rules.tuning)


## How many bots a night with `people` people in it seats for the setting `wanted`: never more than
## the setting, never more than the seats the people leave free, never more than the server's
## `cap` (the room's limit; the setting's own maximum when there is none).
static func target(wanted: int, people: int, cap: int = MatchSettings.MAX_BOTS) -> int:
	var asked := clampi(wanted, MatchSettings.MIN_BOTS, MatchSettings.MAX_BOTS)
	return mini(mini(asked, maxi(cap, 0)), maxi(SEATS - people, 0))


## The name the bot at seat `player_id` wears in a room of `skill` (the lobby shows it before the
## night begins): the skill's cast (`BotRoster`).
static func name_for(player_id: int, skill: int = MatchSettings.DEFAULT_SKILL) -> String:
	return BotRoster.name_for(skill, player_id)


## Whether the night has room for one more bot than it has, for the setting `wanted` and `people`
## people who hold seats.
func wants_more(wanted: int, people: int) -> bool:
	return count() < target(wanted, people, limit)


## The seats the bots hold, lowest first.
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


## Seats bots until there are `target(wanted, people.size(), limit)`, in the highest seat numbers
## `people` (the seats held by people, away or not) leave free; sends the highest seats' bots away
## when there are more than that (a limit that was lowered). Returns the events it caused, each
## seat's name first, so the first notice already reads its name.
func fill(wanted: int, people: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var goal := target(wanted, people.size(), limit)
	while count() > goal:
		events.append_array(_send_away(seats().back()))
	while count() < goal:
		var id := _highest_free(people)
		if id == 0:
			break
		events.append_array(_seat(id))
	return events


## The seat a person takes when a bot holds it: the bot leaves, the seat goes on as it stands, and
## the rules say `bot_replaced`. Returns those events; empty when no bot holds the seat.
func hand_over(player_id: int) -> Array[Dictionary]:
	if not holds(player_id):
		return []
	host.release(player_id)
	_names.erase(player_id)
	return server.apply({"type": NightServer.SEAT_PERSON, "player_id": player_id})


## The seat of a person who left goes to a bot as it stands (decision 7 of the research: the slot
## is inherited both ways): the same body, points, weapons and health, a name and a look of the
## room's cast, and the rules say `bot_seated`. Returns those events. Empty, and nothing changed,
## when the seat is already a bot's or is no one's.
func adopt(player_id: int) -> Array[Dictionary]:
	var seat: PlayerState = server.rules.players.get(player_id)
	if seat == null or seat.bot or holds(player_id):
		return []
	var events: Array[Dictionary] = server.apply(
		{"type": NightServer.SEAT_BOT, "player_id": player_id}
	)
	events.append_array(_enlist(player_id))
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
	events.append_array(_enlist(player_id, false))
	return events


## Gives the seat `player_id` (already a bot's in the rules) its client: the cast's name (told, when
## `tell_name`), the skill's look, and a place in the host. The name goes before the join for a new
## bot (so the first notice reads it), after the seat change for an adopted one.
func _enlist(player_id: int, tell_name := true) -> Array[Dictionary]:
	var skill := server.rules.settings.bot_skill
	var events: Array[Dictionary] = []
	var name_text := name_for(player_id, skill)
	_names[player_id] = name_text
	if tell_name:
		events.append({"type": &"player_named", "player_id": player_id, "name": name_text})
	# The bot wears its own look the way a person's reaches the server, so every client gets it.
	var packet := LookWire.look(BotRoster.look_for(skill, player_id))
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


## The seat number highest among those neither people nor bots hold, or 0.
func _highest_free(people: Array) -> int:
	for id in range(SEATS, 0, -1):
		if not people.has(id) and not holds(id):
			return id
	return 0


## What a bot sends: plain data, to the server as a connection's message from `player_id`. (A
## callable to a method, not a lambda: a lambda naming a member would keep this object alive.)
func _send(action: Dictionary, player_id: int) -> void:
	var answers := server.apply(action, player_id)
	if not answers.is_empty() and _deliver.is_valid():
		_deliver.call(answers)
