class_name MenuProfile
extends RefCounted
## What the menu shows of the player's account. The name, stubs and mastery come from the cached
## profile (`profile/cache` in the settings file: JSON the platform backend will fill; the client
## writes only the player's name); the XP is the profile file's (`ProfileSave`, what the nights
## add to) and the level is `LevelCurve`'s, computed from it. An empty or damaged cache or file is
## a new player (level 1), never an error, and a night never waits on it.

## Levels run 1 to `MAX_LEVEL` (XP past it is kept and shows a full bar).
const MAX_LEVEL := LevelCurve.MAX_LEVEL
const DEFAULT_NAME := "Player"
## The longest name shown, so a long one cannot push the tab bar around.
const MAX_NAME := 16

## The profile file the XP is read from; a test points it at its own.
static var profile_path := ProfileSave.DEFAULT_PATH

var display_name := DEFAULT_NAME
var xp := 0
var stubs := 0
## Mastery points by weapon id.
var mastery: Dictionary = {}


## The profile in the settings file, with the XP of the profile file (0 when there is none).
static func load_saved() -> MenuProfile:
	var profile := from_json(Settings.get_value(SettingsService.PROFILE_CACHE))
	var saved: Variant = ProfileSave.read(profile_path)["profile"]
	profile.xp = (saved as Profile).xp if saved != null else 0
	return profile


## Whether the profile holds a name somebody gave: the player (asked on the first Play together, or
## typed in the menu) or the platform. Without one the player is `Player` here and `Guest NNNN`
## online.
static func is_named() -> bool:
	return str(_record().get("name", "")).strip_edges() != ""


## The name as the profile keeps it: no edge spaces, one space between words, at most `MAX_NAME`.
static func clean_name(text: String) -> String:
	var words := text.strip_edges().split(" ", false)
	return " ".join(words).left(MAX_NAME).strip_edges()


## Saves `text` as the profile's name (cleaned, the rest of the cache kept) and returns what was
## saved; an empty one takes the name away.
static func save_name(text: String) -> String:
	var clean := clean_name(text)
	var record := _record()
	record["name"] = clean
	Settings.set_value(SettingsService.PROFILE_CACHE, JSON.stringify(record))
	return clean


## The cache as a dictionary; empty when it is missing or damaged.
static func _record() -> Dictionary:
	var reader := JSON.new()
	var text: String = Settings.get_value(SettingsService.PROFILE_CACHE)
	if text == "" or reader.parse(text) != OK or typeof(reader.data) != TYPE_DICTIONARY:
		return {}
	return reader.data


## A profile read from JSON text; anything else gives a new player.
static func from_json(text: String) -> MenuProfile:
	var profile := MenuProfile.new()
	if text == "":
		return profile
	# `JSON.new().parse` reports a bad text by its return value; `parse_string` would log an error.
	var reader := JSON.new()
	if reader.parse(text) != OK or typeof(reader.data) != TYPE_DICTIONARY:
		return profile
	var record: Dictionary = reader.data
	var named := str(record.get("name", ""))
	if named.strip_edges() != "":
		profile.display_name = named.strip_edges().left(MAX_NAME)
	profile.xp = _count(record.get("xp", 0))
	profile.stubs = _count(record.get("stubs", 0))
	var points: Variant = record.get("mastery", {})
	if typeof(points) == TYPE_DICTIONARY:
		for id: Variant in points:
			profile.mastery[StringName(str(id))] = _count(points[id])
	return profile


## The text a profile with these facts is saved as (tests and the backend's reader use it).
static func to_json(
	name_text: String, total_xp: int, stub_count: int, mastery_points := {}
) -> String:
	return JSON.stringify(
		{"name": name_text, "xp": total_xp, "stubs": stub_count, "mastery": mastery_points}
	)


## XP needed to go from `level` to the next (`LevelCurve`).
static func xp_to_next(level: int) -> int:
	return LevelCurve.to_leave(level)


## Total XP at which `level` begins (level 1 begins at 0).
static func xp_at(level: int) -> int:
	return LevelCurve.xp_for(level)


## The level of `total_xp`.
static func level_of(total_xp: int) -> int:
	return LevelCurve.level_of(total_xp)


func level() -> int:
	return LevelCurve.level_of(xp)


## XP earned inside the current level, and what the level asks (0 at the top).
func xp_in_level() -> int:
	return LevelCurve.xp_in_level(xp)


func xp_for_level() -> int:
	return LevelCurve.to_leave(level())


## How far to the next level, 0 to 1 (1 at the top).
func level_fraction() -> float:
	return LevelCurve.fraction(xp)


## Mastery level of a weapon: 1 to 10, level N to N + 1 costing `400 + 100 x N` points.
func mastery_level(weapon: StringName) -> int:
	var left := int(mastery.get(weapon, 0))
	var level := 1
	while level < 10 and left >= 400 + 100 * level:
		left -= 400 + 100 * level
		level += 1
	return level


## How far the weapon is to its next mastery level, 0 to 1 (1 at level 10).
func mastery_fraction(weapon: StringName) -> float:
	var left := int(mastery.get(weapon, 0))
	var level := 1
	while level < 10 and left >= 400 + 100 * level:
		left -= 400 + 100 * level
		level += 1
	if level >= 10:
		return 1.0
	return clampf(float(left) / float(400 + 100 * level), 0.0, 1.0)


static func _count(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return maxi(value, 0)
		TYPE_FLOAT:
			return maxi(int(value), 0) if is_finite(value) else 0
	return 0
