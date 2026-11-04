class_name XpAward
extends RefCounted
## A night's XP for the seats that hold an account, counted where the night is decided: the game
## server (and, in a solo night, the local rules, the same code). A kill moves exactly its killer's
## tally; nothing a client says can. It reads the rules' events as they happen (`observe`), adds
## each one's worth to the seat's `XpMeter` (the rules are `XpRules`), and once a tick (`end_tick`)
## answers the events every client hears: `xp_gained`, and when a total crosses a level `level_up`,
## `tier_up` and `unlock_earned`. A tick's kills are added together first, so a seat is told at most
## once per tick (more rarely with `window_ticks`), however big the horde.
##
## A seat is registered by whoever knows its account (`register`: the game server from the verified
## ticket); a seat nobody registered earns nothing, which is how a night with no account at all pays
## nothing and how a bot never has a level. The backend is never written here: `take_report` hands
## over what each seat earned since the last report, for the host to post at a round's end and at
## the night's end (docs/design/progression.md#who-awards-xp-and-live-xp, #1059).
##
## The two one-off awards (the opening night, the day's first game) are the backend's to pay, once,
## from the profile it holds: a report only claims them for a seat that finished a round
## (`finished_round`).
##
## Events (the keys are the contract the popups, the level over a head and the voice lines read):
##   xp_gained     player_id, hundredths (added since the seat was last told), xp (the night's whole
##                 XP), total (the account's raw XP), sources {stat: hundredths}
##   level_up      player_id, level, total        (once per level crossed, in order)
##   tier_up       player_id, tier, tier_name, level   (a crossed level that opens a tier)
##   unlock_earned player_id, level, slot, item   (one per available item the level gives)

const GAINED := &"xp_gained"
const LEVEL_UP := &"level_up"
const TIER_UP := &"tier_up"
const UNLOCK := &"unlock_earned"
## The sources of whole XP that are no stat (`add_xp`).
const OPENING_NIGHT := &"opening_night"
const FIRST_GAME := &"first_game_of_the_day"
const CHALLENGE := &"challenge"

## The events that can move a paying stat. Every other event of a night (a shot, a hit, a frame) is
## skipped by one dictionary read.
const HEARD: Dictionary[StringName, bool] = {
	&"zombie_removed": true,
	&"board_repaired": true,
	&"purchase_made": true,
	&"player_revived": true,
	&"points_changed": true,
	&"round_started": true,
	&"round_ended": true,
	&"game_over": true,
}

## False: no seat is registered, so the night pays nothing and the award costs one read a tick (the
## measurement's "without" arm, and a kill-switch).
var enabled := true
## Ticks between the times a seat is told its XP (1: every tick). Raised only if a horde's numbers
## ask for it (the issue's 0.25 s window is 15 ticks).
var window_ticks := 1
var tally: NightTally
var unlocks: LadderUnlocks
## The day number the first game of the day is paid for; the server's clock (UTC).
var clock: ChallengeClock

var _seats: Dictionary[int, Seat] = {}
var _departed: Array[Seat] = []
## The reports the night owes: `{round, final}` for each round that ended and for the night's end.
var _due: Array[Dictionary] = []


func _init(fuel_items: Array[StringName] = [&"fuel_can"], p_clock: ChallengeClock = null) -> void:
	tally = NightTally.new(fuel_items)
	tally.keep_only(XpRules.PAYING)
	unlocks = LadderUnlocks.shipped()
	if p_clock != null:
		clock = p_clock
	else:
		clock = ChallengeClock.from_source(Time.get_unix_time_from_system)


## Gives a player an account for the night. `start_xp` is the account's raw XP when the seat sat
## down (the verified ticket's), `round_number` the round the night is in (rounds before it do not
## pay a late joiner). The same user registered again (a seat taken back) changes nothing.
func register(player_id: int, user: String, start_xp: int, round_number: int) -> void:
	if not enabled or user == "":
		return
	var held: Seat = _seats.get(player_id)
	if held != null:
		if held.user == user:
			return
		release(player_id)
	var seat := Seat.new(player_id, user, maxi(start_xp, 0), round_number)
	seat.level = LevelCurve.level_of(seat.start_xp)
	_seats[player_id] = seat
	tally.forget(player_id)
	tally.set_present(player_id)


## The seat leaves (or a bot takes it): what it earned and has not reported waits for the next
## report.
func release(player_id: int) -> void:
	var seat: Seat = _seats.get(player_id)
	if seat == null:
		return
	_seats.erase(player_id)
	seat.night_stats = XpRules.stats_of(tally, player_id)
	_departed.append(seat)
	tally.set_present(player_id, false)


func has_seat(player_id: int) -> bool:
	return _seats.has(player_id)


## The account a seat holds (`""` for a seat with none).
func user_of(player_id: int) -> String:
	var seat: Seat = _seats.get(player_id)
	return "" if seat == null else seat.user


## Whether any account sits in the night, or left with something not yet reported.
func has_accounts() -> bool:
	return not _seats.is_empty() or not _departed.is_empty()


## The seats with an account, in the order they sat down.
func seats() -> Array[int]:
	var out: Array[int] = []
	out.assign(_seats.keys())
	return out


## Every account seat's level, `{player_id: level}` (a bot has none): what a WELCOME carries.
func levels() -> Dictionary:
	var out := {}
	for id in _seats:
		out[id] = _seats[id].level
	return out


## The account's raw XP of a seat now (0 for a seat with no account).
func total_of(player_id: int) -> int:
	var seat: Seat = _seats.get(player_id)
	return 0 if seat == null else seat.start_xp + seat.meter.xp()


## Whole XP the seat has earned this night (the cap held).
func night_xp(player_id: int) -> int:
	var seat: Seat = _seats.get(player_id)
	return 0 if seat == null else seat.meter.xp()


## Adds whole XP that no stat shows (a challenge's reward, the one-off awards) to a seat.
func add_xp(player_id: int, xp: int, source: StringName) -> void:
	var seat: Seat = _seats.get(player_id)
	if seat == null or xp <= 0:
		return
	var hundredths := xp * XpRules.HUNDREDTHS
	seat.meter.add_xp(xp)
	seat.pending += hundredths
	seat.sources[source] = int(seat.sources.get(source, 0)) + hundredths


## Hears one event of the night (the rules' own; the others are skipped at once).
func observe(event: Dictionary) -> void:
	if _seats.is_empty() or not HEARD.has(event["type"]):
		return
	var began := PerfProbe.begin()
	for made in tally.observe(event):
		var seat: Seat = _seats.get(made["player_id"])
		if seat == null:
			continue
		var change: Dictionary = made
		if change["stat"] == ChallengeStats.ROUND:
			change = _since_joining(seat, made)
			if change.is_empty():
				continue
		var added := seat.meter.observe(change)
		if added > 0:
			seat.pending += added
			var stat: StringName = change["stat"]
			seat.sources[stat] = int(seat.sources.get(stat, 0)) + added
	match event["type"]:
		&"round_ended":
			_seats_finish_a_round()
			_due.append({"round": int(event["round"]), "final": false})
		&"game_over":
			_due.append({"round": int(event["round_reached"]), "final": true})
	PerfProbe.end(&"server.xp", began)


## The events of this tick to tell every client, in order. A seat whose window is not up waits
## (`force` tells every seat that has something now).
func end_tick(force: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _seats.is_empty():
		return out
	var began := PerfProbe.begin()
	for seat: Seat in _seats.values():
		seat.quiet += 1
		if seat.pending > 0 and (force or seat.quiet >= window_ticks):
			_tell(seat, out)
	PerfProbe.end(&"server.xp", began)
	return out


## The reports owed since the last call, in order: `{round, final}` for a round that ended and for
## the night's end. The host takes them after each step and makes the reports (`take_report`).
func take_due() -> Array[Dictionary]:
	var due := _due
	_due = []
	return due


func has_due() -> bool:
	return not _due.is_empty()


## What each seat earned since the last report, for the host to post, and the seats that left since
## then. `final` lists every seat even with nothing new, for the night's own report. Each entry:
## `{user, player_id, xp (whole XP new since the last report, without the one-offs), finished_round
## (the seat has ended a round: the backend pays the opening night and the day's first game once),
## day (the UTC day number), level, night_stats}` where `night_stats` are the night's paying counts
## so far. A report taken is not taken again.
func take_report(final: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seat in _departed:
		_entry(seat, false, out)
	_departed.clear()
	for seat: Seat in _seats.values():
		seat.night_stats = XpRules.stats_of(tally, seat.player_id)
		_entry(seat, final, out)
	return out


func _entry(seat: Seat, always: bool, out: Array[Dictionary]) -> void:
	var xp := seat.meter.xp() - seat.reported
	if xp <= 0 and not always:
		return
	(
		out
		. append(
			{
				"user": seat.user,
				"player_id": seat.player_id,
				"xp": maxi(xp, 0),
				"finished_round": seat.finished_round,
				"day": clock.day(),
				"level": LevelCurve.level_of(seat.start_xp + seat.meter.xp()),
				"night_stats": seat.night_stats,
			}
		)
	)
	seat.reported += maxi(xp, 0)


## A round count since the seat sat down: the rounds before it were not played by this player.
func _since_joining(seat: Seat, change: Dictionary) -> Dictionary:
	var value := int(change["value"]) - seat.round_base
	var before := maxi(int(change["value"]) - int(change["delta"]) - seat.round_base, 0)
	if value <= before:
		return {}
	return {
		"player_id": change["player_id"],
		"stat": change["stat"],
		"value": value,
		"delta": value - before,
	}


## A round ended: every seat sitting in it has finished one.
func _seats_finish_a_round() -> void:
	for seat: Seat in _seats.values():
		seat.finished_round = true


func _tell(seat: Seat, out: Array[Dictionary]) -> void:
	var total := seat.start_xp + seat.meter.xp()
	(
		out
		. append(
			{
				"type": GAINED,
				"player_id": seat.player_id,
				"hundredths": seat.pending,
				"xp": seat.meter.xp(),
				"total": total,
				"sources": seat.sources,
			}
		)
	)
	seat.pending = 0
	seat.sources = {}
	seat.quiet = 0
	PerfProbe.count(&"xp.gained")
	var level := LevelCurve.level_of(total)
	while seat.level < level:
		seat.level += 1
		_cross(seat, out)


## A seat reached `seat.level`: its card, the tier if it opens one, and what it unlocks.
func _cross(seat: Seat, out: Array[Dictionary]) -> void:
	(
		out
		. append(
			{
				"type": LEVEL_UP,
				"player_id": seat.player_id,
				"level": seat.level,
				"total": seat.start_xp + seat.meter.xp(),
			}
		)
	)
	var tier := LevelCurve.tier_of(seat.level)
	if tier > LevelCurve.tier_of(seat.level - 1):
		(
			out
			. append(
				{
					"type": TIER_UP,
					"player_id": seat.player_id,
					"tier": tier,
					"tier_name": LevelCurve.TIER_NAMES[tier],
					"level": seat.level,
				}
			)
		)
	for row: Dictionary in unlocks.earned_at(seat.level):
		(
			out
			. append(
				{
					"type": UNLOCK,
					"player_id": seat.player_id,
					"level": seat.level,
					"slot": row["slot"],
					"item": row["item"],
				}
			)
		)


## One seat's night.
class Seat:
	extends RefCounted
	var player_id: int
	var user: String
	var meter: XpMeter
	## The account's raw XP when the seat sat down, and the level that was.
	var start_xp: int
	var level := 1
	## The round the night was in when the seat sat down: it pays rounds after it.
	var round_base: int
	## Hundredths and their sources since the seat was last told.
	var pending := 0
	var sources: Dictionary = {}
	## Ticks since the seat was last told.
	var quiet := 0
	## Whole XP already in a report.
	var reported := 0
	## The seat has been in a round that ended.
	var finished_round := false
	var night_stats: Dictionary = {}

	func _init(p_player_id: int, p_user: String, p_start_xp: int, p_round: int) -> void:
		player_id = p_player_id
		user = p_user
		start_xp = p_start_xp
		round_base = p_round
		meter = XpMeter.new(p_player_id)
