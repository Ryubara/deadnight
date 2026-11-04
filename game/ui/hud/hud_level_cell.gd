class_name HudLevelCell
extends RefCounted
## The name cell of a roster row (the scoreboard, the night report) with a player's level: the
## ladder icon before the name and the level after it, in the width the name column already has
## (docs/design/progression.md#the-level-over-a-head). A board where somebody shows a level keeps
## the room for it in every row, a bot's too, so the names stay in one column; a board where nobody
## does (levels turned off, a night with no backend) is as it was.

## The icon's size, the gap after it, and the room the level number has at the other end.
const ICON := 24.0
const GAP := 6.0
const LEVEL_WIDTH := 52.0


## The width the icon and the level take from a name column when `reserve`.
static func taken(reserve: bool) -> float:
	return ICON + GAP + LEVEL_WIDTH if reserve else 0.0


## Whether some entry of `members` (entries of `HudState.team`, their "level" as the board shows it)
## has a level.
static func any(members: Array) -> bool:
	for member: Dictionary in members:
		if int(member.get("level", 0)) > 0:
			return true
	return false


## `name_label` (already as wide as the column less `taken`) with the icon before it and the level
## after it; `shown` is `Vector2i(level, icon)` (zero for none). Without `reserve` it is the label
## itself.
static func wrap(
	name_label: Label, shown: Vector2i, reserve: bool, ink: Color, height: float
) -> Control:
	if not reserve:
		return name_label
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	var slot := CenterContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(ICON + GAP, height)
	if shown.x > 0:
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = LevelIcons.texture(shown.y)
		icon.texture_filter = LevelIcons.FILTER
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(ICON, ICON)
		slot.add_child(icon)
	row.add_child(slot)
	row.add_child(name_label)
	var level := HudStyle.clip(HudStyle.label("", HudStyle.MEDIUM, ink, true))
	HudStyle.set_fitted(
		level,
		str(shown.x) if shown.x > 0 else "",
		HudStyle.MEDIUM,
		LEVEL_WIDTH - float(HudStyle.SM)
	)
	level.custom_minimum_size = Vector2(LEVEL_WIDTH, height)
	level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(level)
	return row
