class_name ControllerHint
extends Control
## "Click the game once to use a controller": a line at the bottom of every screen while the game
## runs in a frame that has no focus (a Discord Activity before its first click). A browser lists
## no gamepad to such a frame, so a controller does nothing until one click gives it the focus
## (#479). Reads the page every half second (`GamepadProbe.hint`); off the web it never shows.

## The canvas layer it once sat on (104); it now shares the router's (#883).
const LAYER := 104
const EVERY := 0.5

var label: UILabel
var _since := EVERY


func _ready() -> void:
	name = "ControllerHint"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Under a CanvasLayer a Control has no parent rect to anchor to: it takes the viewport's size.
	get_viewport().size_changed.connect(_fit)
	_fit()
	label = UILabel.new()
	label.style = UILabel.Style.BODY
	label.text = GamepadProbe.HINT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The strip along the bottom edge: full width, 28 pixels high, 12 above the edge.
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = -40.0
	label.offset_bottom = -12.0
	add_child(label)
	show_for({})


func _process(delta: float) -> void:
	_since += delta
	if _since < EVERY:
		return
	_since = 0.0
	show_for(GamepadProbe.read())


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


## Shows the hint for a page report (the probe's, or `{}` for none).
func show_for(report: Dictionary) -> void:
	label.visible = GamepadProbe.hint(report) != ""
