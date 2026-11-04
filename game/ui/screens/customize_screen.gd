class_name CustomizeScreen
extends UIScreen
## The wardrobe: a lit turntable with the character on it, the character (him or her, #678), a
## picker for each part and colour, the presets of that character, Randomize and Save.
##
## The screen edits a working copy of the look; Save writes it (`LookStore`) and Back leaves
## without saving. Every change shows on the turntable at once. Locked options are drawn greyed
## and say how to get them; nothing here changes how a night plays.
##
## With the param `embedded` it is only the pickers and the footer, without its own title,
## turntable, Back or Save: the main menu's Loadout tab hosts it, shows the look on its own stage
## and keeps the working look until the player leaves the tab (`commit`).
##
## Route to it with `UIRouter.push("res://ui/screens/customize_screen.tscn")`. Tests and captures
## drive it through `apply_preset`, `randomize`, `choose`, `choose_body`, `save` and the strips.

## Emitted when the working look changes, so a stage somewhere else can show it.
signal look_changed(look: CharacterLook)

const PANEL_WIDTH := 1500
const PICKER_WIDTH := 900
## The width of every picker strip: sixteen compact swatches.
const STRIP_WIDTH := 540
## The same in the main menu's Loadout tab, where the pickers have a column of their own.
const EMBEDDED_STRIP_WIDTH := 380
## Height of the scrolling list of pickers.
const SCROLL_HEIGHT := 640
## The keys of the strips: a prefix and the slot name.
const PART_PREFIX := "part:"
const COLOUR_PREFIX := "colour:"
const CUSTOM_LABEL := "Custom"

## What this player has unlocked. Replace before the screen is shown to try other gates.
var unlocks := LookUnlocks.new()
## The look being edited.
var look: CharacterLook
## The look on disk.
var saved: CharacterLook

var _rng := RandomNumberGenerator.new()
var _strips := {}
var _selectors := {}
var _preset_selector: UIOptionSelector
var _body_selector: UIOptionSelector
## The presets the preset row offers (indices into `LookCatalog.presets()`): the character's own.
var _preset_ids: Array[int] = []
var _preview: LookPreview
var _hint: UILabel
var _status: UILabel
var _armband_note: UILabel
var _save_button: UIButton
var _building := false
var _embedded := false


func _ready() -> void:
	super._ready()
	if params.has("seed"):
		_rng.seed = int(params["seed"])
	else:
		_rng.randomize()
	if params.has("unlocks"):
		unlocks = params["unlocks"]
	_embedded = params.get("embedded", false)
	saved = LookStore.load_look(unlocks)
	look = saved.duplicate_look()
	_build()
	_sync_all()
	initial_focus = _body_selector.get_path()


## Puts the look of preset `index` on the character.
func apply_preset(index: int) -> void:
	look = CharacterLook.from_preset(index).without_locked(unlocks)
	_sync_all()


## Rolls a look from the options this player may wear, for the character they chose.
func randomize() -> void:
	look = CharacterLook.randomized(_rng, unlocks, look.body())
	_sync_all()


## Makes the working look `body`'s (`CharacterLook.set_body`: a cut of the other character's
## becomes this one's own), as the Character row does.
func choose_body(body: StringName) -> void:
	look.set_body(body)
	_sync_all()


## Picks entry `index` of the picker `key` ("part:<slot>" or "colour:<slot>"), as the player would.
func choose(key: String, index: int) -> void:
	if key.begins_with(PART_PREFIX):
		(_selectors[StringName(key.trim_prefix(PART_PREFIX))] as UIOptionSelector).select(index)
	else:
		(_strips[key] as ChoiceStrip).move_to(index)


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


## The swatch strip of a colour channel, by key ("colour:<channel>").
func strip(key: String) -> ChoiceStrip:
	return _strips[key]


## The selector of a part slot.
func selector(slot: StringName) -> UIOptionSelector:
	return _selectors[slot]


## The Character row's selector (Male, Female).
func body_selector() -> UIOptionSelector:
	return _body_selector


## The Preset row's selector: the character's presets, then "Custom".
func preset_selector() -> UIOptionSelector:
	return _preset_selector


func preview() -> LookPreview:
	return _preview


func is_dirty() -> bool:
	return not look.equals(saved)


func _build() -> void:
	_building = true
	if _embedded:
		_build_embedded()
		_link_focus()
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
	_link_focus()
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
	initial_focus = _preset_selector.get_path()


## Up and down walk the pickers row by row, then on to the footer; left to the engine, the nearest
## control in that direction could be a footer button on the other side of the screen.
func _link_focus() -> void:
	var chain: Array[Control] = [_body_selector, _preset_selector]
	for slot in LookCatalog.choosable_part_slots():
		chain.append(_selectors[slot])
	for slot in LookCatalog.colour_slots():
		chain.append(_strips[COLOUR_PREFIX + slot])
	if _save_button != null:
		chain.append(_save_button)
	for i in chain.size() - 1:
		chain[i].focus_neighbor_bottom = chain[i].get_path_to(chain[i + 1])
		chain[i + 1].focus_neighbor_top = chain[i + 1].get_path_to(chain[i])


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
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override(&"separation", _tokens.space_sm)
	panel.add_child(holder)
	# Every part slot and colour channel is a row; there are more than fit, so the rows scroll and
	# the scroll follows the focus.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = SCROLL_HEIGHT
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", _tokens.space_md)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	var body_row := UIRow.new()
	body_row.title = LookCatalog.PART_TITLES[LookCatalog.BODY_SLOT]
	body_row.hint = "Every outfit fits both."
	_body_selector = UIOptionSelector.new()
	var bodies := PackedStringArray()
	for option: Dictionary in LookCatalog.options(LookCatalog.BODY_SLOT):
		bodies.append(option["label"])
	_body_selector.options = bodies
	_body_selector.selected_changed.connect(_on_body_selected)
	body_row.set_control(_body_selector)
	_selectors[LookCatalog.BODY_SLOT] = _body_selector
	rows.add_child(body_row)

	var preset_row := UIRow.new()
	preset_row.title = "Preset"
	preset_row.hint = "Ready-made looks."
	_preset_selector = UIOptionSelector.new()
	_preset_selector.selected_changed.connect(_on_preset_selected)
	preset_row.set_control(_preset_selector)
	rows.add_child(preset_row)

	for slot in LookCatalog.choosable_part_slots():
		rows.add_child(_build_part_row(slot))
	for slot in LookCatalog.colour_slots():
		rows.add_child(_build_colour_row(slot))

	_hint = _label("", UILabel.Style.CAPTION)
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	holder.add_child(_hint)
	return panel


func _build_part_row(slot: StringName) -> UIRow:
	var row := UIRow.new()
	row.title = LookCatalog.PART_TITLES[slot]
	var chooser := UIOptionSelector.new()
	chooser.selected_changed.connect(_on_part_selected.bind(slot))
	row.set_control(chooser)
	_selectors[slot] = chooser
	return row


## The names of a part row's options as the look's character calls them (her face choices differ).
func _part_names(slot: StringName) -> PackedStringArray:
	var names := PackedStringArray()
	var list := LookCatalog.options(slot)
	for i in list.size():
		var option: Dictionary = list[i]
		var locked := not unlocks.is_unlocked(slot, option["id"], option["gate"])
		names.append(LookCatalog.label(slot, i, look.body()) + (" (locked)" if locked else ""))
	return names


## The preset row's entries: this character's presets, then "Custom".
func _sync_preset_options() -> void:
	_preset_ids.clear()
	var names := PackedStringArray()
	var presets := LookCatalog.presets()
	for i in presets.size():
		if presets[i]["parts"].get(LookCatalog.BODY_SLOT, LookCatalog.MALE) == look.body():
			_preset_ids.append(i)
			names.append(presets[i]["name"])
	names.append(CUSTOM_LABEL)
	_preset_selector.options = names


func _build_colour_row(slot: StringName) -> UIRow:
	var entries: Array[Dictionary] = []
	for entry: Dictionary in LookCatalog.palette(slot):
		(
			entries
			. append(
				{
					"label": entry["label"],
					"colour": entry["colour"],
					"locked": not unlocks.is_unlocked(slot, entry["id"], entry["gate"]),
					"hint": entry["label"] + _gate_text(entry["gate"], slot, entry["id"]),
				}
			)
		)
	return _build_strip_row(COLOUR_PREFIX + slot, LookCatalog.COLOUR_TITLES[slot], entries)


func _build_strip_row(key: String, title: String, entries: Array[Dictionary]) -> UIRow:
	var row := UIRow.new()
	row.title = title
	var strip_control := ChoiceStrip.new()
	strip_control.entries = entries
	# Every strip is as wide as the longest palette, so all the rows line up.
	strip_control.custom_minimum_size.x = EMBEDDED_STRIP_WIDTH if _embedded else STRIP_WIDTH
	strip_control.chosen.connect(_on_chosen.bind(key))
	strip_control.blocked.connect(_on_blocked.bind(key))
	strip_control.cursor_moved.connect(_on_cursor_moved.bind(key))
	row.set_control(strip_control)
	_strips[key] = strip_control
	return row


func _build_footer(with_back := true) -> HBoxContainer:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", _tokens.space_md)
	var random_button := UIButton.new()
	random_button.text = "Randomize"
	random_button.variant = UIButton.Variant.SECONDARY
	random_button.pressed.connect(randomize)
	footer.add_child(random_button)
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


## Puts every control, the preview and the captions in step with `look`.
func _sync_all() -> void:
	_building = true
	_body_selector.select(LookCatalog.option_index(LookCatalog.BODY_SLOT, look.body()), false)
	_sync_preset_options()
	for slot in LookCatalog.choosable_part_slots():
		(_selectors[slot] as UIOptionSelector).options = _part_names(slot)
		(_selectors[slot] as UIOptionSelector).select(
			LookCatalog.option_index(slot, look.parts[slot]), false
		)
	for slot in LookCatalog.colour_slots():
		(_strips[COLOUR_PREFIX + slot] as ChoiceStrip).select(int(look.colours[slot]))
	_sync_preset_selector()
	_building = false
	_hint.text = ""
	_refresh_preview()
	_refresh_status()


func _sync_preset_selector() -> void:
	var index := _preset_ids.size()
	for i in _preset_ids.size():
		if CharacterLook.from_preset(_preset_ids[i]).equals(look):
			index = i
			break
	_preset_selector.select(index, false)


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


func _on_preset_selected(index: int) -> void:
	if index >= _preset_ids.size():
		return
	apply_preset(_preset_ids[index])


func _on_body_selected(index: int) -> void:
	if _building:
		return
	var option: Dictionary = LookCatalog.options(LookCatalog.BODY_SLOT)[index]
	choose_body(option["id"])
	_hint.text = option["label"]


func _on_part_selected(index: int, slot: StringName) -> void:
	if _building:
		return
	var option: Dictionary = LookCatalog.options(slot)[index]
	if not unlocks.is_unlocked(slot, option["id"], option["gate"]):
		# Looked at, not worn: back to the part the look has, and say how to get this one.
		(_selectors[slot] as UIOptionSelector).select(
			LookCatalog.option_index(slot, look.parts[slot]), false
		)
		_hint.text = (
			"Locked: %s%s" % [option["label"], _gate_text(option["gate"], slot, option["id"])]
		)
		UIMotion.shake(_selectors[slot])
		return
	look.parts[slot] = option["id"]
	_sync_preset_selector()
	_refresh_preview()
	_refresh_status()
	_hint.text = LookCatalog.label(slot, index, look.body())


func _on_chosen(index: int, key: String) -> void:
	if _building:
		return
	look.colours[StringName(key.trim_prefix(COLOUR_PREFIX))] = index
	_sync_preset_selector()
	_refresh_preview()
	_refresh_status()
	_hint.text = (strip(key).entries[index]["hint"] as String)


func _on_blocked(index: int, key: String) -> void:
	_hint.text = "Locked: " + (strip(key).entries[index]["hint"] as String)


func _on_cursor_moved(index: int, key: String) -> void:
	var entry: Dictionary = strip(key).entries[index]
	if not entry.get("locked", false):
		_hint.text = entry["hint"]


## " - Reach Billing level 10" for a gated option, or "" for a free one.
func _gate_text(gate: Dictionary, slot: StringName, id: StringName) -> String:
	if unlocks.is_unlocked(slot, id, gate):
		return ""
	return " - " + LookUnlocks.describe(gate)


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
