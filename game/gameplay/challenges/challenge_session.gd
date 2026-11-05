class_name ChallengeSession
extends RefCounted
## A night's link to the challenges: it listens to the client state's events, counts them for the
## local player (`ChallengeTracker`), keeps the player's board saved at the end of every round and
## of the night (so a quit or a crash loses at most the round in progress), and passes each
## advance on through `advanced` for the in-night prompt.
##
## Only a night a person plays gets one (the night screen makes it); bots, captures and tests
## leave `Night.challenges` empty, so they never write to the player's save.
##
## Online, the game server follows an account's board and says what moved (`ChallengeAward`'s
## `challenge_progress`), so the prompt shows that and not this class's own count: the count here is
## the local board's cache, kept as it always was. A seat without an account, or a night that runs
## here, has no server to say it, and the prompt shows the local count.

signal advanced(advance: Dictionary)
## A poster set was finished by what this machine counted (a night the rules run here, or a seat
## with no account): its `poster_set_done` event. It is also told to the client state, so the
## HUD, the voice and the night report hear it as they hear a game server's. Online the game
## server tells every client the same event, and this is silent.
signal set_finished(event: Dictionary)

var board: ChallengeBoard
## The poster sets a finish may complete. Null: the shipped ones.
var sets: PosterSets
var tracker: ChallengeTracker
## Writes the board to the account at each round's end (`ChallengeUplink`): set by a signed-in solo
## night, whose rules run here. Held here, not only by the night's code, so that a Callable or a
## request in flight never outlives it (`docs/godot/callables-and-coroutines.md`).
var uplink: ChallengeUplink

var _state: ClientState
var _following := -1
var _sets_told: Dictionary[StringName, bool] = {}
var _server_follows := false


## `tuning` names the shop's fuel items; the board is the player's.
func _init(p_board: ChallengeBoard, tuning: RulesTuning = null) -> void:
	board = p_board
	tracker = ChallengeTracker.new(
		board.catalog, board.clock, NightTally.new(NightTally.fuel_items_of(tuning))
	)
	tracker.advanced.connect(_on_advanced)


## Starts listening to what this client hears. `online`: the night is a game server's, which tells
## the seats that hold an account what their challenges did.
func attach(state: ClientState, online: bool = false) -> void:
	_state = state
	_server_follows = online
	state.event_received.connect(_on_event)


## Whether the prompt is the game server's to say: online, for a seat that holds an account.
func server_speaks() -> bool:
	return _server_follows and _state != null and _state.levels.has(_state.player_id)


func _on_advanced(advance: Dictionary) -> void:
	if not server_speaks():
		advanced.emit(advance)
		if advance.get("completed", false):
			_tell_set(StringName(advance["id"]))


## The finish of `id` may have been the last panel of a poster set: tell it, once, and note it so
## that the menu does not tell it again (`ProgressSeen`).
func _tell_set(id: StringName) -> void:
	var poster_sets := sets if sets != null else PosterSets.shipped()
	var poster_set := poster_sets.completed_by(id, board.profile.feats_done(board.catalog))
	# Two feats of a set can finish on one event: the set is told once.
	if poster_set == null or _sets_told.has(poster_set.id):
		return
	_sets_told[poster_set.id] = true
	ProgressSeen.note_set(poster_set.id)
	var event := poster_sets.event_of(poster_set, _state.player_id if _state != null else 0)
	set_finished.emit(event)
	if _state != null:
		_state.event_received.emit(event)


func _on_event(event: Dictionary) -> void:
	if event["type"] == PosterSets.DONE:
		# The game server told the set: the lane shows it, and the menu must not (`ProgressSeen`).
		if server_speaks() and int(event["player_id"]) == _state.player_id:
			ProgressSeen.note_set(StringName(event["id"]))
		return
	if event["type"] == ChallengeAward.PROGRESS:
		if server_speaks() and int(event["player_id"]) == _state.player_id:
			advanced.emit(event)
		return
	if _following != _state.player_id:
		_following = _state.player_id
		tracker.follow(_following, board.profile)
	tracker.observe(event)
	if event["type"] == &"round_ended" or event["type"] == &"game_over":
		board.save()
		if uplink != null:
			# Not awaited: a night never waits on the backend.
			uplink.send(board)


## Writes the board now (a night left before it ended).
func flush() -> void:
	board.save()
	if uplink != null:
		uplink.send(board)
