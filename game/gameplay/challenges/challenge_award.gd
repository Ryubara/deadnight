class_name ChallengeAward
extends RefCounted
## The challenge board of every seat that holds an account, followed where the night is decided: the
## game server (rule 9: the server awards, the client asks; docs/design/progression.md#the-save).
## It runs the same `NightTally` and `ChallengeTracker` a client runs, over the events the night
## makes, so a solo player and a seat in a crowd count the same night the same way. Nothing a
## client sends reaches it.
##
## A seat sits down (`seat`); the host reads the account's board from the backend, once, and hands
## it over when it arrives (`arrived`): a night never waits for it, and a seat whose board did not
## come is not followed and never written (the backend's board is left as it is). A board read is
## kept for the whole night, so a seat that leaves and comes back (a new ticket, another seat) is
## followed from where it was, never read again and never paid for a challenge twice.
##
## It answers two kinds of event, which every client hears (`take_events`):
##   challenge_progress  player_id and the advance `ChallengeProfile.apply` made: id, family, text,
##                       before, after, target, checkpoint (25..100), completed, rung, rungs. Only a
##                       move worth saying (a quarter mark, a ladder's step), never every kill.
##   challenge_done      player_id, id, family, text, target, rung, rungs, reward (the definition's
##                       dictionary: `xp`), once for a challenge finished.
##   poster_set_done     player_id, id, title, card, emblem (`PosterSets.event_of`): after the
##                       `challenge_done` of the last of a poster set's six, so once for a set.
##                       The prize is owned from the finished challenges (`PlateCatalog`), not
##                       from here.
## A finished challenge pays its XP to the seat's `XpAward` (the source `challenge`) and is listed
## in the next report (`fill_report`: the ids it finished, and the board as the tracker holds it).

## The backend's own answer for an account with no board yet (the read of the `challenges` slot).
## Only this body is "no board": a 404 from anywhere else (a backend from before the route, a wrong
## address) must not start a fresh board that would be written over the account's real one.
const NO_BOARD := {"error": "not_found"}
const PROGRESS := &"challenge_progress"
const DONE := &"challenge_done"

## The events that can move a challenge. Every other event of a night is skipped by one read.
const HEARD: Dictionary[StringName, bool] = {
	&"frame": true,
	&"player_added": true,
	&"player_removed": true,
	&"weapon_equipped": true,
	&"shot_fired": true,
	&"zombie_removed": true,
	&"board_repaired": true,
	&"purchase_made": true,
	&"player_revived": true,
	&"player_downed": true,
	&"settings_changed": true,
	&"blast_resolved": true,
	&"circuit_changed": true,
	&"points_changed": true,
	&"round_started": true,
	&"round_ended": true,
	&"game_over": true,
}

## False: no seat is followed (the measurement's arm without the tracker, and a kill-switch).
var enabled := true
## What is asked of the players. Null: the shipped catalogue, read when the first board arrives.
var catalog: ChallengeCatalog
## The day the dailies are dealt for: the server's (UTC), the clock the XP award uses.
var clock: ChallengeClock
## The poster sets a finish may complete. Null: the shipped ones.
var sets: PosterSets
## The night's rules, for what the odd stats need of them (the shop's doors, the map): set by the
## night's server before a board arrives.
var rules: GameRules

var _xp: XpAward
var _fuel_items: Array[StringName]
var _tracker: ChallengeTracker
var _boards: Dictionary[String, Board] = {}
## Account -> true, for every account whose board was asked for this night (answered or not).
var _asked: Dictionary[String, bool] = {}
## Player id -> account, for every seat that holds one.
var _seats: Dictionary[int, String] = {}
## Player id -> board, for the seats being followed.
var _live: Dictionary[int, Board] = {}
var _out: Array[Dictionary] = []


func _init(p_xp: XpAward, fuel_items: Array[StringName] = [&"fuel_can"]) -> void:
	_xp = p_xp
	clock = p_xp.clock
	_fuel_items = fuel_items


## A seat with an account sat down (or was taken back). True when this account's board has never
## been asked for this night: the host reads it and answers with `arrived`.
func seat(player_id: int, user: String) -> bool:
	if not enabled or user == "":
		return false
	var held: String = _seats.get(player_id, "")
	if held != "" and held != user:
		release(player_id)
	_seats[player_id] = user
	var board: Board = _boards.get(user)
	if board != null:
		_follow(player_id, board)
		return false
	if _asked.has(user):
		return false
	_asked[user] = true
	return true


## The backend's answer to the read of `user`'s board: `status` 200 with the envelope, 404 with
## `NO_BOARD` for an account with no board yet (it starts fresh), anything else (no answer, an
## error, any other 404, a board this game cannot read or is older than) and the night goes on
## without it.
func arrived(user: String, status: int, envelope: Variant) -> void:
	var profile := _profile_of(status, envelope)
	if profile == null or _boards.has(user):
		return
	_ensure_tracker()
	var before := JSON.stringify(profile.to_dict())
	profile.refresh(catalog, clock.day())
	profile.settle(catalog)
	var board := Board.new(user, profile)
	board.dirty = JSON.stringify(profile.to_dict()) != before
	_boards[user] = board
	for player_id: int in _seats:
		if _seats[player_id] == user:
			_follow(player_id, board)


## The seat is free: its board is kept for the night, and what it counted waits for the next report.
func release(player_id: int) -> void:
	_seats.erase(player_id)
	if _live.erase(player_id) and _tracker != null:
		_tracker.unfollow(player_id)


## Whether this seat's board is being followed.
func follows(player_id: int) -> bool:
	return _live.has(player_id)


## The board of an account this night, or null (not asked, not answered, or not readable).
func profile_of(user: String) -> ChallengeProfile:
	var board: Board = _boards.get(user)
	return null if board == null else board.profile


## Hears one event of the night (the others are skipped at once).
func observe(event: Dictionary) -> void:
	if _live.is_empty() or not HEARD.has(event["type"]):
		return
	var began := PerfProbe.begin()
	_tracker.observe(event)
	if event["type"] == &"game_over":
		for board: Board in _live.values():
			board.dirty = true
	PerfProbe.end(&"server.challenges", began)


## The events made since the last call, in order, for the night to tell every client.
func take_events() -> Array[Dictionary]:
	if _out.is_empty():
		return _out
	var out := _out
	_out = []
	return out


## Adds the boards that moved to the report being made (`XpAward.take_report`'s entries): for each,
## the challenge ids finished since the last report (`done`) and the board as the backend's
## `challenges` slot takes it (`board`). An account that moved its board without earning XP gets an
## entry of its own. A board that was taken is not taken again until it moves.
func fill_report(entries: Array[Dictionary]) -> void:
	for board: Board in _boards.values():
		if not board.dirty and board.done.is_empty():
			continue
		var entry := _entry_of(entries, board.user)
		if entry.is_empty():
			entry = {
				"user": board.user,
				"player_id": -1,
				"xp": 0,
				"finished_round": false,
				"day": clock.day(),
				"level": 0,
				"night_stats": {},
			}
			entries.append(entry)
		entry["done"] = board.done.duplicate()
		entry["board"] = {
			"schemaVersion": ChallengeSave.SCHEMA_VERSION, "data": board.profile.to_dict()
		}
		board.done.clear()
		board.dirty = false


func _entry_of(entries: Array[Dictionary], user: String) -> Dictionary:
	for entry in entries:
		if entry["user"] == user:
			return entry
	return {}


func _profile_of(status: int, envelope: Variant) -> ChallengeProfile:
	if status == 404 and envelope is Dictionary and envelope.get("error") == NO_BOARD["error"]:
		return ChallengeProfile.fresh()
	if status != 200 or not envelope is Dictionary:
		return null
	# A board this game cannot read, or a newer game wrote, is left alone: no profile, no write.
	return ChallengeSave.from_envelope(envelope)["profile"]


func _ensure_tracker() -> void:
	if _tracker != null:
		return
	if catalog == null:
		catalog = ChallengeCatalog.load_default()
	_tracker = ChallengeTracker.new(catalog, clock, NightTally.new(_fuel_items))
	if rules != null:
		_tracker.tally.know(rules.tuning, rules.settings.map)
		for id: int in rules.players:
			_tracker.tally.set_bot(id, rules.players[id].bot)
	_tracker.advanced.connect(_on_advanced)


func _follow(player_id: int, board: Board) -> void:
	if _live.get(player_id) == board:
		return
	_ensure_tracker()
	_live[player_id] = board
	_tracker.follow(player_id, board.profile)
	# A person who takes a bot's seat, or sits down late, counts from a clean slate.
	_tracker.tally.forget(player_id)
	_tracker.tally.set_present(player_id)
	if rules != null and rules.players.has(player_id):
		_tracker.tally.set_bot(player_id, rules.players[player_id].bot)


func _on_advanced(advance: Dictionary) -> void:
	var board: Board = _live.get(int(advance["player_id"]))
	if board == null:
		return
	PerfProbe.count(&"challenge.advance")
	board.dirty = true
	if advance["completed"]:
		_finish(board, advance)
	elif advance["checkpoint"] > 0 or advance["rung"] > 0:
		var event := advance.duplicate()
		event["type"] = PROGRESS
		_out.append(event)
		PerfProbe.count(&"challenge.told")


## A challenge is done: said once, paid once, and listed for the report.
func _finish(board: Board, advance: Dictionary) -> void:
	var id := StringName(advance["id"])
	if board.finished.has(id):
		return
	board.finished[id] = true
	board.done.append(String(id))
	var player_id: int = advance["player_id"]
	var progress := advance.duplicate()
	progress["type"] = PROGRESS
	_out.append(progress)
	PerfProbe.count(&"challenge.told")
	var def := catalog.get_def(id)
	var reward: Dictionary = {} if def == null else def.reward.duplicate()
	(
		_out
		. append(
			{
				"type": DONE,
				"player_id": player_id,
				"id": id,
				"family": advance["family"],
				"text": advance["text"],
				"target": advance["target"],
				"rung": advance["rung"],
				"rungs": advance["rungs"],
				"reward": reward,
			}
		)
	)
	var poster_sets := sets if sets != null else PosterSets.shipped()
	var poster_set := poster_sets.completed_by(id, board.profile.feats_done(catalog))
	# Two feats of a set can finish on the same event: the set is complete at the first of them
	# (both are on the board), and is said once.
	if poster_set != null and not board.sets_told.has(poster_set.id):
		board.sets_told[poster_set.id] = true
		_out.append(poster_sets.event_of(poster_set, player_id))
		PerfProbe.count(&"challenge.told")
	_xp.add_xp(player_id, int(reward.get("xp", 0)), XpAward.CHALLENGE)


## One account's board for the night.
class Board:
	extends RefCounted
	var user: String
	var profile: ChallengeProfile
	## The board changed since it was last put in a report.
	var dirty := false
	## The ids finished since the last report.
	var done: Array[String] = []
	## Every id finished and said this night: never said or paid twice.
	var finished: Dictionary[StringName, bool] = {}
	## The poster sets said this night, once each.
	var sets_told: Dictionary[StringName, bool] = {}

	func _init(p_user: String, p_profile: ChallengeProfile) -> void:
		user = p_user
		profile = p_profile
