class_name HudSlots
extends HudPart
## The weapons carried, as a row of numbered places above the ammo card (#682): slot 1, slot 2 (and
## a slot 3 when the player has the perk that carries a third), each showing the weapon's silhouette
## drawn from its model and the number of the key that takes it in hand (`1`, `2`, `3`). The one in
## hand is the lit one. No rounds here: the ammo card is the one home of the numbers; this answers
## "what do I carry and which is in my hand" in a glance.
##
## It lives in the bottom right column beside the ammo card, one card's width, so the places share
## it: two places of about 120 units, three of about 78.

const WIDTH := HudAmmo.WIDTH
const HEIGHT := 64.0
const GAP := float(HudStyle.SM)

## The silhouettes, drawn from the weapon models the first time each is needed.
var silhouettes := WeaponSilhouettes.new()

var _row := HBoxContainer.new()
var _cells: Array[HudSlotCell] = []


func _init() -> void:
	super()
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override(&"separation", int(GAP))
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_row)
	add_child(silhouettes)


func topics() -> Array[StringName]:
	return [HudState.SLOTS]


func refresh() -> void:
	var places := maxi(state.slot_count, state.slot_ids.size())
	_fit_cells(places)
	for i in places:
		var id: StringName = state.slot_ids[i] if i < state.slot_ids.size() else &""
		_cells[i].show_slot(i + 1, id, state.slot_held == i + 1, silhouettes.texture_of(id))


## The cells shown, one per place.
func cells() -> Array[HudSlotCell]:
	return _cells


## How wide one place is when `places` share the strip, a whole number of units so the row never
## runs past the card above which it stands.
static func cell_width(places: int) -> float:
	return floorf((WIDTH - GAP * float(places - 1)) / float(maxi(places, 1)))


func _fit_cells(places: int) -> void:
	while _cells.size() > places:
		_cells.pop_back().queue_free()
	while _cells.size() < places:
		var cell := HudSlotCell.new()
		_cells.append(cell)
		_row.add_child(cell)
	for cell in _cells:
		cell.custom_minimum_size = Vector2(cell_width(places), HEIGHT)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
