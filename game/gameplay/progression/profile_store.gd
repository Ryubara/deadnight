class_name ProfileStore
extends RefCounted
## The player's profile on this machine, and the writes waiting for the backend.
##
## **No offline XP.** XP exists for an account the server tracks, and a Guest account is one (the
## maintainer, 2026-11-04): it earns like any other. `credit` on a night with no account at all (the
## backend was never reached) refuses and awards nothing. For an account, a night's XP is added to
## the cached profile at once and queued as a write with an id; `flush` sends the queue to the
## backend through a Callable and keeps what it refuses, to send again, so a night never waits on
## the backend (rule 10) and a resent write is the same write. An offline file is never merged into
## an account. Keeping a Guest account across visits is a separate issue.
##
## Only a night a person plays gets a store (the night screen makes it); bots, captures and tests
## leave it empty, so they never write the player's file.

var profile := Profile.new()
## Writes the backend has not taken: each `{id, xp, opening_night, bonus_day}`, oldest first.
var queue: Array[Dictionary] = []
var path := ProfileSave.DEFAULT_PATH
## Why the file could not be used (`ProfileSave.NEWER_VERSION`): the store then works in memory and
## never writes over the file.
var problem: StringName = ProfileSave.NO_PROBLEM
var revision := 0

var _account: Callable
var _ids := RandomNumberGenerator.new()


## The store of the file at `path`. `account_check` is a Callable returning whether this player has
## an account session, a Guest account included (`TogetherApi.signed_in`).
static func open(
	p_path: String = ProfileSave.DEFAULT_PATH, account_check: Callable = Callable()
) -> ProfileStore:
	var store := ProfileStore.new()
	store.path = p_path
	store._account = account_check
	store._ids.randomize()
	var read := ProfileSave.read(p_path)
	store.problem = read["problem"]
	if read["profile"] != null:
		store.profile = read["profile"]
		store.queue.assign(read["queue"])
		store.revision = read["revision"]
	return store


## Whether this player has an account (a Guest one counts) to keep XP in.
func has_account() -> bool:
	return _account.is_valid() and _account.call() == true


## A seed for the write ids (a test makes them the same every run).
func seed_ids(value: int) -> void:
	_ids.seed = value


## Credits a night's XP: `xp` whole XP, with the one-off `opening_night` the night claimed and the
## local day whose first-game XP it holds (`bonus_day`, -1 when none). Returns false and changes
## nothing for a night with no account.
func credit(xp: int, opening_night: bool = false, bonus_day: int = Profile.NO_DAY) -> bool:
	if not has_account():
		return false
	if xp <= 0 and not opening_night and bonus_day == Profile.NO_DAY:
		return true
	profile.add_xp(xp)
	profile.opening_night = profile.opening_night or opening_night
	if bonus_day != Profile.NO_DAY:
		profile.bonus_day = bonus_day
	(
		queue
		. append(
			{
				"id": "%016x" % _ids.randi(),
				"xp": xp,
				"opening_night": opening_night,
				"bonus_day": bonus_day,
			}
		)
	)
	save()
	return true


## Notes a finished challenge on the profile (for an account), and saves.
func finished(id: StringName) -> void:
	if has_account() and not profile.done.has(id):
		profile.mark_done(id)
		save()


## Sends the queue, oldest first, through `send` (a Callable taking the write, answering true when
## the backend took it). Stops at the first refusal, keeping it and what follows. Returns how many
## were taken.
func flush(send: Callable) -> int:
	var taken := 0
	while not queue.is_empty():
		if send.call(queue[0]) != true:
			break
		queue.pop_front()
		taken += 1
	if taken > 0:
		save()
	return taken


## Writes the file (unless it is from a newer game). True when written.
func save() -> bool:
	if problem == ProfileSave.NEWER_VERSION:
		return false
	revision += 1
	if ProfileSave.write(profile, queue, revision, path):
		return true
	revision -= 1
	return false
