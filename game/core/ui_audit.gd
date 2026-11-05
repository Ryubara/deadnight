class_name UiAudit
extends RefCounted
## What a person would measure on a screen with a ruler, in CSS pixels (#1197): the smallest text
## and the smallest thing a finger presses. The written minimums are 14 px of text and 44 px for a
## target (`MenuLook`). The numbers are read where the player sees them: the node's rectangle and
## font size times the window's stretch and the page's CSS pixels per window pixel.
##
## The web probe publishes the result when the page asks (`window.deadnight_audit`), and the
## phone test (`test_phone_floor.gd`) reads the same numbers for every menu screen.

const MIN_TEXT_PX := 14.0
const MIN_TAP_PX := 44.0
## How many names of what is under a floor `summary` lists. None: a page that asked for the
## audit printed "Invalid unicode codepoint" errors when the summary carried the names (control
## text) through the JavaScript bridge; the numbers go and the names stay in the tests.
const MAX_NAMES := 0

var tap_min := INF
var tap_small := PackedStringArray()
var text_min := INF
var text_small := PackedStringArray()
## CSS pixels in one canvas unit.
var per_unit := 1.0


## Measures the visible controls under `root`. `css_per_pixel` is `PageSize.css_per_pixel`.
static func scan(root: Node, css_per_pixel := 1.0) -> UiAudit:
	var audit := UiAudit.new()
	var view := root.get_viewport() if root.is_inside_tree() else null
	if view == null:
		return audit
	audit.per_unit = view.get_final_transform().get_scale().x * css_per_pixel
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		audit._read(control)
	return audit


## One line: the smallest text and target, how many are under the floors, and `MAX_NAMES` names.
func summary() -> String:
	return (
		"text %s px [%d] (%s) tap %s px [%d] (%s)"
		% [
			_number(text_min),
			text_small.size(),
			_first(text_small),
			_number(tap_min),
			tap_small.size(),
			_first(tap_small)
		]
	)


func _read(control: Control) -> void:
	var text := _text_of(control)
	if text != "":
		var px := float(control.get_theme_font_size(&"font_size")) * per_unit
		if px > 0.0:
			text_min = minf(text_min, px)
			if px < MIN_TEXT_PX - 0.05:
				text_small.append("%s:%.1f" % [_name(control), px])
	if _is_target(control):
		var tall := control.size.y * per_unit
		tap_min = minf(tap_min, tall)
		if tall < MIN_TAP_PX - 0.05:
			tap_small.append("%s:%.1f" % [_name(control), tall])


func _is_target(control: Control) -> bool:
	if control is BaseButton:
		return (
			not (control as BaseButton).disabled
			and control.mouse_filter != Control.MOUSE_FILTER_IGNORE
		)
	return control is LineEdit or control is Slider


func _text_of(control: Control) -> String:
	if control is Label:
		return (control as Label).text
	if control is Button:
		return (control as Button).text
	if control is LineEdit:
		return (
			(control as LineEdit).text
			if (control as LineEdit).text != ""
			else (control as LineEdit).placeholder_text
		)
	return ""


func _name(control: Control) -> String:
	var shown := _text_of(control)
	return String(control.name) if shown == "" else shown.left(18)


func _first(names: PackedStringArray) -> String:
	return ",".join(names.slice(0, MAX_NAMES))


func _number(value: float) -> String:
	return "-" if is_inf(value) else "%.1f" % value
