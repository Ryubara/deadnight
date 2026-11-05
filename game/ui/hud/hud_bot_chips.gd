class_name HudBotChips
extends VBoxContainer
## The room's bots as a strip of chips under the people's boxes, when the night holds more than
## eight bodies (#1179): the cap of eight is people, the bots come on top, and fifteen boxes would
## stand 598 units high, taller than the room the column has on a 864 high canvas. A chip is the
## bot's name in the colour of its seat's armband, outlined in it, on the HUD's dark (a person's
## box is solid colour, so the two never read alike); a bot that is down has a dim outline and its
## name in the danger colour. Four to a row. The points are on the scoreboard, as for every box.
## At eight bodies or fewer a bot has a box like anyone.

const COLUMNS := 4
const CHIP_HEIGHT := 25.0
const OUTLINE := 2

## The chips as {"id", "text", "downed", "colour"}, in the order drawn, for tests and tools.
var shown: Array[Dictionary] = []

var _tokens := UITokens.active()
var _grid := GridContainer.new()
var _chips: Dictionary[int, PanelContainer] = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.columns = COLUMNS
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override(&"h_separation", HudStyle.XS)
	_grid.add_theme_constant_override(&"v_separation", HudStyle.XS)
	add_child(_grid)
	visible = false


## The height of the strip for `count` bots.
static func height_for(count: int) -> float:
	if count <= 0:
		return 0.0
	var rows := ceili(float(count) / COLUMNS)
	return float(rows) * CHIP_HEIGHT + float(rows - 1) * float(HudStyle.XS)


## Draws the bots `ids` of `members` (`{player_id: HudState.team entry}`), in that order.
func show_bots(ids: Array[int], members: Dictionary) -> void:
	for id in _chips.keys():
		if not ids.has(id):
			var gone: Control = _chips[id]
			_grid.remove_child(gone)
			gone.queue_free()
			_chips.erase(id)
	shown.clear()
	var width := (HudStyle.COLUMN - float(COLUMNS - 1) * float(HudStyle.XS)) / COLUMNS
	for i in ids.size():
		var id := ids[i]
		var member: Dictionary = members[id]
		if not _chips.has(id):
			var made := PanelContainer.new()
			made.mouse_filter = Control.MOUSE_FILTER_IGNORE
			made.custom_minimum_size = Vector2(width, CHIP_HEIGHT)
			var name_label := HudStyle.clip(HudStyle.label("", HudStyle.MIN_TEXT, Color.WHITE))
			name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			made.add_child(name_label)
			_chips[id] = made
			_grid.add_child(made)
		_grid.move_child(_chips[id], i)
		var downed := bool(member["downed"])
		var seat_colour := LookCatalog.armband_colour(int(member.get("seat", 0)))
		var colour := (
			seat_colour.lerp(_tokens.bg, 1.0 - HudPlayerBox.DOWN_KEEP) if downed else seat_colour
		)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(_tokens.bg, 0.85)
		box.set_border_width_all(OUTLINE)
		box.border_color = colour
		box.content_margin_left = 4.0
		box.content_margin_right = 4.0
		box.content_margin_top = 0.0
		box.content_margin_bottom = 0.0
		(_chips[id] as PanelContainer).add_theme_stylebox_override(&"panel", box)
		var label := (_chips[id] as PanelContainer).get_child(0) as Label
		var text := str(member.get("name", "BOT")).to_upper()
		label.add_theme_color_override(&"font_color", _tokens.danger if downed else colour)
		HudStyle.set_fitted(label, text, HudStyle.MIN_TEXT, width - 8.0 - 2.0 * float(OUTLINE))
		shown.append({"id": id, "text": text, "downed": downed, "colour": colour})
	visible = not ids.is_empty()
	update_minimum_size()


## The chip of a bot, for tests and tools; null when it has none.
func chip_of(player_id: int) -> PanelContainer:
	return _chips.get(player_id)
