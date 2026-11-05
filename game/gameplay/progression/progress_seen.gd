class_name ProgressSeen
extends RefCounted
## What the player has already been told of their progress, kept beside the profile
## (`user://progress_seen.json`), so a card is shown once: either live in a night or, for progress
## made while no night was up, in the menu (`ProgressNews`).
##
## It holds, for one account, the highest level a card was shown for (`level`) and the finished
## challenges a night's HUD showed (`told`, by `challenge_key`). A night notes what it shows as it
## shows it (`note_level`, `note_challenge`); the menu reads it when it learns of a level or a
## finished challenge the cache did not have (a game server's night, another machine's) and tells
## only what is not in it. A profile read at sign-in then becomes the new "told": the file is
## rewritten for the account at that point.
##
## `path` is empty in tests and captures: nothing is read or written.

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://progress_seen.json"

## The file the real game keeps; its root sets it (`Main`).
static var path := ""

var account := ""
## The highest level shown for `account` (0: none known).
var level := 0
## Finished challenges shown live and not yet read back from the account, `{key: true}`.
var told: Dictionary = {}

var _path := ""


## The ledger in the file at `p_path` (the game's by default); a missing or damaged file is an
## empty one.
static func open(p_path: String = path) -> ProgressSeen:
	var seen := ProgressSeen.new()
	seen._path = p_path
	if p_path == "" or not FileAccess.file_exists(p_path):
		return seen
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(p_path)) != OK or not json.data is Dictionary:
		return seen
	var data: Dictionary = json.data
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		return seen
	seen.account = str(data.get("account", ""))
	seen.level = maxi(int(data.get("level", 0)), 0)
	for key: Variant in data.get("told", []):
		seen.told[str(key)] = true
	return seen


## The key a finished challenge is told by: a daily is that day's (the same one comes round on
## another day), an order or a ladder is its id.
static func challenge_key(family: int, id: StringName, day: int) -> String:
	if family == ChallengeDef.Family.DAILY:
		return "daily:%s:%d" % [id, day]
	return "%s:%s" % ["order" if family == ChallengeDef.Family.ORDER else "milestone", id]


## A live card for `level` was shown (or sent for) to the signed-in player: remembered. Does
## nothing without a file or an account.
static func note_level(level_reached: int, account_id: String = TogetherApi.account_id()) -> void:
	var seen := open()
	if not seen.bind(account_id) or level_reached <= seen.level:
		return
	seen.level = level_reached
	seen.save()


## A live card for a finished challenge was shown to the signed-in player: remembered.
static func note_challenge(
	family: int,
	id: StringName,
	account_id: String = TogetherApi.account_id(),
	day: int = ChallengeClock.system().day()
) -> void:
	var seen := open()
	if not seen.bind(account_id):
		return
	var key := challenge_key(family, id, day)
	if seen.told.has(key):
		return
	seen.told[key] = true
	seen.save()


## Makes the ledger the account's: another account's leaves it empty. False for no account or no
## file to keep it in.
func bind(account_id: String) -> bool:
	if account_id == "" or _path == "":
		return false
	if account != account_id:
		account = account_id
		level = 0
		told = {}
	return true


## The level the ledger knows for `account_id`: 0 for an account it has not met.
func level_for(account_id: String) -> int:
	return level if account == account_id else 0


## Whether a card for `key` was shown live to `account_id`.
func was_told(account_id: String, key: String) -> bool:
	return account == account_id and told.has(key)


## Writes the file (to a temporary one first). True when written.
func save() -> bool:
	if _path == "":
		return false
	var temporary := _path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	var keys: Array = told.keys()
	keys.sort()
	(
		file
		. store_string(
			(
				JSON
				. stringify(
					{
						"schema_version": SCHEMA_VERSION,
						"account": account,
						"level": level,
						"told": keys,
					}
				)
			)
		)
	)
	file.close()
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)
	return DirAccess.rename_absolute(temporary, _path) == OK
