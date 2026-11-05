class_name MenuScale
extends RefCounted
## The menu's size rules for small screens. The project stretches a 1920 x 1080 design to any
## window; on a phone held sideways (shorter side under `PHONE_SHORT_SIDE`) that makes one unit
## 0.36 px at 844 x 390 and the type unreadable. The phone factor doubles the units' size, so the
## design is 540 high there: one unit 0.72 px, a caption of 22 units 15.8 px, a body of 26 units
## 18.7 px, a tap target of 64 units 46 px (the written minimums are 14, 18 and 44).
##
## "Px" there is a CSS pixel, what the person holds. A web page's window is its canvas in device
## pixels (a pixel ratio of up to 2, `PhoneRender`): an 844 x 390 phone page is a 1688 x 780
## window, and the factor gives the same 1169 x 540 canvas as a 844 x 390 window would (#1197).

const PHONE_SHORT_SIDE := 500
const PHONE_FACTOR := 2.0
## The design size the project stretches from.
const DESIGN := Vector2(1920.0, 1080.0)


## Whether the menu is laid out as a phone's. Two cases, either is enough:
## - the window's own short side is under `PHONE_SHORT_SIDE` (a native window, a small desktop
##   browser window at a pixel ratio of 1: what the test always was);
## - the device is a touch screen (`TouchMode.detect`: a coarse pointer, or an Android or iOS
##   build) and the page's short side in CSS pixels is under it (`PageSize`): a phone page whose
##   canvas is two times its CSS size. A desktop browser window at a higher pixel ratio, a tablet
##   (short side 744 CSS px and up) and a desktop build keep the layout they had.
static func is_phone(window_size: Vector2i) -> bool:
	if mini(window_size.x, window_size.y) < PHONE_SHORT_SIDE:
		return true
	return TouchMode.detect() and PageSize.short_side(window_size) < PHONE_SHORT_SIDE


## The `content_scale_factor` for a window: the player's UI scale, times the phone factor.
static func factor(window_size: Vector2i, ui_scale: float) -> float:
	return ui_scale * (PHONE_FACTOR if is_phone(window_size) else 1.0)


## Real pixels in one design unit at this window and factor (the base stretch, `expand` aspect).
static func pixels_per_unit(window_size: Vector2i, scale_factor: float) -> float:
	var base := minf(float(window_size.x) / DESIGN.x, float(window_size.y) / DESIGN.y)
	return base * scale_factor


## CSS pixels in one design unit: what a person with a ruler measures. It differs from
## `pixels_per_unit` on a web page, whose canvas has more pixels than the page has CSS pixels.
static func css_per_unit(window_size: Vector2i, scale_factor: float) -> float:
	return pixels_per_unit(window_size, scale_factor) * PageSize.css_per_pixel(window_size)


## One line saying which scale a window runs at: the page, the canvas, the factor, the canvas in
## units and the unit in CSS pixels. A capture prints it, so nobody reads a layout at a scale it
## never had (#1197).
static func describe(window_size: Vector2i, scale_factor: float) -> String:
	var units := Vector2(window_size) / maxf(pixels_per_unit(window_size, scale_factor), 0.0001)
	var page := PageSize.css(window_size)
	return (
		"page %dx%d css, canvas %dx%d, factor %s -> %dx%d units, %.2f css px per unit%s"
		% [
			roundi(page.x),
			roundi(page.y),
			window_size.x,
			window_size.y,
			scale_factor,
			roundi(units.x),
			roundi(units.y),
			css_per_unit(window_size, scale_factor),
			" (phone)" if is_phone(window_size) else ""
		]
	)
