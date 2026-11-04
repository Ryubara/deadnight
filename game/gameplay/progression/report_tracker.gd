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
## It counts nothing for a seat the server keeps, so an online account pays this client no
## per-kill work beyond one dictionary read.

## The card changed: an `xp_gained` came in, or the night ended.
signal changed

var _state: ClientState
var _sources: Dictionary = {}
var _night_xp := 0
var _heard := false
var _tally: NightTally


## Starts listening to what this client hears. `fuel_items` are the shop ids that sell fuel, as
## `NightTally` takes them.
func attach(state: ClientState, fuel_items: Array[StringName] = [&"fuel_can"]) -> void:
	_state = state
	_tally = NightTally.new(fuel_items)
	_tally.keep_only(XpRules.PAYING)
	state.event_received.connect(_on_event)


## The card's data for the night as it stands (`NightReport.compose`).
func model() -> Dictionary:
	if _kept():
		return NightReport.compose(_sources, _night_xp, _state.account_xp - _night_xp, true)
	var stats := XpRules.stats_of(_tally, _state.player_id)
	var sources := NightReport.sources_of_stats(stats)
	var hundredths := 0
	for source: StringName in sources:
		hundredths += int(sources[source])
	return NightReport.compose(sources, XpRules.to_xp(hundredths), 0, false)


## Whole XP the server has told this client the night paid so far (0 for a night nobody keeps).
func night_xp() -> int:
	return _night_xp


## Whether an account holds this night.
func is_kept() -> bool:
	return _kept()


func _kept() -> bool:
	return _heard or _state.levels.has(_state.player_id)


func _on_event(event: Dictionary) -> void:
	var type: StringName = event["type"]
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
