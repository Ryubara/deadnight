class_name MouseMotion
extends RefCounted
## What a mouse motion means for the look: screen pixels of the hand, the same at every window size.
##
## `InputEventMouseMotion.relative` is in the viewport's units, so the project's `canvas_items`
## stretch scales it by `1920 / window width` (a 1280 pixel window turned the view 1.5 times as far
## per pixel as a 1920 one, #928). `screen_relative` is the unscaled motion, and that is what turns
## the view.
##
## On the web the runtime reports a pointer move in device pixels (the browser's `movementX` times
## `devicePixelRatio`), so on a screen with a ratio of 2 the same hand would turn the view twice as
## far. The look divides the ratio out, so a page feels the same on every screen, as it did while
## the stretch happened to cancel the ratio.


## The motion in mouse pixels. `pixel_ratio` is the screen's device pixel ratio on the web and 1
## elsewhere. The touch layer's own motion (`TouchLook.DEVICE`) is in mouse pixels already.
static func pixels(event: InputEventMouseMotion, pixel_ratio := device_pixel_ratio()) -> Vector2:
	if event.device == TouchLook.DEVICE:
		return event.screen_relative
	return event.screen_relative / maxf(pixel_ratio, 1.0)


## The browser's `devicePixelRatio` on the web, 1 on every other platform.
static func device_pixel_ratio() -> float:
	if not OS.has_feature("web"):
		return 1.0
	return DisplayServer.screen_get_scale()
