class_name CustomizeScreen
extends UIScreen
## The wardrobe: a lit turntable with the character on it, a picker for each part and colour, the
## eight presets, Randomize and Save.
##
## The screen edits a working copy of the look; Save writes it (`LookStore`) and Back leaves
## without saving. Every change shows on the turntable at once. Locked options are drawn greyed
## and say how to get them; nothing here changes how a night plays.
##
## Route to it with `UIRouter.push("res://ui/screens/customize_screen.tscn")`. Tests and captures
## drive it through `apply_preset`, `randomize`, `choose`, `save` and the strips themselves.

const PANEL_WIDTH := 1500
const PICKER_WIDTH := 900
## The width of every picker strip: sixteen compact swatches.
const STRIP_WIDTH := 540
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
var _preset_selector: UIOptionSelector
var _preview: LookPreview
var _hint: UILabel
var _status: UILabel
var _armband_note: UILabel
var _save_button: UIButton
var _building := false


func _ready() -> void:
	super._ready()
	if params.has("seed"):
		_rng.seed = int(params["seed"])
	else:
		_rng.randomize()
	if params.has("unlocks"):
		unlocks = params["unlocks"]
	saved = LookStore.load_look(unlocks)
	look = saved.duplicate_look()
	_build()
	_sync_all()
	initial_focus = _preset_selector.get_path()


## Puts the look of preset `index` on the character.
func apply_preset(index: int) -> void:
	look = CharacterLook.from_preset(index).without_locked(unlocks)
	_sync_all()


## Rolls a look from the options this player may wear.
func randomize() -> void:
	look = CharacterLook.randomized(_rng, unlocks)
	_sync_all()


## Picks entry `index` of the strip `key` ("part:<slot>" or "colour:<slot>"), as the cursor would.
func choose(key: String, index: int) -> void:
	(_strips[key] as ChoiceStrip).move_to(index)


## Writes the working look to the settings file.
func save() -> void:
	look = look.without_locked(unlocks)
	LookStore.save_look(look)
	saved = look.duplicate_look()
	_refresh_status()
	UIAudio.play(&"press")


func strip(key: String) -> ChoiceStrip:
	return _strips[key]


func preview() -> LookPreview:
	return _preview


func is_dirty() -> bool:
	return not look.equals(saved)


func _build() -> void:
	_building = true
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
	panel.custom_minimum_size.x = PICKER_WIDTH
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", _tokens.space_md)
	panel.add_child(rows)

	var preset_row := UIRow.new()
	preset_row.title = "Preset"
	preset_row.hint = "Eight ready-made looks."
	_preset_selector = UIOptionSelector.new()
	var names := PackedStringArray()
	for preset: Dictionary in LookCatalog.presets():
		names.append(preset["name"])
	names.append(CUSTOM_LABEL)
	_preset_selector.options = names
	_preset_selector.selected_changed.connect(_on_preset_selected)
	preset_row.set_control(_preset_selector)
	rows.add_child(preset_row)

	for slot in LookCatalog.choosable_part_slots():
		rows.add_child(_build_part_row(slot))
	for slot in LookCatalog.colour_slots():
		rows.add_child(_build_colour_row(slot))

	_hint = _label("", UILabel.Style.CAPTION)
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(_hint)
	return panel


func _build_part_row(slot: StringName) -> UIRow:
	var entries: Array[Dictionary] = []
	for option: Dictionary in LookCatalog.options(slot):
		(
			entries
			. append(
				{
					"label": option["label"],
					"locked": not unlocks.is_unlocked(slot, option["id"], option["gate"]),
					"hint": option["label"] + _gate_text(option["gate"], slot, option["id"]),
				}
			)
		)
	return _build_strip_row(PART_PREFIX + slot, LookCatalog.PART_TITLES[slot], entries)


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
	strip_control.custom_minimum_size.x = STRIP_WIDTH
	strip_control.chosen.connect(_on_chosen.bind(key))
	strip_control.blocked.connect(_on_blocked.bind(key))
	strip_control.cursor_moved.connect(_on_cursor_moved.bind(key))
	row.set_control(strip_control)
	_strips[key] = strip_control
	return row


func _build_footer() -> HBoxContainer:
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
	var back := UIButton.new()
	back.text = "Back"
	back.variant = UIButton.Variant.GHOST
	back.pressed.connect(func() -> void: UIRouter.pop())
	footer.add_child(back)
	_save_button = UIButton.new()
	_save_button.text = "Save"
	_save_button.pressed.connect(save)
	footer.add_child(_save_button)
	return footer


## Puts every control, the preview and the captions in step with `look`.
func _sync_all() -> void:
	_building = true
	for slot in LookCatalog.choosable_part_slots():
		(_strips[PART_PREFIX + slot] as ChoiceStrip).select(
			LookCatalog.option_index(slot, look.parts[slot])
		)
	for slot in LookCatalog.colour_slots():
		(_strips[COLOUR_PREFIX + slot] as ChoiceStrip).select(int(look.colours[slot]))
	_sync_preset_selector()
	_building = false
	_hint.text = ""
	_refresh_preview()
	_refresh_status()


func _sync_preset_selector() -> void:
	var index := LookCatalog.presets().size()
	for i in LookCatalog.presets().size():
		if CharacterLook.from_preset(i).equals(look):
			index = i
			break
	_preset_selector.select(index, false)


func _refresh_preview() -> void:
	_preview.show_look(look, 0)
	var colour := LookCatalog.armband_colour(0)
	_armband_note.text = "Armband: seat 1, always this colour"
	_armband_note.add_theme_color_override(&"font_color", colour)


func _refresh_status() -> void:
	if is_dirty():
		_status.text = "Not saved yet"
	else:
		_status.text = "Saved: this is how the others see you"


func _on_preset_selected(index: int) -> void:
	if index >= LookCatalog.presets().size():
		return
	apply_preset(index)


func _on_chosen(index: int, key: String) -> void:
	if _building:
		return
	if key.begins_with(PART_PREFIX):
		var slot := StringName(key.trim_prefix(PART_PREFIX))
		look.parts[slot] = LookCatalog.options(slot)[index]["id"]
	else:
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
