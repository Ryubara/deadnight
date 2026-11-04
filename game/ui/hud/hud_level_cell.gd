class_name HudLevelCell
extends RefCounted
## The name cell of a roster row (the scoreboard, the night report) with a player's level: the
## ladder icon, the level right beside it and then the name, in the order and with the gaps of
## `LevelTag` (docs/design/progression.md#the-level-over-a-head). A row with no level (a bot, a
## seat without one, levels turned off) is the name alone, as wide as its column: no gap before it.
## A row with a level keeps the room of a two-digit level, so the names of the people start on one
## line and a level of 55 is never cut.

## The room a level has, in the board's type: measured once.
static var _level_room := -1.0


## The width of the level's room in the board's type (two digits).
static func level_room() -> float:
	if _level_room < 0.0:
		var probe := HudStyle.label("", HudStyle.MEDIUM, Color.WHITE, true)
		_level_room = LevelTag.level_room(probe.get_theme_font(&"font"), HudStyle.MEDIUM)
		probe.free()
	return _level_room


## The width the badge and the gap before the name take from a name column; nothing without a level.
static func taken(shown: Vector2i) -> float:
	return LevelTag.taken(level_room()) if shown.x > 0 else 0.0


## `name_label` (already as wide as the column less `taken(shown)`) with the badge before it;
## `shown` is `Vector2i(level, icon)` (zero for none, and then it is the label itself).
static func wrap(name_label: Label, shown: Vector2i, ink: Color, height: float) -> Control:
	if shown.x < 1:
		return name_label
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(LevelTag.NAME_GAP))
	var badge := HBoxContainer.new()
	badge.name = &"Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_constant_override(&"separation", int(LevelTag.ICON_GAP))
	var slot := CenterContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(LevelTag.ICON, height)
	var icon := LevelTag.icon_rect(shown.y)
	icon.name = &"Icon"
	slot.add_child(icon)
	badge.add_child(slot)
	var level := HudStyle.clip(HudStyle.label("", HudStyle.MEDIUM, ink, true))
	level.name = &"Level"
	HudStyle.set_fitted(level, str(shown.x), HudStyle.MEDIUM, level_room())
	level.custom_minimum_size = Vector2(level_room(), height)
	level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	badge.add_child(level)
	row.add_child(badge)
	name_label.name = &"Name"
	row.add_child(name_label)
	return row
