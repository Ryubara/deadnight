class_name Profile
extends RefCounted
## The player's permanent profile: facts, never the level. `xp` is the raw total (the level, the bar
## and the tier are `LevelCurve`'s, so a retune needs no migration). Plain data that round-trips
## through `to_dict` / `from_dict`; the envelope it travels in is `ProfileSave`.
##
## `equipped` is what the player wears and shows to others: the calling card and the emblem they
## chose (`card`, `emblem`: piece ids, absent for none), `done` the challenge ids ever finished
## (what a challenge gave them is read from it, `PlateCatalog`), `opening_night` whether the one-off
## first-night XP was paid, `bonus_day` the local day number the first-game-of-the-day XP was last
## paid for (-1: never). XP past level 55 is kept; nothing is awarded for it yet (#1055).

const SCHEMA_VERSION := 1
const NO_DAY := -1

var xp := 0
var equipped: Dictionary = {}
var done: Array[StringName] = []
var opening_night := false
var bonus_day := NO_DAY


func level() -> int:
	return LevelCurve.level_of(xp)


## Adds `amount` XP (never takes any away).
func add_xp(amount: int) -> void:
	xp += maxi(amount, 0)


## Adds a queued write (`ProfileStore`: `{xp, opening_night, bonus_day, done, equipped}`, every key
## optional; `equipped` holds the choices that changed, an empty id taking one away):
## what the backend is sent, and what the cached profile takes, so the two agree.
func apply_write(write: Dictionary) -> void:
	add_xp(int(write.get("xp", 0)))
	opening_night = opening_night or write.get("opening_night", false) == true
	var day := int(write.get("bonus_day", NO_DAY))
	if day != NO_DAY:
		bonus_day = maxi(bonus_day, day)
	var finished: Variant = write.get("done", [])
	if finished is Array:
		for id: Variant in finished:
			mark_done(StringName(str(id)))
	var chosen: Variant = write.get("equipped", {})
	if chosen is Dictionary:
		for kind: Variant in chosen:
			choose(StringName(str(kind)), StringName(str(chosen[kind])))


## Whether the day's first-game XP is still owed for local day `day`.
func bonus_due(day: int) -> bool:
	return bonus_day != day


## The piece of `kind` (`card`, `emblem`) the player chose, `&""` for none.
func chosen(kind: StringName) -> StringName:
	return StringName(str(equipped.get(String(kind), "")))


## Chooses a piece to wear (an empty id takes the choice away).
func choose(kind: StringName, id: StringName) -> void:
	if id == &"":
		equipped.erase(String(kind))
	else:
		equipped[String(kind)] = String(id)


## Notes a finished challenge once.
func mark_done(id: StringName) -> void:
	if not done.has(id):
		done.append(id)


func to_dict() -> Dictionary:
	return {
		"xp": xp,
		"equipped": equipped.duplicate(true),
		"done": done.map(func(id: StringName) -> String: return String(id)),
		"opening_night": opening_night,
		"bonus_day": bonus_day,
	}


## Reads a dictionary `to_dict` wrote (schema 1). A wrong or missing field falls back to its
## starting value: a damaged save never breaks a night.
static func from_dict(data: Dictionary) -> Profile:
	var profile := Profile.new()
	profile.xp = _count(data.get("xp", 0))
	var worn: Variant = data.get("equipped")
	if worn is Dictionary:
		profile.equipped = (worn as Dictionary).duplicate(true)
	var finished: Variant = data.get("done")
	if finished is Array:
		for id: Variant in finished:
			profile.mark_done(StringName(str(id)))
	var opened: Variant = data.get("opening_night", false)
	profile.opening_night = typeof(opened) == TYPE_BOOL and opened
	var day: Variant = data.get("bonus_day", NO_DAY)
	profile.bonus_day = int(day) if typeof(day) in [TYPE_INT, TYPE_FLOAT] else NO_DAY
	return profile


static func _count(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return maxi(value, 0)
		TYPE_FLOAT:
			return maxi(int(value), 0) if is_finite(value) else 0
	return 0
