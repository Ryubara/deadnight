class_name TouchSlop
extends RefCounted
## How far a finger may slip while it presses a button inside a scrolling card, before the touch is
## a scroll (#1257); a drag that starts anywhere else on the card scrolls at once. A finger that
## lands on a button and drifts a few pixels is still pressing it; a finger that travels further is
## scrolling the card, and the button gives its press up.
##
## The distance is `CSS_PIXELS` of the page, the size the person holds, so it is the same
## movement of the finger on every scale: 10 CSS pixels are 14 units on a phone's menu (0.72 CSS
## px a unit), 28 on a phone's night, 10 on a desktop at the design size. `UIScroll.slip_units`
## asks for it at each press, so a resized window and a changed interface size are followed.

## Android scrolls after 8 dp, iOS after 10 pt, Chromium counts a touch that moved less than 15 CSS
## pixels as a click: 10 is the middle, and it is a quarter of the 44 CSS pixels of a button.
const CSS_PIXELS := 10.0
## The most it is ever, in units: a window too small to press anything (a test's 64 x 64) would
## otherwise ask for a slip wider than the screen.
const MAX_UNITS := 64.0


## The slip of `window`, in its units now.
static func units(window: Window) -> float:
	return units_for(window.size, window.content_scale_factor)


## The slip of a window of this size at this `content_scale_factor`.
static func units_for(window_size: Vector2i, scale_factor: float) -> float:
	var per_unit := MenuScale.css_per_unit(window_size, scale_factor)
	if per_unit <= 0.0:
		return 0.0
	return minf(CSS_PIXELS / per_unit, MAX_UNITS)
