class_name MatchSettingsPanel
extends VBoxContainer
## The match settings as form rows: how intense the night is (zombies per round and how fast they
## come), how many at once and how long the breaks are. Built from gds_ui controls (`UIRow`,
## `UIOptionSelector`, `UISlider`) and bound to nothing: it holds a `MatchSettings`, says `changed`
## when a control moves and hands the result out with `settings()`.
##
## The Play screen uses it for a night on this machine. The room host's lobby (#391) puts the same
## panel on its screen, reads `settings()` and hands it to the server with
## `NightHost.configure_match`; a guest's lobby calls `set_settings` with what the WELCOME carried
## and `set_editable(false)`.

## A control moved: the settings as they now stand.
signal changed(settings: MatchSettings)

const ALIVE_STEP := 1
const BREAK_MAX := 30

var count_row: UIRow
var alive_row: UIRow
var break_row: UIRow
var count_selector: UIOptionSelector
var alive_slider: UISlider
var break_slider: UISlider

## The tuned break, shown on the break slider while the setting follows it.
var _standard_break: float
var _alive_ceiling: int
var _break_set := false


## "Auto" for no cap, else the number.
static func alive_text(max_alive: int) -> String:
	return "Auto" if max_alive <= MatchSettings.AUTO else str(max_alive)


func _init() -> void:
	var tuning := (load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).rounds
	_standard_break = tuning.break_seconds
	# The host's own platform: a browser host offers the browser's crowd, a desktop host the desktop's.
	_alive_ceiling = tuning.ceiling_for(OS.has_feature("web"))
	var tokens := UITokens.active()
	add_theme_constant_override(&"separation", tokens.space_md)
	count_row = _row("Zombie intensity", "More of the dead, and faster.")
	count_selector = UIOptionSelector.new()
	var labels := PackedStringArray()
	for choice in MatchSettings.COUNT_CHOICES:
		labels.append("%dx" % roundi(choice))
	count_selector.options = labels
	count_selector.selected_changed.connect(_on_changed.unbind(1))
	count_row.set_control(count_selector)
	alive_row = _row("Most alive at once", "Auto follows the round.")
	alive_slider = _slider(0, _alive_ceiling, ALIVE_STEP)
	alive_row.set_control(alive_slider)
	break_row = _row("Break between rounds", "Time to spend points and get ready.")
	break_slider = _slider(int(MatchSettings.MIN_BREAK), BREAK_MAX, 1)
	break_row.set_control(break_slider)
	set_settings(MatchSettings.new())


## The settings the controls show.
func settings() -> MatchSettings:
	var out := MatchSettings.new()
	out.count_multiplier = MatchSettings.COUNT_CHOICES[count_selector.selected]
	out.max_alive = roundi(alive_slider.value)
	out.break_seconds = break_slider.value if _break_set else 0.0
	return out.clamped()


## Shows `value` without saying `changed`. A count that is not one of the choices shows the nearest.
func set_settings(value: MatchSettings) -> void:
	var held := value.clamped()
	count_selector.select(_nearest_choice(held.count_multiplier), false)
	alive_slider.set_value_no_signal(held.max_alive)
	_break_set = held.break_seconds > 0.0
	break_slider.set_value_no_signal(held.break_seconds if _break_set else _standard_break)
	_show_values()


## A guest sees the host's settings and cannot move them.
func set_editable(on: bool) -> void:
	alive_slider.editable = on
	break_slider.editable = on
	count_selector.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	count_selector.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


## The first control, for the screen's initial focus.
func first_control() -> Control:
	return count_selector


## The last control, to link the focus to what follows the panel.
func last_control() -> Control:
	return break_slider


func _row(title: String, hint: String) -> UIRow:
	var row := UIRow.new()
	row.title = title
	row.hint = hint
	add_child(row)
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
