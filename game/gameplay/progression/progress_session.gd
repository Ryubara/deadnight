class_name ProgressSession
extends RefCounted
## A night's XP for the local player: it hears the events this client hears, counts them
## (`NightTally`), keeps the running XP (`XpMeter`, the rules `XpRules`) and, for an account (a
## Guest account is one), writes the profile at the end of every round and of the night (so a quit
## loses at most the round in progress). A night with no account counts the same and writes
## nothing (`ProfileStore`).
##
## The one-off XP is claimed when the night's first round ends, so it pays for playing, never for
## opening the game: the opening night once ever, the first game of the day once a local day (the
## day number the dailies use, `ChallengeClock`). A completed daily or order adds the XP its
## definition holds. Only a night a person plays gets one (the night makes it when the screen gives
## it a store); bots, captures, tests and online nights (the server awards those) have none.

## Hundredths of XP just added by an event, for the live popup; `total` is the whole XP so far.
signal gained(hundredths: int, total: int)

var store: ProfileStore
## What the night has counted (read it, do not feed it).
var tally: NightTally
## Sends a queued write to the backend (a Callable taking the write, answering whether it was
## taken: `ProfileUplink.send`; it may await). A refused write stays queued, and goes again at the
## next round's end; what is queued is sent as one write.
var uploader := Callable()
## The night's `XpAward`, when the local rules tell the player their XP as events (a signed-in solo
## night): the one-off awards and challenge rewards, which no stat shows, are told to it so its
## totals agree with the profile.
var award: XpAward

var _clock: ChallengeClock
var _meter: XpMeter
var _state: ClientState
var _challenges: ChallengeSession
var _following := -1
var _credited := 0
var _challenge_xp := 0
var _claimed := false
var _pending_opening := false
var _pending_day := Profile.NO_DAY


## `fuel_items` are the shop ids that sell fuel, as `NightTally` takes them.
func _init(
	p_store: ProfileStore, p_clock: ChallengeClock, fuel_items: Array[StringName] = [&"fuel_can"]
) -> void:
	store = p_store
	_clock = p_clock
	tally = NightTally.new(fuel_items)


## Starts listening to what this client hears; `challenges`, when there are some, pay their XP.
func attach(state: ClientState, challenges: ChallengeSession = null) -> void:
	_state = state
	state.event_received.connect(_on_event)
	_challenges = challenges
	if challenges != null:
		challenges.advanced.connect(_on_advanced)


## Whole XP this night is worth so far, held to the night's cap.
func xp() -> int:
	return _meter.xp() if _meter != null else 0


## XP the night's finished challenges paid (it is in `xp`).
func challenge_xp() -> int:
	return _challenge_xp


## XP the profile holds from this night (0 for a night with no account, whatever `xp` says).
func credited() -> int:
	return _credited


## True when this night's XP is not being kept, because there is no account at all.
func is_unkept() -> bool:
	return not store.has_account()


## Writes what the night has earned since the last write (a night left before it ended).
func flush() -> void:
	_persist()


func _on_event(event: Dictionary) -> void:
	if _following != _state.player_id:
		_following = _state.player_id
		_meter = XpMeter.new(_following)
	for change in tally.observe(event):
		var added := _meter.observe(change)
		if added > 0:
			gained.emit(added, _meter.xp())
	match event["type"]:
		&"round_ended":
			_claim_once()
			_persist()
		&"game_over":
			_persist()


## The challenge board paid out: add the XP its definition holds, once.
func _on_advanced(advance: Dictionary) -> void:
	if _meter == null or not advance.get("completed", false):
		return
	if int(advance.get("player_id", _following)) != _following:
		return
	var id := StringName(advance["id"])
	var def := _challenges.board.catalog.get_def(id)
	if def == null:
		return
	var reward := int(def.reward.get("xp", 0))
	if reward > 0:
		_meter.add_xp(reward)
		_challenge_xp += reward
		_tell_award(reward, XpAward.CHALLENGE)
		gained.emit(reward * XpRules.HUNDREDTHS, _meter.xp())
	store.finished(id)


## The first round's end: the opening night and the day's first game, for an account that has not
## had them. A night with no account claims nothing.
func _claim_once() -> void:
	if _claimed or not store.has_account():
		return
	_claimed = true
	var day := _clock.day()
	if not store.profile.opening_night:
		_pending_opening = true
		_meter.add_xp(XpRules.OPENING_NIGHT_XP)
		_tell_award(XpRules.OPENING_NIGHT_XP, XpAward.OPENING_NIGHT)
	if store.profile.bonus_due(day):
		_pending_day = day
		_meter.add_xp(XpRules.FIRST_GAME_OF_THE_DAY_XP)
		_tell_award(XpRules.FIRST_GAME_OF_THE_DAY_XP, XpAward.FIRST_GAME)


func _tell_award(xp: int, source: StringName) -> void:
	if award != null:
		award.add_xp(_following, xp, source)


func _persist() -> void:
	if _meter == null:
		return
	var gained_xp := _meter.xp() - _credited
	if gained_xp > 0 or _pending_opening or _pending_day != Profile.NO_DAY:
		if store.credit(maxi(gained_xp, 0), _pending_opening, _pending_day):
			_credited += maxi(gained_xp, 0)
			_pending_opening = false
			_pending_day = Profile.NO_DAY
	if uploader.is_valid() and store.has_account():
		store.flush(uploader, true)
