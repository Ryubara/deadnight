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
##
## Under a finger (`fit_touch`, #1280) it is the phone's weapon control and the HUD's mirror at
## once: each place is at least a fingertip wide and high, and a place for the grenades stands after
## the weapons. The touch layer reads the places' boxes (`touch_zones`) and presses the action of
## the one a finger lands on: the key of that slot, or the grenade button (held to cook).

const WIDTH := HudAmmo.WIDTH
const HEIGHT := 64.0
const GAP := float(HudStyle.SM)
## Under a finger a weapon's place is this much wider than the fingertip it is at least as high as:
## the silhouette is a long shape.
const TOUCH_WIDE := 1.25
## The action a press on the grenades' place sends, held while the pin is out.
const GRENADE_ACTION := &"throw_grenade"

## The silhouettes, drawn from the weapon models the first time each is needed.
var silhouettes := WeaponSilhouettes.new()

## True while a finger holds the screen: the places are fingertip-sized and the grenades have one.
var touch := false
## The grenades' place, there only while `touch` (a desktop's strip is what it was).
var grenade_cell: HudGrenadeCell

## Whether the cells were made from the state once.
var _built := false
var _row := HBoxContainer.new()
var _cells: Array[HudSlotCell] = []
## The least width and height of a place, canvas units (`MenuScale.tap_units`), and the type of the
## number in it.
var _finger := 0.0
var _number_px := HudStyle.SMALL


func _init() -> void:
	super()
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	set_process(false)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override(&"separation", int(GAP))
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_row)
	add_child(silhouettes)


func topics() -> Array[StringName]:
	return [HudState.SLOTS, HudState.HEALTH]


func refresh() -> void:
	# A keyboard's strip has no grenades' place: a change of the health (which carries the count)
	# is nothing to it, as it never was.
	if _built and not touch and not state.is_dirty(HudState.SLOTS):
		return
	_rebuild()


func _rebuild() -> void:
	_built = true
	var places := maxi(state.slot_count, state.slot_ids.size())
	_fit_cells(places)
	for i in places:
		var id: StringName = state.slot_ids[i] if i < state.slot_ids.size() else &""
		_cells[i].show_slot(i + 1, id, state.slot_held == i + 1, silhouettes.texture_of(id))
	_show_grenades()


## Puts the strip under a finger, or back for a keyboard or a pad: a place is `finger` canvas units
## wide at least (weapons a little more) and as high, and its number is typed at `number_px`.
func fit_touch(on: bool, finger: float, number_px := HudStyle.SMALL) -> void:
	if on == touch and is_equal_approx(finger, _finger) and number_px == _number_px:
		return
	touch = on
	_finger = finger if on else 0.0
	_number_px = number_px if on else HudStyle.SMALL
	set_process(on)
	if not on and grenade_cell != null:
		grenade_cell.queue_free()
		grenade_cell = null
	if is_node_ready() and state != null:
		_rebuild()
	else:
		_fit_cells(maxi(WeaponSlots.count(), _cells.size()))


## What a finger can press, in the screen's units: the action each place sends and its box. The
## weapons' places send their slot's key, the grenades' the throw. None while the strip is not
## under a finger or is not shown (the arrival's show, a pause).
func touch_zones() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not touch or not is_visible_in_tree():
		return found
	for i in _cells.size():
		found.append({&"action": WeaponSlots.ACTIONS[i], &"rect": _cells[i].get_global_rect()})
	if grenade_cell != null:
		found.append({&"action": GRENADE_ACTION, &"rect": grenade_cell.get_global_rect()})
	return found


func _process(_delta: float) -> void:
	# Redrawn only when the pin goes in or comes out (a redraw a frame is a cost, #834).
	if grenade_cell != null and state != null and _cooking() != grenade_cell.held:
		_show_grenades()


## Whether the pin is out: the throw's action is held (by the finger on the place, or by anything
## else that presses it).
func _cooking() -> bool:
	return Input.is_action_pressed(GRENADE_ACTION)


func _show_grenades() -> void:
	if grenade_cell != null:
		grenade_cell.show_grenades(state.grenades, _cooking())


## The width and height of a weapon's place under a finger, `fit_touch`.
func touch_cell_size() -> Vector2:
	return Vector2(maxf(roundf(_finger * TOUCH_WIDE), HEIGHT), ceilf(maxf(_finger, HEIGHT)))


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
	if touch:
		_fit_touch_cells()
		return
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	for cell in _cells:
		cell.custom_minimum_size = Vector2(cell_width(places), HEIGHT)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.set_number_size(HudStyle.SMALL)


## The places a finger presses: fingertip-sized, side by side, the grenades' after the weapons.
func _fit_touch_cells() -> void:
	if grenade_cell == null:
		grenade_cell = HudGrenadeCell.new()
		_row.add_child(grenade_cell)
	var weapon := touch_cell_size()
	var grenade := Vector2(ceilf(maxf(_finger, HEIGHT)), weapon.y)
	for cell in _cells:
		cell.custom_minimum_size = weapon
		cell.size_flags_horizontal = Control.SIZE_FILL
		cell.set_number_size(_number_px)
	grenade_cell.custom_minimum_size = grenade
	grenade_cell.size_flags_horizontal = Control.SIZE_FILL
	grenade_cell.set_number_size(_number_px)
	custom_minimum_size = Vector2(
		weapon.x * _cells.size() + grenade.x + GAP * float(_cells.size()), weapon.y
	)
