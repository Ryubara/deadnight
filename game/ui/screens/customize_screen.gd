# gdlint: disable=max-public-methods
class_name CustomizeScreen
extends UIScreen
## The wardrobe: a lit turntable with the character on it, a strip of tabs (Costumes, Body, Hair,
## Hats, Tops, Legs, Shoes, Eyes, Neck, Colours) and, under it, the choices of the tab in a grid
## (#1065).
##
## The Costumes tab (#1066) holds the twelve presets, each a whole look: dark with `???` and how to
## get it until the player owns every piece, lit after, and a press sets the look (its pieces, its
## face and hair, and its colours). The player may then change any part they own. The Colours tab
## starts with a "Default" option that gives the costume on the character its own three colours
## back; the player's own colours come from the palette they have unlocked, and the colours of a
## costume they own count as unlocked in the channel the costume puts them in.
##
## An item the player has is lit; one they have not is the dark silhouette of its icon, its name
## `???`, and what it takes to get it on the detail line under the grid (the pointer on it says it,
## and so does the focus, for a pad and a phone). A locked item can be looked at, never worn: there
## is no fitting room. Face, hair, skin, body and mouth carry no lock marks; weapons and tonics are
## never locked and are not here.
##
## The screen edits a working copy of the look; Save writes it (`LookStore`) and Back leaves
## without saving. Every change shows on the turntable at once. Nothing here changes how a night
## plays.
##
## With the param `embedded` it is only the tabs, the grid and the footer, without its own title,
## turntable, Back or Save: the main menu's Loadout tab hosts it, shows the look on its own stage
## and keeps the working look until the player leaves the tab (`commit`). `unlocks` (a
## `LookUnlocks`) is what the player has; without it the profile file's level is read. `compact`
## is a phone's layout.
##
## Route to it with `UIRouter.push("res://ui/screens/customize_screen.tscn")`. Tests and captures
## drive it through `wear_costume`, `use_default_colours`, `randomize`, `choose`, `choose_body`,
## `save`, `show_tab` and the cells.

## Emitted when the working look changes, so a stage somewhere else can show it.
signal look_changed(look: CharacterLook)
## Emitted when the host's rows should go one over the other, or side by side again (a narrow tab).
signal rows_stacked(stacked: bool)

const PANEL_WIDTH := 1500
const PICKER_WIDTH := 900
## Height of the scrolling grid on its own screen; embedded it takes what its tab leaves.
const SCROLL_HEIGHT := 520
## The room round the tabs, the grid and the detail line inside the panel.
const MARGIN := 14
const MARGIN_COMPACT := 8
## The widths the host's rows (the Loadout tab's weapon row) share: a title and a control.
const EMBEDDED_TITLE_WIDTH := 150.0
const EMBEDDED_CONTROL_WIDTH := 380.0
## The keys of the choices: a prefix and the slot (or colour channel) name.
const PART_PREFIX := "part:"
const COLOUR_PREFIX := "colour:"
const CUSTOM_LABEL := "Custom"
## What the detail line says while nothing is pointed at.
const REST_HINT := "Point at an item to read it; press to wear it."
## The cells of the costumes, and of the Default option, in `_cells`.
const COSTUME_KEY := "costume:costumes"
const DEFAULT_KEY := "costume:default"
const DEFAULT_TITLE := "Default"
const NO_COSTUME_NOTE := "wear a costume to give it its own colours back"
## The tabs, in order: a key, the words on the tab, and the sections of the grid: a part slot
## (`part`), a colour channel (`colour`), the costumes (`costumes`) or the Default colours option
## (`default`).
const TABS: Array[Dictionary] = [
	{"key": &"costumes", "title": "Costumes", "sections": [{"costumes": true}]},
	{
		"key": &"body",
		"title": "Body",
		"sections": [{"part": &"body"}, {"part": &"head"}, {"part": &"mouth"}, {"colour": &"skin"}],
	},
	{"key": &"hair", "title": "Hair", "sections": [{"part": &"hair"}, {"colour": &"hair"}]},
	{"key": &"headwear", "title": "Hats", "sections": [{"part": &"headwear"}]},
	{"key": &"torso", "title": "Tops", "sections": [{"part": &"torso"}]},
	{"key": &"legs", "title": "Legs", "sections": [{"part": &"legs"}]},
	{"key": &"feet", "title": "Shoes", "sections": [{"part": &"feet"}]},
	{"key": &"eyewear", "title": "Eyes", "sections": [{"part": &"eyewear"}]},
	{"key": &"neck", "title": "Neck", "sections": [{"part": &"neck"}, {"part": &"arm"}]},
	{
		"key": &"colours",
		"title": "Colours",
		"sections":
		[
			{"default": true},
			{"colour": &"primary"},
			{"colour": &"secondary"},
			{"colour": &"accent"}
		],
	},
]

## What this player has unlocked. Replace before the screen is shown to try other gates.
var unlocks := LookUnlocks.new()
## The look being edited.
var look: CharacterLook
## The look on disk.
var saved: CharacterLook
## The widths the host's rows share (title, control): the Loadout tab's weapon row uses them.
var row_widths := Vector2(EMBEDDED_TITLE_WIDTH, EMBEDDED_CONTROL_WIDTH)

var _rng := RandomNumberGenerator.new()
## The grid's cells by key ("part:<slot>", "colour:<channel>"), in the order the grid shows them.
var _cells := {}
var _tabs := {}
var _pages := {}
var _tab := &"body"
var _preview: LookPreview
var _hint: UILabel
var _status: UILabel
var _armband_note: UILabel
var _save_button: UIButton
var _random_button: UIButton
var _building := false
var _embedded := false
var _compact := false
var _rows: Control
var _pickers: Control
var _picker_scroll: ScrollContainer
var _link_pending := false


func _ready() -> void:
	super._ready()
	if params.has("seed"):
		_rng.seed = int(params["seed"])
	else:
		_rng.randomize()
	unlocks = params["unlocks"] if params.has("unlocks") else LookUnlocks.saved()
	_embedded = params.get("embedded", false)
	_compact = params.get("compact", false)
	saved = LookStore.load_look(unlocks)
	look = saved.duplicate_look()
	_build()
	_sync_all()
	show_tab(_tab)
	initial_focus = (_tabs[_tab] as Control).get_path()


## Puts the look of preset `index` on the character, in what the player owns (a script's way in;
## the player's is `wear_costume`).
func apply_preset(index: int) -> void:
	look = CharacterLook.from_preset(index).without_locked(unlocks)
	_sync_all()


## Wears costume `index` (a preset) as a press on its cell does: its pieces, face and hair, and its
## default colours. A costume the player does not own whole is refused (false).
func wear_costume(index: int) -> bool:
	if index < 0 or index >= Costumes.count() or not unlocks.owns_costume(index):
		return false
	look = Costumes.look(index).without_locked(unlocks)
	_sync_all()
	return true


## Gives the costume on the character its own three colours back (the Default option), or does
## nothing and returns false when the look wears no costume.
func use_default_colours() -> bool:
	var worn := Costumes.of_look(look)
	if worn < 0:
		return false
	Costumes.give_default_colours(look, worn)
	for channel in Costumes.COLOUR_CHANNELS:
		_sync_cells(COLOUR_PREFIX + channel)
	_after_pick(COLOUR_PREFIX + "primary")
	return true


## Rolls a look from the options this player may wear, for the character they chose.
func randomize() -> void:
	look = CharacterLook.randomized(_rng, unlocks, look.body())
	_sync_all()


## Makes the working look `body`'s (`CharacterLook.set_body`: a cut of the other character's
## becomes this one's own), as the Body tab's Character choice does.
func choose_body(body: StringName) -> void:
	look.set_body(body)
	_sync_all()


## Picks the entry `index` (its place in the catalogue) of `key` ("part:<slot>" or
## "colour:<channel>"), as a press on its cell would: a locked one is refused.
func choose(key: String, index: int) -> void:
	var picked := cell(key, index)
	if picked != null:
		picked.pressed.emit()


## Takes the unlocks of a level that changed under the screen, and locks or opens every cell by it
## (the catalogue's order does not depend on them, so each grid's specs line up with its cells).
func set_unlocks(value: LookUnlocks) -> void:
	unlocks = value
	for key: String in _cells:
		var specs := _specs(key)
		var cells: Array[WardrobeCell] = _cells[key]
		for i in cells.size():
			var spec: Dictionary = specs[i]
			assert(cells[i].slot == spec["slot"] and cells[i].id == spec["id"])
			cells[i].soon = spec["soon"]
			cells[i].instructions = spec["instructions"]
			cells[i].locked = spec["locked"]


## Writes the working look to the settings file.
func save() -> void:
	look = look.without_locked(unlocks)
	LookStore.save_look(look)
	saved = look.duplicate_look()
	_refresh_status()


## Makes the working look the saved one in memory and leaves the file write to the caller (the
## Loadout panel writes every choice it holds at once).
func commit() -> void:
	look = look.without_locked(unlocks)
	LookStore.set_look(look)
	saved = look.duplicate_look()
	_refresh_status()


## Shows the tab `key` (a key of `TABS`, a String or a StringName).
func show_tab(key: Variant) -> void:
	var wanted := StringName(key)
	if not _pages.has(wanted):
		return
	var changed := wanted != _tab
	_tab = wanted
	for tab_key: StringName in _pages:
		(_pages[tab_key] as Control).visible = tab_key == wanted
		(_tabs[tab_key] as WardrobeTab).active = tab_key == wanted
	if _picker_scroll != null:
		_picker_scroll.scroll_vertical = 0
	if _hint != null and changed:
		_hint.text = REST_HINT
	_relink_soon()


## The key of the tab on show.
func current_tab() -> StringName:
	return _tab


## The keys of the tabs, in order.
func tab_keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for tab: Dictionary in TABS:
		out.append(tab["key"])
	return out


## The button of the tab `key`.
func tab_button(key: StringName) -> WardrobeTab:
	return _tabs[key]


## The cells of `key` ("part:<slot>", "colour:<channel>") in the order the grid shows them: the
## wearables a level opens run from the starting ones up the ladder.
func cells(key: String) -> Array[WardrobeCell]:
	var out: Array[WardrobeCell] = []
	for found: WardrobeCell in _cells.get(key, []):
		out.append(found)
	return out


## The cell of the catalogue entry `index` of `key`, or null.
func cell(key: String, index: int) -> WardrobeCell:
	for found in cells(key):
		if found.index == index:
			return found
	return null


## The cell of the wearable `id` of `slot`, including one the art does not have yet.
func cell_of(slot: StringName, id: StringName) -> WardrobeCell:
	for found in cells(PART_PREFIX + slot):
		if found.id == id:
			return found
	return null


## The first locked cell on the tab on show, or null.
func first_locked_cell() -> WardrobeCell:
	for found in _cells_on(_tab):
		if found.locked:
			return found
	return null


## What the detail line under the grid says now.
func detail_text() -> String:
	return _hint.text


## The cell of costume `index`.
func costume_cell(index: int) -> WardrobeCell:
	for found in cells(COSTUME_KEY):
		if found.index == index:
			return found
	return null


## The Default option's cell.
func default_cell() -> WardrobeCell:
	return cells(DEFAULT_KEY)[0]


func preview() -> LookPreview:
	return _preview


func is_dirty() -> bool:
	return not look.equals(saved)


func _build() -> void:
	_building = true
	if _embedded:
		_build_embedded()
		_building = false
		return
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, _tokens.space_xl)
	add_child(margin)
	var centre := CenterContainer.new()
	margin.add_child(centre)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = PANEL_WIDTH
	column.add_theme_constant_override(&"separation", _tokens.space_md)
	centre.add_child(column)
	column.add_child(_label("WARDROBE", UILabel.Style.OVERLINE))
	column.add_child(_label("Your character", UILabel.Style.TITLE))
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", _tokens.space_xl)
	column.add_child(body)
	body.add_child(_build_stage())
	body.add_child(_build_pickers())
	column.add_child(_build_footer())
	_building = false


func _build_embedded() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", _tokens.space_md)
	add_child(column)
	var pickers := _build_pickers()
	pickers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pickers)
	column.add_child(_build_footer(false))


## A tab's way down is the first cell of its page, and the way up from the cells of the page's first
## row is the tab on show (not whichever tab the engine finds above: a tab is only shown when it is
## pressed). Everywhere else the engine's walk to the nearest control in the direction of the key
## is the right one for a grid. The rows are known once the grid is laid out, so this runs again
## when a grid is sorted.
func _link_focus() -> void:
	_link_pending = false
	var items := _cells_on(_tab)
	var tab := _tabs[_tab] as Control
	for tab_key: StringName in _tabs:
		var other := _tabs[tab_key] as Control
		other.focus_neighbor_bottom = (
			other.get_path_to(items[0]) if not items.is_empty() else NodePath()
		)
	var top := INF
	for item in items:
		top = minf(top, item.global_position.y)
	for item in items:
		var first_row := absf(item.global_position.y - top) < 1.0
		item.focus_neighbor_top = item.get_path_to(tab) if first_row else NodePath()


## Asks for `_link_focus` once the layout has settled.
func _relink_soon() -> void:
	if not _link_pending:
		_link_pending = true
		_link_focus.call_deferred()


func _build_stage() -> Control:
	var stage := VBoxContainer.new()
	stage.add_theme_constant_override(&"separation", _tokens.space_sm)
	_preview = LookPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(_preview)
	_armband_note = _label("", UILabel.Style.CAPTION)
	_armband_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(_armband_note)
	var turn := _label("Drag or use the right stick to turn", UILabel.Style.CAPTION)
	turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(turn)
	return stage


func _build_pickers() -> Control:
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.RAISED
	panel.custom_minimum_size.x = 0.0 if _embedded else PICKER_WIDTH
	var inner := MarginContainer.new()
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		inner.add_theme_constant_override(side, MARGIN_COMPACT if _compact else MARGIN)
	panel.add_child(inner)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override(&"separation", _tokens.space_sm)
	inner.add_child(holder)
	_pickers = panel
	holder.add_child(_build_tab_strip())
	# The pages of the tabs sit one over the other in a scrolling area that follows the focus; the
	# host's own rows (the Loadout tab's weapon row on a phone) go above them.
	var scroll := ScrollContainer.new()
	UIScroll.use_slip(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = 0.0 if _embedded else SCROLL_HEIGHT
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker_scroll = scroll
	holder.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", _tokens.space_md)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	_rows = rows
	for tab: Dictionary in TABS:
		var page := _build_page(tab)
		rows.add_child(page)
		_pages[tab["key"]] = page
	if _embedded:
		resized.connect(_restack)
	_hint = _label(REST_HINT, UILabel.Style.CAPTION if _compact else UILabel.Style.BODY)
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	holder.add_child(_hint)
	return panel


func _build_tab_strip() -> Control:
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override(&"h_separation", 3 if _compact else 6)
	strip.add_theme_constant_override(&"v_separation", 4)
	for tab: Dictionary in TABS:
		var button := WardrobeTab.new(tab["key"], tab["title"], _compact)
		button.pressed.connect(show_tab.bind(tab["key"]))
		strip.add_child(button)
		_tabs[tab["key"]] = button
	return strip


## One tab's page: its sections, each a title (when the tab has more than one) over a wrapping grid.
func _build_page(tab: Dictionary) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", _tokens.space_md)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sections: Array = tab["sections"]
	for section: Dictionary in sections:
		var box := VBoxContainer.new()
		box.add_theme_constant_override(&"separation", _tokens.space_sm)
		page.add_child(box)
		var key := ""
		var heading := ""
		if section.has("costumes"):
			key = COSTUME_KEY
			heading = "Costumes"
		elif section.has("default"):
			key = DEFAULT_KEY
			heading = "Costume colours"
		elif section.has("part"):
			key = PART_PREFIX + section["part"]
			heading = LookCatalog.PART_TITLES[section["part"]]
		else:
			key = COLOUR_PREFIX + section["colour"]
			heading = LookCatalog.COLOUR_TITLES[section["colour"]]
		if sections.size() > 1:
			box.add_child(_label(heading, UILabel.Style.CAPTION))
		box.add_child(_build_grid(key))
	return page


func _build_grid(key: String) -> Control:
	var grid := HFlowContainer.new()
	grid.sort_children.connect(_relink_soon)
	grid.add_theme_constant_override(&"h_separation", _tokens.space_sm)
	grid.add_theme_constant_override(&"v_separation", _tokens.space_sm)
	var made: Array[WardrobeCell] = []
	for spec: Dictionary in _specs(key):
		var item := WardrobeCell.new()
		item.compact = _compact
		item.kind = spec["kind"]
		item.slot = spec["slot"]
		item.id = spec["id"]
		item.index = spec["index"]
		item.colour = spec.get("colour", Color.WHITE)
		item.title = spec["title"]
		item.locked = spec["locked"]
		item.soon = spec["soon"]
		item.instructions = spec["instructions"]
		item.action = spec.get("action", item.action)
		item.swatches = spec.get("swatches", {})
		item.chosen.connect(_on_cell_chosen.bind(item, key))
		item.refused.connect(_on_cell_refused.bind(item))
		item.shown.connect(_on_cell_shown.bind(item))
		grid.add_child(item)
		made.append(item)
	_cells[key] = made
	return grid


## What the grid of `key` shows: every catalogue entry, then the wearables with no model yet, the
## ones a lower level opens first (a stable order: the catalogue's within a level).
func _specs(key: String) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	if key == COSTUME_KEY:
		return _costume_specs()
	if key == DEFAULT_KEY:
		return [_default_spec()]
	if key.begins_with(PART_PREFIX):
		var slot := StringName(key.trim_prefix(PART_PREFIX))
		var list := LookCatalog.options(slot)
		for i in list.size():
			var option: Dictionary = list[i]
			var kind := WardrobeCell.Kind.TEXT
			if option["id"] == &"none":
				kind = WardrobeCell.Kind.NONE
			elif ItemIcons.has(slot, option["id"]):
				kind = WardrobeCell.Kind.PART
			specs.append(_spec(kind, slot, option, i, LookCatalog.label(slot, i, LookCatalog.MALE)))
		for option: Dictionary in LookCatalog.pending(slot):
			specs.append(_spec(WardrobeCell.Kind.PART, slot, option, -1, option["label"]))
	else:
		var channel := StringName(key.trim_prefix(COLOUR_PREFIX))
		var entries := LookCatalog.palette(channel)
		for i in entries.size():
			var entry: Dictionary = entries[i]
			var made := _spec(WardrobeCell.Kind.COLOUR, channel, entry, i, entry["label"])
			made["colour"] = entry["colour"]
			specs.append(made)
	var decorated: Array = []
	for i in specs.size():
		decorated.append([LookUnlocks.level_of(specs[i]["gate"]), i])
	decorated.sort()
	var ordered: Array[Dictionary] = []
	for pair: Array in decorated:
		ordered.append(specs[pair[1]])
	return ordered


## The costumes with the ones a lower level opens first, the starting ones leading (a stable
## order within a level).
func _costume_specs() -> Array[Dictionary]:
	var decorated: Array = []
	for index in Costumes.count():
		decorated.append([Costumes.level_needed(index), index])
	decorated.sort()
	var specs: Array[Dictionary] = []
	for pair: Array in decorated:
		var index: int = pair[1]
		var open := unlocks.owns_costume(index)
		(
			specs
			. append(
				{
					"kind": WardrobeCell.Kind.COSTUME,
					"slot": &"costume",
					"id": Costumes.id(index),
					"index": index,
					"title": Costumes.title(index),
					"gate": {},
					"locked": not open,
					"soon": false,
					"instructions": "" if open else unlocks.costume_instructions(index),
					"action": "press to wear it in its own colours",
					"swatches": _costume_swatches(Costumes.look(index)),
				}
			)
		)
	return specs


func _default_spec() -> Dictionary:
	return {
		"kind": WardrobeCell.Kind.DEFAULT,
		"slot": &"costume",
		"id": &"default",
		"index": 0,
		"title": DEFAULT_TITLE,
		"gate": {},
		"locked": false,
		"soon": false,
		"instructions": "",
		"action": "press to give the costume its own colours back",
		"swatches": {},
	}


## The colours a costume's figure is drawn in, for a look.
func _costume_swatches(of: CharacterLook) -> Dictionary:
	return {
		"skin": of.colour(&"skin"),
		"hair": of.colour(&"hair"),
		"main": of.colour(&"primary"),
		"second": of.colour(&"secondary"),
		"trim": of.colour(&"accent"),
	}


func _spec(
	kind: WardrobeCell.Kind, slot: StringName, option: Dictionary, index: int, title: String
) -> Dictionary:
	var gate: Dictionary = option["gate"]
	var open := unlocks.is_unlocked(slot, option["id"], gate)
	return {
		"kind": kind,
		"slot": slot,
		"id": option["id"],
		"index": index,
		"title": title,
		"gate": gate,
		"locked": not open,
		"soon": open and index < 0,
		"instructions": "" if open else unlocks.instructions(gate),
	}


func _cells_on(tab_key: StringName) -> Array[WardrobeCell]:
	var out: Array[WardrobeCell] = []
	var page := _pages.get(tab_key) as Node
	if page == null:
		return out
	for found: Node in page.find_children("*", "Button", true, false):
		if found is WardrobeCell:
			out.append(found)
	return out


## The host's own row (the Loadout tab's weapon row on a phone) at the top of the Body tab, above
## its sections: a phone's 372 units are the grid's, so the row is on the first tab only.
func prepend_row(row: Control) -> void:
	var page := _pages[&"body"] as Control
	page.add_child(row)
	page.move_child(row, 0)


## Scrolls the grid so that `item` is whole in view (a pad or a key does it by focusing).
func reveal(item: Control) -> void:
	_picker_scroll.ensure_control_visible(item)


## The host's rows go one over the other (title above the control) when the tab is too narrow to
## hold them side by side: a phone's narrowest canvas gives the pickers 672 units.
func _restack() -> void:
	if _rows == null or size.x <= 0.0:
		return
	var around := (
		_pickers.get_theme_stylebox(&"panel").get_minimum_size().x
		+ (MARGIN_COMPACT if _compact else MARGIN) * 2.0
		+ UIScroll.side_room(_picker_scroll)
	)
	var gap := float(_tokens.space_lg)
	var stacked := size.x < row_widths.x + gap + row_widths.y + around
	rows_stacked.emit(stacked)


func _build_footer(with_back := true) -> HBoxContainer:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", _tokens.space_md)
	_random_button = UIButton.new()
	_random_button.text = "Randomize"
	_random_button.variant = UIButton.Variant.SECONDARY
	_random_button.pressed.connect(randomize)
	footer.add_child(_random_button)
	_status = _label("", UILabel.Style.CAPTION)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(_status)
	if with_back:
		var back := UIButton.new()
		back.text = "Back"
		back.variant = UIButton.Variant.GHOST
		back.pressed.connect(func() -> void: UIRouter.pop())
		footer.add_child(back)
	if not _embedded:
		_save_button = UIButton.new()
		_save_button.text = "Save"
		_save_button.pressed.connect(save)
		footer.add_child(_save_button)
	return footer


## Puts every cell, the preview and the captions in step with `look`.
func _sync_all() -> void:
	_building = true
	for key: String in _cells:
		_sync_cells(key)
	_building = false
	_refresh_preview()
	_refresh_status()
	if _hint != null:
		_hint.text = REST_HINT


## What a cell wears and is called, for the look and the character it has now.
func _sync_cells(key: String) -> void:
	if key == COSTUME_KEY or key == DEFAULT_KEY:
		_sync_costume_cells()
		return
	var is_part := key.begins_with(PART_PREFIX)
	var name_of := StringName(key.trim_prefix(PART_PREFIX if is_part else COLOUR_PREFIX))
	for found: WardrobeCell in _cells[key]:
		if is_part:
			found.worn = found.index >= 0 and look.parts[name_of] == found.id
			if found.index >= 0:
				found.title = LookCatalog.label(name_of, found.index, look.body())
		else:
			found.worn = found.index == int(look.colours[name_of])
			# A colour that is only the costume's is lit while the look wears it as its Default.
			var entry: Dictionary = LookCatalog.palette(name_of)[found.index]
			var owned := unlocks.is_unlocked(name_of, entry["id"], entry["gate"])
			found.locked = not owned and not (found.worn and look.default_costume(unlocks) >= 0)


## The costume on the character is the worn one; the Default option shows its colours and is off
## when there is none.
func _sync_costume_cells() -> void:
	var worn := Costumes.of_look(look)
	for found: WardrobeCell in _cells.get(COSTUME_KEY, []):
		found.worn = found.index == worn
	for found: WardrobeCell in _cells.get(DEFAULT_KEY, []):
		found.off_reason = "" if worn >= 0 else NO_COSTUME_NOTE
		found.swatches = _costume_swatches(Costumes.look(maxi(worn, 0)))
		found.worn = worn >= 0 and Costumes.has_default_colours(look, worn)


func _refresh_preview() -> void:
	look_changed.emit(look)
	if _preview == null:
		return
	_preview.show_look(look, 0)
	var colour := LookCatalog.armband_colour(0)
	_armband_note.text = "Armband: seat 1, always this colour"
	_armband_note.add_theme_color_override(&"font_color", colour)


func _refresh_status() -> void:
	if is_dirty():
		_status.text = "Saved when you leave this tab" if _embedded else "Not saved yet"
	else:
		_status.text = "Saved: this is how the others see you"


func _on_cell_chosen(item: WardrobeCell, key: String) -> void:
	if _building:
		return
	if key == COSTUME_KEY:
		wear_costume(item.index)
	elif key == DEFAULT_KEY:
		use_default_colours()
	elif key.begins_with(PART_PREFIX):
		if item.slot == LookCatalog.BODY_SLOT:
			choose_body(item.id)
		else:
			look.parts[item.slot] = item.id
			_after_pick(key)
	else:
		look.colours[item.slot] = item.index
		_repair_colours()
		_after_pick(key)
	_hint.text = item.detail()


## A colour the player has changed leaves the rest of a costume's Default colours to the palette
## they own: a locked one is put back at once, so what the turntable shows is what is saved.
func _repair_colours() -> void:
	var fixed := look.without_locked(unlocks)
	if fixed.colours == look.colours:
		return
	look.colours = fixed.colours
	for channel in LookCatalog.colour_slots():
		_sync_cells(COLOUR_PREFIX + channel)


func _after_pick(key: String) -> void:
	_sync_cells(key)
	_sync_costume_cells()
	_refresh_preview()
	_refresh_status()


func _on_cell_refused(item: WardrobeCell) -> void:
	_hint.text = item.detail()


## The pointer or the focus on a cell reads it on the detail line; leaving it reads whatever else
## holds the focus, or the rest line.
func _on_cell_shown(on: bool, item: WardrobeCell) -> void:
	if on:
		_hint.text = item.detail()
		return
	var holder: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if holder is WardrobeCell and holder != item:
		_hint.text = (holder as WardrobeCell).detail()
	else:
		_hint.text = REST_HINT


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
