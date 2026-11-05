class_name ReportTracker
extends RefCounted
## What the night report needs from the night, kept as the night is heard (`NightReport` makes the
## card). It reads the same events every client hears and adds no XP of its own:
##
## - A seat the server keeps an account for (`ClientState.levels` holds it: a game server's WELCOME,
##   or the local rules of a signed-in solo night) is told its XP as `xp_gained` events; their
##   `sources` are added up here, so the card is the server's own tally.
## - A seat nobody keeps (no account at all, the backend could not be reached) is told nothing, so
##   the night is counted here the way `XpRules` would have paid it (`NightTally`, the rules'
##   `worth`), and the card says nothing was saved.
##
## A poster set the local player finished (`poster_set_done`, told by a game server or, in a night
## that runs here, by `ChallengeSession` as the same event) is kept once and shown on the card.
##
## It counts nothing for a seat the server keeps, so an online account pays this client no
## per-kill work beyond one dictionary read.

## The card changed: an `xp_gained` came in, or the night ended.
signal changed

## The film credits' own count of every player in the night (`CrewTracker`).
var crew: CrewTracker

var _state: ClientState
var _sources: Dictionary = {}
var _night_xp := 0
var _heard := false
## The poster sets the local player finished tonight, once each, in the order they finished.
var _sets: Array[Dictionary] = []
var _tally: NightTally


## A tracker on `state`, reading the night's XP for the report at its end: the server's own tally
## when an account holds the night, else what the night would have paid.
static func follow(state: ClientState, fuel_items: Array[StringName]) -> ReportTracker:
	var tracker := ReportTracker.new()
	tracker.attach(state, fuel_items)
	return tracker


## Starts listening to what this client hears. `fuel_items` are the shop ids that sell fuel, as
## `NightTally` takes them.
func attach(state: ClientState, fuel_items: Array[StringName] = [&"fuel_can"]) -> void:
	_state = state
	_tally = NightTally.new(fuel_items)
	_tally.keep_only(XpRules.PAYING)
	state.event_received.connect(_on_event)
	crew = CrewTracker.follow(state, fuel_items)
	crew.changed.connect(changed.emit)


## The card's data for the night as it stands (`NightReport.compose`).
func model() -> Dictionary:
	if _kept():
		return NightReport.compose(_sources, _night_xp, _state.account_xp - _night_xp, true, _sets)
	var stats := XpRules.stats_of(_tally, _state.player_id)
	var sources := NightReport.sources_of_stats(stats)
	var hundredths := 0
	for source: StringName in sources:
		hundredths += int(sources[source])
	return NightReport.compose(sources, XpRules.to_xp(hundredths), 0, false, _sets)


## What the film credits read (`CrewTracker.input`), with this client's own XP when an account
## holds the night: an unsaved night's number is not XP anyone has, so it is not given.
func credits_input() -> Dictionary:
	var input := crew.input()
	if _kept():
		input["xp"][_state.player_id] = _night_xp
	return input


## Whole XP the server has told this client the night paid so far (0 for a night nobody keeps).
func night_xp() -> int:
	return _night_xp


## Whether an account holds this night.
func is_kept() -> bool:
	return _kept()


func _kept() -> bool:
	return _heard or _state.levels.has(_state.player_id)


## Keeps a poster set the local player finished, once (the same event may be heard twice: from the
## server and from a night's own session).
func _note_set(event: Dictionary) -> void:
	if int(event.get("player_id", -1)) != _state.player_id:
		return
	for held in _sets:
		if held["id"] == event["id"]:
			return
	(
		_sets
		. append(
			{
				"id": event["id"],
				"title": event["title"],
				"card": event["card"],
				"emblem": event["emblem"],
			}
		)
	)
	changed.emit()


func _on_event(event: Dictionary) -> void:
	var type: StringName = event["type"]
	if type == PosterSets.DONE:
		_note_set(event)
		return
	if type == XpAward.GAINED:
		if int(event["player_id"]) != _state.player_id:
			return
		_heard = true
		_night_xp = int(event["xp"])
		var told: Dictionary = event["sources"]
		for source: StringName in told:
			_sources[source] = int(_sources.get(source, 0)) + int(told[source])
		changed.emit()
		return
	if _kept() or not XpAward.HEARD.has(type):
		return
	# This client is in the night it hears (the tally counts rounds for the players it knows).
	_tally.set_present(_state.player_id)
	_tally.observe(event)
	if type == &"game_over":
		changed.emit()
