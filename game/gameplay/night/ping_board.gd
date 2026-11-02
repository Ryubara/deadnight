class_name PingBoard
extends RefCounted
## The pings of a night: a player marks a place, a door, an ammunition spot, an enemy or a downed
## teammate, and the others (people and bots alike) see the mark for a while. Plain data, no clock
## of its own: time is the `delta` the server passes in. A player has one mark at a time (a new one
## replaces it) and may place one every `gap` seconds, so a held key is not a flood.
##
## A ping has one meaning each (Back 4 Blood's players asked for ping as an order; Vermintide ruled
## its tag out for tomes because "one tag could mean many things"): `here` hold this place, `door`
## buy this door, `ammo` this is where to buy rounds, `enemy` shoot this one, `downed` raise this
## one.

const HERE := &"here"
const DOOR := &"door"
const AMMO := &"ammo"
const ENEMY := &"enemy"
const DOWNED := &"downed"
## The kinds in wire order (`NetWire.mark` sends the index).
const KINDS: Array[StringName] = [HERE, DOOR, AMMO, ENEMY, DOWNED]

## Seconds a mark stays up.
var seconds := 20.0
## Seconds before the same player may place another.
var gap := 1.0

var _marks: Dictionary[int, Dictionary] = {}
var _wait: Dictionary[int, float] = {}


## Whether this player may place a mark now.
func ready_for(player_id: int) -> bool:
	return _wait.get(player_id, 0.0) <= 0.0


## Puts the mark up (replacing the player's last) and returns it as the event everyone hears.
## `subject` is the thing marked: a door id, a zombie id or a player id; 0 or empty for none.
func place(player_id: int, kind: StringName, at: Vector3, subject: Variant) -> Dictionary:
	_wait[player_id] = gap
	_marks[player_id] = {"kind": kind, "pos": at, "subject": subject, "left": seconds}
	return {
		"type": &"ping_placed",
		"player_id": player_id,
		"kind": kind,
		"pos": at,
		"subject": subject,
		"seconds": seconds,
	}


## Time passes. Returns a `ping_cleared` event for each mark that ran out.
func step(delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for player_id in _wait.keys():
		_wait[player_id] = maxf(_wait[player_id] - delta, 0.0)
	for player_id in _marks.keys():
		_marks[player_id]["left"] -= delta
		if _marks[player_id]["left"] <= 0.0:
			_marks.erase(player_id)
			events.append({"type": &"ping_cleared", "player_id": player_id})
	return events


## Takes a player's mark down (they left).
func forget(player_id: int) -> void:
	_marks.erase(player_id)
	_wait.erase(player_id)


## The marks now up, by the player who placed them, for the frame.
func marks() -> Dictionary:
	var out := {}
	for player_id in _marks:
		out[player_id] = _marks[player_id].duplicate()
	return out
