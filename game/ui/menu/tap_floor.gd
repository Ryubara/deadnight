class_name TapFloor
extends RefCounted
## The least size of what a finger presses on a phone (#1197). The kit's controls (sliders,
## toggles, selectors, text fields) are `control_height` units high, 52: 37.6 CSS pixels at the
## phone factor, under the 44 a fingertip needs. On a phone's canvas each is raised to
## `MenuLook.TAP_TARGET` (62 units, 44.8 CSS pixels) and goes back on a larger one.

## A canvas this high or lower is a phone's (a phone held sideways is 540 units).
const PHONE_CANVAS_HEIGHT := 600.0
const _BASE := &"tap_floor_base"


## Whether a screen of this canvas size is a phone's.
static func phone_canvas(canvas: Vector2) -> bool:
	return canvas.y <= PHONE_CANVAS_HEIGHT


## Raises every pressable control under `root` to a tap target high when `on`; puts the height it
## had back when not.
static func fit(root: Node, on: bool) -> void:
	var controls := root.find_children("*", "Control", true, false)
	controls.push_front(root)
	for node in controls:
		var control := node as Control
		if control == null or not _is_target(control):
			continue
		if not control.has_meta(_BASE):
			control.set_meta(_BASE, control.custom_minimum_size.y)
		var base := float(control.get_meta(_BASE))
		control.custom_minimum_size.y = maxf(base, MenuLook.TAP_TARGET) if on else base


static func _is_target(control: Control) -> bool:
	return (
		control is UISlider
		or control is UIToggle
		or control is UICheckBox
		or control is UIOptionSelector
		or control is LineEdit
	)
