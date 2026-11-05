class_name MenuScale
extends RefCounted
## The menu's size rules for small screens. The project stretches a 1920 x 1080 design to any
## window; on a phone held sideways (shorter side under `PHONE_SHORT_SIDE` px) that makes one unit
## 0.36 px at 844 x 390 and the type unreadable. The phone factor doubles the units' size, so the
## design is 540 high there: one unit 0.72 px, a caption of 22 units 15.8 px, a body of 26 units
## 18.7 px, a tap target of 64 units 46 px (the written minimums are 14, 18 and 44).

const PHONE_SHORT_SIDE := 500
const PHONE_FACTOR := 2.0
## The design size the project stretches from.
const DESIGN := Vector2(1920.0, 1080.0)
## The least size of anything pressed on a touch screen, in CSS pixels, which is what a finger
## meets (the written minimum). On a phone's page one CSS pixel is the page's pixel ratio (2, capped
## by `PhoneRender`) pixels of the window: 844 x 390 CSS px is a 1688 x 780 window. The menu's
## `MenuLook.TAP_TARGET` is the same size: 62 units at the menu's phone factor (0.36 CSS px a unit
## at the interface size, so 0.72 at the factor) is 44.8 CSS px. A night runs at the interface size
## alone: 44 CSS px are 122 units there.
const TAP_PIXELS := 44.0
## The least size of the words a finger-held screen shows, in CSS pixels (the written floor).
const TEXT_PIXELS := 14.0
## The most of the screen's height words are (a window too small to read anything).
const TEXT_SHARE_MAX := 0.06
## The most of the screen's height a tap target is (a window too small to press anything).
const TAP_SHARE_MAX := 0.2
## What the page's pixel ratio is for the tap size: a test says its own (negative: the device's).
static var pixel_ratio := -1.0


static func is_phone(window_size: Vector2i) -> bool:
	return mini(window_size.x, window_size.y) < PHONE_SHORT_SIDE


## The `content_scale_factor` for a window: the player's UI scale, times the phone factor.
static func factor(window_size: Vector2i, ui_scale: float) -> float:
	return ui_scale * (PHONE_FACTOR if is_phone(window_size) else 1.0)


## Real pixels in one design unit at this window and factor (the base stretch, `expand` aspect).
static func pixels_per_unit(window_size: Vector2i, scale_factor: float) -> float:
	var base := minf(float(window_size.x) / DESIGN.x, float(window_size.y) / DESIGN.y)
	return base * scale_factor


## The least height and width of a control the player presses, in the units of `window` at its
## `content_scale_factor` now: `TAP_PIXELS` CSS pixels. Zero when no finger is meant to press it
## (`touch`: `TouchMode.wanted`), so a desktop's controls keep their own size. It does not ask
## whether the window is small: a phone's page is 1688 x 780 in window pixels.
static func tap_units(window: Window, touch: bool) -> float:
	if not touch:
		return 0.0
	var ratio := pixel_ratio if pixel_ratio > 0.0 else MouseMotion.device_pixel_ratio()
	var per_unit := pixels_per_unit(window.size, window.content_scale_factor)
	# Never more than a fifth of the screen's height: a window too small for a finger (a headless
	# test's 64 x 64) would otherwise ask for a button taller than the screen.
	var canvas_height := float(window.size.y) / per_unit
	return minf(
		ceilf(TAP_PIXELS * maxf(ratio, 1.0) / per_unit), floorf(canvas_height * TAP_SHARE_MAX)
	)


## The size, in the units of `window` at its `content_scale_factor` now, of words that must read at
## `TEXT_PIXELS` CSS pixels: `desktop_units` when no finger holds the screen (`touch`:
## `TouchMode.wanted`: a desktop's scale is never changed), else that size or the one the floor
## asks for, whichever is more. A night's unit is 0.36 CSS px on a phone's page, so 14 CSS px are
## 39 units there and the HUD's 20 are 7.
static func text_units(window: Window, touch: bool, desktop_units: int) -> int:
	if not touch:
		return desktop_units
	var ratio := pixel_ratio if pixel_ratio > 0.0 else MouseMotion.device_pixel_ratio()
	var per_unit := pixels_per_unit(window.size, window.content_scale_factor)
	var canvas_height := float(window.size.y) / per_unit
	var wanted := ceili(TEXT_PIXELS * maxf(ratio, 1.0) / per_unit)
	return maxi(desktop_units, mini(wanted, floori(canvas_height * TEXT_SHARE_MAX)))
