class_name HudSlotCell
extends Control
## One numbered place for a weapon on the slot strip (#682): a small ticket with the slot's number
## in a corner and the weapon's silhouette across it. The one in hand is the lit one, amber paper
## with dark ink; a weapon put away is cream on dark paper; an empty place is the number alone, dim.
## Light against dark carries the difference, not the colour alone.

## The number's type.
const NUMBER_SIZE := HudStyle.SMALL
## How far in from the cell's edges the silhouette stays.
const PICTURE_PAD := 3.0
## The cell's corner cut, a little smaller than a card's.
const NOTCH := HudStyle.NOTCH * 0.6

var number := 0
var weapon_id: StringName = &""
var held := false

var _tokens := UITokens.active()
var _number := HudStyle.label("", NUMBER_SIZE, _tokens.ink, true)
var _picture := TextureRect.new()
var _name := HudStyle.clip(HudStyle.label("", HudStyle.MIN_TEXT, _tokens.ink_muted))


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_picture)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_name)
	add_child(_number)
	resized.connect(_layout)


## Shows `slot_number` holding `id` (`&""` for an empty place), lit when `in_hand`. `picture` is the
## weapon's silhouette; without one (a weapon with no model) its name stands in.
func show_slot(slot_number: int, id: StringName, in_hand: bool, picture: Texture2D) -> void:
	number = slot_number
	weapon_id = id
	held = in_hand
	_picture.texture = picture
	_picture.visible = picture != null
	_name.visible = id != &"" and picture == null
	if _name.visible:
		var def := WeaponCatalog.get_def(id)
		HudStyle.set_text(_name, (def.display_name if def != null else String(id)).to_upper())
	var ink := ink_colour()
	_picture.modulate = ink
	_name.add_theme_color_override(&"font_color", ink)
	_number.add_theme_color_override(&"font_color", ink)
	HudStyle.set_text(_number, str(slot_number))
	_layout()
	queue_redraw()


## The colour of the number and the weapon: dark on the lit paper, cream on the dark, dim when the
## place is empty.
func ink_colour() -> Color:
	if held:
		return _tokens.ink_on_accent
	return _tokens.ink if weapon_id != &"" else _tokens.ink_disabled


## The picture's rectangle inside the cell (the part the weapon's texture is fitted to).
func picture_rect() -> Rect2:
	return Rect2(_picture.position, _picture.size)


## Whether the weapon's silhouette shows (a texture is set and shown).
func shows_picture() -> bool:
	return _picture.visible and _picture.texture != null


## The number's rectangle in the cell.
func number_rect() -> Rect2:
	return Rect2(_number.position, _number.get_minimum_size())


func _layout() -> void:
	var pad := Vector2(PICTURE_PAD, PICTURE_PAD)
	_picture.position = pad
	_picture.size = size - pad * 2.0
	_name.position = pad
	_name.size = size - pad * 2.0
	_number.position = Vector2(NOTCH * 0.6 + 2.0, 0.0)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var outline := HudStyle.ticket_points(rect, NOTCH)
	var shadow := PackedVector2Array()
	for point in outline:
		shadow.append(point + HudStyle.SHADOW * 0.75)
	var paper := _tokens.accent if held else _tokens.surface_raised
	if not held and weapon_id == &"":
		paper = _tokens.surface
	var edge := outline.duplicate()
	edge.append(outline[0])
	# One command for the three shapes (`HudShapes`).
	var shapes := HudShapes.new()
	shapes.polygon(shadow, _tokens.shadow)
	shapes.polygon(outline, paper)
	shapes.polyline(edge, _tokens.accent_bright if held else _tokens.outline, float(_tokens.border))
	shapes.flush(self)
