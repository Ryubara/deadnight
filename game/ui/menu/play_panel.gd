class_name PlayPanel
extends MenuPanel
## The Play tab: start a night (Play together, Quick join, Solo) and see today's challenges. The
## three starts only ask the main menu (`MenuContext.action`): Play together opens its screen,
## Quick join joins from the menu itself (`QuickJoinOverlay`) and Solo opens the Play screen, where
## the night's rules are set before the night starts.

const ROUTES := [
	[&"together", "Play together", "Open a room, bring friends"],
	[&"quick_join", "Quick join", "The next open night"],
	[&"solo", "Solo", "One night on your own"],
]
## How many of today's dailies show here (the Challenges tab has the rest).
const DAILIES_SHOWN := 3
const DAILIES_SHOWN_COMPACT := 2
## The sign's lettering size: it fits the column.
const SIGN_SIZE := 64

## The Deadnight sign over the three starts (a phone has no room for it).
var sign_node: NeonSign

var _buttons := {}
var _daily_box: VBoxContainer
var _refresh_note: Label


func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", 10)
	add_child(column)
	if not context.compact:
		sign_node = NeonSign.new()
		sign_node.name = "Sign"
		sign_node.font_size = SIGN_SIZE
		sign_node.tracking = 6.0
		var tokens := UITokens.active()
		sign_node.tube_a = tokens.hot
		sign_node.tube_b = tokens.accent
		column.add_child(sign_node)
	var index := 0
	for route: Array in ROUTES:
		var button := MenuItemButton.new()
		button.title = route[1]
		button.subtitle = "" if context.compact else route[2]
		button.primary = index == 0 and not context.compact
		button.admit = true
		button.set_width(width(context.compact))
		button.name = String(route[0])
		button.pressed.connect(context.request.bind(route[0]))
		column.add_child(button)
		_buttons[route[0]] = button
		index += 1
	var gap := Control.new()
	gap.custom_minimum_size.y = 12.0
	column.add_child(gap)
	var head := HBoxContainer.new()
	var name_label := MenuLook.label("Today's bill", MenuLook.SIZE_TITLE, MenuLook.INK, &"wide")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	_refresh_note = MenuLook.label(
		"", MenuLook.SIZE_CAPTION, MenuLook.AMBER, &"wide", HORIZONTAL_ALIGNMENT_RIGHT
	)
	_refresh_note.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_refresh_note)
	column.add_child(head)
	_daily_box = VBoxContainer.new()
	_daily_box.add_theme_constant_override(&"separation", 8)
	column.add_child(_daily_box)
	refresh()


func width(compact: bool) -> float:
	return 440.0 if compact else 600.0


## The start buttons, by route id.
func button(id: StringName) -> MenuItemButton:
	return _buttons[id]


func first_focus() -> Control:
	return _buttons[&"together"]


## The challenge rows on show.
func rows() -> Array[ChallengeRow]:
	var out: Array[ChallengeRow] = []
	for child in _daily_box.get_children():
		if child is ChallengeRow:
			out.append(child)
	return out


func refresh() -> void:
	if _daily_box == null:
		return
	for child in _daily_box.get_children():
		_daily_box.remove_child(child)
		child.queue_free()
	if context.board == null:
		_refresh_note.text = ""
		return
	_refresh_note.text = ("Resets in %s" % context.board.refresh_text()).to_upper()
	var shown := DAILIES_SHOWN_COMPACT if context.compact else DAILIES_SHOWN
	var dailies: Array = context.board.dailies()
	for index in mini(shown, dailies.size()):
		_daily_box.add_child(ChallengeRow.make(dailies[index], width(context.compact), false, true))
	_link_focus()


## Down and Up walk the three starts and then the dailies, in the order they are drawn; the first
## start's Up is left to the shell (it goes to the tab bar) and the last row's Down stops.
func _link_focus() -> void:
	var chain: Array[Control] = []
	for route: Array in ROUTES:
		chain.append(_buttons[route[0]])
	for row in rows():
		chain.append(row)
	for index in chain.size() - 1:
		chain[index].focus_neighbor_bottom = chain[index].get_path_to(chain[index + 1])
		chain[index + 1].focus_neighbor_top = chain[index + 1].get_path_to(chain[index])
	var last := chain[chain.size() - 1]
	last.focus_neighbor_bottom = last.get_path_to(last)
