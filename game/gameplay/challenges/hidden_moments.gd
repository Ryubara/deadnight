class_name HiddenMoments
extends RefCounted
## The stats the hidden challenges need (`docs/design/progression.md#the-hidden-challenges`):
## a whole break at the stand, a round reached with the map's second door still shut, a death in the
## first round, and a night that ends with the same four or more people it began with. A part of
## `NightMoments` (which hands it the events in `LISTENS` and the tally to credit), kept apart so
## the odd stats and these stay small; it reads no game object either: positions, doors and rounds
## are in the events a client hears.
##
## Where the stand is and which door is the second are data lines (`ChallengeAreas`). A person is a
## seat no bot plays (`player_added.bot`, `bot_replaced`, `bot_seated`), as for *Two's company*.
##
## What it costs: a frame adds a rectangle test and a flag a player; every other event it listens to
## is rare (a break, a round, a door, a death, the night's end).

## The events this listens to (`NightMoments.LISTENS` has them too; the tally passes nothing else).
const LISTENS: Dictionary[StringName, bool] = {
	&"frame": true,
	&"player_added": true,
	&"bot_replaced": true,
	&"bot_seated": true,
	&"door_opened": true,
	&"break_started": true,
	&"round_started": true,
	&"player_died": true,
	&"game_over": true,
}
## Standing room only: this many people at the least, the same ones from the first round to the end.
const FULL_LOT := 4
## Why the night ended with everyone down: nobody was left to get a downed player up.
const ALL_DOWN := &"all_down"

var _map := ""
var _stand := PackedFloat32Array()
var _second_door: StringName = &""
var _round := 0
var _bots: Dictionary[int, bool] = {}
## Player id -> whether the last frame had them at the stand.
var _at_stand: Dictionary[int, bool] = {}
## A break between two rounds is on, and how many frames it has had.
var _in_break := false
var _break_frames := 0
## The players at the stand since the break began, and not once out of it.
var _whole: Dictionary[int, bool] = {}
var _door_open := false
## Player id -> true, for each who died this night, so the night's end does not count it twice.
var _died: Dictionary[int, bool] = {}
## The people in the lot when the first round began (ids, sorted).
var _opening_people: Array[int] = []


## Says what map the night is on (`MapRegistry` id, "" for the default one).
func set_map(map_id: String) -> void:
	_map = map_id
	_stand = ChallengeAreas.rect(map_id, ChallengeAreas.STAND)
	_second_door = ChallengeAreas.second_door(map_id)


## Says whether a bot plays the seat.
func set_bot(player_id: int, bot: bool) -> void:
	_bots[player_id] = bot


## A new night: what was counted is forgotten; who is a bot and the map are kept.
func reset() -> void:
	_round = 0
	_in_break = false
	_break_frames = 0
	_door_open = false
	_at_stand.clear()
	_whole.clear()
	_died.clear()
	_opening_people.clear()


## A person takes a seat that was another's: what the earlier player did is not theirs.
func forget(player_id: int) -> void:
	_at_stand.erase(player_id)
	_whole.erase(player_id)
	_died.erase(player_id)


func observe(event: Dictionary, tally: NightTally) -> void:
	match event["type"]:
		&"frame":
			_on_frame(event)
		&"player_added":
			_bots[int(event["player_id"])] = event.get("bot", false)
		&"bot_replaced":
			_bots[int(event["player_id"])] = false
		&"bot_seated":
			_bots[int(event["player_id"])] = true
		&"door_opened":
			if event["door_id"] == _second_door:
				_door_open = true
		&"break_started":
			_on_break_started(int(event["next_round"]), tally)
		&"round_started":
			_on_round_started(int(event["round"]), tally)
		&"player_died":
			_on_died(int(event["player_id"]), tally)
		&"game_over":
			_on_game_over(event, tally)


func _on_frame(event: Dictionary) -> void:
	if event.has("round"):
		_round = int(event["round"])
	if _second_door != &"" and event.has("doors") and (event["doors"] as Array).has(_second_door):
		_door_open = true
	if _stand.size() != 4:
		return
	if _in_break:
		_break_frames += 1
	var players: Dictionary = event.get("players", {})
	for id: int in players:
		var fields: Dictionary = players[id]
		if not fields.has("pos"):
			continue
		var inside := ChallengeAreas.contains(_stand, fields["pos"])
		_at_stand[id] = inside
		if _in_break and not inside:
			_whole.erase(id)


## A break between two rounds begins: who is at the stand now may keep it whole. The wait before
## the first round (the intro, `next_round` 1) is no break between rounds.
func _on_break_started(next_round: int, tally: NightTally) -> void:
	_in_break = next_round > 1 and _stand.size() == 4
	_break_frames = 0
	_whole.clear()
	if not _in_break:
		return
	for id in tally.present_ids():
		if _at_stand.get(id, false):
			_whole[id] = true


func _on_round_started(round_number: int, tally: NightTally) -> void:
	_round = round_number
	if _in_break and _break_frames > 0:
		for id in _whole:
			if tally.is_present(id):
				tally.credit(id, ChallengeStats.BREAKS_STAND)
	_in_break = false
	_whole.clear()
	if round_number == 1:
		_opening_people = _people(tally)
	if _second_door != &"" and not _door_open:
		for id in tally.present_ids():
			tally.reach(id, ChallengeStats.ROUND_LONG_WAY, round_number)


func _on_died(player_id: int, tally: NightTally) -> void:
	if _round == 1:
		_die(player_id, tally)


func _die(player_id: int, tally: NightTally) -> void:
	if not _died.has(player_id):
		_died[player_id] = true
		tally.credit(player_id, ChallengeStats.DEATHS_ROUND_ONE)


## The night ended. In the first round with everyone down, each who was in the lot died in it
## (unless the bleed-out already said so); with the same four or more people as the first round
## began with, it was a full house.
func _on_game_over(event: Dictionary, tally: NightTally) -> void:
	_in_break = false
	if event.get("reason", &"") == ALL_DOWN and int(event.get("round_reached", 0)) == 1:
		for id in tally.present_ids():
			_die(id, tally)
	var people := _people(tally)
	if people.size() >= FULL_LOT and people == _opening_people:
		for id in people:
			tally.credit(id, ChallengeStats.NIGHTS_FULL_LOT)


## The people (no bot) in the lot now, by id.
func _people(tally: NightTally) -> Array[int]:
	var people: Array[int] = []
	for id in tally.present_ids():
		if not _bots.get(id, false):
			people.append(id)
	people.sort()
	return people
