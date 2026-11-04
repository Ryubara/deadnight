class_name ChallengeBoard
extends RefCounted
## What the menu reads: the player's challenges as plain data, and nothing else it needs. The main
## menu's home panel and the Challenges tab are built on this class alone.
##
##   var board := ChallengeBoard.open()          # loads the save, deals today's dailies
##   board.dailies()          -> today's three, each a Dictionary (below)
##   board.orders()           -> the open Concession Orders
##   board.milestones()       -> every lifetime ladder
##   board.seconds_to_refresh(), board.refresh_text()   the time until the next dailies
##   board.swap_order(slot)   changes an order (free, unlimited) and saves
##   board.refresh()          call when the menu is shown again: a new day deals new dailies
##   board.reload()           reads the file again when something else wrote it (the account's board
##                            read at sign-in, a night that ended); `watch_file()` does it by itself
##                            when `ChallengeUplink` replaces the file
##
## A daily or order: `{id, text, progress, target, fraction (0..1), done, tier, reward}`; an order
## also has `slot` and `pillar`. A daily expires at the next refresh, done or not. A milestone:
## `{id, text (the next step), stat, value, rung, rungs, target (the next step; 0 when the ladder
## is done), fraction, done}`.
## `tier` is "short", "medium" or "long". `reward` is a placeholder dictionary (nothing pays yet).

signal changed

## The boards that asked to follow their file (`watch_file`), weakly: a menu that is gone is not
## kept.
static var _watching: Array[WeakRef] = []

var catalog: ChallengeCatalog
var clock: ChallengeClock
var profile: ChallengeProfile
var path := ChallengeSave.DEFAULT_PATH
## Why the save could not be used (`ChallengeSave.NEWER_VERSION`): the board then works in memory
## and never writes over the file.
var problem: StringName = ChallengeSave.NO_PROBLEM


## Opens the player's board: the save at `path` (a fresh profile when there is none), dealt for
## today. `p_clock` and `p_catalog` are for tests; the machine's clock and the shipped data
## otherwise.
static func open(
	p_path: String = ChallengeSave.DEFAULT_PATH,
	p_clock: ChallengeClock = null,
	p_catalog: ChallengeCatalog = null
) -> ChallengeBoard:
	var board := ChallengeBoard.new()
	board.path = p_path
	board.clock = p_clock if p_clock != null else ChallengeClock.system()
	board.catalog = p_catalog if p_catalog != null else ChallengeCatalog.load_default()
	var read := ChallengeSave.read(p_path)
	board.problem = read["problem"]
	board.profile = read["profile"] if read["profile"] != null else ChallengeProfile.fresh()
	board.refresh()
	return board


## Follows the file: when the account's board replaces it (`file_replaced`), this board reads it and
## says `changed`. The menu's board does; a night's board never does (its tracker holds the
## profile).
func watch_file() -> void:
	_watching = _watching.filter(func(ref: WeakRef) -> bool: return ref.get_ref() != null)
	_watching.append(weakref(self))


## Tells the boards watching `file_path` that it was written by someone else.
static func file_replaced(file_path: String) -> void:
	for ref in _watching:
		var board := ref.get_ref() as ChallengeBoard
		if board != null and board.path == file_path:
			board.reload()


## Takes the file's board when it is not the one held (another board or the sign-in wrote it).
## A file that cannot be used (damaged, or a newer game's) changes nothing.
func reload() -> void:
	var read := ChallengeSave.read(path)
	if read["problem"] == ChallengeSave.NEWER_VERSION:
		problem = ChallengeSave.NEWER_VERSION
		return
	var found: ChallengeProfile = read["profile"]
	if found == null or _same(found, profile):
		return
	problem = ChallengeSave.NO_PROBLEM
	profile = found
	refresh()


static func _same(a: ChallengeProfile, b: ChallengeProfile) -> bool:
	return (
		JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict())
		and a.account == b.account
		and a.account_revision == b.account_revision
	)


## Deals the day if it turned, settles finished orders, and saves what changed.
func refresh() -> void:
	var before := JSON.stringify(profile.to_dict())
	profile.refresh(catalog, clock.day())
	profile.settle(catalog)
	if JSON.stringify(profile.to_dict()) != before or not FileAccess.file_exists(path):
		save()
	changed.emit()


## Writes the profile (unless the file on disk is from a newer game).
func save() -> bool:
	if problem == ChallengeSave.NEWER_VERSION:
		return false
	return ChallengeSave.write(profile, path)


func seconds_to_refresh() -> int:
	return clock.seconds_to_refresh()


## "6 h 12 min" or "42 min" until the dailies change.
func refresh_text() -> String:
	var minutes := ceili(seconds_to_refresh() / 60.0)
	if minutes >= 60:
		return "%d h %02d min" % [minutes / 60, minutes % 60]
	return "%d min" % maxi(minutes, 1)


func dailies() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for entry in profile.dailies:
		var row := _row(entry)
		if not row.is_empty():
			list.append(row)
	return list


func orders() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for slot in profile.orders.size():
		var row := _row(profile.orders[slot])
		if row.is_empty():
			continue
		var def := catalog.get_def(row["id"])
		row["slot"] = slot
		row["pillar"] = def.pillar
		list.append(row)
	return list


func milestones() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for def in catalog.of_family(ChallengeDef.Family.MILESTONE):
		var value := int(profile.lifetime.get(def.stat, 0))
		var rung := ChallengeProfile.rung_of(def, value)
		var done := rung >= def.steps.size()
		var next := 0 if done else def.steps[rung]
		var floor_value := def.steps[rung - 1] if rung > 0 else 0
		var fraction := 1.0
		if not done:
			fraction = clampf(float(value - floor_value) / float(next - floor_value), 0.0, 1.0)
		(
			list
			. append(
				{
					"id": def.id,
					"text": def.words(def.steps[mini(rung, def.steps.size() - 1)]),
					"stat": def.stat,
					"value": value,
					"rung": rung,
					"rungs": def.steps.size(),
					"target": next,
					"fraction": fraction,
					"done": done,
					"reward": def.reward,
				}
			)
		)
	return list


func swap_order(slot: int) -> bool:
	if not profile.swap_order(catalog, slot):
		return false
	save()
	changed.emit()
	return true


func _row(entry: Dictionary) -> Dictionary:
	var def := catalog.get_def(StringName(entry["id"]))
	if def == null:
		return {}
	var progress := mini(int(entry["progress"]), def.target)
	return {
		"id": def.id,
		"text": def.words(),
		"progress": progress,
		"target": def.target,
		"fraction": float(progress) / float(def.target),
		"done": progress >= def.target,
		"tier": ChallengeDef.TIER_NAMES.find_key(def.tier),
		"reward": def.reward,
	}
