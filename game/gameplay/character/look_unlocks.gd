class_name LookUnlocks
extends RefCounted
## What this player may wear. Progression (docs/design/progression.md) is cosmetics only: a level
## opens wearables and colours, and `unlocks.json` says which (`LookCatalog` reads it). A gate is a
## dictionary: empty means free, otherwise `level` (the account level that opens it) or `order` (a
## named goal, for a challenge's reward).
##
## The level is the account's: `at_level` for a screen that knows it, `saved` for the one the
## profile file holds on this machine (what a night and the menu's stage use). The game server asks
## for the level of each player it knows (`NightServer.player_levels`).

## The profile file `saved` reads the level from; a test or a capture points it at its own.
static var profile_path := ProfileSave.DEFAULT_PATH

## Account level. A gate `{"level": n}` opens at level n.
var level := 1
## Options earned by other means, keyed by `key`.
var owned := {}


## Unlocks of an account at `at` (a level below 1 reads as 1).
static func at_level(at: int) -> LookUnlocks:
	var unlocks := LookUnlocks.new()
	unlocks.level = maxi(at, 1)
	return unlocks


## Unlocks of the account whose profile file is `profile_path` (a new player when it is missing or
## damaged: level 1, the starting wardrobe).
static func saved() -> LookUnlocks:
	var read := ProfileSave.read(profile_path)
	var profile: Variant = read["profile"]
	return at_level((profile as Profile).level() if profile != null else 1)


## The key under which an option is recorded as owned.
static func key(slot: StringName, id: StringName) -> String:
	return "%s/%s" % [slot, id]


func is_unlocked(slot: StringName, id: StringName, gate: Dictionary) -> bool:
	if gate.is_empty() or owned.has(key(slot, id)):
		return true
	return gate.has("level") and level >= int(gate["level"])


## Whether every piece of costume `index` (`Costumes`) is this player's.
func owns_costume(index: int) -> bool:
	for piece in Costumes.gated_pieces(index):
		if not is_unlocked(piece["slot"], piece["id"], piece["gate"]):
			return false
	return true


## How to own costume `index`, for this player: "Reach level 20 (you are level 12)", or empty when
## they own it. The last piece decides the level.
func costume_instructions(index: int) -> String:
	if owns_costume(index):
		return ""
	var last: Dictionary = {}
	for piece in Costumes.gated_pieces(index):
		if is_unlocked(piece["slot"], piece["id"], piece["gate"]):
			continue
		if last.is_empty() or level_of(piece["gate"]) > level_of(last):
			last = piece["gate"]
	return instructions(last)


func grant(slot: StringName, id: StringName) -> void:
	owned[key(slot, id)] = true


## The level a gate asks for, or 0 when it asks for none.
static func level_of(gate: Dictionary) -> int:
	return int(gate.get("level", 0))


## Words for a locked option: how to get it.
static func describe(gate: Dictionary) -> String:
	if gate.has("level"):
		return "Reach level %d" % int(gate["level"])
	if gate.has("order"):
		return "Finish the order: %s" % gate["order"]
	return ""


## The same, for this player: "Reach level 22 (you are level 12)".
func instructions(gate: Dictionary) -> String:
	if gate.has("level"):
		return "%s (you are level %d)" % [describe(gate), level]
	return describe(gate)
