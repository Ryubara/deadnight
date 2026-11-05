class_name CrewTracker
extends RefCounted
## What the film credits need from the night, kept as the night is heard (`NightCredits` hands out
## the titles, `HudCredits` draws them). It reads the events every client hears and keeps, for
## every player in the night: the stats the titles name (a `NightTally` that counts only those; a
## kill costs it one read, and only a boss kill is looked at) and the XP the server told that seat
## (`xp_gained`, which every client hears). It adds no number of its own.

## A seat's XP came in: the credits can be drawn again.
signal changed

var _titles: CrewTitles
var _tally: NightTally
## Player id -> the night's whole XP the server last told that seat.
var _xp: Dictionary[int, int] = {}


## A tracker on `state`. `fuel_items` are the shop ids that sell fuel, as `NightTally` takes them.
static func follow(
	state: ClientState, fuel_items: Array[StringName], titles: CrewTitles = null
) -> CrewTracker:
	var tracker := CrewTracker.new()
	tracker.attach(state, fuel_items, titles)
	return tracker


func attach(
	state: ClientState, fuel_items: Array[StringName] = [&"fuel_can"], titles: CrewTitles = null
) -> void:
	_titles = titles if titles != null else CrewTitles.shipped()
	_tally = NightTally.new(fuel_items)
	_tally.keep_only(_titles.stats())
	state.event_received.connect(_on_event)


## What the credits read: `{counts: {player_id: {stat: count}}, xp: {player_id: whole XP}}` for the
## players the night has named (the board adds the ones it knows that no event named).
func input() -> Dictionary:
	var counts := {}
	var stats := _titles.stats()
	for id in _tally.players():
		var mine := {}
		for stat in stats:
			mine[stat] = _tally.count(id, stat)
		counts[id] = mine
	return {"counts": counts, "xp": _xp.duplicate()}


## The night's whole XP the server told `player_id`, -1 for a seat it told nothing (a bot, or a seat
## nobody keeps).
func xp_of(player_id: int) -> int:
	return _xp.get(player_id, -1)


func _on_event(event: Dictionary) -> void:
	var type: StringName = event["type"]
	if type == XpAward.GAINED:
		_xp[int(event["player_id"])] = int(event["xp"])
		changed.emit()
		return
	if not CrewTitles.HEARD.has(type):
		return
	# Only a boss kill moves a title's stat; the others are the horde, left unread.
	if type == &"zombie_removed" and not event["boss"]:
		return
	_tally.observe(event)
