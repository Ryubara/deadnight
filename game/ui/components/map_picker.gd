class_name MapPicker
extends GridContainer
## The map choice: one `MapCard` for every map of the `MapRegistry`, the chosen one marked. On the
## desktop the cards are one under another; on a phone held sideways (`set_compact`) they sit side
## by side so the row is one card high, which is all the 540 units of that canvas leave it. Arrows
## and the d-pad walk the cards (Up and Down between rows, Left and Right along one), Accept or a
## click or a tap chooses the card in focus, and a card that is not built yet (`MapCard.is_locked`)
## can be focused and read but chooses nothing: the picker says `blocked` and keeps the choice it
## had. So does a card the host's level does not open (`level`, `MapCard.is_level_locked`): it shows
## `???` and what unlocks it, and only the host's picker decides (a guest's picker is read-only and
## shows the map the lobby is on, whatever the guest's level: a guest below a map's level still
## plays a hosted night there).
##
## A row of `MatchSettingsPanel`, so Solo and a room host's lobby show the same picker. It holds
## only the id of the map; the panel puts it into the `MatchSettings` it hands out.

## The player chose a map that can be played. Not said by `set_selected`.
signal chosen(id: String)
## The player pressed a card that is not built yet.
signal blocked(info: MapInfo)

## The width of the column the picker sits in (a `UIRow`'s control column is 440 wide).
const WIDTH := 440.0
const GAP := 8

var cards: Array[MapCard] = []
var selected_id := MapRegistry.DEFAULT
## The level of the person choosing, which decides which cards are open; the local player's by
## default (`PlayerLevel`).
var level := PlayerLevel.local():
	set(value):
		level = value
		for card in cards:
			card.player_level = level
		_keep_choice_open()

var _editable := true


func _init() -> void:
	columns = 1
	add_theme_constant_override(&"h_separation", GAP)
	add_theme_constant_override(&"v_separation", GAP)
	for info in MapRegistry.all():
		var card := MapCard.new()
		card.info = info
		card.name = info.id
		card.set_width(WIDTH)
		card.player_level = level
		card.pressed.connect(_on_pressed.bind(card))
		add_child(card)
		cards.append(card)
	set_selected(selected_id)


func _ready() -> void:
	_link_focus()


## Marks `id` as the choice without saying `chosen`. An id that cannot be played marks the default
## (a map the level does not open is marked all the same, to show a lobby's map to a guest; a picker
## that can be edited drops back to the default when it takes the choice, `set_editable`).
func set_selected(id: String) -> void:
	selected_id = id if MapRegistry.is_playable(id) else MapRegistry.DEFAULT
	for card in cards:
		card.selected = card.info.id == selected_id


## The map that is marked.
func selected_info() -> MapInfo:
	return MapRegistry.of(selected_id)


## The card of the map `id`, or null.
func card_for(id: String) -> MapCard:
	for card in cards:
		if card.info.id == id:
			return card
	return null


## A guest sees the host's map and cannot change it.
func set_editable(on: bool) -> void:
	_editable = on
	_keep_choice_open()
	for card in cards:
		card.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		card.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


func is_editable() -> bool:
	return _editable


## A host cannot sit on a map their level does not open (a lobby handed down by a higher host, or
## the level changing): the choice falls back to the default map.
func _keep_choice_open() -> void:
	if _editable and not MapRegistry.is_open(selected_id, level):
		set_selected(MapRegistry.DEFAULT)


## The phone's form: cards without a picture, two to a row, a little over a tap target high.
func set_compact(on: bool) -> void:
	columns = mini(2, cards.size()) if on else 1
	var width := (WIDTH - GAP) / 2.0 if on else WIDTH
	for card in cards:
		card.compact = on
		card.set_width(width)
	if is_inside_tree():
		_link_focus()


## The card the keyboard enters the picker on: the chosen map's.
func entry_control() -> Control:
	var card := card_for(selected_id)
	return card if card != null else cards[0]


## The first card, to link the focus from what is above the picker.
func first_card() -> Control:
	return cards[0]


## The cards of the first row: what Up leaves the picker from.
func top_row() -> Array[Control]:
	var out: Array[Control] = []
	for index in mini(columns, cards.size()):
		out.append(cards[index])
	return out


## The last card, to link the focus to what follows.
func last_card() -> Control:
	return cards[cards.size() - 1]


func _on_pressed(card: MapCard) -> void:
	if not _editable:
		return
	if card.blocks():
		blocked.emit(card.info)
		return
	if card.info.id == selected_id:
		return
	set_selected(card.info.id)
	chosen.emit(selected_id)


## Up and Down walk the rows and Left and Right a row; a card with nothing beside it stays put
## along that axis. Past the first row and the last the screen's own chain takes over.
func _link_focus() -> void:
	for index in cards.size():
		var card := cards[index]
		var column := index % columns
		card.focus_neighbor_left = _path(card, index - 1 if column > 0 else index)
		card.focus_neighbor_right = _path(
			card, index + 1 if column < columns - 1 and index + 1 < cards.size() else index
		)
		card.focus_neighbor_top = _path(card, index - columns) if index >= columns else NodePath()
		card.focus_neighbor_bottom = (
			_path(card, index + columns) if index + columns < cards.size() else NodePath()
		)


func _path(from: Control, to_index: int) -> NodePath:
	return from.get_path_to(cards[to_index])
