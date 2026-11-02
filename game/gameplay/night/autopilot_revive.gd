class_name AutopilotRevive
extends RefCounted
## When the bot pulls a teammate up. It sees what a client sees: the frame's players (where they
## are, whether they are down, their bleed-out clock, who holds the revive on them) and the
## zombies. The rules are the ones a careful player uses (docs/design/revive.md, Bots): it goes to
## a downed teammate only when no zombie is near the body, only when the clock leaves time for the
## walk and the hold, never to one somebody else is reviving, and it lets go of a hold when a
## zombie comes within reach. Otherwise the bot fights as it always does, and the revive waits for
## a clear moment.

## Metres: no zombie nearer than this to the body, or the bot clears them first.
var safe_radius := 7.0
## Metres: a zombie this near the bot ends a hold and the bot fights.
var abort_radius := 3.0
## Metres a bot walks in a second when judging whether the clock leaves time for the walk (below
## the real run speed on purpose).
var walk_speed := 4.0
## The revive's reach and hold time, from the shared tuning table.
var reach := 2.0
var seconds := 3.5


## The player to revive now (an id), or 0 for nobody. `zombies` are the client's decoded zombies.
func choose(frame: Dictionary, me: int, here: Vector3, zombies: Array[Dictionary]) -> int:
	var players: Dictionary = frame.get("players", {})
	if not players.has(me) or players[me].get("downed", true):
		return 0
	var best := 0
	var best_apart := INF
	for id: int in players:
		if id == me or not _is_patient(players[id], me):
			continue
		var apart := _flat(here, players[id]["pos"])
		if apart >= best_apart or not _has_time(players[id], me, apart):
			continue
		if not _is_safe(players[id], me, here, zombies):
			continue
		best = id
		best_apart = apart
	return best


## Whether the player is downed, alive and not being revived by somebody else.
func _is_patient(player: Dictionary, me: int) -> bool:
	if not player.get("downed", false) or player.get("dead", false):
		return false
	var holder: int = player.get("reviver", 0)
	return holder == 0 or holder == me


## Whether the clock leaves time to walk there and hold (a hold already begun needs only the rest).
func _has_time(player: Dictionary, me: int, apart: float) -> bool:
	if player.get("reviver", 0) == me:
		return true
	var walk := maxf(apart - reach, 0.0) / walk_speed
	return float(player.get("bleed", 0.0)) > walk + seconds


## Whether no zombie stands near the body (to start) and none within reach of the bot (to go on).
func _is_safe(player: Dictionary, me: int, here: Vector3, zombies: Array[Dictionary]) -> bool:
	var holding: bool = player.get("reviver", 0) == me
	var around := abort_radius if holding else safe_radius
	for zombie in zombies:
		if zombie["mode"] == ZombieBody.Mode.DYING or zombie["mode"] == ZombieBody.Mode.EMERGING:
			continue
		if _flat(here, zombie["position"]) < abort_radius:
			return false
		if _flat(player["pos"], zombie["position"]) < around:
			return false
	return true


## Whether the bot is near enough to hold the revive (a little inside the server's reach).
func in_reach(here: Vector3, there: Vector3) -> bool:
	return _flat(here, there) <= reach - 0.2


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
