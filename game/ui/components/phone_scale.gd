class_name PhoneScale
extends Control
## A part of the night laid out at the menu's phone factor while the rest is not (#1205).
## A night runs on the interface size alone: its HUD and touch layer are made for 1080 units, and
## the factor 2 would put half the buttons off the top (#606, #1192). The pause card and the
## Settings opened from it are menu screens in the night, and at 0.36 CSS pixels to the unit their
## text is 12 px and a button 28 px.
##
## This control sits over the whole screen and is as big as the screen over the factor, drawn at
## the factor: its children lay out on the 1169 x 540 canvas a menu has on a phone and a unit is
## 0.72 CSS pixels. The window's own factor never changes, so nothing else in the night moves. On
## a screen that is not a phone's the factor is 1 and this is a plain full-size control.
##
## It takes no mouse itself: a press goes to the child under the finger, as it would in the menu.

## The factor now: the menu's phone factor on a phone's screen, 1 on any other.
var factor := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	get_window().size_changed.connect(fit)
	var holder := get_parent_control()
	if holder != null:
		holder.resized.connect(fit)
	fit()


## Whether a window is a phone's, so the part is drawn at the phone factor.
static func factor_for(window: Window) -> float:
	return MenuScale.PHONE_FACTOR if MenuScale.is_phone(window.size) else 1.0


## Takes the factor and the size the screen asks for now: the holder's size over the factor.
func fit() -> void:
	var holder := get_parent_control()
	if holder == null or not is_inside_tree():
		return
	factor = factor_for(get_window())
	scale = Vector2(factor, factor)
	position = Vector2.ZERO
	size = holder.size / factor
