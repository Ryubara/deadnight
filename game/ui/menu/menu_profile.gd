class_name MenuProfile
extends RefCounted
## What the menu shows of the player's account, from the cached profile (`profile/cache` in the
## settings file: JSON the platform backend will fill; nothing in the client writes it). Plain
## values and the Billing arithmetic of docs/design/progression.md; an empty or damaged cache is a
## new player (level 1, no stubs), never an error, and a night never waits on it.

## Billing levels run 1 to `MAX_LEVEL`; Encores after it are cosmetic and not counted here.
const MAX_LEVEL := 50
## XP from level L to L + 1 is `XP_BASE + XP_PER_LEVEL * L`.
const XP_BASE := 150
const XP_PER_LEVEL := 30
const DEFAULT_NAME := "Player"
## The longest name shown, so a long one cannot push the tab bar around.
const MAX_NAME := 16

var display_name := DEFAULT_NAME
var xp := 0
var stubs := 0
## Mastery points by weapon id.
var mastery: Dictionary = {}


## The profile in the settings file.
static func load_saved() -> MenuProfile:
	return from_json(Settings.get_value(SettingsService.PROFILE_CACHE))


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


## XP needed to go from `level` to the next.
static func xp_to_next(level: int) -> int:
	return XP_BASE + XP_PER_LEVEL * level


## Total XP at which `level` begins (level 1 begins at 0).
static func xp_at(level: int) -> int:
	var total := 0
	for step in range(1, level):
		total += xp_to_next(step)
	return total


## The Billing level of `total_xp`.
static func level_of(total_xp: int) -> int:
	var level := 1
	var left := total_xp
	while level < MAX_LEVEL and left >= xp_to_next(level):
		left -= xp_to_next(level)
		level += 1
	return level


func level() -> int:
	return level_of(xp)


## XP earned inside the current level, and what the level asks (0 at the top).
func xp_in_level() -> int:
	return xp - xp_at(level())


func xp_for_level() -> int:
	return 0 if level() >= MAX_LEVEL else xp_to_next(level())


## How far to the next level, 0 to 1 (1 at the top).
func level_fraction() -> float:
	if level() >= MAX_LEVEL:
		return 1.0
	return clampf(float(xp_in_level()) / float(xp_for_level()), 0.0, 1.0)


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
