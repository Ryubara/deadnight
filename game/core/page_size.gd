class_name PageSize
extends RefCounted
## What the player holds, in CSS pixels (#1197). A web page's window is its canvas in device
## pixels: an 844 x 390 phone page reports a pixel ratio of 2 (`PhoneRender.PIXEL_RATIO_CAP`) and
## the canvas is 1688 x 780, so a test on the window's own size takes a phone for a laptop. The
## page's size in CSS pixels is what the person sees and what a fingertip is measured against.
##
## Native builds have no CSS pixel: the window is the page.

## The canvas's box in CSS pixels, as `width,height`: the element the engine draws into, or the
## page's inner size when there is none (an embedding that renames the canvas).
const SCRIPT := (
	"(function(){var c=document.getElementById('canvas');"
	+ "var r=c?c.getBoundingClientRect():null;"
	+ "var w=(r&&r.width>0)?r.width:window.innerWidth;"
	+ "var h=(r&&r.height>0)?r.height:window.innerHeight;"
	+ "return w+','+h})()"
)

## Tests and captures set this to stand in for the page's size (a `Vector2` of CSS pixels).
static var css_override: Variant = null


## The page's size in CSS pixels. `window_size` is the window's own size, the answer off the web.
static func css(window_size: Vector2i) -> Vector2:
	if css_override != null:
		return css_override
	if OS.has_feature("web"):
		var answer: Variant = JavaScriptBridge.eval(SCRIPT, true)
		if answer is String:
			var parts := (answer as String).split(",")
			if parts.size() == 2 and float(parts[0]) > 0.0 and float(parts[1]) > 0.0:
				return Vector2(float(parts[0]), float(parts[1]))
	return Vector2(window_size)


## CSS pixels in one window pixel (0.5 on a phone page of ratio 2; 1 off the web).
static func css_per_pixel(window_size: Vector2i) -> float:
	if window_size.x <= 0:
		return 1.0
	return css(window_size).x / float(window_size.x)


## The shorter side of the page, in CSS pixels.
static func short_side(window_size: Vector2i) -> float:
	var page := css(window_size)
	return minf(page.x, page.y)
