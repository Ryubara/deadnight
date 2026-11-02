class_name ChallengeSession
extends RefCounted
## A night's link to the challenges: it listens to the client state's events, counts them for the
## local player (`ChallengeTracker`), keeps the player's board saved at the end of every round and
## of the night (so a quit or a crash loses at most the round in progress), and passes each
## advance on through `advanced` for the in-night prompt.
##
## Only a night a person plays gets one (the night screen makes it); bots, captures and tests
## leave `Night.challenges` empty, so they never write to the player's save.

signal advanced(advance: Dictionary)

var board: ChallengeBoard
var tracker: ChallengeTracker

var _state: ClientState
var _following := -1


## `tuning` names the shop's fuel items; the board is the player's.
func _init(p_board: ChallengeBoard, tuning: RulesTuning = null) -> void:
	board = p_board
	var fuel: Array[StringName] = []
	if tuning != null:
		for item in tuning.economy.items:
			if item.kind == ShopItem.Kind.FUEL:
				fuel.append(item.id)
	if fuel.is_empty():
		fuel.append(&"fuel_can")
	tracker = ChallengeTracker.new(board.catalog, board.clock, NightTally.new(fuel))
	tracker.advanced.connect(_on_advanced)


## Starts listening to what this client hears.
func attach(state: ClientState) -> void:
	_state = state
	state.event_received.connect(_on_event)


func _on_advanced(advance: Dictionary) -> void:
	advanced.emit(advance)


func _on_event(event: Dictionary) -> void:
	if _following != _state.player_id:
		_following = _state.player_id
		tracker.follow(_following, board.profile)
	tracker.observe(event)
	if event["type"] == &"round_ended" or event["type"] == &"game_over":
		board.save()


## Writes the board now (a night left before it ended).
func flush() -> void:
	board.save()
