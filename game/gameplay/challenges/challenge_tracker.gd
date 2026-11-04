class_name ChallengeTracker
extends RefCounted
## Counts a night for the players whose progress is kept. It hears the night's events, lets a
## `NightTally` turn them into stats for every player, and advances each followed player's
## `ChallengeProfile`. A client follows its own player; a server (the platform backend, later) can
## follow all of them: each is counted from the events that name them, so solo and co-op are the
## same code and the same numbers.
##
## `advanced` fires once per challenge that moved, with `ChallengeProfile.apply`'s dictionary plus
## `player_id`. The prompt in the night listens to it; the menu reads the profile.

signal advanced(advance: Dictionary)

var catalog: ChallengeCatalog
var clock: ChallengeClock
var tally: NightTally

var _followed: Dictionary[int, ChallengeProfile] = {}


func _init(
	p_catalog: ChallengeCatalog, p_clock: ChallengeClock, p_tally: NightTally = null
) -> void:
	catalog = p_catalog
	clock = p_clock
	tally = p_tally if p_tally != null else NightTally.new()


## Keeps this player's progress in `profile` from now on.
func follow(player_id: int, profile: ChallengeProfile) -> void:
	_followed[player_id] = profile
	profile.refresh(catalog, clock.day())


## Stops following this player (the seat is free): the profile keeps what it has.
func unfollow(player_id: int) -> void:
	_followed.erase(player_id)


func profile_of(player_id: int) -> ChallengeProfile:
	return _followed.get(player_id)


## Counts one event. Answers the advances it caused, in order.
func observe(event: Dictionary) -> Array[Dictionary]:
	var moved: Array[Dictionary] = []
	var day := clock.day()
	for change in tally.observe(event):
		var profile := profile_of(change["player_id"])
		if profile == null:
			continue
		if day > profile.dealt_day:
			profile.refresh(catalog, day)
		for advance in profile.apply(catalog, change["stat"], change["value"], change["delta"]):
			advance["player_id"] = change["player_id"]
			moved.append(advance)
			advanced.emit(advance)
	if event["type"] == &"game_over":
		for profile in _followed.values():
			profile.settle(catalog)
	return moved
