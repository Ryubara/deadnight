class_name PopupCard
extends Control
## One card of the popup lane, in the look of the menu's "The program" and the night's challenge
## prompt: a paper ticket, cream with dark ink, notched like the HUD's cards, a tear line of dots
## down its left edge. Four kinds (docs/design/progression.md#popups-motion-and-sound):
##
## - LEVEL: the level's icon, the number beside it, a little padding, then `LEVEL UP`, the next
##   thing the ladder gives (its level, then its name, in the same order) and a row of punch
##   holes toward it.
## - TIER: the level card made longer: `TIER UP` and the tier's name, with the marquee's bulbs
##   chasing along its top and bottom edges.
## - UNLOCK: half the height: the item's thumbnail beside `NEW TOP` and the name of the item, both
##   from the wardrobe's own source (`LadderItem`, `ItemIcons`): the icon of a wearable, the paint
##   chip of a colour, the picture of a map; a chip with its slot's letter for what has no art yet.
## - CHALLENGE: `CHALLENGE DONE` and the challenge's words.
## - MORE: `3 NEW ITEMS`, what the cards that did not fit say together.
##
## The card draws itself once (paper, tear line, holes); the lane moves it, fades it and scales its
## icon from outside, so a card standing still costs no redraw.

const LEVEL_SIZE := Vector2(420.0, 108.0)
const UNLOCK_SIZE := Vector2(372.0, 64.0)
const CHALLENGE_SIZE := Vector2(420.0, 92.0)
const MORE_SIZE := Vector2(372.0, 48.0)
## The width every card is centred in.
const WIDTH := LEVEL_SIZE.x

const ICON := 64.0
const CHIP := 48.0
## A calling card's chip is wider: the card keeps its proportions across the chip.
const CARD_CHIP_WIDTH := 112.0
const CHIP_INSET := 3.0
const HOLE_RADIUS := 5.0
const HOLE_GAP := 22.0
const PERFORATION_GAP := 10.0
const PERFORATION_RADIUS := 2.2
const BULB_GAP := 21.0
const BULB_RADIUS := 3.0
const BULBS_INSET := 5.0
## The space between the icon and the number, and between the number and the words (padding): the
## game's one order and two gaps for a level beside a name (`LevelTag`).
const BESIDE := LevelTag.ICON_GAP
const PADDING := LevelTag.NAME_GAP

var kind: PopupQueue.Kind = PopupQueue.Kind.LEVEL
var data: Dictionary = {}
## The icon of a level card, for the lane to stamp.
var icon := TextureRect.new()

var _tokens := UITokens.active()
var _caption := _ink(HudStyle.label("", HudStyle.MEDIUM, _tokens.hot, true, HudStyle.TRACK_CAPTION))
var _number := _ink(HudStyle.label("", HudStyle.BIG, _tokens.ink_on_accent, true))
var _words := _ink(HudStyle.label("", HudStyle.TEXT, _tokens.ink_on_accent))
var _next := HBoxContainer.new()
var _next_label := _ink(HudStyle.label("NEXT", HudStyle.SMALL, _tokens.ink_disabled, false, 1.0))
var _badge := HBoxContainer.new()
var _next_icon := LevelTag.icon_rect(1)
var _next_level := _ink(HudStyle.label("", HudStyle.SMALL, _tokens.hot, true))
var _next_name := _ink(HudStyle.label("", HudStyle.SMALL, _tokens.ink_on_accent))
var _chip := Control.new()
var _chip_letter := _ink(HudStyle.label("", HudStyle.TEXT, _tokens.ink, true))
var _item: Dictionary = {}
var _picture: Texture2D = null
var _punched := 0
var _chase := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for label: Label in [_caption, _number, _words, _next_label, _next_level, _next_name]:
		HudStyle.clip(label)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = LevelIcons.FILTER
	icon.size = Vector2(ICON, ICON)
	icon.pivot_offset = Vector2(ICON, ICON) * 0.5
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_constant_override(&"separation", int(LevelTag.ICON_GAP))
	_badge.add_child(_next_icon)
	_badge.add_child(_next_level)
	_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next.add_theme_constant_override(&"separation", int(LevelTag.NAME_GAP))
	_next_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for part: Control in [_next_label, _badge, _next_name]:
		_next.add_child(part)
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.size = Vector2(CHIP, CHIP)
	_chip.draw.connect(_draw_chip)
	_chip_letter.size = Vector2(CHIP, CHIP)
	_chip_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chip.add_child(_chip_letter)
	for part: Control in [_caption, _number, _words, icon, _next, _chip]:
		add_child(part)
	_words.autowrap_mode = TextServer.AUTOWRAP_OFF


## The size a card of `of_kind` has.
static func size_of(of_kind: PopupQueue.Kind) -> Vector2:
	match of_kind:
		PopupQueue.Kind.UNLOCK:
			return UNLOCK_SIZE
		PopupQueue.Kind.CHALLENGE:
			return CHALLENGE_SIZE
		PopupQueue.Kind.MORE:
			return MORE_SIZE
	return LEVEL_SIZE


## Fills the card: `data` is `{level}` for a level card, `{level, tier_name}` for a tier,
## `{slot, item, level}` for an unlock, `{text, family}` for a challenge and `{count}` for the rest.
func setup(card_kind: PopupQueue.Kind, card_data: Dictionary) -> void:
	kind = card_kind
	data = card_data
	size = size_of(kind)
	custom_minimum_size = size
	for part: Control in [_caption, _number, _words, icon, _next, _chip]:
		part.visible = false
	match kind:
		PopupQueue.Kind.LEVEL, PopupQueue.Kind.TIER:
			_set_level()
		PopupQueue.Kind.UNLOCK:
			_set_unlock()
		PopupQueue.Kind.CHALLENGE:
			_set_challenge()
		PopupQueue.Kind.MORE:
			_set_more()
	queue_redraw()


## The bulbs of a tier card, one step on (the lane calls this as the chase moves).
func set_chase(step: int) -> void:
	if step != _chase:
		_chase = step
		if kind == PopupQueue.Kind.TIER:
			queue_redraw()


## Whether an unlock card shows the item's own picture (an icon, a paint chip, a map's picture)
## and not the letter chip of an item with no art, for tests.
func has_thumbnail() -> bool:
	if kind != PopupQueue.Kind.UNLOCK:
		return false
	var item_kind: int = _item.get("kind", LadderItem.Kind.OTHER)
	return (
		item_kind != LadderItem.Kind.OTHER
		and (item_kind != LadderItem.Kind.MAP or _picture != null)
	)


## How many holes are punched (a level card), for tests.
func punched() -> int:
	return _punched


## The words the card says, top to bottom, for tests and for the card's own accessible text.
func lines() -> Array[String]:
	var out: Array[String] = []
	for part: Label in [_caption, _number, _words, _next_level, _next_name]:
		var shown := part.visible and (part.get_parent() != _next or _next.visible)
		if shown and part.text != "":
			out.append(part.text)
	return out


func _set_level() -> void:
	var level := int(data.get("level", 1))
	var is_tier := kind == PopupQueue.Kind.TIER
	var top := (size.y - ICON) * 0.5
	icon.texture = LevelIcons.texture(level)
	icon.position = Vector2(float(HudStyle.PAD_LEFT) + 2.0, top)
	icon.visible = true
	var number_at := icon.position.x + ICON + BESIDE
	_place(_number, Rect2(number_at, top, 84.0, ICON))
	HudStyle.set_fitted(_number, str(level), HudStyle.BIG, 84.0)
	var words_at := number_at + 84.0 + PADDING
	var room := size.x - words_at - float(HudStyle.PAD)
	_place(_caption, Rect2(words_at, 8.0, room, 34.0))
	HudStyle.set_text(_caption, "TIER UP" if is_tier else "LEVEL UP")
	if is_tier:
		_place(_words, Rect2(words_at, 46.0, room, 34.0))
		HudStyle.set_fitted(
			_words, String(data.get("tier_name", "")).to_upper(), HudStyle.MEDIUM, room
		)
		_words.add_theme_color_override(&"font_color", _tokens.ink_on_accent)
		_punched = 0
		return
	var next := PopupLadder.next_unlock(level)
	_punched = PopupLadder.punched(level)
	_next.visible = not next.is_empty()
	if not next.is_empty():
		_next.position = Vector2(words_at, 46.0)
		_next.size = Vector2(room, 24.0)
		LevelTag.set_icon(_next_icon, int(next["level"]))
		HudStyle.set_text(_next_level, str(int(next["level"])))
		HudStyle.set_text(_next_name, PopupLadder.name_of(next["slot"], next["item"]))
		_next_level.custom_minimum_size.x = LevelTag.level_room(
			_next_level.get_theme_font(&"font"), HudStyle.SMALL
		)
		_next_label.custom_minimum_size.x = 46.0
		_next_name.custom_minimum_size.x = 40.0


func _set_unlock() -> void:
	var slot: StringName = data.get("slot", &"")
	var item: StringName = data.get("item", &"")
	_item = LadderItem.of(slot, item)
	_picture = null
	if _item["kind"] == LadderItem.Kind.MAP:
		_picture = (_item["info"] as MapInfo).preview()
	_chip.visible = true
	_chip.size = Vector2(CARD_CHIP_WIDTH if _item["kind"] == LadderItem.Kind.CARD else CHIP, CHIP)
	_chip.position = Vector2(float(HudStyle.PAD_LEFT) + 2.0, (size.y - CHIP) * 0.5)
	HudStyle.set_text(_chip_letter, "" if has_thumbnail() else PopupLadder.chip_letter(slot))
	_chip.queue_redraw()
	var at := _chip.position.x + _chip.size.x + PADDING * 0.75
	var room := size.x - at - float(HudStyle.PAD)
	_place(_caption, Rect2(at, 4.0, room, 24.0))
	_caption.add_theme_font_size_override(&"font_size", HudStyle.SMALL)
	HudStyle.set_text(_caption, PopupLadder.caption_of(slot))
	_place(_words, Rect2(at, 28.0, room, 30.0))
	HudStyle.set_fitted(_words, _item["name"], HudStyle.TEXT, room)
	_punched = 0


func _set_challenge() -> void:
	var at := float(HudStyle.PAD_LEFT) + 2.0
	var room := size.x - at - float(HudStyle.PAD)
	_place(_caption, Rect2(at, 6.0, room, 30.0))
	_caption.add_theme_font_size_override(&"font_size", HudStyle.TEXT)
	HudStyle.set_text(_caption, "CHALLENGE DONE")
	_place(_words, Rect2(at, 38.0, room, 48.0))
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.clip_text = true
	_words.max_lines_visible = 2
	_words.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_words.add_theme_constant_override(&"line_spacing", -2)
	HudStyle.set_text(_words, String(data.get("text", "")))
	_punched = 4


func _set_more() -> void:
	var count := int(data.get("count", 1))
	_place(_caption, Rect2(0.0, 0.0, size.x, size.y))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override(&"font_size", HudStyle.TEXT)
	HudStyle.set_text(_caption, "%d NEW ITEM%s" % [count, "" if count == 1 else "S"])


func _place(part: Control, rect: Rect2) -> void:
	part.position = rect.position
	part.size = rect.size
	part.visible = true


## Dark ink on paper: no outline, no shadow under the letters.
static func _ink(label: Label) -> Label:
	label.add_theme_constant_override(&"outline_size", 0)
	(label as HudLabel).halo_size = 0
	label.add_theme_constant_override(&"shadow_offset_y", 0)
	label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
	return label


func _draw() -> void:
	var shapes := HudShapes.new()
	var rect := Rect2(Vector2.ZERO, size)
	var outline := HudStyle.ticket_points(rect)
	var shadow := PackedVector2Array()
	for point in outline:
		shadow.append(point + HudStyle.SHADOW)
	shapes.polygon(shadow, _tokens.shadow)
	shapes.polygon(outline, _tokens.ink)
	var x := HudStyle.STRIPE + 4.0
	var y := HudStyle.NOTCH + 4.0
	while y < size.y - HudStyle.NOTCH:
		shapes.circle(Vector2(x, y), PERFORATION_RADIUS, _tokens.ink_disabled)
		y += PERFORATION_GAP
	if kind == PopupQueue.Kind.LEVEL:
		_add_holes(shapes)
	elif kind == PopupQueue.Kind.TIER:
		_add_bulbs(shapes)
	elif kind == PopupQueue.Kind.CHALLENGE:
		_add_stamp(shapes)
	shapes.flush(self)


## The punch holes of a level card, under the next unlock, from the left.
func _add_holes(shapes: HudShapes) -> void:
	var at := _next.position.x + HOLE_RADIUS + 1.0
	var y := size.y - 22.0
	for i in PopupLadder.HOLES:
		var centre := Vector2(at + i * HOLE_GAP, y)
		if i < _punched:
			shapes.circle(centre, HOLE_RADIUS, _tokens.bg)
		else:
			shapes.circle(centre, HOLE_RADIUS, _tokens.ink_disabled)
			shapes.circle(centre, HOLE_RADIUS - 2.0, _tokens.ink)


## The marquee's bulbs along the top and the bottom edge of a tier card, every third one lit and
## the lit ones moving a step each time the lane calls `set_chase`.
func _add_bulbs(shapes: HudShapes) -> void:
	var count := int((size.x - 2.0 * HudStyle.NOTCH) / BULB_GAP)
	for i in count:
		var lit := (i + _chase) % 3 == 0
		var colour := _tokens.hot if lit else _tokens.ink_disabled
		var x := HudStyle.NOTCH + BULB_GAP * (i + 0.5)
		shapes.circle(Vector2(x, BULBS_INSET), BULB_RADIUS, colour)
		shapes.circle(Vector2(size.x - x, size.y - BULBS_INSET), BULB_RADIUS, colour)


## The last hole of a finished challenge, punched: a ring of four holes at the card's right.
func _add_stamp(shapes: HudShapes) -> void:
	var y := 17.0
	for i in 4:
		shapes.circle(Vector2(size.x - 24.0 - i * 18.0, y), HOLE_RADIUS - 1.0, _tokens.bg)


## The thumbnail on its plate, the wardrobe cell's own drawing at the size of a card's chip.
func _draw_chip() -> void:
	var rect := Rect2(Vector2.ZERO, _chip.size)
	var inner := rect.grow(-CHIP_INSET)
	_chip.draw_rect(rect, _tokens.ink_on_accent)
	if not has_thumbnail():
		_chip.draw_rect(rect.grow(-2.0), PopupLadder.CHIP_FALLBACK)
		return
	_chip.draw_rect(rect.grow(-2.0), _tokens.surface_raised)
	match int(_item["kind"]):
		LadderItem.Kind.PART:
			ItemIcons.draw(_chip, inner, _item["slot"], _item["id"], false)
		LadderItem.Kind.COLOUR:
			ItemIcons.draw_chip(_chip, inner, _item["colour"], false)
		LadderItem.Kind.CARD:
			PlateDraw.card(_chip, inner, _item["plate"])
		LadderItem.Kind.EMBLEM:
			PlateDraw.emblem(_chip, inner, _item["plate"])
		LadderItem.Kind.MAP:
			var wide := Vector2(inner.size.x, inner.size.x * 9.0 / 16.0)
			var at := inner.position + (inner.size - wide) * 0.5
			_chip.draw_texture_rect(_picture, Rect2(at, wide), false)
