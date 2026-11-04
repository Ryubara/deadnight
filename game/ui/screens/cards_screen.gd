class_name CardsScreen
extends UIScreen
## The calling cards and emblems of the player's plate: what they wear (the card behind their box
## and the emblem after their name, for every client), what else they own, and what is still to
## earn with how to earn it (the level, or the challenge itself). A tile pressed puts the piece on;
## a piece not earned shakes and says what it takes. What is worn is the profile's `equipped`
## (`ProfileStore.equip`) and goes to the account (`PlateEquip`).
##
## `params` (a test or a capture sets them): `path` the profile file, `account` a Callable
## answering whether there is an account (`TogetherApi.signed_in`).

## The card on show at the top, and a tile's art, in units of the 440 by 120 sheet.
const PREVIEW_WIDTH := 330.0
const TILE_CARD_WIDTH := 240.0
const TILE_EMBLEM := 64.0
## At or below this width the screen is a phone's: one column of cards, three of emblems.
const PHONE_WIDTH := 960.0
## Below this height the screen is a short one: a phone held sideways.
const SHORT_HEIGHT := 640.0

var store: ProfileStore
var back_button: UIButton

var _catalog := PlateCatalog.shipped()
var _preview_card: CardArt
var _preview_emblem: EmblemArt
var _note: Label
var _tiles: Array[PlateTile] = []
var _card_grid: GridContainer
var _emblem_grid: GridContainer
var _done: Array[StringName] = []


func _ready() -> void:
	super._ready()
	var path: String = params.get("path", ProfileSave.DEFAULT_PATH)
	var account: Callable = params.get("account", TogetherApi.signed_in)
	store = ProfileStore.open(path, account)
	_done = store.profile.done.duplicate()
	var phone := get_viewport_rect().size.x <= PHONE_WIDTH
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, _tokens.space_lg)
	add_child(margin)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(panel)
	var card := VBoxContainer.new()
	card.add_theme_constant_override(&"separation", _tokens.space_sm)
	panel.add_child(card)
	# A short screen (a phone held sideways is 540 units) drops the overline and shows a smaller
	# preview, so the list keeps its room.
	var short := get_viewport_rect().size.y < SHORT_HEIGHT
	if not short:
		card.add_child(_label("THE PLATE", UILabel.Style.OVERLINE))
	card.add_child(_label("Your plate", UILabel.Style.TITLE))
	card.add_child(_preview_row(0.6 if short else 1.0))
	_note = _label("", UILabel.Style.CAPTION)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_note)
	var scroll := UIFitScroll.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.margin = float(_tokens.space_lg) * 2.0
	card.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", _tokens.space_sm)
	scroll.add_child(list)
	list.add_child(_label("CALLING CARDS", UILabel.Style.OVERLINE))
	_card_grid = _grid(1 if phone else 2)
	list.add_child(_card_grid)
	list.add_child(_label("EMBLEMS", UILabel.Style.OVERLINE))
	_emblem_grid = _grid(3 if phone else 4)
	list.add_child(_emblem_grid)
	back_button = UIButton.new()
	back_button.name = "Back"
	back_button.text = "Back"
	back_button.variant = UIButton.Variant.GHOST
	back_button.pressed.connect(UIRouter.pop)
	card.add_child(back_button)
	panel.custom_minimum_size.x = minf(
		get_viewport_rect().size.x - 4.0 * _tokens.space_lg,
		(TILE_CARD_WIDTH * 2.0 + 140.0) if not phone else TILE_CARD_WIDTH + 200.0
	)
	_rebuild()
	initial_focus = get_path_to(back_button)


## Every tile (cards then emblems), for tests.
func tiles() -> Array[PlateTile]:
	return _tiles


func tile(kind: StringName, id: StringName) -> PlateTile:
	for each in _tiles:
		if each.kind == kind and each.piece_id == id:
			return each
	return null


## The words under the preview.
func note_text() -> String:
	return _note.text


## The card and emblem on show in the preview, for tests.
func previewed() -> Dictionary:
	return {"card": _preview_card.card_id, "emblem": _preview_emblem.emblem_id}


## Wears `id` of `kind` (`&""` for none) if the player owns it; a piece not earned shakes the tile
## and says what it takes. True when something was put on.
func wear(kind: StringName, id: StringName) -> bool:
	if id != &"" and not _owns(kind, id):
		var locked := tile(kind, id)
		if locked != null:
			UIMotion.shake(locked)
		_say("%s: %s." % [_catalog.title(kind, id), _catalog.how_to_get(kind, id)])
		return false
	if not PlateEquip.choose(get_tree().root, store, kind, id):
		if not store.has_account():
			_say("Sign in to keep a calling card: Play together does it.")
		return false
	_rebuild()
	_say("%s on." % (_catalog.title(kind, id) if id != &"" else "Nothing"))
	return true


func _owns(kind: StringName, id: StringName) -> bool:
	return _catalog.owns(kind, id, store.profile.level(), _done)


func _preview_row(share := 1.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", _tokens.space_md)
	_preview_card = CardArt.new()
	_preview_card.titled = true
	_preview_card.custom_minimum_size = (
		Vector2(PREVIEW_WIDTH, PREVIEW_WIDTH * 120.0 / 440.0) * share
	)
	row.add_child(_preview_card)
	_preview_emblem = EmblemArt.new()
	_preview_emblem.custom_minimum_size = Vector2.ONE * TILE_EMBLEM * share
	_preview_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_preview_emblem)
	return row


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override(&"h_separation", _tokens.space_sm)
	grid.add_theme_constant_override(&"v_separation", _tokens.space_sm)
	return grid


## Makes every tile again from what the profile holds now.
func _rebuild() -> void:
	for grid: GridContainer in [_card_grid, _emblem_grid]:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	_tiles.clear()
	var level := store.profile.level()
	var worn := _catalog.worn(store.profile.equipped, level, _done)
	_preview_card.card_id = worn[PlateCatalog.CARD]
	_preview_emblem.emblem_id = worn[PlateCatalog.EMBLEM]
	var card_size := Vector2(TILE_CARD_WIDTH, TILE_CARD_WIDTH * 120.0 / 440.0)
	for kind in PlateCatalog.KINDS:
		var grid := _card_grid if kind == PlateCatalog.CARD else _emblem_grid
		var size := card_size if kind == PlateCatalog.CARD else Vector2.ONE * TILE_EMBLEM
		# What the player can put on comes first, the rest follow in the catalogue's order.
		var ids: Array[StringName] = [&""]
		var earned := _catalog.owned(kind, level, _done)
		ids.append_array(earned)
		for id in _catalog.ids(kind):
			if not earned.has(id):
				ids.append(id)
		for id in ids:
			var owned := id == &"" or _owns(kind, id)
			var tile := PlateTile.make(
				kind,
				id,
				size,
				owned,
				worn[kind] == id,
				_catalog.how_to_get(kind, id) if id != &"" else ""
			)
			tile.pressed.connect(wear.bind(kind, id))
			grid.add_child(tile)
			_tiles.append(tile)
	if _note.text == "":
		_say(_summary(level))


## "3 of 23 calling cards and 5 of 33 emblems are yours."
func _summary(level: int) -> String:
	var cards := _catalog.owned(PlateCatalog.CARD, level, _done).size()
	var emblems := _catalog.owned(PlateCatalog.EMBLEM, level, _done).size()
	var line := (
		"%d of %d calling cards and %d of %d emblems are yours."
		% [
			cards,
			_catalog.ids(PlateCatalog.CARD).size(),
			emblems,
			_catalog.ids(PlateCatalog.EMBLEM).size(),
		]
	)
	if not store.has_account():
		line += " Sign in to earn and keep them."
	return line


func _say(text: String) -> void:
	_note.text = text


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
