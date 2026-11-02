class_name ChallengeSave
extends RefCounted
## Reads and writes a `ChallengeProfile` as the save envelope the platform backend defines
## (`{revision, schemaVersion, data}`, docs/research/platform-backend.md#save-format): locally in
## `user://challenges.json` today, the backend's save slot later, the same JSON either way.
##
## `schemaVersion` says how to read `data`. This game reads every version it has ever written and
## writes the newest; a file from a newer game is left alone, never overwritten, so an old client
## cannot wipe progress. A damaged file is set aside as `.broken` and play starts fresh. Nothing
## here is a 64-bit number: counts and seeds are small, so they travel as plain JSON numbers.

const DEFAULT_PATH := "user://challenges.json"
## The layout of `data`. 1: dailies with their day, orders with a seed and a draw count, lifetime
## totals by stat, finished counts. To change it: add the next version, read both, write the newest.
const SCHEMA_VERSION := 1
const NO_PROBLEM := &""
const UNREADABLE := &"unreadable"
const NEWER_VERSION := &"newer_version"


## The envelope text for `profile` (its revision is whatever it holds).
static func to_json(profile: ChallengeProfile) -> String:
	var envelope := {
		"revision": profile.revision,
		"schemaVersion": SCHEMA_VERSION,
		"data": profile.to_dict(),
	}
	return JSON.stringify(envelope, "\t")


## `{profile, problem}`: the profile the text holds, or null with why (`unreadable`,
## `newer_version`).
static func from_json(text: String) -> Dictionary:
	# An instance reports a parse failure as a code; `parse_string` would print an engine error.
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary:
		return {"profile": null, "problem": UNREADABLE}
	var envelope: Dictionary = parsed
	var version := int(envelope.get("schemaVersion", 0))
	var data: Variant = envelope.get("data")
	if version < 1 or not data is Dictionary:
		return {"profile": null, "problem": UNREADABLE}
	if version > SCHEMA_VERSION:
		return {"profile": null, "problem": NEWER_VERSION}
	var profile := ChallengeProfile.from_dict(_migrate(data, version))
	profile.revision = maxi(0, int(envelope.get("revision", 0)))
	return {"profile": profile, "problem": NO_PROBLEM}


## Brings `data` written at `version` up to the newest layout. Only version 1 exists.
static func _migrate(data: Dictionary, _version: int) -> Dictionary:
	return data


## Writes the profile to `path` (to a temporary file first, so a crash leaves the old save), with
## its revision one higher. True when it was written.
static func write(profile: ChallengeProfile, path: String = DEFAULT_PATH) -> bool:
	profile.revision += 1
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		profile.revision -= 1
		return false
	file.store_string(to_json(profile))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temporary, path) == OK


## `{profile, problem}` from the file at `path`. No file is a fresh start (`profile` empty-handed
## is a new profile, no problem); a damaged one is moved aside.
static func read(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"profile": null, "problem": NO_PROBLEM}
	var result := from_json(FileAccess.get_file_as_string(path))
	if result["problem"] == UNREADABLE:
		DirAccess.rename_absolute(path, path + ".broken")
	return result
