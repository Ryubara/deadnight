class_name SayBoard
extends RefCounted
## The lines the bots call out (`BotSay`): the server's gate for a `say` action. A line must be one
## of the enumerated ids and a player may say one every `gap` seconds, so a bot that misjudges its
## own cooldowns still cannot flood the feed. Plain data, no clock of its own: time is the `delta`
## the server passes in.

## Seconds before the same player may say another line.
var gap := 4.0

var _wait: Dictionary[int, float] = {}


## The event everyone hears, or an empty dictionary when the line is refused.
func say(player_id: int, line: StringName, subject: int, at: Vector3) -> Dictionary:
	if not BotSay.is_line(line) or _wait.get(player_id, 0.0) > 0.0:
		return {}
	if not at.is_finite():
		return {}
	_wait[player_id] = gap
	return {"type": &"bot_say", "player_id": player_id, "line": line, "subject": subject, "pos": at}


## The same from a `say` action `{line, subject, pos}` (a field it lacks or has of the wrong type
## makes the line refused).
func from_action(player_id: int, action: Dictionary) -> Dictionary:
	var at: Variant = action.get("pos")
	if not at is Vector3:
		return {}
	return say(player_id, StringName(action.get("line", &"")), int(action.get("subject", -1)), at)


## Time passes.
func step(delta: float) -> void:
	for player_id in _wait.keys():
		_wait[player_id] = maxf(_wait[player_id] - delta, 0.0)


func forget(player_id: int) -> void:
	_wait.erase(player_id)
