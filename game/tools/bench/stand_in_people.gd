class_name StandInPeople
extends RefCounted
## More people in a solo night, for the worst-room budget (`--people=N` of `AutopilotRun`, #1193): a
## room seats eight people and seven bots, and one process can hold only one real client, so the
## other people sit down as seats a client would hold (no bot flag: the crowd's table, the looks and
## the HUD count them as people) and play with a bot's brain, which is the most a person's seat can
## cost the server. They hear the night and send their commands as the room's bots do, through
## `NightServer.apply`. Not part of the play.

const SEED := 1193

var night: Night
## The seats it holds, lowest first.
var ids: Array[int] = []


## Seats `count` more people beside the night's player, in the lowest free seats of 1 to
## `NightHost.MAX_PLAYERS`, and puts their brains in the night's bot host (heard and ticked with
## the bots). Returns the helper, which has to be kept as long as the night is.
static func seat(p_night: Night, count: int) -> StandInPeople:
	var helper := StandInPeople.new()
	helper.night = p_night
	var seat_id := 1
	while helper.ids.size() < count and seat_id <= NightHost.MAX_PLAYERS:
		if not p_night.server.rules.players.has(seat_id):
			helper._sit(seat_id)
		seat_id += 1
	return helper


func _sit(player_id: int) -> void:
	ids.append(player_id)
	var events := night.server.apply(
		{"type": NightServer.JOIN, "player_id": player_id, "local": false}
	)
	night.link.broadcast(events)
	var state := ClientState.new()
	state.player_id = player_id
	var profile := BotProfile.for_skill(night.server.rules.settings.bot_skill)
	var client := BotClient.new(
		state,
		profile,
		hash([SEED, player_id]),
		Callable(self, &"_send").bind(player_id),
		night.bots.level
	)
	night.bots.host.add(client, false)


## What the seat's brain sent: to the server as a connection's message; the answers go to the night.
func _send(action: Dictionary, player_id: int) -> void:
	var answers := night.server.apply(action, player_id)
	if not answers.is_empty():
		night.link.broadcast(answers)
