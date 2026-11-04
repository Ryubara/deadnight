class_name ProfileSave
extends RefCounted
## Reads and writes a `Profile` as the save envelope the platform backend defines
## (`{revision, schemaVersion, data}`, docs/research/platform-backend.md#save-format), plus the
## `queue`: the writes the backend has not taken yet. Locally the file (`user://profile.json`) is a
## cache and a retry queue for the account's own writes (a Guest account is one), nothing more: an
## offline save is never merged into an account (no offline XP).
##
## Like `ChallengeSave`: this game reads every version it has written and writes the newest; a
## file from a newer game is left alone, never overwritten; a damaged file is set aside as
## `.broken` and play starts fresh. Nothing here is a 64-bit number.

const DEFAULT_PATH := "user://profile.json"
const SCHEMA_VERSION := Profile.SCHEMA_VERSION
const NO_PROBLEM := &""
const UNREADABLE := &"unreadable"
const NEWER_VERSION := &"newer_version"


## The envelope text: `queue` is an array of write dictionaries (`ProfileStore`'s).
static func to_json(profile: Profile, queue: Array[Dictionary], revision: int = 0) -> String:
	var envelope := {
		"revision": revision,
		"schemaVersion": SCHEMA_VERSION,
		"data": profile.to_dict(),
		"queue": queue,
	}
	return JSON.stringify(envelope, "\t")


## `{profile, queue, revision, problem}`: what the text holds, or a null profile with why
## (`unreadable`, `newer_version`).
static func from_json(text: String) -> Dictionary:
	# An instance reports a parse failure as a code; `parse_string` would print an engine error.
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	var failed := {"profile": null, "queue": [], "revision": 0, "problem": UNREADABLE}
	if not parsed is Dictionary:
		return failed
	var envelope: Dictionary = parsed
	var version := int(envelope.get("schemaVersion", 0))
	var data: Variant = envelope.get("data")
	if version < 1 or not data is Dictionary:
		return failed
	if version > SCHEMA_VERSION:
		failed["problem"] = NEWER_VERSION
		return failed
	var queue: Array[Dictionary] = []
	var waiting: Variant = envelope.get("queue")
	if waiting is Array:
		for entry: Variant in waiting:
			if entry is Dictionary and entry.has("id"):
				queue.append(entry)
	return {
		"profile": Profile.from_dict(data),
		"queue": queue,
		"revision": maxi(0, int(envelope.get("revision", 0))),
		"problem": NO_PROBLEM,
	}


## Writes to `path` (a temporary file first, so a crash leaves the old save). True when written.
static func write(
	profile: Profile, queue: Array[Dictionary], revision: int, path: String = DEFAULT_PATH
) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_json(profile, queue, revision))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temporary, path) == OK


## `{profile, queue, revision, problem}` from the file at `path`. No file is a fresh start (a
## null profile and no problem); a damaged one is moved aside.
static func read(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"profile": null, "queue": [], "revision": 0, "problem": NO_PROBLEM}
	var result := from_json(FileAccess.get_file_as_string(path))
	if result["problem"] == UNREADABLE:
		DirAccess.rename_absolute(path, path + ".broken")
	return result
