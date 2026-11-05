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
## an account.
##
## **The queue holds changes, not profiles.** The backend takes the whole profile on its latest
## revision, so a queued write is what the night added (`{id, xp, opening_night, bonus_day, done}`)
## and `ProfileUplink` puts it on top of the account's own latest when it sends. The file is a cache
## of the account's profile with those changes on it: `adopt` replaces it with what the backend
## holds (read at sign-in), keeps the changes still queued on top, and drops a queue that belongs to
## another account (a Guest account that ran out).
##
## Only a night a person plays gets a store (the night screen makes it); bots, captures and tests
## leave it empty, so they never write the player's file.

var profile := Profile.new()
## Writes the backend has not taken: each `{id, xp, opening_night, bonus_day}` (and `done`,
## `equipped` when it carries them), oldest first.
var queue: Array[Dictionary] = []
var path := ProfileSave.DEFAULT_PATH
## Why the file could not be used (`ProfileSave.NEWER_VERSION`): the store then works in memory and
## never writes over the file.
var problem: StringName = ProfileSave.NO_PROBLEM
var revision := 0
## The backend's id of the account the file belongs to ("" while none has been read).
var account := ""
## The revision of the account's profile when it was last read (not kept in the file: it is read
## again at every sign-in).
var account_revision := 0

var _account: Callable
var _ids := RandomNumberGenerator.new()
var _flushing := false


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
		store.account = read["account"]
	return store


## Whether this player has an account (a Guest one counts) to keep XP in.
func has_account() -> bool:
	return _account.is_valid() and _account.call() == true


## A seed for the write ids (a test makes them the same every run).
func seed_ids(value: int) -> void:
	_ids.seed = value


## Credits a night's XP: `xp` whole XP, with the one-off `opening_night` the night claimed and the
## day (UTC) whose first-game XP it holds (`bonus_day`, -1 when none). Returns false and changes
## nothing for a night with no account.
func credit(xp: int, opening_night: bool = false, bonus_day: int = Profile.NO_DAY) -> bool:
	if not has_account():
		return false
	if xp <= 0 and not opening_night and bonus_day == Profile.NO_DAY:
		return true
	_enqueue(xp, opening_night, bonus_day, [])
	return true


## Notes a finished challenge on the profile (for an account), queues it for the backend and saves.
func finished(id: StringName) -> void:
	if has_account() and not profile.done.has(id):
		_enqueue(0, false, Profile.NO_DAY, [String(id)])


## Chooses the calling card or emblem to wear (`kind` is `card` or `emblem`, an empty `id` takes
## it off), for an account: the choice is on the cached profile at once and queued for the
## backend, which is where the game server reads it from when the player joins a night. Returns
## false and changes nothing for a player with no account or a choice already made.
func equip(kind: StringName, id: StringName) -> bool:
	if not has_account() or profile.chosen(kind) == id:
		return false
	_enqueue(0, false, Profile.NO_DAY, [], {String(kind): String(id)})
	return true


## The account's own profile, as `TogetherApi.read_save` answers it, replaces the cached one; the
## writes still queued stay on top of it. A queue kept for another account is dropped. A profile in
## a newer layout than this game reads is left alone.
func adopt(answer: Dictionary, account_id: String) -> void:
	if int(answer.get("schema_version", 0)) > ProfileSave.SCHEMA_VERSION:
		return
	if account != "" and account_id != "" and account != account_id:
		queue.clear()
	account = account_id
	account_revision = int(answer.get("revision", 0))
	profile = Profile.from_dict(answer.get("data", {}))
	for write in queue:
		profile.apply_write(write)
	save()


## Makes the whole queue one write: the XP added up, the one-offs and finished challenges kept. A
## backend that holds a night to what a person earns in the time since the last write takes a
## round's XP and the ones after it together, not one after another.
func coalesce() -> void:
	if queue.size() < 2:
		return
	var merged: Dictionary = queue[0].duplicate(true)
	var finished_ids: Array = merged.get("done", [])
	for write in queue.slice(1):
		merged["xp"] = int(merged["xp"]) + int(write["xp"])
		merged["opening_night"] = merged["opening_night"] or write["opening_night"]
		merged["bonus_day"] = maxi(int(merged["bonus_day"]), int(write["bonus_day"]))
		for id: Variant in write.get("done", []):
			if not finished_ids.has(id):
				finished_ids.append(id)
		# A later choice wins over an earlier one of the same kind.
		var chosen: Dictionary = merged.get("equipped", {})
		chosen.merge(write.get("equipped", {}), true)
		if not chosen.is_empty():
			merged["equipped"] = chosen
	merged["done"] = finished_ids
	queue.assign([merged])


## Sends the queue, oldest first, through `send` (a Callable taking the write, answering true when
## the backend took it; it may await). Stops at the first refusal, keeping it and what follows.
## `merge` sends the queue as one write (`coalesce`). Returns how many were taken. A flush that
## finds another one running does nothing: that one goes on to what was queued meanwhile.
func flush(send: Callable, merge: bool = false) -> int:
	if _flushing:
		return 0
	_flushing = true
	# The night that flushes may go while a request is out: the flush finishes and saves.
	@warning_ignore("unused_variable")
	var held := self
	var taken := 0
	while not queue.is_empty():
		if merge:
			coalesce()
		var sent: Variant = await send.call(queue[0])
		if sent != true:
			break
		queue.pop_front()
		taken += 1
	_flushing = false
	if taken > 0:
		save()
	return taken


## Whether a flush is waiting on the backend now.
func is_flushing() -> bool:
	return _flushing


## Writes the file (unless it is from a newer game). True when written.
func save() -> bool:
	if problem == ProfileSave.NEWER_VERSION:
		return false
	revision += 1
	if ProfileSave.write(profile, queue, revision, path, account):
		return true
	revision -= 1
	return false


func _enqueue(xp: int, opening_night: bool, bonus_day: int, done: Array, equipped := {}) -> void:
	var write := {
		"id": "%016x" % _ids.randi(),
		"xp": xp,
		"opening_night": opening_night,
		"bonus_day": bonus_day,
	}
	if not done.is_empty():
		write["done"] = done
	if not equipped.is_empty():
		write["equipped"] = equipped
	profile.apply_write(write)
	queue.append(write)
	save()
