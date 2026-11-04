class_name WardrobeCell
extends Button
## One choice of the wardrobe's grid: a plate with the item's icon over its name.
##
## Four looks, by `kind` and `locked`:
##   - a wearable: its icon (`ItemIcons`) and its name, lit; a lock turns it into the silhouette of
##     the same icon with the name `???` (the maintainer's rule, #1065);
##   - a colour: a paint chip and its name, the same way;
##   - a free choice (a face, a hair style, a mouth): its name on the plate. Nothing free carries a
##     lock mark;
##   - "None" of a slot that may be empty: a slashed ring;
##   - a costume (#1066): a figure in the costume's colours, or its silhouette and `???` until the
##     player owns every piece;
##   - the "Default" option of a costume's colours: its three colours as bands. It is `off` while
##     the look wears no costume: a press says so and changes nothing.
## `soon` is a wearable the player has earned and the art does not have yet: it is lit, and cannot
## be worn.
##
## The pointer or the focus on a cell says what it is on `shown` (the screen's detail line reads
## it); a press on a lit cell is `chosen`, on a locked one `refused`. Nothing here changes a look.

## A lit cell was pressed (or accepted): the screen puts it on the soldier.
signal chosen
## A locked cell, or one with no model yet, was pressed: it shakes and says why (the screen).
signal refused
## The pointer or the focus came to this cell, or left it for another (`shown` is false then).
signal shown(on: bool)

enum Kind { PART, COLOUR, TEXT, NONE, COSTUME, DEFAULT }

## The size of a cell: the icon's plate, and the name's line under it.
const SIZE := Vector2(148.0, 170.0)
const SIZE_COMPACT := Vector2(104.0, 114.0)
## A colour's cell (and the Default option's) is smaller: sixteen of them fit two rows of the grid.
const SIZE_CHIP := Vector2(96.0, 112.0)
const SIZE_CHIP_COMPACT := Vector2(84.0, 100.0)
## A free choice with no drawing (a face, a mouth) is its name on a low plate, a tap target high.
const SIZE_NAME := Vector2(148.0, 76.0)
const SIZE_NAME_COMPACT := Vector2(104.0, 62.0)
const ICON := 96.0
const ICON_COMPACT := 64.0
const ICON_CHIP := 64.0
const ICON_CHIP_COMPACT := 52.0
const NAME_SIZE := 22
const NAME_SIZE_COMPACT := 20
const NAME_MIN := 15
const PAD := 8.0
const CHOSEN_BORDER := 4

## What the cell is: filled by the screen.
var kind := Kind.PART:
	set(value):
		kind = value
		_fit()
		queue_redraw()
## The catalogue slot (or colour channel) and the id of the item.
var slot: StringName = &""
var id: StringName = &""
## The place in the catalogue (`LookCatalog.options`, `palette`), or -1 for a piece with no model.
var index := -1
## The name shown when it is not locked.
var title := "":
	set(value):
		title = value
		_refresh_name()
## The colour of a paint chip.
var colour := Color.WHITE
## Locked: the silhouette and `???`. `soon`: earned, but not drawn yet.
var locked := false:
	set(value):
		locked = value
		_refresh_name()
var soon := false
## The one the look wears now.
var worn := false:
	set(value):
		worn = value
		_refresh_name()
		queue_redraw()
## How to get it, for a locked one ("Reach level 22 (you are level 12)").
var instructions := ""
## What a press on a lit cell does, for the detail line ("press to wear").
var action := "press to wear"
## Why a press does nothing while the cell is not locked ("wear a costume first"); empty when it
## does something. A cell that is `off` is dim.
var off_reason := "":
	set(value):
		off_reason = value
		_refresh_name()
## The colours a costume's figure (`skin`, `hair`, `main`, `second`, `trim`) or the Default
## option's bands (`main`, `second`, `trim`) are drawn in.
var swatches := {}:
	set(value):
		swatches = value
		queue_redraw()
var compact := false:
	set(value):
		compact = value
		_fit()
		queue_redraw()

var _tokens := UITokens.active()
var _ring: UIFocusRing
var _fill := StyleBoxFlat.new()


func _init() -> void:
	UiSounds.wire(self)
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	toggle_mode = false
	_ring = UIFocusRing.new(_tokens, _tokens.radius_md)
	_fill.anti_aliasing = true
	_fill.set_corner_radius_all(_tokens.radius_md)
	_fit()
	pressed.connect(_on_pressed)
	focus_entered.connect(_on_lit.bind(true))
	focus_exited.connect(_on_lit.bind(false))
	mouse_entered.connect(_on_lit.bind(true))
	mouse_exited.connect(_on_lit.bind(false))


## A cell is a map card to the sound table: a hover and a focus tick, a select on a press, and a
## refusal when it is locked.
func ui_sound_role() -> StringName:
	return &"map_card_locked" if locked or soon or is_off() else &"map_card"


## The name the cell shows: `???` while it is locked.
func shown_name() -> String:
	return "???" if locked else title


## The two lines the screen's detail line reads for this cell: the name, then what it asks of the
## player or what a press does.
func detail() -> String:
	if locked:
		return "%s - %s" % [shown_name(), instructions]
	if is_off():
		return "%s - %s" % [title, off_reason]
	if soon:
		return "%s - not drawn yet, it comes in a later update" % title
	if worn:
		return "%s - wearing" % title
	return "%s - %s" % [title, action]


## Whether a press does nothing for a reason that is not a lock.
func is_off() -> bool:
	return off_reason != ""


func _fit() -> void:
	if kind == Kind.COLOUR or kind == Kind.DEFAULT:
		custom_minimum_size = SIZE_CHIP_COMPACT if compact else SIZE_CHIP
	elif kind == Kind.TEXT:
		custom_minimum_size = SIZE_NAME_COMPACT if compact else SIZE_NAME
	else:
		custom_minimum_size = SIZE_COMPACT if compact else SIZE


func _icon_side() -> float:
	if kind == Kind.COLOUR or kind == Kind.DEFAULT:
		return ICON_CHIP_COMPACT if compact else ICON_CHIP
	return ICON_COMPACT if compact else ICON


func _refresh_name() -> void:
	accessibility_name = (
		"Locked item, %s" % instructions if locked else (title + (", wearing" if worn else ""))
	)
	if is_off():
		accessibility_name = "%s, %s" % [title, off_reason]
	queue_redraw()


func _on_pressed() -> void:
	if locked or soon or is_off():
		refused.emit()
		UIMotion.shake(self)
	else:
		chosen.emit()


func _on_lit(on: bool) -> void:
	queue_redraw()
	shown.emit(on)


func _draw() -> void:
	var lit := has_focus() or is_hovered()
	var plate := Rect2(Vector2.ZERO, size)
	var dark := locked
	_fill.bg_color = _tokens.bg if dark else _tokens.surface_raised
	if lit:
		_fill.bg_color = _fill.bg_color.lightened(0.08)
	var border := CHOSEN_BORDER if worn else _tokens.border
	_fill.border_color = _tokens.accent_bright if worn else _tokens.outline
	_fill.set_border_width_all(border)
	draw_style_box(_fill, plate)
	var icon_side := _icon_side()
	var icon := Rect2(Vector2((size.x - icon_side) * 0.5, PAD), Vector2(icon_side, icon_side))
	match kind:
		Kind.PART:
			ItemIcons.draw(self, icon, slot, id, locked)
		Kind.COLOUR:
			ItemIcons.draw_chip(self, icon, colour, locked)
		Kind.NONE:
			ItemIcons.draw_none(self, icon, _tokens.ink_muted)
		Kind.COSTUME:
			ItemIcons.draw_costume(self, icon, swatches, locked)
		Kind.DEFAULT:
			var bands: Array = [
				swatches.get("main", Color.WHITE),
				swatches.get("second", Color.WHITE),
				swatches.get("trim", Color.WHITE)
			]
			ItemIcons.draw_swatches(self, icon, bands, 0.35 if is_off() else 1.0)
		Kind.TEXT:
			pass
	_draw_name(plate, icon)
	if locked:
		_draw_padlock(Vector2(plate.size.x - 18.0, 20.0))
	if worn:
		_draw_check(Vector2(18.0, 20.0))
	if is_hovered() and not worn:
		draw_rect(plate.grow(-1.0), Color(MenuLook.AMBER, 0.8), false, 3.0)
	if has_focus() and not UIInputMode.pointer:
		_ring.draw(self, plate, 1.0)


func _draw_name(plate: Rect2, icon: Rect2) -> void:
	var font: Font = _tokens.font_text
	var text := shown_name()
	var room := plate.size.x - PAD * 2.0
	var base := NAME_SIZE_COMPACT if compact else NAME_SIZE
	var font_size := base
	while (
		font_size > NAME_MIN
		and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > room
	):
		font_size -= 1
	var ink := _tokens.ink_disabled if locked or is_off() else _tokens.ink
	var band := Rect2(PAD, icon.end.y, room, plate.size.y - icon.end.y - PAD)
	if kind == Kind.TEXT:
		band = Rect2(PAD, 0.0, room, plate.size.y)
		font_size = mini(font_size + 4, 28)
	var baseline := (
		band.position.y
		+ (band.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	)
	draw_string(
		font,
		Vector2(band.position.x, baseline),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		room,
		font_size,
		ink
	)


func _draw_padlock(at: Vector2) -> void:
	var colour_now := _tokens.ink_disabled
	var body := Rect2(at + Vector2(-7.0, -1.0), Vector2(14.0, 11.0))
	draw_rect(body, colour_now)
	draw_arc(at + Vector2(0.0, -1.0), 5.0, PI, TAU, 12, colour_now, 2.5, true)


func _draw_check(at: Vector2) -> void:
	draw_circle(at, 11.0, _tokens.accent_bright)
	draw_polyline(
		PackedVector2Array(
			[at + Vector2(-5.0, 0.0), at + Vector2(-1.5, 4.0), at + Vector2(5.5, -4.0)]
		),
		_tokens.ink_on_accent,
		2.8,
		true
	)
