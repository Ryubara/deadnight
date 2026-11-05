class_name MatchSettingsPanel
extends VBoxContainer
## The match settings as form rows: which map the night is on (`MapPicker`), the night modifiers
## (how intense it is, zombies per round and how fast they come, and how many perks a player may
## carry), how many zombies at once, how long the breaks are and how many bots join the night.
## Built from gds_ui controls (`UIRow`, `UIOptionSelector`, `UISlider`) and bound to nothing: it
## holds a `MatchSettings`, says `changed` when a control moves and hands the result out with
## `settings()`.
##
## The Play screen (Solo) and the room host's lobby (#391) use this one panel, so solo and rooms
## offer the same settings from one definition. Each setting of `MatchSettings.KEYS` has a row in
## `rows` (`setting_keys()`, `row_for()`) and `missing_keys()` names any that lack one; a test fails
## on a setting added to `MatchSettings` without a row, so it cannot reach rooms and miss solo. The
## lobby reads `settings()` and hands it to the server with `NightHost.configure_match`; a guest's
## lobby calls `set_settings` with what the WELCOME carried and `set_editable(false)`.
##
## Each control is named by its setting's key (`count_multiplier`, `perk_limit`, `max_alive`,
## `break_seconds`, `bots`, `bot_skill`; a map card by its map's id), which the web probe publishes
## as `focus`: a browser smoke walks the keyboard to a control by that name, never by counting key
## presses (#743).

## A control moved: the settings as they now stand.
signal changed(settings: MatchSettings)

const ALIVE_STEP := 1
## The line under the Bots row's title: the count and the skill share the row.
const BOTS_HINT := "Teammates, and how well they play."
## The line under the night modifiers' title: the zombie intensity and the perk limit share the row.
const MODIFIERS_HINT := "More of the dead, and how many perks."
## The line under each row's title (a phone leaves them out).
const HINTS := {
	"map": "Where the night is held.",
	"count_multiplier": MODIFIERS_HINT,
	"perk_limit": MODIFIERS_HINT,
	"max_alive": "Auto follows the round.",
	"break_seconds": "Time to spend points and get ready.",
	"bots": BOTS_HINT,
	"bot_skill": BOTS_HINT,
}
## The skills' names on the selector, in `MatchSettings.SKILL_*` order.
const SKILL_LABELS: Array[String] = ["Rookie", "Regular", "Veteran"]
const BREAK_MAX := 30

## The row of each setting, by its key in `MatchSettings.KEYS`, in the order they are shown.
var rows := {}
var map_row: UIRow
var count_row: UIRow
var alive_row: UIRow
var break_row: UIRow
var map_picker: MapPicker
var bots_row: UIRow
var count_selector: UIOptionSelector
var perk_selector: UIOptionSelector
var bots_selector: UIOptionSelector
var skill_selector: UIOptionSelector
var alive_slider: UISlider
var break_slider: UISlider

## The tuned break, shown on the break slider while the setting follows it.
var _standard_break: float
var _alive_ceiling: int
var _break_set := false


## "Auto" for no cap, else the number.
static func alive_text(max_alive: int) -> String:
	return "Auto" if max_alive <= MatchSettings.AUTO else str(max_alive)


## The settings as a browser test reads them, `2x|Auto|20 s`: the intensity, the cap and the break
## in seconds (`break_shown`, which a setting left on the tuned break does not hold), then `|3 bots`
## when there are bots (none is the usual night and says nothing), then `|rookie` or `|veteran`
## when the bots are not the regular ones, and `|unlimited perks` when the perk limit is lifted.
static func text_for(value: MatchSettings, break_shown: float) -> String:
	var text := (
		"%dx|%s|%d s"
		% [roundi(value.count_multiplier), alive_text(value.max_alive), roundi(break_shown)]
	)
	if value.bots > 0:
		text += "|%d bots" % value.bots
		if value.bot_skill != MatchSettings.DEFAULT_SKILL:
			text += "|" + SKILL_LABELS[value.bot_skill].to_lower()
	if value.perk_limit == MatchSettings.PERKS_UNLIMITED:
		text += "|unlimited perks"
	return text


func _init() -> void:
	var tuning := (load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).rounds
	_standard_break = tuning.break_seconds
	# The host's own platform: a browser host offers the browser's crowd, a desktop host the desktop's.
	_alive_ceiling = tuning.ceiling_for(OS.has_feature("web"))
	var tokens := UITokens.active()
	add_theme_constant_override(&"separation", tokens.space_md)
	map_row = _row("map", "Map")
	map_picker = MapPicker.new()
	map_picker.chosen.connect(_on_changed.unbind(1))
	map_row.set_control(map_picker)
	count_row = _row("count_multiplier", "Night modifiers")
	count_selector = UIOptionSelector.new()
	count_selector.name = &"count_multiplier"
	var labels := PackedStringArray()
	for choice in MatchSettings.COUNT_CHOICES:
		labels.append("%dx" % roundi(choice))
	count_selector.options = labels
	count_selector.selected_changed.connect(_on_changed.unbind(1))
	# The perk limit sits beside the intensity in the same row: both change the night itself, and a
	# sixth row would not fit a phone held sideways or a 720p window (`test_play_screen.gd`).
	perk_selector = UIOptionSelector.new()
	perk_selector.name = &"perk_limit"
	perk_selector.options = PackedStringArray(MatchSettings.PERK_LIMIT_LABELS)
	perk_selector.selected_changed.connect(_on_changed.unbind(1))
	count_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	perk_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var modifiers := HBoxContainer.new()
	modifiers.add_theme_constant_override(&"separation", UITokens.active().space_sm)
	count_row.set_control(modifiers)
	modifiers.add_child(count_selector)
	modifiers.add_child(perk_selector)
	# `perk_limit` is a key of the settings: its row is the intensity's row.
	rows["perk_limit"] = count_row
	alive_row = _row("max_alive", "Most alive at once")
	alive_slider = _slider(0, _alive_ceiling, ALIVE_STEP)
	alive_slider.name = &"max_alive"
	alive_row.set_control(alive_slider)
	# Left and right change a selector's value, so the two are linked up and down; the slider below
	# is reached from the perk selector, the one nearer to it.
	count_selector.focus_neighbor_bottom = count_selector.get_path_to(perk_selector)
	perk_selector.focus_neighbor_top = perk_selector.get_path_to(count_selector)
	perk_selector.focus_neighbor_bottom = perk_selector.get_path_to(alive_slider)
	alive_slider.focus_neighbor_top = alive_slider.get_path_to(perk_selector)
	break_row = _row("break_seconds", "Break between rounds")
	break_slider = _slider(int(MatchSettings.MIN_BREAK), BREAK_MAX, 1)
	break_slider.name = &"break_seconds"
	break_row.set_control(break_slider)
	bots_row = _row("bots", "Bots")
	bots_selector = UIOptionSelector.new()
	bots_selector.name = &"bots"
	var bot_labels := PackedStringArray()
	for count in range(MatchSettings.MIN_BOTS, MatchSettings.MAX_BOTS + 1):
		bot_labels.append(str(count))
	bots_selector.options = bot_labels
	bots_selector.selected_changed.connect(_on_changed.unbind(1))
	# The skill sits beside the count in the same row: a sixth row would not fit a phone held
	# sideways or a 720p window (`test_play_screen.gd`), and the two settings belong together.
	skill_selector = UIOptionSelector.new()
	skill_selector.name = &"bot_skill"
	skill_selector.options = PackedStringArray(SKILL_LABELS)
	skill_selector.selected_changed.connect(_on_changed.unbind(1))
	skill_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bots_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bots_pair := HBoxContainer.new()
	bots_pair.add_theme_constant_override(&"separation", UITokens.active().space_sm)
	bots_row.set_control(bots_pair)
	bots_pair.add_child(bots_selector)
	bots_pair.add_child(skill_selector)
	# Left and right change a selector's value, so the two are linked up and down.
	bots_selector.focus_neighbor_bottom = bots_selector.get_path_to(skill_selector)
	skill_selector.focus_neighbor_top = skill_selector.get_path_to(bots_selector)
	# `bot_skill` is a key of the settings: its row is the Bots row.
	rows["bot_skill"] = bots_row
	set_settings(MatchSettings.new())


## What the controls show, as `text_for` writes it.
func text() -> String:
	return text_for(settings(), break_slider.value)


## The settings the controls show.
func settings() -> MatchSettings:
	var out := MatchSettings.new()
	out.map = map_picker.selected_id
	out.count_multiplier = MatchSettings.COUNT_CHOICES[count_selector.selected]
	out.max_alive = roundi(alive_slider.value)
	out.break_seconds = break_slider.value if _break_set else 0.0
	out.perk_limit = perk_selector.selected
	out.bots = bots_selector.selected
	out.bot_skill = skill_selector.selected
	return out.clamped()


## Shows `value` without saying `changed`. A count that is not one of the choices shows the nearest.
func set_settings(value: MatchSettings) -> void:
	var held := value.clamped()
	map_picker.set_selected(held.map)
	count_selector.select(_nearest_choice(held.count_multiplier), false)
	perk_selector.select(held.perk_limit, false)
	bots_selector.select(held.bots, false)
	skill_selector.select(held.bot_skill, false)
	alive_slider.set_value_no_signal(held.max_alive)
	_break_set = held.break_seconds > 0.0
	break_slider.set_value_no_signal(held.break_seconds if _break_set else _standard_break)
	_show_values()


## A guest sees the host's settings and cannot move them.
func set_editable(on: bool) -> void:
	map_picker.set_editable(on)
	alive_slider.editable = on
	break_slider.editable = on
	count_selector.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	count_selector.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	perk_selector.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	perk_selector.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	bots_selector.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	bots_selector.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	skill_selector.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	skill_selector.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


## The keys of the settings the panel shows, in the order of its rows.
func setting_keys() -> Array:
	return rows.keys()


## The row of the setting `key` (a key of `MatchSettings.KEYS`), or null.
func row_for(key: String) -> UIRow:
	return rows.get(key)


## The settings `MatchSettings` has that the panel shows no row for (none, or a setting was added
## without its row).
func missing_keys() -> Array:
	return MatchSettings.KEYS.keys().filter(func(key: String) -> bool: return not rows.has(key))


## The phone's form: every row a tap target high (`MenuLook.TAP_TARGET`) and the hints left out,
## which gives the canvas of a phone held sideways (540 units) its room. `false` is the desktop's.
## Every row title shows whole, never "Break between ro...": the titles' column grows to the longest
## (#1227), and the gaps in a row are a step smaller, so the widest row (the break between rounds)
## still fits the narrowest phone's card of 848 units (#1250).
func set_compact(on: bool) -> void:
	for key: String in rows:
		var row := rows[key] as UIRow
		row.show_whole_title(on)
		row.set_tight(on)
		row.custom_minimum_size.y = MenuLook.TAP_TARGET if on else 0.0
		row.hint = "" if on else HINTS[key]
	map_picker.set_compact(on)
	TapFloor.fit(self, on)
	# A phone's canvas is 540 units high: the rows sit close together (a row is a tap target high
	# either way).
	var tokens := UITokens.active()
	add_theme_constant_override(&"separation", tokens.space_xs if on else tokens.space_md)


## The controls Up leaves the panel from: the first row of map cards.
func first_controls() -> Array[Control]:
	return map_picker.top_row()


## The last control, to link the focus to what follows the panel.
func last_control() -> Control:
	return skill_selector


func _row(key: String, title: String) -> UIRow:
	var row := UIRow.new()
	row.title = title
	row.hint = HINTS[key]
	add_child(row)
	rows[key] = row
	return row


func _slider(low: int, high: int, step: int) -> UISlider:
	var slider := UISlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value_changed.connect(_on_slider.bind(slider))
	return slider


func _on_slider(_value: float, slider: UISlider) -> void:
	_break_set = _break_set or slider == break_slider
	_on_changed()


func _on_changed() -> void:
	_show_values()
	changed.emit(settings())


func _show_values() -> void:
	alive_row.set_value_text(alive_text(roundi(alive_slider.value)))
	break_row.set_value_text("%d s" % roundi(break_slider.value))


static func _nearest_choice(multiplier: float) -> int:
	var best := 0
	for i in MatchSettings.COUNT_CHOICES.size():
		var choice := MatchSettings.COUNT_CHOICES[i]
		if absf(choice - multiplier) < absf(MatchSettings.COUNT_CHOICES[best] - multiplier):
			best = i
	return best
