class_name LevelCurve
extends RefCounted
## The account level, computed from raw XP. Only XP is ever stored; the level, the bar and the tier
## are read off this table, so a retune of `TIER_COSTS` needs no migration of any save.
##
## The climb rises and never goes flat: a tier of five levels asks the same, and each tier asks
## more than the one before ("it takes longer to level up the higher you go", the maintainer,
## 2026-11-04). 18,010 XP in all to reach level 55, about 8 hours of nights at 300 or more kills
## (docs/design/progression.md#xp-and-the-ladder-of-55). Levels run 1 to `MAX_LEVEL`; XP past it
## is kept and shows a full bar, and nothing is awarded for it until prestige is decided (#1055).

const MAX_LEVEL := 55
const TIER_SIZE := 5
## What a lobby member's `icon` starts with: `level_07`, the file name of the ladder's icon.
const ICON_PREFIX := "level_"
## XP to leave each level of a tier, tier by tier (levels 1-5, 6-10, ... 51-55). Level 55 is the
## last, so the last tier's four paying levels (51 to 54) are the only ones that cost 590.
const TIER_COSTS: Array[int] = [85, 135, 185, 235, 290, 340, 390, 440, 490, 540, 590]
## The tiers' names, the drive-in's billing (docs/design/progression.md).
const TIER_NAMES: Array[String] = [
	"Doors Open",
	"Cartoon",
	"Newsreel",
	"Intermission",
	"Trailers",
	"Second Feature",
	"Main Feature",
	"Late Show",
	"Midnight Show",
	"Headliner",
	"Last Reel",
]

## The tier a level is in, 0 for levels 1 to 5 up to 10 for levels 51 to 55 (an index into
## `TIER_COSTS` and `TIER_NAMES`). A level outside 1 to `MAX_LEVEL` is clamped into it.
@warning_ignore("integer_division")
static func tier_of(level: int) -> int:
	return (clampi(level, 1, MAX_LEVEL) - 1) / TIER_SIZE


## What a server says of a seat's level, as `Vector2i(level, icon)` (the level 1 to `MAX_LEVEL`, the
## icon the same range): from a level alone (the server's `levels`: the icon is the level's own), a
## `Vector2i`, or a pair `[level, icon]` of numbers. `Vector2i.ZERO` for anything else, a level
## outside the ladder too, since a client must not index outside the atlas with a server's word. An
## icon outside the ladder follows the level.
static func seat_tag(held: Variant) -> Vector2i:
	var pair := Vector2i.ZERO
	if typeof(held) == TYPE_INT or typeof(held) == TYPE_FLOAT:
		pair = Vector2i(int(held), int(held))
	elif typeof(held) == TYPE_VECTOR2I:
		pair = held
	elif typeof(held) == TYPE_ARRAY and (held as Array).size() == 2:
		var level: Variant = held[0]
		var icon: Variant = held[1]
		if (
			(typeof(level) == TYPE_INT or typeof(level) == TYPE_FLOAT)
			and (typeof(icon) == TYPE_INT or typeof(icon) == TYPE_FLOAT)
		):
			pair = Vector2i(int(level), int(icon))
	if pair.x < 1 or pair.x > MAX_LEVEL:
		return Vector2i.ZERO
	return Vector2i(pair.x, pair.x if pair.y < 1 or pair.y > MAX_LEVEL else pair.y)


## The level and icon of a lobby member as the backend lists them (`level`, and `icon` as the file
## name `level_07`), as `Vector2i(level, icon)`; `Vector2i.ZERO` when the level is missing or not a
## whole number of the ladder. The icon follows the level when it is missing or wrong.
static func member_tag(level: Variant, icon_name: Variant) -> Vector2i:
	if typeof(level) != TYPE_FLOAT and typeof(level) != TYPE_INT:
		return Vector2i.ZERO
	if float(level) != float(int(level)):
		return Vector2i.ZERO
	var icon := int(level)
	var named := str(icon_name)
	if named.begins_with(ICON_PREFIX) and named.substr(ICON_PREFIX.length()).is_valid_int():
		icon = named.substr(ICON_PREFIX.length()).to_int()
	return seat_tag(Vector2i(int(level), icon))


## The name of the tier a level is in.
static func tier_name(level: int) -> String:
	return TIER_NAMES[tier_of(level)]


## XP to go from `level` to the next (0 at `MAX_LEVEL`, where there is no next).
static func to_leave(level: int) -> int:
	if level < 1 or level >= MAX_LEVEL:
		return 0
	return TIER_COSTS[tier_of(level)]


## Total XP at which `level` begins (level 1 begins at 0). Past `MAX_LEVEL` it is the total for 55.
static func xp_for(level: int) -> int:
	var total := 0
	for step in range(1, mini(level, MAX_LEVEL)):
		total += to_leave(step)
	return total


## XP to reach `MAX_LEVEL`.
static func total() -> int:
	return xp_for(MAX_LEVEL)


## The level raw XP has reached, 1 to `MAX_LEVEL` (XP past the top stays on the top).
static func level_of(xp: int) -> int:
	var level := 1
	var left := maxi(xp, 0)
	while level < MAX_LEVEL and left >= to_leave(level):
		left -= to_leave(level)
		level += 1
	return level


## XP still needed for the next level (0 at the top).
static func to_next(xp: int) -> int:
	var level := level_of(xp)
	if level >= MAX_LEVEL:
		return 0
	return xp_for(level + 1) - maxi(xp, 0)


## XP earned inside the current level.
static func xp_in_level(xp: int) -> int:
	return maxi(xp, 0) - xp_for(level_of(xp)) if level_of(xp) < MAX_LEVEL else 0


## How far to the next level, 0 to 1 (1 at the top: a full bar).
static func fraction(xp: int) -> float:
	var level := level_of(xp)
	if level >= MAX_LEVEL:
		return 1.0
	return clampf(float(xp_in_level(xp)) / float(to_leave(level)), 0.0, 1.0)
