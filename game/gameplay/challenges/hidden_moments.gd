class_name HiddenMoments
extends RefCounted
## The stats the hidden challenges need (`docs/design/progression.md#the-hidden-challenges`):
## a whole break at the stand, a round reached with the map's second door still shut, a death in the
## first round, and a night that ends with the same four or more people it began with. A part of
## `NightMoments` (which calls it for the events it needs, with the tally to credit), kept apart so
## the odd stats and these stay small; it reads no game object either: positions, doors and rounds
## are in the events a client hears.
##
## Where the stand is and which door is the second are data lines (`ChallengeAreas`). A person is a
## seat no bot plays (`player_added.bot`, `bot_replaced`, `bot_seated`), as for *Two's company*.
##
## What it costs: nothing in the events it does not listen to, and nothing in a frame outside a
## break. `NightMoments` calls the few methods below from its own arms for the rare events (a door,
## a break, a round, a death, the night's end) and forwards a frame (`on_break_frame`) only while a
## break is on. It keeps no frame: a reference to the last one made the next frame's release (a
## whole tree of dictionaries) fall inside the tracker's timer, a quarter more `server.challenges`
## in the late-round budget for work that only moved there.

## Standing room only: this many people at the least, the same ones from the first round to the end.
const FULL_LOT := 4
## Why the night ended with everyone down: nobody was left to get a downed player up.
const ALL_DOWN := &"all_down"

## Player id -> whether a bot plays the seat: `NightMoments`' own, shared (it hears who is a bot).
var bots: Dictionary[int, bool] = {}
## The doors bought so far: `NightMoments`' own, shared (it reads them from the frames and buys).
var doors_open: Dictionary[StringName, bool] = {}
## A break between two rounds is on (`NightMoments` forwards its frames meanwhile), and how many
## frames it has had.
var in_break := false

var _map := ""
var _stand := PackedFloat32Array()
var _second_door: StringName = &""
var _round := 0
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


## A new night: what was counted is forgotten; who is a bot and the map are kept.
func reset() -> void:
	_round = 0
	in_break = false
	_break_frames = 0
	_door_open = false
	_whole.clear()
	_died.clear()
	_opening_people.clear()


## A person takes a seat that was another's: what the earlier player did is not theirs.
func forget(player_id: int) -> void:
	_whole.erase(player_id)
	_died.erase(player_id)


## The second door was bought.
func door_opened(door_id: StringName) -> void:
	if door_id == _second_door:
		_door_open = true


## A frame of a break. The first one says who is at the stand (a tick after the break began); each
## later one drops whoever is not.
func on_break_frame(event: Dictionary) -> void:
	_break_frames += 1
	var players: Dictionary = event.get("players", {})
	for id: int in players:
		var fields: Dictionary = players[id]
		var inside := fields.has("pos") and ChallengeAreas.contains(_stand, fields["pos"])
		if inside and _break_frames == 1:
			_whole[id] = true
		elif not inside:
			_whole.erase(id)


## A break between two rounds begins. The wait before the first round (the intro, `next_round` 1)
## is no break between rounds.
func break_started(next_round: int) -> void:
	in_break = next_round > 1 and _stand.size() == 4
	_break_frames = 0
	_whole.clear()


func round_started(round_number: int, tally: NightTally) -> void:
	_round = round_number
	if in_break and _break_frames > 0:
		for id in _whole:
			if tally.is_present(id):
				tally.credit(id, ChallengeStats.BREAKS_STAND)
	in_break = false
	_whole.clear()
	if _second_door != &"" and doors_open.has(_second_door):
		_door_open = true
	if round_number == 1:
		_opening_people = _people(tally)
	if _second_door != &"" and not _door_open:
		for id in tally.present_ids():
			tally.reach(id, ChallengeStats.ROUND_LONG_WAY, round_number)


func died(player_id: int, tally: NightTally) -> void:
	if _round == 1:
		_die(player_id, tally)


func _die(player_id: int, tally: NightTally) -> void:
	if not _died.has(player_id):
		_died[player_id] = true
		tally.credit(player_id, ChallengeStats.DEATHS_ROUND_ONE)


## The night ended. In the first round with everyone down, each who was in the lot died in it
## (unless the bleed-out already said so); with the same four or more people as the first round
## began with, it was a full house.
func game_over(event: Dictionary, tally: NightTally) -> void:
	in_break = false
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
		if not bots.get(id, false):
			people.append(id)
	people.sort()
	return people
