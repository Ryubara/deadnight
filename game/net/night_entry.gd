class_name NightEntry
extends RefCounted
## One row of the Server Browser: a public night as the backend lists it (`GET /lobbies`,
## `TogetherApi.list_nights`,
## docs/design/lobby.md#the-list-of-nights-the-server-browsers-data-1179), with the words a player
## reads for it. A night is either a **lobby** that waits for its host or a **match** in progress;
## both are joined the same way, by the row's code.
##
## The people count is people only, out of the night's seats: a bot holds no seat, so the bots the
## host set are a separate note and never part of "3 of 8".

enum Kind { LOBBY, MATCH }

var id := ""
## The code a press joins by (`TogetherApi.join_code`).
var code := ""
var map_id := ""
var host_name := ""
var players := 0
var max_players := NightHost.MAX_PLAYERS
var bots := 0
var kind := Kind.LOBBY
## The round a match is in; 0 until the game server has said one (and for a lobby that waits).
var round_number := 0
var full := false


## The rows of an answer of `TogetherApi.list_nights`, in the order the backend gave them (room
## first, then the most people, then the newest); rows that are not rows are left out.
static func parse(answer: Dictionary) -> Array[NightEntry]:
	var out: Array[NightEntry] = []
	var rows: Variant = answer.get("nights", [])
	if typeof(rows) != TYPE_ARRAY:
		return out
	for row: Variant in rows:
		if typeof(row) == TYPE_DICTIONARY:
			var entry := from_row(row)
			if entry.code != "":
				out.append(entry)
	return out


static func from_row(row: Dictionary) -> NightEntry:
	var entry := NightEntry.new()
	entry.id = str(row.get("id", ""))
	entry.code = str(row.get("code", ""))
	entry.map_id = str(row.get("map", MapRegistry.DEFAULT))
	entry.host_name = str(row.get("hostName", ""))
	entry.max_players = maxi(1, int(row.get("maxPlayers", NightHost.MAX_PLAYERS)))
	entry.players = clampi(int(row.get("players", 0)), 0, entry.max_players)
	entry.bots = maxi(0, int(row.get("bots", 0)))
	var started: bool = (
		str(row.get("kind", "")) == "match" or str(row.get("state", "")) == "started"
	)
	entry.kind = Kind.MATCH if started else Kind.LOBBY
	var round_value: Variant = row.get("round")
	entry.round_number = int(round_value) if round_value != null and started else 0
	entry.full = bool(row.get("full", false)) or entry.players >= entry.max_players
	return entry


func is_match() -> bool:
	return kind == Kind.MATCH


## The map the night is on (the default map for one the game does not know).
func map() -> MapInfo:
	return MapRegistry.of(map_id)


## `3 of 8`: the people in the night, bots not counted.
func people_text() -> String:
	return "%d of %d" % [players, max_players]


## Which of the two it is, in words: a waiting room or a night in progress with its round.
func state_text() -> String:
	if full and not is_match():
		return "Waiting room, full"
	if not is_match():
		return "Waiting to start"
	if round_number > 0:
		return "In progress, round %d" % round_number
	return "In progress"


## The one word on the row's badge.
func badge_text() -> String:
	if full:
		return "FULL"
	return "IN PROGRESS" if is_match() else "WAITING"


func host_text() -> String:
	return "Hosted by %s" % host_name if host_name != "" else ""


## `+3 bots`, or nothing: the bots are not people and hold no seat.
func bots_text() -> String:
	if bots <= 0:
		return ""
	return "+%d bot%s" % [bots, "" if bots == 1 else "s"]


## What a screen reader says for the row.
func spoken() -> String:
	var parts: Array[String] = [map().title, state_text(), "%s people" % people_text()]
	if host_name != "":
		parts.append(host_text())
	if bots > 0:
		parts.append(bots_text())
	parts.append("Full" if full else "Press to join")
	return ". ".join(parts)


## Whether `other` shows the same thing (the screen draws a row again only when this is false).
func same_as(other: NightEntry) -> bool:
	return (
		other != null
		and id == other.id
		and code == other.code
		and map_id == other.map_id
		and host_name == other.host_name
		and players == other.players
		and max_players == other.max_players
		and bots == other.bots
		and kind == other.kind
		and round_number == other.round_number
		and full == other.full
	)
