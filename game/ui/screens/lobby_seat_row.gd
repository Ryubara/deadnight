class_name LobbySeatRow
extends RefCounted
## One seat's row in the lobby (`LobbyScreen`): its nodes, and the level and plate shown on them.

const SEAT_NUMBER_WIDTH := 48.0
const TAG_WIDTH := 96.0
## A seat row's height, which the card behind it fits and the emblem is cut to.
const SEAT_ROW_HEIGHT := 40.0


## The calling card, emblem and frame a member chose, only those the game has (the backend lists
## what the account chose; the night holds it to what the account owns).
static func plate_of(member: Dictionary) -> Dictionary:
	var catalog := PlateCatalog.shipped()
	var card := StringName(str(member.get("card", "")))
	var emblem := StringName(str(member.get("emblem", "")))
	var frame := StringName(str(member.get("frame", "")))
	return {
		"card": card if catalog.has(PlateCatalog.CARD, card) else &"",
		"emblem": emblem if catalog.has(PlateCatalog.EMBLEM, emblem) else &"",
		"frame": frame if catalog.has(PlateCatalog.FRAME, frame) else &"",
	}


## The card behind a seat's row, the emblem after the name and the frame round it (`PlateRow`);
## gone for none.
static func show_plate(row: Dictionary, plate: Dictionary) -> void:
	var card := row["card"] as CardArt
	card.card_id = plate.get("card", &"")
	card.visible = card.card_id != &""
	var emblem := row["emblem"] as EmblemArt
	emblem.emblem_id = plate.get("emblem", &"")
	emblem.visible = emblem.emblem_id != &""
	var frame := row["frame"] as FrameArt
	frame.frame_id = plate.get("frame", &"")
	frame.visible = frame.frame_id != &""
	# The seat keeps the border's room clear at both ends, so the number is not under it.
	var clear := PlateRow.frame_clear(frame.frame_id, SEAT_ROW_HEIGHT)
	var inset := (row["box"] as Control).get_theme_stylebox(&"panel") as StyleBoxEmpty
	inset.content_margin_left = clear
	inset.content_margin_right = clear
	frame.grow = Vector2(clear, 0.0)


## The icon and the level of a seat's row, the badge before the name (`LevelTag`): gone for a bot,
## an open seat or a seat without a level, and then the name starts right after the seat number.
static func show_level(row: Dictionary, held: Vector2i) -> void:
	var badge := row["badge"] as Control
	badge.visible = held.x > 0
	var level := row["level"] as Label
	level.text = str(held.x) if held.x > 0 else ""
	if held.x > 0:
		LevelTag.set_icon(row["icon"] as TextureRect, held.y)
		_place_icon(row["icon"] as TextureRect, level, held.y)


## The icon's top in its slot: its body is centred on the level's digits, which sit at the font's
## height in a line that starts at the top of the label (`LevelTag.icon_top`).
static func _place_icon(icon: TextureRect, level: Label, icon_level: int) -> void:
	icon.position.y = LevelTag.icon_top_in_line(
		0.0, level.get_theme_font(&"font"), level.get_theme_font_size(&"font_size"), icon_level
	)
	# The row is as tall as the icon reaches (the icon was a child of the row's box, which was as
	# tall as it).
	(icon.get_parent() as Control).custom_minimum_size.y = (
		maxf(icon.position.y, 0.0) + LevelTag.ICON
	)


## A seat's row, added to `seats`, as the nodes `show_plate` and `show_level` fill.
static func make(seats: VBoxContainer, tokens: UITokens) -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", tokens.space_md)
	var number := _label("", UILabel.Style.BODY)
	number.custom_minimum_size.x = SEAT_NUMBER_WIDTH
	# The seat's player: badge (icon, level), then the name, with the gaps of `LevelTag`.
	var who := HBoxContainer.new()
	who.name = &"Who"
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_constant_override(&"separation", int(LevelTag.NAME_GAP))
	var badge := HBoxContainer.new()
	badge.name = &"Badge"
	badge.add_theme_constant_override(&"separation", int(LevelTag.ICON_GAP))
	badge.visible = false
	# The icon is set on the digits (`_place_icon`), in a slot of its own width that takes the row's
	# height from the level beside it.
	var slot := Control.new()
	slot.name = &"IconSlot"
	slot.custom_minimum_size.x = LevelTag.ICON
	var icon := LevelTag.icon_rect(1)
	icon.name = &"Icon"
	icon.size = Vector2.ONE * LevelTag.ICON
	slot.add_child(icon)
	var level := _label("", UILabel.Style.BODY)
	level.name = &"Level"
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# The line starts at the top of the row's box, where `_place_icon` counts from.
	level.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	level.size_flags_vertical = Control.SIZE_FILL
	var seat_name := _label("", UILabel.Style.BODY)
	seat_name.name = &"Name"
	seat_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seat_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var tag := _label("", UILabel.Style.OVERLINE)
	tag.custom_minimum_size.x = TAG_WIDTH
	badge.add_child(slot)
	badge.add_child(level)
	who.add_child(badge)
	who.add_child(seat_name)
	# The emblem follows the name's room; the card is a chip behind the whole row.
	var emblem := EmblemArt.make(&"", PlateRow.emblem_side(SEAT_ROW_HEIGHT))
	emblem.name = &"Emblem"
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	emblem.visible = false
	box.add_child(number)
	box.add_child(who)
	box.add_child(emblem)
	box.add_child(tag)
	var holder := PanelContainer.new()
	holder.name = &"Seat"
	holder.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	var card := CardArt.new()
	card.name = &"Card"
	card.by_height = true
	card.veil = Color(tokens.bg, PlateRow.VEIL)
	card.visible = false
	holder.add_child(card)
	holder.add_child(box)
	var frame := FrameArt.new()
	frame.name = &"Frame"
	frame.visible = false
	holder.add_child(frame)
	seats.add_child(holder)
	# Two digits of room, so the names of the people start on one line (a level of 55 is whole).
	level.custom_minimum_size.x = LevelTag.level_room(
		level.get_theme_font(&"font"), level.get_theme_font_size(&"font_size")
	)
	return {
		"box": holder,
		"card": card,
		"emblem": emblem,
		"frame": frame,
		"number": number,
		"who": who,
		"badge": badge,
		"icon": icon,
		"name": seat_name,
		"level": level,
		"tag": tag
	}


static func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
